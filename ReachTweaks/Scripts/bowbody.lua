-- Bow body follow: while the string is held, the bow resolver averages the
-- grip and string coupler motions (UNDNTResolverBasic::CombineMotionsWithMagnets,
-- equal weights), so the bow body only covers part of the way to the bow hand
-- every frame and feels slow and heavy.
--
-- This module learns where the grip coupler sits in the space of the real
-- motion controller while only the grip is held, and while the string is held
-- moves the bow actor (translation only) towards that point. The string, its
-- couplers and the bow rotation (aim) are left to the game.
local Util = require("util")
local Player = require("player")

local BowBody = {}

local BOW_CLASS = "/Script/AtlasGameplay.AtlasBow"

local cfg
local bowKey = nil
local restOffset = nil      -- grip position in controller space (cm)
local heldMs = 0
local blend = 0             -- 0..1, fades the correction in/out
local prevCtrl = nil

-- Debug statistics (one summary per second)
local stats = nil
local statAcc = 0

-- Axes of a UE rotator (FRotationMatrix)
local function axes(r)
    local p, y, ro = math.rad(r.Pitch), math.rad(r.Yaw), math.rad(r.Roll)
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(ro), math.cos(ro)
    local x = { cp * cy, cp * sy, sp }
    local yv = { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp }
    local z = { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp }
    return x, yv, z
end

local function dot(v, a) return v[1] * a[1] + v[2] * a[2] + v[3] * a[3] end

local function toLocal(v, x, y, z) return { dot(v, x), dot(v, y), dot(v, z) } end

local function toWorld(l, x, y, z)
    return { l[1] * x[1] + l[2] * y[1] + l[3] * z[1],
             l[1] * x[2] + l[2] * y[2] + l[3] * z[2],
             l[1] * x[3] + l[2] * y[3] + l[3] * z[3] }
end

local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end

local function vec(u) return { u.X, u.Y, u.Z } end

local function compLoc(c)
    local ok, v = pcall(function() return c:K2_GetComponentLocation() end)
    if ok and v then return vec(v) end
    return nil
end

local function compRot(c)
    local ok, v = pcall(function() return c:K2_GetComponentRotation() end)
    if ok and v then return { Pitch = v.Pitch, Yaw = v.Yaw, Roll = v.Roll } end
    return nil
end

local function stringHeld(bow)
    local c = Util.Prop(bow, "BowStringCouplerRef")
    if not c then return false end
    local ok, arr = pcall(function() return c:GetPartners() end)
    if ok and #Util.ArrayToTable(arr) > 0 then return true end
    return false
end

local function newStats()
    return { [false] = { n = 0, sum = 0, max = 0 }, [true] = { n = 0, sum = 0, max = 0, post = 0 }, vmax = 0 }
end

local function record(drawing, err, post, speed)
    stats = stats or newStats()
    local s = stats[drawing]
    s.n = s.n + 1
    s.sum = s.sum + err
    if err > s.max then s.max = err end
    if drawing then s.post = s.post + post end
    if speed > stats.vmax then stats.vmax = speed end
end

local function flushStats(dtMs, applying)
    statAcc = statAcc + dtMs
    if statAcc < 1000 then return end
    statAcc = 0
    local st = stats
    stats = nil
    -- only with noticeable movement (> 80 cm/s)
    if not st or st.vmax < 80 then return end
    local f, d = st[false], st[true]
    local parts = {}
    if f.n > 0 then parts[#parts + 1] = string.format("grip-only err avg %.1f max %.1f", f.sum / f.n, f.max) end
    if d.n > 0 then
        parts[#parts + 1] = string.format("DRAWING err avg %.1f max %.1f -> shown avg %.1f",
            d.sum / d.n, d.max, d.post / d.n)
    end
    Util.Log("[bowbody] vmax=%4.0f cm/s %s (follow=%.2f %s)", st.vmax, table.concat(parts, " | "),
        cfg.BodyFollow, applying and "ON" or "OFF")
end

local function reset()
    bowKey, restOffset, heldMs, blend, prevCtrl = nil, nil, 0, 0, nil
end

-- applying = false measures only (tweaks disabled with F7)
function BowBody.Tick(dtMs, applying)
    local hand, bow = Player.HandHoldingClass({ BOW_CLASS })
    if not bow then
        if bowKey then reset() end
        return
    end
    local key = Util.Key(bow)
    if key ~= bowKey then
        reset()
        bowKey = key
    end
    heldMs = heldMs + dtMs

    local mc = Player.MotionController(hand)
    local grip = Util.Prop(bow, "BowCouplerRef")
    if not mc or not grip then return end
    local cLoc, cRot, gLoc = compLoc(mc), compRot(mc), compLoc(grip)
    if not cLoc or not cRot or not gLoc then return end

    local speed = 0
    if prevCtrl then
        speed = len({ cLoc[1] - prevCtrl[1], cLoc[2] - prevCtrl[2], cLoc[3] - prevCtrl[3] }) / (dtMs / 1000)
    end
    prevCtrl = cLoc

    local x, y, z = axes(cRot)
    local rel = { gLoc[1] - cLoc[1], gLoc[2] - cLoc[2], gLoc[3] - cLoc[3] }
    local drawing = stringHeld(bow)

    if not drawing then
        -- Learn the grip offset while the bow is held still with one hand
        if heldMs > 500 and speed < cfg.LearnMaxSpeed then
            local l = toLocal(rel, x, y, z)
            if restOffset == nil then
                restOffset = l
            else
                for i = 1, 3 do restOffset[i] = restOffset[i] + (l[i] - restOffset[i]) * 0.1 end
            end
        end
    end

    -- Fade the correction in while drawing and out after releasing
    local target = (drawing and applying) and 1 or 0
    local step = dtMs / math.max(cfg.BlendMs, 1)
    if blend < target then blend = math.min(target, blend + step) else blend = math.max(target, blend - step) end

    if restOffset == nil then return end
    local want = toWorld(restOffset, x, y, z)
    local err = { want[1] - rel[1], want[2] - rel[2], want[3] - rel[3] }
    local errLen = len(err)

    local k = cfg.BodyFollow * blend
    -- Far off (e.g. the bow is being taken away or teleported): leave it to the game
    if k > 0 and errLen > 0.05 and errLen < cfg.MaxCorrection then
        local d = { X = err[1] * k, Y = err[2] * k, Z = err[3] * k }
        Util.SafeCall(function() bow:K2_AddActorWorldOffset(d, false, {}, true) end)
    else
        k = 0
    end

    if Util.Debug then
        record(drawing, errLen, errLen * (1 - k), speed)
        flushStats(dtMs, applying)
    end
end

function BowBody.Init(config)
    cfg = config
    cfg.BodyFollow = Util.Clamp(tonumber(cfg.BodyFollow) or 0, 0, 1)
    cfg.BlendMs = tonumber(cfg.BlendMs) or 150
    cfg.LearnMaxSpeed = tonumber(cfg.LearnMaxSpeed) or 40
    cfg.MaxCorrection = tonumber(cfg.MaxCorrection) or 40
    Util.Log("BowBody: follow=%.2f blend=%d ms", cfg.BodyFollow, cfg.BlendMs)
end

return BowBody
