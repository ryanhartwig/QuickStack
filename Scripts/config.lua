local config = {}

-- Default values
config.Keybind = "N"
config.KeybindOpen = "F"
config.Radius = 25
config.Cooldown = 1.0
config.Notify = true

-- Parse config.txt from the mod's root folder
local function loadConfig()
    local modDir = debug.getinfo(1, "S").source:match("@(.*/)")
    -- Go up one level from Scripts/ to the mod root
    local configPath = modDir .. "../config.txt"

    local file = io.open(configPath, "r")
    if not file then
        print("[QuickStack] config.txt not found, using defaults\n")
        return
    end

    for line in file:lines() do
        -- Skip empty lines and comments
        if line ~= "" and not line:match("^#") then
            local key, value = line:match("^(%w+)%s*=%s*(.+)$")
            if key and value then
                value = value:match("^%s*(.-)%s*$") -- trim whitespace
                if key == "keybind" then
                    config.Keybind = value:upper()
                elseif key == "keybind_open" then
                    config.KeybindOpen = value:upper()
                elseif key == "radius" then
                    config.Radius = tonumber(value) or 15
                elseif key == "cooldown" then
                    config.Cooldown = tonumber(value) or 1.0
                elseif key == "notify" then
                    config.Notify = (value == "true")
                end
            end
        end
    end

    file:close()
    print(string.format("[QuickStack] Config loaded: keybind=%s, keybind_open=%s, radius=%d, cooldown=%.1f, notify=%s\n",
        config.Keybind, config.KeybindOpen, config.Radius, config.Cooldown, tostring(config.Notify)))
end

loadConfig()

return config
