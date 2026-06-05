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
local autolabel = require("autolabel")
local network = require("network")
local lang = require("lang")
local L = lang.L

categories.init(config)
battery.init(config)
restock.init(config)
ui.init(config)
autolabel.init(config)

local VERSION = "4.0.1"
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
        -- Controls
        { key="keybind", title='%s',
          description='%s',
          type="keybind", default="N" },
        { key="keybind_open", title='%s',
          description='%s',
          type="keybind", default="G" },
        { key="keybind_overflow", title='%s',
          description='%s',
          type="keybind", default="H" },

        -- Stacking
        { key="radius", title='%s',
          description='%s',
          type="slider", default=25, min=5, max=235, step=5, format="integer" },
        { key="stack_tools", title='%s',
          description='%s',
          type="toggle", default=false },
        { key="stack_equipment", title='%s',
          description='%s',
          type="toggle", default=false },
        { key="stack_consumables", title='%s',
          description='%s',
          type="toggle", default=false },

        -- Label routing
        { key="label_routing", title='%s',
          description='%s',
          type="toggle", default=true },

        -- Restock
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
        { key="battery_swap", title='%s',
          description='%s',
          type="toggle", default=true },

        -- Auto-label
        { key="auto_label_max", title='%s',
          description='%s',
          type="slider", default=0, min=0, max=5, step=1, format="integer" },

        -- Notifications
        { key="notify", title='%s',
          description='%s',
          type="toggle", default=true },
        { key="summary_panel", title='%s',
          description='%s',
          type="toggle", default=true },
        { key="summary_duration", title='%s',
          description='%s',
          type="slider", default=6, min=2, max=15, step=1, format="integer",
          enabled_by="summary_panel" },
        { key="summary_show_dest", title='%s',
          description='%s',
          type="toggle", default=true,
          enabled_by="summary_panel" },
        { key="summary_truncate", title='%s',
          description='%s',
          type="slider", default=20, min=0, max=50, step=5, format="integer",
          enabled_by="summary_panel" },
        { key="summary_position_left", title='%s',
          description='%s',
          type="toggle", default=false,
          enabled_by="summary_panel" },
        { key="summary_text_scale", title='%s',
          description='%s',
          type="slider", default=0.8, min=0.5, max=2.0, step=0.1, format="float",
          enabled_by="summary_panel" },

        -- Vehicle sourcing
        { key="sort_from_tadpole", title='%s',
          description='%s',
          type="toggle", default=false },

        -- Auto-sort
        { key="auto_sort_on_entry", title='%s',
          description='%s',
          type="toggle", default=false },
        { key="auto_sort_cooldown", title='%s',
          description='%s',
          type="slider", default=60, min=5, max=300, step=5, format="integer",
          enabled_by="auto_sort_on_entry" },
    },
}
]=],
        esc(L("mod_display")), VERSION,
        -- Controls
        esc(L("keybind_title")), esc(L("keybind_desc")),
        esc(L("keybind_open_title")), esc(L("keybind_open_desc")),
        esc(L("keybind_overflow_title")), esc(L("keybind_overflow_desc")),
        -- Stacking
        esc(L("radius_title")), esc(L("radius_desc")),
        esc(L("stack_tools_title")), esc(L("stack_tools_desc")),
        esc(L("stack_equip_title")), esc(L("stack_equip_desc")),
        esc(L("stack_consum_title")), esc(L("stack_consum_desc")),
        -- Label routing
        esc(L("label_routing_title")), esc(L("label_routing_desc")),
        -- Restock
        esc(L("food_title")), esc(L("food_desc")),
        esc(L("drink_title")), esc(L("drink_desc")),
        esc(L("heal_title")), esc(L("heal_desc")),
        esc(L("battery_budget_title")), esc(L("battery_budget_desc")),
        esc(L("powercell_budget_title")), esc(L("powercell_budget_desc")),
        esc(L("battery_swap_title")), esc(L("battery_swap_desc")),
        -- Auto-label
        esc(L("auto_label_title")), esc(L("auto_label_desc")),
        -- Notifications
        esc(L("notify_title")), esc(L("notify_desc")),
        esc(L("summary_title")), esc(L("summary_desc")),
        esc(L("summary_dur_title")), esc(L("summary_dur_desc")),
        esc(L("summary_dest_title")), esc(L("summary_dest_desc")),
        esc(L("summary_trunc_title")), esc(L("summary_trunc_desc")),
        esc(L("summary_left_title")), esc(L("summary_left_desc")),
        esc(L("summary_scale_title")), esc(L("summary_scale_desc")),
        -- Vehicle sourcing
        esc(L("tadpole_title")), esc(L("tadpole_desc")),
        -- Auto-sort
        esc(L("auto_sort_title")), esc(L("auto_sort_desc")),
        esc(L("auto_sort_cd_title")), esc(L("auto_sort_cd_desc"))
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
local waitForReplication = utils.waitForReplication
local showTransferSummary = ui.showTransferSummary

-- Constants
local DEFAULT_MAX_ITEMS = utils.DEFAULT_MAX_ITEMS

--- Get the inventory component of the currently open container
local function getOpenContainerInventory()
    -- Standard inventory tab (lockers, chests, etc.)
    local tabs = FindAllOf("WBP_TabInventory_C")
    if tabs then
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
    end

    -- Bioreactor screen (custom UI, not a standard inventory tab)
    local bioScreens = FindAllOf("WBP_BioreactorScreen_C")
    if bioScreens then
        for _, screen in ipairs(bioScreens) do
            if screen:IsValid() then
                local okA, active = pcall(function() return screen:IsActivated() end)
                if okA and active then
                    local pawn = utils.GetPlayerPawn()
                    if pawn then
                        local bioreactors = FindAllOf("SN2Bioreactor")
                        if bioreactors then
                            for _, br in ipairs(bioreactors) do
                                if br:IsValid() and utils.GetDistance(pawn, br) <= utils.MetersToUnits(config.Radius) then
                                    local okInv, inv = pcall(function() return br.InventoryComponent end)
                                    if okInv and inv and inv:IsValid() then
                                        return inv, true  -- true = skip keep rules
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, false
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
    local lockerTypeData, lockerItemCount, lockerMaxItems, lockerLabels = utils.snapshotLockerContents(nearbyLockers)

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

--- Route items from tadpole/portable locker source inventories to nearby base lockers.
--- Called after pass 1 + overflow so locker snapshots reflect current state.
local function doTadpoleSourcePass(playerInv, nearbyLockers, overflowLockers)
    local pawn = utils.GetPlayerPawn()
    if not pawn then return 0, {} end

    local tadpoleInvs = utils.findTadpoleSourceInventories(pawn, utils.MetersToUnits(config.Radius))
    if #tadpoleInvs == 0 then return 0, {} end

    -- Re-snapshot targets (pass 1 + overflow may have changed counts)
    local typeData, itemCount, maxItems, labels = utils.snapshotLockerContents(nearbyLockers)

    local overflowItemCount = {}
    local overflowMaxItems = {}
    for i, data in ipairs(overflowLockers) do
        local ok0, max = pcall(function() return data.inventory.MaxItems end)
        overflowMaxItems[i] = (ok0 and max) or DEFAULT_MAX_ITEMS
        overflowItemCount[i] = 0
        local ok, items = pcall(function() return data.inventory:GetItems() end)
        if ok and items then overflowItemCount[i] = #items end
    end

    local totalMoved = 0
    local details = {}

    for _, tadpoleInv in ipairs(tadpoleInvs) do
        local ok, items = pcall(function() return tadpoleInv:GetItems() end)
        if not ok or not items then goto nextInv end

        for _, rawItem in ipairs(items) do
            local s = rawItem:get()
            local info = readItemInfo(s)
            if not info then goto nextItem end

            -- Respect category protection flags (same items the player protects shouldn't route from vehicles)
            local skipItem = false
            pcall(function()
                if not config.StackConsumables and categories.getConsumableCategory(info.typeName) then
                    skipItem = true
                elseif not config.StackTools and type(info.fullName) == "string" and string.find(string.lower(info.fullName), "/tools/", 1, true) then
                    skipItem = true
                elseif not config.StackEquipment then
                    if categories.isBatteryType(info.typeName) then
                        skipItem = true
                    elseif type(info.fullName) == "string" then
                        local lpath = string.lower(info.fullName)
                        if string.find(lpath, "/equipment/", 1, true) or string.find(lpath, "/equippable/", 1, true) or string.find(lpath, "/deployables/", 1, true) then
                            skipItem = true
                        end
                    end
                end
            end)
            if skipItem then goto nextItem end

            -- Label + type-count scoring (same as transferToLockers)
            local bestLabelScore = 0
            local bestLabelIdx = nil
            local bestUnlabeledIdx = nil
            local bestUnlabeledCount = 0

            for i = 1, #nearbyLockers do
                if itemCount[i] < maxItems[i] then
                    local labelScore = 0
                    if labels[i] then
                        labelScore = scoreLockerMatch(labels[i], info.displayName)
                        if labelScore > bestLabelScore then
                            bestLabelScore = labelScore
                            bestLabelIdx = i
                        end
                    end
                    if labelScore == 0 then
                        local tc = typeData[i][info.typeName] or 0
                        if tc > 0 and tc > bestUnlabeledCount then
                            bestUnlabeledCount = tc
                            bestUnlabeledIdx = i
                        end
                    end
                end
            end

            local bestIdx = bestLabelIdx or bestUnlabeledIdx

            if bestIdx then
                local ok3 = pcall(function()
                    playerInv:MoveItemBetweenInventories(info.itemId, info.inventoryId, nearbyLockers[bestIdx].inventoryId)
                end)
                if ok3 then
                    typeData[bestIdx][info.typeName] = (typeData[bestIdx][info.typeName] or 0) + 1
                    itemCount[bestIdx] = itemCount[bestIdx] + 1
                    totalMoved = totalMoved + 1
                    utils.recordDetail(details, info.typeName, info.itemType, info.displayName, labels[bestIdx] or "Unlabeled")
                    goto nextItem
                end
            end

            -- Overflow fallback
            for i, data in ipairs(overflowLockers) do
                if overflowItemCount[i] < overflowMaxItems[i] then
                    local ok3 = pcall(function()
                        playerInv:MoveItemBetweenInventories(info.itemId, info.inventoryId, data.inventoryId)
                    end)
                    if ok3 then
                        overflowItemCount[i] = overflowItemCount[i] + 1
                        totalMoved = totalMoved + 1
                        utils.recordDetail(details, info.typeName, info.itemType, info.displayName, data.label or "Overflow")
                        break
                    end
                end
            end

            ::nextItem::
        end
        ::nextInv::
    end

    return totalMoved, details
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

    -- Battery management always runs on quickstack (N key), not tied to restock keybind.
    -- Runs first so getTransferableItems sees the post-management inventory.
    local batteryStashCount, batteryPullCount = 0, 0
    local batteryDetails = {}
    local tadpoleMoved, tadpoleDetails = 0, {}
    local anyBatteryBudget = (config.RestockBatteryCount or 0) > 0 or (config.RestockPowerCellCount or 0) > 0
    if anyBatteryBudget then
        batteryStashCount, batteryPullCount, _, batteryDetails = battery.doBatteryManagement(pawn, playerInv)
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

    -- Restock runs with quickstack unless a separate restock keybind is configured
    local restockWithQuickstack = (config.KeybindRestock == "" or config.KeybindRestock == config.Keybind)

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

    -- Merge battery details into restock details for the summary panel
    local function mergeDetails(target, source)
        for k, v in pairs(source) do
            if not target[k] then
                target[k] = v
            else
                target[k].count = target[k].count + v.count
                for label in pairs(v.containers) do target[k].containers[label] = true end
            end
        end
    end

    -- Function to show results (called after all passes complete)
    local function showResults(totalTransferred, totalContainers, overflowDetails, restockDetails)
        local restockCount = 0
        for _ in pairs(restockDetails or {}) do restockCount = restockCount + 1 end

        local batteryActivity = batteryStashCount + batteryPullCount

        if totalTransferred == 0 and swapCount == 0 and restockCount == 0 and batteryActivity == 0 and tadpoleMoved == 0 and #nearbyLockers == 0 and #overflowLockers == 0 then
            utils.Notify(L("no_match"), config)
        elseif totalTransferred == 0 and swapCount == 0 and restockCount == 0 and batteryActivity == 0 and tadpoleMoved == 0 then
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
            if tadpoleMoved > 0 then
                table.insert(parts, L("tadpole_sourced", tadpoleMoved))
            end
            if restockCount > 0 then
                table.insert(parts, L("restocked", restockCount))
            end
            if #parts > 0 then
                utils.Notify(table.concat(parts, " | "), config)
            end
            mergeDetails(transferDetails, tadpoleDetails)
            mergeDetails(restockDetails, batteryDetails)
            showTransferSummary(transferDetails, overflowDetails, restockDetails)
        end
    end

    -- Nothing to do?
    local batteryActivity = batteryStashCount + batteryPullCount
    if #transferableItems == 0 and swapCount == 0 and batteryActivity == 0 and not restockEnabled and not config.SortFromTadpole then
        utils.Notify(L("nothing_to_stack"), config)
        return
    end

    -- If nothing to stash/swap but restock is enabled, skip straight to restock
    if #transferableItems == 0 and swapCount == 0 and batteryActivity == 0 and restockEnabled and not config.SortFromTadpole then
        local restockDetails = restock.execute(playerInv, restockCandidates)
        mergeDetails(restockDetails, batteryDetails)
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

    -- Finalize: run tadpole source pass, then restock, then show results
    local function finalize(totalTransferred, totalContainers, overflowDetails)
        if config.SortFromTadpole then
            tadpoleMoved, tadpoleDetails = doTadpoleSourcePass(playerInv, nearbyLockers, overflowLockers)
        end
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
    local containerInv, skipKeepRules = getOpenContainerInventory()
    if not containerInv then
        utils.Notify(L("no_container_open"), config)
        return
    end

    local pawn = utils.GetPlayerPawn()
    if not pawn then return end

    local playerInv = pawn.InventoryComponent
    if not playerInv or not playerInv:IsValid() then return end

    -- Bioreactor etc.: skip keep rules so consumables/equipment can be deposited
    local transferableItems, totalItemsBefore
    if skipKeepRules then
        local items = playerInv:GetItems()
        totalItemsBefore = #items
        transferableItems = {}
        for _, playerItem in ipairs(items) do
            local s = playerItem:get()
            local itemData = readItemInfo(s)
            if itemData then
                table.insert(transferableItems, itemData)
            end
        end
    else
        transferableItems, totalItemsBefore = getTransferableItems(playerInv)
    end
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

    -- Route batteries to terminals FIRST (chargers have priority over lockers)
    local batteryRouted, batteryMovedIds = battery.routeOverflowBatteriesToTerminal(pawn, playerInv, overflowLockers)

    -- Snapshot target locker contents for type-count matching
    local targetTypeData, targetItemCount, targetMaxItems, targetLabels = utils.snapshotLockerContents(targetLockers)

    -- Sort remaining items from overflow lockers into targets (skip batteries already routed)
    local transferDetails = {}
    local totalMoved = 0
    local containersUsed = {}
    local someFull = false

    for _, overflowData in ipairs(overflowLockers) do
        local ok, overflowItems = pcall(function() return overflowData.inventory:GetItems() end)
        if not ok or not overflowItems then goto nextOverflowLocker end

        for _, rawItem in ipairs(overflowItems) do
            local s = rawItem:get()
            -- Skip items already routed to terminals
            if batteryMovedIds[s.ItemId] then goto nextOverflowItem end

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

-- Dynamic keybind dispatch: register ALL possible keys, dispatch by current config.
-- UE4SS has no UnregisterKeyBind, so static registration can't adapt to SN2ModSettings
-- changes. Instead, every key in keyMap gets a handler that does an O(1) table lookup.
-- Unbound keys hit nil and return instantly — no ExecuteInGameThread, no overhead.
local activeBindings = {}  -- keyStr -> actionFn

local function rebuildBindings()
    activeBindings = {}
    -- Priority order: first bind wins if user accidentally assigns the same key twice
    local function bind(keyStr, action)
        if keyStr and keyStr ~= "" and not activeBindings[keyStr] then
            activeBindings[keyStr] = action
        end
    end
    bind(config.Keybind, doQuickStack)
    bind(config.KeybindOpen, doQuickStackOpen)
    bind(config.KeybindOverflow, doSortOverflow)
    local rws = (config.KeybindRestock == "" or config.KeybindRestock == config.Keybind)
    if not rws then
        bind(config.KeybindRestock, doRestockOnly)
    end
end

rebuildBindings()

for keyStr, keyConst in pairs(keyMap) do
    RegisterKeyBind(keyConst, function()
        local action = activeBindings[keyStr]
        if not action then return end
        ExecuteInGameThread(function()
            if isTextInputFocused() then return end
            local now = os.clock()
            if now - lastActivation < config.Cooldown then return end
            lastActivation = now
            config.refreshModSettings()
            rebuildBindings()
            -- Re-check: key might no longer be bound after settings refresh
            action = activeBindings[keyStr]
            if not action then return end
            autolabel.suppress = true
            action()
            -- Delay clearing to cover async callbacks (waitForReplication)
            ExecuteWithDelay(2000, function()
                ExecuteInGameThread(function()
                    autolabel.suppress = false
                end)
            end)
        end)
    end)
end

-- Delayed refresh: pick up SN2ModSettings keybind values after it loads.
-- QuickStack loads before SN2ModSettings alphabetically (Q < S), so shared
-- variables aren't populated yet at require() time.
ExecuteWithDelay(3000, function()
    ExecuteInGameThread(function()
        config.refreshModSettings()
        rebuildBindings()
    end)
end)

-- Network handlers: host executes operations on behalf of clients
network.onMessage("SETLABEL", function(senderPC, payload)
    -- payload: lockerIndex|labelText (index into FindAllOf("SN2Locker"))
    -- Client sends locker inventoryId + label text, host finds locker and sets label
    local invIdStr, labelText = payload:match("^([^|]+)|(.*)")
    local targetInvId = tonumber(invIdStr)
    if not targetInvId or not labelText then return end

    local lockers = FindAllOf("SN2Locker")
    if not lockers then return end
    for _, locker in ipairs(lockers) do
        if locker:IsValid() then
            local okInv, inv = pcall(function() return locker.Inventory end)
            if okInv and inv and inv:IsValid() and inv.InventoryId == targetInvId then
                pcall(function()
                    local ugc = locker.UGCComponent
                    if ugc and ugc:IsValid() then
                        ugc:ServerSetPlayerText({ TagName = FName("None") }, labelText)
                    end
                end)
                break
            end
        end
    end
end)

-- Auto-sort on base entry: fires once per outside→inside transition
-- Always registered (fires ~2-4 times per session), config checked in callback
do
    -- Arm wasInBase=true so the FIRST UpdateIsInBase after a world load is treated as the
    -- spawn/join, not a deliberate entry. If you actually load OUTSIDE a base, the base-power
    -- VM fires (false) and self-corrects below; a real outside->inside walk then fires the sort.
    -- This must re-arm on every world load (initial, save reload, AND client joining a session)
    -- -- a startup-only timer doesn't, because an MP client joins minutes after the mod loads,
    -- long after any startup window, so the join transition would auto-sort/restock on join.
    local wasInBase = true
    local lastAutoSort = 0

    -- Lua-flag only -- safe inside the map-load teardown hook (NO UObject access here).
    RegisterLoadMapPostHook(function()
        wasInBase = true
    end)

    RegisterCustomEvent("UpdateIsInBase", function(self, inBase)
        local isInBase = inBase:get()
        if isInBase and not wasInBase then
            wasInBase = true
            config.refreshModSettings()
            if config.AutoSortOnEntry then
                local now = os.clock()
                if now - lastAutoSort >= config.AutoSortCooldown then
                    lastAutoSort = now
                    autolabel.suppress = true
                    doQuickStack()
                    ExecuteWithDelay(2000, function()
                        ExecuteInGameThread(function()
                            autolabel.suppress = false
                        end)
                    end)
                end
            end
        else
            wasInBase = isInBase
        end
    end)
end
