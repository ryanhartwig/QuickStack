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
local ui = require("ui")

categories.init(config)
ui.init(config)

local VERSION = "3.3.1"
print(string.format("[QuickStack] v%s loaded\n", VERSION))

-- Write SN2ModSettings manifest if the mod is installed (optional integration)
do
    local SN2_DIR = "./ue4ss/Mods/SN2ModSettings/"
    local REG_DIR = SN2_DIR .. "registrations/"
    local MANIFEST_CONTENT = string.format([=[return {
    name     = "QuickStack",
    display  = "Quick Stack",
    version  = "%s",
    github   = "ryanhartwig/QuickStack",
    nexus_id = "128",
    settings = {
        { key="radius", title="Scan Radius (meters)",
          description="How far to search for containers when quick-stacking. Game limit is ~235m.",
          type="slider", default=25, min=5, max=200, step=5, format="integer" },

        { key="battery_swap", title="Battery Swap",
          description="Auto-swap drained batteries with higher-charged ones from nearby chargers.",
          type="toggle", default=true },

        { key="restock_food_count", title="Food Budget",
          description="How many food items to restock after quick-stacking. Set to 0 to disable.",
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="restock_drink_count", title="Drink Budget",
          description="How many drink items to restock after quick-stacking. Set to 0 to disable.",
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="restock_heal_count", title="Heal Budget",
          description="How many healing items to restock after quick-stacking. Set to 0 to disable.",
          type="slider", default=2, min=0, max=10, step=1, format="integer" },

        { key="summary_panel", title="Summary Panel",
          description="Show the visual transfer summary panel with item icons after quick-stacking.",
          type="toggle", default=true },
        { key="summary_duration", title="Summary Duration (seconds)",
          description="How long the summary panel stays on screen.",
          type="slider", default=6, min=2, max=15, step=1, format="integer",
          enabled_by="summary_panel" },
    },
}
]=], VERSION)

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
                -- Write our manifest
                local f = io.open(REG_DIR .. "QuickStack.lua", "w")
                if f then
                    f:write(MANIFEST_CONTENT)
                    f:close()
                    print(string.format("[QuickStack] SN2ModSettings manifest written (attempt %d/%d)\n",
                        attempts, MAX_ATTEMPTS))
                end
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

-- Cooldown state
local lastActivation = 0

-- Module aliases for frequently used functions
local isBatteryType = categories.isBatteryType
local readCharge = categories.readCharge
local shouldKeepItem = categories.shouldKeepItem
local scoreLockerMatch = matching.scoreLockerMatch
local waitForReplication = ui.waitForReplication
local showTransferSummary = ui.showTransferSummary

--- Read the user-set label from a locker's UGCComponent
local function getLockerLabel(actor)
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

    for _, playerItem in ipairs(items) do
        local s = playerItem:get()
        if s.ItemType then
            local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok then
                local ok2, fullName = pcall(function() return s.ItemType:GetFullName() end)
                local fName = ok2 and fullName or ""

                local displayName = nil
                pcall(function() displayName = s.ItemType.Name:ToString() end)
                if not displayName or displayName == "" then
                    displayName = typeName:gsub("^DA_", ""):gsub("_ItemType$", "")
                end

                local itemData = {
                    typeName = typeName,
                    displayName = displayName,
                    fullName = fName,
                    itemId = s.ItemId,
                    inventoryId = s.InventoryId,
                    itemType = s.ItemType,
                    count = s.Count or 1,
                }

                if not shouldKeepItem(typeName, fName) then
                    table.insert(transferable, itemData)
                else
                    -- Track consumables for budget trimming
                    local cat = categories.getConsumableCategory(typeName)
                    if cat then
                        itemData.category = cat
                        itemData.priority = categories.getPriority(typeName, cat)
                        table.insert(heldConsumables, itemData)
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
    local transferDetails = {}  -- keyed by typeName: { itemType, count, containers }

    local function recordTransfer(item, lockerIdx)
        local label = lockerLabels[lockerIdx] or "Unlabeled"
        if not transferDetails[item.typeName] then
            transferDetails[item.typeName] = {
                itemType = item.itemType,
                displayName = item.displayName,
                count = 0,
                containers = {},
            }
        end
        transferDetails[item.typeName].count = transferDetails[item.typeName].count + 1
        transferDetails[item.typeName].containers[label] = true
    end

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
                recordTransfer(item, bestIdx)
            else
                local ok4 = pcall(function()
                    playerInv:MoveInventoryItem(data.inventory, item.itemId, playerInv)
                end)
                if ok4 then
                    containersUsed[bestIdx] = true
                    lockerTypeData[bestIdx][item.typeName] = (lockerTypeData[bestIdx][item.typeName] or 0) + item.count
                    lockerItemCount[bestIdx] = lockerItemCount[bestIdx] + 1
                    recordTransfer(item, bestIdx)
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

--- Battery swap: for each battery/power cell in player inventory,
--- check nearby chargers for a higher-charge replacement and swap
local function doBatterySwap(pawn, playerInv)
    if not config.BatterySwap then return 0 end

    local playerLoc = pawn:K2_GetActorLocation()
    local radiusUnits = utils.MetersToUnits(config.Radius)

    -- Find chargers — whitelist known charger classes to avoid stripping vehicles (Tadpole etc.)
    local CHARGER_CLASSES = {
        BP_BasicBatteryTerminal_C = true,
        BP_PowerCellTerminal_C = true,
    }
    local chargers = FindAllOf("UWEPowerTerminal")
    if not chargers then return 0 end

    -- Collect nearby charger inventories (only whitelisted terminal classes)
    local chargerInvs = {}
    for _, charger in ipairs(chargers) do
        if charger:IsValid() then
            local okCls, className = pcall(function() return charger:GetClass():GetFName():ToString() end)
            if okCls and CHARGER_CLASSES[className] then
                local dist = utils.GetDistance(pawn, charger)
                if dist <= radiusUnits then
                    local ok, inv = pcall(function() return charger.InventoryComponent end)
                    if ok and inv and inv:IsValid() then
                        table.insert(chargerInvs, inv)
                    end
                end
            end
        end
    end

    if #chargerInvs == 0 then return 0 end

    -- Get player batteries with charge info
    local playerItems = playerInv:GetItems()
    local playerBatteries = {}
    for _, item in ipairs(playerItems) do
        local s = item:get()
        if s.ItemType then
            local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok and isBatteryType(typeName) then
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
    for _, chargerInv in ipairs(chargerInvs) do
        local ok, chargerItems = pcall(function() return chargerInv:GetItems() end)
        if ok and chargerItems then
            for _, cItem in ipairs(chargerItems) do
                local cs = cItem:get()
                if cs.ItemType then
                    local ok2, cTypeName = pcall(function() return cs.ItemType:GetFName():ToString() end)
                    if ok2 and isBatteryType(cTypeName) then
                        local cCurrent, cMax = readCharge(cs)
                        if cCurrent and cMax then
                            table.insert(chargerBatteries, {
                                typeName = cTypeName,
                                charge = cCurrent,
                                itemId = cs.ItemId,
                                inventoryId = cs.InventoryId,
                                chargerInv = chargerInv,
                                used = false,
                            })
                        end
                    end
                end
            end
        end
    end

    local swapCount = 0

    -- Sort player batteries lowest charge first (swap worst ones first)
    table.sort(playerBatteries, function(a, b) return a.chargePercent < b.chargePercent end)

    for _, playerBat in ipairs(playerBatteries) do
        if playerBat.chargePercent >= 0.99 then goto nextBattery end

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

            -- Step 1: Move player battery to charger
            local ok1 = pcall(function()
                playerInv:MoveItemBetweenInventories(
                    playerBat.itemId, playerBat.inventoryId, cb.chargerInv.InventoryId)
            end)

            if ok1 then
                -- Step 2: Move charger battery to player
                local ok2 = pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        cb.itemId, cb.inventoryId, playerInv.InventoryId)
                end)

                if ok2 then
                    swapCount = swapCount + 1
                    cb.used = true
                else
                    -- Rollback
                    pcall(function()
                        playerInv:MoveItemBetweenInventories(
                            playerBat.itemId, cb.chargerInv.InventoryId, playerBat.inventoryId)
                    end)
                end
            end
        end

        ::nextBattery::
    end

    return swapCount
end

--- Show the appropriate notification for a quick-stack result
local function showResultNotification(actualTransferred, numContainers, someFull, swapCount, playerInv, totalItemsBefore)
    local function buildMessage(transferred, containers, full, swaps)
        local parts = {}
        if transferred > 0 then
            local itm = transferred == 1 and "item" or "items"
            local ctr = containers == 1 and "container" or "containers"
            if full then
                table.insert(parts, string.format("Quick Stacked %d %s to %d %s (some full)", transferred, itm, containers, ctr))
            else
                table.insert(parts, string.format("Quick Stacked %d %s to %d %s", transferred, itm, containers, ctr))
            end
        end
        if swaps > 0 then
            local bat = swaps == 1 and "battery" or "batteries"
            table.insert(parts, string.format("Swapped %d %s", swaps, bat))
        end
        if #parts == 0 then
            if full then return "No matching containers nearby (some full)" end
            return "No matching containers nearby"
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
        utils.Notify("Error: Could not find player inventory", config)
        return
    end

    local transferableItems, totalItemsBefore = getTransferableItems(playerInv)

    -- Whitelisted container classes
    local containerSources = {
        { class = "SN2Locker",          getInv = function(a) return a.Inventory end,          hasLabel = true },
        { class = "BP_Tailing_Chest_C", getInv = function(a) return a.InventoryComponent end, hasLabel = false },
    }

    local playerLoc = pawn:K2_GetActorLocation()
    local radiusUnits = utils.MetersToUnits(config.Radius)
    local nearbyLockers = {}
    local overflowLockers = {}
    local excludedLockerInvs = {}  -- for restock: %x lockers still have food/water

    for _, source in ipairs(containerSources) do
        local actors = FindAllOf(source.class)
        if actors then
            for _, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = utils.GetDistance(pawn, actor)
                    if dist <= radiusUnits then
                        local ok, inv = pcall(function() return source.getInv(actor) end)
                        if ok and inv and inv:IsValid() then
                            -- Read label if this container type supports it
                            local rawLabel = nil
                            if source.hasLabel then
                                local ok2, lbl = pcall(function() return getLockerLabel(actor) end)
                                if ok2 then rawLabel = lbl end
                            end

                            -- Check exclusion prefix — skip this container for stacking
                            if rawLabel and config.ExcludePrefix ~= "" then
                                if rawLabel:sub(1, #config.ExcludePrefix) == config.ExcludePrefix then
                                    table.insert(excludedLockerInvs, inv)
                                    goto nextActor
                                end
                            end

                            -- Check overflow prefix — collect separately
                            if rawLabel and config.OverflowPrefix ~= "" then
                                if rawLabel:sub(1, #config.OverflowPrefix) == config.OverflowPrefix then
                                    table.insert(overflowLockers, {
                                        inventory = inv,
                                        inventoryId = inv.InventoryId,
                                        label = rawLabel,
                                    })
                                    goto nextActor
                                end
                            end

                            local label = nil
                            if rawLabel and config.LabelRouting then
                                if rawLabel then
                                    if config.LabelPrefix == "" then
                                        label = rawLabel
                                    else
                                        local prefixLen = #config.LabelPrefix
                                        if rawLabel:sub(1, prefixLen) == config.LabelPrefix then
                                            label = rawLabel:sub(prefixLen + 1):match("^%s*(.-)%s*$")
                                            if label == "" then label = nil end
                                        end
                                    end
                                end
                            end
                            table.insert(nearbyLockers, {
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

    -- Do battery swap (runs regardless of whether there are lockers)
    local swapCount = doBatterySwap(pawn, playerInv)

    -- Do item stacking
    local actualTransferred, numContainers, someFull, transferDetails = 0, 0, false, {}
    if #transferableItems > 0 and #nearbyLockers > 0 then
        actualTransferred, numContainers, someFull, transferDetails = transferToLockers(
            playerInv, transferableItems, totalItemsBefore, nearbyLockers)
    end

    -- Scan ALL nearby lockers (including %o and %x) for restock candidates
    local restockCandidates = {}
    local restockEnabled = (config.RestockFoodCount or 0) > 0 or (config.RestockDrinkCount or 0) > 0 or (config.RestockHealCount or 0) > 0
    if restockEnabled then
        -- Combine all locker inventories: normal + overflow + excluded
        local allLockerInvs = {}
        for _, data in ipairs(nearbyLockers) do table.insert(allLockerInvs, data.inventory) end
        for _, data in ipairs(overflowLockers) do table.insert(allLockerInvs, data.inventory) end
        for _, inv in ipairs(excludedLockerInvs) do table.insert(allLockerInvs, inv) end

        for _, inv in ipairs(allLockerInvs) do
            local ok, items = pcall(function() return inv:GetItems() end)
            if ok and items then
                for _, item in ipairs(items) do
                    local s = item:get()
                    if s.ItemType then
                        local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                        if ok2 then
                            local category = categories.getConsumableCategory(typeName)
                            if category then
                                local displayName = nil
                                pcall(function() displayName = s.ItemType.Name:ToString() end)
                                table.insert(restockCandidates, {
                                    itemId = s.ItemId,
                                    inventoryId = s.InventoryId,
                                    typeName = typeName,
                                    displayName = displayName or typeName:gsub("^DA_", ""):gsub("_ItemType$", ""),
                                    itemType = s.ItemType,
                                    category = category,
                                    priority = categories.getPriority(typeName, category),
                                    lockerInv = inv,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    --- Restock pass: pull consumables from nearby lockers to fill budgets
    local function doRestockPass(restockDetails)
        local restockEnabled = (config.RestockFoodCount or 0) > 0 or (config.RestockDrinkCount or 0) > 0 or (config.RestockHealCount or 0) > 0
        if not restockEnabled or #restockCandidates == 0 then return restockDetails end

        local playerInvId = playerInv.InventoryId

        local function recordRestock(candidate)
            if not restockDetails[candidate.typeName] then
                restockDetails[candidate.typeName] = {
                    itemType = candidate.itemType,
                    displayName = candidate.displayName,
                    count = 0,
                    containers = {},
                }
            end
            restockDetails[candidate.typeName].count = restockDetails[candidate.typeName].count + 1
            restockDetails[candidate.typeName].containers["Locker"] = true
        end

        -- Scan player's current consumables with full item data
        local heldByCategory = { food = {}, drink = {}, heal = {} }
        local currentCounts = { food = 0, drink = 0, heal = 0 }
        local playerItems = playerInv:GetItems()
        for _, item in ipairs(playerItems) do
            local s = item:get()
            if s.ItemType then
                local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                if ok then
                    local cat = categories.getConsumableCategory(typeName)
                    if cat then
                        currentCounts[cat] = currentCounts[cat] + 1
                        table.insert(heldByCategory[cat], {
                            itemId = s.ItemId,
                            inventoryId = s.InventoryId,
                            typeName = typeName,
                            priority = categories.getPriority(typeName, cat),
                        })
                    end
                end
            end
        end

        -- Sort candidates best first, held items worst first
        table.sort(restockCandidates, function(a, b) return a.priority < b.priority end)
        for _, items in pairs(heldByCategory) do
            table.sort(items, function(a, b) return a.priority > b.priority end)
        end

        -- Phase 1: Fill shortfalls (pull best from lockers)
        local budgets = {
            food  = math.max(0, (config.RestockFoodCount or 0)  - currentCounts.food),
            drink = math.max(0, (config.RestockDrinkCount or 0) - currentCounts.drink),
            heal  = math.max(0, (config.RestockHealCount or 0)  - currentCounts.heal),
        }

        local usedCandidates = {}
        for i, candidate in ipairs(restockCandidates) do
            local cat = candidate.category
            if budgets[cat] and budgets[cat] > 0 then
                local ok = pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        candidate.itemId, candidate.inventoryId, playerInvId)
                end)
                if ok then
                    budgets[cat] = budgets[cat] - 1
                    usedCandidates[i] = true
                    recordRestock(candidate)
                end
            end
        end

        -- Phase 2: Upgrade — swap player's worst for locker's best if better
        for _, cat in ipairs({"food", "drink", "heal"}) do
            local held = heldByCategory[cat]
            if #held == 0 then goto nextCat end

            for _, candidate in ipairs(restockCandidates) do
                if usedCandidates[_] then goto nextCandidate end
                if candidate.category ~= cat then goto nextCandidate end

                -- Find player's worst item in this category
                local worst = held[1]  -- sorted worst first
                if not worst or candidate.priority >= worst.priority then
                    break  -- no upgrade possible (candidates sorted best first)
                end

                -- Swap: stash worst to candidate's source locker, pull candidate
                local stashOk = pcall(function()
                    playerInv:MoveItemBetweenInventories(
                        worst.itemId, worst.inventoryId, candidate.inventoryId)
                end)
                if stashOk then
                    local pullOk = pcall(function()
                        playerInv:MoveItemBetweenInventories(
                            candidate.itemId, candidate.inventoryId, playerInvId)
                    end)
                    if pullOk then
                        usedCandidates[_] = true
                        table.remove(held, 1)  -- remove worst from tracking
                        recordRestock(candidate)
                    else
                        -- Pull failed, reverse the stash
                        pcall(function()
                            playerInv:MoveItemBetweenInventories(
                                worst.itemId, candidate.inventoryId, worst.inventoryId)
                        end)
                    end
                end

                ::nextCandidate::
            end

            ::nextCat::
        end

        return restockDetails
    end

    -- Function to show results (called after all passes complete)
    local function showResults(totalTransferred, totalContainers, overflowDetails, restockDetails)
        local restockCount = 0
        for _ in pairs(restockDetails or {}) do restockCount = restockCount + 1 end

        if totalTransferred == 0 and swapCount == 0 and restockCount == 0 and #nearbyLockers == 0 and #overflowLockers == 0 then
            utils.Notify("No matching containers nearby", config)
        elseif totalTransferred == 0 and swapCount == 0 and restockCount == 0 then
            utils.Notify("Nothing to stack", config)
        else
            local parts = {}
            if totalTransferred > 0 then
                local itm = totalTransferred == 1 and "item" or "items"
                local ctr = totalContainers == 1 and "container" or "containers"
                if someFull then
                    table.insert(parts, string.format("Quick Stacked %d %s to %d %s (some full)", totalTransferred, itm, totalContainers, ctr))
                else
                    table.insert(parts, string.format("Quick Stacked %d %s to %d %s", totalTransferred, itm, totalContainers, ctr))
                end
            end
            if swapCount > 0 then
                local bat = swapCount == 1 and "battery" or "batteries"
                table.insert(parts, string.format("Swapped %d %s", swapCount, bat))
            end
            if restockCount > 0 then
                local ritm = restockCount == 1 and "type" or "types"
                table.insert(parts, string.format("Restocked %d %s", restockCount, ritm))
            end
            if #parts > 0 then
                utils.Notify(table.concat(parts, " | "), config)
            end
            showTransferSummary(transferDetails, overflowDetails, restockDetails)
        end
    end

    -- Nothing to do?
    local restockEnabled = (config.RestockFoodCount or 0) > 0 or (config.RestockDrinkCount or 0) > 0 or (config.RestockHealCount or 0) > 0
    if #transferableItems == 0 and swapCount == 0 and not restockEnabled then
        utils.Notify("Nothing to stack", config)
        return
    end

    -- If nothing to stash/swap but restock is enabled, skip straight to restock
    if #transferableItems == 0 and swapCount == 0 and restockEnabled then
        local restockDetails = doRestockPass({})
        local restockCount = 0
        for _ in pairs(restockDetails) do restockCount = restockCount + 1 end
        if restockCount > 0 then
            local ritm = restockCount == 1 and "type" or "types"
            utils.Notify(string.format("Restocked %d %s", restockCount, ritm), config)
            showTransferSummary({}, {}, restockDetails)
        else
            utils.Notify("Nothing to stack", config)
        end
        return
    end

    -- Finalize: run restock pass then show results
    local function finalize(totalTransferred, totalContainers, overflowDetails)
        local restockDetails = doRestockPass({})
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
            overflowMaxItems[i] = (ok0 and maxItems) or 30
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
                        if not overflowDetails[item.typeName] then
                            overflowDetails[item.typeName] = {
                                itemType = item.itemType,
                                displayName = item.displayName,
                                count = 0,
                                containers = {},
                            }
                        end
                        overflowDetails[item.typeName].count = overflowDetails[item.typeName].count + 1
                        overflowDetails[item.typeName].containers[data.label or "Overflow"] = true
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

    local containerTypes = {}
    local ok, containerItems = pcall(function() return containerInv:GetItems() end)
    if ok and containerItems then
        for _, item in ipairs(containerItems) do
            local s = item:get()
            if s.ItemType then
                local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                if ok2 then containerTypes[typeName] = true end
            end
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
                utils.Notify("No matching items for this container", config)
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

    -- Whitelisted container classes
    local containerSources = {
        { class = "SN2Locker",          getInv = function(a) return a.Inventory end,          hasLabel = true },
        { class = "BP_Tailing_Chest_C", getInv = function(a) return a.InventoryComponent end, hasLabel = false },
    }

    local radiusUnits = utils.MetersToUnits(config.Radius)
    local overflowLockers = {}
    local targetLockers = {}

    -- Scan for overflow and target lockers
    for _, source in ipairs(containerSources) do
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
                                local ok2, lbl = pcall(function() return getLockerLabel(actor) end)
                                if ok2 then rawLabel = lbl end
                            end

                            -- Skip excluded
                            if rawLabel and config.ExcludePrefix ~= "" then
                                if rawLabel:sub(1, #config.ExcludePrefix) == config.ExcludePrefix then
                                    goto nextOverflowActor
                                end
                            end

                            -- Collect overflow lockers as sources
                            if rawLabel and config.OverflowPrefix ~= "" then
                                if rawLabel:sub(1, #config.OverflowPrefix) == config.OverflowPrefix then
                                    table.insert(overflowLockers, {
                                        inventory = inv,
                                        inventoryId = inv.InventoryId,
                                        label = rawLabel,
                                    })
                                    goto nextOverflowActor
                                end
                            end

                            -- Everything else is a target
                            local label = nil
                            if rawLabel and config.LabelRouting then
                                if config.LabelPrefix == "" then
                                    label = rawLabel
                                else
                                    local prefixLen = #config.LabelPrefix
                                    if rawLabel:sub(1, prefixLen) == config.LabelPrefix then
                                        label = rawLabel:sub(prefixLen + 1):match("^%s*(.-)%s*$")
                                        if label == "" then label = nil end
                                    end
                                end
                            end
                            table.insert(targetLockers, {
                                inventory = inv,
                                inventoryId = inv.InventoryId,
                                label = label,
                            })
                        end
                    end
                    ::nextOverflowActor::
                end
            end
        end
    end

    if #overflowLockers == 0 then
        utils.Notify("No overflow lockers nearby", config)
        return
    end

    if #targetLockers == 0 then
        utils.Notify("No target lockers nearby", config)
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
        targetMaxItems[i] = (ok0 and maxItems) or 30
        local ok, items = pcall(function() return data.inventory:GetItems() end)
        if ok and items then
            targetItemCount[i] = #items
            for _, item in ipairs(items) do
                local s = item:get()
                if s.ItemType then
                    local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
                    if ok2 then
                        targetTypeData[i][typeName] = (targetTypeData[i][typeName] or 0) + 1
                    end
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
            if not s.ItemType then goto nextOverflowItem end

            local ok2, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if not ok2 then goto nextOverflowItem end

            local displayName = nil
            pcall(function() displayName = s.ItemType.Name:ToString() end)
            if not displayName or displayName == "" then
                displayName = typeName:gsub("^DA_", ""):gsub("_ItemType$", "")
            end

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
                    -- Record transfer details
                    if not transferDetails[typeName] then
                        transferDetails[typeName] = {
                            itemType = s.ItemType,
                            displayName = displayName,
                            count = 0,
                            containers = {},
                        }
                    end
                    transferDetails[typeName].count = transferDetails[typeName].count + 1
                    local targetLabel = targetLabels[bestIdx] or "Unlabeled"
                    transferDetails[typeName].containers[targetLabel] = true
                end
            end

            ::nextOverflowItem::
        end

        ::nextOverflowLocker::
    end

    if totalMoved == 0 then
        utils.Notify("No items could be sorted from overflow", config)
        return
    end

    local numContainers = 0
    for _ in pairs(containersUsed) do numContainers = numContainers + 1 end

    -- Use waitForReplication on first overflow locker to confirm moves
    local firstOverflow = overflowLockers[1]
    local firstOverflowCount = 0
    pcall(function() firstOverflowCount = #firstOverflow.inventory:GetItems() end)

    -- Show results (wait for replication if needed)
    local itm = totalMoved == 1 and "item" or "items"
    local ctr = numContainers == 1 and "container" or "containers"
    local msg = string.format("Sorted %d %s from overflow to %d %s", totalMoved, itm, numContainers, ctr)
    if someFull then msg = msg .. " (some full)" end

    utils.Notify(msg, config)
    showTransferSummary(transferDetails)
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

-- Keybind registration (config.txt only — keybinds are set-and-forget)
RegisterKeyBind(bindKey, function()
    ExecuteInGameThread(function()
        if isTextInputFocused() then return end
        local now = os.clock()
        if now - lastActivation < config.Cooldown then return end
        lastActivation = now
        config.refreshModSettings()
        doQuickStack()
    end)
end)

local bindKeyOpen = keyMap[config.KeybindOpen]
if not bindKeyOpen then
    print(string.format("[QuickStack] ERROR: Unknown keybind_open '%s', defaulting to G\n", config.KeybindOpen))
    bindKeyOpen = Key.G
end

RegisterKeyBind(bindKeyOpen, function()
    ExecuteInGameThread(function()
        if isTextInputFocused() then return end
        local now = os.clock()
        if now - lastActivation < config.Cooldown then return end
        lastActivation = now
        config.refreshModSettings()
        doQuickStackOpen()
    end)
end)

local bindKeyOverflow = keyMap[config.KeybindOverflow]
if not bindKeyOverflow then
    print(string.format("[QuickStack] ERROR: Unknown keybind_overflow '%s', defaulting to H\n", config.KeybindOverflow))
    bindKeyOverflow = Key.H
end

RegisterKeyBind(bindKeyOverflow, function()
    ExecuteInGameThread(function()
        if isTextInputFocused() then return end
        local now = os.clock()
        if now - lastActivation < config.Cooldown then return end
        lastActivation = now
        config.refreshModSettings()
        doSortOverflow()
    end)
end)
