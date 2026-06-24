--- QuickStack: Category Labels
--- categories.txt maps a CATEGORY NAME -> a comma-separated list of item-name fragments. At routing time
--- (matching.scoreWithTokens), a locker-label fragment that STRICTLY matches a category name
--- (case-insensitive) expands to that category's list -- so a locker labeled "Components" routes exactly
--- like the fully typed-out label would. SINGLE-LEVEL expansion (a spliced fragment is never re-expanded).
---
--- Host / single-player loads categories.txt here. In multiplayer, clients receive the host's map via RPC
--- (Phase 2) and do NOT read their own file -- the host is authoritative. NOTE: this is distinct from
--- categories.lua (item-type detection for restock / keep rules) -- a different concept, kept separate.

local categorylabels = {}

-- { [lower(trim(name))] = "raw csv value string" }  -- prebuilt hash for O(1) lookup, built once at load.
local _map = {}

--- (Re)load categories.txt from the mod root (sibling of config.txt). Replaces the map wholesale.
function categorylabels.load()
    _map = {}
    local modDir = debug.getinfo(1, "S").source:match("@(.*/)")
    if not modDir then return end
    local file = io.open(modDir .. "../categories.txt", "r")
    if not file then return end  -- no file -> empty map -> labels behave exactly as today
    local count = 0
    for line in file:lines() do
        if line ~= "" and not line:match("^#") then
            -- name = everything before the first '=' (allows multi-word names like "Adv Components");
            -- value = the rest of the line (a comma-separated fragment list).
            local name, value = line:match("^%s*([^=]-)%s*=%s*(.*)$")
            if name and value and name ~= "" then
                if name:find("[\n|]") then  -- guard RPC wire-framing chars in the NAME (Phase 2 sync)
                    print(string.format("[QuickStack] categories.txt: skipping invalid name %q\n", name))
                else
                    local v = value:match("^%s*(.-)%s*$")  -- trim
                    if v ~= "" then
                        _map[name:lower()] = v
                        count = count + 1
                    end
                end
            end
        end
    end
    file:close()
    print(string.format("[QuickStack] categories.txt: loaded %d categor%s\n", count, count == 1 and "y" or "ies"))
end

--- Expand a locker label: replace any comma-fragment that STRICTLY matches a category name with that
--- category's fragment list. Returns the label UNCHANGED when no fragment is a category (the common case
--- -> byte-identical, so non-category labels score exactly as today). Single-level: a spliced fragment is
--- NOT re-checked against the category map (no recursion / infinite loops). Cheap: one comma split + an
--- O(1) hash lookup per fragment, and an early-out when no categories are loaded.
function categorylabels.expand(label)
    if not label or label == "" or next(_map) == nil then return label end
    local parts, expanded = {}, false
    for frag in label:gmatch("[^,]+") do
        local trimmed = frag:match("^%s*(.-)%s*$")
        local repl = _map[trimmed:lower()]
        if repl then
            parts[#parts + 1] = repl
            expanded = true
        else
            parts[#parts + 1] = trimmed
        end
    end
    if not expanded then return label end
    return table.concat(parts, ", ")
end

--- Number of loaded categories (status / debug).
function categorylabels.count()
    local n = 0
    for _ in pairs(_map) do n = n + 1 end
    return n
end

return categorylabels
