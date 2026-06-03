local UEHelpers = require("UEHelpers")
local utils = {}

--- Calculate 3D distance between two actors
---@param actorA userdata Actor with K2_GetActorLocation
---@param actorB userdata Actor with K2_GetActorLocation
---@return number distance in Unreal units (1 unit = 1 cm, so 100 = 1 meter)
function utils.GetDistance(actorA, actorB)
    local locA = actorA:K2_GetActorLocation()
    local locB = actorB:K2_GetActorLocation()
    local dx = locA.X - locB.X
    local dy = locA.Y - locB.Y
    local dz = locA.Z - locB.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Get the player pawn (physical character in the world)
--- Uses IsLocalPlayerController() to find the correct controller on listen servers,
--- since UEHelpers:GetPlayerController() can return a remote client's controller.
--- Caches result after first success to avoid repeated FindAllOf calls.
---@return userdata|nil The player pawn actor, or nil if not found
local cachedPawn = nil
function utils.GetPlayerPawn()
    -- Return cached pawn if still valid
    if cachedPawn then
        local ok, valid = pcall(function() return cachedPawn:IsValid() end)
        if ok and valid then return cachedPawn end
        cachedPawn = nil
    end

    local allPCs = FindAllOf("PlayerController")
    if allPCs then
        for _, pc in ipairs(allPCs) do
            if pc:IsValid() then
                local okLocal, isLocal = pcall(function() return pc:IsLocalPlayerController() end)
                if okLocal and isLocal then
                    local ok, pawn = pcall(function() return pc.Pawn end)
                    if ok and pawn and pawn:IsValid() then
                        cachedPawn = pawn
                        return pawn
                    end
                end
            end
        end
    end
    -- Fallback to UEHelpers (single player / no PlayerController found)
    local controller = UEHelpers:GetPlayerController()
    if controller and controller:IsValid() then
        local ok, pawn = pcall(function() return controller.Pawn end)
        if ok and pawn and pawn:IsValid() then
            cachedPawn = pawn
            return pawn
        end
    end
    return nil
end

--- Show a notification message to the player using the game's toast system
---@param message string The message to display
---@param config table The mod config (needs config.Notify)
function utils.Notify(message, config)
    if not config.Notify then return end
    -- Console output
    print(string.format("[QuickStack] %s\n", message))
    -- In-game toast via UWEGameplayMessageBPLibrary::NotifyLocalPlayerSimple
    local ok, err = pcall(function()
        local msgLib = StaticFindObject("/Script/UWEGameplayMessageRuntime.Default__UWEGameplayMessageBPLibrary")
        if msgLib then
            local pawn = utils.GetPlayerPawn()
            if pawn then
                msgLib:NotifyLocalPlayerSimple(pawn, { TagName = FName("Notification.Info") }, FText(message))
            end
        end
    end)
    if not ok then
        print(string.format("[QuickStack] Toast failed: %s\n", tostring(err)))
    end
end

--- Convert radius in meters to Unreal units
--- Unreal Engine uses centimeters as base unit
---@param meters number Distance in meters
---@return number Distance in Unreal units (centimeters)
function utils.MetersToUnits(meters)
    return meters * 100
end

--- Read common item data from an inventory item struct.
--- Returns table { typeName, displayName, fullName, itemId, inventoryId, itemType, count } or nil.
function utils.readItemInfo(itemStruct)
    if not itemStruct.ItemType then return nil end
    local ok, typeName = pcall(function() return itemStruct.ItemType:GetFName():ToString() end)
    if not ok then return nil end

    local ok2, fullName = pcall(function() return itemStruct.ItemType:GetFullName() end)

    local displayName = nil
    pcall(function() displayName = itemStruct.ItemType.Name:ToString() end)
    if not displayName or displayName == "" then
        displayName = typeName:gsub("^DA_", ""):gsub("_ItemType$", "")
    end

    return {
        typeName = typeName,
        displayName = displayName,
        fullName = ok2 and fullName or "",
        itemId = itemStruct.ItemId,
        inventoryId = itemStruct.InventoryId,
        itemType = itemStruct.ItemType,
        count = itemStruct.Count or 1,
    }
end

--- Read just the typeName from an inventory item struct. Returns string or nil.
function utils.readItemTypeName(itemStruct)
    if not itemStruct.ItemType then return nil end
    local ok, typeName = pcall(function() return itemStruct.ItemType:GetFName():ToString() end)
    if ok then return typeName end
    return nil
end

--- Find nearby battery/power cell charger terminals.
--- Returns list of { inv (InventoryComponent), forPowerCell (bool) }.
function utils.findNearbyTerminals(pawn, radiusUnits)
    local CHARGER_CLASSES = {
        BP_BasicBatteryTerminal_C = true,
        BP_PowerCellTerminal_C = true,
    }
    local chargers = FindAllOf("UWEPowerTerminal")
    if not chargers then return {} end

    local terminals = {}
    for _, charger in ipairs(chargers) do
        if charger:IsValid() then
            local okCls, className = pcall(function() return charger:GetClass():GetFName():ToString() end)
            if okCls and CHARGER_CLASSES[className] then
                local dist = utils.GetDistance(pawn, charger)
                if dist <= radiusUnits then
                    local ok, inv = pcall(function() return charger.InventoryComponent end)
                    if ok and inv and inv:IsValid() then
                        table.insert(terminals, {
                            inv = inv,
                            forPowerCell = (className == "BP_PowerCellTerminal_C"),
                        })
                    end
                end
            end
        end
    end
    return terminals
end

--- Read the user-set label from a locker's UGCComponent
function utils.getLockerLabel(actor)
    local ok, ugc = pcall(function() return actor.UGCComponent end)
    if not ok or not ugc then return nil end
    local ok1b, valid = pcall(function() return ugc:IsValid() end)
    if not ok1b or not valid then return nil end

    local ok2, hasUGC = pcall(function() return ugc:HasUserGeneratedContent() end)
    if not ok2 or not hasUGC then return nil end

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
                    local s = nil
                    local ok_ts, ts = pcall(function() return val:ToString() end)
                    if ok_ts and ts and type(ts) == "string" then s = ts end
                    if not s then
                        local ok_get, g = pcall(function() return val:get() end)
                        if ok_get and g and type(g) == "string" then s = g end
                    end
                    if not s then
                        local raw = tostring(val)
                        if raw and not raw:match("^FString:") and raw ~= "" and raw ~= "nil" then s = raw end
                    end
                    if s and s ~= "" then str = s end
                end
            end
        end)
        if str then return str end
    end
    return nil
end

--- Whitelisted container classes for scanning
utils.CONTAINER_SOURCES = {
    { class = "SN2Locker",          getInv = function(a) return a.Inventory end,          hasLabel = true },
    { class = "BP_Tailing_Chest_C", getInv = function(a) return a.InventoryComponent end, hasLabel = false },
}

--- Discover nearby containers, categorized by label prefix.
--- Returns lockers, overflowLockers, excludedLockerInvs
--- lockers: { inventory, inventoryId, label } -- normal routing targets
--- overflowLockers: { inventory, inventoryId, label } -- overflow dump targets
--- excludedLockerInvs: { inv } -- excluded containers (still used for restock candidate scanning)
function utils.discoverNearbyContainers(pawn, radiusUnits, cfg)
    local lockers = {}
    local overflowLockers = {}
    local excludedLockerInvs = {}

    for _, source in ipairs(utils.CONTAINER_SOURCES) do
        local actors = FindAllOf(source.class)
        if actors then
            for _, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = utils.GetDistance(pawn, actor)
                    if dist <= radiusUnits then
                        local ok, inv = pcall(function() return source.getInv(actor) end)
                        if ok and inv and inv:IsValid() then
                            local rawLabel = nil
                            if source.hasLabel then
                                local ok2, lbl = pcall(function() return utils.getLockerLabel(actor) end)
                                if ok2 then rawLabel = lbl end
                            end

                            -- Exclusion prefix
                            if rawLabel and cfg.ExcludePrefix ~= "" then
                                if rawLabel:sub(1, #cfg.ExcludePrefix) == cfg.ExcludePrefix then
                                    table.insert(excludedLockerInvs, inv)
                                    goto nextActor
                                end
                            end

                            -- Overflow prefix
                            if rawLabel and cfg.OverflowPrefix ~= "" then
                                if rawLabel:sub(1, #cfg.OverflowPrefix) == cfg.OverflowPrefix then
                                    table.insert(overflowLockers, {
                                        inventory = inv,
                                        inventoryId = inv.InventoryId,
                                        label = rawLabel,
                                    })
                                    goto nextActor
                                end
                            end

                            -- Parse routing label
                            local label = nil
                            if rawLabel and cfg.LabelRouting then
                                if cfg.LabelPrefix == "" then
                                    label = rawLabel
                                else
                                    local prefixLen = #cfg.LabelPrefix
                                    if rawLabel:sub(1, prefixLen) == cfg.LabelPrefix then
                                        label = rawLabel:sub(prefixLen + 1):match("^%s*(.-)%s*$")
                                        if label == "" then label = nil end
                                    end
                                end
                            end
                            table.insert(lockers, {
                                inventory = inv,
                                inventoryId = inv.InventoryId,
                                label = label,
                            })
                        end
                    end
                    ::nextActor::
                end
            end
        end
    end

    -- Stable overflow ordering
    table.sort(overflowLockers, function(a, b) return (a.label or "") < (b.label or "") end)

    return lockers, overflowLockers, excludedLockerInvs
end

--- Find all nearby container inventories (no label parsing). For restock-only scanning.
function utils.findAllNearbyInvs(pawn, radiusUnits)
    local invs = {}
    for _, source in ipairs(utils.CONTAINER_SOURCES) do
        local actors = FindAllOf(source.class)
        if actors then
            for _, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = utils.GetDistance(pawn, actor)
                    if dist <= radiusUnits then
                        local ok, inv = pcall(function() return source.getInv(actor) end)
                        if ok and inv and inv:IsValid() then
                            table.insert(invs, inv)
                        end
                    end
                end
            end
        end
    end
    return invs
end

--- Tadpole/chassis classes whose hardpoints may have portable lockers attached
utils.TADPOLE_CLASSES = {
    BP_Tadpole_C = true,
    BP_Haul_TadpoleChassis_C = true,
    BP_ScoutRay_TadpoleChassis_C = true,
}

--- Find inventories from docked tadpoles/chassis within range.
--- Returns list of UWEInventoryComponent refs (haul chassis built-in + attached portable lockers).
--- Detection: locker-side via GetAttachParentActor() (chassis-side AttachedActor is unreliable).
function utils.findTadpoleSourceInventories(pawn, radiusUnits)
    local inventories = {}
    local seen = {}

    -- Haul chassis built-in inventory
    local haulActors = FindAllOf("BP_Haul_TadpoleChassis_C")
    if haulActors then
        for _, actor in ipairs(haulActors) do
            if actor:IsValid() then
                local dist = utils.GetDistance(pawn, actor)
                if dist <= radiusUnits then
                    local ok, inv = pcall(function() return actor.UWEInventory end)
                    if ok and inv and inv:IsValid() then
                        local okId, invId = pcall(function() return inv.InventoryId end)
                        if okId then
                            seen[invId] = true
                            table.insert(inventories, inv)
                        end
                    end
                end
            end
        end
    end

    -- Portable lockers attached to any tadpole/chassis hardpoint
    local lockers = FindAllOf("BP_FloatingLocker_Carryable_C")
    if lockers then
        for _, locker in ipairs(lockers) do
            if locker:IsValid() then
                local dist = utils.GetDistance(pawn, locker)
                if dist <= radiusUnits then
                    local okP, parent = pcall(function() return locker:GetAttachParentActor() end)
                    if okP and parent then
                        local okV, pValid = pcall(function() return parent:IsValid() end)
                        if okV and pValid then
                            local okC, cls = pcall(function() return parent:GetClass():GetFName():ToString() end)
                            if okC and utils.TADPOLE_CLASSES[cls] then
                                local ok, inv = pcall(function() return locker.UWEInventory end)
                                if ok and inv and inv:IsValid() then
                                    local okId, invId = pcall(function() return inv.InventoryId end)
                                    if okId and not seen[invId] then
                                        seen[invId] = true
                                        table.insert(inventories, inv)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return inventories
end

--- Default max items per container (fallback when MaxItems property is unavailable)
utils.DEFAULT_MAX_ITEMS = 30

--- Snapshot locker contents for type-count matching.
--- Returns typeData, itemCount, maxItems, labels (parallel arrays indexed by locker position).
function utils.snapshotLockerContents(lockerList)
    local typeData = {}
    local itemCount = {}
    local maxItems = {}
    local labels = {}
    for i, data in ipairs(lockerList) do
        typeData[i] = {}
        labels[i] = data.label
        itemCount[i] = 0
        local ok0, max = pcall(function() return data.inventory.MaxItems end)
        maxItems[i] = (ok0 and max) or utils.DEFAULT_MAX_ITEMS
        local ok, items = pcall(function() return data.inventory:GetItems() end)
        if ok and items then
            itemCount[i] = #items
            for _, item in ipairs(items) do
                local s = item:get()
                local typeName = utils.readItemTypeName(s)
                if typeName then
                    typeData[i][typeName] = (typeData[i][typeName] or 0) + 1
                end
            end
        end
    end
    return typeData, itemCount, maxItems, labels
end

--- Record a transfer/restock detail entry for the summary panel.
function utils.recordDetail(detailsTable, typeName, itemType, displayName, containerLabel)
    if not detailsTable[typeName] then
        detailsTable[typeName] = {
            itemType = itemType,
            displayName = displayName,
            count = 0,
            containers = {},
        }
    end
    detailsTable[typeName].count = detailsTable[typeName].count + 1
    detailsTable[typeName].containers[containerLabel] = true
end

--- Wait for server replication before reading inventory
--- Polls every 100ms until item count changes or timeout reached
--- Host: 0ms (instant). Non-host: ~100-200ms typical, 1500ms max.
function utils.waitForReplication(inventory, countBefore, callback, maxWaitMs)
    maxWaitMs = maxWaitMs or 1500
    local elapsed = 0
    local function check()
        local current = #inventory:GetItems()
        if current < countBefore or elapsed >= maxWaitMs then
            callback(countBefore - current)
        else
            elapsed = elapsed + 100
            ExecuteWithDelay(100, function()
                ExecuteInGameThread(check)
            end)
        end
    end
    check()
end

return utils
