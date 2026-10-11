local Util = {}

Util.Debug = false

-- Mod's own log file (appended, not overwritten when the game is relaunched)
local logFile = nil

function Util.OpenLog(path)
    local ok, f = pcall(io.open, path, "a")
    if ok and f then
        logFile = f
        logFile:write(string.format("\n===== Session %s =====\n", os.date("%Y-%m-%d %H:%M:%S")))
        logFile:flush()
    end
end

function Util.Log(fmt, ...)
    local msg = string.format(fmt, ...)
    print("[ReachTweaks] " .. msg .. "\n")
    if logFile then
        pcall(function()
            logFile:write(os.date("%H:%M:%S ") .. msg .. "\n")
            logFile:flush()
        end)
    end
end

function Util.DLog(fmt, ...)
    if Util.Debug then Util.Log(fmt, ...) end
end

function Util.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Runs fn protected; each distinct error message is logged only once.
local reported = {}
function Util.SafeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        local msg = tostring(res)
        if not reported[msg] then
            reported[msg] = true
            Util.Log("ERROR: %s", msg)
        end
        return nil
    end
    return res
end

-- Plain functions for pcall (no closure is created on every call: these
-- helpers run hundreds of times per frame)
local function isValidRaw(o) return o:IsValid() end
local function addressRaw(o) return o:GetAddress() end
local function ownerRaw(o) return o:GetOwner() end
local function indexRaw(o, k) return o[k] end
local function fullNameRaw(o) return o:GetFullName() end
local function isARaw(o, cls) return o:IsA(cls) end

function Util.IsValid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(isValidRaw, obj)
    return ok and valid
end

-- Stable key to use objects as table indices.
-- Never keep UObjects across ticks: if the engine destroys them, touching the
-- stale wrapper can crash the game. Keep keys and look objects up again.
function Util.Key(obj)
    local ok, addr = pcall(addressRaw, obj)
    if ok and addr then return addr end
    return tostring(obj)
end

-- Object path without the class prefix ("Class /Path.Object" -> "/Path.Object"),
-- usable with StaticFindObject.
function Util.Path(obj)
    local ok, full = pcall(fullNameRaw, obj)
    if not ok or type(full) ~= "string" then return nil end
    return full:match("^%S+%s+(.+)$") or full
end

function Util.SameObject(a, b)
    return Util.IsValid(a) and Util.IsValid(b) and Util.Key(a) == Util.Key(b)
end

-- UClass lookup cache (classes are never garbage collected)
local classCache = {}
function Util.Class(path)
    local c = classCache[path]
    if c ~= nil then return c end
    c = StaticFindObject(path)
    if Util.IsValid(c) then
        classCache[path] = c
        return c
    end
    return nil
end

function Util.IsA(obj, classPath)
    if not Util.IsValid(obj) then return false end
    local cls = Util.Class(classPath)
    if cls == nil then return false end
    local ok, res = pcall(isARaw, obj, cls)
    return ok and res
end

-- Converts a UE4SS TArray into a Lua table of valid objects.
function Util.ArrayToTable(arr)
    local out = {}
    if arr == nil then return out end
    if type(arr) == "table" then
        for _, v in ipairs(arr) do
            if Util.IsValid(v) then out[#out + 1] = v end
        end
        return out
    end
    pcall(function()
        arr:ForEach(function(_, elem)
            local v = elem:get()
            -- TWeakObjectPtr
            if v ~= nil and not Util.IsValid(v) then
                local ok, inner = pcall(function() return v:Get() end)
                if ok then v = inner end
            end
            if Util.IsValid(v) then out[#out + 1] = v end
        end)
    end)
    return out
end

function Util.GetOwner(obj)
    if not Util.IsValid(obj) then return nil end
    local ok, owner = pcall(ownerRaw, obj)
    if ok and Util.IsValid(owner) then return owner end
    return nil
end

-- Components of an actor, found by class name and owner.
-- K2_GetComponentsByClass does not work with this UE4SS build, and FindAllOf
-- only returns the exact class, so callers pass every class they care about.
function Util.FindOwnedBy(actor, classNames)
    local out = {}
    if not Util.IsValid(actor) then return out end
    local key = Util.Key(actor)
    for _, cn in ipairs(classNames) do
        for _, o in ipairs(FindAllOf(cn) or {}) do
            local owner = Util.OwnerOf(o)
            if owner and Util.Key(owner) == key then out[#out + 1] = o end
        end
    end
    return out
end

-- Owner actor of a component (GetOwner, or OwnerActor on nDreams objects)
function Util.OwnerOf(o)
    local owner = Util.GetOwner(o)
    if owner == nil then
        local ok, oa = pcall(indexRaw, o, "OwnerActor")
        if ok and Util.IsValid(oa) then owner = oa end
    end
    return owner
end

-- FindOwnedBy with the result remembered as object paths: FindAllOf walks the
-- whole object list (milliseconds), StaticFindObject on a path is a hash
-- lookup. The paths are checked on every call (the object still exists and
-- still belongs to the actor) and the search is repeated when one is gone; an
-- empty result is searched again after EMPTY_RETRY_MS.
local ownedCache = {}       -- "actorKey|classes" -> { paths = {...}, at = ms }
local ownedCount = 0
local EMPTY_RETRY_MS = 2000

function Util.FindOwnedByCached(actor, classNames)
    if not Util.IsValid(actor) then return {} end
    local key = Util.Key(actor)
    local ck = tostring(key) .. "|" .. table.concat(classNames, ",")
    local now = os.clock() * 1000
    local c = ownedCache[ck]
    if c and (#c.paths > 0 or now - c.at < EMPTY_RETRY_MS) then
        local out = {}
        for _, p in ipairs(c.paths) do
            local o = StaticFindObject(p)
            local owner = Util.IsValid(o) and Util.OwnerOf(o) or nil
            if not owner or Util.Key(owner) ~= key then
                out = nil
                break
            end
            out[#out + 1] = o
        end
        if out then return out end
    end
    local list = Util.FindOwnedBy(actor, classNames)
    local paths = {}
    for _, o in ipairs(list) do
        local p = Util.Path(o)
        if p then paths[#paths + 1] = p end
    end
    if c == nil then
        ownedCount = ownedCount + 1
        -- Actors come and go with levels: start over instead of growing forever
        if ownedCount > 256 then ownedCache, ownedCount = {}, 1 end
    end
    ownedCache[ck] = { paths = paths, at = now }
    return list
end

-- Reads an object property; returns nil if it is not a valid UObject.
-- Note: many nDreams properties are NDComponentPath structs; the actual
-- pointer lives in the matching "...Reference" property.
function Util.Prop(obj, name)
    local ok, v = pcall(indexRaw, obj, name)
    if ok and Util.IsValid(v) then return v end
    return nil
end

-- Delayed calls run from the game-thread main loop (UE4SS ExecuteWithDelay
-- runs its callback on another thread, which is not safe with our Lua).
local timers = {}

function Util.After(ms, fn)
    timers[#timers + 1] = { left = ms, fn = fn }
end

function Util.RunTimers(dtMs)
    if #timers == 0 then return end
    local due = {}
    for i = #timers, 1, -1 do
        local t = timers[i]
        t.left = t.left - dtMs
        if t.left <= 0 then
            table.remove(timers, i)
            due[#due + 1] = t.fn
        end
    end
    for i = #due, 1, -1 do Util.SafeCall(due[i]) end
end

return Util
