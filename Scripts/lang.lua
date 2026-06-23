-- QuickStack Localization
-- Detects game language and provides L() for translated strings.
-- Add new languages by adding a table keyed by ISO code (e.g. "de", "fr").

local gthread = require("gthread")
local lang = {}

-----------------------------------------------------------
-- String tables
-----------------------------------------------------------
-- Entries can be plain strings or functions(args...) -> string.
-- Functions are used when the language needs custom plural/grammar logic.

local strings = {}

--- Pluralization helpers for translation tables.
--- Simple: plural(n, "item", "items") — most European languages
--- Slavic: plural_slavic(n, "предмет", "предмета", "предметов") — ru, uk
--- East Asian languages (ja, ko, zh) don't need pluralization.
local function plural(n, one, many)
    return n == 1 and one or many
end

local function plural_slavic(n, one, few, many)
    local m = n % 10
    local t = n % 100
    if m == 1 and t ~= 11 then return one end
    if m >= 2 and m <= 4 and (t < 12 or t > 14) then return few end
    return many
end

strings.en = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stacked %d %s to %d %s",
            n, plural(n, "item", "items"), c, plural(c, "container", "containers"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stacked %d %s to %d %s (some full)",
            n, plural(n, "item", "items"), c, plural(c, "container", "containers"))
    end,
    swapped = function(n)
        return string.format("Swapped %d %s", n, plural(n, "battery", "batteries"))
    end,
    restocked = function(n)
        return string.format("Restocked %d %s", n, plural(n, "type", "types"))
    end,
    sorted = function(n, c)
        return string.format("Sorted %d %s from overflow to %d %s",
            n, plural(n, "item", "items"), c, plural(c, "container", "containers"))
    end,
    sorted_full = function(n, c)
        return string.format("Sorted %d %s from overflow to %d %s (some full)",
            n, plural(n, "item", "items"), c, plural(c, "container", "containers"))
    end,

    -- Status / error messages
    no_match              = "No matching containers nearby",
    no_match_full         = "No matching containers nearby (some full)",
    nothing_to_stack      = "Nothing to stack",
    nothing_to_restock    = "Nothing to restock",
    battery_stashed       = function(n) return string.format("Stashed %d %s", n, plural(n, "battery", "batteries")) end,
    battery_pulled        = function(n) return string.format("Pulled %d %s", n, plural(n, "battery", "batteries")) end,
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

    -- Infinite range
    infinite_range_title  = "Use Infinite Range",
    infinite_range_desc   = "Quick-stack into matching base lockers anywhere on the map, not just nearby ones. Host / single-player only — on a multiplayer client this falls back to nearby lockers (full client support is planned for a later update). Only deposits into lockers whose label is known from this session.",

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
    tadpole_sourced       = function(n) return string.format("Sorted %d %s from vehicles", n, plural(n, "item", "items")) end,
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

strings.de = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s in %d %s verstaut",
            n, plural(n, "Gegenstand", "Gegenstände"), c, "Behälter")
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s in %d %s verstaut (einige voll)",
            n, plural(n, "Gegenstand", "Gegenstände"), c, "Behälter")
    end,
    swapped = function(n)
        return string.format("%d %s getauscht", n, plural(n, "Batterie", "Batterien"))
    end,
    restocked = function(n)
        return string.format("%d %s aufgefüllt", n, plural(n, "Typ", "Typen"))
    end,
    sorted = function(n, c)
        return string.format("%d %s aus Überlauf in %d %s sortiert",
            n, plural(n, "Gegenstand", "Gegenstände"), c, "Behälter")
    end,
    sorted_full = function(n, c)
        return string.format("%d %s aus Überlauf in %d %s sortiert (einige voll)",
            n, plural(n, "Gegenstand", "Gegenstände"), c, "Behälter")
    end,

    -- Status / error messages
    no_match              = "Keine passenden Behälter in der Nähe",
    no_match_full         = "Keine passenden Behälter in der Nähe (einige voll)",
    nothing_to_stack      = "Nichts zu verstauen",
    nothing_to_restock    = "Nichts zum Auffüllen",
    battery_stashed       = function(n) return string.format("%d %s eingelagert", n, plural(n, "Batterie", "Batterien")) end,
    battery_pulled        = function(n) return string.format("%d %s entnommen", n, plural(n, "Batterie", "Batterien")) end,
    no_inventory          = "Fehler: Spielerinventar nicht gefunden",
    no_container_open     = "Kein Behälter geöffnet",
    no_match_container    = "Keine passenden Gegenstände für diesen Behälter",
    no_overflow           = "Keine Überlauf-Schließfächer in der Nähe",
    no_target             = "Keine Ziel-Schließfächer in der Nähe",
    no_overflow_sorted    = "Keine Gegenstände aus Überlauf sortierbar",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Quick Stack Taste (Neustart erforderlich)",
    keybind_desc          = "Taste zum Verstauen von Gegenständen in nahe Behälter.",
    keybind_open_title    = "In offenen Behälter stapeln (Neustart erforderlich)",
    keybind_open_desc     = "Taste zum Verstauen passender Gegenstände in den geöffneten Behälter.",
    keybind_overflow_title = "Überlauf sortieren (Neustart erforderlich)",
    keybind_overflow_desc  = "Taste zum Sortieren von Überlauf-Inhalten in passende Schließfächer.",
    cooldown_title        = "Abklingzeit (Sekunden)",
    cooldown_desc         = "Mindestzeitraum zwischen Tastendrücken.",

    -- Stacking
    radius_title          = "Suchradius (Meter)",
    radius_desc           = "Suchreichweite für Behälter beim Quick Stack. Spiellimit ca. 235 m.",
    stack_tools_title     = "Werkzeuge verstauen",
    stack_tools_desc      = "Erlaubt das Verstauen von Werkzeugen aus dem Inventar.",
    stack_equip_title     = "Ausrüstung verstauen",
    stack_equip_desc      = "Erlaubt das Verstauen von Ausrüstung und Batterien aus dem Inventar.",
    stack_consum_title    = "Verbrauchsgüter verstauen",
    stack_consum_desc     = "Erlaubt das Verstauen von Nahrung, Getränken und Medizin aus dem Inventar.",

    -- Label routing
    label_routing_title   = "Label-Routing",
    label_routing_desc    = "Gegenstände anhand des Schließfach-Labels zuordnen. Deaktivieren für reine Typ-Zuordnung.",

    -- Restock
    food_title            = "Nahrungsvorrat",
    food_desc             = "Anzahl aufzufüllender Nahrung nach Quick Stack. 0 = deaktiviert.",
    drink_title           = "Getränkevorrat",
    drink_desc            = "Anzahl aufzufüllender Getränke nach Quick Stack. 0 = deaktiviert.",
    heal_title            = "Medizinvorrat",
    heal_desc             = "Anzahl aufzufüllender Medizin nach Quick Stack. 0 = deaktiviert.",
    battery_swap_title    = "Batterietausch",
    battery_swap_desc     = "Leere Batterien automatisch gegen vollere aus nahen Ladestationen tauschen.",
    battery_budget_title  = "Batterie-Budget",
    battery_budget_desc   = "Batterien im Inventar behalten. Überschuss geht an Battery Terminal. 0 = Tauschmodus.",
    powercell_budget_title = "Energiezellen-Budget",
    powercell_budget_desc  = "Energiezellen im Inventar behalten. Überschuss geht an Power Cell Terminal. 0 = Tauschmodus.",

    -- Auto-label
    auto_label_title      = "Auto-Label Maximum",
    auto_label_desc       = "Unbeschriftete Schließfächer beim Einlagern automatisch benennen. 0 = deaktiviert.",

    -- Notifications
    notify_title          = "Toast-Benachrichtigungen",
    notify_desc           = "Textbenachrichtigung links nach Quick Stack anzeigen.",
    summary_title         = "Zusammenfassungspanel",
    summary_desc          = "Visuelles Transfer-Panel mit Gegenstandssymbolen nach Quick Stack anzeigen.",
    summary_dur_title     = "Anzeigedauer (Sekunden)",
    summary_dur_desc      = "Wie lange das Zusammenfassungspanel sichtbar bleibt.",
    summary_dest_title    = "Ziele anzeigen",
    summary_dest_desc     = "Ziel-Behälternamen im Zusammenfassungspanel anzeigen.",
    summary_trunc_title   = "Namen kürzen (Zeichen)",
    summary_trunc_desc    = "Zielnamen auf diese Zeichenanzahl kürzen. 0 = nicht kürzen.",
    summary_left_title    = "Zusammenfassung links",
    summary_left_desc     = "Zusammenfassungspanel auf die linke Bildschirmseite verschieben.",
    summary_scale_title   = "Textgröße der Zusammenfassung",
    summary_scale_desc    = "Textgröße des Zusammenfassungspanels skalieren. 1.0 = Standard.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s aus Fahrzeugen sortiert", n, n == 1 and "Gegenstand" or "Gegenstände") end,
    tadpole_title         = "Aus Tadpole sortieren",
    tadpole_desc          = "Beim Quick Stack Gegenstände aus angedockten Tadpole-Inventaren (Transportchassis + tragbare Schließfächer) entnehmen.",

    -- Auto-sort on entry
    auto_sort_title       = "Auto-Sortierung beim Betreten",
    auto_sort_desc        = "Quick Stack automatisch beim Betreten eines Basis-Habitats ausführen.",
    auto_sort_cd_title    = "Auto-Sortierung Abklingzeit (Sekunden)",
    auto_sort_cd_desc     = "Mindestzeitraum zwischen Auto-Sortierungen. Verhindert wiederholtes Auslösen am Moonpool.",
}

strings.es = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s en %d %s",
            n, plural(n, "objeto", "objetos"),
            c, plural(c, "contenedor", "contenedores"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s en %d %s (algunos llenos)",
            n, plural(n, "objeto", "objetos"),
            c, plural(c, "contenedor", "contenedores"))
    end,
    swapped = function(n)
        return string.format("%d %s intercambiadas", n, plural(n, "batería", "baterías"))
    end,
    restocked = function(n)
        return string.format("%d %s reabastecidos", n, plural(n, "tipo", "tipos"))
    end,
    sorted = function(n, c)
        return string.format("%d %s del desbordamiento ordenados en %d %s",
            n, plural(n, "objeto", "objetos"),
            c, plural(c, "contenedor", "contenedores"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s del desbordamiento ordenados en %d %s (algunos llenos)",
            n, plural(n, "objeto", "objetos"),
            c, plural(c, "contenedor", "contenedores"))
    end,

    -- Status / error messages
    no_match              = "No hay contenedores compatibles cerca",
    no_match_full         = "No hay contenedores compatibles cerca (algunos llenos)",
    nothing_to_stack      = "Nada que apilar",
    nothing_to_restock    = "Nada que reabastecer",
    battery_stashed       = function(n) return string.format("%d %s guardadas", n, plural(n, "batería", "baterías")) end,
    battery_pulled        = function(n) return string.format("%d %s retiradas", n, plural(n, "batería", "baterías")) end,
    no_inventory          = "Error: No se encontró el inventario del jugador",
    no_container_open     = "Ningún contenedor abierto",
    no_match_container    = "No hay objetos compatibles para este contenedor",
    no_overflow           = "No hay casilleros de desbordamiento cerca",
    no_target             = "No hay casilleros destino cerca",
    no_overflow_sorted    = "No se pudieron ordenar objetos del desbordamiento",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Tecla de Quick Stack (requiere reinicio)",
    keybind_desc          = "Tecla para apilar objetos en contenedores cercanos.",
    keybind_open_title    = "Tecla apilar en contenedor abierto (requiere reinicio)",
    keybind_open_desc     = "Tecla para apilar objetos compatibles en el contenedor abierto.",
    keybind_overflow_title = "Tecla ordenar desbordamiento (requiere reinicio)",
    keybind_overflow_desc  = "Tecla para ordenar el contenido del desbordamiento en casilleros compatibles.",
    cooldown_title        = "Tiempo de espera (segundos)",
    cooldown_desc         = "Segundos mínimos entre pulsaciones.",

    -- Stacking
    radius_title          = "Radio de búsqueda (metros)",
    radius_desc           = "Distancia de búsqueda de contenedores al apilar. Límite del juego: ~235 m.",
    stack_tools_title     = "Apilar herramientas",
    stack_tools_desc      = "Permitir apilar herramientas fuera del inventario.",
    stack_equip_title     = "Apilar equipamiento",
    stack_equip_desc      = "Permitir apilar equipamiento y baterías fuera del inventario.",
    stack_consum_title    = "Apilar consumibles",
    stack_consum_desc     = "Permitir apilar comida, bebida y objetos médicos fuera del inventario.",

    -- Label routing
    label_routing_title   = "Enrutamiento por etiqueta",
    label_routing_desc    = "Dirigir objetos según el texto de la etiqueta del casillero. Desactivar para usar solo tipo.",

    -- Restock
    food_title            = "Reserva de comida",
    food_desc             = "Cantidad de comida a reabastecer tras Quick Stack. 0 = desactivado.",
    drink_title           = "Reserva de bebida",
    drink_desc            = "Cantidad de bebida a reabastecer tras Quick Stack. 0 = desactivado.",
    heal_title            = "Reserva de medicina",
    heal_desc             = "Cantidad de medicina a reabastecer tras Quick Stack. 0 = desactivado.",
    battery_swap_title    = "Intercambio de baterías",
    battery_swap_desc     = "Intercambiar baterías agotadas por otras con más carga de cargadores cercanos.",
    battery_budget_title  = "Presupuesto de baterías",
    battery_budget_desc   = "Baterías a mantener en inventario. El exceso va al Battery Terminal. 0 = modo intercambio.",
    powercell_budget_title = "Presupuesto de celdas de energía",
    powercell_budget_desc  = "Celdas a mantener en inventario. El exceso va al Power Cell Terminal. 0 = modo intercambio.",

    -- Auto-label
    auto_label_title      = "Auto-etiquetado máximo",
    auto_label_desc       = "Nombrar automáticamente casilleros sin etiqueta al depositar objetos. 0 = desactivado.",

    -- Notifications
    notify_title          = "Notificaciones",
    notify_desc           = "Mostrar notificación de texto a la izquierda tras Quick Stack.",
    summary_title         = "Panel de resumen",
    summary_desc          = "Mostrar panel visual con iconos de objetos tras Quick Stack.",
    summary_dur_title     = "Duración del resumen (segundos)",
    summary_dur_desc      = "Tiempo que el panel de resumen permanece en pantalla.",
    summary_dest_title    = "Mostrar destinos",
    summary_dest_desc     = "Mostrar nombres de contenedores destino en el panel de resumen.",
    summary_trunc_title   = "Truncar nombres (caracteres)",
    summary_trunc_desc    = "Truncar nombres de destino a este número de caracteres. 0 = sin truncar.",
    summary_left_title    = "Resumen a la izquierda",
    summary_left_desc     = "Mover el panel de resumen al lado izquierdo de la pantalla.",
    summary_scale_title   = "Escala del texto del resumen",
    summary_scale_desc    = "Escalar el tamaño del texto del panel de resumen. 1.0 = predeterminado.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s ordenados desde vehículos", n, plural(n, "objeto", "objetos")) end,
    tadpole_title         = "Ordenar desde Tadpole",
    tadpole_desc          = "Extraer objetos del inventario de Tadpoles atracados (chasis de carga + casilleros portátiles) al apilar.",

    -- Auto-sort on entry
    auto_sort_title       = "Auto-ordenar al entrar a la base",
    auto_sort_desc        = "Ejecutar Quick Stack automáticamente al entrar en un hábitat.",
    auto_sort_cd_title    = "Espera de auto-ordenar (segundos)",
    auto_sort_cd_desc     = "Segundos mínimos entre auto-ordenamientos. Evita disparos repetidos en el moonpool.",
}

strings.fr = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack : %d %s dans %d %s",
            n, plural(n, "objet", "objets"),
            c, plural(c, "conteneur", "conteneurs"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack : %d %s dans %d %s (certains pleins)",
            n, plural(n, "objet", "objets"),
            c, plural(c, "conteneur", "conteneurs"))
    end,
    swapped = function(n)
        return string.format("%d %s échangées", n, plural(n, "batterie", "batteries"))
    end,
    restocked = function(n)
        return string.format("%d %s réapprovisionnés", n, plural(n, "type", "types"))
    end,
    sorted = function(n, c)
        return string.format("%d %s triés du surplus vers %d %s",
            n, plural(n, "objet", "objets"),
            c, plural(c, "conteneur", "conteneurs"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s triés du surplus vers %d %s (certains pleins)",
            n, plural(n, "objet", "objets"),
            c, plural(c, "conteneur", "conteneurs"))
    end,

    -- Status / error messages
    no_match              = "Aucun conteneur correspondant à proximité",
    no_match_full         = "Aucun conteneur correspondant à proximité (certains pleins)",
    nothing_to_stack      = "Rien à empiler",
    nothing_to_restock    = "Rien à réapprovisionner",
    battery_stashed       = function(n) return string.format("%d %s rangées", n, plural(n, "batterie", "batteries")) end,
    battery_pulled        = function(n) return string.format("%d %s retirées", n, plural(n, "batterie", "batteries")) end,
    no_inventory          = "Erreur : inventaire du joueur introuvable",
    no_container_open     = "Aucun conteneur ouvert",
    no_match_container    = "Aucun objet correspondant pour ce conteneur",
    no_overflow           = "Aucun casier de surplus à proximité",
    no_target             = "Aucun casier cible à proximité",
    no_overflow_sorted    = "Aucun objet n'a pu être trié du surplus",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Touche Quick Stack (redémarrage requis)",
    keybind_desc          = "Touche pour empiler les objets dans les conteneurs proches.",
    keybind_open_title    = "Touche empiler dans conteneur ouvert (redémarrage requis)",
    keybind_open_desc     = "Touche pour empiler les objets correspondants dans le conteneur ouvert.",
    keybind_overflow_title = "Touche trier le surplus (redémarrage requis)",
    keybind_overflow_desc  = "Touche pour trier le contenu du surplus dans les casiers correspondants.",
    cooldown_title        = "Délai de récupération (secondes)",
    cooldown_desc         = "Secondes minimum entre les appuis.",

    -- Stacking
    radius_title          = "Rayon de recherche (mètres)",
    radius_desc           = "Distance de recherche des conteneurs lors du Quick Stack. Limite du jeu : ~235 m.",
    stack_tools_title     = "Empiler les outils",
    stack_tools_desc      = "Permettre l'empilement des outils hors de l'inventaire.",
    stack_equip_title     = "Empiler l'équipement",
    stack_equip_desc      = "Permettre l'empilement de l'équipement et des batteries hors de l'inventaire.",
    stack_consum_title    = "Empiler les consommables",
    stack_consum_desc     = "Permettre l'empilement de nourriture, boissons et médicaments hors de l'inventaire.",

    -- Label routing
    label_routing_title   = "Routage par étiquette",
    label_routing_desc    = "Diriger les objets selon le texte de l'étiquette du casier. Désactiver pour le tri par type uniquement.",

    -- Restock
    food_title            = "Réserve de nourriture",
    food_desc             = "Quantité de nourriture à réapprovisionner après Quick Stack. 0 = désactivé.",
    drink_title           = "Réserve de boissons",
    drink_desc            = "Quantité de boissons à réapprovisionner après Quick Stack. 0 = désactivé.",
    heal_title            = "Réserve de soins",
    heal_desc             = "Quantité de soins à réapprovisionner après Quick Stack. 0 = désactivé.",
    battery_swap_title    = "Échange de batteries",
    battery_swap_desc     = "Échanger automatiquement les batteries vides contre des batteries plus chargées des chargeurs proches.",
    battery_budget_title  = "Budget batteries",
    battery_budget_desc   = "Batteries à garder dans l'inventaire. L'excédent va au Battery Terminal. 0 = mode échange.",
    powercell_budget_title = "Budget cellules d'énergie",
    powercell_budget_desc  = "Cellules à garder dans l'inventaire. L'excédent va au Power Cell Terminal. 0 = mode échange.",

    -- Auto-label
    auto_label_title      = "Auto-étiquetage maximum",
    auto_label_desc       = "Nommer automatiquement les casiers non étiquetés lors du dépôt. 0 = désactivé.",

    -- Notifications
    notify_title          = "Notifications toast",
    notify_desc           = "Afficher la notification texte à gauche après Quick Stack.",
    summary_title         = "Panneau de résumé",
    summary_desc          = "Afficher le panneau visuel de transfert avec icônes après Quick Stack.",
    summary_dur_title     = "Durée du résumé (secondes)",
    summary_dur_desc      = "Durée d'affichage du panneau de résumé.",
    summary_dest_title    = "Afficher les destinations",
    summary_dest_desc     = "Afficher les noms des conteneurs cibles dans le panneau de résumé.",
    summary_trunc_title   = "Tronquer les noms (caractères)",
    summary_trunc_desc    = "Tronquer les noms de destination à ce nombre de caractères. 0 = pas de troncature.",
    summary_left_title    = "Résumé à gauche",
    summary_left_desc     = "Déplacer le panneau de résumé à gauche de l'écran.",
    summary_scale_title   = "Échelle du texte du résumé",
    summary_scale_desc    = "Ajuster la taille du texte du panneau. 1.0 = par défaut.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s triés depuis les véhicules", n, plural(n, "objet", "objets")) end,
    tadpole_title         = "Trier depuis le Tadpole",
    tadpole_desc          = "Extraire les objets des inventaires Tadpole amarrés (châssis de transport + casiers portables) lors du Quick Stack.",

    -- Auto-sort on entry
    auto_sort_title       = "Tri automatique à l'entrée",
    auto_sort_desc        = "Lancer Quick Stack automatiquement en entrant dans un habitat.",
    auto_sort_cd_title    = "Délai du tri automatique (secondes)",
    auto_sort_cd_desc     = "Secondes minimum entre les tris automatiques. Évite les déclenchements répétés au moonpool.",
}

strings.it = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s in %d %s",
            n, plural(n, "oggetto", "oggetti"),
            c, plural(c, "contenitore", "contenitori"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s in %d %s (alcuni pieni)",
            n, plural(n, "oggetto", "oggetti"),
            c, plural(c, "contenitore", "contenitori"))
    end,
    swapped = function(n)
        return string.format("%d %s scambiate", n, plural(n, "batteria", "batterie"))
    end,
    restocked = function(n)
        return string.format("%d %s riforniti", n, plural(n, "tipo", "tipi"))
    end,
    sorted = function(n, c)
        return string.format("%d %s dall'overflow ordinati in %d %s",
            n, plural(n, "oggetto", "oggetti"),
            c, plural(c, "contenitore", "contenitori"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s dall'overflow ordinati in %d %s (alcuni pieni)",
            n, plural(n, "oggetto", "oggetti"),
            c, plural(c, "contenitore", "contenitori"))
    end,

    -- Status / error messages
    no_match              = "Nessun contenitore compatibile nelle vicinanze",
    no_match_full         = "Nessun contenitore compatibile nelle vicinanze (alcuni pieni)",
    nothing_to_stack      = "Niente da impilare",
    nothing_to_restock    = "Niente da rifornire",
    battery_stashed       = function(n) return string.format("%d %s riposte", n, plural(n, "batteria", "batterie")) end,
    battery_pulled        = function(n) return string.format("%d %s prelevate", n, plural(n, "batteria", "batterie")) end,
    no_inventory          = "Errore: inventario del giocatore non trovato",
    no_container_open     = "Nessun contenitore aperto",
    no_match_container    = "Nessun oggetto compatibile per questo contenitore",
    no_overflow           = "Nessun armadietto di overflow nelle vicinanze",
    no_target             = "Nessun armadietto destinazione nelle vicinanze",
    no_overflow_sorted    = "Nessun oggetto ordinabile dall'overflow",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Tasto Quick Stack (richiede riavvio)",
    keybind_desc          = "Tasto per impilare oggetti nei contenitori vicini.",
    keybind_open_title    = "Tasto impila in contenitore aperto (richiede riavvio)",
    keybind_open_desc     = "Tasto per impilare oggetti compatibili nel contenitore aperto.",
    keybind_overflow_title = "Tasto ordina overflow (richiede riavvio)",
    keybind_overflow_desc  = "Tasto per ordinare il contenuto dell'overflow negli armadietti compatibili.",
    cooldown_title        = "Tempo di attesa (secondi)",
    cooldown_desc         = "Secondi minimi tra le pressioni dei tasti.",

    -- Stacking
    radius_title          = "Raggio di ricerca (metri)",
    radius_desc           = "Distanza di ricerca dei contenitori durante Quick Stack. Limite di gioco: ~235 m.",
    stack_tools_title     = "Impila strumenti",
    stack_tools_desc      = "Permettere l'impilamento degli strumenti dall'inventario.",
    stack_equip_title     = "Impila equipaggiamento",
    stack_equip_desc      = "Permettere l'impilamento di equipaggiamento e batterie dall'inventario.",
    stack_consum_title    = "Impila consumabili",
    stack_consum_desc     = "Permettere l'impilamento di cibo, bevande e medicinali dall'inventario.",

    -- Label routing
    label_routing_title   = "Instradamento per etichetta",
    label_routing_desc    = "Instradare gli oggetti in base al testo dell'etichetta. Disattivare per usare solo il tipo.",

    -- Restock
    food_title            = "Scorta di cibo",
    food_desc             = "Quantità di cibo da rifornire dopo Quick Stack. 0 = disattivato.",
    drink_title           = "Scorta di bevande",
    drink_desc            = "Quantità di bevande da rifornire dopo Quick Stack. 0 = disattivato.",
    heal_title            = "Scorta di cure",
    heal_desc             = "Quantità di cure da rifornire dopo Quick Stack. 0 = disattivato.",
    battery_swap_title    = "Scambio batterie",
    battery_swap_desc     = "Scambiare automaticamente le batterie scariche con quelle più cariche dai caricatori vicini.",
    battery_budget_title  = "Budget batterie",
    battery_budget_desc   = "Batterie da tenere nell'inventario. L'eccesso va al Battery Terminal. 0 = modalità scambio.",
    powercell_budget_title = "Budget celle energetiche",
    powercell_budget_desc  = "Celle da tenere nell'inventario. L'eccesso va al Power Cell Terminal. 0 = modalità scambio.",

    -- Auto-label
    auto_label_title      = "Auto-etichetta massimo",
    auto_label_desc       = "Nominare automaticamente gli armadietti senza etichetta al deposito. 0 = disattivato.",

    -- Notifications
    notify_title          = "Notifiche toast",
    notify_desc           = "Mostrare la notifica testuale a sinistra dopo Quick Stack.",
    summary_title         = "Pannello di riepilogo",
    summary_desc          = "Mostrare il pannello visuale di trasferimento con icone dopo Quick Stack.",
    summary_dur_title     = "Durata del riepilogo (secondi)",
    summary_dur_desc      = "Tempo di permanenza del pannello di riepilogo sullo schermo.",
    summary_dest_title    = "Mostra destinazioni",
    summary_dest_desc     = "Mostrare i nomi dei contenitori destinazione nel pannello di riepilogo.",
    summary_trunc_title   = "Tronca nomi (caratteri)",
    summary_trunc_desc    = "Troncare i nomi di destinazione a questo numero di caratteri. 0 = nessun troncamento.",
    summary_left_title    = "Riepilogo a sinistra",
    summary_left_desc     = "Spostare il pannello di riepilogo a sinistra dello schermo.",
    summary_scale_title   = "Scala testo del riepilogo",
    summary_scale_desc    = "Scalare la dimensione del testo del pannello. 1.0 = predefinito.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s ordinati dai veicoli", n, plural(n, "oggetto", "oggetti")) end,
    tadpole_title         = "Ordina dal Tadpole",
    tadpole_desc          = "Prelevare oggetti dagli inventari Tadpole attraccati (telaio da trasporto + armadietti portatili) durante Quick Stack.",

    -- Auto-sort on entry
    auto_sort_title       = "Ordinamento automatico all'ingresso",
    auto_sort_desc        = "Eseguire Quick Stack automaticamente entrando in un habitat.",
    auto_sort_cd_title    = "Attesa ordinamento automatico (secondi)",
    auto_sort_cd_desc     = "Secondi minimi tra gli ordinamenti automatici. Evita attivazioni ripetute al moonpool.",
}

strings.ja = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d個のアイテムを%d個のコンテナに収納", n, c)
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d個のアイテムを%d個のコンテナに収納（一部満杯）", n, c)
    end,
    swapped = function(n)
        return string.format("バッテリー%d個を交換", n)
    end,
    restocked = function(n)
        return string.format("%d種類を補充", n)
    end,
    sorted = function(n, c)
        return string.format("オーバーフローから%d個のアイテムを%d個のコンテナに整理", n, c)
    end,
    sorted_full = function(n, c)
        return string.format("オーバーフローから%d個のアイテムを%d個のコンテナに整理（一部満杯）", n, c)
    end,

    -- Status / error messages
    no_match              = "近くに一致するコンテナがありません",
    no_match_full         = "近くに一致するコンテナがありません（一部満杯）",
    nothing_to_stack      = "収納するものがありません",
    nothing_to_restock    = "補充するものがありません",
    battery_stashed       = function(n) return string.format("バッテリー%d個を格納", n) end,
    battery_pulled        = function(n) return string.format("バッテリー%d個を取り出し", n) end,
    no_inventory          = "エラー: プレイヤーインベントリが見つかりません",
    no_container_open     = "コンテナが開いていません",
    no_match_container    = "このコンテナに一致するアイテムがありません",
    no_overflow           = "近くにオーバーフローロッカーがありません",
    no_target             = "近くにターゲットロッカーがありません",
    no_overflow_sorted    = "オーバーフローから整理できるアイテムがありません",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Quick Stackキー（再起動が必要）",
    keybind_desc          = "近くのコンテナにアイテムを収納するキー。",
    keybind_open_title    = "開いているコンテナに収納キー（再起動が必要）",
    keybind_open_desc     = "開いているコンテナに一致するアイテムを収納するキー。",
    keybind_overflow_title = "オーバーフロー整理キー（再起動が必要）",
    keybind_overflow_desc  = "オーバーフローの中身を一致するロッカーに整理するキー。",
    cooldown_title        = "クールダウン（秒）",
    cooldown_desc         = "キー押下の最小間隔。",

    -- Stacking
    radius_title          = "検索半径（メートル）",
    radius_desc           = "Quick Stack時のコンテナ検索距離。ゲーム上限は約235m。",
    stack_tools_title     = "ツールを収納",
    stack_tools_desc      = "ツールをインベントリからQuick Stackすることを許可。",
    stack_equip_title     = "装備を収納",
    stack_equip_desc      = "装備品とバッテリーをインベントリからQuick Stackすることを許可。",
    stack_consum_title    = "消耗品を収納",
    stack_consum_desc     = "食料、飲料、医療品をインベントリからQuick Stackすることを許可。",

    -- Label routing
    label_routing_title   = "ラベルルーティング",
    label_routing_desc    = "ロッカーのラベルに基づいてアイテムを振り分け。無効にするとタイプ一致のみ使用。",

    -- Restock
    food_title            = "食料の備蓄数",
    food_desc             = "Quick Stack後に補充する食料の数。0で無効。",
    drink_title           = "飲料の備蓄数",
    drink_desc            = "Quick Stack後に補充する飲料の数。0で無効。",
    heal_title            = "医療品の備蓄数",
    heal_desc             = "Quick Stack後に補充する医療品の数。0で無効。",
    battery_swap_title    = "バッテリー交換",
    battery_swap_desc     = "消耗したバッテリーを近くの充電器のより充電されたものと自動交換。",
    battery_budget_title  = "バッテリー予算",
    battery_budget_desc   = "インベントリに保持するバッテリー数。余剰はBattery Terminalへ。0=交換モード。",
    powercell_budget_title = "パワーセル予算",
    powercell_budget_desc  = "インベントリに保持するパワーセル数。余剰はPower Cell Terminalへ。0=交換モード。",

    -- Auto-label
    auto_label_title      = "自動ラベル上限",
    auto_label_desc       = "アイテム格納時にラベルのないロッカーを自動命名。0で無効。",

    -- Notifications
    notify_title          = "トースト通知",
    notify_desc           = "Quick Stack後に左側テキスト通知を表示。",
    summary_title         = "サマリーパネル",
    summary_desc          = "Quick Stack後にアイテムアイコン付きの転送サマリーを表示。",
    summary_dur_title     = "サマリー表示時間（秒）",
    summary_dur_desc      = "サマリーパネルの画面表示時間。",
    summary_dest_title    = "送り先を表示",
    summary_dest_desc     = "サマリーパネルに送り先コンテナ名を表示。",
    summary_trunc_title   = "名前を切り詰め（文字数）",
    summary_trunc_desc    = "送り先名をこの文字数に切り詰め。0=切り詰めなし。",
    summary_left_title    = "サマリーを左側に表示",
    summary_left_desc     = "サマリーパネルを画面左側に移動。",
    summary_scale_title   = "サマリーテキストの拡大率",
    summary_scale_desc    = "サマリーパネルのテキストサイズを調整。1.0=デフォルト。",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("車両から%d個のアイテムを整理", n) end,
    tadpole_title         = "Tadpoleから整理",
    tadpole_desc          = "Quick Stack時にドッキング中のTadpoleインベントリ（運搬シャーシ+ポータブルロッカー）からアイテムを取得。",

    -- Auto-sort on entry
    auto_sort_title       = "基地入場時に自動整理",
    auto_sort_desc        = "基地ハビタットに入った時にQuick Stackを自動実行。",
    auto_sort_cd_title    = "自動整理クールダウン（秒）",
    auto_sort_cd_desc     = "自動整理の最小間隔。ムーンプール境界での連続発動を防止。",
}

strings.ko = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: 아이템 %d개를 컨테이너 %d개에 수납", n, c)
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: 아이템 %d개를 컨테이너 %d개에 수납 (일부 가득 참)", n, c)
    end,
    swapped = function(n)
        return string.format("배터리 %d개 교체", n)
    end,
    restocked = function(n)
        return string.format("%d종 보충 완료", n)
    end,
    sorted = function(n, c)
        return string.format("오버플로에서 아이템 %d개를 컨테이너 %d개에 정리", n, c)
    end,
    sorted_full = function(n, c)
        return string.format("오버플로에서 아이템 %d개를 컨테이너 %d개에 정리 (일부 가득 참)", n, c)
    end,

    -- Status / error messages
    no_match              = "근처에 일치하는 컨테이너 없음",
    no_match_full         = "근처에 일치하는 컨테이너 없음 (일부 가득 참)",
    nothing_to_stack      = "수납할 항목 없음",
    nothing_to_restock    = "보충할 항목 없음",
    battery_stashed       = function(n) return string.format("배터리 %d개 보관", n) end,
    battery_pulled        = function(n) return string.format("배터리 %d개 꺼냄", n) end,
    no_inventory          = "오류: 플레이어 인벤토리를 찾을 수 없음",
    no_container_open     = "열린 컨테이너 없음",
    no_match_container    = "이 컨테이너에 맞는 아이템 없음",
    no_overflow           = "근처에 오버플로 보관함 없음",
    no_target             = "근처에 대상 보관함 없음",
    no_overflow_sorted    = "오버플로에서 정리할 아이템 없음",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Quick Stack 키 (재시작 필요)",
    keybind_desc          = "근처 컨테이너에 아이템을 수납하는 키.",
    keybind_open_title    = "열린 컨테이너에 수납 키 (재시작 필요)",
    keybind_open_desc     = "열린 컨테이너에 맞는 아이템을 수납하는 키.",
    keybind_overflow_title = "오버플로 정리 키 (재시작 필요)",
    keybind_overflow_desc  = "오버플로 내용을 맞는 보관함에 정리하는 키.",
    cooldown_title        = "쿨다운 (초)",
    cooldown_desc         = "키 입력 사이 최소 대기 시간.",

    -- Stacking
    radius_title          = "검색 반경 (미터)",
    radius_desc           = "Quick Stack 시 컨테이너 검색 거리. 게임 제한: ~235m.",
    stack_tools_title     = "도구 수납",
    stack_tools_desc      = "인벤토리에서 도구의 Quick Stack을 허용.",
    stack_equip_title     = "장비 수납",
    stack_equip_desc      = "인벤토리에서 장비 및 배터리의 Quick Stack을 허용.",
    stack_consum_title    = "소모품 수납",
    stack_consum_desc     = "인벤토리에서 음식, 음료, 의료품의 Quick Stack을 허용.",

    -- Label routing
    label_routing_title   = "라벨 라우팅",
    label_routing_desc    = "보관함 라벨 텍스트에 따라 아이템을 분배. 비활성화하면 유형 매칭만 사용.",

    -- Restock
    food_title            = "식량 비축량",
    food_desc             = "Quick Stack 후 보충할 식량 수. 0 = 비활성화.",
    drink_title           = "음료 비축량",
    drink_desc            = "Quick Stack 후 보충할 음료 수. 0 = 비활성화.",
    heal_title            = "치료 비축량",
    heal_desc             = "Quick Stack 후 보충할 치료 아이템 수. 0 = 비활성화.",
    battery_swap_title    = "배터리 교체",
    battery_swap_desc     = "방전된 배터리를 근처 충전기의 더 충전된 배터리와 자동 교체.",
    battery_budget_title  = "배터리 예산",
    battery_budget_desc   = "인벤토리에 보관할 배터리 수. 초과분은 Battery Terminal로. 0 = 교체 모드.",
    powercell_budget_title = "파워 셀 예산",
    powercell_budget_desc  = "인벤토리에 보관할 파워 셀 수. 초과분은 Power Cell Terminal로. 0 = 교체 모드.",

    -- Auto-label
    auto_label_title      = "자동 라벨 최대치",
    auto_label_desc       = "아이템 보관 시 라벨 없는 보관함을 자동 명명. 0 = 비활성화.",

    -- Notifications
    notify_title          = "토스트 알림",
    notify_desc           = "Quick Stack 후 왼쪽에 텍스트 알림을 표시.",
    summary_title         = "요약 패널",
    summary_desc          = "Quick Stack 후 아이템 아이콘이 있는 전송 요약 패널을 표시.",
    summary_dur_title     = "요약 표시 시간 (초)",
    summary_dur_desc      = "요약 패널이 화면에 표시되는 시간.",
    summary_dest_title    = "목적지 표시",
    summary_dest_desc     = "요약 패널에 대상 컨테이너 이름을 표시.",
    summary_trunc_title   = "이름 자르기 (글자 수)",
    summary_trunc_desc    = "대상 이름을 이 글자 수로 자르기. 0 = 자르지 않음.",
    summary_left_title    = "요약을 왼쪽에 표시",
    summary_left_desc     = "요약 패널을 화면 왼쪽으로 이동.",
    summary_scale_title   = "요약 텍스트 크기",
    summary_scale_desc    = "요약 패널 텍스트 크기 조절. 1.0 = 기본값.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("차량에서 아이템 %d개 정리", n) end,
    tadpole_title         = "Tadpole에서 정리",
    tadpole_desc          = "Quick Stack 시 도킹된 Tadpole 인벤토리(운반 섀시 + 휴대용 보관함)에서 아이템을 가져옴.",

    -- Auto-sort on entry
    auto_sort_title       = "기지 진입 시 자동 정리",
    auto_sort_desc        = "기지 거주지에 들어갈 때 Quick Stack을 자동 실행.",
    auto_sort_cd_title    = "자동 정리 쿨다운 (초)",
    auto_sort_cd_desc     = "자동 정리 사이 최소 대기 시간. 문풀 경계에서 반복 발동 방지.",
}

strings.pt = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s em %d %s",
            n, plural(n, "item", "itens"),
            c, plural(c, "contêiner", "contêineres"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s em %d %s (alguns cheios)",
            n, plural(n, "item", "itens"),
            c, plural(c, "contêiner", "contêineres"))
    end,
    swapped = function(n)
        return string.format("%d %s trocadas", n, plural(n, "bateria", "baterias"))
    end,
    restocked = function(n)
        return string.format("%d %s reabastecidos", n, plural(n, "tipo", "tipos"))
    end,
    sorted = function(n, c)
        return string.format("%d %s do overflow organizados em %d %s",
            n, plural(n, "item", "itens"),
            c, plural(c, "contêiner", "contêineres"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s do overflow organizados em %d %s (alguns cheios)",
            n, plural(n, "item", "itens"),
            c, plural(c, "contêiner", "contêineres"))
    end,

    -- Status / error messages
    no_match              = "Nenhum contêiner compatível por perto",
    no_match_full         = "Nenhum contêiner compatível por perto (alguns cheios)",
    nothing_to_stack      = "Nada para empilhar",
    nothing_to_restock    = "Nada para reabastecer",
    battery_stashed       = function(n) return string.format("%d %s guardadas", n, plural(n, "bateria", "baterias")) end,
    battery_pulled        = function(n) return string.format("%d %s retiradas", n, plural(n, "bateria", "baterias")) end,
    no_inventory          = "Erro: inventário do jogador não encontrado",
    no_container_open     = "Nenhum contêiner aberto",
    no_match_container    = "Nenhum item compatível para este contêiner",
    no_overflow           = "Nenhum armário de overflow por perto",
    no_target             = "Nenhum armário destino por perto",
    no_overflow_sorted    = "Nenhum item pôde ser organizado do overflow",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Tecla Quick Stack (requer reinício)",
    keybind_desc          = "Tecla para empilhar itens em contêineres próximos.",
    keybind_open_title    = "Tecla empilhar no contêiner aberto (requer reinício)",
    keybind_open_desc     = "Tecla para empilhar itens compatíveis no contêiner aberto.",
    keybind_overflow_title = "Tecla organizar overflow (requer reinício)",
    keybind_overflow_desc  = "Tecla para organizar o conteúdo do overflow em armários compatíveis.",
    cooldown_title        = "Tempo de espera (segundos)",
    cooldown_desc         = "Segundos mínimos entre pressionamentos de tecla.",

    -- Stacking
    radius_title          = "Raio de busca (metros)",
    radius_desc           = "Distância de busca de contêineres no Quick Stack. Limite do jogo: ~235 m.",
    stack_tools_title     = "Empilhar ferramentas",
    stack_tools_desc      = "Permitir empilhar ferramentas para fora do inventário.",
    stack_equip_title     = "Empilhar equipamentos",
    stack_equip_desc      = "Permitir empilhar equipamentos e baterias para fora do inventário.",
    stack_consum_title    = "Empilhar consumíveis",
    stack_consum_desc     = "Permitir empilhar comida, bebida e itens médicos para fora do inventário.",

    -- Label routing
    label_routing_title   = "Roteamento por rótulo",
    label_routing_desc    = "Direcionar itens com base no texto do rótulo do armário. Desativar para usar apenas tipo.",

    -- Restock
    food_title            = "Reserva de comida",
    food_desc             = "Quantidade de comida a reabastecer após Quick Stack. 0 = desativado.",
    drink_title           = "Reserva de bebida",
    drink_desc            = "Quantidade de bebida a reabastecer após Quick Stack. 0 = desativado.",
    heal_title            = "Reserva de cura",
    heal_desc             = "Quantidade de cura a reabastecer após Quick Stack. 0 = desativado.",
    battery_swap_title    = "Troca de baterias",
    battery_swap_desc     = "Trocar baterias descarregadas por outras mais carregadas de carregadores próximos.",
    battery_budget_title  = "Orçamento de baterias",
    battery_budget_desc   = "Baterias a manter no inventário. Excesso vai para Battery Terminal. 0 = modo troca.",
    powercell_budget_title = "Orçamento de células de energia",
    powercell_budget_desc  = "Células a manter no inventário. Excesso vai para Power Cell Terminal. 0 = modo troca.",

    -- Auto-label
    auto_label_title      = "Auto-rótulo máximo",
    auto_label_desc       = "Nomear automaticamente armários sem rótulo ao depositar itens. 0 = desativado.",

    -- Notifications
    notify_title          = "Notificações toast",
    notify_desc           = "Mostrar notificação de texto à esquerda após Quick Stack.",
    summary_title         = "Painel de resumo",
    summary_desc          = "Mostrar painel visual de transferência com ícones de itens após Quick Stack.",
    summary_dur_title     = "Duração do resumo (segundos)",
    summary_dur_desc      = "Tempo que o painel de resumo permanece na tela.",
    summary_dest_title    = "Mostrar destinos",
    summary_dest_desc     = "Mostrar nomes dos contêineres destino no painel de resumo.",
    summary_trunc_title   = "Truncar nomes (caracteres)",
    summary_trunc_desc    = "Truncar nomes de destino para este número de caracteres. 0 = sem truncar.",
    summary_left_title    = "Resumo à esquerda",
    summary_left_desc     = "Mover o painel de resumo para o lado esquerdo da tela.",
    summary_scale_title   = "Escala do texto do resumo",
    summary_scale_desc    = "Ajustar o tamanho do texto do painel. 1.0 = padrão.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s organizados dos veículos", n, plural(n, "item", "itens")) end,
    tadpole_title         = "Organizar do Tadpole",
    tadpole_desc          = "Puxar itens dos inventários de Tadpoles atracados (chassi de carga + armários portáteis) ao empilhar.",

    -- Auto-sort on entry
    auto_sort_title       = "Organizar ao entrar na base",
    auto_sort_desc        = "Executar Quick Stack automaticamente ao entrar em um habitat.",
    auto_sort_cd_title    = "Espera da organização automática (segundos)",
    auto_sort_cd_desc     = "Segundos mínimos entre organizações automáticas. Evita disparos repetidos no moonpool.",
}

strings.ru = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s в %d %s",
            n, plural_slavic(n, "предмет", "предмета", "предметов"),
            c, plural_slavic(c, "контейнер", "контейнера", "контейнеров"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s в %d %s (некоторые полны)",
            n, plural_slavic(n, "предмет", "предмета", "предметов"),
            c, plural_slavic(c, "контейнер", "контейнера", "контейнеров"))
    end,
    swapped = function(n)
        return string.format("Заменено %d %s", n, plural_slavic(n, "батарея", "батареи", "батарей"))
    end,
    restocked = function(n)
        return string.format("Пополнено %d %s", n, plural_slavic(n, "тип", "типа", "типов"))
    end,
    sorted = function(n, c)
        return string.format("%d %s из переполнения в %d %s",
            n, plural_slavic(n, "предмет", "предмета", "предметов"),
            c, plural_slavic(c, "контейнер", "контейнера", "контейнеров"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s из переполнения в %d %s (некоторые полны)",
            n, plural_slavic(n, "предмет", "предмета", "предметов"),
            c, plural_slavic(c, "контейнер", "контейнера", "контейнеров"))
    end,

    -- Status / error messages
    no_match              = "Рядом нет подходящих контейнеров",
    no_match_full         = "Рядом нет подходящих контейнеров (некоторые полны)",
    nothing_to_stack      = "Нечего складывать",
    nothing_to_restock    = "Нечего пополнять",
    battery_stashed       = function(n) return string.format("Убрано %d %s", n, plural_slavic(n, "батарея", "батареи", "батарей")) end,
    battery_pulled        = function(n) return string.format("Извлечено %d %s", n, plural_slavic(n, "батарея", "батареи", "батарей")) end,
    no_inventory          = "Ошибка: инвентарь игрока не найден",
    no_container_open     = "Контейнер не открыт",
    no_match_container    = "Нет подходящих предметов для этого контейнера",
    no_overflow           = "Рядом нет шкафчиков переполнения",
    no_target             = "Рядом нет целевых шкафчиков",
    no_overflow_sorted    = "Нет предметов для сортировки из переполнения",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Клавиша Quick Stack (требуется перезапуск)",
    keybind_desc          = "Клавиша для складывания предметов в ближайшие контейнеры.",
    keybind_open_title    = "Клавиша для открытого контейнера (требуется перезапуск)",
    keybind_open_desc     = "Клавиша для складывания подходящих предметов в открытый контейнер.",
    keybind_overflow_title = "Клавиша сортировки переполнения (требуется перезапуск)",
    keybind_overflow_desc  = "Клавиша для сортировки содержимого переполнения в подходящие шкафчики.",
    cooldown_title        = "Задержка (секунды)",
    cooldown_desc         = "Минимальный интервал между нажатиями.",

    -- Stacking
    radius_title          = "Радиус поиска (метры)",
    radius_desc           = "Дальность поиска контейнеров при Quick Stack. Лимит игры: ~235 м.",
    stack_tools_title     = "Складывать инструменты",
    stack_tools_desc      = "Разрешить складывание инструментов из инвентаря.",
    stack_equip_title     = "Складывать снаряжение",
    stack_equip_desc      = "Разрешить складывание снаряжения и батарей из инвентаря.",
    stack_consum_title    = "Складывать расходники",
    stack_consum_desc     = "Разрешить складывание еды, воды и медикаментов из инвентаря.",

    -- Label routing
    label_routing_title   = "Маршрутизация по меткам",
    label_routing_desc    = "Направлять предметы по тексту метки шкафчика. Отключить для сортировки только по типу.",

    -- Restock
    food_title            = "Запас еды",
    food_desc             = "Количество еды для пополнения после Quick Stack. 0 = отключено.",
    drink_title           = "Запас воды",
    drink_desc            = "Количество воды для пополнения после Quick Stack. 0 = отключено.",
    heal_title            = "Запас медикаментов",
    heal_desc             = "Количество медикаментов для пополнения после Quick Stack. 0 = отключено.",
    battery_swap_title    = "Замена батарей",
    battery_swap_desc     = "Автоматически менять разряженные батареи на более заряженные из ближайших зарядных станций.",
    battery_budget_title  = "Бюджет батарей",
    battery_budget_desc   = "Батареи для хранения в инвентаре. Излишки идут в Battery Terminal. 0 = режим обмена.",
    powercell_budget_title = "Бюджет энергоячеек",
    powercell_budget_desc  = "Энергоячейки для хранения в инвентаре. Излишки идут в Power Cell Terminal. 0 = режим обмена.",

    -- Auto-label
    auto_label_title      = "Авто-метка максимум",
    auto_label_desc       = "Автоматически именовать шкафчики без меток при закладке предметов. 0 = отключено.",

    -- Notifications
    notify_title          = "Всплывающие уведомления",
    notify_desc           = "Показывать текстовое уведомление слева после Quick Stack.",
    summary_title         = "Панель итогов",
    summary_desc          = "Показывать визуальную панель переноса с иконками предметов после Quick Stack.",
    summary_dur_title     = "Длительность итогов (секунды)",
    summary_dur_desc      = "Время отображения панели итогов на экране.",
    summary_dest_title    = "Показывать назначения",
    summary_dest_desc     = "Показывать названия контейнеров-назначений в панели итогов.",
    summary_trunc_title   = "Обрезать названия (символы)",
    summary_trunc_desc    = "Обрезать названия назначений до указанного числа символов. 0 = не обрезать.",
    summary_left_title    = "Итоги слева",
    summary_left_desc     = "Переместить панель итогов в левую часть экрана.",
    summary_scale_title   = "Масштаб текста итогов",
    summary_scale_desc    = "Масштаб текста панели итогов. 1.0 = по умолчанию.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s отсортировано из транспорта", n, plural_slavic(n, "предмет", "предмета", "предметов")) end,
    tadpole_title         = "Сортировка из Tadpole",
    tadpole_desc          = "Извлекать предметы из инвентарей пристыкованных Tadpole (грузовое шасси + портативные шкафчики) при Quick Stack.",

    -- Auto-sort on entry
    auto_sort_title       = "Авто-сортировка при входе на базу",
    auto_sort_desc        = "Автоматически запускать Quick Stack при входе в базу.",
    auto_sort_cd_title    = "Задержка авто-сортировки (секунды)",
    auto_sort_cd_desc     = "Минимальный интервал между авто-сортировками. Предотвращает повторные срабатывания у лунного бассейна.",
}

strings.uk = {
    -- Quick Stack notifications
    stacked = function(n, c)
        return string.format("Quick Stack: %d %s у %d %s",
            n, plural_slavic(n, "предмет", "предмети", "предметів"),
            c, plural_slavic(c, "контейнер", "контейнери", "контейнерів"))
    end,
    stacked_full = function(n, c)
        return string.format("Quick Stack: %d %s у %d %s (деякі повні)",
            n, plural_slavic(n, "предмет", "предмети", "предметів"),
            c, plural_slavic(c, "контейнер", "контейнери", "контейнерів"))
    end,
    swapped = function(n)
        return string.format("Замінено %d %s", n, plural_slavic(n, "батарею", "батареї", "батарей"))
    end,
    restocked = function(n)
        return string.format("Поповнено %d %s", n, plural_slavic(n, "тип", "типи", "типів"))
    end,
    sorted = function(n, c)
        return string.format("%d %s з переповнення у %d %s",
            n, plural_slavic(n, "предмет", "предмети", "предметів"),
            c, plural_slavic(c, "контейнер", "контейнери", "контейнерів"))
    end,
    sorted_full = function(n, c)
        return string.format("%d %s з переповнення у %d %s (деякі повні)",
            n, plural_slavic(n, "предмет", "предмети", "предметів"),
            c, plural_slavic(c, "контейнер", "контейнери", "контейнерів"))
    end,

    -- Status / error messages
    no_match              = "Поблизу немає відповідних контейнерів",
    no_match_full         = "Поблизу немає відповідних контейнерів (деякі повні)",
    nothing_to_stack      = "Немає чого складати",
    nothing_to_restock    = "Немає чого поповнювати",
    battery_stashed       = function(n) return string.format("Сховано %d %s", n, plural_slavic(n, "батарею", "батареї", "батарей")) end,
    battery_pulled        = function(n) return string.format("Дістано %d %s", n, plural_slavic(n, "батарею", "батареї", "батарей")) end,
    no_inventory          = "Помилка: інвентар гравця не знайдено",
    no_container_open     = "Контейнер не відкрито",
    no_match_container    = "Немає відповідних предметів для цього контейнера",
    no_overflow           = "Поблизу немає шафок переповнення",
    no_target             = "Поблизу немає цільових шафок",
    no_overflow_sorted    = "Немає предметів для сортування з переповнення",

    -- SN2ModSettings manifest
    mod_display           = "Quick Stack",

    -- Controls
    keybind_title         = "Клавіша Quick Stack (потрібен перезапуск)",
    keybind_desc          = "Клавіша для складання предметів у найближчі контейнери.",
    keybind_open_title    = "Клавіша для відкритого контейнера (потрібен перезапуск)",
    keybind_open_desc     = "Клавіша для складання відповідних предметів у відкритий контейнер.",
    keybind_overflow_title = "Клавіша сортування переповнення (потрібен перезапуск)",
    keybind_overflow_desc  = "Клавіша для сортування вмісту переповнення у відповідні шафки.",
    cooldown_title        = "Затримка (секунди)",
    cooldown_desc         = "Мінімальний інтервал між натисканнями.",

    -- Stacking
    radius_title          = "Радіус пошуку (метри)",
    radius_desc           = "Відстань пошуку контейнерів під час Quick Stack. Ліміт гри: ~235 м.",
    stack_tools_title     = "Складати інструменти",
    stack_tools_desc      = "Дозволити складання інструментів з інвентарю.",
    stack_equip_title     = "Складати спорядження",
    stack_equip_desc      = "Дозволити складання спорядження та батарей з інвентарю.",
    stack_consum_title    = "Складати витратні матеріали",
    stack_consum_desc     = "Дозволити складання їжі, напоїв та медикаментів з інвентарю.",

    -- Label routing
    label_routing_title   = "Маршрутизація за мітками",
    label_routing_desc    = "Направляти предмети за текстом мітки шафки. Вимкнути для сортування лише за типом.",

    -- Restock
    food_title            = "Запас їжі",
    food_desc             = "Кількість їжі для поповнення після Quick Stack. 0 = вимкнено.",
    drink_title           = "Запас напоїв",
    drink_desc            = "Кількість напоїв для поповнення після Quick Stack. 0 = вимкнено.",
    heal_title            = "Запас медикаментів",
    heal_desc             = "Кількість медикаментів для поповнення після Quick Stack. 0 = вимкнено.",
    battery_swap_title    = "Заміна батарей",
    battery_swap_desc     = "Автоматично міняти розряджені батареї на більш заряджені з найближчих зарядних станцій.",
    battery_budget_title  = "Бюджет батарей",
    battery_budget_desc   = "Батареї для зберігання в інвентарі. Надлишок йде до Battery Terminal. 0 = режим обміну.",
    powercell_budget_title = "Бюджет енергокомірок",
    powercell_budget_desc  = "Енергокомірки для зберігання в інвентарі. Надлишок йде до Power Cell Terminal. 0 = режим обміну.",

    -- Auto-label
    auto_label_title      = "Авто-мітка максимум",
    auto_label_desc       = "Автоматично називати шафки без міток при складанні предметів. 0 = вимкнено.",

    -- Notifications
    notify_title          = "Спливаючі сповіщення",
    notify_desc           = "Показувати текстове сповіщення зліва після Quick Stack.",
    summary_title         = "Панель підсумків",
    summary_desc          = "Показувати візуальну панель переміщення з іконками предметів після Quick Stack.",
    summary_dur_title     = "Тривалість підсумків (секунди)",
    summary_dur_desc      = "Час відображення панелі підсумків на екрані.",
    summary_dest_title    = "Показувати призначення",
    summary_dest_desc     = "Показувати назви контейнерів-призначень у панелі підсумків.",
    summary_trunc_title   = "Обрізати назви (символи)",
    summary_trunc_desc    = "Обрізати назви призначень до вказаної кількості символів. 0 = не обрізати.",
    summary_left_title    = "Підсумки зліва",
    summary_left_desc     = "Перемістити панель підсумків у ліву частину екрана.",
    summary_scale_title   = "Масштаб тексту підсумків",
    summary_scale_desc    = "Масштаб тексту панелі підсумків. 1.0 = за замовчуванням.",

    -- Vehicle sourcing
    tadpole_sourced       = function(n) return string.format("%d %s відсортовано з транспорту", n, plural_slavic(n, "предмет", "предмети", "предметів")) end,
    tadpole_title         = "Сортування з Tadpole",
    tadpole_desc          = "Витягувати предмети з інвентарів пристикованих Tadpole (вантажне шасі + портативні шафки) під час Quick Stack.",

    -- Auto-sort on entry
    auto_sort_title       = "Авто-сортування при вході на базу",
    auto_sort_desc        = "Автоматично запускати Quick Stack при вході на базу.",
    auto_sort_cd_title    = "Затримка авто-сортування (секунди)",
    auto_sort_cd_desc     = "Мінімальний інтервал між авто-сортуваннями. Запобігає повторним спрацюванням біля місячного басейну.",
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
gthread.defer(3000, function()
    lang.refresh()
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
