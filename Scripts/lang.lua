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

    -- Controls
    keybind_title         = "Quick Stack Key (Requires Restart)",
    keybind_desc          = "Key to quick-stack items to nearby containers.",
    keybind_open_title    = "Stack to Open Container Key (Requires Restart)",
    keybind_open_desc     = "Key to stack matching items into the currently open container.",
    keybind_overflow_title = "Sort Overflow Key (Requires Restart)",
    keybind_overflow_desc  = "Key to sort overflow locker contents into nearby matching lockers.",
    cooldown_title        = "Cooldown (seconds)",
    cooldown_desc         = "Minimum seconds between key presses.",

    -- Stacking
    radius_title          = "Scan Radius (meters)",
    radius_desc           = "How far to search for containers when quick-stacking. Game limit is ~235m.",
    stack_tools_title     = "Stack Tools",
    stack_tools_desc      = "Allow tools to be quick-stacked out of your inventory.",
    stack_equip_title     = "Stack Equipment",
    stack_equip_desc      = "Allow equipment and batteries to be quick-stacked out of your inventory.",
    stack_consum_title    = "Stack Consumables",
    stack_consum_desc     = "Allow food, water, and medical items to be quick-stacked out of your inventory.",

    -- Label routing
    label_routing_title   = "Label Routing",
    label_routing_desc    = "Route items to lockers based on their label text. Disable to use type-matching only.",

    -- Restock
    food_title            = "Food Budget",
    food_desc             = "How many food items to restock after quick-stacking. Set to 0 to disable.",
    drink_title           = "Drink Budget",
    drink_desc            = "How many drink items to restock after quick-stacking. Set to 0 to disable.",
    heal_title            = "Heal Budget",
    heal_desc             = "How many healing items to restock after quick-stacking. Set to 0 to disable.",
    battery_swap_title    = "Battery Swap",
    battery_swap_desc     = "Auto-swap drained batteries with higher-charged ones from nearby chargers.",
    battery_budget_title  = "Battery Budget",
    battery_budget_desc   = "Batteries to keep in inventory. Excess routes to Battery Terminal. 0 = use swap mode.",
    powercell_budget_title = "Power Cell Budget",
    powercell_budget_desc  = "Power cells to keep in inventory. Excess routes to Power Cell Terminal. 0 = use swap mode.",

    -- Auto-label
    auto_label_title      = "Auto-Label Max",
    auto_label_desc       = "Auto-name unlabeled lockers when you deposit items. 0 = disabled.",

    -- Notifications
    notify_title          = "Toast Notifications",
    notify_desc           = "Show the left-side text notification after quick-stacking.",
    summary_title         = "Summary Panel",
    summary_desc          = "Show the visual transfer summary panel with item icons after quick-stacking.",
    summary_dur_title     = "Summary Duration (seconds)",
    summary_dur_desc      = "How long the summary panel stays on screen.",
    summary_dest_title    = "Show Destinations",
    summary_dest_desc     = "Show destination container names in the summary panel.",
    summary_trunc_title   = "Truncate Names (characters)",
    summary_trunc_desc    = "Truncate destination names to this many characters. 0 = no truncation.",
    summary_left_title    = "Summary on Left Side",
    summary_left_desc     = "Move the summary panel to the left side of the screen.",
    summary_scale_title   = "Summary Text Scale",
    summary_scale_desc    = "Scale the summary panel text size. 1.0 = default.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("Sorted %d %s from vehicles", n, n == 1 and "item" or "items") end,
    tadpole_title         = "Sort from Tadpole",
    tadpole_desc          = "Pull items from docked tadpole inventories (haul chassis + attached portable lockers) when quick-stacking.",

    -- Auto-sort on entry
    auto_sort_title       = "Auto-Sort on Base Entry",
    auto_sort_desc        = "Automatically run quick-stack when entering a base habitat.",
    auto_sort_cd_title    = "Auto-Sort Cooldown (seconds)",
    auto_sort_cd_desc     = "Minimum seconds between auto-sort triggers. Prevents repeated fires at moonpool boundaries.",
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

    -- Controls
    keybind_title         = "快速堆叠按键（需要重启）",
    keybind_desc          = "将物品快速堆叠到附近容器的按键。",
    keybind_open_title    = "堆叠到打开容器按键（需要重启）",
    keybind_open_desc     = "将匹配物品堆叠到当前打开容器的按键。",
    keybind_overflow_title = "溢出整理按键（需要重启）",
    keybind_overflow_desc  = "将溢出储物柜内容整理到附近匹配储物柜的按键。",
    cooldown_title        = "冷却时间（秒）",
    cooldown_desc         = "按键之间的最短间隔。",

    -- Stacking
    radius_title          = "扫描半径（米）",
    radius_desc           = "快速堆叠时搜索储物柜的距离。游戏限制约为235米。",
    stack_tools_title     = "堆叠工具",
    stack_tools_desc      = "允许将工具从物品栏中快速堆叠出去。",
    stack_equip_title     = "堆叠装备",
    stack_equip_desc      = "允许将装备和电池从物品栏中快速堆叠出去。",
    stack_consum_title    = "堆叠消耗品",
    stack_consum_desc     = "允许将食物、饮水和医疗物品从物品栏中快速堆叠出去。",

    -- Label routing
    label_routing_title   = "标签路由",
    label_routing_desc    = "根据储物柜标签文本路由物品。禁用则仅使用类型匹配。",

    -- Restock
    food_title            = "食物补给",
    food_desc             = "快速堆叠后补充的食物数量。设为0禁用。",
    drink_title           = "饮水补给",
    drink_desc            = "快速堆叠后补充的饮水数量。设为0禁用。",
    heal_title            = "医疗补给",
    heal_desc             = "快速堆叠后补充的医疗物品数量。设为0禁用。",
    battery_swap_title    = "更换电池",
    battery_swap_desc     = "自动将耗尽电量的电池与附近充电器中电量较高的电池进行更换。",
    battery_budget_title  = "电池预算",
    battery_budget_desc   = "保留在物品栏中的电池数量。多余的存入充电站。设为0使用交换模式。",
    powercell_budget_title = "电力电池预算",
    powercell_budget_desc  = "保留在物品栏中的电力电池数量。多余的存入充电站。设为0使用交换模式。",

    -- Auto-label
    auto_label_title      = "自动标签数量",
    auto_label_desc       = "手动存放物品时自动命名未标记的储物柜。设为0禁用。",

    -- Notifications
    notify_title          = "提示通知",
    notify_desc           = "快速堆叠后显示左侧文字通知。",
    summary_title         = "摘要面板",
    summary_desc          = "快速堆叠后显示带有物品图标的传输摘要面板。",
    summary_dur_title     = "摘要显示时长（秒）",
    summary_dur_desc      = "摘要面板在屏幕上停留的时间。",
    summary_dest_title    = "显示目标位置",
    summary_dest_desc     = "在摘要面板中显示目标容器名称。",
    summary_trunc_title   = "截断名称（字符数）",
    summary_trunc_desc    = "将目标名称截断为此字符数。设为0不截断。",
    summary_left_title    = "摘要显示在左侧",
    summary_left_desc     = "将摘要面板移至屏幕左侧。",
    summary_scale_title   = "摘要文字缩放",
    summary_scale_desc    = "缩放摘要面板文字大小。1.0为默认。",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("从载具中取出 %d 个物品", n) end,
    tadpole_title         = "从蝌蚪号整理",
    tadpole_desc          = "快速堆叠时从停靠的蝌蚪号库存（运输底盘+挂载的便携储物柜）中取出物品。",

    -- Auto-sort on entry
    auto_sort_title       = "进入基地时自动整理",
    auto_sort_desc        = "进入基地栖息地时自动运行快速堆叠。",
    auto_sort_cd_title    = "自动整理冷却时间（秒）",
    auto_sort_cd_desc     = "自动整理触发之间的最短间隔。防止在月池边界反复触发。",
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
