-- Shield throw speed: the thrown shield leaves at the speed of the swing and
-- keeps it in flight.
--
-- The shield used in game is the pure Blueprint BP_AtlasShield_C (class
-- chain BP_AtlasShield_C < Actor, game feature AtlasBPShieldFeature) with a
-- ProjectileMovementComponent; the native AAtlasShield is unused (same story
-- as the grapple). Measured in game: it is thrown at ~2000-2800 cm/s (more
-- than the swing peak measured here, ~650-760 cm/s) and only loses speed on
-- bounces. The native AAtlasShield, for reference: the throw speed is
-- the hand speed of the release frame (not the peak of the swing), and in
-- flight UShieldState_Thrown::UpdateProjectilePhysics loses ~10 % of the
-- speed per second and turns gravity on below 1000 cm/s.
--
-- This module does not depend on the shield's own logic:
--  * while a hand holds the shield, its speed relative to the pawn is
--    sampled from the actor locations (PeakWindowMs window);
--  * after it is let go, the first time it moves faster than
--    THROW_DETECT_SPEED within RELEASE_WINDOW_MS is the throw: its velocity
--    is rescaled to max(game speed, swing peak) x ThrowSpeedMultiplier, at
--    least MinThrowSpeed;
--  * in flight (KeepSpeed) losses as small as a drag are undone; a sharp turn
--    (bounce) or a bigger loss (friction) sets the new speed to keep. Flight
--    ends when the shield stops or is held again.
-- The velocity is the ProjectileMovementComponent Velocity when the shield
-- has one, otherwise the physics velocity of its root component.
--
-- Shields are kept as path strings (StaticFindObject each tick; UObjects are
-- never kept across ticks) and searched every few seconds.
local Util = require("util")
local Player = require("player")

local Shield = {}

-- FindAllOf is exact-class only
local SHIELD_BP_CLASSES = { "BP_AtlasShield_C" }
local MOVER_CLASSES = { "ProjectileMovementComponent", "AtlasProjectileMovementComponent" }
local THROW_DETECT_SPEED = 100     -- cm/s
local RELEASE_WINDOW_MS = 400
local DRAG_PER_S = 0.3             -- largest loss per second undone by KeepSpeed
local BOUNCE_ANGLE_COS = math.cos(math.rad(20))
local TRACE_MS = { 50, 150, 400, 1000 }   -- flight speed log points after the throw

local cfg
local paths = {}           -- shield path -> per-shield data
local searchMs = 0
local warned = {}

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

local function fname(obj)
    local ok, n = pcall(function() return obj:GetFName():ToString() end)
    return ok and tostring(n) or "?"
end

local function vec(v)
    if v == nil then return nil end
    local ok, r = pcall(function() return { X = v.X, Y = v.Y, Z = v.Z } end)
    if ok and type(r.X) == "number" and type(r.Y) == "number" and type(r.Z) == "number" then return r end
    return nil
end

local function len(v)
    return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local function scaled(v, k)
    return { X = v.X * k, Y = v.Y * k, Z = v.Z * k }
end

local function near(a, b)
    return a ~= nil and math.abs(a.X - b.X) < 0.5 and math.abs(a.Y - b.Y) < 0.5 and math.abs(a.Z - b.Z) < 0.5
end

local function actorLocation(a)
    local ok, v = pcall(function() return vec(a:K2_GetActorLocation()) end)
    if ok then return v end
    return nil
end

-- ---------------------------------------------------------------------------
-- Velocity access: projectile movement component or root physics body

local function moverOf(shield, d)
    if d.moverPath then
        local m = StaticFindObject(d.moverPath)
        if Util.IsValid(m) then return m end
        d.moverPath = nil
    end
    local m = Util.Prop(shield, "ProjectileMovementRef")
    if not m then
        m = Util.FindOwnedBy(shield, MOVER_CLASSES)[1]
    end
    if m then d.moverPath = objectPath(m) end
    return m
end

local function rootOf(shield)
    local ok, r = pcall(function() return shield:K2_GetRootComponent() end)
    if ok and Util.IsValid(r) then return r end
    return nil
end

local function getVelocity(shield, d)
    local m = moverOf(shield, d)
    if m then
        local ok, v = pcall(function() return vec(m.Velocity) end)
        if ok and v then return v, "projectile" end
    end
    local r = rootOf(shield)
    if r then
        local ok, v = pcall(function() return vec(r:GetPhysicsLinearVelocity(FName("None"))) end)
        if ok and v then return v, "physics" end
    end
    return nil
end

-- Writes and reads back; true when the new value stuck.
local function setVelocity(shield, d, v)
    local m = moverOf(shield, d)
    if m then
        pcall(function() m.Velocity = { X = v.X, Y = v.Y, Z = v.Z } end)
        local ok, r = pcall(function() return vec(m.Velocity) end)
        if ok and near(r, v) then return true end
        pcall(function()
            local s = m.Velocity
            s.X, s.Y, s.Z = v.X, v.Y, v.Z
        end)
        ok, r = pcall(function() return vec(m.Velocity) end)
        if ok and near(r, v) then return true end
    end
    local r = rootOf(shield)
    if r then
        pcall(function() r:SetPhysicsLinearVelocity({ X = v.X, Y = v.Y, Z = v.Z }, false, FName("None")) end)
        local ok, rv = pcall(function() return vec(r:GetPhysicsLinearVelocity(FName("None"))) end)
        if ok and near(rv, v) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Diagnostics (Debug only, once per shield class): class chain, the
-- Blueprint's own property names (names only: reading every value of a
-- Blueprint once crashed the game) and movement components.

local described = {}

local function describe(shield)
    local okC, cls = pcall(function() return shield:GetClass() end)
    if not okC or not Util.IsValid(cls) then return end
    local cname = fname(cls)
    if described[cname] then return end
    described[cname] = true
    local chain, c = {}, cls
    for _ = 1, 12 do
        if not Util.IsValid(c) then break end
        chain[#chain + 1] = fname(c)
        local ok, s = pcall(function() return c:GetSuperStruct() end)
        if not ok then break end
        c = s
    end
    Util.Log("[shield] class chain: %s", table.concat(chain, " < "))
    local props = {}
    pcall(function()
        cls:ForEachProperty(function(p)
            local okT, t = pcall(function() return p:GetClass():GetFName():ToString() end)
            props[#props + 1] = fname(p) .. ":" .. (okT and tostring(t) or "?")
        end)
    end)
    Util.Log("[shield] %s properties: %s", cname, #props > 0 and table.concat(props, ", ") or "(none listed)")
    local movers = {}
    for _, m in ipairs(Util.FindOwnedBy(shield, MOVER_CLASSES)) do
        movers[#movers + 1] = fname(m) .. " (" .. fname(m:GetClass()) .. ")"
    end
    local r = rootOf(shield)
    local okP, sim = pcall(function() return r:IsSimulatingPhysics(FName("None")) end)
    Util.Log("[shield] movement: %s; root %s simulating physics=%s",
        #movers > 0 and table.concat(movers, ", ") or "no ProjectileMovementComponent",
        r and fname(r) or "?", okP and tostring(sim) or "?")
end

-- ---------------------------------------------------------------------------

local function isHeld(shield)
    return #Player.HandsHolding(shield) > 0
end

-- Speed of the shield relative to the pawn (cm/s) from the actor locations.
local function sampleSwing(d, shield, dtMs)
    local pawn = Player.GetPawn()
    local s = actorLocation(shield)
    local p = pawn and actorLocation(pawn)
    if not s or not p then
        d.relPos = nil
        return
    end
    local rel = { X = s.X - p.X, Y = s.Y - p.Y, Z = s.Z - p.Z }
    if d.relPos and dtMs > 0 then
        local dx, dy, dz = rel.X - d.relPos.X, rel.Y - d.relPos.Y, rel.Z - d.relPos.Z
        local speed = math.sqrt(dx * dx + dy * dy + dz * dz) / (dtMs / 1000)
        if speed < 10000 then   -- ignore teleports
            d.samples[#d.samples + 1] = { t = d.clock, speed = speed }
        end
    end
    d.relPos = rel
    while #d.samples > 0 and d.clock - d.samples[1].t > cfg.PeakWindowMs do
        table.remove(d.samples, 1)
    end
end

local function onThrown(d, shield, v, kind)
    local game = len(v)
    local peak = 0
    for _, s in ipairs(d.samples) do
        if s.speed > peak then peak = s.speed end
    end
    local speed = game
    if cfg.UsePeakSpeed and peak > speed then speed = peak end
    speed = speed * cfg.ThrowSpeedMultiplier
    if speed < cfg.MinThrowSpeed then speed = cfg.MinThrowSpeed end
    local okW = math.abs(speed / game - 1) < 1e-3 or setVelocity(shield, d, scaled(v, speed / game))
    d.flying = true
    d.keep = speed
    d.lastDir = scaled(v, 1 / game)
    d.flightMs = 0
    d.traceIdx = 1
    Util.DLog("[shield] throw (%s): game %.0f cm/s, swing peak %.0f cm/s -> %.0f cm/s%s",
        kind, game, peak, speed, okW and "" or " (write FAILED)")
end

-- In flight: undo small losses; a bounce or a bigger loss sets a new speed.
local function keepSpeed(d, shield, v, dtMs)
    local speed = len(v)
    local dir = scaled(v, 1 / speed)
    local last = d.lastDir
    d.lastDir = dir
    if last and dir.X * last.X + dir.Y * last.Y + dir.Z * last.Z < BOUNCE_ANGLE_COS then
        Util.DLog("[shield] bounce: %.0f -> %.0f cm/s", d.keep, speed)
        d.keep = speed
        return
    end
    if speed >= d.keep then
        d.keep = speed
        return
    end
    if (d.keep - speed) / d.keep > DRAG_PER_S * dtMs / 1000 + 0.01 then
        d.keep = speed
        return
    end
    setVelocity(shield, d, scaled(dir, d.keep))
end

local function tickShield(d, shield, dtMs)
    d.clock = d.clock + dtMs
    if Util.Debug then describe(shield) end
    if isHeld(shield) then
        if not d.held then Util.DLog("[shield] grabbed") end
        d.held, d.flying, d.releaseMs = true, false, nil
        sampleSwing(d, shield, dtMs)
        return
    end
    if d.held then
        d.held = false
        d.releaseMs = 0
        d.relPos = nil
        Util.DLog("[shield] released (%d swing samples)", #d.samples)
    end
    local v, kind = getVelocity(shield, d)
    local speed = v and len(v) or 0
    if d.releaseMs then
        d.releaseMs = d.releaseMs + dtMs
        if v and speed > THROW_DETECT_SPEED then
            d.releaseMs = nil
            onThrown(d, shield, v, kind)
            d.samples = {}
            return
        end
        if d.releaseMs > RELEASE_WINDOW_MS then
            d.releaseMs = nil
            d.samples = {}
            Util.DLog("[shield] no throw after release (speed %.0f cm/s, %s)", speed, tostring(kind or "no velocity"))
        end
        return
    end
    if not d.flying then return end
    if not v or speed < 1 then
        d.flying = false
        Util.DLog("[shield] stopped after %.0f ms", d.flightMs)
        return
    end
    d.flightMs = d.flightMs + dtMs
    if TRACE_MS[d.traceIdx] and d.flightMs >= TRACE_MS[d.traceIdx] then
        Util.DLog("[shield] flight %4.0f ms: %.0f cm/s (keeping %.0f)", d.flightMs, speed, d.keep)
        d.traceIdx = d.traceIdx + 1
    end
    if cfg.KeepSpeed then keepSpeed(d, shield, v, dtMs) end
end

function Shield.Tick(dtMs)
    searchMs = searchMs - dtMs
    if searchMs <= 0 then
        searchMs = 2000
        local found = {}
        for _, cn in ipairs(SHIELD_BP_CLASSES) do
            for _, a in ipairs(FindAllOf(cn) or {}) do found[#found + 1] = a end
        end
        if #found == 0 and next(paths) == nil and Util.Debug then
            warnOnce("none", "[shield] no shield in the world yet")
        end
        for _, a in ipairs(found) do
            local p = objectPath(a)
            if p and not p:find("Default__", 1, true) and not p:find("_GEN_VARIABLE", 1, true) and not paths[p] then
                paths[p] = { samples = {}, clock = 0 }
                Util.DLog("[shield] found %s", p)
            end
        end
    end
    for p, d in pairs(paths) do
        local shield = StaticFindObject(p)
        if Util.IsValid(shield) then
            tickShield(d, shield, dtMs)
        else
            Util.DLog("[shield] gone: %s", p)
            paths[p] = nil
        end
    end
end

-- Tweaks turned off (F7): nothing of the game is changed outside a throw.
function Shield.Stop()
    paths = {}
    searchMs = 0
end

function Shield.Init(config)
    cfg = config
    cfg.UsePeakSpeed = cfg.UsePeakSpeed ~= false
    cfg.PeakWindowMs = cfg.PeakWindowMs or 150
    cfg.MinThrowSpeed = cfg.MinThrowSpeed or 0
    cfg.ThrowSpeedMultiplier = cfg.ThrowSpeedMultiplier or 1.0
    cfg.KeepSpeed = cfg.KeepSpeed ~= false
    Util.Log("Shield throw enabled (peak=%s, min=%.0f cm/s, x%.2f, keep speed=%s)",
        tostring(cfg.UsePeakSpeed), cfg.MinThrowSpeed, cfg.ThrowSpeedMultiplier, tostring(cfg.KeepSpeed))
end

return Shield
