-- labelcache.lua — host-side locker label cache for global-pull routing.
-- Registry: inventoryId -> { label = rawString, pos = {X,Y,Z} }. Presence = "known".
--
-- Phase 1 (host capture): primed from currently-loaded lockers, then kept fresh as lockers stream
-- in (a gthread-paced batch pump -- NEVER the expensive label read synchronously in the per-actor
-- BeginPlay hook; that is the autolabel dispatch trap, reference_hot_hook_dispatch_cost) and on
-- rename (ServerSetPlayerText, the server-authoritative setter that fires on the host for host AND
-- client renames). Cleared on map load. Phase 2 persists to disk; Phase 4 syncs to clients.
-- Routing reads via labelcache.get. `pos` is captured for a future id-reuse guard (reject a recycled
-- inventoryId whose live position no longer matches the captured one) -- NOT yet enforced by any scan.

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

--- Snapshot of known inventory ids, ascending. Global-pull scans iterate THIS (the lockers we
--- actually know about) instead of 1..8192 — the fail-closed domain IS the cache. Before this,
--- the restock + overflow scans each ran isDepositTarget (subsystem calls) across all 8192 ids
--- just to discard the unknown ones, which dominated the per-press cost (~90ms). Iterating the
--- ~few dozen known ids drops that to a handful of isDepositTarget calls. Read-only snapshot;
--- safe to hold across a scan (ascending order preserves the old 1..N tie-break order).
function labelcache.knownIds()
    local ids = {}
    for id in pairs(_registry) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
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

--- Enqueue every currently-loaded locker for (batch-pumped) capture. FindAllOf reads the LIVE world,
--- so this is safe to run on every world load and is inherently warm-reload / double-fire safe -- it
--- re-admits warm actors that never re-fire BeginPlay, and a later call just re-reads the world.
function labelcache.primeFromLoaded()
    local lockers = FindAllOf("SN2Locker")
    if lockers then for _, a in ipairs(lockers) do labelcache.enqueueLocker(a) end end
end

--- Re-read LIVE labels of all currently-loaded lockers (tens of actors) straight into the registry.
--- Called once per quickstack press (infinite range) BEFORE the global scans, so loaded lockers
--- always route on their live label -- the event-driven cache alone goes stale on MP clients (the
--- ServerSetPlayerText rename hook fires on the host only) and is empty after a warm reload (no
--- BeginPlay re-fire). Far / unloaded lockers keep their captured snapshot. This is the cheap
--- restoration of the pre-cache per-press harvest, scoped to the loaded set.
function labelcache.refreshLoaded()
    local lockers = utils.getLoadedActors("SN2Locker")
    if not lockers then return end
    for _, a in ipairs(lockers) do captureActor(a) end
end

-- Rename capture (low-frequency, host-authoritative).
RegisterHook("/Script/UWEUserGeneratedContent.UWEUGCComponent:ServerSetPlayerText",
    function(self, textKey, playerText)
        pcall(function()
            local comp = self:get()
            local owner = comp and comp:GetOwner()
            if owner then captureActor(owner) end
        end)
    end)

-- Prime shortly after EVERY world load (not just mod load): the map-load hook resets the registry,
-- so without a re-prime the cache stays empty after a warm quit-to-menu reload (only ~8 actors
-- re-fire BeginPlay) or the documented LoadMapPostHook double-fire. Mirrors utils.primeAllSoon.
local function primeSoon()
    gthread.defer(5000, function() pcall(labelcache.primeFromLoaded) end)
end

RegisterLoadMapPostHook(function()
    labelcache.reset()
    primeSoon()
end)

primeSoon()  -- mod load / hot reload catch-up

return labelcache
