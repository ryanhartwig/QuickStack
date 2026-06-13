local config = {}

-- Default values
config.Keybind = "N"
config.KeybindOpen = "G"
config.Radius = 25
config.Cooldown = 1.0
config.Notify = true
config.StackTools = false
config.StackEquipment = false
config.StackConsumables = false
config.KeepTypes = {}
config.LabelPrefix = ""
config.ExcludePrefix = "%x"
config.OverflowPrefix = "%o"
config.LabelRouting = true
config.KeybindOverflow = "H"
config.KeybindRestock = ""
config.BatterySwap = true
config.RestockBatteryCount = 0
config.RestockPowerCellCount = 0
config.RestockFoodCount = 2
config.RestockDrinkCount = 2
config.RestockHealCount = 2
config.LabelMaxChars = 200
config.SummaryPanel = true
config.SummaryShowDestination = true
config.SummaryDuration = 6
config.SummaryPosition = "right"
config.SummaryTextScale = 0.8
config.SummaryTruncate = 20
config.AutoLabelMax = 0
config.SortFromTadpole = false
config.AutoSortOnEntry = false
config.AutoSortCooldown = 60
config.InfiniteRange = false

-- Parse a comma-separated string into a table
local function parseList(str)
    local result = {}
    if not str or str == "" then return result end
    for item in str:gmatch("[^,]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end
    return result
end

-- Parse config.txt from the mod's root folder
local function loadConfig()
    local modDir = debug.getinfo(1, "S").source:match("@(.*/)")
    local configPath = modDir .. "../config.txt"

    local file = io.open(configPath, "r")
    if not file then
        print("[QuickStack] config.txt not found, using defaults\n")
        return
    end

    for line in file:lines() do
        -- Skip empty lines and comments
        if line ~= "" and not line:match("^#") then
            local key, value = line:match("^([%w_]+)%s*=%s*(.*)$")
            if key and value then
                value = value:match("^%s*(.-)%s*$") -- trim whitespace
                if key == "keybind" then
                    config.Keybind = value:upper()
                elseif key == "keybind_open" then
                    config.KeybindOpen = value:upper()
                elseif key == "radius" then
                    config.Radius = tonumber(value) or 25
                elseif key == "cooldown" then
                    config.Cooldown = tonumber(value) or 1.0
                elseif key == "notify" then
                    config.Notify = (value == "true")
                elseif key == "stack_tools" then
                    config.StackTools = (value == "true")
                elseif key == "stack_equipment" then
                    config.StackEquipment = (value == "true")
                elseif key == "stack_consumables" then
                    config.StackConsumables = (value == "true")
                elseif key == "keep_types" then
                    config.KeepTypes = parseList(value)
                elseif key == "label_prefix" then
                    config.LabelPrefix = value
                elseif key == "exclude_prefix" then
                    config.ExcludePrefix = value
                elseif key == "overflow_prefix" then
                    config.OverflowPrefix = value
                elseif key == "keybind_overflow" then
                    config.KeybindOverflow = value:upper()
                elseif key == "keybind_restock" then
                    config.KeybindRestock = value ~= "" and value:upper() or ""
                elseif key == "label_routing" then
                    config.LabelRouting = (value == "true")
                elseif key == "battery_swap" then
                    config.BatterySwap = (value == "true")
                elseif key == "restock_battery_count" then
                    config.RestockBatteryCount = tonumber(value) or 0
                elseif key == "restock_powercell_count" then
                    config.RestockPowerCellCount = tonumber(value) or 0
                elseif key == "restock_food_count" then
                    config.RestockFoodCount = tonumber(value) or 2
                elseif key == "restock_drink_count" then
                    config.RestockDrinkCount = tonumber(value) or 2
                elseif key == "restock_heal_count" then
                    config.RestockHealCount = tonumber(value) or 2
                elseif key == "label_max_chars" then
                    config.LabelMaxChars = tonumber(value) or 50
                elseif key == "summary_panel" then
                    config.SummaryPanel = (value == "true")
                elseif key == "summary_show_destination" then
                    config.SummaryShowDestination = (value == "true")
                elseif key == "summary_duration" then
                    config.SummaryDuration = tonumber(value) or 6
                elseif key == "summary_truncate" then
                    config.SummaryTruncate = tonumber(value) or 0
                elseif key == "summary_position" then
                    local v = value:lower()
                    if v == "left" or v == "right" then config.SummaryPosition = v end
                elseif key == "summary_text_scale" then
                    config.SummaryTextScale = tonumber(value) or 1.0
                elseif key == "auto_label_max" then
                    config.AutoLabelMax = tonumber(value) or 0
                elseif key == "sort_from_tadpole" then
                    config.SortFromTadpole = (value == "true")
                elseif key == "auto_sort_on_entry" then
                    config.AutoSortOnEntry = (value == "true")
                elseif key == "auto_sort_cooldown" then
                    config.AutoSortCooldown = tonumber(value) or 60
                elseif key == "infinite_range" then
                    config.InfiniteRange = (value == "true")
                end
            end
        end
    end

    file:close()
    print(string.format("[QuickStack] Config loaded: keybind=%s, keybind_open=%s, radius=%d, cooldown=%.1f, notify=%s, stack_tools=%s, stack_equipment=%s, keep_types=%d items, battery_swap=%s, battery_budget=%d, summary_duration=%ds\n",
        config.Keybind, config.KeybindOpen, config.Radius, config.Cooldown,
        tostring(config.Notify), tostring(config.StackTools), tostring(config.StackEquipment),
        #config.KeepTypes, tostring(config.BatterySwap), config.RestockBatteryCount, config.SummaryDuration))
end

loadConfig()

-- Override with SN2ModSettings values if available (optional dependency)
-- transform: optional function to post-process the value before storing
local settingsMap = {
    -- Controls
    { key = "keybind",             field = "Keybind",           type = "string", transform = string.upper },
    { key = "keybind_open",        field = "KeybindOpen",       type = "string", transform = string.upper },
    { key = "keybind_overflow",    field = "KeybindOverflow",   type = "string", transform = string.upper },
    -- Stacking
    { key = "radius",              field = "Radius",            type = "number" },
    { key = "stack_tools",         field = "StackTools",        type = "boolean" },
    { key = "stack_equipment",     field = "StackEquipment",    type = "boolean" },
    { key = "stack_consumables",   field = "StackConsumables",  type = "boolean" },
    -- Label routing
    { key = "label_routing",       field = "LabelRouting",      type = "boolean" },
    -- Restock
    { key = "restock_food_count",  field = "RestockFoodCount",  type = "number" },
    { key = "restock_drink_count", field = "RestockDrinkCount", type = "number" },
    { key = "restock_heal_count",  field = "RestockHealCount",  type = "number" },
    { key = "battery_swap",        field = "BatterySwap",       type = "boolean" },
    { key = "restock_battery_count", field = "RestockBatteryCount", type = "number" },
    { key = "restock_powercell_count", field = "RestockPowerCellCount", type = "number" },
    -- Auto-label
    { key = "auto_label_max",      field = "AutoLabelMax",      type = "number" },
    -- Notifications
    { key = "notify",              field = "Notify",            type = "boolean" },
    { key = "summary_panel",       field = "SummaryPanel",      type = "boolean" },
    { key = "summary_duration",    field = "SummaryDuration",   type = "number" },
    { key = "summary_show_dest",   field = "SummaryShowDestination", type = "boolean" },
    { key = "summary_truncate",    field = "SummaryTruncate",   type = "number" },
    { key = "summary_position_left", field = "SummaryPosition", type = "boolean",
      transform = function(v) return v and "left" or "right" end },
    { key = "summary_text_scale",  field = "SummaryTextScale",  type = "number", raw = true },
    -- Vehicle sourcing
    { key = "sort_from_tadpole",   field = "SortFromTadpole",   type = "boolean" },
    -- Auto-sort
    { key = "auto_sort_on_entry",  field = "AutoSortOnEntry",   type = "boolean" },
    { key = "auto_sort_cooldown",  field = "AutoSortCooldown",  type = "number" },
    -- Infinite range (global pull)
    { key = "infinite_range",      field = "InfiniteRange",     type = "boolean" },
}

function config.refreshModSettings()
    if not ModRef then return end
    for _, entry in ipairs(settingsMap) do
        local ok, val = pcall(function()
            return ModRef:GetSharedVariable("SN2ModSettings/QuickStack/" .. entry.key)
        end)
        if ok and val ~= nil and type(val) == entry.type then
            -- SN2ModSettings sliders return floats — round to int unless raw
            if entry.type == "number" and not entry.raw then
                val = math.floor(val + 0.5)
            end
            if entry.transform then
                val = entry.transform(val)
            end
            config[entry.field] = val
        end
    end
end

--- Refresh a single SN2ModSettings value by config key. Cheap -- one GetSharedVariable
--- call -- for hot paths (e.g. the auto-label hook) where a full refreshModSettings
--- (one cross-mod call per setting, ~25) would stutter the game thread.
function config.refreshOne(key)
    if not ModRef then return end
    for _, entry in ipairs(settingsMap) do
        if entry.key == key then
            local ok, val = pcall(function()
                return ModRef:GetSharedVariable("SN2ModSettings/QuickStack/" .. entry.key)
            end)
            if ok and val ~= nil and type(val) == entry.type then
                if entry.type == "number" and not entry.raw then
                    val = math.floor(val + 0.5)
                end
                if entry.transform then
                    val = entry.transform(val)
                end
                config[entry.field] = val
            end
            return
        end
    end
end

config.refreshModSettings()

return config
