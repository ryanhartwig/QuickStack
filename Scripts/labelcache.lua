-- labelcache.lua — host-side locker label cache for global-pull routing.
-- Registry: inventoryId -> { label = rawString, pos = {X,Y,Z} }. Presence = "known".
--
-- Phase 1 (host capture): primed from currently-loaded lockers, then kept fresh as lockers stream
-- in (a gthread-paced batch pump -- NEVER the expensive label read synchronously in the per-actor
-- BeginPlay hook; that is the autolabel dispatch trap, reference_hot_hook_dispatch_cost) and on
-- rename (ServerSetPlayerText, the server-authoritative setter that fires on the host for host AND
-- client renames). Cleared on map load. Phase 2 persists to disk; Phase 4 syncs to clients.
-- Routing reads via labelcache.get; `pos` lets routing reject a recycled inventoryId whose live
-- position no longer matches the captured one (red-team C2 id-reuse guard).

local UEHelpers = require("UEHelpers")
local utils = require("utils")
local gthread = require("gthread")

local labelcache = {}
local _registry = {}              -- invId -> { label, pos }
local _queue = {}                 -- ring of locker actors awaiting capture (head/tail, O(1))
local _qHead, _qTail = 1, 0

function labelcache.reset()
    _registry = {}
    _queue = {}
    _qHead, _qTail = 1, 0
end

--- Routing lookup: { label, pos } or nil (unknown).
function labelcache.get(invId)
    return _registry[invId]
end

function labelcache.count()
    local n = 0
    for _ in pairs(_registry) do n = n + 1 end
    return n
end

-- Read label + position for a loaded locker actor and store it (a few cheap UObject reads).
local function captureActor(actor)
    pcall(function()
        if not actor or not actor:IsValid() then return end
        local inv = actor.Inventory
        if not (inv and inv:IsValid()) then return end
        local id = inv.InventoryId
        local label = utils.getLockerLabel(actor) or ""
        local loc = actor:K2_GetActorLocation()
        _registry[id] = { label = label, pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }
    end)
end

--- Enqueue a streamed-in locker for capture. Trivial — called from the BeginPlay hook; the
--- expensive label read happens on the batch pump below, off the streaming burst.
function labelcache.enqueueLocker(actor)
    _qTail = _qTail + 1
    _queue[_qTail] = actor
end

-- Batch pump: capture a few per tick so a mega-base streaming wave can't stall the frame.
local CAPTURES_PER_TICK = 8
LoopInGameThreadWithDelay(50, function()
    local n = 0
    while _qHead <= _qTail and n < CAPTURES_PER_TICK do
        local a = _queue[_qHead]
        _queue[_qHead] = nil
        _qHead = _qHead + 1
        captureActor(a)
        n = n + 1
    end
    if _qHead > _qTail then _queue, _qHead, _qTail = {}, 1, 0 end  -- fully drained → reset pointers
    return false
end)

-- Prime from already-loaded lockers shortly after load (BeginPlay only fires for NEW actors).
gthread.defer(5000, function()
    local lockers = FindAllOf("SN2Locker")
    if lockers then for _, a in ipairs(lockers) do labelcache.enqueueLocker(a) end end
end)

-- Rename capture (low-frequency, host-authoritative).
RegisterHook("/Script/UWEUserGeneratedContent.UWEUGCComponent:ServerSetPlayerText",
    function(self, textKey, playerText)
        pcall(function()
            local comp = self:get()
            local owner = comp and comp:GetOwner()
            if owner then captureActor(owner) end
        end)
    end)

RegisterLoadMapPostHook(function() labelcache.reset() end)

return labelcache
