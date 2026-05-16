-- QuickStack Mod for Subnautica 2
-- Automatically stacks inventory items into nearby matching containers

local config = require("config")
local utils = require("utils")

print("[QuickStack] Mod loaded\n")

-- Map config keybind string to UE4SS Key constant
local keyMap = {
    A = Key.A, B = Key.B, C = Key.C, D = Key.D, E = Key.E,
    F = Key.F, G = Key.G, H = Key.H, I = Key.I, J = Key.J,
    K = Key.K, L = Key.L, M = Key.M, N = Key.N, O = Key.O,
    P = Key.P, Q = Key.Q, R = Key.R, S = Key.S, T = Key.T,
    U = Key.U, V = Key.V, W = Key.W, X = Key.X, Y = Key.Y,
    Z = Key.Z,
    F1 = Key.F1, F2 = Key.F2, F3 = Key.F3, F4 = Key.F4,
    F5 = Key.F5, F6 = Key.F6, F7 = Key.F7, F8 = Key.F8,
}

local bindKey = keyMap[config.Keybind]
if not bindKey then
    print(string.format("[QuickStack] ERROR: Unknown keybind '%s', defaulting to N\n", config.Keybind))
    bindKey = Key.N
end

-- Cooldown state
local lastActivation = 0

RegisterKeyBind(bindKey, function()
    ExecuteInGameThread(function()
        local now = os.clock()
        if now - lastActivation < config.Cooldown then
            return -- on cooldown, silent ignore
        end
        lastActivation = now

        local pawn = utils.GetPlayerPawn()
        if pawn then
            local loc = pawn:K2_GetActorLocation()
            print(string.format("[QuickStack] Player at: X=%.1f Y=%.1f Z=%.1f\n", loc.X, loc.Y, loc.Z))
            utils.Notify("Quick Stack activated!", config)
        end
    end)
end)
