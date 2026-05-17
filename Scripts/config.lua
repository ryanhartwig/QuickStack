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
config.LabelRouting = true
config.BatterySwap = true

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
                elseif key == "label_routing" then
                    config.LabelRouting = (value == "true")
                elseif key == "battery_swap" then
                    config.BatterySwap = (value == "true")
                end
            end
        end
    end

    file:close()
    print(string.format("[QuickStack] Config loaded: keybind=%s, keybind_open=%s, radius=%d, cooldown=%.1f, notify=%s, stack_tools=%s, stack_equipment=%s, keep_types=%d items, battery_swap=%s\n",
        config.Keybind, config.KeybindOpen, config.Radius, config.Cooldown,
        tostring(config.Notify), tostring(config.StackTools), tostring(config.StackEquipment),
        #config.KeepTypes, tostring(config.BatterySwap)))
end

loadConfig()

return config
