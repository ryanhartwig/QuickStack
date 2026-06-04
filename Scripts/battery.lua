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

--- Get the world inventory subsystem (server-authoritative inventory registry).
local function getInventorySubsystem(playerInv)
    local ss = nil
    pcall(function() ss = playerInv:GetInventorySubsystem() end)
    if ss and ss:IsValid() then return ss end
    ss = FindFirstOf("UWEInventorySubsystem")
    if ss and ss:IsValid() then return ss end
    return nil
end

--- Swap a depleted player battery for a charged terminal battery via the inventory
--- subsystem. Unlike UWEInventoryComponent:MoveItemBetweenInventories, the subsystem move
--- is server-authoritative and does NOT gate on the client's stale local fullness view --
--- so it works for FULL terminals on non-host clients (QuickStack #7, verified host+client).
--- Pulls the charged battery first to free a real slot, then pushes the depleted one in.
--- Returns true on a completed swap.
local function subsystemTerminalSwap(playerInv, pullItemId, terminalInvId, pushItemId)
    local ss = getInventorySubsystem(playerInv)
    if not ss then return false end
    local playerInvId = playerInv.InventoryId
    local pullOk = false
    pcall(function() pullOk = ss:MoveInventoryItem(pullItemId, terminalInvId, playerInvId) end)
    if not pullOk then return false end
    local pushOk = false
    pcall(function() pushOk = ss:MoveInventoryItem(pushItemId, playerInvId, terminalInvId) end)
    if not pushOk then
        -- Push rejected: return the charged battery so we don't leave a free pull behind.
        pcall(function() ss:MoveInventoryItem(pullItemId, playerInvId, terminalInvId) end)
        return false
    end
    return true
end

--- Move one item between inventories. Prefers the server-authoritative subsystem
--- (real bool return, bypasses the client's stale local fullness gate); falls back to
--- the component path with player-inventory count verification if the subsystem is
--- unavailable. Returns true on a completed move.
local function moveItem(ss, playerInv, itemId, fromId, toId)
    if ss then
        local ok = false
        pcall(function() ok = ss:MoveInventoryItem(itemId, fromId, toId) end)
        return ok == true
    end
    local before = #playerInv:GetItems()
    pcall(function() playerInv:MoveItemBetweenInventories(itemId, fromId, toId) end)
    return #playerInv:GetItems() ~= before
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
                -- Terminal full: the push-first attempt above no-ops on a full terminal
                -- (and silently no-ops on non-host clients regardless). Swap via the
                -- inventory subsystem instead -- server-authoritative, bypasses the
                -- client's stale local fullness gate. Pull the charged battery first to
                -- free a slot, then push the depleted one in (QuickStack #7).
                if subsystemTerminalSwap(playerInv, cb.itemId, cb.inventoryId, playerBat.itemId) then
                    swapCount = swapCount + 1
                    cb.used = true
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

    -- Keep the BEST `budget` batteries of each kind in the player's inventory and send
    -- the rest to the terminal. We rank player-held and terminal batteries together in
    -- one pool, so a low-charge held battery gets upgraded even when the player is UNDER
    -- budget (e.g. holding 1 depleted battery, budget 3, terminal full of full batteries
    -- -> the player ends with the 3 best and the depleted one goes to the terminal).
    -- Moves go through the server-authoritative subsystem so they work on non-host
    -- clients (no stale local-fullness gating, real bool return -- see QuickStack #7).
    local ss = getInventorySubsystem(playerInv)
    for _, group in ipairs(groups) do
        -- Terminal batteries available to this kind (unused, matching battery/power-cell)
        local termGroup = {}
        for _, tb in ipairs(termBatteries) do
            if not tb.used and tb.forPowerCell == group.isPowerCell then
                table.insert(termGroup, tb)
            end
        end

        -- Combined pool ranked highest charge first. On ties, player-held batteries sort
        -- first so we don't churn equal-charge batteries between player and terminal.
        local pool = {}
        for _, b in ipairs(group.items) do
            table.insert(pool, { info = b, origin = "player", charge = b.chargePercent })
        end
        for _, tb in ipairs(termGroup) do
            table.insert(pool, { info = tb, origin = "terminal", charge = tb.chargePercent })
        end
        table.sort(pool, function(a, b)
            if a.charge ~= b.charge then return a.charge > b.charge end
            return a.origin == "player" and b.origin ~= "player"
        end)

        -- Classify: terminal batteries inside the top `budget` get pulled to the player;
        -- player batteries outside it get stashed to the terminal.
        local toPull, toStash = {}, {}
        for rank, entry in ipairs(pool) do
            if rank <= group.budget then
                if entry.origin == "terminal" then table.insert(toPull, entry.info) end
            elseif entry.origin == "player" then
                table.insert(toStash, entry.info)
            end
        end

        -- Pull first: brings the best batteries in and frees terminal slots for stashing.
        for _, tb in ipairs(toPull) do
            if moveItem(ss, playerInv, tb.itemId, tb.inventoryId, playerInvId) then
                pullCount = pullCount + 1
                tb.used = true
                utils.recordDetail(batteryDetails, tb.typeName, tb.itemType, tb.displayName, "Terminal")
            end
        end

        -- Then stash the excess, lower-charge player batteries into a matching terminal
        -- (now has freed slots). If no terminal accepts it, leave it in inventory -- the
        -- normal quickstack pass routes it to a locker.
        for _, bat in ipairs(toStash) do
            local placed = false
            for _, term in ipairs(terminalInvs) do
                if term.forPowerCell == group.isPowerCell then
                    if moveItem(ss, playerInv, bat.itemId, bat.inventoryId, term.inv.InventoryId) then
                        stashCount = stashCount + 1
                        utils.recordDetail(batteryDetails, bat.typeName, bat.itemType, bat.displayName, "Terminal")
                        placed = true
                        break
                    end
                end
            end
            if not placed then
                table.insert(unplaced, bat)
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
