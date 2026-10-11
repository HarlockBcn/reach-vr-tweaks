-- Arm-swing sprint: swinging both arms like a runner (while moving with the
-- stick) starts the game's sprint, as clicking the stick does; when the arms
-- stop swinging the player walks again.
--
-- Gesture: each hand's position relative to the head (so walking, turning
-- the body or teleports do not count) is reduced to one "swing" coordinate,
-- height + distance in front of the head (a running arm moves forward-up and
-- back-down). Its velocity is smoothed and compared between the hands over a
-- short window: both hands must swing fast enough (RMS speed) and in
-- opposite directions (negative correlation). Moving both hands together
-- (aiming, climbing, looking around) does not count.
-- Stopping is measured separately with a much shorter window: the swing
-- window needs ~1 s to forget a fast swing, so when either hand's short-window
-- speed drops below MinHandSpeed for StillMs the gesture ends at once. A
-- swinging hand stays well above that even at the turning points.
--
-- Sprint: StartSprint / StopSprint on the movement component, the same
-- functions the sprint input uses (Speed = RunSpeed / WalkSpeed, sprint lines,
-- OnSprintStarted / OnSprintEnded). Only a sprint started here is ended
-- here: a sprint started with the stick is left to the game.
-- Slide (slide.lua): while it holds the sprint state (slide, crouch lock)
-- nothing is started or stopped here. Ending the gesture is delayed by
-- StopMs, so ducking right after swinging still counts as sprinting.
-- Jumps (jumpsprint.lua): while JumpSprint.Holds() our sprint is not ended
-- (the arms usually stop swinging during a jump) and a sprint the game ended
-- on the jump is still ours once restarted.
-- Climbing: moving the hands while climbing (with the stick pushed) looked
-- like a running swing. While a hand holds a climbable surface (the game's
-- climbing movement mode, UAtlasMovementModeClimbingBase::IsEitherHandClimbing,
-- found among the movement component's CustomMovementModes) and for
-- ClimbGraceMs after letting go, no sprint is started, our sprint ends and the
-- gesture is forgotten. Holding an object or a weapon is not climbing.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")
local Slide = require("slide")
local JumpSprint = require("jumpsprint")

local ArmSprint = {}

local cfg

local MAX_STEP_CM = 50           -- a bigger jump in one tick is a tracking glitch

local lastKey = nil
local lastS = { [0] = nil, [1] = nil }   -- last swing coordinate per hand (cm)
local vel = { [0] = 0, [1] = 0 }          -- smoothed swing velocity (cm/s)
local eLL, eRR, eLR = 0, 0, 0             -- windowed velocity products
local fLL, fRR = 0, 0                     -- short-window squared velocities (stop detection)
local gesture = false
local onMs, offMs, stillMs = 0, 0, 0
local ours = false               -- the current sprint was started here
local retryMs = 0                -- wait before starting again after the game ended our sprint
local logAcc = 0
local warned = {}
local climbing = false
local climbGraceMs = 0           -- time left after letting go of a climbable surface
local modesLogged = false

local function movement(pawn)
    return Util.Prop(pawn, "AtlasMovementComponentReference") or Util.Prop(pawn, "AtlasMovementComponent")
end

local function readBool(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    return ok and v == true
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

local function location(comp)
    if not comp then return nil end
    local ok, loc = pcall(function() return comp:K2_GetComponentLocation() end)
    if ok and loc then return { X = loc.X, Y = loc.Y, Z = loc.Z } end
    return nil
end

local function headComponent(pawn, mc)
    return Util.Prop(mc, "Headset") or Util.Prop(pawn, "HeadReference") or Util.Prop(pawn, "HeadComponent")
end

local function handComponent(mc, hand)
    local c = Util.Prop(mc, hand == Haptics.LEFT and "LeftMotionController" or "RightMotionController")
    if c then return c end
    warnOnce("hand", "[armsprint] movement component has no motion controllers; searching them by class")
    return Player.MotionController(hand)
end

-- Horizontal forward of the head (unit vector).
local function headForward(head)
    local ok, f = pcall(function() return head:GetForwardVector() end)
    if not ok or not f then return 1, 0 end
    local len = math.sqrt(f.X * f.X + f.Y * f.Y)
    if len < 0.1 then return 1, 0 end
    return f.X / len, f.Y / len
end

-- Stick deflection (0..1); nil when the game does not report it.
local function stickInput(mc)
    local f, r = call(mc, "GetForwardInput"), call(mc, "GetRightInput")
    if type(f) ~= "number" or type(r) ~= "number" then return nil end
    return math.sqrt(f * f + r * r)
end

-- True while either hand holds a climbable surface; nil when the climbing
-- movement mode cannot be read. The modes are looked up every tick (UObjects
-- are never kept across ticks).
local function handsClimbing(mc)
    local result = nil
    local names = Util.Debug and not modesLogged and {} or nil
    local ok, err = pcall(function()
        mc.CustomMovementModes:ForEach(function(_, value)
            local mode = value:get()
            if names then
                local okN, n = pcall(function() return mode:GetClass():GetFName():ToString() end)
                names[#names + 1] = okN and n or "?"
            end
            local okC, v = pcall(function() return mode:IsEitherHandClimbing() end)
            if okC and type(v) == "boolean" then
                result = result or v
            end
        end)
    end)
    if names then
        modesLogged = true
        Util.DLog("[armsprint] movement modes: %s", ok and table.concat(names, ", ") or tostring(err))
    end
    return result
end

local function reset()
    lastS[0], lastS[1] = nil, nil
    vel[0], vel[1] = 0, 0
    eLL, eRR, eLR = 0, 0, 0
    fLL, fRR = 0, 0
    gesture, onMs, offMs, stillMs = false, 0, 0, 0
end

-- Updates the gesture statistics; returns whether the hands swing like a
-- runner, whether a hand has stopped, and the values for the log.
local function measure(pawn, mc, dt)
    local head = headComponent(pawn, mc)
    local hp = location(head)
    if not hp then
        warnOnce("head", "[armsprint] head component not found")
        return false, true
    end
    local fx, fy = headForward(head)
    local smooth = Util.Clamp(dt / (cfg.SmoothMs / 1000), 0, 1)
    for hand = 0, 1 do
        local p = location(handComponent(mc, hand))
        if not p then
            lastS[hand], vel[hand] = nil, 0
        else
            local dx, dy, dz = p.X - hp.X, p.Y - hp.Y, p.Z - hp.Z
            local s = dz + dx * fx + dy * fy
            local v = 0
            if lastS[hand] and dt > 0 and math.abs(s - lastS[hand]) < MAX_STEP_CM then
                v = (s - lastS[hand]) / dt
            end
            lastS[hand] = s
            vel[hand] = vel[hand] + (v - vel[hand]) * smooth
        end
    end
    local a = Util.Clamp(dt / (cfg.WindowMs / 1000), 0, 1)
    local vl, vr = vel[Haptics.LEFT], vel[Haptics.RIGHT]
    eLL = eLL + (vl * vl - eLL) * a
    eRR = eRR + (vr * vr - eRR) * a
    eLR = eLR + (vl * vr - eLR) * a
    local f = Util.Clamp(dt / (cfg.StillWindowMs / 1000), 0, 1)
    fLL = fLL + (vl * vl - fLL) * f
    fRR = fRR + (vr * vr - fRR) * f
    local rmsL, rmsR = math.sqrt(eLL), math.sqrt(eRR)
    local corr = (eLL > 1 and eRR > 1) and eLR / math.sqrt(eLL * eRR) or 0
    local min2 = cfg.MinHandSpeed * cfg.MinHandSpeed
    local still = fLL < min2 or fRR < min2
    return rmsL >= cfg.MinHandSpeed and rmsR >= cfg.MinHandSpeed and corr <= cfg.MaxCorrelation, still, rmsL, rmsR, corr
end

local function start(mc)
    call(mc, "StartSprint")
    ours = readBool(mc, "bIsSprinting")
    if ours and cfg.HapticAmplitude > 0 then
        Haptics.Pulse(Haptics.LEFT, cfg.HapticAmplitude, 60, 0, 0.5)
        Haptics.Pulse(Haptics.RIGHT, cfg.HapticAmplitude, 60, 0, 0.5)
    end
    Util.DLog("[armsprint] sprint start%s", ours and "" or " FAILED")
end

local function stop(mc, reason)
    if ours and readBool(mc, "bIsSprinting") then call(mc, "StopSprint") end
    ours = false
    Util.DLog("[armsprint] sprint end (%s)", reason)
end

function ArmSprint.Tick(dtMs)
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if not mc then
        ours, lastKey = false, nil
        climbing, climbGraceMs, modesLogged = false, 0, false
        reset()
        return
    end
    local key = Util.Key(pawn)
    if key ~= lastKey then
        -- New pawn (level change, respawn)
        lastKey, ours = key, false
        climbing, climbGraceMs, modesLogged = false, 0, false
        reset()
    end

    local dt = dtMs / 1000
    if cfg.BlockWhileClimbing then
        local c = handsClimbing(mc)
        if c == nil then warnOnce("climb", "[armsprint] climbing state not readable; sprint not blocked while climbing") end
        c = c == true
        if c ~= climbing then
            climbing = c
            Util.DLog("[armsprint] %s", c and "climbing: no sprint" or "let go of the climbable surface")
        end
        if c then climbGraceMs = cfg.ClimbGraceMs elseif climbGraceMs > 0 then climbGraceMs = climbGraceMs - dtMs end
        if c or climbGraceMs > 0 then
            -- Forget the hand movement of the climb; keep tracking positions
            reset()
            measure(pawn, mc, dt)
            if Slide.HoldsSprint() then
                ours = false
            elseif ours and not JumpSprint.Holds() then
                stop(mc, "climbing")
            end
            return
        end
    end
    local swinging, still, rmsL, rmsR, corr = measure(pawn, mc, dt)
    -- A stopped hand also blocks the start: the swing window still remembers
    -- the swing for a while and would turn the gesture on again every tick
    swinging = swinging and not still
    if swinging then onMs, offMs = onMs + dtMs, 0 else onMs, offMs = 0, offMs + dtMs end
    if still then stillMs = stillMs + dtMs else stillMs = 0 end
    if not gesture and onMs >= cfg.StartMs then
        gesture = true
        Util.DLog("[armsprint] gesture on (L=%.0f R=%.0f cm/s, corr=%.2f)", rmsL or 0, rmsR or 0, corr or 0)
    elseif gesture and (stillMs >= cfg.StillMs or offMs >= cfg.StopMs) then
        gesture = false
        Util.DLog("[armsprint] gesture off (%s)", stillMs >= cfg.StillMs and "hands stopped" or "swing lost")
    end
    if retryMs > 0 then retryMs = retryMs - dtMs end

    local stick = stickInput(mc)
    if stick == nil then warnOnce("stick", "[armsprint] stick input not readable; the stick is not required") end
    local moving = stick == nil or stick >= cfg.MinStick
    local sprinting = readBool(mc, "bIsSprinting")

    if Util.Debug then
        logAcc = logAcc + dtMs
        if logAcc >= 1000 and (gesture or ours or (rmsL or 0) > cfg.MinHandSpeed * 0.5) then
            logAcc = 0
            Util.DLog("[armsprint] L=%.0f R=%.0f cm/s corr=%.2f gesture=%s stick=%s sprint=%s ours=%s slide=%s",
                rmsL or 0, rmsR or 0, corr or 0, tostring(gesture), stick and string.format("%.2f", stick) or "?",
                tostring(sprinting), tostring(ours), tostring(Slide.HoldsSprint()))
        end
    end

    if Slide.HoldsSprint() then
        -- The slide owns the sprint state now; it ends it itself
        if ours then Util.DLog("[armsprint] sprint handed to the slide") end
        ours = false
        return
    end
    if JumpSprint.Holds() then
        -- Jumping: keep our sprint (JumpSprint restarts it if the game ended it)
        return
    end
    if ours and not sprinting then
        -- Ended by the game (stick released, sprint input, ...)
        ours = false
        retryMs = cfg.RetryMs
        Util.DLog("[armsprint] sprint ended by the game")
    end
    if gesture and moving then
        if not sprinting and retryMs <= 0 then start(mc) end
    elseif ours then
        stop(mc, gesture and "stick released" or "arms stopped")
    end
end

-- Tweaks turned off (F7): end our sprint and start clean.
function ArmSprint.Stop()
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if mc and ours and not Slide.HoldsSprint() then stop(mc, "disabled") end
    ours = false
    reset()
end

function ArmSprint.Init(config)
    cfg = config
    cfg.MinHandSpeed = cfg.MinHandSpeed or 80
    cfg.MaxCorrelation = cfg.MaxCorrelation or -0.3
    cfg.StartMs = cfg.StartMs or 200
    cfg.StopMs = cfg.StopMs or 500
    cfg.StillMs = cfg.StillMs or 100
    cfg.StillWindowMs = cfg.StillWindowMs or 150
    cfg.MinStick = cfg.MinStick or 0.3
    cfg.WindowMs = cfg.WindowMs or 400
    cfg.SmoothMs = cfg.SmoothMs or 40
    cfg.RetryMs = cfg.RetryMs or 500
    cfg.HapticAmplitude = cfg.HapticAmplitude or 0.15
    if cfg.BlockWhileClimbing == nil then cfg.BlockWhileClimbing = true end
    cfg.ClimbGraceMs = cfg.ClimbGraceMs or 500
    Util.Log("Arm-swing sprint enabled (min hand speed=%.0f cm/s, correlation <= %.2f, start %d ms, stop %d ms)",
        cfg.MinHandSpeed, cfg.MaxCorrelation, cfg.StartMs, cfg.StopMs)
end

return ArmSprint
