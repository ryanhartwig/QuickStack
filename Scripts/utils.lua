local UEHelpers = require("UEHelpers")
local utils = {}

--- Calculate 3D distance between two actors
---@param actorA userdata Actor with K2_GetActorLocation
---@param actorB userdata Actor with K2_GetActorLocation
---@return number distance in Unreal units (1 unit = 1 cm, so 100 = 1 meter)
function utils.GetDistance(actorA, actorB)
    local locA = actorA:K2_GetActorLocation()
    local locB = actorB:K2_GetActorLocation()
    local dx = locA.X - locB.X
    local dy = locA.Y - locB.Y
    local dz = locA.Z - locB.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Get the player pawn (physical character in the world)
---@return userdata|nil The player pawn actor, or nil if not found
function utils.GetPlayerPawn()
    local controller = UEHelpers:GetPlayerController()
    if not controller:IsValid() then
        print("[QuickStack] ERROR: Could not get player controller\n")
        return nil
    end
    local ok, pawn = pcall(function() return controller.Pawn end)
    if not ok or not pawn or not pawn:IsValid() then
        print("[QuickStack] ERROR: Could not get player pawn\n")
        return nil
    end
    return pawn
end

--- Show a notification message to the player using the game's toast system
---@param message string The message to display
---@param config table The mod config (needs config.Notify)
function utils.Notify(message, config)
    if not config.Notify then return end
    -- Console output
    print(string.format("[QuickStack] %s\n", message))
    -- In-game toast via UWEGameplayMessageBPLibrary::NotifyLocalPlayerSimple
    local ok, err = pcall(function()
        local msgLib = StaticFindObject("/Script/UWEGameplayMessageRuntime.Default__UWEGameplayMessageBPLibrary")
        if msgLib then
            local pawn = utils.GetPlayerPawn()
            if pawn then
                msgLib:NotifyLocalPlayerSimple(pawn, { TagName = FName("Notification.Info") }, FText(message))
            end
        end
    end)
    if not ok then
        print(string.format("[QuickStack] Toast failed: %s\n", tostring(err)))
    end
end

--- Convert radius in meters to Unreal units
--- Unreal Engine uses centimeters as base unit
---@param meters number Distance in meters
---@return number Distance in Unreal units (centimeters)
function utils.MetersToUnits(meters)
    return meters * 100
end

return utils
