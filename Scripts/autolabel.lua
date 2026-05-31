-- Auto-Label: automatically name lockers based on items deposited manually.
-- When a player manually transfers an item into a container with a blank label,
-- the label is set to the item's display name. Subsequent unique items append
-- comma-separated until auto_label_max is reached.

local utils = require("utils")
local config = nil
local autolabel = {}

autolabel.suppress = false  -- set by main.lua during automated operations

function autolabel.init(cfg)
    config = cfg

    -- Hook fires when any inventory gains an item
    RegisterHook("/Script/UWEInventory.UWEInventoryComponent:OnItemAddedToInventory", function(self, inventoryId, inventoryItem)
        if autolabel.suppress then return end
        local maxLabels = config.AutoLabelMax or 0
        if maxLabels <= 0 then return end

        -- self is the UWEInventoryComponent that received the item
        -- Find the owning actor to check if it's a locker
        local owner = nil

        -- Try GetOwner first (standard UE pattern)
        local okOwner, result = pcall(function() return self:GetOwner() end)
        if okOwner and result and result:IsValid() then
            owner = result
        end

        -- Fallback: scan SN2Lockers and match by InventoryId
        if not owner then
            local invId = nil
            local okId = pcall(function() invId = inventoryId:get() end)
            if not okId then invId = inventoryId end

            local selfId = nil
            pcall(function() selfId = self.InventoryId end)

            local matchId = invId or selfId
            if matchId then
                local lockers = FindAllOf("SN2Locker")
                if lockers then
                    for _, locker in ipairs(lockers) do
                        if locker:IsValid() then
                            local okInv, inv = pcall(function() return locker.Inventory end)
                            if okInv and inv and inv:IsValid() then
                                local okLid, lid = pcall(function() return inv.InventoryId end)
                                if okLid and lid == matchId then
                                    owner = locker
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        if not owner or not owner:IsValid() then return end

        -- Only label SN2Lockers
        local okCls, className = pcall(function() return owner:GetClass():GetFName():ToString() end)
        if not okCls or className ~= "SN2Locker" then return end

        -- Check if label is blank
        local currentLabel = utils.getLockerLabel(owner)

        -- Read the item's display name from the InventoryItem parameter
        local itemStruct = nil
        local okGet, getResult = pcall(function() return inventoryItem:get() end)
        if okGet and getResult then
            itemStruct = getResult
        else
            -- inventoryItem might already be the struct
            itemStruct = inventoryItem
        end

        local info = utils.readItemInfo(itemStruct)
        if not info then return end
        local newName = info.displayName

        -- Get UGCComponent for setting label
        local okUgc, ugc = pcall(function() return owner.UGCComponent end)
        if not okUgc or not ugc then return end
        local okValid, valid = pcall(function() return ugc:IsValid() end)
        if not okValid or not valid then return end

        local key = { TagName = FName("None") }

        if not currentLabel or currentLabel == "" then
            -- Blank label: set to item name
            pcall(function() ugc:ServerSetPlayerText(key, newName) end)
        else
            -- Non-blank: check if we can append
            -- Count existing names
            local names = {}
            for name in currentLabel:gmatch("[^,]+") do
                local trimmed = name:match("^%s*(.-)%s*$")
                if trimmed ~= "" then
                    table.insert(names, trimmed)
                end
            end

            -- Check if already at max
            if #names >= maxLabels then return end

            -- Check if this name is already in the label
            for _, existing in ipairs(names) do
                if existing == newName then return end
            end

            -- Append
            table.insert(names, newName)
            local newLabel = table.concat(names, ", ")
            pcall(function() ugc:ServerSetPlayerText(key, newLabel) end)
        end
    end)
end

return autolabel
