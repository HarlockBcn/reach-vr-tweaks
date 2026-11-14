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
-- Stow on release (StowOnRelease): the game stows the shield as soon as the
-- hand holding it reaches the shoulder. When a hand loses the shield while
-- its grip button is still held, the shield is coupled to it again
-- (ForceCoupleShield); letting go of the grip at that spot stows it
-- (ForceStowShield). See onLetGo.
--
-- Shields are kept as path strings (StaticFindObject each tick; UObjects are
-- never kept across ticks), found when a player hand grabs one and dropped
-- when idle again.
local Util = require("util")
local Player = require("player")

local Shield = {}

-- Exact class names (the held actor's class is compared by name)
local SHIELD_BP_CLASSES = { "BP_AtlasShield_C" }
local MOVER_CLASSES = { "ProjectileMovementComponent", "AtlasProjectileMovementComponent" }
local THROW_DETECT_SPEED = 100     -- cm/s
local RELEASE_WINDOW_MS = 400
local DRAG_PER_S = 0.3             -- largest loss per second undone by KeepSpeed
local BOUNCE_ANGLE_COS = math.cos(math.rad(20))
local TRACE_MS = { 50, 150, 400, 1000 }   -- flight speed log points after the throw

local cfg
local paths = {}           -- shield path -> per-shield data
local warned = {}
local gripText             -- defined with the grip helpers (used by the Debug hooks)

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
        m = Util.FindOwnedByCached(shield, MOVER_CLASSES)[1]
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
    -- Function names; the ones about stowing are hooked to log when they run
    local funcs, hooks = {}, {}
    pcall(function()
        cls:ForEachFunction(function(f)
            local n = fname(f)
            funcs[#funcs + 1] = n
            if n:lower():find("stow") then
                local okF, full = pcall(function() return f:GetFullName() end)
                if okF and type(full) == "string" then hooks[#hooks + 1] = { name = n, path = full:gsub("^%S+%s+", "") } end
            end
        end)
    end)
    Util.Log("[shield] %s functions: %s", cname, #funcs > 0 and table.concat(funcs, ", ") or "(none listed)")
    for _, h in ipairs(hooks) do
        local okH, err = pcall(function()
            RegisterHook(h.path, function()
                Util.SafeCall(function() Util.DLog("[shield] BP %s runs (%s)", h.name, gripText()) end)
            end)
        end)
        Util.Log("[shield] hook %s: %s", h.name, okH and "OK" or tostring(err))
    end
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
-- Grip buttons (StowOnRelease). The keys with "grip" in their name mapped in
-- the loaded input mapping contexts (one search, retried on later grabs while
-- none is found), read with PlayerController:IsInputKeyDown or, for analog
-- keys, GetInputAnalogKeyState. Only read when a hand lets go of the shield
-- (and in Debug traces), never every tick.

local gripKeys = nil          -- [hand] = { { name =, digital =, analog = } }
local gripSearches = 0

local function findGripKeys()
    if gripKeys or gripSearches >= 5 then return end
    gripSearches = gripSearches + 1
    local found, seen, names = { [0] = {}, [1] = {} }, {}, {}
    for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
        pcall(function()
            ctx.Mappings:ForEach(function(_, elem)
                local m = elem:get()
                local okK, kn = pcall(function() return m.Key.KeyName:ToString() end)
                if not okK or type(kn) ~= "string" or seen[kn] then return end
                local lk = kn:lower()
                if not lk:find("grip") or lk:find("touch$") then return end
                local hand = lk:find("left") and 0 or (lk:find("right") and 1 or nil)
                if hand == nil then return end
                seen[kn] = true
                local okA, an = pcall(function() return m.Action:GetFName():ToString() end)
                table.insert(found[hand], { name = kn, digital = true, analog = true })
                names[#names + 1] = kn .. " (" .. (okA and tostring(an) or "?") .. ")"
            end)
        end)
    end
    Util.Log("[shield] grip keys: %s", #names > 0 and table.concat(names, ", ") or "none found")
    if #found[0] > 0 or #found[1] > 0 then gripKeys = found end
end

-- true / false, or nil when unknown (no key found or none can be read).
local function gripDown(hand)
    local keys = gripKeys and gripKeys[hand]
    local pc = Player.GetController()
    if not keys or #keys == 0 or not pc then return nil end
    local known = false
    for _, k in ipairs(keys) do
        local key = { KeyName = FName(k.name) }
        if k.digital then
            local ok, down = pcall(function() return pc:IsInputKeyDown(key) end)
            if ok and type(down) == "boolean" then
                known = true
                if down then return true end
            else
                k.digital = false
                Util.DLog("[shield] IsInputKeyDown(%s) unusable", k.name)
            end
        end
        if k.analog then
            local ok, v = pcall(function() return pc:GetInputAnalogKeyState(key) end)
            if ok and type(v) == "number" then
                known = true
                if v > 0.5 then return true end
            else
                k.analog = false
                Util.DLog("[shield] GetInputAnalogKeyState(%s) unusable", k.name)
            end
        end
    end
    if known then return false end
    return nil
end

gripText = function()
    return string.format("grip L=%s R=%s", tostring(gripDown(0)), tostring(gripDown(1)))
end

-- Hand controller position relative to the head, in the head's yaw frame
-- (X forward, Y right, Z up; cm).
local function handRel(hand)
    local pc = Player.GetController()
    local cam = pc and Util.Prop(pc, "PlayerCameraManager")
    local mc = Player.MotionController(hand)
    if not cam or not mc then return nil end
    local okH, h = pcall(function() return vec(cam:GetCameraLocation()) end)
    local okY, yaw = pcall(function() return cam:GetCameraRotation().Yaw end)
    local okM, m = pcall(function() return vec(mc:K2_GetComponentLocation()) end)
    if not (okH and h and okY and type(yaw) == "number" and okM and m) then return nil end
    local dx, dy, dz = m.X - h.X, m.Y - h.Y, m.Z - h.Z
    local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    return { X = dx * c + dy * s, Y = -dx * s + dy * c, Z = dz }
end

local function relText(r)
    if not r then return "hand ?" end
    return string.format("hand fwd %.0f right %.0f up %.0f cm", r.X, r.Y, r.Z)
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

-- ---------------------------------------------------------------------------
-- StowOnRelease: the game stows the shield as soon as the hand holding it
-- reaches the shoulder. When the hand lets go of the shield while its grip is
-- still held, that was the game's stow: the shield is coupled to the hand
-- again and the spot is remembered; letting go of the grip there (slowly)
-- stows it (ForceStowShield).

local function recouple(shield, hand)
    local right = hand == 1
    if pcall(function() shield:ForceCoupleShield(right) end) then return "ForceCoupleShield" end
    if pcall(function() shield:CoupleToHand(not right) end) then return "CoupleToHand" end
    return nil
end

local function recentPeak(d)
    local peak = 0
    for _, s in ipairs(d.samples) do
        if s.speed > peak then peak = s.speed end
    end
    return peak
end

local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Called when no hand holds the shield any more; true when handled here (no
-- throw to look for).
local function onLetGo(d, shield)
    local hand = d.hand
    if hand == nil then return false end
    local grip = gripDown(hand)
    local rel = handRel(hand)
    if grip == true then
        -- Let go by the game with the grip held: its stow
        if d.clock < (d.giveUpUntil or 0) then
            Util.DLog("[shield] stowed with grip held (re-couple paused), %s", relText(rel))
            return true
        end
        local recent = {}
        for _, t in ipairs(d.blocks) do
            if d.clock - t < 1000 then recent[#recent + 1] = t end
        end
        recent[#recent + 1] = d.clock
        d.blocks = recent
        if #recent >= 4 then
            d.giveUpUntil = d.clock + 3000
            Util.Log("[shield] the game keeps stowing the shield: re-couple paused for 3 s")
        end
        d.zone = rel or d.zone
        local how = recouple(shield, hand)
        d.recoupleMs = how and 0 or nil
        Util.DLog("[shield] stow with grip held blocked: %s (%s)", how and ("re-couple via " .. how) or "re-couple FAILED", relText(rel))
        return true
    end
    if grip == false and d.zone and rel and dist(rel, d.zone) <= cfg.StowZoneCm then
        local peak = recentPeak(d)
        if peak <= cfg.StowMaxSpeed then
            local ok = pcall(function() shield:ForceStowShield() end)
            Util.DLog("[shield] grip released at the shoulder (%.0f cm from the stow spot, %.0f cm/s): ForceStowShield %s",
                dist(rel, d.zone), peak, ok and "OK" or "FAILED")
            d.zone = nil
            return true
        end
    end
    Util.DLog("[shield] let go: %s, %s", grip == nil and "grip unknown" or "grip released", relText(rel))
    return false
end

-- Debug: shield state changes (CurrentShieldState) with the grip state.
local function traceState(d, shield)
    if d.noState then return end
    local ok, st = pcall(function() return shield.CurrentShieldState end)
    if not ok or st == nil then
        d.noState = true
        return
    end
    st = tostring(st)
    if st ~= d.state then
        Util.DLog("[shield] state %s -> %s (%s, %s)", tostring(d.state), st, gripText(), relText(d.hand and handRel(d.hand)))
        d.state = st
    end
end

local function tickShield(d, shield, dtMs)
    d.clock = d.clock + dtMs
    if Util.Debug then
        describe(shield)
        traceState(d, shield)
    end
    local hands = Player.HandsHolding(shield)
    if #hands > 0 then
        if not d.held then
            Util.DLog("[shield] grabbed%s", d.recoupleMs and string.format(" (re-coupled after %.0f ms)", d.recoupleMs) or "")
        end
        d.held, d.flying, d.releaseMs, d.recoupleMs = true, false, nil, nil
        d.hand = hands[1]
        sampleSwing(d, shield, dtMs)
        return
    end
    if d.recoupleMs then
        d.recoupleMs = d.recoupleMs + dtMs
        if d.recoupleMs > RELEASE_WINDOW_MS then
            d.recoupleMs = nil
            Util.DLog("[shield] re-couple did not take")
        end
        return
    end
    if d.held then
        d.held = false
        d.relPos = nil
        if cfg.StowOnRelease and onLetGo(d, shield) then
            d.samples = {}
            return
        end
        d.releaseMs = 0
        Util.DLog("[shield] released (%d swing samples)", #d.samples)
    end
    if not d.releaseMs and not d.flying then return end
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

-- A shield is tracked from the moment a player hand holds it until it is
-- idle again (not held, no throw pending, not flying); then it is dropped and
-- found again the next time it is grabbed. No object search is needed: only
-- a thrown shield matters, and it is always held first.
local heldKeys = { [0] = nil, [1] = nil }   -- held actor key last checked per hand

local function discover()
    for hand = 0, 1 do
        local a = Player.Held(hand)
        local key = a and Util.Key(a) or nil
        if key ~= heldKeys[hand] then
            heldKeys[hand] = key
            if a then
                local okC, cls = pcall(function() return a:GetClass() end)
                local cname = okC and fname(cls) or nil
                for _, cn in ipairs(SHIELD_BP_CLASSES) do
                    if cname == cn then
                        local p = Util.Path(a)
                        if p and not paths[p] then
                            paths[p] = { samples = {}, clock = 0, blocks = {} }
                            Util.DLog("[shield] found %s", p)
                        end
                        if cfg.StowOnRelease then findGripKeys() end
                        break
                    end
                end
            end
        end
    end
end

local function idle(d)
    return not d.held and not d.releaseMs and not d.flying and not d.recoupleMs
end

function Shield.Tick(dtMs)
    discover()
    for p, d in pairs(paths) do
        local shield = StaticFindObject(p)
        if Util.IsValid(shield) then
            tickShield(d, shield, dtMs)
            if idle(d) then paths[p] = nil end
        else
            Util.DLog("[shield] gone: %s", p)
            paths[p] = nil
        end
    end
end

-- Tweaks turned off (F7): nothing of the game is changed outside a throw.
function Shield.Stop()
    paths = {}
    heldKeys = { [0] = nil, [1] = nil }
end

function Shield.Init(config)
    cfg = config
    cfg.UsePeakSpeed = cfg.UsePeakSpeed ~= false
    cfg.PeakWindowMs = cfg.PeakWindowMs or 150
    cfg.MinThrowSpeed = cfg.MinThrowSpeed or 0
    cfg.ThrowSpeedMultiplier = cfg.ThrowSpeedMultiplier or 1.0
    cfg.KeepSpeed = cfg.KeepSpeed ~= false
    cfg.StowOnRelease = cfg.StowOnRelease ~= false
    cfg.StowZoneCm = cfg.StowZoneCm or 25
    cfg.StowMaxSpeed = cfg.StowMaxSpeed or 300
    Util.Log("Shield throw enabled (peak=%s, min=%.0f cm/s, x%.2f, keep speed=%s, stow on release=%s)",
        tostring(cfg.UsePeakSpeed), cfg.MinThrowSpeed, cfg.ThrowSpeedMultiplier, tostring(cfg.KeepSpeed),
        tostring(cfg.StowOnRelease))
end

return Shield
