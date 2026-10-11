-- Sprint through jumps: the game's movement Blueprint ends the sprint when the
-- player jumps or lands (the native code never calls StopSprint itself), so
-- after every jump the player walks and has to start sprinting again.
--
-- When a sprint ends around a jump (in the air, within JumpWindowMs of the
-- jump, or within LandGraceMs of landing) it is carried over:
--   * in the air it is started again at once (KeepInAir), so the jump keeps
--     the running speed and the speed lines; if the game ends it again during
--     the same jump, it waits for the landing instead of fighting every tick;
--   * on landing it is started again if the stick is still pushed; if the
--     player lets go of the stick for ResumeWindowMs the carry is dropped.
-- The game ending the sprint again right after a restart is retried at most
-- MaxRestarts times per jump.
--
-- Arm-swing sprint (armsprint.lua) does not end its sprint while Holds() is
-- true (the arms usually stop swinging during a jump).
-- Slide (slide.lua): nothing is done while it holds the sprint state.
local Util = require("util")
local Player = require("player")
local Slide = require("slide")

local JumpSprint = {}

local cfg

local lastKey = nil
local wasSprinting = false
local wasAirborne = false
local landedMs = math.huge       -- time since the last landing
local carry = false              -- a sprint ended by a jump waits to be restarted
local carryGroundMs = 0          -- time on the ground without stick while carrying
local airRestarted = false       -- already restarted once during this jump
local restarts = 0               -- restarts since the jump started
local warned = {}

local function movement(pawn)
    return Util.Prop(pawn, "AtlasMovementComponentReference") or Util.Prop(pawn, "AtlasMovementComponent")
end

local function readBool(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "boolean" then return v end
    return nil
end

local function call(obj, fn, ...)
    local args = { ... }
    local ok, v = pcall(function() return obj[fn](obj, table.unpack(args)) end)
    if ok then return v end
    return nil
end

local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    Util.Log(fmt, ...)
end

-- Stick deflection (0..1); nil when the game does not report it.
local function stickInput(mc)
    local f, r = call(mc, "GetForwardInput"), call(mc, "GetRightInput")
    if type(f) ~= "number" or type(r) ~= "number" then return nil end
    return math.sqrt(f * f + r * r)
end

local function reset()
    wasSprinting, wasAirborne = false, false
    landedMs = math.huge
    carry, carryGroundMs, airRestarted, restarts = false, 0, false, 0
end

local function restart(mc, why)
    call(mc, "StartSprint")
    local ok = readBool(mc, "bIsSprinting") == true
    restarts = restarts + 1
    Util.DLog("[jumpsprint] sprint restarted (%s)%s", why, ok and "" or " FAILED")
    return ok
end

function JumpSprint.Tick(dtMs)
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if not mc then
        lastKey = nil
        reset()
        return
    end
    local key = Util.Key(pawn)
    if key ~= lastKey then
        lastKey = key
        reset()
    end

    local sprinting = readBool(mc, "bIsSprinting") == true
    local onGround = readBool(mc, "bOnGround")
    if onGround == nil then
        warnOnce("ground", "[jumpsprint] bOnGround not readable; sprint through jumps disabled")
        return
    end
    local airborne = not onGround
    local sinceJump = call(mc, "GetTimeSinceJump")
    local jumpedMs = type(sinceJump) == "number" and sinceJump * 1000 or math.huge

    if airborne and not wasAirborne then
        airRestarted, restarts = false, 0
        if sprinting then Util.DLog("[jumpsprint] took off sprinting") end
    elseif wasAirborne and not airborne then
        landedMs = 0
        Util.DLog("[jumpsprint] landed (sprint=%s carry=%s)", tostring(sprinting), tostring(carry))
    elseif not airborne then
        landedMs = landedMs + dtMs
    end
    wasAirborne = airborne

    if Slide.HoldsSprint() then
        carry = false
        wasSprinting = sprinting
        return
    end

    local nearJump = airborne or jumpedMs < cfg.JumpWindowMs or landedMs < cfg.LandGraceMs
    if wasSprinting and not sprinting and nearJump then
        if restarts >= cfg.MaxRestarts then
            Util.DLog("[jumpsprint] game ended the sprint again; giving up for this jump")
            carry = false
        else
            carry, carryGroundMs = true, 0
            Util.DLog("[jumpsprint] game ended the sprint (%s, %.0f ms after the jump)",
                airborne and "in the air" or (landedMs < cfg.LandGraceMs and "landing" or "jump"), jumpedMs)
        end
    end

    if carry then
        if sprinting then
            carry = false
        elseif airborne then
            if cfg.KeepInAir and not airRestarted then
                airRestarted = true
                sprinting = restart(mc, "in the air")
                if sprinting then carry = false end
            end
        else
            local stick = stickInput(mc)
            if stick == nil then warnOnce("stick", "[jumpsprint] stick input not readable; the stick is not required") end
            if stick == nil or stick >= cfg.MinStick then
                sprinting = restart(mc, "landed")
                carry = false
            else
                carryGroundMs = carryGroundMs + dtMs
                if carryGroundMs >= cfg.ResumeWindowMs then
                    carry = false
                    Util.DLog("[jumpsprint] stick released after landing; sprint not restarted")
                end
            end
        end
    end
    wasSprinting = sprinting
end

-- True while a jump is in progress (in the air, just landed, or a sprint
-- waiting to be restarted): the arm-swing sprint must not end its sprint.
function JumpSprint.Holds()
    return cfg ~= nil and (wasAirborne or carry or landedMs < cfg.LandGraceMs)
end

function JumpSprint.Stop()
    reset()
end

function JumpSprint.Init(config)
    cfg = config
    cfg.KeepInAir = cfg.KeepInAir ~= false
    cfg.MinStick = cfg.MinStick or 0.3
    cfg.JumpWindowMs = cfg.JumpWindowMs or 300
    cfg.LandGraceMs = cfg.LandGraceMs or 400
    cfg.ResumeWindowMs = cfg.ResumeWindowMs or 300
    cfg.MaxRestarts = cfg.MaxRestarts or 3
    Util.Log("Sprint through jumps enabled (keep in air=%s, land grace %d ms)", tostring(cfg.KeepInAir), cfg.LandGraceMs)
end

return JumpSprint
