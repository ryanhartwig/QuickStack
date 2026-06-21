-- gthread.lua — Game-thread work queue. Replaces ExecuteInGameThread/ExecuteWithDelay.
--
-- WHY (do not "simplify" back to ExecuteInGameThread/ExecuteWithDelay):
-- UE4SS runs LoopAsync/ExecuteWithDelay bodies on the mod's async thread WITHOUT the
-- mutex that serializes game-thread and keybind Lua (LuaMod.cpp:6440-6505). Lua executed
-- there (and the unguarded luaL_ref ExecuteInGameThread does on the calling thread,
-- LuaMod.cpp ~4025) races the game thread on the registry freelist. UE4SS then resolves
-- the corrupted ref via get_function_ref OUTSIDE its TRY block (LuaMod.cpp:3683) -> Lua
-- panic -> abort() -> the game's Sentry handler silently terminates the process (exit
-- 0x40000015). Confirmed by symbolized minidumps; known upstream as RE-UE4SS issue #1180
-- (fix in progress on the 'luastability' branch). Until the SN2 UE4SS fork ships that
-- fix, this pattern is mandatory. See sn2-modding docs/tasks/terraformer-crash-investigation.md.
--
-- This queue is pure Lua. The single LoopInGameThreadWithDelay pump below creates ONE
-- registry ref at mod load and never churns it. require()-ing this module from multiple
-- QuickStack files yields the same cached instance with a single pump.

local gthread = {}

local _queue = {} -- array of { at = <os.clock deadline in seconds>, fn = function }

---Run fn on the game thread at the next pump tick (~15ms). Drop-in for ExecuteInGameThread.
---@param fn function
function gthread.run(fn)
    _queue[#_queue + 1] = { at = 0, fn = fn }
end

---Run fn on the game thread after delayMs milliseconds. Drop-in for ExecuteWithDelay.
---@param delayMs number
---@param fn function
function gthread.defer(delayMs, fn)
    _queue[#_queue + 1] = { at = os.clock() + (delayMs or 0) / 1000, fn = fn }
end

LoopInGameThreadWithDelay(15, function()
    if #_queue == 0 then return false end
    local now = os.clock()
    local i = 1
    while i <= #_queue do
        local item = _queue[i]
        if now >= item.at then
            table.remove(_queue, i)
            local ok, err = pcall(item.fn)
            if not ok then
                print(string.format("[QuickStack:GThread] deferred callback error: %s\n", tostring(err)))
            end
            -- do not advance i: next item shifted into slot i
        else
            i = i + 1
        end
    end
    return false
end)

return gthread
