-- F8: cycles experiments to compare how weapons feel.
-- Current set: bow string coupler weights. When both bow couplers (grip and
-- string) are held, UNDNTResolverBasic::CombineMotionsWithMagnets averages
-- their motions, so the string hand drags the bow away from the bow hand.
-- Guns avoid this: their support-hand coupler has OutgoingMotionWeight = 0
-- and ResolverSiblingWeighting = 0. These experiments try the same on the bow.
-- Values are re-applied every tick (the game may rewrite them) and restored
-- when switching experiments.
local Util = require("util")
local Player = require("player")
local Notify = require("notify")

local Experiments = {}

-- target: "weight"    = weight-spring resolvers of held objects (guns)
--         "bowstring" = BowStringCouplerRef of the held bow
-- set = fixed value, mul = multiplier of the original value
-- Entry 1: the mod with the config.lua values (no experiment).
-- Entry 2: the original game (the mod's hand tweaks are put aside).
local LIST = {
    { name = "Mod: config.lua values", ops = {} },
    { name = "0: ORIGINAL game", ops = {} },
    { name = "1: String motion weight 0.5", ops = {
        { target = "bowstring", prop = "OutgoingMotionWeight", set = 0.5 },
    } },
    { name = "2: String motion weight 0", ops = {
        { target = "bowstring", prop = "OutgoingMotionWeight", set = 0.0 },
    } },
    { name = "3: String sibling weight 0", ops = {
        { target = "bowstring", prop = "ResolverSiblingWeighting", set = 0.0 },
    } },
    { name = "4: String weights 0 (like gun grip)", ops = {
        { target = "bowstring", prop = "OutgoingMotionWeight", set = 0.0 },
        { target = "bowstring", prop = "ResolverSiblingWeighting", set = 0.0 },
    } },
}

local index = 1
-- Keys and values only: game objects are never kept across ticks
local orig = {}      -- [objKey][prop] = original

local Hands = require("hands")

-- Objects of a target kind for the currently held actors
local function targets(kind)
    local out = {}
    for hand = 0, 1 do
        local a = Player.Held(hand)
        if a then
            if kind == "weight" then
                for _, r in ipairs(Hands.WeightResolvers(a)) do out[#out + 1] = r end
            elseif kind == "bowstring" then
                local c = Util.Prop(a, "BowStringCouplerRef")
                if c then out[#out + 1] = c end
            end
        end
    end
    return out
end

-- Every object of every kind in the level (to restore originals)
local function allTargets()
    local out = Hands.AllWeightResolvers()
    for _, bow in ipairs(FindAllOf("BP_AtlasBow_C") or {}) do
        local c = Util.IsValid(bow) and Util.Prop(bow, "BowStringCouplerRef")
        if c then out[#out + 1] = c end
    end
    return out
end

local function applyOp(op)
    for _, obj in ipairs(targets(op.target)) do
        local key = Util.Key(obj)
        local ok, cur = pcall(function() return obj[op.prop] end)
        if ok and type(cur) == "number" then
            orig[key] = orig[key] or {}
            if orig[key][op.prop] == nil then orig[key][op.prop] = cur end
            local want = op.set or (orig[key][op.prop] * op.mul)
            if math.abs(cur - want) > 1e-4 then
                pcall(function() obj[op.prop] = want end)
            end
        end
    end
end

local function restoreAll()
    if next(orig) == nil then return end
    for _, obj in ipairs(allTargets()) do
        local props = orig[Util.Key(obj)]
        if props then
            for prop, v in pairs(props) do pcall(function() obj[prop] = v end) end
        end
    end
    orig = {}
end

Experiments.RestoreAll = function() restoreAll() end

-- An experiment other than "Mod" is active
function Experiments.Active()
    return index > 1
end

-- Call every ~100 ms on the game thread
function Experiments.Tick()
    for _, op in ipairs(LIST[index].ops) do applyOp(op) end
end

function Experiments.Next()
    restoreAll()
    if Experiments.BeforeChange then Util.SafeCall(Experiments.BeforeChange) end
    index = index % #LIST + 1
    local e = LIST[index]
    Experiments.Tick()
    local parts = {}
    for _, props in pairs(orig) do
        for prop, v in pairs(props) do parts[#parts + 1] = prop .. " orig=" .. tostring(v) end
    end
    Util.Log("[exp] Active experiment: %s | %s", e.name, table.concat(parts, ", "))
    Notify.Show(e.name, { R = 120, G = 200, B = 255 }, 3.5)
end

function Experiments.Init()
    Util.SafeCall(function()
        RegisterKeyBind(Key.F8, function()
            ExecuteInGameThread(function() Util.SafeCall(Experiments.Next) end)
        end)
    end)
    Util.Log("Experiments: F8 = next")
end

return Experiments
