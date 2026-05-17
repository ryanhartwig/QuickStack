-- QuickStack Mod for Subnautica 2
-- N: Quick Stack to nearby containers (matching items only)
-- G: Quick Stack into currently open container (matching items only)
-- Supports locker labels for routing items to specific containers

local UEHelpers = require("UEHelpers")

local config = require("config")
local utils = require("utils")

local VERSION = "2.0.0"
print(string.format("[QuickStack] v%s loaded\n", VERSION))

-- Map config keybind string to UE4SS Key constant
local keyMap = {
    A = Key.A, B = Key.B, C = Key.C, D = Key.D, E = Key.E,
    F = Key.F, G = Key.G, H = Key.H, I = Key.I, J = Key.J,
    K = Key.K, L = Key.L, M = Key.M, N = Key.N, O = Key.O,
    P = Key.P, Q = Key.Q, R = Key.R, S = Key.S, T = Key.T,
    U = Key.U, V = Key.V, W = Key.W, X = Key.X, Y = Key.Y,
    Z = Key.Z,
    F1 = Key.F1, F2 = Key.F2, F3 = Key.F3, F4 = Key.F4,
    F5 = Key.F5, F6 = Key.F6, F7 = Key.F7, F8 = Key.F8,
}

local bindKey = keyMap[config.Keybind]
if not bindKey then
    print(string.format("[QuickStack] ERROR: Unknown keybind '%s', defaulting to N\n", config.Keybind))
    bindKey = Key.N
end

-- Cooldown state
local lastActivation = 0

--- Check if an item should be kept in the player's inventory
---@param typeName string The item's FName (e.g. "DA_Titanium_ItemType")
---@param fullName string The item type's full UE path
---@return boolean True if item should NOT be transferred
local function shouldKeepItem(typeName, fullName)
    local lname = string.lower(fullName)

    -- Keep tools (Scanner, Multitool, etc.)
    if config.KeepTools then
        if string.find(lname, "/tools/", 1, true) then return true end
    end

    -- Keep equipment (tanks, fins, rebreather, etc.)
    if config.KeepEquipment then
        if string.find(lname, "/equipment/", 1, true) then return true end
        if string.find(lname, "/equippable/", 1, true) then return true end
        if string.find(lname, "/deployables/", 1, true) then return true end
    end

    -- Keep explicitly listed types
    for _, keepType in ipairs(config.KeepTypes) do
        if typeName == keepType then return true end
    end

    return false
end

--- Read the user-set label from a locker's UGCComponent
---@param actor userdata The locker actor
---@return string|nil The label text, or nil if no label
local function getLockerLabel(actor)
    local ok, ugc = pcall(function() return actor.UGCComponent end)
    if not ok or not ugc then return nil end
    local ok1b, valid = pcall(function() return ugc:IsValid() end)
    if not ok1b or not valid then return nil end

    -- Check if it has any user-generated content at all
    local ok2, hasUGC = pcall(function() return ugc:HasUserGeneratedContent() end)
    if not ok2 or not hasUGC then return nil end

    -- Read PlayerTexts array directly (safer than calling GetPlayerText with unknown tags)
    local ok3, texts = pcall(function() return ugc.PlayerTexts end)
    if not ok3 or not texts then return nil end

    local ok4, len = pcall(function() return #texts end)
    if not ok4 or not len or len == 0 then return nil end

    for i = 1, len do
        local str = nil
        pcall(function()
            local entry = texts[i]
            if entry then
                local val = entry.Value
                if val then
                    -- Try multiple ways to unwrap FString
                    local s = nil
                    local ok_ts, ts = pcall(function() return val:ToString() end)
                    if ok_ts and ts and type(ts) == "string" then
                        s = ts
                    end
                    if not s then
                        local ok_get, g = pcall(function() return val:get() end)
                        if ok_get and g and type(g) == "string" then
                            s = g
                        end
                    end
                    if not s then
                        local raw = tostring(val)
                        -- Filter out pointer strings like "FString: 0x..."
                        if raw and not raw:match("^FString:") and raw ~= "" and raw ~= "nil" then
                            s = raw
                        end
                    end
                    if s and s ~= "" then
                        str = s
                    end
                end
            end
        end)
        if str then
            print(string.format("[QuickStack] DEBUG: Locker label found: '%s'\n", str))
            return str
        end
    end

    return nil
end

--- Check if a locker label matches an item type name (fuzzy)
---@param label string The locker's label text
---@param typeName string The item's FName (e.g. "DA_Titanium_ItemType")
---@return boolean True if the label matches this item type
local function labelMatchesItem(label, typeName)
    local function normalize(s)
        return string.lower(s):gsub("[%s_]", "")
    end

    local cleanType = typeName:gsub("^DA_", ""):gsub("_ItemType$", "")
    local normType = normalize(cleanType)

    -- Split label by commas and check each part
    for part in label:gmatch("[^,]+") do
        local normPart = normalize(part)
        if normPart ~= "" then
            if string.find(normPart, normType, 1, true) then return true end
            if string.find(normType, normPart, 1, true) then return true end
        end
    end

    return false
end

--- Get the inventory component of the currently open container (if any)
local function getOpenContainerInventory()
    local tabs = FindAllOf("WBP_TabInventory_C")
    if not tabs then return nil end

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
                            return invComp
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- Build the list of player items, filtered by keep rules
---@param playerInv userdata Player's UWEInventoryComponent
---@return table Array of {typeName, fullName, itemId, inventoryId, itemType}
local function getTransferableItems(playerInv)
    local items = playerInv:GetItems()
    local transferable = {}

    for _, playerItem in ipairs(items) do
        local s = playerItem:get()
        if s.ItemType then
            local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok then
                local ok2, fullName = pcall(function() return s.ItemType:GetFullName() end)
                local fName = ok2 and fullName or ""

                if not shouldKeepItem(typeName, fName) then
                    table.insert(transferable, {
                        typeName = typeName,
                        fullName = fName,
                        itemId = s.ItemId,
                        inventoryId = s.InventoryId,
                        itemType = s.ItemType,
                        count = s.Count or 1,
                    })
                end
            end
        end
    end

    return transferable, #items
end

--- Transfer matching items from player inventory to nearby containers
--- Supports label-based routing and content-based matching
local function transferToLockers(playerInv, transferableItems, totalItemsBefore, nearbyLockers)
    -- Build locker data: contents, labels, capacity tracking
    local lockerTypeData = {}
    local lockerLabels = {}
    local lockerItemCount = {}
    local lockerMaxItems = {}

    for i, data in ipairs(nearbyLockers) do
        lockerTypeData[i] = {}
        lockerLabels[i] = data.label  -- may be nil
        lockerItemCount[i] = 0

        local ok0, maxItems = pcall(function() return data.inventory.MaxItems end)
        lockerMaxItems[i] = (ok0 and maxItems) or 30

        local ok, lockerItems = pcall(function() return data.inventory:GetItems() end)
        if ok and lockerItems then
            lockerItemCount[i] = #lockerItems
            for _, item in ipairs(lockerItems) do
                local s = item:get()
                if s.ItemType then
                    local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                    if ok2 then
                        lockerTypeData[i][typeName] = (lockerTypeData[i][typeName] or 0) + (s.Count or 1)
                    end
                end
            end
        end
    end

    local containersUsed = {}
    local someFull = false

    for _, item in ipairs(transferableItems) do
        local bestIdx = nil
        local bestCount = 0
        local bestIsLabel = false

        for i, data in ipairs(nearbyLockers) do
            -- Use our tracked count instead of IsFull() to avoid stale data
            if lockerItemCount[i] >= lockerMaxItems[i] then
                someFull = true
            else
                -- Priority 1: labeled locker that matches this item
                if lockerLabels[i] and labelMatchesItem(lockerLabels[i], item.typeName) then
                    if not bestIsLabel then
                        bestIdx = i
                        bestCount = 999999
                        bestIsLabel = true
                    end
                -- Priority 2: locker already containing this item type (only if no label match found)
                elseif not bestIsLabel then
                    local typeCount = lockerTypeData[i][item.typeName]
                    if typeCount and typeCount > 0 and typeCount > bestCount then
                        bestCount = typeCount
                        bestIdx = i
                    end
                end
            end
        end

        if bestIdx then
            local data = nearbyLockers[bestIdx]
            local ok3 = pcall(function()
                playerInv:MoveItemBetweenInventories(item.itemId, item.inventoryId, data.inventoryId)
            end)

            if ok3 then
                containersUsed[bestIdx] = true
                lockerTypeData[bestIdx][item.typeName] = (lockerTypeData[bestIdx][item.typeName] or 0) + item.count
                lockerItemCount[bestIdx] = lockerItemCount[bestIdx] + 1
            else
                local ok4 = pcall(function()
                    playerInv:MoveInventoryItem(data.inventory, item.itemId, playerInv)
                end)
                if ok4 then
                    containersUsed[bestIdx] = true
                    lockerTypeData[bestIdx][item.typeName] = (lockerTypeData[bestIdx][item.typeName] or 0) + item.count
                    lockerItemCount[bestIdx] = lockerItemCount[bestIdx] + 1
                end
            end
        end
    end

    -- Count actual transfers
    local afterItems = playerInv:GetItems()
    local actualTransferred = totalItemsBefore - #afterItems
    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end

    return actualTransferred, numContainers, someFull
end

--- Show the appropriate notification for a quick-stack result
local function showResultNotification(actualTransferred, numContainers, someFull, playerInv, totalItemsBefore)
    -- If we got 0 actual transfers but attempted some, the server may not have
    -- replicated yet (non-host clients). Delay and re-check.
    if actualTransferred <= 0 and numContainers > 0 then
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                local delayedItems = playerInv:GetItems()
                local delayedCount = totalItemsBefore - #delayedItems
                local itm = delayedCount == 1 and "item" or "items"
                local ctr = numContainers == 1 and "container" or "containers"

                if delayedCount <= 0 and someFull then
                    utils.Notify("No matching containers nearby (some full)", config)
                elseif delayedCount <= 0 then
                    utils.Notify("No matching containers nearby", config)
                elseif someFull then
                    utils.Notify(string.format("Quick Stacked %d %s to %d %s (some full)",
                        delayedCount, itm, numContainers, ctr), config)
                else
                    utils.Notify(string.format("Quick Stacked %d %s to %d %s",
                        delayedCount, itm, numContainers, ctr), config)
                end
            end)
        end)
    else
        local itm = actualTransferred == 1 and "item" or "items"
        local ctr = numContainers == 1 and "container" or "containers"

        if actualTransferred <= 0 and someFull then
            utils.Notify("No matching containers nearby (some full)", config)
        elseif actualTransferred <= 0 then
            utils.Notify("No matching containers nearby", config)
        elseif someFull then
            utils.Notify(string.format("Quick Stacked %d %s to %d %s (some full)",
                actualTransferred, itm, numContainers, ctr), config)
        else
            utils.Notify(string.format("Quick Stacked %d %s to %d %s",
                actualTransferred, itm, numContainers, ctr), config)
        end
    end
end

--- Quick Stack: transfer matching items to nearby containers
local function doQuickStack()
    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then
        utils.Notify("Error: Could not find player inventory", config)
        return
    end

    local transferableItems, totalItemsBefore = getTransferableItems(playerInv)
    if #transferableItems == 0 then
        utils.Notify("Nothing to stack", config)
        return
    end

    -- Whitelisted container classes
    local containerSources = {
        { class = "SN2Locker",          getInv = function(a) return a.Inventory end,          hasLabel = true },
        { class = "BP_Tailing_Chest_C", getInv = function(a) return a.InventoryComponent end, hasLabel = false },
    }

    local playerLoc = pawn:K2_GetActorLocation()
    local radiusUnits = utils.MetersToUnits(config.Radius)
    local nearbyLockers = {}

    for _, source in ipairs(containerSources) do
        local actors = FindAllOf(source.class)
        if actors then
            print(string.format("[QuickStack] DEBUG: Scanning %d %s actors\n", #actors, source.class))
            for j, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = utils.GetDistance(pawn, actor)
                    if dist <= radiusUnits then
                        local ok, inv = pcall(function() return source.getInv(actor) end)
                        if ok and inv and inv:IsValid() then
                            local label = nil
                            if source.hasLabel then
                                local rawLabel = getLockerLabel(actor)
                                if rawLabel then
                                    if config.LabelPrefix == "" then
                                        -- No prefix required, use label as-is
                                        label = rawLabel
                                    else
                                        -- Check if label starts with prefix, strip it
                                        local prefixLen = #config.LabelPrefix
                                        if rawLabel:sub(1, prefixLen) == config.LabelPrefix then
                                            label = rawLabel:sub(prefixLen + 1):match("^%s*(.-)%s*$")
                                            if label == "" then label = nil end
                                        end
                                        -- Labels without prefix are ignored
                                    end
                                end
                            end
                            table.insert(nearbyLockers, {
                                inventory = inv,
                                inventoryId = inv.InventoryId,
                                label = label,
                            })
                            print(string.format("[QuickStack] DEBUG: Added container #%d (label=%s)\n",
                                #nearbyLockers, tostring(label)))
                        end
                    end
                end
            end
        end
    end

    if #nearbyLockers == 0 then
        utils.Notify("No matching containers nearby", config)
        return
    end

    local actualTransferred, numContainers, someFull = transferToLockers(
        playerInv, transferableItems, totalItemsBefore, nearbyLockers)

    showResultNotification(actualTransferred, numContainers, someFull, playerInv, totalItemsBefore)
end

--- Quick Stack into the currently open container (matching items only)
local function doQuickStackOpen()
    local containerInv = getOpenContainerInventory()
    if not containerInv then
        utils.Notify("No container open", config)
        return
    end

    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then return end

    local transferableItems, totalItemsBefore = getTransferableItems(playerInv)
    if #transferableItems == 0 then
        utils.Notify("Nothing to stack", config)
        return
    end

    -- Build set of item types already in the container
    local containerTypes = {}
    local ok, containerItems = pcall(function() return containerInv:GetItems() end)
    if ok and containerItems then
        for _, item in ipairs(containerItems) do
            local s = item:get()
            if s.ItemType then
                local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                if ok2 then
                    containerTypes[typeName] = true
                end
            end
        end
    end

    local targetId = containerInv.InventoryId

    -- Transfer only matching items (respecting keep rules)
    for _, item in ipairs(transferableItems) do
        if containerTypes[item.typeName] then
            pcall(function()
                playerInv:MoveItemBetweenInventories(item.itemId, item.inventoryId, targetId)
            end)
        end
    end

    local afterItems = playerInv:GetItems()
    local actualTransferred = totalItemsBefore - #afterItems

    if actualTransferred <= 0 then
        utils.Notify("No matching items for this container", config)
    end
end

--- Check if the player is in a UI/menu (inventory open, label popup, etc.)
local function isInUI()
    -- Check label editing popup
    local popups = FindAllOf("WBP_ChangeLabelPopup_C")
    if popups then
        for _, popup in ipairs(popups) do
            if popup:IsValid() then
                local ok, active = pcall(function() return popup:IsActivated() end)
                if ok and active then return true end
            end
        end
    end
    return false
end

-- Keybind: N for Quick Stack (nearby containers)
RegisterKeyBind(bindKey, function()
    ExecuteInGameThread(function()
        -- Skip if player is in a menu (prevents firing while typing labels)
        if isInUI() then return end

        local now = os.clock()
        if now - lastActivation < config.Cooldown then
            return
        end
        lastActivation = now
        doQuickStack()
    end)
end)

-- Keybind: G for Quick Stack into open container
local bindKeyOpen = keyMap[config.KeybindOpen]
if not bindKeyOpen then
    print(string.format("[QuickStack] ERROR: Unknown keybind_open '%s', defaulting to G\n", config.KeybindOpen))
    bindKeyOpen = Key.G
end

RegisterKeyBind(bindKeyOpen, function()
    ExecuteInGameThread(function()
        if isInUI() then return end

        local now = os.clock()
        if now - lastActivation < config.Cooldown then
            return
        end
        lastActivation = now
        doQuickStackOpen()
    end)
end)
