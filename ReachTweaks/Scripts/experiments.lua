-- F8: cycles weight-spring stiffness levels to compare how weapons feel.
-- Cause of the "heaviness": UAtlasThrowableResolver::ApplyWeight spring.
-- Values are re-applied every tick (the game may rewrite them) and restored
-- when switching experiments.
local Util = require("util")
local Player = require("player")
local Notify = require("notify")

local Experiments = {}

-- set = fixed value, mul = multiplier of the original value
-- Entry 1: the mod with the config.lua values (no experiment).
-- Entry 2: the original game (the mod does not touch the weight).
local LIST = {
    { name = "Mod: config.lua values", ops = {} },
    { name = "0: ORIGINAL game", ops = {} },
    { name = "1: Stiffness x3", ops = {
        { target = "weight", prop = "LinearStiffness", mul = 3 },
        { target = "weight", prop = "AngularStiffness", mul = 3 },
        { target = "weight", prop = "LinearDamping", set = 1.0 },
        { target = "weight", prop = "AngularDamping", set = 1.0 },
    } },
    { name = "2: Stiffness x10", ops = {
        { target = "weight", prop = "LinearStiffness", mul = 10 },
        { target = "weight", prop = "AngularStiffness", mul = 10 },
        { target = "weight", prop = "LinearDamping", set = 1.0 },
        { target = "weight", prop = "AngularDamping", set = 1.0 },
    } },
    { name = "3: Stiffness x30", ops = {
        { target = "weight", prop = "LinearStiffness", mul = 30 },
        { target = "weight", prop = "AngularStiffness", mul = 30 },
        { target = "weight", prop = "LinearDamping", set = 1.0 },
        { target = "weight", prop = "AngularDamping", set = 1.0 },
    } },
    { name = "4: Stiffness x100", ops = {
        { target = "weight", prop = "LinearStiffness", mul = 100 },
        { target = "weight", prop = "AngularStiffness", mul = 100 },
        { target = "weight", prop = "LinearDamping", set = 1.0 },
        { target = "weight", prop = "AngularDamping", set = 1.0 },
    } },
}

local index = 1
-- Keys and values only: game objects are never kept across ticks
local orig = {}      -- [objKey][prop] = original

local Hands = require("hands")

local function applyOp(op)
    for hand = 0, 1 do
        local a = Player.Held(hand)
        if a then
            for _, obj in ipairs(Hands.WeightResolvers(a)) do
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
    end
end

local function restoreAll()
    if next(orig) == nil then return end
    for _, obj in ipairs(Hands.AllWeightResolvers()) do
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
