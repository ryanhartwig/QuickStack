--- QuickStack: Battery swap and management module
--- Handles legacy battery swap, budget-based battery management, and overflow routing

local utils = require("utils")
local categories = require("categories")
local config = nil

local battery = {}

local isBatteryType = categories.isBatteryType
local isPowerCellType = categories.isPowerCellType
local readCharge = categories.readCharge
local readItemInfo = utils.readItemInfo
local readItemTypeName = utils.readItemTypeName

local BATTERY_FULL_THRESHOLD = 0.99

function battery.init(cfg)
    config = cfg
end

--- Battery swap: for each battery/power cell in player inventory,
--- check nearby chargers for a higher-charge replacement and swap
function battery.doBatterySwap(pawn, playerInv)
    if not config.BatterySwap then return 0 end

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local allTerminals = utils.findNearbyTerminals(pawn, radiusUnits)
    if #allTerminals == 0 then return 0 end

    -- Get player batteries with charge info
    local playerItems = playerInv:GetItems()
    local playerBatteries = {}
    for _, item in ipairs(playerItems) do
        local s = item:get()
        local typeName = readItemTypeName(s)
        if typeName and isBatteryType(typeName) then
            -- Skip types managed by budget (those are handled by doBatteryManagement)
            local isPC = isPowerCellType(typeName)
            local managed = isPC and (config.RestockPowerCellCount or 0) > 0
                or not isPC and (config.RestockBatteryCount or 0) > 0
            if not managed then
                local current, max = readCharge(s)
                if current and max and max > 0 then
                    table.insert(playerBatteries, {
                        typeName = typeName,
                        itemId = s.ItemId,
                        inventoryId = s.InventoryId,
                        charge = current,
                        maxCharge = max,
                        chargePercent = current / max,
                    })
                end
            end
        end
    end

    if #playerBatteries == 0 then return 0 end

    -- Snapshot all charger batteries upfront (avoids stale GetItems after swaps)
    local chargerBatteries = {} -- { typeName, charge, itemId, inventoryId, chargerInv, used }
    for _, term in ipairs(allTerminals) do
        local ok, chargerItems = pcall(function() return term.inv:GetItems() end)
        if ok and chargerItems then
            for _, cItem in ipairs(chargerItems) do
                local cs = cItem:get()
                local cTypeName = readItemTypeName(cs)
                if cTypeName and isBatteryType(cTypeName) then
                    local cCurrent, cMax = readCharge(cs)
                    if cCurrent and cMax then
                        table.insert(chargerBatteries, {
                            typeName = cTypeName,
                            charge = cCurrent,
                            itemId = cs.ItemId,
                            inventoryId = cs.InventoryId,
                            chargerInv = term.inv,
                            used = false,
                        })
                    end
                end
            end
        end
    end

    local swapCount = 0

    -- Sort player batteries lowest charge first (swap worst ones first)
    table.sort(playerBatteries, function(a, b) return a.chargePercent < b.chargePercent end)

    for _, playerBat in ipairs(playerBatteries) do
        if playerBat.chargePercent >= BATTERY_FULL_THRESHOLD then goto nextBattery end

        -- Find best unused charger battery (same type, highest charge, better than player's)
        local bestIdx = nil
        local bestCharge = playerBat.charge

        for i, cb in ipairs(chargerBatteries) do
            if not cb.used and cb.typeName == playerBat.typeName and cb.charge > bestCharge then
                bestCharge = cb.charge
                bestIdx = i
            end
        end

        if bestIdx then
            local cb = chargerBatteries[bestIdx]
            local beforeCount = #playerInv:GetItems()

            -- Try push-first: works immediately on host and clients with non-full terminals
            pcall(function()
                playerInv:MoveItemBetweenInventories(
                    playerBat.itemId, playerBat.inventoryId, cb.chargerInv.InventoryId)
            end)
            local afterPush = #playerInv:GetItems()

            if afterPush < beforeCount then
                -- Push succeeded (terminal had space), pull charged battery
                pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        cb.itemId, cb.inventoryId, playerInv.InventoryId)
                end)
                local afterPull = #playerInv:GetItems()
                if afterPull > afterPush then
                    swapCount = swapCount + 1
                    cb.used = true
                else
                    -- Pull failed, rollback push
                    pcall(function()
                        playerInv:MoveItemBetweenInventories(
                            playerBat.itemId, cb.chargerInv.InventoryId, playerBat.inventoryId)
                    end)
                end
            else
                -- Terminal full: pull first to free a slot, then push after replication.
                -- On host this is synchronous. On clients, poll terminal count until
                -- the pulled item is removed (replication delay), then push.
                local termCountBefore = 0
                pcall(function() termCountBefore = #cb.chargerInv:GetItems() end)

                pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        cb.itemId, cb.inventoryId, playerInv.InventoryId)
                end)
                local afterPull = #playerInv:GetItems()

                if afterPull > beforeCount then
                    -- Pull succeeded — try push immediately (works on host)
                    pcall(function()
                        playerInv:MoveItemBetweenInventories(
                            playerBat.itemId, playerBat.inventoryId, cb.chargerInv.InventoryId)
                    end)
                    local afterSwap = #playerInv:GetItems()

                    if afterSwap < afterPull then
                        -- Push worked (host path)
                        swapCount = swapCount + 1
                        cb.used = true
                    else
                        -- Push failed (client: terminal hasn't replicated yet)
                        -- Poll terminal count until slot frees up, then push
                        swapCount = swapCount + 1  -- optimistic
                        cb.used = true
                        local pushItemId = playerBat.itemId
                        local pushInvId = playerBat.inventoryId
                        local pushTargetInvId = cb.chargerInv.InventoryId
                        local termInv = cb.chargerInv
                        local elapsed = 0
                        local function pollAndPush()
                            local termCount = 0
                            pcall(function() termCount = #termInv:GetItems() end)
                            if termCount < termCountBefore then
                                -- Terminal replicated, push now
                                pcall(function()
                                    playerInv:MoveItemBetweenInventories(pushItemId, pushInvId, pushTargetInvId)
                                end)
                            elseif elapsed < 1500 then
                                elapsed = elapsed + 100
                                ExecuteWithDelay(100, function()
                                    ExecuteInGameThread(pollAndPush)
                                end)
                            end
                        end
                        ExecuteWithDelay(100, function()
                            ExecuteInGameThread(pollAndPush)
                        end)
                    end
                end
            end
        end

        ::nextBattery::
    end

    return swapCount
end

--- Battery management: stash excess batteries/power cells to matching Terminal, pull to fill budget
--- Processes batteries and power cells independently with separate budgets.
--- Returns stashCount, pullCount, unplacedBatteries, batteryDetails (for summary panel)
function battery.doBatteryManagement(pawn, playerInv)
    local batteryBudget = config.RestockBatteryCount or 0
    local powerCellBudget = config.RestockPowerCellCount or 0
    if batteryBudget <= 0 and powerCellBudget <= 0 then return 0, 0, {}, {} end  -- stash, pull, unplaced, details

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local terminalInvs = utils.findNearbyTerminals(pawn, radiusUnits)

    local playerInvId = playerInv.InventoryId
    local stashCount = 0
    local pullCount = 0
    local batteryDetails = {}  -- for summary panel

    -- Scan player inventory for all battery-type items
    local playerBats = {}
    local playerPCs = {}
    local playerItems = playerInv:GetItems()
    for _, item in ipairs(playerItems) do
        local s = item:get()
        local info = readItemInfo(s)
        if info and isBatteryType(info.typeName) then
            local current, max = readCharge(s)
            if current and max and max > 0 then
                info.charge = current
                info.chargePercent = current / max
                if isPowerCellType(info.typeName) then
                    table.insert(playerPCs, info)
                else
                    table.insert(playerBats, info)
                end
            end
        end
    end

    -- Build groups: only process types that have a budget > 0
    local groups = {}
    if batteryBudget > 0 then
        table.insert(groups, { items = playerBats, budget = batteryBudget, isPowerCell = false })
    end
    if powerCellBudget > 0 then
        table.insert(groups, { items = playerPCs, budget = powerCellBudget, isPowerCell = true })
    end

    local unplaced = {}

    -- No terminals: all excess become unplaced for normal locker routing
    if #terminalInvs == 0 then
        for _, group in ipairs(groups) do
            if #group.items > group.budget then
                table.sort(group.items, function(a, b) return a.chargePercent > b.chargePercent end)
                for i = group.budget + 1, #group.items do
                    table.insert(unplaced, group.items[i])
                end
            end
        end
        return 0, 0, unplaced, {}
    end

    -- Snapshot ALL terminal batteries (shared across groups, used flag prevents double-swap)
    local termBatteries = {}
    for _, term in ipairs(terminalInvs) do
        local ok, items = pcall(function() return term.inv:GetItems() end)
        if ok and items then
            for _, item in ipairs(items) do
                local s = item:get()
                local info = readItemInfo(s)
                if info and isBatteryType(info.typeName) then
                    local cur, mx = readCharge(s)
                    if cur and mx and mx > 0 then
                        info.chargePercent = cur / mx
                        info.terminalInv = term.inv
                        info.forPowerCell = term.forPowerCell
                        info.used = false
                        table.insert(termBatteries, info)
                    end
                end
            end
        end
    end

    -- Phase 1: Stash excess for each group
    for _, group in ipairs(groups) do
        if #group.items > group.budget then
            table.sort(group.items, function(a, b) return a.chargePercent < b.chargePercent end)
            local toStash = #group.items - group.budget

            for i = 1, toStash do
                local bat = group.items[i]
                -- Try direct stash first (terminal has space, matching type)
                local placed = false
                local beforeCount = #playerInv:GetItems()
                for _, term in ipairs(terminalInvs) do
                    if term.forPowerCell == group.isPowerCell then
                        pcall(function()
                            playerInv:MoveItemBetweenInventories(bat.itemId, bat.inventoryId, term.inv.InventoryId)
                        end)
                        local afterCount = #playerInv:GetItems()
                        if afterCount < beforeCount then
                            stashCount = stashCount + 1
                            utils.recordDetail(batteryDetails, bat.typeName, bat.itemType, bat.displayName, "Terminal")
                            placed = true
                            break
                        end
                    end
                end
                -- Terminal full: swap with highest-charge terminal battery of same type.
                -- Pull from terminal first (frees a slot), then push player battery in.
                if not placed then
                    local bestIdx = nil
                    local bestCharge = bat.chargePercent
                    for j, tb in ipairs(termBatteries) do
                        if not tb.used and tb.typeName == bat.typeName and tb.forPowerCell == group.isPowerCell and tb.chargePercent > bestCharge then
                            bestCharge = tb.chargePercent
                            bestIdx = j
                        end
                    end
                    if bestIdx then
                        local tb = termBatteries[bestIdx]
                        local beforePull = #playerInv:GetItems()
                        pcall(function()
                            playerInv:MoveItemBetweenInventories(
                                tb.itemId, tb.inventoryId, playerInvId)
                        end)
                        local afterPull = #playerInv:GetItems()
                        if afterPull > beforePull then
                            pcall(function()
                                playerInv:MoveItemBetweenInventories(
                                    bat.itemId, bat.inventoryId, tb.terminalInv.InventoryId)
                            end)
                            local afterPush = #playerInv:GetItems()
                            if afterPush < afterPull then
                                stashCount = stashCount + 1
                                utils.recordDetail(batteryDetails, bat.typeName, bat.itemType, bat.displayName, "Terminal")
                                tb.used = true
                                placed = true
                                table.insert(unplaced, {
                                    typeName = tb.typeName,
                                    displayName = tb.displayName,
                                    itemType = tb.itemType,
                                    itemId = tb.itemId,
                                    inventoryId = playerInvId,
                                    count = tb.count,
                                })
                            else
                                pcall(function()
                                    playerInv:MoveItemBetweenInventories(
                                        tb.itemId, playerInvId, tb.inventoryId)
                                end)
                            end
                        end
                    end
                end
                if not placed then
                    table.insert(unplaced, bat)
                end
            end
        end
    end

    -- Phase 2: Pull best batteries from Terminal if player needs more (per type)
    playerItems = playerInv:GetItems()
    for _, group in ipairs(groups) do
        -- Count how many of this type the player currently holds
        local currentCount = 0
        for _, item in ipairs(playerItems) do
            local s = item:get()
            local typeName = readItemTypeName(s)
            if typeName and isBatteryType(typeName) and (isPowerCellType(typeName) == group.isPowerCell) then
                currentCount = currentCount + 1
            end
        end

        if currentCount < group.budget then
            local needed = group.budget - currentCount
            local pullCandidates = {}
            for _, term in ipairs(terminalInvs) do
                if term.forPowerCell == group.isPowerCell then
                    local ok, items = pcall(function() return term.inv:GetItems() end)
                    if ok and items then
                        for _, item in ipairs(items) do
                            local s = item:get()
                            local info = readItemInfo(s)
                            if info and isBatteryType(info.typeName) then
                                local current, max = readCharge(s)
                                info.chargePercent = (current and max and max > 0) and (current / max) or 0
                                table.insert(pullCandidates, info)
                            end
                        end
                    end
                end
            end

            table.sort(pullCandidates, function(a, b) return a.chargePercent > b.chargePercent end)
            local pulled = 0
            for _, bat in ipairs(pullCandidates) do
                if pulled >= needed then break end
                local ok = pcall(function()
                    playerInv:MoveItemBetweenInventories(bat.itemId, bat.inventoryId, playerInvId)
                end)
                if ok then
                    pulled = pulled + 1
                    pullCount = pullCount + 1
                    utils.recordDetail(batteryDetails, bat.typeName, bat.itemType, bat.displayName, "Terminal")
                end
            end
        end
    end

    return stashCount, pullCount, unplaced, batteryDetails
end

--- Route batteries from overflow lockers to Battery Terminal (used by H key).
--- Simple direct moves — if terminal is full, batteries stay in overflow for normal locker routing.
--- Returns moved count and a set of ItemIds that were routed (so caller can skip them).
function battery.routeOverflowBatteriesToTerminal(pawn, playerInv, overflowLockers)
    local anyBudget = (config.RestockBatteryCount or 0) > 0 or (config.RestockPowerCellCount or 0) > 0
    if not anyBudget then return 0, {} end

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local terminalInvs = utils.findNearbyTerminals(pawn, radiusUnits)
    if #terminalInvs == 0 then return 0, {} end

    local moved = 0
    local movedItemIds = {}
    for _, overflowData in ipairs(overflowLockers) do
        local ok, items = pcall(function() return overflowData.inventory:GetItems() end)
        if ok and items then
            for _, item in ipairs(items) do
                local s = item:get()
                local typeName = readItemTypeName(s)
                if typeName and isBatteryType(typeName) then
                    local isPC = isPowerCellType(typeName)
                    for _, term in ipairs(terminalInvs) do
                        if term.forPowerCell == isPC then
                            local beforeCount = #overflowData.inventory:GetItems()
                            pcall(function()
                                playerInv:MoveItemBetweenInventories(s.ItemId, s.InventoryId, term.inv.InventoryId)
                            end)
                            local afterCount = #overflowData.inventory:GetItems()
                            if afterCount < beforeCount then
                                moved = moved + 1
                                movedItemIds[s.ItemId] = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return moved, movedItemIds
end

return battery
