--- QuickStack: Transfer Summary UI module
--- Handles the visual panel showing transfer results with animations

local UEHelpers = require("UEHelpers")

local ui = {}
local config = nil
local activeSummaryPanel = nil

function ui.init(cfg)
    config = cfg
end

--- Wait for server replication before reading inventory
--- Polls every 100ms until item count changes or timeout reached
--- Host: 0ms (instant). Non-host: ~100-200ms typical, 1500ms max.
function ui.waitForReplication(inventory, countBefore, callback, maxWaitMs)
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

--- Show the transfer summary panel
--- transferDetails: normal transfers (item → locker)
--- overflowDetails: overflow dumps (item → %o locker)
--- restockDetails: consumable restocks (item ← locker)
function ui.showTransferSummary(transferDetails, overflowDetails, restockDetails)
    if not config.SummaryPanel then return end
    overflowDetails = overflowDetails or {}
    restockDetails = restockDetails or {}

    local count = 0
    for _ in pairs(transferDetails) do count = count + 1 end
    local overflowCount = 0
    for _ in pairs(overflowDetails) do overflowCount = overflowCount + 1 end
    local restockCount = 0
    for _ in pairs(restockDetails) do restockCount = restockCount + 1 end
    if count == 0 and overflowCount == 0 and restockCount == 0 then return end

    -- Remove previous panel if still visible
    if activeSummaryPanel then
        pcall(function() activeSummaryPanel:RemoveFromViewport() end)
        activeSummaryPanel = nil
    end

    local pc = UEHelpers:GetPlayerController()
    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    if not pc or not wbLib or not uwClass then return end

    local root = nil
    pcall(function() root = wbLib:Create(pc, uwClass, pc) end)
    if not root then return end

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

    local canvas = make(canvasCls, "Canvas")
    if not canvas then return end
    pcall(function() root.WidgetTree.RootWidget = canvas end)

    local vbox = make(vboxCls, "VBox")
    if not vbox then return end

    pcall(function()
        local slot = canvas:AddChildToCanvas(vbox)
        if slot then
            slot:SetAnchors({ Minimum = { X = 1.0, Y = 0.3 }, Maximum = { X = 1.0, Y = 0.3 } })
            slot:SetAlignment({ X = 1.0, Y = 0.0 })
            slot:SetPosition({ X = -20, Y = 0 })
            slot:SetAutoSize(true)
        end
    end)

    -- Helper to build rows from a details table
    local function buildRows(details, prefix, arrowDir)
        arrowDir = arrowDir or " -> "
        local sorted = {}
        for typeName, detail in pairs(details) do
            table.insert(sorted, { typeName = typeName, detail = detail })
        end
        table.sort(sorted, function(a, b) return a.detail.count > b.detail.count end)

        for _, entry in ipairs(sorted) do
            local detail = entry.detail
            local hbox = make(hboxCls, prefix .. "HBox")
            if not hbox then break end

            if imgCls and detail.itemType then
                local img = make(imgCls, prefix .. "Img")
                if img then
                    pcall(function() img:SetBrushFromSoftTexture(detail.itemType.Thumbnail, false) end)
                    pcall(function() img:SetDesiredSizeOverride({ X = 32, Y = 32 }) end)
                    pcall(function()
                        local imgSlot = hbox:AddChildToHorizontalBox(img)
                        if imgSlot then
                            imgSlot:SetPadding({ Left = 4, Top = 2, Right = 8, Bottom = 2 })
                            imgSlot:SetSize({ Value = 0, SizeRule = 0 })
                        end
                    end)
                end
            end

            local cleanName = detail.displayName or entry.typeName:gsub("^DA_", ""):gsub("_ItemType$", ""):gsub("_", " ")
            local text1 = make(textCls, prefix .. "Name")
            if text1 then
                pcall(function() text1:SetText(FText(cleanName .. " x" .. detail.count)) end)
                pcall(function() hbox:AddChildToHorizontalBox(text1) end)
            end

            if config.SummaryShowDestination then
                local labels = {}
                for label, _ in pairs(detail.containers) do
                    table.insert(labels, label)
                end
                if #labels > 0 then
                    local text2 = make(textCls, prefix .. "Dest")
                    if text2 then
                        local destRaw = table.concat(labels, ", ")
                        if #destRaw > 15 then destRaw = destRaw:sub(1, 15) .. "..." end
                        pcall(function() text2:SetText(FText(arrowDir .. destRaw)) end)
                        pcall(function() hbox:AddChildToHorizontalBox(text2) end)
                    end
                end
            end

            pcall(function() vbox:AddChildToVerticalBox(hbox) end)
        end
    end

    local function addSeparator(label, topPad)
        local sepText = make(textCls, "Sep")
        if sepText then
            pcall(function() sepText:SetText(FText(label)) end)
            pcall(function()
                local sepSlot = vbox:AddChildToVerticalBox(sepText)
                if sepSlot then
                    sepSlot:SetPadding({ Left = 4, Top = topPad or 2, Right = 0, Bottom = 2 })
                end
            end)
        end
    end

    -- Sections in priority order: Restocked > Overflow > Sorted
    local hasPrevSection = false

    if restockCount > 0 then
        addSeparator("── Restocked ──", 2)
        buildRows(restockDetails, "R", " <- ")
        hasPrevSection = true
    end

    if overflowCount > 0 then
        addSeparator("── Overflow ──", hasPrevSection and 6 or 2)
        buildRows(overflowDetails, "O")
        hasPrevSection = true
    end

    if count > 0 then
        if hasPrevSection then
            addSeparator("── Sorted ──", 6)
        end
        buildRows(transferDetails, "N")
    end

    -- Display with slide-in + fade-in animation
    pcall(function() vbox:SetRenderOpacity(0) end)
    pcall(function() vbox:SetRenderTranslation({ X = 150, Y = 0 }) end)
    pcall(function() root:AddToViewport(150) end)
    activeSummaryPanel = root

    local animSteps = 12
    local animInterval = 33
    for step = 1, animSteps do
        ExecuteWithDelay(step * animInterval, function()
            ExecuteInGameThread(function()
                if activeSummaryPanel ~= root then return end
                local t = step / animSteps
                local eased = 1 - (1 - t) * (1 - t) * (1 - t)
                pcall(function() vbox:SetRenderOpacity(eased) end)
                pcall(function() vbox:SetRenderTranslation({ X = 250 * (1 - eased), Y = 0 }) end)
            end)
        end)
    end

    local duration = (config.SummaryDuration or 6) * 1000
    local fadeDuration = math.floor(duration * 0.4)
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

return ui
