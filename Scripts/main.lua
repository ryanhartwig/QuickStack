-- QuickStack Mod for Subnautica 2
-- Automatically stacks inventory items into nearby matching containers

print("[QuickStack] Mod loaded\n")

RegisterKeyBind(Key.N, function()
    ExecuteInGameThread(function()
        print("[QuickStack] N key pressed - Quick Stack triggered!\n")
    end)
end)
