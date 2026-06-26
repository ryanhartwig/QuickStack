--- QuickStack: Infinite Range (global pull) module.
--- Operates on the UWEInventorySubsystem by inventory ID so quickstack can deposit into
--- every base locker map-wide, escaping the ~235m actor-streaming ceiling. Far lockers
--- have no loaded actor, but their inventories are reachable by ID at any distance.
---
--- Feasibility proven in-game 2026-06-13: full cold scan ~2-3ms; IsChildOf(SN2Locker)
--- gate excludes loot crates / vehicles / player inventories; item move verified at 5486m.
--- Spec: docs/superpowers/specs/2026-06-13-quickstack-infinite-range-design.md (sn2-modding repo)

local utils      = require("utils")
local matching   = require("matching")
local network    = require("network")
local categories = require("categories")
local labelcache = require("labelcache")

local globalpull = {}
local config = nil

local DEFAULT_MAX_ITEMS = 30
local CHEST_CLASS = "BP_Tailing_Chest_C"

-- Explicit loot/special-container denylist. The class gate below excludes these because
-- they don't subclass SN2Locker (verified in-game 2026-06-13), but this is cheap insurance
-- against a future game patch making a loot crate derive from SN2Locker. Fail-safe by name.
local LOOT_DENY = {
    BP_WorldSupplyLocker_C = true,
    BP_WorldSupplyLocker_Blighted_C = true,
}

-- Cached refs (revalidated on use)
local _ss = nil
local _lockerClass = nil

-- Label source is the labelcache module (host capture; later disk + client sync). Routing is
-- fail-closed: only lockers whose label is KNOWN (present in the cache) are candidates.

function globalpull.init(cfg)
    config = cfg
end

-- Lua-only reset; safe inside the map-load teardown hook (no UObject access).
RegisterLoadMapPostHook(function()
    _ss = nil
    _lockerClass = nil
end)

local function getSubsystem()
    if _ss then
        local ok, valid = pcall(function() return _ss:IsValid() end)
        if ok and valid then return _ss end
    end
    _ss = FindFirstOf("UWEInventorySubsystem")
    if _ss and _ss:IsValid() then return _ss end
    _ss = nil
    return nil
end

local function getLockerClass()
    if _lockerClass then
        local ok, valid = pcall(function() return _lockerClass:IsValid() end)
        if ok and valid then return _lockerClass end
    end
    _lockerClass = StaticFindObject("/Script/Subnautica2.SN2Locker")
    if _lockerClass and _lockerClass:IsValid() then return _lockerClass end
    _lockerClass = nil
    return nil
end

-- NOTE: global scans no longer sweep 1..HighestInventoryId. They iterate labelcache.knownIds()
-- (the lockers we've captured) — the fail-closed candidate domain, and far cheaper than probing
-- every id via the subsystem. This also sidesteps the client HighestInventoryId=0 problem (the
-- counter doesn't replicate to clients), since the cache is populated from loaded actors, not
-- the server counter. (HighestInventoryId=0 on client verified in-game 2026-06-21.)

--- Host vs client. NOTE: network.isHost() (FindFirstOf UWESaveGame) is unreliable — it
--- returns true on clients too (UWESaveGame replicates). No longer used to gate global pull
--- (clients can run it directly: subsystem moves are server-authoritative). Kept for callers
--- that still want a best-effort check.
function globalpull.isHost()
    return network.isHost()
end

--- Two-factor safety gate: inventory is valid, not the player's, and its actor class is
--- an SN2Locker subclass OR the tailing chest (minus the loot denylist). Fail-closed
--- (nil/unknown class -> deny) at EVERY branch — the class check is the load-bearing guard:
--- player/equipment inventories are pawn components never registered as storage actors, and
--- loot/vehicle/beacon classes don't subclass SN2Locker. This is what keeps items out of
--- loot crates and other players' packs.
local function isDepositTarget(ss, id, playerInvId, lockerClass, cacheKnown)
    if id == playerInvId then return false end
    local ok, valid = pcall(function() return ss:IsInventoryValid(id) end)
    if not ok or not valid then return false end
    local cls = nil
    pcall(function() cls = ss:GetActorClassForInventory(id) end)
    if not cls or not cls:IsValid() then
        -- Class UNRESOLVABLE -> a far locker whose actor has never loaded this session. Verified
        -- 2026-06-25: after a cold/menu reload neither GetActorClassForInventory NOR the storage
        -- container's InventoryClass resolves for never-loaded lockers (only ~1/67 far ids did), so the
        -- class gate can't see them and persisted far routing silently dropped to 3 targets. But the
        -- labelcache ONLY ever captures SN2Locker actors (FindAllOf("SN2Locker") / the SN2Locker-filtered
        -- BeginPlay hook / a rename on a locker), so a cached id IS a known locker -> trust it. The
        -- server-authoritative MoveInventoryItem is the final backstop: a wrong/reused id just fails the
        -- move, never mis-deposits. cacheKnown is passed true only by knownIds-driven callers.
        return cacheKnown == true
    end
    local okN, name = pcall(function() return cls:GetFName():ToString() end)
    if okN and LOOT_DENY[name] then return false end  -- explicit loot exclusion
    local isLocker = false
    pcall(function() isLocker = cls:IsChildOf(lockerClass) end)
    if isLocker then return true end
    -- The tailing chest is accepted here for parity with the nearby path, but it can never reach
    -- this scan under infinite range: it isn't an SN2Locker subclass and stores its inventory on
    -- .UWEInventory, so the labelcache never captures it (and knownIds() drives every scan). Do NOT
    -- "fix" that by feeding chest ids straight to the subsystem -- GetActorClassForInventory ->
    -- GetFName faults on a chest inventory (uncatchable by pcall; crashed the game while probing,
    -- 2026-06-23). Chests stay nearby-only under infinite range, documented in the release notes.
    return okN and name == CHEST_CLASS
end

--- Apply QuickStack's prefix routing to a raw label (mirrors utils.discoverNearbyContainers).
--- Returns: "skip" (excluded/overflow -> not a stack target), or a routing label string,
--- or nil (no routing label -> type-count only).
local function parseRoutingLabel(rawLabel)
    if not rawLabel then return nil end
    if config.ExcludePrefix ~= "" and rawLabel:sub(1, #config.ExcludePrefix) == config.ExcludePrefix then
        return "skip"
    end
    if config.OverflowPrefix ~= "" and rawLabel:sub(1, #config.OverflowPrefix) == config.OverflowPrefix then
        return "skip"  -- overflow lockers aren't normal stack targets
    end
    if not config.LabelRouting then return nil end
    if config.LabelPrefix == "" then
        -- A blank/whitespace label is UNLABELED (nil), not an empty routing label. captureActor stores
        -- `getLockerLabel(actor) or ""` as the cache's known-blank marker, so without this a blank locker
        -- routed by type-count but the summary showed "" instead of "Unlabeled" (`"" or "Unlabeled"` ==
        -- "", since "" is truthy). Mirrors the nearby path (utils.discoverNearbyContainers).
        local t = rawLabel:match("^%s*(.-)%s*$")
        return t ~= "" and t or nil
    end
    local prefixLen = #config.LabelPrefix
    if rawLabel:sub(1, prefixLen) == config.LabelPrefix then
        local label = rawLabel:sub(prefixLen + 1):match("^%s*(.-)%s*$")
        if label == "" then return nil end
        return label
    end
    return nil
end

--- Subsystem move (server-authoritative, real bool). This is the ONLY move path for
--- global targets — intentionally no component-move fallback, because far targets have no
--- loaded component. Returns true only on a confirmed server-side move (accounting trusts it).
function globalpull.move(itemId, fromId, toId)
    local ss = getSubsystem()
    if not ss then return false end
    local ok, result = pcall(function() return ss:MoveInventoryItem(itemId, fromId, toId) end)
    return ok and result == true
end

--- Global stack: route transferable items to all gated lockers map-wide.
--- Mirrors transferToLockers' scoring (label match -> type-count fallback) but reads and
--- moves via the subsystem so it works at any distance. Returns the same tuple
--- (actualTransferred, numContainers, someFull, transferDetails) for reporting parity.
function globalpull.stack(playerInv, transferableItems, totalItemsBefore)
    local ss = getSubsystem()
    if not ss then return 0, 0, false, {} end
    local lockerClass = getLockerClass()
    if not lockerClass then return 0, 0, false, {} end

    local playerInvId = playerInv.InventoryId

    -- Enumerate gated targets and snapshot each (type-count + capacity + routing label).
    -- FAIL-CLOSED: candidates come ONLY from the labelcache (lockers whose label we KNOW:
    -- captured while loaded this session / synced / persisted). Iterating knownIds (not 1..8192)
    -- is also the per-press cost win — we never isDepositTarget an unknown id we'd just skip.
    local targetIds, typeData, itemCount, maxItems, labels = {}, {}, {}, {}, {}
    for _, id in ipairs(labelcache.knownIds()) do
        local entry = labelcache.get(id)
        if isDepositTarget(ss, id, playerInvId, lockerClass, true) then  -- knownIds => cache-known locker
            local routing = parseRoutingLabel(entry.label)
            if routing ~= "skip" then
                local idx = #targetIds + 1
                targetIds[idx] = id
                labels[idx] = routing  -- string or nil
                typeData[idx] = {}
                itemCount[idx] = 0
                maxItems[idx] = DEFAULT_MAX_ITEMS
                pcall(function()
                    local mx = ss:GetMaxItemsForInventory(id)
                    if mx and mx > 0 then maxItems[idx] = mx end
                    local items = ss:GetItemsForInventory(id)
                    itemCount[idx] = #items
                    for _, it in ipairs(items) do
                        local s = it:get()
                        if s.ItemType then
                            local tn = s.ItemType:GetFName():ToString()
                            typeData[idx][tn] = (typeData[idx][tn] or 0) + 1
                        end
                    end
                end)
            end
        end
    end

    if #targetIds == 0 then return 0, 0, false, {} end

    local containersUsed, someFull, transferDetails = {}, false, {}
    local movedCount = 0
    local movedIds = {}  -- itemIds confirmed-moved this pass; the overflow pass excludes them (client-lag-proof)
    for _, item in ipairs(transferableItems) do
        local bestLabelScore, bestLabelIdx = 0, nil
        local bestUnlabeledIdx, bestUnlabeledCount = nil, 0
        -- Tokenize the item name ONCE, not per labeled target (the target set is map-wide).
        local nameWords, totalChars = matching.tokenizeName(item.displayName)

        for i = 1, #targetIds do
            local full = itemCount[i] >= maxItems[i]
            local labelScore = 0
            if labels[i] then
                labelScore = matching.scoreWithTokens(labels[i], nameWords, totalChars)
            end
            -- Type-count only when the label didn't match (mirrors transferToLockers).
            local typeCount = (labelScore == 0) and (typeData[i][item.typeName] or 0) or 0
            if full then
                -- Only flag "some full" for a locker this item actually wanted (relevant),
                -- not for unrelated full lockers elsewhere on the map.
                if labelScore > 0 or typeCount > 0 then someFull = true end
            elseif labelScore > 0 then
                if labelScore > bestLabelScore then
                    bestLabelScore = labelScore
                    bestLabelIdx = i
                end
            elseif typeCount > 0 then
                if typeCount > bestUnlabeledCount then
                    bestUnlabeledCount = typeCount
                    bestUnlabeledIdx = i
                end
            end
        end

        local bestIdx = bestLabelIdx or bestUnlabeledIdx
        if bestIdx then
            local id = targetIds[bestIdx]
            if globalpull.move(item.itemId, item.inventoryId, id) then
                movedCount = movedCount + 1
                movedIds[item.itemId] = true
                containersUsed[bestIdx] = true
                -- Count a NEW slot only when the type wasn't already present (same-type
                -- moves usually merge into the existing stack — no new slot consumed).
                local hadType = (typeData[bestIdx][item.typeName] or 0) > 0
                typeData[bestIdx][item.typeName] = (typeData[bestIdx][item.typeName] or 0) + item.count
                if not hadType then itemCount[bestIdx] = itemCount[bestIdx] + 1 end
                utils.recordDetail(transferDetails, item.typeName, item.itemType, item.displayName,
                    labels[bestIdx] or "Unlabeled")
            end
        end
    end

    -- Count confirmed (server-authoritative) moves rather than the player-inventory delta:
    -- on a CLIENT the local inventory count lags replication, so the delta under-reports.
    -- Each globalpull.move returns the real server result, so movedCount is accurate everywhere.
    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end
    return movedCount, numContainers, someFull, transferDetails, movedIds
end

local function getPlayerInvId()
    local id = -1
    pcall(function()
        local pawn = utils.GetPlayerPawn()
        if pawn then id = pawn.InventoryComponent.InventoryId end
    end)
    return id
end

--- Build restock candidates (consumables) from ALL gated lockers map-wide, via the
--- subsystem. Same candidate shape as restock.buildCandidates so restock.execute can
--- consume it unchanged. Keyed inventoryId = the locker id (subsystem-stable).
function globalpull.buildRestockCandidates()
    local ss = getSubsystem()
    if not ss then return {} end
    local lockerClass = getLockerClass()
    if not lockerClass then return {} end
    local playerInvId = getPlayerInvId()

    local candidates = {}
    -- Known lockers only (labelcache). On the HOST this is the same set in practice (relevancy
    -- invariant: the host loads every locker any player is near). On a CLIENT the cache covers only
    -- loaded (~150m) lockers until label-sync Phase 4 syncs the host registry -- far lockers are
    -- skipped (fail-closed: a reach reduction, never a mis-route). Skips the 8192-id sweep either way.
    for _, id in ipairs(labelcache.knownIds()) do
        if isDepositTarget(ss, id, playerInvId, lockerClass, true) then  -- knownIds => cache-known locker
            pcall(function()
                for _, it in ipairs(ss:GetItemsForInventory(id)) do
                    local s = it:get()
                    local typeName = utils.readItemTypeName(s)
                    if typeName then
                        local category = categories.getConsumableCategory(typeName)
                        if category then
                            local displayName = nil
                            pcall(function() displayName = s.ItemType.Name:ToString() end)
                            candidates[#candidates + 1] = {
                                itemId = s.ItemId,
                                inventoryId = id,
                                typeName = typeName,
                                displayName = displayName or typeName:gsub("^DA_", ""):gsub("_ItemType$", ""),
                                itemType = s.ItemType,
                                category = category,
                                priority = categories.getPriority(typeName, category),
                            }
                        end
                    end
                end
            end)
        end
    end
    return candidates
end

--- Dump leftover items into %o-labeled overflow lockers map-wide, via the subsystem.
--- Returns (moved, containerCount, overflowDetails). Mirrors the local overflow pass.
function globalpull.overflowDump(playerInv, remainingItems)
    local ss = getSubsystem()
    if not ss then return 0, 0, {} end
    local lockerClass = getLockerClass()
    if not lockerClass then return 0, 0, {} end
    if config.OverflowPrefix == "" then return 0, 0, {} end

    local playerInvId = playerInv.InventoryId

    -- Enumerate %o-labeled gated lockers (overflow targets). Known lockers only (labelcache) —
    -- the %o check already required a cache entry, so this is the same set, minus the 8192 sweep.
    local ids, count, maxItems, labels = {}, {}, {}, {}
    for _, id in ipairs(labelcache.knownIds()) do
        if isDepositTarget(ss, id, playerInvId, lockerClass, true) then  -- knownIds => cache-known locker
            local entry = labelcache.get(id)
            local raw = entry and entry.label
            if raw and raw:sub(1, #config.OverflowPrefix) == config.OverflowPrefix then
                local idx = #ids + 1
                ids[idx] = id
                labels[idx] = raw
                count[idx] = 0
                maxItems[idx] = DEFAULT_MAX_ITEMS
                pcall(function()
                    local mx = ss:GetMaxItemsForInventory(id)
                    if mx and mx > 0 then maxItems[idx] = mx end
                    count[idx] = #ss:GetItemsForInventory(id)
                end)
            end
        end
    end
    if #ids == 0 then return 0, 0, {} end

    -- Stable order by label, like the local overflow pass.
    -- (ids/labels are parallel; sort an index permutation.)
    local order = {}
    for i = 1, #ids do order[i] = i end
    table.sort(order, function(a, b) return (labels[a] or "") < (labels[b] or "") end)

    local used, details, moved = {}, {}, 0
    for _, item in ipairs(remainingItems) do
        for _, i in ipairs(order) do
            if count[i] < maxItems[i] then
                if globalpull.move(item.itemId, item.inventoryId, ids[i]) then
                    used[i] = true
                    count[i] = count[i] + 1
                    moved = moved + 1
                    utils.recordDetail(details, item.typeName, item.itemType, item.displayName,
                        labels[i] or "Overflow")
                    break
                end
            end
        end
    end

    local n = 0
    for _ in pairs(used) do n = n + 1 end
    return moved, n, details
end

return globalpull
