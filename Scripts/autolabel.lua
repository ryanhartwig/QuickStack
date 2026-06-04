-- Auto-Label: automatically name lockers based on items deposited manually.
-- When a player manually transfers an item into a container with a blank label,
-- the label is set to the item's display name. Subsequent unique items append
-- comma-separated until auto_label_max is reached.

local UEHelpers = require("UEHelpers")
local utils = require("utils")
local network = require("network")
local config = nil
local autolabel = {}

autolabel.suppress = false  -- set by main.lua during automated operations

--- Get the open container's InventoryComponent, its InventoryId, and the owning actor.
--- Returns invComp, invId, ownerActor or nil, nil, nil.
local function getOpenContainerInfo()
    local tabs = FindAllOf("WBP_TabInventory_C")
    if not tabs then return nil, nil, nil end
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
                            local okId, invId = pcall(function() return invComp.InventoryId end)
                            local okOwner, owner = pcall(function() return invComp:GetOwner() end)
                            if okId and okOwner and owner and owner:IsValid() then
                                return invComp, invId, owner
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

--- Parse a label string into a list of trimmed names.
local function parseNames(label)
    local names = {}
    if not label or label == "" then return names end
    for name in label:gmatch("[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(names, trimmed)
        end
    end
    return names
end

function autolabel.init(cfg)
    config = cfg

    -- Cache: one getOpenContainerInfo() call per container, not per hook fire.
    -- Also caches parsed label state to avoid repeated getLockerLabel + parsing.
    -- Cache invalidates when a different inventoryId is seen (player opens a different container).
    local cache = { invId = nil, owner = nil, names = nil, rawLabel = nil }

    -- Cache player inventory ID to skip hook fires for player inventory (item pulls)
    local playerInvId = nil

    RegisterHook("/Script/UWEInventory.UWEInventoryComponent:OnItemAddedToInventory", function(self, inventoryId, inventoryItem)
        if autolabel.suppress then return end

        -- Cheap early-out when auto-label is disabled. Uses the cached config value,
        -- which is refreshed on every QuickStack keybind press (registerCooldownBind) and
        -- once per container open below -- so we never touch SN2ModSettings on this hot
        -- path while disabled. This hook fires ~10x per transfer, so per-fire cross-mod
        -- reads (the old refreshModSettings here) froze the game thread.
        if (config.AutoLabelMax or 0) <= 0 then return end

        -- Get the hook's inventory ID (cheap)
        local hookInvId = nil
        pcall(function() hookInvId = inventoryId:get() end)
        if not hookInvId then return end

        -- Cache and skip player inventory (covers pulling items out of lockers)
        if not playerInvId then
            pcall(function()
                local pawn = utils.GetPlayerPawn()
                if pawn then
                    playerInvId = pawn.InventoryComponent.InventoryId
                end
            end)
        end
        if hookInvId == playerInvId then return end

        -- Cache: only scan when the target inventory changes (once per new container)
        if hookInvId ~= cache.invId then
            -- Pick up a live auto_label_max slider change cheaply (one cross-mod read),
            -- once per container -- not a full refreshModSettings on every hook fire.
            config.refreshOne("auto_label_max")
            if (config.AutoLabelMax or 0) <= 0 then
                cache = { invId = hookInvId, owner = nil, names = nil, rawLabel = nil }
                return
            end
            local _, openInvId, owner = getOpenContainerInfo()
            if openInvId == hookInvId and owner then
                local currentLabel = utils.getLockerLabel(owner) or ""
                local names = parseNames(currentLabel)
                cache = {
                    invId = hookInvId,
                    owner = owner,
                    names = names,
                    rawLabel = currentLabel,
                }
            else
                cache = { invId = hookInvId, owner = nil, names = nil, rawLabel = nil }
                return
            end
        end

        local maxLabels = config.AutoLabelMax or 0
        if maxLabels <= 0 then return end

        -- Fast bail: not a valid target
        if not cache.owner then return end

        -- Staleness check: if the label was manually changed or cleared, re-read it
        local realLabel = utils.getLockerLabel(cache.owner) or ""
        if realLabel ~= cache.rawLabel then
            cache.names = parseNames(realLabel)
            cache.rawLabel = realLabel
        end

        -- Check if at max
        if #cache.names >= maxLabels then return end

        -- Read the item's display name
        local itemStruct = nil
        pcall(function() itemStruct = inventoryItem:get() end)
        if not itemStruct then return end

        local info = utils.readItemInfo(itemStruct)
        if not info then return end
        local newName = info.displayName

        -- Check if this name is already in the cached names
        for _, existing in ipairs(cache.names) do
            if existing == newName then return end
        end

        -- Get UGCComponent from the owning actor
        local okUgc, ugc = pcall(function() return cache.owner.UGCComponent end)
        if not okUgc or not ugc then return end
        local okValid, valid = pcall(function() return ugc:IsValid() end)
        if not okValid or not valid then return end

        -- Build new label
        table.insert(cache.names, newName)
        local newLabel = table.concat(cache.names, ", ")

        -- Set label: host calls directly, clients delegate via network
        if network.isHost() then
            local key = { TagName = FName("None") }
            pcall(function() ugc:ServerSetPlayerText(key, newLabel) end)
        else
            network.sendToHost("SETLABEL", tostring(cache.invId) .. "|" .. newLabel)
        end
        cache.rawLabel = newLabel
    end)
end

return autolabel
