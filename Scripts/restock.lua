local categories = require("categories")
local utils = require("utils")
local config = nil

local restock = {}

function restock.init(cfg)
    config = cfg
end

--- Build restock candidates from a list of inventory components.
--- Scans for consumable items with category/priority data.
function restock.buildCandidates(lockerInvs)
    local candidates = {}
    for _, inv in ipairs(lockerInvs) do
        local ok, items = pcall(function() return inv:GetItems() end)
        if ok and items then
            for _, item in ipairs(items) do
                local s = item:get()
                local typeName = utils.readItemTypeName(s)
                if typeName then
                    local category = categories.getConsumableCategory(typeName)
                    if category then
                        local displayName = nil
                        pcall(function() displayName = s.ItemType.Name:ToString() end)
                        table.insert(candidates, {
                            itemId = s.ItemId,
                            inventoryId = s.InventoryId,
                            typeName = typeName,
                            displayName = displayName or typeName:gsub("^DA_", ""):gsub("_ItemType$", ""),
                            itemType = s.ItemType,
                            category = category,
                            priority = categories.getPriority(typeName, category),
                        })
                    end
                end
            end
        end
    end
    return candidates
end

--- Execute the restock pass: fill shortfalls, then upgrade worst for best.
--- candidates: from buildCandidates() or globalpull.buildRestockCandidates()
--- moveFn (optional): function(itemId, fromId, toId) -> bool. Default = the local
---   component path (playerInv:MoveItemBetweenInventories). Infinite range passes the
---   server-authoritative subsystem move so far-locker pulls work map-wide.
--- Returns restockDetails table for the summary panel.
function restock.execute(playerInv, candidates, moveFn)
    local restockDetails = {}
    if #candidates == 0 then return restockDetails end

    local playerInvId = playerInv.InventoryId
    moveFn = moveFn or function(itemId, fromId, toId)
        return (pcall(function() playerInv:MoveItemBetweenInventories(itemId, fromId, toId) end))
    end

    -- Scan player's current consumables
    local heldByCategory = { food = {}, drink = {}, heal = {} }
    local currentCounts = { food = 0, drink = 0, heal = 0 }
    local playerItems = playerInv:GetItems()
    for _, item in ipairs(playerItems) do
        local s = item:get()
        local typeName = utils.readItemTypeName(s)
        if typeName then
            local cat = categories.getConsumableCategory(typeName)
            if cat then
                currentCounts[cat] = currentCounts[cat] + 1
                table.insert(heldByCategory[cat], {
                    itemId = s.ItemId,
                    inventoryId = s.InventoryId,
                    typeName = typeName,
                    priority = categories.getPriority(typeName, cat),
                })
            end
        end
    end

    -- Sort candidates best first, held items worst first
    table.sort(candidates, function(a, b) return a.priority < b.priority end)
    for _, items in pairs(heldByCategory) do
        table.sort(items, function(a, b) return a.priority > b.priority end)
    end

    -- Phase 1: Fill shortfalls
    local budgets = {
        food  = math.max(0, (config.RestockFoodCount or 0)  - currentCounts.food),
        drink = math.max(0, (config.RestockDrinkCount or 0) - currentCounts.drink),
        heal  = math.max(0, (config.RestockHealCount or 0)  - currentCounts.heal),
    }

    local usedCandidates = {}
    for i, candidate in ipairs(candidates) do
        local cat = candidate.category
        if budgets[cat] and budgets[cat] > 0 then
            local ok = moveFn(candidate.itemId, candidate.inventoryId, playerInvId)
            if ok then
                budgets[cat] = budgets[cat] - 1
                usedCandidates[i] = true
                utils.recordDetail(restockDetails, candidate.typeName, candidate.itemType, candidate.displayName, "Locker")
            end
        end
    end

    -- Phase 2: Upgrade worst for best
    -- Re-scan player consumables after Phase 1 pulls (snapshot may be stale)
    heldByCategory = { food = {}, drink = {}, heal = {} }
    playerItems = playerInv:GetItems()
    for _, item in ipairs(playerItems) do
        local s = item:get()
        local typeName = utils.readItemTypeName(s)
        if typeName then
            local cat = categories.getConsumableCategory(typeName)
            if cat then
                table.insert(heldByCategory[cat], {
                    itemId = s.ItemId,
                    inventoryId = s.InventoryId,
                    typeName = typeName,
                    priority = categories.getPriority(typeName, cat),
                })
            end
        end
    end
    for _, items in pairs(heldByCategory) do
        table.sort(items, function(a, b) return a.priority > b.priority end)
    end

    local configBudgets = {
        food  = config.RestockFoodCount or 0,
        drink = config.RestockDrinkCount or 0,
        heal  = config.RestockHealCount or 0,
    }
    for _, cat in ipairs({"food", "drink", "heal"}) do
        if configBudgets[cat] == 0 then goto nextCat end
        local held = heldByCategory[cat]
        if #held == 0 then goto nextCat end

        for i, candidate in ipairs(candidates) do
            if usedCandidates[i] then goto nextCandidate end
            if candidate.category ~= cat then goto nextCandidate end

            local worst = held[1]
            if not worst or candidate.priority >= worst.priority then break end

            local stashOk = moveFn(worst.itemId, worst.inventoryId, candidate.inventoryId)
            if stashOk then
                local pullOk = moveFn(candidate.itemId, candidate.inventoryId, playerInvId)
                if pullOk then
                    usedCandidates[i] = true
                    table.remove(held, 1)
                    utils.recordDetail(restockDetails, candidate.typeName, candidate.itemType, candidate.displayName, "Locker")
                else
                    moveFn(worst.itemId, candidate.inventoryId, worst.inventoryId)
                end
            end

            ::nextCandidate::
        end

        ::nextCat::
    end

    return restockDetails
end

--- Check if any restock category has a budget > 0.
function restock.isEnabled()
    return (config.RestockFoodCount or 0) > 0
        or (config.RestockDrinkCount or 0) > 0
        or (config.RestockHealCount or 0) > 0
end

return restock
