-- Auto-Label: automatically name lockers based on items deposited manually.
-- When a player manually transfers an item into a container with a blank label,
-- the label is set to the item's display name. Subsequent unique items append
-- comma-separated until auto_label_max is reached.

local UEHelpers = require("UEHelpers")
local utils = require("utils")
local network = require("network")
local config = nil
local autolabel = {}

autolabel.suppress = false  -- set by main.lua during automated operations
autolabel.debug = false     -- timing instrumentation; set false / remove before release

--- Get the open container's InventoryComponent, its InventoryId, and the owning actor.
--- Returns invComp, invId, ownerActor or nil, nil, nil.
local function getOpenContainerInfo()
    local tabs = FindAllOf("WBP_TabInventory_C")
    if not tabs then return nil, nil, nil end
    for _, tab in ipairs(tabs) do
        if tab:IsValid() then
            local ok, active = pcall(function() return tab:IsActivated() end)
            if ok and active then
                local ok2, vm = pcall(function() return tab.ViewModel end)
                if ok2 and vm and vm:IsValid() then
                    local ok3, otherInv = pcall(function() return vm.OtherInventory end)
                    if ok3 and otherInv and otherInv:IsValid() then
                        local ok4, invComp = pcall(function() return otherInv.InventoryComponent end)
                        if ok4 and invComp and invComp:IsValid() then
                            local okId, invId = pcall(function() return invComp.InventoryId end)
                            local okOwner, owner = pcall(function() return invComp:GetOwner() end)
                            if okId and okOwner and owner and owner:IsValid() then
                                return invComp, invId, owner
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

--- Parse a label string into a list of trimmed names.
local function parseNames(label)
    local names = {}
    if not label or label == "" then return names end
    for name in label:gmatch("[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(names, trimmed)
        end
    end
    return names
end

function autolabel.init(cfg)
    config = cfg

    -- Cache: one getOpenContainerInfo() scan per container, not per hook fire.
    -- The hook's `self` is the component that PROCESSES the add (often the player's
    -- inventory component) -- NOT the destination locker -- so the locker can only be
    -- resolved by matching inventoryId against the open container. Cache invalidates when
    -- a different inventoryId is seen (player opens a different container).
    local cache = { invId = nil, owner = nil, names = nil, rawLabel = nil }

    -- Cache player inventory ID to skip hook fires for player inventory (item pulls)
    local playerInvId = nil

    local _alFires, _alMisses, _alMissTime = 0, 0, 0  -- [DIAG]

    RegisterHook("/Script/UWEInventory.UWEInventoryComponent:OnItemAddedToInventory", function(self, inventoryId, inventoryItem)
        _alFires = _alFires + 1  -- [DIAG]
        if _alFires % 100 == 0 then  -- [DIAG]
            utils.diag(string.format("[DIAG] autolabel fires=%d misses=%d refreshTime=%.0fms", _alFires, _alMisses, _alMissTime * 1000))
        end
        if autolabel.suppress then return end

        local t0 = autolabel.debug and os.clock() or 0

        -- Get the hook's destination inventory ID (cheap)
        local hookInvId = nil
        pcall(function() hookInvId = inventoryId:get() end)
        if not hookInvId then return end

        -- Cache and skip player inventory (covers pulling items out of lockers)
        if not playerInvId then
            pcall(function()
                local pawn = utils.GetPlayerPawn()
                if pawn then
                    playerInvId = pawn.InventoryComponent.InventoryId
                end
            end)
        end
        if hookInvId == playerInvId then return end

        -- Scan only when the target inventory changes (once per container). The refresh
        -- runs HERE -- before any disabled bail -- so a stale-0 auto_label_max (e.g. the
        -- first-boot SN2ModSettings default) self-heals instead of permanently bailing.
        if hookInvId ~= cache.invId then
            _alMisses = _alMisses + 1  -- [DIAG]
            local _mt = os.clock()  -- [DIAG]
            config.refreshOne("auto_label_max")
            _alMissTime = _alMissTime + (os.clock() - _mt)  -- [DIAG]
            if (config.AutoLabelMax or 0) <= 0 then
                cache = { invId = hookInvId, owner = nil, names = nil, rawLabel = nil }
                if autolabel.debug then
                    print(string.format("[QS-AL] disabled invId=%s dt=%.2fms\n", tostring(hookInvId), (os.clock() - t0) * 1000))
                end
                return
            end
            local ts = autolabel.debug and os.clock() or 0
            local _, openInvId, owner = getOpenContainerInfo()
            if autolabel.debug then
                print(string.format("[QS-AL] scan invId=%s open=%s match=%s scanDt=%.2fms\n",
                    tostring(hookInvId), tostring(openInvId), tostring(openInvId == hookInvId), (os.clock() - ts) * 1000))
            end
            if openInvId == hookInvId and owner then
                local currentLabel = utils.getLockerLabel(owner) or ""
                cache = { invId = hookInvId, owner = owner, names = parseNames(currentLabel), rawLabel = currentLabel }
                if autolabel.debug then
                    print(string.format("[QS-AL] seed invId=%s label=%q seededN=%d\n",
                        tostring(hookInvId), currentLabel, #cache.names))
                end
            else
                cache = { invId = hookInvId, owner = nil, names = nil, rawLabel = nil }
                return
            end
        end

        if (config.AutoLabelMax or 0) <= 0 then return end
        if not cache.owner then return end

        local maxLabels = config.AutoLabelMax or 0

        -- Already full: cheapest possible repeat-fire bail -- no item read, no label re-read.
        -- The client fires this hook many times per transfer while inventory state reconciles
        -- with the server, so everything past this point must stay cheap.
        if #cache.names >= maxLabels then
            if autolabel.debug then
                print(string.format("[QS-AL] full invId=%s n=%d max=%d dt=%.2fms\n", tostring(hookInvId), #cache.names, maxLabels, (os.clock() - t0) * 1000))
            end
            return
        end

        -- Read the item's display name (needed for dedup)
        local itemStruct = nil
        pcall(function() itemStruct = inventoryItem:get() end)
        if not itemStruct then return end

        local info = utils.readItemInfo(itemStruct)
        if not info then return end
        local newName = info.displayName

        -- Dedup against the names we've already ensured. We trust our own grown set, NOT a
        -- re-read of the locker label: on clients the label lags behind until the host's SET
        -- replicates back, so re-reading would wipe our set and re-send a SETLABEL on EVERY
        -- hook fire (the ~85x/transfer client stutter that this whole module was choking on).
        for _, existing in ipairs(cache.names) do
            if existing == newName then
                if autolabel.debug then
                    print(string.format("[QS-AL] dup invId=%s name=%s n=%d max=%d dt=%.2fms\n", tostring(hookInvId), newName, #cache.names, maxLabels, (os.clock() - t0) * 1000))
                end
                return
            end
        end

        -- Genuinely new name. Merge in any names the player typed manually (grow-only, never
        -- shrink) so we don't clobber a manual edit, then re-check max/dedup before committing.
        local realNames = parseNames(utils.getLockerLabel(cache.owner) or "")
        for _, rn in ipairs(realNames) do
            local known = false
            for _, e in ipairs(cache.names) do if e == rn then known = true break end end
            if not known then table.insert(cache.names, rn) end
        end
        if #cache.names >= maxLabels then return end
        for _, existing in ipairs(cache.names) do
            if existing == newName then return end
        end

        -- Get UGCComponent from the owning actor
        local okUgc, ugc = pcall(function() return cache.owner.UGCComponent end)
        if not okUgc or not ugc then return end
        local okValid, valid = pcall(function() return ugc:IsValid() end)
        if not okValid or not valid then return end

        -- Build new label
        table.insert(cache.names, newName)
        local newLabel = table.concat(cache.names, ", ")

        -- Set label: host calls directly, clients delegate via network
        if network.isHost() then
            local key = { TagName = FName("None") }
            pcall(function() ugc:ServerSetPlayerText(key, newLabel) end)
        else
            network.sendToHost("SETLABEL", tostring(cache.invId) .. "|" .. newLabel)
        end
        cache.rawLabel = newLabel

        if autolabel.debug then
            print(string.format("[QS-AL] SET invId=%s name=%s n=%d max=%d host=%s dt=%.2fms\n",
                tostring(hookInvId), newName, #cache.names, maxLabels, tostring(network.isHost()), (os.clock() - t0) * 1000))
        end
    end)
end

return autolabel
