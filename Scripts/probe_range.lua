-- Temporary probe: check how many SN2Locker and UWEInventoryComponent instances
-- exist at various distances from the player

local UEHelpers = require("UEHelpers")

RegisterKeyBind(Key.M, function()
    ExecuteInGameThread(function()
        print("\n[QuickStack] === RANGE PROBE ===\n")
        local controller = UEHelpers:GetPlayerController()
        local pawn = controller.Pawn
        local playerLoc = pawn:K2_GetActorLocation()

        local lockers = FindAllOf("SN2Locker")
        if not lockers then
            print("[QuickStack] No SN2Locker instances found\n")
            return
        end

        print(string.format("[QuickStack] Total SN2Locker instances in memory: %d\n", #lockers))

        -- Count by distance buckets
        local buckets = {25, 50, 100, 150, 200, 300, 500, 1000}
        local counts = {}
        for _, b in ipairs(buckets) do counts[b] = 0 end

        local farthest = 0
        for _, locker in ipairs(lockers) do
            if locker:IsValid() then
                local ok, loc = pcall(function() return locker:K2_GetActorLocation() end)
                if ok then
                    local dx = loc.X - playerLoc.X
                    local dy = loc.Y - playerLoc.Y
                    local dz = loc.Z - playerLoc.Z
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz) / 100 -- meters
                    if dist > farthest then farthest = dist end
                    for _, b in ipairs(buckets) do
                        if dist <= b then counts[b] = counts[b] + 1 end
                    end
                end
            end
        end

        print("[QuickStack] Lockers by distance:\n")
        for _, b in ipairs(buckets) do
            print(string.format("[QuickStack]   <= %dm: %d lockers\n", b, counts[b]))
        end
        print(string.format("[QuickStack] Farthest locker: %.0fm\n", farthest))

        print("[QuickStack] === END RANGE PROBE ===\n\n")
    end)
end)

print("[QuickStack] Range probe loaded - press M\n")
