-- Sprint speed: scales the game's sprint speed (RunSpeed on the movement
-- component; StartSprint copies it into Speed).
--
-- The game can set RunSpeed itself (Blueprint SetRunSpeed, new pawn): a value
-- different from the one written here is taken as the new original and
-- scaled again. A sprint already running gets the new speed at once.
local Util = require("util")
local Player = require("player")
local Slide = require("slide")

local Sprint = {}

local cfg

local lastKey = nil
local original = nil     -- game's RunSpeed (cm/s)
local applied = nil      -- RunSpeed written here

local function movement(pawn)
    return Util.Prop(pawn, "AtlasMovementComponentReference") or Util.Prop(pawn, "AtlasMovementComponent")
end

local function readNum(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function readBool(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    return ok and v == true
end

local function write(obj, name, value)
    pcall(function() obj[name] = value end)
end

-- Writes RunSpeed; a running sprint (Speed at the old run speed) follows.
local function setRunSpeed(mc, old, new)
    write(mc, "RunSpeed", new)
    if readBool(mc, "bIsSprinting") and not Slide.HoldsSprint() then
        local speed = readNum(mc, "Speed")
        if speed and math.abs(speed - old) < 0.5 then write(mc, "Speed", new) end
    end
end

function Sprint.Tick()
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if not mc then
        lastKey, original, applied = nil, nil, nil
        return
    end
    local key = Util.Key(pawn)
    if key ~= lastKey then
        lastKey, original, applied = key, nil, nil
    end
    local run = readNum(mc, "RunSpeed")
    if not run then return end
    if applied == nil or math.abs(run - applied) > 0.5 then
        original = run
        Util.DLog("[sprint] game run speed %.0f cm/s -> %.0f cm/s (x%.2f), walk %.0f cm/s",
            original, original * cfg.SpeedMultiplier, cfg.SpeedMultiplier, readNum(mc, "WalkSpeed") or 0)
    end
    local target = original * cfg.SpeedMultiplier
    if math.abs(run - target) > 0.5 then setRunSpeed(mc, run, target) end
    applied = target
end

-- Tweaks turned off (F7): give the game its own sprint speed back.
function Sprint.Stop()
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    local run = mc and readNum(mc, "RunSpeed")
    if run and original and applied and math.abs(run - applied) <= 0.5 then
        setRunSpeed(mc, run, original)
        Util.DLog("[sprint] run speed restored to %.0f cm/s", original)
    end
    lastKey, original, applied = nil, nil, nil
end

function Sprint.Init(config)
    cfg = config
    cfg.SpeedMultiplier = cfg.SpeedMultiplier or 1.0
    Util.Log("Sprint speed enabled (x%.2f)", cfg.SpeedMultiplier)
end

return Sprint
