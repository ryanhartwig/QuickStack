-- Temporary probe: find all inventory-holding actors near the player
local UEHelpers = require("UEHelpers")

RegisterKeyBind(Key.M, function()
    ExecuteInGameThread(function()
        print("\n[QuickStack] === CONTAINER CLASS PROBE ===\n")
        local controller = UEHelpers:GetPlayerController()
        local pawn = controller.Pawn
        local playerLoc = pawn:K2_GetActorLocation()

        -- Check all UWEInventoryComponent instances and find their owners
        local invComps = FindAllOf("UWEInventoryComponent")
        if not invComps then
            print("[QuickStack] No UWEInventoryComponent instances found\n")
            return
        end

        print(string.format("[QuickStack] Found %d UWEInventoryComponent instances\n", #invComps))

        for i, inv in ipairs(invComps) do
            if inv:IsValid() then
                local ok, outer = pcall(function() return inv:GetOuter() end)
                if ok and outer and outer:IsValid() then
                    local ok2, outerLoc = pcall(function() return outer:K2_GetActorLocation() end)
                    if ok2 then
                        local dx = outerLoc.X - playerLoc.X
                        local dy = outerLoc.Y - playerLoc.Y
                        local dz = outerLoc.Z - playerLoc.Z
                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz) / 100

                        if dist < 30 then
                            local ok3, className = pcall(function() return outer:GetClass():GetFName():ToString() end)
                            local ok4, fullName = pcall(function() return outer:GetFullName() end)
                            print(string.format("[QuickStack] %.1fm - Class: %s\n", dist,
                                ok3 and className or "unknown"))
                            print(string.format("[QuickStack]         Name: %s\n",
                                ok4 and fullName or "unknown"))

                            -- Check if it's an SN2Locker
                            local ok5, isSN2 = pcall(function()
                                return outer:IsA(StaticFindObject("/Script/Subnautica2.SN2Locker"))
                            end)
                            print(string.format("[QuickStack]         IsA SN2Locker: %s\n",
                                ok5 and tostring(isSN2) or "check failed"))
                        end
                    end
                end
            end
        end

        print("[QuickStack] === END PROBE ===\n\n")
    end)
end)

print("[QuickStack] Container probe loaded - press M near a Tailing Chest\n")
