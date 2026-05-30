-- QuickStack Mod for Subnautica 2
-- N: Quick Stack to nearby containers + battery swap + overflow dump
-- G: Quick Stack into currently open container
-- H: Sort overflow locker contents into nearby matching lockers
-- Supports locker labels, item protection, battery/power cell swapping, overflow lockers

local UEHelpers = require("UEHelpers")
local config = require("config")
local utils = require("utils")
local matching = require("matching")
local categories = require("categories")
local battery = require("battery")
local restock = require("restock")
local ui = require("ui")
local lang = require("lang")
local L = lang.L

categories.init(config)
battery.init(config)
restock.init(config)
ui.init(config)

local VERSION = "3.3.3"
print(string.format("[QuickStack] v%s loaded\n", VERSION))

-- Write SN2ModSettings manifest if the mod is installed (optional integration)
do
    local SN2_DIR = "./ue4ss/Mods/SN2ModSettings/"
    local REG_DIR = SN2_DIR .. "registrations/"

    local function buildManifest()
        local function esc(s) return s:gsub("'", "\\'") end
        return string.format([=[return {
    name     = "QuickStack",
    display  = '%s',
    version  = "%s",
    github   = "ryanhartwig/QuickStack",
    nexus_id = "128",
    settings = {
        { key="radius", title='%s',
          description='%s',
          type="slider", default=25, min=5, max=235, step=5, format="integer" },

        { key="battery_swap", title='%s',
          description='%s',
          type="toggle", default=true },

        { key="restock_food_count", title='%s',
          description='%s',
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="restock_drink_count", title='%s',
          description='%s',
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="restock_heal_count", title='%s',
          description='%s',
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="restock_battery_count", title='%s',
          description='%s',
          type="slider", default=0, min=0, max=10, step=1, format="integer" },

        { key="restock_powercell_count", title='%s',
          description='%s',
          type="slider", default=0, min=0, max=10, step=1, format="integer" },

        { key="summary_panel", title='%s',
          description='%s',
          type="toggle", default=true },
        { key="summary_duration", title='%s',
          description='%s',
          type="slider", default=6, min=2, max=15, step=1, format="integer",
          enabled_by="summary_panel" },
    },
}
]=],
        esc(L("mod_display")), VERSION,
        esc(L("radius_title")), esc(L("radius_desc")),
        esc(L("battery_swap_title")), esc(L("battery_swap_desc")),
        esc(L("food_title")), esc(L("food_desc")),
        esc(L("drink_title")), esc(L("drink_desc")),
        esc(L("heal_title")), esc(L("heal_desc")),
        esc(L("battery_budget_title")), esc(L("battery_budget_desc")),
        esc(L("powercell_budget_title")), esc(L("powercell_budget_desc")),
        esc(L("summary_title")), esc(L("summary_desc")),
        esc(L("summary_dur_title")), esc(L("summary_dur_desc"))
        )
    end

    local function writeManifest()
        local f = io.open(REG_DIR .. "QuickStack.lua", "w")
        if f then
            f:write(buildManifest())
            f:close()
        end
    end

    -- Re-write manifest when language changes
    lang.onRefresh = writeManifest

    -- Check if SN2ModSettings is installed
    local enabledFile = io.open(SN2_DIR .. "enabled.txt", "r")
    if enabledFile then
        enabledFile:close()

        -- Poll for SN2ModSettings initialization (writes its own manifest on startup)
        local attempts = 0
        local MAX_ATTEMPTS = 10
        local function tryWriteManifest()
            attempts = attempts + 1

            -- Check if SN2ModSettings has initialized (its self-manifest exists)
            local selfManifest = io.open(REG_DIR .. "SN2ModSettings.lua", "r")
            local initialized = selfManifest ~= nil
            if selfManifest then selfManifest:close() end

            if initialized or attempts >= MAX_ATTEMPTS then
                -- Create registrations dir if needed (fixes systems where ensure_dir fails)
                if not initialized then
                    os.execute('mkdir "' .. REG_DIR:gsub("/", "\\") .. '" 2>nul')
                end
                writeManifest()
                print(string.format("[QuickStack] SN2ModSettings manifest written (attempt %d/%d)\n",
                    attempts, MAX_ATTEMPTS))
            else
                -- Retry in 1 second
                ExecuteWithDelay(1000, function()
                    ExecuteInGameThread(tryWriteManifest)
                end)
            end
        end

        -- Start polling after 1 second (give SN2ModSettings time to begin loading)
        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(tryWriteManifest)
        end)
    end
end

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

-- Restock runs with quickstack unless a separate restock keybind is configured
local restockWithQuickstack = (config.KeybindRestock == "" or config.KeybindRestock == config.Keybind)

-- Cooldown state
local lastActivation = 0

-- Module aliases for frequently used functions
local isBatteryType = categories.isBatteryType
local isPowerCellType = categories.isPowerCellType
local readCharge = categories.readCharge
local shouldKeepItem = categories.shouldKeepItem
local readItemInfo = utils.readItemInfo
local readItemTypeName = utils.readItemTypeName
local scoreLockerMatch = matching.scoreLockerMatch
local waitForReplication = ui.waitForReplication
local showTransferSummary = ui.showTransferSummary

-- Constants
local DEFAULT_MAX_ITEMS = 30

--- Get the inventory component of the currently open container
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
local function getTransferableItems(playerInv)
    local items = playerInv:GetItems()
    local transferable = {}
    local heldConsumables = {}  -- consumables kept by shouldKeepItem, sorted later for budget trimming
    local heldBatteries = {}    -- battery-type items kept by shouldKeepItem, for budget trimming

    for _, playerItem in ipairs(items) do
        local s = playerItem:get()
        local itemData = readItemInfo(s)
        if itemData then
            if not shouldKeepItem(itemData.typeName, itemData.fullName) then
                table.insert(transferable, itemData)
            else
                -- Track consumables for budget trimming
                local cat = categories.getConsumableCategory(itemData.typeName)
                if cat then
                    itemData.category = cat
                    itemData.priority = categories.getPriority(itemData.typeName, cat)
                    table.insert(heldConsumables, itemData)
                elseif isBatteryType(itemData.typeName) then
                    local current, max = readCharge(s)
                    if current and max and max > 0 then
                        itemData.chargePercent = current / max
                        table.insert(heldBatteries, itemData)
                    end
                end
            end
        end
    end

    -- Budget trimming: if player holds more consumables than budget, transfer the worst
    local budgets = {
        food  = config.RestockFoodCount or 0,
        drink = config.RestockDrinkCount or 0,
        heal  = config.RestockHealCount or 0,
    }

    -- Group by category
    local byCat = { food = {}, drink = {}, heal = {} }
    for _, item in ipairs(heldConsumables) do
        if byCat[item.category] then
            table.insert(byCat[item.category], item)
        end
    end

    -- For each category, sort by priority (best first), keep budget, transfer excess
    for cat, catItems in pairs(byCat) do
        if budgets[cat] > 0 and #catItems > budgets[cat] then
            table.sort(catItems, function(a, b) return a.priority < b.priority end)
            -- Items beyond the budget get transferred (worst ones)
            for i = budgets[cat] + 1, #catItems do
                table.insert(transferable, catItems[i])
            end
        end
    end

    -- Battery/power cell budget trimming: keep best-charged, transfer excess
    local batBudget = config.RestockBatteryCount or 0
    local pcBudget = config.RestockPowerCellCount or 0
    if batBudget > 0 or pcBudget > 0 then
        local batItems = {}
        local pcItems = {}
        for _, item in ipairs(heldBatteries) do
            if isPowerCellType(item.typeName) then
                table.insert(pcItems, item)
            else
                table.insert(batItems, item)
            end
        end
        if batBudget > 0 and #batItems > batBudget then
            table.sort(batItems, function(a, b) return a.chargePercent > b.chargePercent end)
            for i = batBudget + 1, #batItems do
                table.insert(transferable, batItems[i])
            end
        end
        if pcBudget > 0 and #pcItems > pcBudget then
            table.sort(pcItems, function(a, b) return a.chargePercent > b.chargePercent end)
            for i = pcBudget + 1, #pcItems do
                table.insert(transferable, pcItems[i])
            end
        end
    end

    return transferable, #items
end

--- Transfer matching items from player inventory to nearby containers
local function transferToLockers(playerInv, transferableItems, totalItemsBefore, nearbyLockers)
    local lockerTypeData = {}
    local lockerLabels = {}
    local lockerItemCount = {}
    local lockerMaxItems = {}

    for i, data in ipairs(nearbyLockers) do
        lockerTypeData[i] = {}
        lockerLabels[i] = data.label
        lockerItemCount[i] = 0
        local ok0, maxItems = pcall(function() return data.inventory.MaxItems end)
        lockerMaxItems[i] = (ok0 and maxItems) or DEFAULT_MAX_ITEMS
        local ok, lockerItems = pcall(function() return data.inventory:GetItems() end)
        if ok and lockerItems then
            lockerItemCount[i] = #lockerItems
            for _, item in ipairs(lockerItems) do
                local s = item:get()
                local typeName = readItemTypeName(s)
                if typeName then
                    lockerTypeData[i][typeName] = (lockerTypeData[i][typeName] or 0) + (s.Count or 1)
                end
            end
        end
    end

    local containersUsed = {}
    local someFull = false
    local transferDetails = {}  -- keyed by typeName: { itemType, count, containers }

    for _, item in ipairs(transferableItems) do
        local bestLabelScore = 0
        local bestLabelIdx = nil
        local bestUnlabeledIdx = nil
        local bestUnlabeledCount = 0

        for i, data in ipairs(nearbyLockers) do
            if lockerItemCount[i] >= lockerMaxItems[i] then
                someFull = true
            else
                local labelScore = 0
                if lockerLabels[i] then
                    labelScore = scoreLockerMatch(lockerLabels[i], item.displayName)
                    if labelScore > bestLabelScore then
                        bestLabelScore = labelScore
                        bestLabelIdx = i
                    end
                end
                -- Type-count fallback: unlabeled lockers OR labeled lockers that don't match
                if labelScore == 0 then
                    local typeCount = lockerTypeData[i][item.typeName] or 0
                    if typeCount > 0 and typeCount > bestUnlabeledCount then
                        bestUnlabeledCount = typeCount
                        bestUnlabeledIdx = i
                    end
                end
            end
        end

        local bestIdx = bestLabelIdx or bestUnlabeledIdx

        if bestIdx then
            local data = nearbyLockers[bestIdx]
            local ok3 = pcall(function()
                playerInv:MoveItemBetweenInventories(item.itemId, item.inventoryId, data.inventoryId)
            end)
            if ok3 then
                containersUsed[bestIdx] = true
                lockerTypeData[bestIdx][item.typeName] = (lockerTypeData[bestIdx][item.typeName] or 0) + item.count
                lockerItemCount[bestIdx] = lockerItemCount[bestIdx] + 1
                utils.recordDetail(transferDetails, item.typeName, item.itemType, item.displayName, lockerLabels[bestIdx] or "Unlabeled")
            else
                local ok4 = pcall(function()
                    playerInv:MoveInventoryItem(data.inventory, item.itemId, playerInv)
                end)
                if ok4 then
                    containersUsed[bestIdx] = true
                    lockerTypeData[bestIdx][item.typeName] = (lockerTypeData[bestIdx][item.typeName] or 0) + item.count
                    lockerItemCount[bestIdx] = lockerItemCount[bestIdx] + 1
                    utils.recordDetail(transferDetails, item.typeName, item.itemType, item.displayName, lockerLabels[bestIdx] or "Unlabeled")
                end
            end
        end
    end

    local afterItems = playerInv:GetItems()
    local actualTransferred = totalItemsBefore - #afterItems
    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end
    return actualTransferred, numContainers, someFull, transferDetails
end

--- Show the appropriate notification for a quick-stack result
local function showResultNotification(actualTransferred, numContainers, someFull, swapCount, playerInv, totalItemsBefore)
    local function buildMessage(transferred, containers, full, swaps)
        local parts = {}
        if transferred > 0 then
            if full then
                table.insert(parts, L("stacked_full", transferred, containers))
            else
                table.insert(parts, L("stacked", transferred, containers))
            end
        end
        if swaps > 0 then
            table.insert(parts, L("swapped", swaps))
        end
        if #parts == 0 then
            if full then return L("no_match_full") end
            return L("no_match")
        end
        return table.concat(parts, " | ")
    end

    if actualTransferred <= 0 and numContainers > 0 then
        waitForReplication(playerInv, totalItemsBefore, function(confirmedCount)
            utils.Notify(buildMessage(confirmedCount, numContainers, someFull, swapCount), config)
        end)
    else
        utils.Notify(buildMessage(actualTransferred, numContainers, someFull, swapCount), config)
    end
end

--- Quick Stack: transfer matching items to nearby containers + battery swap
local function doQuickStack()
    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then
        utils.Notify(L("no_inventory"), config)
        return
    end

    -- Battery management runs first (terminal stash/swap/pull) so getTransferableItems
    -- sees the post-management inventory and correctly marks remaining excess as transferable
    local batteryStashCount, batteryPullCount = 0, 0
    local anyBatteryBudget = (config.RestockBatteryCount or 0) > 0 or (config.RestockPowerCellCount or 0) > 0
    if anyBatteryBudget then
        batteryStashCount, batteryPullCount = battery.doBatteryManagement(pawn, playerInv)
    end

    local transferableItems, totalItemsBefore = getTransferableItems(playerInv)

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local nearbyLockers, overflowLockers, excludedLockerInvs = utils.discoverNearbyContainers(pawn, radiusUnits, config)

    -- Legacy swap for types not managed by a budget (doBatterySwap skips managed types)
    local swapCount = battery.doBatterySwap(pawn, playerInv)

    -- Do item stacking
    local actualTransferred, numContainers, someFull, transferDetails = 0, 0, false, {}
    if #transferableItems > 0 and #nearbyLockers > 0 then
        actualTransferred, numContainers, someFull, transferDetails = transferToLockers(
            playerInv, transferableItems, totalItemsBefore, nearbyLockers)
    end

    -- Build restock candidates from all nearby locker inventories
    local restockCandidates = {}
    local restockEnabled = restockWithQuickstack and restock.isEnabled()
    if restockEnabled then
        local allLockerInvs = {}
        for _, data in ipairs(nearbyLockers) do table.insert(allLockerInvs, data.inventory) end
        for _, data in ipairs(overflowLockers) do table.insert(allLockerInvs, data.inventory) end
        for _, inv in ipairs(excludedLockerInvs) do table.insert(allLockerInvs, inv) end
        restockCandidates = restock.buildCandidates(allLockerInvs)
    end

    -- Function to show results (called after all passes complete)
    local function showResults(totalTransferred, totalContainers, overflowDetails, restockDetails)
        local restockCount = 0
        for _ in pairs(restockDetails or {}) do restockCount = restockCount + 1 end

        local batteryActivity = batteryStashCount + batteryPullCount

        if totalTransferred == 0 and swapCount == 0 and restockCount == 0 and batteryActivity == 0 and #nearbyLockers == 0 and #overflowLockers == 0 then
            utils.Notify(L("no_match"), config)
        elseif totalTransferred == 0 and swapCount == 0 and restockCount == 0 and batteryActivity == 0 then
            utils.Notify(L("nothing_to_stack"), config)
        else
            local parts = {}
            if totalTransferred > 0 then
                if someFull then
                    table.insert(parts, L("stacked_full", totalTransferred, totalContainers))
                else
                    table.insert(parts, L("stacked", totalTransferred, totalContainers))
                end
            end
            if swapCount > 0 then
                table.insert(parts, L("swapped", swapCount))
            end
            if batteryStashCount > 0 then
                table.insert(parts, L("battery_stashed", batteryStashCount))
            end
            if batteryPullCount > 0 then
                table.insert(parts, L("battery_pulled", batteryPullCount))
            end
            if restockCount > 0 then
                table.insert(parts, L("restocked", restockCount))
            end
            if #parts > 0 then
                utils.Notify(table.concat(parts, " | "), config)
            end
            showTransferSummary(transferDetails, overflowDetails, restockDetails)
        end
    end

    -- Nothing to do?
    local batteryActivity = batteryStashCount + batteryPullCount
    if #transferableItems == 0 and swapCount == 0 and batteryActivity == 0 and not restockEnabled then
        utils.Notify(L("nothing_to_stack"), config)
        return
    end

    -- If nothing to stash/swap but restock is enabled, skip straight to restock
    if #transferableItems == 0 and swapCount == 0 and batteryActivity == 0 and restockEnabled then
        local restockDetails = restock.execute(playerInv, restockCandidates)
        local restockCount = 0
        for _ in pairs(restockDetails) do restockCount = restockCount + 1 end
        if restockCount > 0 then
            utils.Notify(L("restocked", restockCount), config)
            showTransferSummary({}, {}, restockDetails)
        else
            utils.Notify(L("nothing_to_stack"), config)
        end
        return
    end

    -- Finalize: run restock pass then show results
    local function finalize(totalTransferred, totalContainers, overflowDetails)
        local restockDetails = restock.execute(playerInv, restockCandidates)
        showResults(totalTransferred, totalContainers, overflowDetails, restockDetails)
    end

    -- Pass 2: Overflow dump (only if overflow lockers exist and items remain)
    local function doOverflowPass(pass1Transferred, pass1Containers)
        if #overflowLockers == 0 then
            finalize(pass1Transferred, pass1Containers, {})
            return
        end

        -- Re-read player inventory after pass 1
        local remainingItems, remainingCount = getTransferableItems(playerInv)
        if #remainingItems == 0 then
            finalize(pass1Transferred, pass1Containers, {})
            return
        end

        -- Dump remaining items into overflow lockers
        local overflowItemCount = {}
        local overflowMaxItems = {}
        for i, data in ipairs(overflowLockers) do
            overflowItemCount[i] = 0
            local ok0, maxItems = pcall(function() return data.inventory.MaxItems end)
            overflowMaxItems[i] = (ok0 and maxItems) or DEFAULT_MAX_ITEMS
            local ok, items = pcall(function() return data.inventory:GetItems() end)
            if ok and items then
                overflowItemCount[i] = #items
            end
        end

        local overflowContainersUsed = {}
        local overflowDetails = {}
        for _, item in ipairs(remainingItems) do
            for i, data in ipairs(overflowLockers) do
                if overflowItemCount[i] < overflowMaxItems[i] then
                    local ok = pcall(function()
                        playerInv:MoveItemBetweenInventories(item.itemId, item.inventoryId, data.inventoryId)
                    end)
                    if ok then
                        overflowContainersUsed[i] = true
                        overflowItemCount[i] = overflowItemCount[i] + 1
                        utils.recordDetail(overflowDetails, item.typeName, item.itemType, item.displayName, data.label or "Overflow")
                        break
                    end
                end
            end
        end

        local overflowContainerCount = 0
        for _ in pairs(overflowContainersUsed) do overflowContainerCount = overflowContainerCount + 1 end

        -- Wait for overflow replication, then restock + show
        waitForReplication(playerInv, remainingCount, function(overflowTransferred)
            finalize(pass1Transferred + overflowTransferred, pass1Containers + overflowContainerCount, overflowDetails)
        end)
    end

    -- Wait for pass 1 replication if needed, then run overflow pass
    if actualTransferred <= 0 and numContainers > 0 then
        waitForReplication(playerInv, totalItemsBefore, function(confirmedCount)
            doOverflowPass(confirmedCount, numContainers)
        end)
    else
        doOverflowPass(actualTransferred, numContainers)
    end
end

--- Quick Stack into the currently open container (matching items only)
local function doQuickStackOpen()
    local containerInv = getOpenContainerInventory()
    if not containerInv then
        utils.Notify(L("no_container_open"), config)
        return
    end

    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then return end

    local transferableItems, totalItemsBefore = getTransferableItems(playerInv)
    if #transferableItems == 0 then
        utils.Notify(L("nothing_to_stack"), config)
        return
    end

    local containerTypes = {}
    local ok, containerItems = pcall(function() return containerInv:GetItems() end)
    if ok and containerItems then
        for _, item in ipairs(containerItems) do
            local s = item:get()
            local typeName = readItemTypeName(s)
            if typeName then containerTypes[typeName] = true end
        end
    end

    local targetId = containerInv.InventoryId
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
        waitForReplication(playerInv, totalItemsBefore, function(confirmedCount)
            if confirmedCount <= 0 then
                utils.Notify(L("no_match_container"), config)
            end
        end)
    end
end

--- Sort overflow: move items from %o lockers into nearby matching lockers
local function doSortOverflow()
    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then return end

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local targetLockers, overflowLockers = utils.discoverNearbyContainers(pawn, radiusUnits, config)

    if #overflowLockers == 0 then
        utils.Notify(L("no_overflow"), config)
        return
    end

    if #targetLockers == 0 then
        utils.Notify(L("no_target"), config)
        return
    end

    -- Snapshot target locker contents for type-count matching
    local targetTypeData = {}
    local targetItemCount = {}
    local targetMaxItems = {}
    local targetLabels = {}
    for i, data in ipairs(targetLockers) do
        targetTypeData[i] = {}
        targetLabels[i] = data.label
        targetItemCount[i] = 0
        local ok0, maxItems = pcall(function() return data.inventory.MaxItems end)
        targetMaxItems[i] = (ok0 and maxItems) or DEFAULT_MAX_ITEMS
        local ok, items = pcall(function() return data.inventory:GetItems() end)
        if ok and items then
            targetItemCount[i] = #items
            for _, item in ipairs(items) do
                local s = item:get()
                local typeName = readItemTypeName(s)
                if typeName then
                    targetTypeData[i][typeName] = (targetTypeData[i][typeName] or 0) + 1
                end
            end
        end
    end

    -- Sort items from each overflow locker into targets
    local transferDetails = {}
    local totalMoved = 0
    local containersUsed = {}
    local someFull = false

    for _, overflowData in ipairs(overflowLockers) do
        local ok, overflowItems = pcall(function() return overflowData.inventory:GetItems() end)
        if not ok or not overflowItems then goto nextOverflowLocker end
        local totalBeforeThisLocker = #overflowItems

        for _, rawItem in ipairs(overflowItems) do
            local s = rawItem:get()
            local info = readItemInfo(s)
            if not info then goto nextOverflowItem end

            local typeName = info.typeName
            local displayName = info.displayName

            -- Find best target (same scoring as main transfer)
            local bestLabelScore = 0
            local bestLabelIdx = nil
            local bestUnlabeledIdx = nil
            local bestUnlabeledCount = 0

            for i, data in ipairs(targetLockers) do
                if targetItemCount[i] >= targetMaxItems[i] then
                    someFull = true
                else
                    local labelScore = 0
                    if targetLabels[i] then
                        labelScore = scoreLockerMatch(targetLabels[i], displayName)
                        if labelScore > bestLabelScore then
                            bestLabelScore = labelScore
                            bestLabelIdx = i
                        end
                    end
                    if labelScore == 0 then
                        local typeCount = targetTypeData[i][typeName] or 0
                        if typeCount > 0 and typeCount > bestUnlabeledCount then
                            bestUnlabeledCount = typeCount
                            bestUnlabeledIdx = i
                        end
                    end
                end
            end

            local bestIdx = bestLabelIdx or bestUnlabeledIdx
            if bestIdx then
                local targetData = targetLockers[bestIdx]
                local ok3 = pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        s.ItemId, s.InventoryId, targetData.inventoryId)
                end)
                if ok3 then
                    containersUsed[bestIdx] = true
                    targetTypeData[bestIdx][typeName] = (targetTypeData[bestIdx][typeName] or 0) + 1
                    targetItemCount[bestIdx] = targetItemCount[bestIdx] + 1
                    totalMoved = totalMoved + 1
                    utils.recordDetail(transferDetails, typeName, s.ItemType, displayName, targetLabels[bestIdx] or "Unlabeled")
                end
            end

            ::nextOverflowItem::
        end

        ::nextOverflowLocker::
    end

    -- Route batteries from overflow to Battery Terminal
    local batteryRouted = battery.routeOverflowBatteriesToTerminal(pawn, playerInv, overflowLockers)

    if totalMoved == 0 and batteryRouted == 0 then
        utils.Notify(L("no_overflow_sorted"), config)
        return
    end

    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end

    -- Use waitForReplication on first overflow locker to confirm moves
    local firstOverflow = overflowLockers[1]
    local firstOverflowCount = 0
    pcall(function() firstOverflowCount = #firstOverflow.inventory:GetItems() end)

    -- Show results
    local parts = {}
    if totalMoved > 0 then
        if someFull then
            parts[#parts + 1] = L("sorted_full", totalMoved, numContainers)
        else
            parts[#parts + 1] = L("sorted", totalMoved, numContainers)
        end
    end
    if batteryRouted > 0 then
        parts[#parts + 1] = L("battery_stashed", batteryRouted)
    end

    utils.Notify(table.concat(parts, " | "), config)
    showTransferSummary(transferDetails)
end

--- Standalone restock: scan nearby lockers and restock consumables only
local function doRestockOnly()
    local pawn = utils.GetPlayerPawn()
    if not pawn then return end
    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then
        utils.Notify(L("no_inventory"), config)
        return
    end
    if not restock.isEnabled() then
        utils.Notify(L("nothing_to_restock"), config)
        return
    end

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local allLockerInvs = utils.findAllNearbyInvs(pawn, radiusUnits)
    if #allLockerInvs == 0 then
        utils.Notify(L("no_match"), config)
        return
    end

    local candidates = restock.buildCandidates(allLockerInvs)
    if #candidates == 0 then
        utils.Notify(L("nothing_to_restock"), config)
        return
    end

    local restockDetails = restock.execute(playerInv, candidates)
    local restockCount = 0
    for _ in pairs(restockDetails) do restockCount = restockCount + 1 end
    if restockCount > 0 then
        utils.Notify(L("restocked", restockCount), config)
        showTransferSummary({}, {}, restockDetails)
    else
        utils.Notify(L("nothing_to_restock"), config)
    end
end

--- Check if any text input field has keyboard focus
--- Suppresses hotkeys during label editing, F8 bug reports, chat, etc.
--- Does NOT suppress when inventory or container UI is open (no text input focused)
local function isTextInputFocused()
    local inputs = FindAllOf("EditableTextBox")
    if inputs then
        for _, widget in ipairs(inputs) do
            if widget:IsValid() then
                local ok, focused = pcall(function() return widget:HasKeyboardFocus() end)
                if ok and focused then return true end
            end
        end
    end
    return false
end

--- Override locker label character limit
--- The game defaults to 15 chars; patch at creation time via NotifyOnNewObject
--- so the limit is raised before any label text is loaded into the field
if config.LabelMaxChars and config.LabelMaxChars > 0 then
    NotifyOnNewObject("/Script/UWECommonUI.UWEEditableTextBoxWithValidation", function(editBox)
        pcall(function()
            editBox.MaxNumChars = config.LabelMaxChars
        end)
    end)
end

-- Keybind helper: wraps action in cooldown + text-input guard
local function registerCooldownBind(key, actionFn)
    RegisterKeyBind(key, function()
        ExecuteInGameThread(function()
            if isTextInputFocused() then return end
            local now = os.clock()
            if now - lastActivation < config.Cooldown then return end
            lastActivation = now
            config.refreshModSettings()
            actionFn()
        end)
    end)
end

-- Keybind registration (config.txt only — keybinds are set-and-forget)
registerCooldownBind(bindKey, doQuickStack)

local bindKeyOpen = keyMap[config.KeybindOpen]
if not bindKeyOpen then
    print(string.format("[QuickStack] ERROR: Unknown keybind_open '%s', defaulting to G\n", config.KeybindOpen))
    bindKeyOpen = Key.G
end
registerCooldownBind(bindKeyOpen, doQuickStackOpen)

local bindKeyOverflow = keyMap[config.KeybindOverflow]
if not bindKeyOverflow then
    print(string.format("[QuickStack] ERROR: Unknown keybind_overflow '%s', defaulting to H\n", config.KeybindOverflow))
    bindKeyOverflow = Key.H
end
registerCooldownBind(bindKeyOverflow, doSortOverflow)

-- Restock-only keybind (only registered when configured and different from quickstack key)
if not restockWithQuickstack and config.KeybindRestock ~= "" then
    local bindKeyRestock = keyMap[config.KeybindRestock]
    if not bindKeyRestock then
        print(string.format("[QuickStack] ERROR: Unknown keybind_restock '%s'\n", config.KeybindRestock))
    else
        registerCooldownBind(bindKeyRestock, doRestockOnly)
        print(string.format("[QuickStack] Restock keybind registered: %s\n", config.KeybindRestock))
    end
end
