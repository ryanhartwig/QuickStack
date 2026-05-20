--- QuickStack: Item category detection module
--- Battery detection, charge reading, item keep rules, consumable categorization

local categories = {}
local config = nil

function categories.init(cfg)
    config = cfg
end

-- Battery/power cell type patterns
local BATTERY_PATTERNS = {"battery", "powercell", "powercellv2"}

-- Consumable patterns by category
local FOOD_PATTERNS = {
    "nutrient", "block", "pavlova", "souvlaki", "temaki", "chutney",
    "jerky", "salad", "saturn", "mash", "clump", "shavings", "cookie",
}
local DRINK_PATTERNS = { "water", "isotonic", "drink" }
local HEAL_PATTERNS = { "firstaid", "first_aid", "medkit", "med_kit" }

-- Priority order (lower index = better). Used for restock preference.
categories.FOOD_PRIORITY = {
    "pavlova", "souvlaki", "temaki", "chutney", "jerky", "salad",
    "saturn", "mash", "clump", "shavings", "cookie", "block",
}
categories.DRINK_PRIORITY = { "isotonic", "water" }
categories.HEAL_PRIORITY = { "enhanced", "advanced", "basic", "firstaid", "medkit" }

function categories.isBatteryType(typeName)
    local lname = string.lower(typeName)
    for _, pattern in ipairs(BATTERY_PATTERNS) do
        if string.find(lname, pattern, 1, true) then return true end
    end
    return false
end

function categories.isFoodType(typeName)
    local lname = string.lower(typeName)
    for _, pattern in ipairs(FOOD_PATTERNS) do
        if string.find(lname, pattern, 1, true) then return true end
    end
    return false
end

function categories.isDrinkType(typeName)
    local lname = string.lower(typeName)
    for _, pattern in ipairs(DRINK_PATTERNS) do
        if string.find(lname, pattern, 1, true) then return true end
    end
    return false
end

function categories.isHealType(typeName)
    local lname = string.lower(typeName)
    for _, pattern in ipairs(HEAL_PATTERNS) do
        if string.find(lname, pattern, 1, true) then return true end
    end
    return false
end

--- Returns the consumable category ("food", "drink", "heal") or nil
function categories.getConsumableCategory(typeName)
    if categories.isFoodType(typeName) then return "food" end
    if categories.isDrinkType(typeName) then return "drink" end
    if categories.isHealType(typeName) then return "heal" end
    return nil
end

--- Get the priority score for a consumable (lower = better)
--- Returns 999 if not in the priority list
function categories.getPriority(typeName, category)
    local list
    if category == "food" then list = categories.FOOD_PRIORITY
    elseif category == "drink" then list = categories.DRINK_PRIORITY
    elseif category == "heal" then list = categories.HEAL_PRIORITY
    else return 999 end

    local lname = string.lower(typeName)
    for i, pattern in ipairs(list) do
        if string.find(lname, pattern, 1, true) then return i end
    end
    return 999
end

--- Read charge level from an inventory item's Attributes
--- Returns current charge, max charge (or nil, nil if unreadable)
function categories.readCharge(itemStruct)
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
function categories.shouldKeepItem(typeName, fullName)
    local lname = string.lower(fullName)

    if not config.StackTools then
        if string.find(lname, "/tools/", 1, true) then return true end
    end

    if not config.StackEquipment then
        if string.find(lname, "/equipment/", 1, true) then return true end
        if string.find(lname, "/equippable/", 1, true) then return true end
        if string.find(lname, "/deployables/", 1, true) then return true end
    end

    -- Batteries: protected by equipment setting OR battery swap setting
    -- Even with stack_equipment=true, battery swap needs them in inventory
    if categories.isBatteryType(typeName) then
        if not config.StackEquipment or config.BatterySwap then return true end
    end

    if not config.StackConsumables then
        if categories.getConsumableCategory(typeName) then return true end
    end

    for _, keepType in ipairs(config.KeepTypes) do
        if typeName == keepType then return true end
    end

    return false
end

return categories
