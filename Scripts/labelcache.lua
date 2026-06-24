-- labelcache.lua — host-side locker label cache for global-pull routing.
-- Registry: inventoryId -> { label = rawString, pos = {X,Y,Z} }. Presence = "known".
--
-- Host capture: primed from currently-loaded lockers, then kept fresh as lockers stream in (a
-- gthread-paced batch pump -- NEVER the expensive label read synchronously in the per-actor BeginPlay
-- hook; that is the autolabel dispatch trap, reference_hot_hook_dispatch_cost) and on rename
-- (ServerSetPlayerText, the server-authoritative setter that fires on the host for host AND client
-- renames). Cleared on map load, then re-primed AND seeded from disk.
--
-- DISK PERSISTENCE (host / single-player only): the registry is persisted per-save so far-base lockers
-- stay KNOWN across sessions. Without it, a host spawned away from base can't route to base lockers
-- (not loaded -> not cached) and items scatter to a nearby locker by type-count. Keyed by the save
-- GUID; debounced atomic writes; clients do not persist (they don't route via this cache).
--
-- CRITICAL: inventoryIds are REASSIGNED on every world reload (exit-to-menu / full restart), so the
-- persisted invId is useless across sessions. The STABLE identity is the locker's world POSITION. On
-- load we therefore IGNORE the persisted invId and re-resolve the CURRENT invId for each persisted
-- locker by matching its position against `ss:GetStorageContainerForInventory(id).InventoryLocation`
-- (distance-readable -- works for far/unloaded lockers). A live capture always wins; isDepositTarget
-- re-validates each id live at routing time.

local UEHelpers = require("UEHelpers")
local utils = require("utils")
local gthread = require("gthread")

local labelcache = {}
local _registry = {}              -- invId -> { label, pos }
local _queue = {}                 -- ring of locker actors awaiting capture (head/tail, O(1))
local _qHead, _qTail = 1, 0

-- ===== Disk persistence state =====
local _persistKey = nil           -- per-save file key; nil disables persistence
local _isHost = false             -- resolved at loadPersisted (HasAuthority); only host/SP persists
local _dirty, _writeScheduled = false, false
-- MP/SP both read HighestInventoryId as 0, so bound the load-time re-resolution scan. A blind scan of
-- 1..1024 (IsInventoryValid + InventoryLocation) is ~3-4ms, one-time, on the +5s post-load defer.
local PERSIST_SCAN_CAP = 1024

function labelcache.reset()
    _registry = {}
    _queue = {}
    _qHead, _qTail = 1, 0
    -- Disable persistence until loadPersisted re-resolves, so a write during the reset->reload window
    -- can't overwrite a save's file with an empty registry.
    _isHost, _persistKey, _dirty = false, nil, false
end

-- ===== Persistence helpers =====
local function saveKey()
    local save = FindFirstOf("UWESaveGame")
    if not save then return nil end
    local key = nil
    pcall(function()
        local sid = save.MetaData.SaveId  -- FGuid; format is deterministic per save (verified 2026-06-23)
        key = string.format("%08X%08X%08X%08X", sid.A, sid.B, sid.C, sid.D)
    end)
    return key
end

local function isAuthority()
    local pc = UEHelpers:GetPlayerController()
    if not pc or not pc:IsValid() then return false end
    local ok, auth = pcall(function() return pc:HasAuthority() end)
    return ok and auth == true
end

local function persistPath()
    if not _persistKey then return nil end
    local modDir = debug.getinfo(1, "S").source:match("@(.*/)")
    return modDir and (modDir .. "../labelcache_" .. _persistKey .. ".txt") or nil
end

-- File: line 1 "v1"; then one "invId|x|y|z|label" per locker (label LAST so it may contain '|').
local function writeToDisk()
    if not _isHost then return end
    local path = persistPath()
    if not path then return end
    local lines = { "v1" }
    for id, e in pairs(_registry) do
        local p = e.pos or {}
        local label = (e.label or ""):gsub("[\r\n]", " ")
        lines[#lines + 1] = string.format("%d|%.1f|%.1f|%.1f|%s", id, p.X or 0, p.Y or 0, p.Z or 0, label)
    end
    local f = io.open(path .. ".tmp", "w")
    if not f then return end
    f:write(table.concat(lines, "\n"))
    f:close()
    os.remove(path)                 -- Windows: os.rename won't overwrite an existing file
    os.rename(path .. ".tmp", path)
end

-- Debounced write: one write ~5s after the first change in a batch (gthread, never ExecuteWithDelay).
local function markDirty()
    if not _isHost or not _persistKey then return end
    _dirty = true
    if _writeScheduled then return end
    _writeScheduled = true
    gthread.defer(5000, function()
        _writeScheduled = false
        if _dirty then _dirty = false; pcall(writeToDisk) end
    end)
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
--- actually know about) instead of 1..8192 — the fail-closed domain IS the cache. Read-only snapshot;
--- ascending order preserves the old 1..N tie-break order.
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
    markDirty()
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
--- so this is safe to run on every world load and is inherently warm-reload / double-fire safe.
function labelcache.primeFromLoaded()
    local lockers = FindAllOf("SN2Locker")
    if lockers then for _, a in ipairs(lockers) do labelcache.enqueueLocker(a) end end
end

--- Re-read LIVE labels of all currently-loaded lockers straight into the registry. Called once per
--- quickstack press (infinite range) BEFORE the global scans, so loaded lockers always route on their
--- live label. Far / unloaded lockers keep their captured (or persisted) snapshot.
function labelcache.refreshLoaded()
    local lockers = utils.getLoadedActors("SN2Locker")
    if not lockers then return end
    for _, a in ipairs(lockers) do captureActor(a) end
end

--- Seed the registry from the per-save disk file (host/SP only), RE-RESOLVING the current invId for each
--- persisted locker by POSITION. invIds are reassigned on every world reload, so the persisted id is
--- ignored -- we blind-scan the live inventory subsystem, read each valid id's InventoryLocation (works
--- for far/unloaded lockers), and match it to a persisted position. Fills gaps only (live capture wins).
--- Also resolves the host/SP gate + per-save key that gate subsequent writes. No-op on clients / at the
--- main menu / when no file exists.
function labelcache.loadPersisted()
    _isHost = isAuthority()
    if not _isHost then _persistKey = nil; return end
    _persistKey = saveKey()
    local path = persistPath()
    local f = path and io.open(path, "r")
    if not f then return end
    -- Parse persisted {pos,label}; the stored invId is STALE across a world reload, so it's discarded.
    local persisted = {}
    if f:read("*l") == "v1" then
        for line in f:lines() do
            local _id, x, y, z, label = line:match("^(%d+)|([%-%d.]+)|([%-%d.]+)|([%-%d.]+)|(.*)$")
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            if x and y and z then persisted[#persisted + 1] = { x = x, y = y, z = z, label = label or "" } end
        end
    end
    f:close()
    if #persisted == 0 then return end

    local ss = FindFirstOf("UWEInventorySubsystem")
    if not ss then return end
    local TOL2 = 50 * 50            -- 50cm tolerance² (same locker matches within <1cm; nearest lockers ~>1m apart)
    local count = 0
    for id = 1, PERSIST_SCAN_CAP do
        if not _registry[id] then   -- a live capture already owns this id -> leave it
            local px, py, pz
            pcall(function()
                if ss:IsInventoryValid(id) then
                    local loc = ss:GetStorageContainerForInventory(id).InventoryLocation
                    px, py, pz = loc.X, loc.Y, loc.Z
                end
            end)
            if px then
                for _, e in ipairs(persisted) do
                    local dx, dy, dz = px - e.x, py - e.y, pz - e.z
                    if dx * dx + dy * dy + dz * dz < TOL2 then
                        _registry[id] = { label = e.label, pos = { X = px, Y = py, Z = pz } }
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    print(string.format("[QuickStack] labelcache: re-resolved %d/%d persisted locker(s) by position\n",
        count, #persisted))
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

-- Shortly after EVERY world load (not just mod load): seed from disk, then re-prime from the live world.
-- loadPersisted runs FIRST (fills gaps) so the batch pump's live captures overwrite loaded lockers with
-- fresh data while far persisted lockers are retained. The map-load hook resets first, so this also
-- recovers from a warm quit-to-menu reload / the documented LoadMapPostHook double-fire.
local function primeSoon()
    gthread.defer(5000, function()
        pcall(labelcache.loadPersisted)
        pcall(labelcache.primeFromLoaded)
    end)
end

RegisterLoadMapPostHook(function()
    labelcache.reset()
    primeSoon()
end)

primeSoon()  -- mod load / hot reload catch-up

return labelcache
