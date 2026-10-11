-- Grapple only in view: the grapple drone only latches onto a target the
-- player can see.
--
-- The game does not use the native UAtlasGrapplingArmComponent (only its
-- class default exists). The grapple is the Blueprint component
-- BP_AtlasGrapplingArm_C (left hand; BP_AtlasGrapplingArm_R_C for the right),
-- added to the player by the AtlasBPGrapplingArmFeature game feature.
-- Its variables (dumped in game): GrabPressed, ActiveGrappleTargetActor /
-- ActiveGrappleTargetComponent / ActiveGrappleTargetLocation (current
-- target found along the hand), ReachDistance (1200 cm), HandCoupleTimer
-- (already at its maximum, 8, when a target is found, so it is not the
-- trigger).
--
-- Blocking: ReachDistance is set to 1 cm, so the Blueprint finds no target
-- and the hand cannot latch on (verified in game: no grapple while blocked).
-- The Blueprint keeps its last target after grip is released, so the target
-- is only judged while grip is held (see tickComponent).
--
-- In view: the angle between the head direction (headset component) and the
-- target is at most ViewAngle and, with RequireLineOfSight, a Visibility
-- trace from the head to LineOfSightMarginCm short of the target hits nothing
-- (the player, held objects and the target's actor are ignored).
--
-- Components are kept as path strings (StaticFindObject each tick; UObjects
-- are never kept across ticks) and searched with FindAllOf every few seconds
-- while missing.
local Util = require("util")
local Player = require("player")

local Grapple = {}

local CLASS_NAMES = { "BP_AtlasGrapplingArm_C", "BP_AtlasGrapplingArm_R_C" }
local HAND_TAGS = { "L", "R" }
local HAND_CONTROLLERS = { "LeftMotionController", "RightMotionController" }
local BLOCKED_REACH = 1.0        -- cm

local cfg
local paths = {}                 -- class name -> component path
local searchMs = 0
local blocks = {}                -- hand tag -> { path, reach, ms }
local settle = {}                -- hand tag -> ms before the target is judged
local warned = {}
local ksl = nil
local lastBlocker = nil

local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    Util.Log(fmt, ...)
end

-- "Class /Path.Object" -> "/Path.Object"
local function objectPath(obj)
    local ok, full = pcall(function() return obj:GetFullName() end)
    if not ok or type(full) ~= "string" then return nil end
    return full:match("^%S+%s+(.+)$") or full
end

local function shortName(obj)
    local ok, n = pcall(function() return obj:GetFName():ToString() end)
    return ok and tostring(n) or "?"
end

local function readProp(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

local function vec(v)
    if v == nil then return nil end
    local ok, r = pcall(function() return { X = v.X, Y = v.Y, Z = v.Z } end)
    if ok and type(r.X) == "number" and type(r.Y) == "number" and type(r.Z) == "number" then return r end
    return nil
end

-- Real level instance owned by a player pawn (not a class default/template).
local function playerComponent(c)
    if not Util.IsValid(c) then return false end
    local path = objectPath(c)
    if not path or path:find("Default__", 1, true) or path:find("_GEN_VARIABLE", 1, true) then return false end
    local owner = Util.GetOwner(c)
    if not owner then return false end
    local pawn = Player.GetPawn()
    if pawn and Util.Key(owner) == Util.Key(pawn) then return true end
    return shortName(owner):find("^BP_AtlasPlayer_C") ~= nil
end

-- The player's grappling components as { comp, tag, index } (re-found every
-- tick from their paths).
local function components(dtMs)
    local out, missing = {}, false
    for i, cn in ipairs(CLASS_NAMES) do
        local c = paths[cn] and StaticFindObject(paths[cn]) or nil
        if Util.IsValid(c) then
            out[#out + 1] = { comp = c, tag = HAND_TAGS[i], index = i }
        else
            if paths[cn] then Util.DLog("[grapple] component gone: %s", paths[cn]) end
            paths[cn] = nil
            missing = true
        end
    end
    if not missing then return out end
    searchMs = searchMs - dtMs
    if searchMs > 0 then return out end
    searchMs = 3000
    for i, cn in ipairs(CLASS_NAMES) do
        if not paths[cn] then
            for _, c in ipairs(FindAllOf(cn) or {}) do
                if playerComponent(c) then
                    paths[cn] = objectPath(c)
                    Util.DLog("[grapple] component: %s", tostring(paths[cn]))
                    out[#out + 1] = { comp = c, tag = HAND_TAGS[i], index = i }
                    break
                end
            end
        end
    end
    return out
end

local function movement()
    local pawn = Player.GetPawn()
    if not pawn then return nil, nil end
    return pawn, Util.Prop(pawn, "AtlasMovementComponentReference") or Util.Prop(pawn, "AtlasMovementComponent")
end

local function unit(v)
    if not v then return nil end
    local len = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    if len < 1e-3 then return nil end
    return { X = v.X / len, Y = v.Y / len, Z = v.Z / len }
end

-- Location and forward direction of a scene component.
local function pose(comp)
    if not comp then return nil end
    local okL, loc = pcall(function() return vec(comp:K2_GetComponentLocation()) end)
    local okF, fwd = pcall(function() return unit(vec(comp:GetForwardVector())) end)
    if okL and loc and okF and fwd then return loc, fwd end
    return nil
end

local function head()
    local pawn, mc = movement()
    if not pawn then return nil end
    local h = (mc and Util.Prop(mc, "Headset")) or Util.Prop(pawn, "HeadReference") or Util.Prop(pawn, "HeadComponent")
    local loc, fwd = pose(h)
    if loc then return loc, fwd end
    -- Fallback: camera manager location + rotation
    local pc = Player.GetController()
    local cam = pc and Util.Prop(pc, "PlayerCameraManager")
    if not cam then return nil end
    local okL, cl = pcall(function() return vec(cam:GetCameraLocation()) end)
    local okR, rot = pcall(function()
        local r = cam:GetCameraRotation()
        return { Pitch = r.Pitch, Yaw = r.Yaw }
    end)
    if not okL or not cl or not okR or type(rot.Pitch) ~= "number" or type(rot.Yaw) ~= "number" then return nil end
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    return cl, { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end

local function angleDeg(a, b)
    return math.deg(math.acos(Util.Clamp(a.X * b.X + a.Y * b.Y + a.Z * b.Z, -1, 1)))
end

-- Angle between the head direction and where the hand points (nil if unknown).
local function handAimAngle(index, headFwd)
    local _, mc = movement()
    local _, fwd = pose(mc and Util.Prop(mc, HAND_CONTROLLERS[index]))
    if not fwd then return nil end
    return angleDeg(headFwd, fwd)
end

local function targetLocation(comp, target, targetActor)
    local ok, v = pcall(function() return vec(target:K2_GetComponentLocation()) end)
    if ok and v then return v end
    ok, v = pcall(function() return vec(comp.ActiveGrappleTargetLocation) end)
    if ok and v and (v.X ~= 0 or v.Y ~= 0 or v.Z ~= 0) then return v end
    ok, v = pcall(function() return vec(targetActor:K2_GetActorLocation()) end)
    if ok and v then return v end
    return nil
end

-- True when nothing blocks the view from the head to the target; nil when
-- the trace cannot be done.
local function lineOfSight(from, to, targetActor)
    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= cfg.LineOfSightMarginCm then return true end
    local k = (dist - cfg.LineOfSightMarginCm) / dist
    local stop = { X = from.X + dx * k, Y = from.Y + dy * k, Z = from.Z + dz * k }
    local pawn = Player.GetPawn()
    if not pawn then return nil end
    if not Util.IsValid(ksl) then ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not Util.IsValid(ksl) then return nil end
    local ignore = {}
    for hand = 0, 1 do
        local a = Player.Held(hand)
        if a then ignore[#ignore + 1] = a end
    end
    if Util.IsValid(targetActor) then ignore[#ignore + 1] = targetActor end
    lastBlocker = nil
    local hit = {}
    local color = { R = 0, G = 0, B = 0, A = 0 }
    -- TraceTypeQuery1 = Visibility; no debug draw; ignore the pawn (self)
    local ok, blocked = pcall(function()
        return ksl:LineTraceSingle(pawn, from, stop, 0, false, ignore, 0, hit, true, color, color, 0)
    end)
    if not ok or type(blocked) ~= "boolean" then
        warnOnce("trace", "[grapple] line of sight trace failed (%s); only the view angle is checked", tostring(blocked))
        return nil
    end
    if blocked and Util.Debug then
        local okN, name = pcall(function() return hit.HitObjectHandle.Actor:get():GetFName():ToString() end)
        if not okN then okN, name = pcall(function() return hit.Component:get():GetFullName() end) end
        lastBlocker = okN and tostring(name) or nil
    end
    return not blocked
end

-- nil = in view; otherwise the reason it is not.
local function outOfView(comp, target, targetActor, eye, fwd)
    local loc = targetLocation(comp, target, targetActor)
    if not loc then
        warnOnce("loc", "[grapple] target location not readable; grapple not restricted")
        return nil
    end
    local dir = unit({ X = loc.X - eye.X, Y = loc.Y - eye.Y, Z = loc.Z - eye.Z })
    if dir then
        local angle = angleDeg(fwd, dir)
        if angle > cfg.ViewAngle then return string.format("out of view, %.0f deg", angle) end
    end
    if cfg.RequireLineOfSight and lineOfSight(eye, loc, targetActor) == false then
        return "hidden behind " .. tostring(lastBlocker or "geometry")
    end
    return nil
end

local function setReach(comp, v)
    return pcall(function() comp.ReachDistance = v end)
end

local function block(comp, tag, reason, mode)
    if blocks[tag] then return end
    local reach = readProp(comp, "ReachDistance")
    if type(reach) ~= "number" then
        warnOnce("reach", "[grapple] ReachDistance not readable; grapple not restricted")
        return
    end
    if setReach(comp, BLOCKED_REACH) then
        blocks[tag] = { path = objectPath(comp), reach = reach, mode = mode }
        Util.DLog("[grapple] %s BLOCKED (%s)", tag, reason)
    end
end

local function unblock(comp, tag, why)
    local b = blocks[tag]
    if not b then return end
    if comp and objectPath(comp) == b.path then setReach(comp, b.reach) end
    blocks[tag] = nil
    Util.DLog("[grapple] %s unblocked (%s)", tag, why)
end

-- The Blueprint keeps the last target after grip is released and only looks
-- for a new one while grip is held (and while its reach is not blocked), so:
-- nothing is checked without grip; after pressing grip (or unblocking) the
-- target is only judged after SettleMs, when the Blueprint has refreshed it;
-- a hand pointing far from the view (HandAimAngle) is blocked at once; a
-- target blocked for being out of view stays frozen (no new search) and is
-- unblocked as soon as the player turns to see it.
local function tickComponent(c, dtMs, eye, fwd)
    local comp, tag = c.comp, c.tag
    local grab = readProp(comp, "GrabPressed") == true
    settle[tag] = settle[tag] or 0
    if not grab then
        unblock(comp, tag, "grip released")
        settle[tag] = cfg.SettleMs
        return
    end
    local b = blocks[tag]
    local aim = handAimAngle(c.index, fwd)
    if aim and aim > cfg.HandAimAngle then
        if b and b.mode ~= "hand" then unblock(comp, tag, "switch to hand check") end
        block(comp, tag, string.format("hand points away from the view, %.0f deg", aim), "hand")
        settle[tag] = cfg.SettleMs
        return
    end
    if b and b.mode == "hand" then
        unblock(comp, tag, string.format("hand points towards the view, %.0f deg", aim or -1))
        settle[tag] = cfg.SettleMs
        return
    end
    if settle[tag] > 0 then
        settle[tag] = settle[tag] - dtMs
        return
    end
    local target = readProp(comp, "ActiveGrappleTargetComponent")
    local targetActor = readProp(comp, "ActiveGrappleTargetActor")
    if not Util.IsValid(target) then target = nil end
    if not Util.IsValid(targetActor) then targetActor = nil end
    if not target and not targetActor then return end
    local reason = outOfView(comp, target, targetActor, eye, fwd)
    local name = targetActor and shortName(targetActor) or shortName(target)
    if reason and not b then
        block(comp, tag, name .. " " .. reason, "target")
    elseif not reason and b then
        unblock(comp, tag, name .. " in view")
        settle[tag] = cfg.SettleMs
    end
end

function Grapple.Tick(dtMs)
    local list = components(dtMs)
    if #list == 0 then return end
    local eye, fwd = head()
    if not eye then
        warnOnce("head", "[grapple] head position not readable; grapple not restricted")
        return
    end
    for _, c in ipairs(list) do
        tickComponent(c, dtMs, eye, fwd)
    end
end

-- Tweaks turned off (F7): give the game its reach back.
function Grapple.Stop()
    for i, cn in ipairs(CLASS_NAMES) do
        local tag = HAND_TAGS[i]
        if blocks[tag] then
            local c = paths[cn] and StaticFindObject(paths[cn]) or nil
            unblock(Util.IsValid(c) and c or nil, tag, "disabled")
        end
    end
    blocks, settle = {}, {}
end

function Grapple.Init(config)
    cfg = config
    cfg.ViewAngle = cfg.ViewAngle or 60
    if cfg.RequireLineOfSight == nil then cfg.RequireLineOfSight = false end
    cfg.LineOfSightMarginCm = cfg.LineOfSightMarginCm or 100
    cfg.HandAimAngle = cfg.HandAimAngle or 90
    cfg.SettleMs = cfg.SettleMs or 100
    Util.Log("Grapple only in view enabled (view angle=%.0f deg, line of sight=%s)",
        cfg.ViewAngle, tostring(cfg.RequireLineOfSight))
end

return Grapple
