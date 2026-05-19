-- QuickStack Mod for Subnautica 2
-- N: Quick Stack to nearby containers + battery swap
-- G: Quick Stack into currently open container
-- Supports locker labels, item protection, battery/power cell swapping

local UEHelpers = require("UEHelpers")
local config = require("config")
local utils = require("utils")

local VERSION = "3.1.0"
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

-- Battery/power cell type patterns
local BATTERY_PATTERNS = {"battery", "powercell", "powercellv2"}

--- Check if an item type name is a battery or power cell
local function isBatteryType(typeName)
    local lname = string.lower(typeName)
    for _, pattern in ipairs(BATTERY_PATTERNS) do
        if string.find(lname, pattern, 1, true) then return true end
    end
    return false
end

--- Read charge level from an inventory item's Attributes
--- Returns current charge, max charge (or nil, nil if unreadable)
local function readCharge(itemStruct)
    local ok, attrs = pcall(function() return itemStruct.Attributes end)
    if not ok or not attrs then return nil, nil end

    local ok2, alen = pcall(function() return #attrs end)
    if not ok2 or not alen or alen < 2 then return nil, nil end

    local current, max = nil, nil
    pcall(function()
        local val1 = ""
        pcall(function() val1 = attrs[1].Value:ToString() end)
        if val1 == "" then pcall(function() val1 = tostring(attrs[1].Value) end) end
        current = tonumber(val1)
    end)
    pcall(function()
        local val2 = ""
        pcall(function() val2 = attrs[2].Value:ToString() end)
        if val2 == "" then pcall(function() val2 = tostring(attrs[2].Value) end) end
        max = tonumber(val2)
    end)

    return current, max
end

--- Check if an item should be kept in the player's inventory
local function shouldKeepItem(typeName, fullName)
    local lname = string.lower(fullName)

    if not config.StackTools then
        if string.find(lname, "/tools/", 1, true) then return true end
    end

    if not config.StackEquipment then
        if string.find(lname, "/equipment/", 1, true) then return true end
        if string.find(lname, "/equippable/", 1, true) then return true end
        if string.find(lname, "/deployables/", 1, true) then return true end
    end

    -- Skip consumables (food, water, medical)
    if not config.StackConsumables then
        local ltname = string.lower(typeName)
        local consumablePatterns = {
            -- Water/drinks
            "water", "isotonic", "drink",
            -- Food
            "nutrient", "block", "pavlova", "souvlaki", "temaki", "chutney",
            "jerky", "salad", "saturn", "mash", "clump", "shavings", "cookie",
            -- Medical
            "firstaid", "first_aid", "medkit", "med_kit",
        }
        for _, pattern in ipairs(consumablePatterns) do
            if string.find(ltname, pattern, 1, true) then return true end
        end
    end

    -- Skip batteries/power cells when battery swap is enabled (handled by swap logic)
    if config.BatterySwap and isBatteryType(typeName) then return true end

    for _, keepType in ipairs(config.KeepTypes) do
        if typeName == keepType then return true end
    end

    return false
end

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

--- Score how well a locker label matches an item's display name
--- Returns 0 (no match) or positive score (higher = better match)
--- Label is comma-separated groups (OR), each group is space-separated tokens (AND)
--- Each token must be a case-insensitive prefix of a distinct word in the display name
--- Score = word coverage + character coverage tiebreaker
--- The tiebreaker ensures "铜线" beats "铜" for item "铜线" (CJK has no word spaces)
local function scoreLockerMatch(label, displayName)
    local nameWords = {}
    local totalNameChars = 0
    for word in displayName:lower():gmatch("%S+") do
        table.insert(nameWords, word)
        totalNameChars = totalNameChars + #word
    end
    if #nameWords == 0 then return 0 end

    local bestScore = 0

    for part in label:gmatch("[^,]+") do
        local tokens = {}
        for token in part:lower():gmatch("%S+") do
            table.insert(tokens, token)
        end
        if #tokens == 0 then goto nextPart end

        -- Each token must prefix-match a distinct word
        local usedWords = {}
        local matched = 0
        local matchedTokenChars = 0
        for _, token in ipairs(tokens) do
            for j, word in ipairs(nameWords) do
                if not usedWords[j] and word:sub(1, #token) == token then
                    usedWords[j] = true
                    matched = matched + 1
                    matchedTokenChars = matchedTokenChars + #token
                    break
                end
            end
        end

        -- All tokens must match for this group to count
        if matched == #tokens then
            -- Word coverage is the primary score (0 to 1.0)
            -- Character coverage is a tiebreaker (adds 0 to 0.01)
            local score = (matched / #nameWords)
                + (matchedTokenChars / totalNameChars) * 0.01
            if score > bestScore then bestScore = score end
        end

        ::nextPart::
    end

    return bestScore
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
    for _, playerItem in ipairs(items) do
        local s = playerItem:get()
        if s.ItemType then
            local ok, typeName = pcall(function() return s.ItemType:GetFName():ToString() end)
            if ok then
                local ok2, fullName = pcall(function() return s.ItemType:GetFullName() end)
                local fName = ok2 and fullName or ""
                if not shouldKeepItem(typeName, fName) then
                    -- Resolve localized display name via FText:ToString()
                    local displayName = nil
                    pcall(function() displayName = s.ItemType.Name:ToString() end)
                    if not displayName or displayName == "" then
                        displayName = typeName:gsub("^DA_", ""):gsub("_ItemType$", "")
                    end
                    table.insert(transferable, {
                        typeName = typeName,
                        displayName = displayName,
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

    -- Find all chargers (UWEPowerTerminal covers both battery and power cell terminals)
    local chargers = FindAllOf("UWEPowerTerminal")
    if not chargers then return 0 end

    -- Collect nearby charger inventories
    local chargerInvs = {}
    for _, charger in ipairs(chargers) do
        if charger:IsValid() then
            local dist = utils.GetDistance(pawn, charger)
            if dist <= radiusUnits then
                local ok, inv = pcall(function() return charger.InventoryComponent end)
                if ok and inv and inv:IsValid() then
                    table.insert(chargerInvs, inv)
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

--- Transfer Summary UI panel
local activeSummaryPanel = nil  -- track current panel for replacement

local function showTransferSummary(transferDetails)
    -- Skip if disabled or nothing transferred
    if not config.SummaryPanel then return end
    local count = 0
    for _ in pairs(transferDetails) do count = count + 1 end
    if count == 0 then return end

    -- Remove previous panel if still visible
    if activeSummaryPanel then
        pcall(function() activeSummaryPanel:RemoveFromViewport() end)
        activeSummaryPanel = nil
    end

    local pc = UEHelpers:GetPlayerController()
    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    if not pc or not wbLib or not uwClass then return end

    -- Create root UUserWidget
    local root = nil
    pcall(function() root = wbLib:Create(pc, uwClass, pc) end)
    if not root then return end

    -- Class references for primitives
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local vboxCls = StaticFindObject("/Script/UMG.VerticalBox")
    local hboxCls = StaticFindObject("/Script/UMG.HorizontalBox")
    local textCls = StaticFindObject("/Script/UMG.TextBlock")
    local imgCls = StaticFindObject("/Script/UMG.Image")

    if not canvasCls or not vboxCls or not textCls then return end

    local widgetNum = 0
    local function make(cls, name)
        if not cls then return nil end
        widgetNum = widgetNum + 1
        local w = nil
        pcall(function() w = StaticConstructObject(cls, root, FName("QS_" .. name .. widgetNum)) end)
        return w
    end

    -- Build widget tree: root > canvas > vbox > rows
    local canvas = make(canvasCls, "Canvas")
    if not canvas then return end
    pcall(function() root.WidgetTree.RootWidget = canvas end)

    local vbox = make(vboxCls, "VBox")
    if not vbox then return end

    pcall(function()
        local slot = canvas:AddChildToCanvas(vbox)
        if slot then
            slot:SetAnchors({ Minimum = { X = 1.0, Y = 0.3 }, Maximum = { X = 1.0, Y = 0.3 } })
            slot:SetAlignment({ X = 1.0, Y = 0.0 })  -- Anchor right edge of content to anchor point
            slot:SetPosition({ X = -20, Y = 0 })      -- 20px padding from right screen edge
            slot:SetAutoSize(true)
        end
    end)

    -- Build rows from transferDetails, sorted by count descending
    local sorted = {}
    for typeName, detail in pairs(transferDetails) do
        table.insert(sorted, { typeName = typeName, detail = detail })
    end
    table.sort(sorted, function(a, b) return a.detail.count > b.detail.count end)

    for _, entry in ipairs(sorted) do
        local detail = entry.detail
        local hbox = make(hboxCls, "HBox")
        if not hbox then break end

        -- Item icon (constrained to 32x32)
        if imgCls and detail.itemType then
            local img = make(imgCls, "Img")
            if img then
                pcall(function() img:SetBrushFromSoftTexture(detail.itemType.Thumbnail, false) end)
                pcall(function() img:SetDesiredSizeOverride({ X = 32, Y = 32 }) end)
                pcall(function()
                    local imgSlot = hbox:AddChildToHorizontalBox(img)
                    if imgSlot then
                        imgSlot:SetPadding({ Left = 4, Top = 2, Right = 8, Bottom = 2 })
                        imgSlot:SetSize({ Value = 0, SizeRule = 0 })  -- Auto size (don't stretch)
                    end
                end)
            end
        end

        -- Item name + count (e.g. "Titanium x3")
        local cleanName = entry.detail.displayName or entry.typeName:gsub("^DA_", ""):gsub("_ItemType$", ""):gsub("_", " ")
        local text1 = make(textCls, "Name")
        if text1 then
            pcall(function() text1:SetText(FText(cleanName .. " x" .. detail.count)) end)
            pcall(function() hbox:AddChildToHorizontalBox(text1) end)
        end

        -- Container label (e.g. " -> Materials")
        if config.SummaryShowDestination then
            local labels = {}
            for label, _ in pairs(detail.containers) do
                table.insert(labels, label)
            end
            if #labels > 0 then
                local text2 = make(textCls, "Dest")
                if text2 then
                    local destRaw = table.concat(labels, ", ")
                    if #destRaw > 15 then destRaw = destRaw:sub(1, 15) .. "..." end
                    local destStr = " -> " .. destRaw
                    pcall(function() text2:SetText(FText(destStr)) end)
                    pcall(function() hbox:AddChildToHorizontalBox(text2) end)
                end
            end
        end

        pcall(function() vbox:AddChildToVerticalBox(hbox) end)
    end

    -- Display with slide-in + fade-in animation
    pcall(function() vbox:SetRenderOpacity(0) end)
    pcall(function() vbox:SetRenderTranslation({ X = 150, Y = 0 }) end)
    pcall(function() root:AddToViewport(150) end)
    activeSummaryPanel = root

    -- Animate in: 12 steps over ~400ms, more pronounced slide
    local animSteps = 12
    local animInterval = 33  -- ms per step
    for step = 1, animSteps do
        ExecuteWithDelay(step * animInterval, function()
            ExecuteInGameThread(function()
                if activeSummaryPanel ~= root then return end
                local t = step / animSteps
                -- Cubic ease-out: more dramatic deceleration
                local eased = 1 - (1 - t) * (1 - t) * (1 - t)
                pcall(function() vbox:SetRenderOpacity(eased) end)
                pcall(function() vbox:SetRenderTranslation({ X = 250 * (1 - eased), Y = 0 }) end)
            end)
        end)
    end

    -- Auto-dismiss with slow fade-out over last 40% of duration
    local duration = (config.SummaryDuration or 6) * 1000
    local fadeDuration = math.floor(duration * 0.4)  -- 40% of total
    local fadeSteps = 12
    local fadeInterval = math.floor(fadeDuration / fadeSteps)
    local fadeStart = duration - fadeDuration

    for step = 1, fadeSteps do
        ExecuteWithDelay(fadeStart + step * fadeInterval, function()
            ExecuteInGameThread(function()
                if activeSummaryPanel ~= root then return end
                local t = step / fadeSteps
                pcall(function() vbox:SetRenderOpacity(1 - t) end)
            end)
        end)
    end

    ExecuteWithDelay(duration, function()
        ExecuteInGameThread(function()
            if activeSummaryPanel == root then
                pcall(function() root:RemoveFromViewport() end)
                activeSummaryPanel = nil
            end
        end)
    end)
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
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                local delayedItems = playerInv:GetItems()
                local delayedCount = totalItemsBefore - #delayedItems
                utils.Notify(buildMessage(delayedCount, numContainers, someFull, swapCount), config)
            end)
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

                            -- Check exclusion prefix — skip this container entirely
                            if rawLabel and config.ExcludePrefix ~= "" then
                                if rawLabel:sub(1, #config.ExcludePrefix) == config.ExcludePrefix then
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

    -- Show combined result
    if #transferableItems == 0 and swapCount == 0 then
        utils.Notify("Nothing to stack", config)
    elseif actualTransferred == 0 and swapCount == 0 and #nearbyLockers == 0 then
        utils.Notify("No matching containers nearby", config)
    else
        showResultNotification(actualTransferred, numContainers, someFull, swapCount, playerInv, totalItemsBefore)
        -- Delay summary panel to match toast on non-host clients (stale inventory data)
        if actualTransferred <= 0 and numContainers > 0 then
            ExecuteWithDelay(500, function()
                ExecuteInGameThread(function()
                    showTransferSummary(transferDetails)
                end)
            end)
        else
            showTransferSummary(transferDetails)
        end
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
        -- Non-host clients may have stale inventory data — retry after 500ms
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                local delayedItems = playerInv:GetItems()
                local delayedCount = totalItemsBefore - #delayedItems
                if delayedCount <= 0 then
                    utils.Notify("No matching items for this container", config)
                end
            end)
        end)
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

-- Keybind: N for Quick Stack (nearby containers + battery swap)
RegisterKeyBind(bindKey, function()
    ExecuteInGameThread(function()
        if isTextInputFocused() then return end
        local now = os.clock()
        if now - lastActivation < config.Cooldown then return end
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
        if isTextInputFocused() then return end
        local now = os.clock()
        if now - lastActivation < config.Cooldown then return end
        lastActivation = now
        doQuickStackOpen()
    end)
end)
