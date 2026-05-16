-- QuickStack Mod for Subnautica 2
-- Press N to auto-stack inventory items into nearby matching containers
-- Press F to dump all items into the currently open container

local UEHelpers = require("UEHelpers")
local config = require("config")
local utils = require("utils")

local VERSION = "1.1.0"
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

--- Get the inventory component of the currently open container (if any)
local function getOpenContainerInventory()
    local screenVMs = FindAllOf("SN2InventoryScreenViewModel")
    if not screenVMs then return nil end

    for _, vm in ipairs(screenVMs) do
        if vm:IsValid() then
            local ok, otherInv = pcall(function() return vm.OtherInventory end)
            if ok and otherInv and otherInv:IsValid() then
                local ok2, invComp = pcall(function() return otherInv.InventoryComponent end)
                if ok2 and invComp and invComp:IsValid() then
                    return invComp
                end
            end
        end
    end
    return nil
end

--- Transfer matching items from player inventory to a set of target lockers
--- Returns actualTransferred, numContainers, someFull
local function transferToLockers(playerInv, playerItems, nearbyLockers)
    -- Build a set of item types each locker already contains, and their counts
    local lockerTypeData = {}
    for i, data in ipairs(nearbyLockers) do
        lockerTypeData[i] = {}
        local ok, lockerItems = pcall(function() return data.inventory:GetItems() end)
        if ok and lockerItems then
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

    -- For each player item, find a matching locker and transfer
    local containersUsed = {}
    local someFull = false

    for _, playerItem in ipairs(playerItems) do
        local s = playerItem:get()
        if s.ItemType then
            local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok then
                local bestIdx = nil
                local bestCount = 0

                for i, data in ipairs(nearbyLockers) do
                    local typeCount = lockerTypeData[i][typeName]
                    if typeCount and typeCount > 0 then
                        local ok2, full = pcall(function() return data.inventory:IsFull() end)
                        if ok2 and not full then
                            if typeCount > bestCount then
                                bestCount = typeCount
                                bestIdx = i
                            end
                        elseif ok2 and full then
                            someFull = true
                        end
                    end
                end

                if bestIdx then
                    local data = nearbyLockers[bestIdx]
                    local itemId = s.ItemId
                    local fromId = s.InventoryId
                    local toId = data.inventoryId

                    local ok3 = pcall(function()
                        return playerInv:MoveItemBetweenInventories(itemId, fromId, toId)
                    end)

                    if ok3 then
                        containersUsed[bestIdx] = true
                        lockerTypeData[bestIdx][typeName] = (lockerTypeData[bestIdx][typeName] or 0) + (s.Count or 1)
                    else
                        local ok4 = pcall(function()
                            return playerInv:MoveInventoryItem(data.inventory, itemId, playerInv)
                        end)
                        if ok4 then
                            containersUsed[bestIdx] = true
                            lockerTypeData[bestIdx][typeName] = (lockerTypeData[bestIdx][typeName] or 0) + (s.Count or 1)
                        end
                    end
                end
            end
        end
    end

    -- Count actual transfers
    local afterItems = playerInv:GetItems()
    local actualTransferred = #playerItems - #afterItems
    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end

    return actualTransferred, numContainers, someFull
end

--- Quick Stack: transfer matching items to nearby lockers
local function doQuickStack()
    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then
        utils.Notify("Error: Could not find player inventory", config)
        return
    end

    local playerItems = playerInv:GetItems()
    if #playerItems == 0 then
        utils.Notify("Nothing to stack", config)
        return
    end

    local lockers = FindAllOf("SN2Locker")
    if not lockers then
        utils.Notify("No matching containers nearby", config)
        return
    end

    local playerLoc = pawn:K2_GetActorLocation()
    local radiusUnits = utils.MetersToUnits(config.Radius)
    local nearbyLockers = {}
    for _, locker in ipairs(lockers) do
        if locker:IsValid() then
            local dist = utils.GetDistance(pawn, locker)
            if dist <= radiusUnits then
                local inv = locker.Inventory
                if inv and inv:IsValid() then
                    table.insert(nearbyLockers, {
                        locker = locker,
                        inventory = inv,
                        inventoryId = inv.InventoryId,
                    })
                end
            end
        end
    end

    if #nearbyLockers == 0 then
        utils.Notify("No matching containers nearby", config)
        return
    end

    local actualTransferred, numContainers, someFull = transferToLockers(playerInv, playerItems, nearbyLockers)

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

    local playerItems = playerInv:GetItems()
    if #playerItems == 0 then
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

    -- Transfer only matching items
    for _, playerItem in ipairs(playerItems) do
        local s = playerItem:get()
        if s.ItemType and s.ItemId then
            local ok3, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok3 and containerTypes[typeName] then
                pcall(function()
                    playerInv:MoveItemBetweenInventories(s.ItemId, s.InventoryId, targetId)
                end)
            end
        end
    end

    local afterItems = playerInv:GetItems()
    local actualTransferred = #playerItems - #afterItems

    if actualTransferred <= 0 then
        utils.Notify("No matching items for this container", config)
    else
        local itm = actualTransferred == 1 and "item" or "items"
        utils.Notify(string.format("Quick Stacked %d %s into container", actualTransferred, itm), config)
    end
end

-- Keybind: N for Quick Stack (nearby lockers)
RegisterKeyBind(bindKey, function()
    ExecuteInGameThread(function()
        local now = os.clock()
        if now - lastActivation < config.Cooldown then
            return
        end
        lastActivation = now
        doQuickStack()
    end)
end)

-- Keybind: F for Quick Dump (into open container)
RegisterKeyBind(Key.F, function()
    ExecuteInGameThread(function()
        local now = os.clock()
        if now - lastActivation < config.Cooldown then
            return
        end
        lastActivation = now
        doQuickStackOpen()
    end)
end)
