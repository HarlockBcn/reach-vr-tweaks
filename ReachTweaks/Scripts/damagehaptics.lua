-- Damage haptics: a kick on the controllers when the player takes damage
-- (the game has none: UAtlasDamageableComponent::ProcessDamage only
-- broadcasts OnDamaged / OnHealthChanged / OnDeath to Blueprints).
--
-- The damageable component binds its UFUNCTIONs TakingPointDamage (shots,
-- hits), TakingRadialDamage (explosions) and TakingDamage (any damage) to the
-- owner's damage delegates, so hooking them costs nothing until damage
-- happens. They run for every damageable actor: only the player pawn counts.
-- AActor::TakeDamage broadcasts the point/radial event before the generic
-- one, so the same hit arrives twice: a generic event in the same tick as a
-- point/radial one is the same hit and is not counted again.
--
-- Bursts (seen in game, 2026-11-15): pellet weapons hit 2-4 times per frame
-- for ~70 ms (10.4 damage each, player MaxHealth 500). Hits within
-- MinIntervalMs of the first one add up: the first kicks at once and the kick
-- is topped up whenever the summed damage makes it clearly stronger.
--
-- Strength: summed damage / MaxHealth of the component (FullAtFraction of the
-- health = MaxAmplitude), or damage / FullDamage if MaxHealth cannot be read.
-- Direction (Directional): the side of the hit relative to where the head
-- looks; the hand on the far side gets a weaker kick.
--   point:  -ShotFromDirection (where the shot came from; in game it agreed
--           with the hit location whenever both were clear and was clear more
--           often); fallback HitLocation - pawn location
--   radial: Origin - pawn location
--   any:    DamageCauser location - pawn location (if far enough)
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local DamageHaptics = {}

local COMPONENT = "/Script/Atlas.AtlasDamageableComponent"

local cfg
local burst = nil           -- { start, damage, hits, sideSum, sideW, played } hits being summed
local lastSpecificAt = nil  -- nowMs of the last point/radial hit (its generic twin follows)
local nowMs = 0
local otherLogged = 0       -- debug: hits on other actors logged (proves the hooks fire)

local function get(p)
    local ok, v = pcall(function() return p:get() end)
    if ok then return v end
    return nil
end

local function num(v)
    if type(v) == "number" then return v end
    return nil
end

local function vec(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.X, v.Y, v.Z end)
    if ok and type(x) == "number" and type(y) == "number" then return { X = x, Y = y, Z = z or 0 } end
    return nil
end

local function actorLocation(a)
    if not Util.IsValid(a) then return nil end
    local ok, l = pcall(function() return a:K2_GetActorLocation() end)
    return ok and vec(l) or nil
end

local function nameOf(o)
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    return ok and n or "?"
end

-- Yaw of the head (camera), degrees
local function headYaw()
    local pc = Player.GetController()
    local cam = pc and Util.Prop(pc, "PlayerCameraManager")
    local ok, yaw = pcall(function() return cam:GetCameraRotation().Yaw end)
    if ok and type(yaw) == "number" then return yaw end
    return nil
end

-- Side of a horizontal direction relative to the head: -1 left .. +1 right
-- (nil if the direction is too short or the head yaw is unknown)
local function sideOf(dir, minLen)
    if not dir then return nil end
    local len = math.sqrt(dir.X * dir.X + dir.Y * dir.Y)
    if len < (minLen or 1e-3) then return nil end
    local yaw = headYaw()
    if not yaw then return nil end
    local r = math.rad(yaw)
    -- UE: forward = (cos, sin), right = (-sin, cos)
    return (dir.X * -math.sin(r) + dir.Y * math.cos(r)) / len
end

local function sideText(side)
    if side == nil then return "unknown" end
    if side < -0.35 then return string.format("left %.2f", side) end
    if side > 0.35 then return string.format("right %.2f", side) end
    return string.format("front/back %.2f", side)
end

local function isPlayer(actor)
    local key = Player.PawnKey()
    return key ~= nil and Util.IsValid(actor) and Util.Key(actor) == key
end

local function maxHealthOf(comp)
    if not Util.IsValid(comp) then return nil end
    local ok, m = pcall(function() return comp:GetModifiedMaxHealth() end)
    if ok and num(m) and m > 0 then return m end
    ok, m = pcall(function() return comp.MaxHealth end)
    if ok and num(m) and m > 0 then return m end
    return nil
end

local function amplitudeOf(damage, maxH)
    local frac
    if maxH then
        frac = damage / (maxH * math.max(cfg.FullAtFraction, 1e-3))
    else
        frac = damage / math.max(cfg.FullDamage, 1e-3)
    end
    return cfg.MinAmplitude + (cfg.MaxAmplitude - cfg.MinAmplitude) * Util.Clamp(frac, 0, 1)
end

local function kick(kind, damage, comp, side, how)
    if burst == nil or nowMs - burst.start >= cfg.MinIntervalMs then
        burst = { start = nowMs, damage = 0, hits = 0, sideSum = 0, sideW = 0, played = 0 }
    end
    burst.damage = burst.damage + damage
    burst.hits = burst.hits + 1
    if side then
        burst.sideSum = burst.sideSum + side * damage
        burst.sideW = burst.sideW + damage
    end
    local maxH = maxHealthOf(comp)
    local amp = amplitudeOf(burst.damage, maxH)
    -- First hit of a burst, or the sum makes it clearly stronger: (re)kick
    if burst.played > 0 and amp < burst.played + 0.1 then return end
    local bside = burst.sideW > 0 and burst.sideSum / burst.sideW or nil

    local left, right = amp, amp
    if cfg.Directional and bside then
        local s = cfg.DirectionStrength
        left = amp * (1 - s * math.max(0, bside))     -- hit from the right: left weaker
        right = amp * (1 - s * math.max(0, -bside))   -- hit from the left: right weaker
    end
    local tail = cfg.TailFraction
    Haptics.Pulse(Haptics.LEFT, left, cfg.DurationMs, left * tail, cfg.Frequency)
    Haptics.Pulse(Haptics.RIGHT, right, cfg.DurationMs, right * tail, cfg.Frequency)
    burst.played = amp
    Util.DLog("[damagehaptics] %s %.1f dmg (%s%.1f in %d hits, max health %s) from %s (%s) -> L %.2f R %.2f",
        kind, damage, burst.hits > 1 and "burst " or "", burst.damage, burst.hits,
        maxH and string.format("%.0f", maxH) or "?", sideText(bside), how, left, right)
end

-- Common entry: filters the player and bad values
local function hit(kind, comp, damagedActor, damage)
    if not isPlayer(damagedActor) then
        if Util.Debug and otherLogged < 3 and damage and damage > 0 then
            otherLogged = otherLogged + 1
            Util.Log("[damagehaptics] %s %.1f dmg on %s (not the player; hooks work)", kind, damage, nameOf(damagedActor))
        end
        return false
    end
    if not damage or damage <= 0 then
        Util.DLog("[damagehaptics] %s on the player with damage %s: ignored", kind, tostring(damage))
        return false
    end
    return true
end

local function onPoint(selfP, damagedActorP, damageP, _instigatedByP, hitLocationP, _hitCompP, _boneP, shotDirP)
    local comp, actor, damage = get(selfP), get(damagedActorP), num(get(damageP))
    if not hit("point", comp, actor, damage) then return end
    lastSpecificAt = nowMs
    local sd = vec(get(shotDirP))
    local side = sd and sideOf({ X = -sd.X, Y = -sd.Y }) or nil
    local how = side and "shot direction" or "no direction"
    if side == nil then
        local loc, hl = actorLocation(actor), vec(get(hitLocationP))
        side = (loc and hl) and sideOf({ X = hl.X - loc.X, Y = hl.Y - loc.Y }, 5) or nil
        if side then how = "hit location" end
    end
    kick("point", damage, comp, side, how)
end

local function onRadial(selfP, damagedActorP, damageP, _damageTypeP, originP)
    local comp, actor, damage = get(selfP), get(damagedActorP), num(get(damageP))
    if not hit("radial", comp, actor, damage) then return end
    lastSpecificAt = nowMs
    local loc, o = actorLocation(actor), vec(get(originP))
    local side = (loc and o) and sideOf({ X = o.X - loc.X, Y = o.Y - loc.Y }, 20) or nil
    kick("radial", damage, comp, side, side and "explosion origin" or "no direction")
end

local function onAny(selfP, damagedActorP, damageP, _damageTypeP, _instigatedByP, causerP)
    local comp, actor, damage = get(selfP), get(damagedActorP), num(get(damageP))
    if not hit("any", comp, actor, damage) then return end
    -- Same tick as a point/radial hit: the generic twin of that hit
    if lastSpecificAt == nowMs then return end
    local loc, c = actorLocation(actor), actorLocation(get(causerP))
    local side = (loc and c) and sideOf({ X = c.X - loc.X, Y = c.Y - loc.Y }, 50) or nil
    kick("any", damage, comp, side, side and ("causer " .. nameOf(get(causerP))) or "no direction")
end

function DamageHaptics.Tick(dtMs)
    nowMs = nowMs + dtMs
end

function DamageHaptics.Init(config)
    cfg = config
    cfg.MinAmplitude = cfg.MinAmplitude or 0.5
    cfg.MaxAmplitude = cfg.MaxAmplitude or 1.0
    cfg.FullAtFraction = cfg.FullAtFraction or 0.15
    cfg.FullDamage = cfg.FullDamage or 75
    cfg.DurationMs = cfg.DurationMs or 200
    cfg.TailFraction = Util.Clamp(cfg.TailFraction or 0.3, 0, 1)
    cfg.Frequency = cfg.Frequency or 1.0
    cfg.MinIntervalMs = cfg.MinIntervalMs or 80
    if cfg.Directional == nil then cfg.Directional = true end
    cfg.DirectionStrength = Util.Clamp(cfg.DirectionStrength or 0.6, 0, 1)
end

-- Hooks once at startup (config reloads only call Init)
function DamageHaptics.Hook()
    local hooks = {
        { "TakingPointDamage", onPoint },
        { "TakingRadialDamage", onRadial },
        { "TakingDamage", onAny },
    }
    local okCount = 0
    for _, h in ipairs(hooks) do
        local path = COMPONENT .. ":" .. h[1]
        local fn = h[2]
        local ok, err = pcall(function()
            RegisterHook(path, function(...) Util.SafeCall(fn, ...) end)
        end)
        if ok then okCount = okCount + 1 end
        Util.DLog("[damagehaptics] hook %s: %s", path, ok and "OK" or tostring(err))
    end
    Util.Log("Damage haptics enabled (%d/3 hooks, amplitude %.2f-%.2f, %d ms, directional=%s)",
        okCount, cfg.MinAmplitude, cfg.MaxAmplitude, cfg.DurationMs, tostring(cfg.Directional))
end

return DamageHaptics
