-- Sprint speed: scales the game's sprint speed (RunSpeed on the movement
-- component; StartSprint copies it into Speed).
--
-- The game can set RunSpeed itself (Blueprint SetRunSpeed, new pawn): a value
-- the mod did not write is taken as the new original and scaled. A value the
-- mod wrote earlier (Util.GameValue, kept per component path for the whole
-- session) always maps back to its original, so it is never scaled twice:
-- the pause menu possesses another pawn (BP_PausePlayer_C) and, on return,
-- the player's RunSpeed is still the scaled one. A sprint already running
-- gets the new speed at once.
local Util = require("util")
local Player = require("player")
local Slide = require("slide")

local Sprint = {}

local cfg

local lastKey = nil
local valueId = nil      -- Util.ValueId of the current pawn's RunSpeed
local original = nil     -- game's RunSpeed (cm/s)
local applied = nil      -- RunSpeed written here

-- Movement component of the current pawn (cached for the tick by Player)
local function movement()
    return Player.Movement()
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
        lastKey, valueId, original, applied = nil, nil, nil, nil
        return
    end
    local key = Player.PawnKey()
    if key ~= lastKey then
        lastKey, original, applied = key, nil, nil
        valueId = Util.ValueId(Util.Path(mc) or key, "RunSpeed")
    end
    local run = readNum(mc, "RunSpeed")
    if not run then return end
    if applied == nil or math.abs(run - applied) > 0.5 then
        original = Util.GameValue(valueId, run)
        Util.DLog("[sprint] game run speed %.0f cm/s%s -> %.0f cm/s (x%.2f), walk %.0f cm/s",
            original, original ~= run and string.format(" (found at %.0f, set by the mod)", run) or "",
            original * cfg.SpeedMultiplier, cfg.SpeedMultiplier, readNum(mc, "WalkSpeed") or 0)
    end
    local target = original * cfg.SpeedMultiplier
    if math.abs(run - target) > 0.5 then setRunSpeed(mc, run, target) end
    if applied ~= target then Util.NoteWritten(valueId, target, original) end
    applied = target
end

-- Tweaks turned off (F7): give the game its own sprint speed back.
function Sprint.Stop()
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    local run = mc and readNum(mc, "RunSpeed")
    if run and valueId then
        local base = Util.GameValue(valueId, run)
        if math.abs(run - base) > 0.5 then
            setRunSpeed(mc, run, base)
            Util.DLog("[sprint] run speed restored to %.0f cm/s", base)
        end
    end
    lastKey, valueId, original, applied = nil, nil, nil, nil
end

function Sprint.Init(config)
    cfg = config
    cfg.SpeedMultiplier = cfg.SpeedMultiplier or 1.0
    Util.Log("Sprint speed enabled (x%.2f)", cfg.SpeedMultiplier)
end

return Sprint
