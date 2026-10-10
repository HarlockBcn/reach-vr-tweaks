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
local firstApplied = false

-- Debug statistics (one summary per second)
local stats = nil
local statAcc = 0

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

-- World axes of a scene component (forward = X, right = Y, up = Z)
local function compAxes(c)
    local ok, x, y, z = pcall(function()
        return vec(c:GetForwardVector()), vec(c:GetRightVector()), vec(c:GetUpVector())
    end)
    if ok and x and y and z then return x, y, z end
    return nil
end

-- Logs once why the module is idle (avoids silent failures)
local lastWhy = nil
local function idle(why)
    if why ~= lastWhy then
        lastWhy = why
        Util.DLog("BowBody: idle (%s)", why)
    end
end

-- Which hand holds the grip and whether a hand holds the string, from the
-- partners of the player's hand couplers. Falls back to the hand that held
-- the bow alone when the coupler cannot be matched.
local lastGripHand = nil
local lastState = nil
local function bowHands(bow)
    local gk = Util.Key(Util.Prop(bow, "BowCouplerRef") or bow)
    local sk = Util.Key(Util.Prop(bow, "BowStringCouplerRef") or bow)
    local bk = Util.Key(bow)
    local grip, drawing, holding = nil, false, {}
    for hand = 0, 1 do
        for _, p in ipairs(Player.HandPartners(hand)) do
            local k = Util.Key(p)
            if k == gk then grip = hand end
            if k == sk then drawing = true end
            local o = Util.GetOwner(p)
            if o and Util.Key(o) == bk and holding[#holding] ~= hand then holding[#holding + 1] = hand end
        end
    end
    local how = grip ~= nil and "grip coupler" or "fallback"
    if grip == nil then
        if #holding == 1 then
            grip = holding[1]
        elseif #holding >= 2 then
            grip = lastGripHand
            drawing = true
        end
    elseif #holding >= 2 then
        drawing = true
    end
    if #holding == 1 then lastGripHand = grip end
    local state = string.format("grip hand %s (%s), hands on bow %d, drawing %s",
        tostring(grip), how, #holding, tostring(drawing))
    if state ~= lastState then
        lastState = state
        Util.DLog("BowBody: %s", state)
    end
    return grip, drawing
end

-- Grip hand and drawing state of a bow (also used by lagprobe.lua)
function BowBody.Hands(bow) return bowHands(bow) end

local function newStats()
    local function one() return { n = 0, sum = 0, max = 0, post = 0, cPos = 0, bPos = 0, cRot = 0, bRot = 0 } end
    return { [false] = one(), [true] = one(), vmax = 0 }
end

-- Rotation angle (degrees) between two frames given by their axes
local function frameAngle(a, b)
    local tr = dot(a[1], b[1]) + dot(a[2], b[2]) + dot(a[3], b[3])
    return math.deg(math.acos(Util.Clamp((tr - 1) / 2, -1, 1)))
end

-- How much the bow moves compared to the controller over the same frames:
-- 100 % = the bow follows the hand fully, 50 % = it covers half the motion.
local prevFrame = nil
local function recordMotion(drawing, cLoc, cAxes, gLoc, bAxes)
    local p = prevFrame
    prevFrame = { cLoc = cLoc, cAxes = cAxes, gLoc = gLoc, bAxes = bAxes }
    if not p then return end
    stats = stats or newStats()
    local s = stats[drawing]
    s.cPos = s.cPos + len({ cLoc[1] - p.cLoc[1], cLoc[2] - p.cLoc[2], cLoc[3] - p.cLoc[3] })
    s.bPos = s.bPos + len({ gLoc[1] - p.gLoc[1], gLoc[2] - p.gLoc[2], gLoc[3] - p.gLoc[3] })
    s.cRot = s.cRot + frameAngle(p.cAxes, cAxes)
    s.bRot = s.bRot + frameAngle(p.bAxes, bAxes)
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
    -- only with noticeable movement (> 80 cm/s or > 20 degrees turned)
    if not st or (st.vmax < 80 and st[false].cRot + st[true].cRot < 20) then return end
    local f, d = st[false], st[true]
    local parts = {}
    local function follow(s)
        local pos = s.cPos > 1 and string.format("%3.0f%%", 100 * s.bPos / s.cPos) or "  -"
        local rot = s.cRot > 3 and string.format("%3.0f%%", 100 * s.bRot / s.cRot) or "  -"
        return string.format("follow pos %s (%.0f cm) rot %s (%.0f deg)", pos, s.cPos, rot, s.cRot)
    end
    if f.n > 0 then
        parts[#parts + 1] = string.format("grip-only err avg %.1f max %.1f %s", f.sum / f.n, f.max, follow(f))
    end
    if d.n > 0 then
        parts[#parts + 1] = string.format("DRAWING err avg %.1f max %.1f -> shown avg %.1f %s",
            d.sum / d.n, d.max, d.post / d.n, follow(d))
    end
    Util.Log("[bowbody] vmax=%4.0f cm/s %s (follow=%.2f %s)", st.vmax, table.concat(parts, " | "),
        cfg.BodyFollow, applying and "ON" or "OFF")
end

local function reset()
    bowKey, restOffset, heldMs, blend, prevCtrl, prevFrame = nil, nil, 0, 0, nil, nil
end

-- applying = false measures only (tweaks disabled with F7)
function BowBody.Tick(dtMs, applying)
    local _, bow = Player.HandHoldingClass({ BOW_CLASS })
    if not bow then
        if bowKey then reset() end
        lastGripHand = nil
        return
    end
    local hand, drawing = bowHands(bow)
    if hand == nil then return idle("grip hand unknown") end
    local key = Util.Key(bow)
    if key ~= bowKey then
        reset()
        bowKey = key
    end
    heldMs = heldMs + dtMs

    local mc = Player.MotionController(hand)
    local grip = Util.Prop(bow, "BowCouplerRef")
    if not mc then return idle("no motion controller") end
    if not grip then return idle("no BowCouplerRef") end
    local cLoc, gLoc = compLoc(mc), compLoc(grip)
    local x, y, z = compAxes(mc)
    if not cLoc or not gLoc or not x then return idle("no controller/grip transform") end

    local speed = 0
    if prevCtrl then
        speed = len({ cLoc[1] - prevCtrl[1], cLoc[2] - prevCtrl[2], cLoc[3] - prevCtrl[3] }) / (dtMs / 1000)
    end
    prevCtrl = cLoc

    local rel = { gLoc[1] - cLoc[1], gLoc[2] - cLoc[2], gLoc[3] - cLoc[3] }

    if not drawing then
        -- Learn the grip offset while the bow is held still with one hand
        if heldMs > 500 and speed < cfg.LearnMaxSpeed then
            local l = toLocal(rel, x, y, z)
            if restOffset == nil then
                restOffset = l
                Util.DLog("BowBody: grip offset learned (hand %d): %.1f %.1f %.1f", hand, l[1], l[2], l[3])
            else
                for i = 1, 3 do restOffset[i] = restOffset[i] + (l[i] - restOffset[i]) * 0.1 end
            end
        end
    end

    -- Fade the correction in while drawing and out after releasing
    local target = (drawing and applying) and 1 or 0
    local step = dtMs / math.max(cfg.BlendMs, 1)
    if blend < target then blend = math.min(target, blend + step) else blend = math.max(target, blend - step) end

    if restOffset == nil then return idle("grip offset not learned yet: hold the bow still") end
    lastWhy = nil
    local want = toWorld(restOffset, x, y, z)
    local err = { want[1] - rel[1], want[2] - rel[2], want[3] - rel[3] }
    local errLen = len(err)

    local k = cfg.BodyFollow * blend
    -- Far off (e.g. the bow is being taken away or teleported): leave it to the game
    if k > 0 and errLen > 0.05 and errLen < cfg.MaxCorrection then
        local d = { X = err[1] * k, Y = err[2] * k, Z = err[3] * k }
        Util.SafeCall(function() bow:K2_AddActorWorldOffset(d, false, {}, true) end)
        if not firstApplied then
            firstApplied = true
            Util.DLog("BowBody: first correction %.1f cm (k=%.2f)", errLen * k, k)
        end
    else
        k = 0
    end

    if Util.Debug then
        local okb, bx, by, bz = pcall(function()
            return vec(bow:GetActorForwardVector()), vec(bow:GetActorRightVector()), vec(bow:GetActorUpVector())
        end)
        if okb and bx then recordMotion(drawing, cLoc, { x, y, z }, gLoc, { bx, by, bz }) end
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
