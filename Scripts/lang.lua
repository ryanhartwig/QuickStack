-- QuickStack Localization
-- Detects game language and provides L() for translated strings.
-- Add new languages by adding a table keyed by ISO code (e.g. "de", "fr").

local lang = {}

-----------------------------------------------------------
-- String tables
-----------------------------------------------------------
-- Entries can be plain strings or functions(args...) -> string.
-- Functions are used when the language needs custom plural/grammar logic.

local strings = {}

strings.en = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stacked %d %s to %d %s",
            n, n == 1 and "item" or "items",
            c, c == 1 and "container" or "containers")
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stacked %d %s to %d %s (some full)",
            n, n == 1 and "item" or "items",
            c, c == 1 and "container" or "containers")
    end,
    swapped = function(n)
        return string.format("Swapped %d %s", n, n == 1 and "battery" or "batteries")
    end,
    restocked = function(n)
        return string.format("Restocked %d %s", n, n == 1 and "type" or "types")
    end,
    sorted = function(n, c)
        return string.format("Sorted %d %s from overflow to %d %s",
            n, n == 1 and "item" or "items",
            c, c == 1 and "container" or "containers")
    end,
    sorted_full = function(n, c)
        return string.format("Sorted %d %s from overflow to %d %s (some full)",
            n, n == 1 and "item" or "items",
            c, c == 1 and "container" or "containers")
    end,

    -- Status / error messages
    no_match              = "No matching containers nearby",
    no_match_full         = "No matching containers nearby (some full)",
    nothing_to_stack      = "Nothing to stack",
    nothing_to_restock    = "Nothing to restock",
    battery_stashed       = function(n) return string.format("Stashed %d %s", n, n == 1 and "battery" or "batteries") end,
    battery_pulled        = function(n) return string.format("Pulled %d %s", n, n == 1 and "battery" or "batteries") end,
    no_inventory          = "Error: Could not find player inventory",
    no_container_open     = "No container open",
    no_match_container    = "No matching items for this container",
    no_overflow           = "No overflow lockers nearby",
    no_target             = "No target lockers nearby",
    no_overflow_sorted    = "No items could be sorted from overflow",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",
    radius_title          = "Scan Radius (meters)",
    radius_desc           = "How far to search for containers when quick-stacking. Game limit is ~235m.",
    battery_swap_title    = "Battery Swap",
    battery_swap_desc     = "Auto-swap drained batteries with higher-charged ones from nearby chargers.",
    food_title            = "Food Budget",
    food_desc             = "How many food items to restock after quick-stacking. Set to 0 to disable.",
    drink_title           = "Drink Budget",
    drink_desc            = "How many drink items to restock after quick-stacking. Set to 0 to disable.",
    heal_title            = "Heal Budget",
    heal_desc             = "How many healing items to restock after quick-stacking. Set to 0 to disable.",
    battery_budget_title  = "Battery Budget",
    battery_budget_desc   = "Batteries to keep in inventory. Excess routes to Battery Terminal. 0 = use swap mode.",
    powercell_budget_title = "Power Cell Budget",
    powercell_budget_desc  = "Power cells to keep in inventory. Excess routes to Power Cell Terminal. 0 = use swap mode.",
    summary_title         = "Summary Panel",
    summary_desc          = "Show the visual transfer summary panel with item icons after quick-stacking.",
    summary_dur_title     = "Summary Duration (seconds)",
    summary_dur_desc      = "How long the summary panel stays on screen.",
}

strings.zh = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("快速堆叠 %d 个物品到 %d 个容器", n, c)
    end,
    stacked_full = function(n, c)
        return string.format("快速堆叠 %d 个物品到 %d 个容器（有些已满）", n, c)
    end,
    swapped = function(n)
        return string.format("已替换 %d 个电池", n)
    end,
    restocked = function(n)
        return string.format("已补充 %d 种物品", n)
    end,
    sorted = function(n, c)
        return string.format("已将 %d 个物品从溢出容器整理到 %d 个容器", n, c)
    end,
    sorted_full = function(n, c)
        return string.format("已将 %d 个物品从溢出容器整理到 %d 个容器（有些已满）", n, c)
    end,

    -- Status / error messages
    no_match              = "附近没有匹配的容器",
    no_match_full         = "附近没有匹配的容器（有些已满）",
    nothing_to_stack      = "没有可堆叠的物品",
    nothing_to_restock    = "没有可补充的物品",
    battery_stashed       = function(n) return string.format("存入 %d 个电池", n) end,
    battery_pulled        = function(n) return string.format("取出 %d 个电池", n) end,
    no_inventory          = "错误：无法找到玩家物品栏",
    no_container_open     = "未打开容器",
    no_match_container    = "此容器没有匹配的物品",
    no_overflow           = "附近没有溢出容器",
    no_target             = "附近没有目标容器",
    no_overflow_sorted    = "无法从溢出容器整理出任何物品",

    -- SN2ModSettings manifest
    mod_display           = "快速堆叠",
    radius_title          = "扫描半径（米）",
    radius_desc           = "快速堆叠时搜索储物柜的距离。游戏限制约为235米。",
    battery_swap_title    = "更换电池",
    battery_swap_desc     = "自动将耗尽电量的电池与附近充电器中电量较高的电池进行更换。",
    food_title            = "食物补给",
    food_desc             = "快速堆叠后补充的食物数量。设为0禁用。",
    drink_title           = "饮水补给",
    drink_desc            = "快速堆叠后补充的饮水数量。设为0禁用。",
    heal_title            = "医疗补给",
    heal_desc             = "快速堆叠后补充的医疗物品数量。设为0禁用。",
    battery_budget_title  = "电池预算",
    battery_budget_desc   = "保留在物品栏中的电池数量。多余的存入充电站。设为0使用交换模式。",
    powercell_budget_title = "电力电池预算",
    powercell_budget_desc  = "保留在物品栏中的电力电池数量。多余的存入充电站。设为0使用交换模式。",
    summary_title         = "摘要面板",
    summary_desc          = "快速堆叠后显示带有物品图标的传输摘要面板。",
    summary_dur_title     = "摘要显示时长（秒）",
    summary_dur_desc      = "摘要面板在屏幕上停留的时间。",
}

-----------------------------------------------------------
-- Language detection
-----------------------------------------------------------

local kil = nil
local ok, result = pcall(function()
    return StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
end)
if ok and result then kil = result end

local active = strings["en"]
local fallback = strings["en"]

lang.code = "en"
lang.strings = strings

--- Re-detect the current language and update the active string table.
--- Call this before using L() if the language may have changed.
function lang.refresh()
    if not kil then return end
    local ok2, code = pcall(function() return kil:GetCurrentLanguage():ToString() end)
    if not ok2 or not code then return end
    if code == lang.code then return end  -- no change
    lang.code = code
    active = strings[code]
        or strings[code:match("^([^%-]+)")]
        or strings["en"]
    print(string.format("[QuickStack] Language changed: %s\n", code))
    if lang.onRefresh then lang.onRefresh() end
end

-- Detect on load (may still be "en" if game hasn't applied saved language yet)
lang.refresh()

-- Re-check after game has finished applying saved settings
ExecuteWithDelay(3000, function()
    ExecuteInGameThread(function()
        lang.refresh()
    end)
end)

-- Auto-refresh when the user changes language in settings
local applyPath = "/Script/Subnautica2.SN2SettingsViewModel:ApplySettings"
local applyFunc = StaticFindObject(applyPath)
if applyFunc then
    RegisterHook(applyPath, function()
        lang.refresh()
    end)
end

--- Look up a translated string by key.
--- If the entry is a function, passes all extra args to it.
--- If it's a format string, passes extra args to string.format.
--- Falls back to English, then returns the raw key.
function lang.L(key, ...)
    local entry = active[key] or fallback[key]
    if entry == nil then return key end
    if type(entry) == "function" then return entry(...) end
    if select("#", ...) > 0 then return string.format(entry, ...) end
    return entry
end

print(string.format("[QuickStack] Language: %s\n", lang.code))

return lang
