-- Agile hands.
-- Source of the weapon "heaviness" (reverse engineered from the exe):
-- UAtlasThrowableResolver::ApplyWeight moves the held object towards the hand
-- with VectorSpringInterp / QuaternionSpringInterp (mass 1.0) using
--   LinearStiffness / LinearDamping   -> position
--   AngularStiffness / AngularDamping -> rotation
-- Low stiffness = lag and capped speed; damping < 1 = wobble.
-- AtlasGunResolver (guns) derives from that class; the bow uses BowResolver.
-- While a weapon is held its stiffness is raised and damping set to critical;
-- original values are restored when it is released or with F7.
local Util = require("util")
local Player = require("player")

local Hands = {}

local WEAPON_CLASSES = {
    "/Script/AtlasGameplay.AtlasGun",
    "/Script/NDWeapon.NDWEBaseGun",
    "/Script/AtlasGameplay.AtlasBow",
}
-- FindAllOf only returns the exact class
local RESOLVER_CLASSES = { "AtlasGunResolver", "AtlasThrowableResolver" }
Hands.RESOLVER_CLASSES = RESOLVER_CLASSES

local cfg
local props            -- [prop] = { mul = x } or { set = x }
local orig = {}        -- [key][prop] = original
local applied = {}     -- [key][prop] = value we wrote
local patched = {}     -- [key] = true (keys only: objects are never kept across ticks)

local function isWeapon(actor)
    for _, cp in ipairs(WEAPON_CLASSES) do
        if Util.IsA(actor, cp) then return true end
    end
    return false
end

local function getNum(obj, prop)
    local ok, v = pcall(function() return obj[prop] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function apply(obj, label)
    local key = Util.Key(obj)
    orig[key] = orig[key] or {}
    applied[key] = applied[key] or {}
    for prop, op in pairs(props) do
        local cur = getNum(obj, prop)
        if cur ~= nil then
            local mine = applied[key][prop]
            -- first time, or the game rewrote the value: that becomes the new original
            if mine == nil or math.abs(cur - mine) > 1e-4 then
                orig[key][prop] = cur
                local new = op.set or (cur * op.mul)
                if pcall(function() obj[prop] = new end) then
                    applied[key][prop] = new
                    patched[key] = true
                    Util.DLog("%s %s: %.3f -> %.3f", label, prop, cur, new)
                end
            end
        end
    end
end

local function restore(obj)
    local key = Util.Key(obj)
    if orig[key] then
        for prop, v in pairs(orig[key]) do
            local cur = getNum(obj, prop)
            if cur ~= nil and applied[key][prop] and math.abs(cur - applied[key][prop]) < 1e-4 then
                pcall(function() obj[prop] = v end)
            end
        end
    end
    orig[key], applied[key], patched[key] = nil, nil, nil
end

-- Weight-spring resolvers of a held object
function Hands.WeightResolvers(actor)
    local list = Util.FindOwnedBy(actor, RESOLVER_CLASSES)
    local bowRes = Util.Prop(actor, "BowResolverRef")
    if bowRes and getNum(bowRes, "LinearStiffness") ~= nil then list[#list + 1] = bowRes end
    return list
end

-- Every weight resolver in the level (to restore those no longer held)
function Hands.AllWeightResolvers()
    local list = {}
    for _, cn in ipairs(RESOLVER_CLASSES) do
        for _, r in ipairs(FindAllOf(cn) or {}) do
            if Util.IsValid(r) then list[#list + 1] = r end
        end
    end
    for _, bow in ipairs(FindAllOf("BP_AtlasBow_C") or {}) do
        local r = Util.IsValid(bow) and Util.Prop(bow, "BowResolverRef")
        if r then list[#list + 1] = r end
    end
    return list
end

-- Every ~100 ms on the game thread
function Hands.Tick()
    local heldKeys = {}
    for hand = 0, 1 do
        local a = Player.Held(hand)
        if a and (cfg.Scope == "all" or isWeapon(a)) then
            for _, r in ipairs(Hands.WeightResolvers(a)) do
                heldKeys[Util.Key(r)] = true
                apply(r, "Weight")
            end
        end
    end
    -- Objects no longer held get their original values back (e.g. when thrown)
    local pending = false
    for key in pairs(patched) do
        if not heldKeys[key] then pending = true break end
    end
    if pending then
        for _, r in ipairs(Hands.AllWeightResolvers()) do
            local key = Util.Key(r)
            if patched[key] and not heldKeys[key] then restore(r) end
        end
        -- forget the ones that no longer exist (destroyed with the level)
        for key in pairs(patched) do
            if not heldKeys[key] then orig[key], applied[key], patched[key] = nil, nil, nil end
        end
    end
end

function Hands.RestoreAll()
    for _, r in ipairs(Hands.AllWeightResolvers()) do
        if patched[Util.Key(r)] then restore(r) end
    end
    orig, applied, patched = {}, {}, {}
end

function Hands.Init(config)
    cfg = config
    local k = cfg.WeightStiffnessMultiplier or 10
    local d = cfg.WeightDamping or 1.0
    props = {
        LinearStiffness = { mul = k },
        AngularStiffness = { mul = k },
        LinearDamping = { set = d },
        AngularDamping = { set = d },
    }
end

return Hands
