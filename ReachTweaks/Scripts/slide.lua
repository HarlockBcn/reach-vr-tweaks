-- Sprint slide: crouching while sprinting slides the player a few metres in
-- the direction they were running, at the game's crouch height.
--
-- Game crouch (BP_AtlasMovementComponent): the crouch button (IA_Crouch, "B")
-- toggles StartButtonCrouch / StopButtonCrouch (bButtonCrouch); the head is
-- then held at "Crouch Height" (~90 cm). StopButtonCrouch alone leaves
-- bWantsToCrouch set: the game then calls TryUncrouch -> UnCrouch to give the
-- real head height back. Starting a sprint calls TryUncrouch ("On Sprint
-- Started"), so a sprint stands the player up.
--
-- Triggers (Slide.Trigger): ducking the head (a quick drop of the head
-- height) or the crouch button, while sprinting. IA_Crouch is only handled in
-- Blueprint, so its input event (InpActEvt_IA_Crouch_*) is found at runtime
-- and hooked.
--  * Head slide: the mod calls StartButtonCrouch at the start and
--    StopButtonCrouch at the end (back to the real height).
--  * Button slide: the game crouches by itself; at the end the mod stands
--    the player up unless the crouch button is still held.
-- Movement: the game's thrusters (AddLinearThruster, non-additive = overrides
-- the stick velocity), chained one at a time with HasActiveOverrideThrusters.
-- Sprint lines: bIsSprinting is written directly (no OnSprintStarted, which
-- would uncrouch), so the sprint effect keeps running during the slide.
-- No sprint while crouched (button or physically): bIsSprinting is held on
-- with Speed at walk speed, so the sprint input cannot start a real sprint
-- (which would also stand the player up).
-- Landing: while airborne and for LandSettleMs after landing the head height
-- is ignored. Landing from a height dips the head relative to the feet (the
-- game smooths the head down after the feet hit the floor), which looked like
-- a quick duck and started a slide.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local Slide = {}

local cfg

-- Recent head heights {t, h} (seconds, cm above the feet)
local history = {}
local clock = 0

local lastPos = nil
local velX, velY = 0, 0          -- smoothed horizontal velocity (cm/s)
local lastSprintAt = -1          -- clock when a real sprint was last seen

local sliding = false
local slideT = 0
local dirX, dirY = 0, 0
local startSpeed = 0
local blockedMs, airMs = 0, 0
local cooldown = 0
local byButton = false
local weCrouched = false         -- the mod started the button crouch for this slide
local pressedDuringSlide = false
local logAcc = 0

-- Sprint held on by the mod (slide lines or crouch lock)
local sprintHeld = false
local locked = false
local physCrouched = false
local lastButtonCrouch = false
local buttonCrouchChangedAt = -10
local lastAirAt = -10            -- last tick spent off the ground (clock, s)
local landMinH = nil             -- lowest head height while settling after a landing (debug)

-- Crouch button
local hooked = {}                -- hooked function paths
local hookSearchKey = nil        -- pawn the search was done for
local hookRetryMs = 0
local fullSearchDone = false
local lastButtonEvent = -10      -- clock of the last IA_Crouch event
local buttonPressAt = nil        -- clock of a press not yet consumed
local crouchKeys = nil           -- key names mapped to IA_Crouch

local function movement(pawn)
    return Util.Prop(pawn, "AtlasMovementComponentReference") or Util.Prop(pawn, "AtlasMovementComponent")
end

local function readBool(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    return ok and v == true
end

local function readNum(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function write(obj, name, value)
    pcall(function() obj[name] = value end)
end

local function call(obj, fn, ...)
    local args = { ... }
    local ok, v = pcall(function() return obj[fn](obj, table.unpack(args)) end)
    if ok then return v end
    return nil
end

-- Head height above the feet (cm).
local function headHeight(pawn, mc)
    local head = Util.Prop(pawn, "HeadReference") or Util.Prop(pawn, "HeadComponent")
    local feet = call(mc, "GetActorFeetLocation")
    if head and feet then
        local ok, loc = pcall(function() return head:K2_GetComponentLocation() end)
        if ok and loc then return loc.Z - feet.Z end
    end
    return readNum(mc, "CurrentHeight")
end

-- Standing head height: the calibrated player height when available.
-- Standing head height, learnt from the measured head height: it follows the
-- head up quickly (but not single-frame spikes) and sinks slowly while the
-- player stays low. The game's calibration offset is not used: after a level
-- change it no longer matched the measured head height (stand 174 cm vs a
-- real 143 cm), so the player counted as crouched all the time.
local standRef = nil
local STAND_RISE = 60      -- cm/s
local STAND_SINK = 0.5     -- cm/s
local TELEPORT_CM = 300    -- a bigger jump in one tick is a teleport, not movement
local teleportAt = -10
local function standingHeight(h, dt)
    if standRef == nil then
        standRef = h
    elseif h > standRef then
        standRef = math.min(h, standRef + STAND_RISE * dt)
    else
        standRef = math.max(h, standRef - STAND_SINK * dt)
    end
    return standRef
end

local function pushHistory(h)
    history[#history + 1] = { t = clock, h = h }
    local window = cfg.CrouchWindowMs / 1000
    while #history > 0 and clock - history[1].t > window do table.remove(history, 1) end
end

local function peakHeight()
    local m = nil
    for _, s in ipairs(history) do
        if m == nil or s.h > m then m = s.h end
    end
    return m
end

local function speedAt(t)
    -- Fast ease-out to EndSpeedFactor of the start speed
    local k = Util.Clamp(t / cfg.DurationMs, 0, 1)
    local e = cfg.EndSpeedFactor
    return startSpeed * (e + (1 - e) * (1 - k) * (1 - k))
end

-- Holds bIsSprinting on without the OnSprintStarted broadcast; Speed stays at
-- walk speed. Releasing it lets the sprint input start a real sprint again.
local function holdSprint(mc, on, endRealSprint)
    if on then
        -- A real sprint is ended the game's way first (OnSprintEnded)
        if endRealSprint and not sprintHeld and readBool(mc, "bIsSprinting") then call(mc, "StopSprint") end
        if not readBool(mc, "bIsSprinting") then write(mc, "bIsSprinting", true) end
        local run, walk, speed = readNum(mc, "RunSpeed"), readNum(mc, "WalkSpeed"), readNum(mc, "Speed")
        if run and walk and speed and math.abs(speed - run) < 0.5 then write(mc, "Speed", walk) end
        sprintHeld = true
    elseif sprintHeld then
        write(mc, "bIsSprinting", false)
        sprintHeld = false
    end
end

-- Key names mapped to IA_Crouch in the loaded input mapping contexts.
local function findCrouchKeys()
    local keys = {}
    for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
        pcall(function()
            ctx.Mappings:ForEach(function(_, elem)
                local m = elem:get()
                local okA, an = pcall(function() return m.Action:GetFName():ToString() end)
                if okA and an == "IA_Crouch" then
                    local okK, kn = pcall(function() return m.Key.KeyName:ToString() end)
                    if okK and kn and kn ~= "None" then keys[#keys + 1] = kn end
                end
            end)
        end)
    end
    Util.Log("[slide] crouch button keys: %s", #keys > 0 and table.concat(keys, ", ") or "none found")
    return keys
end

local function crouchButtonHeld()
    local pc = Player.GetController()
    if not pc or not crouchKeys then return false end
    for _, k in ipairs(crouchKeys) do
        local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and down then return true end
    end
    return false
end

-- Stands up the way the crouch button does; under an obstacle the game keeps
-- the player crouched.
local function standUp(mc)
    call(mc, "StopButtonCrouch")
    call(mc, "TryUncrouch")
    if readBool(mc, "bWantsToCrouch") and not readBool(mc, "bIsCrouchingUnderObstacle") then
        call(mc, "UnCrouch")
    end
end

local function stopSlide(mc, reason)
    sliding = false
    cooldown = cfg.CooldownMs
    Haptics.SetContinuous(Haptics.LEFT, "slide", 0)
    Haptics.SetContinuous(Haptics.RIGHT, "slide", 0)
    local stand = false
    if mc and readBool(mc, "bButtonCrouch") and not pressedDuringSlide then
        if byButton then
            stand = not crouchButtonHeld()
        else
            stand = weCrouched
        end
        if stand then standUp(mc) end
    end
    weCrouched = false
    -- Sprint state goes back to the player's input; when staying crouched the
    -- crouch lock takes over at once (a real sprint would stand up)
    if mc and readBool(mc, "bButtonCrouch") and cfg.NoSprintWhileCrouched then
        locked = true
    elseif mc then
        holdSprint(mc, false)
    end
    Util.DLog("[slide] end (%s) after %.0f ms, %s", reason, slideT, stand and "standing up" or "staying crouched")
end

local function startSlide(mc, speed, h, peak, button)
    sliding = true
    byButton = button
    pressedDuringSlide = false
    slideT = 0
    blockedMs, airMs = 0, 0
    dirX, dirY = velX / speed, velY / speed
    startSpeed = math.min(speed * cfg.SpeedBoost, cfg.MaxSpeed)
    crouchFrom = nil
    -- Head slide: crouch at the game's crouch height
    weCrouched = false
    if not button and not readBool(mc, "bButtonCrouch") then
        call(mc, "StartButtonCrouch")
        weCrouched = true
    end
    Util.DLog("[slide] start (%s): speed=%.0f -> %.0f cm/s dir=(%.2f,%.2f) head %.0f -> %.0f cm",
        button and "button" or "head", speed, startSpeed, dirX, dirY, peak, h)
    if cfg.HapticAmplitude > 0 then
        Haptics.Pulse(Haptics.LEFT, cfg.HapticAmplitude, 120, 0, 0.3)
        Haptics.Pulse(Haptics.RIGHT, cfg.HapticAmplitude, 120, 0, 0.3)
    end
end

-- The game crouches by easing its "Crouch Height" variable from ~90 down to
-- ButtonCrouchHeight (~50) in ~870 ms, which lowers the whole player. During
-- a slide it is driven down faster: the full crouch takes CrouchDownMs.
local crouchFrom = nil
local function fastCrouch(mc, dtMs)
    if cfg.CrouchDownMs <= 0 or not readBool(mc, "bButtonCrouch") then return end
    local cur, target = readNum(mc, "Crouch Height"), readNum(mc, "ButtonCrouchHeight")
    if not cur or not target or cur <= target + 0.05 then return end
    crouchFrom = crouchFrom or cur
    local rate = math.max(crouchFrom - target, 1) / cfg.CrouchDownMs   -- cm per ms
    write(mc, "Crouch Height", math.max(target, cur - rate * dtMs))
end

-- Keeps one short override thruster alive with the current slide speed.
local function thrust(mc, speed)
    if cfg.KeepSprintLines then holdSprint(mc, true) end
    local active = call(mc, "HasActiveOverrideThrusters")
    if active then return end
    local ok, err = pcall(function()
        mc:AddLinearThruster({
            bIsAdditiveThruster = false,
            Duration = cfg.ThrusterStepMs / 1000,
            Direction = { X = dirX, Y = dirY, Z = 0.0 },
            Strength = speed,
        })
    end)
    if not ok then
        Util.Log("[slide] AddLinearThruster failed: %s", tostring(err))
        sliding = false
    end
end

-- A crouch button press is the first IA_Crouch event after a quiet gap: the
-- event functions do not tell Started/Triggered/Completed apart, and
-- Triggered repeats every frame while the button is held.
local function onCrouchEvent(name)
    if clock - lastButtonEvent > 0.25 then
        buttonPressAt = clock
        if sliding then pressedDuringSlide = true end
        Util.DLog("[slide] crouch button (%s)", name)
    end
    lastButtonEvent = clock
end

local function hookFunction(func)
    local ok, full = pcall(function() return func:GetFullName() end)
    if not ok or not full then return end
    local path = full:gsub("^%S+%s+", "")   -- strip the "Function " class prefix
    if hooked[path] then return end
    hooked[path] = true
    local name = path:match(":([^:]+)$") or path
    local okHook, err = pcall(function()
        RegisterHook(path, function() Util.SafeCall(onCrouchEvent, name) end)
    end)
    Util.Log("[slide] crouch button hook %s: %s", okHook and "OK" or "FAILED", okHook and path or tostring(err))
end

local function isCrouchEvent(func)
    local ok, n = pcall(function() return func:GetFName():ToString() end)
    return ok and type(n) == "string" and n:find("IA_Crouch", 1, true) ~= nil and n:find("InpActEvt", 1, true) ~= nil
end

-- Searches the functions of a class and its parents.
local function searchClass(cls, seen)
    local depth = 0
    while Util.IsValid(cls) and depth < 12 do
        local key = Util.Key(cls)
        if seen[key] then return end
        seen[key] = true
        pcall(function()
            cls:ForEachFunction(function(func)
                if isCrouchEvent(func) then hookFunction(func) end
            end)
        end)
        local ok, super = pcall(function() return cls:GetSuperStruct() end)
        cls = ok and super or nil
        depth = depth + 1
    end
end

local function hookCount()
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    return n
end

local function findCrouchHooks(pawn, mc)
    local seen = {}
    for _, obj in ipairs({ pawn, mc, Player.GetController() }) do
        local ok, cls = pcall(function() return obj:GetClass() end)
        if ok then searchClass(cls, seen) end
    end
    if hookCount() == 0 and not fullSearchDone then
        -- Not on the pawn/controller: scan every function once (one hitch)
        fullSearchDone = true
        Util.DLog("[slide] IA_Crouch events not on the pawn; scanning all functions")
        for _, func in ipairs(FindAllOf("Function") or {}) do
            if isCrouchEvent(func) then hookFunction(func) end
        end
    end
    if hookCount() == 0 then
        Util.Log("[slide] IA_Crouch input events not found yet (crouch button slide unavailable)")
    end
    crouchKeys = findCrouchKeys()
end

function Slide.Tick(dtMs)
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if not mc then
        -- Level change or death: drop any slide in progress
        if sliding then stopSlide(nil, "pawn lost") end
        sprintHeld, locked = false, false
        lastPos = nil
        return
    end

    local dt = dtMs / 1000
    clock = clock + dt
    if cooldown > 0 then cooldown = cooldown - dtMs end

    local key = Util.Key(pawn)
    if key ~= hookSearchKey then
        -- New pawn (level change, respawn): forget the old body measurements
        standRef, history, physCrouched, lastPos = nil, {}, false, nil
    end
    if cfg.Trigger ~= "head" then
        hookRetryMs = hookRetryMs - dtMs
        if key ~= hookSearchKey or (hookCount() == 0 and hookRetryMs <= 0) then
            hookRetryMs = 5000
            findCrouchHooks(pawn, mc)
        end
    end
    hookSearchKey = key

    -- Horizontal velocity from the actor's motion (smoothed)
    local ok, pos = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok or not pos then return end
    if lastPos and dt > 0 then
        local dx, dy, dz = pos.X - lastPos.X, pos.Y - lastPos.Y, pos.Z - lastPos.Z
        if dx * dx + dy * dy + dz * dz > TELEPORT_CM * TELEPORT_CM then
            -- Teleport / respawn / level streaming: not a real movement
            teleportAt = clock
            velX, velY = 0, 0
            history = {}
        else
            local vx, vy = dx / dt, dy / dt
            local a = Util.Clamp(dt / 0.06, 0, 1)
            velX, velY = velX + (vx - velX) * a, velY + (vy - velY) * a
        end
    end
    lastPos = { X = pos.X, Y = pos.Y, Z = pos.Z }
    local speed = math.sqrt(velX * velX + velY * velY)

    local h = headHeight(pawn, mc)
    if not h then return end
    local onGround = readBool(mc, "bOnGround")
    local buttonCrouch = readBool(mc, "bButtonCrouch")
    if buttonCrouch ~= lastButtonCrouch then
        lastButtonCrouch = buttonCrouch
        buttonCrouchChangedAt = clock
    end
    -- While the game crouches or stands up, the head height is not the
    -- player's real one: ignore it for a moment.
    if onGround == false then lastAirAt = clock end
    local landing = clock - lastAirAt <= cfg.LandSettleMs / 1000
    if Util.Debug then
        -- Size of the landing dip (helps tune LandSettleMs)
        if landing and onGround then
            landMinH = math.min(landMinH or h, h)
        elseif not landing and landMinH then
            Util.DLog("[slide] landing settled: head dipped to %.0f cm (stand %.0f), ignored for %d ms",
                landMinH, standRef or h, cfg.LandSettleMs)
            landMinH = nil
        end
    end
    local heightSettled = not buttonCrouch and clock - buttonCrouchChangedAt > cfg.CrouchSettleMs / 1000
        and clock - teleportAt > 1.0 and not landing
    local stand = standRef or h
    if heightSettled and onGround then stand = standingHeight(h, dt) end
    if heightSettled then
        if physCrouched then
            physCrouched = h < stand - cfg.CrouchDropCm * 0.6
        else
            physCrouched = h < stand - cfg.CrouchDropCm
        end
    end

    local sprinting = readBool(mc, "bIsSprinting") and not sprintHeld
    if sprinting and not sliding then lastSprintAt = clock end

    if Util.Debug then
        logAcc = logAcc + dtMs
        if logAcc >= 1000 and (sprinting or sliding or locked) then
            logAcc = 0
            Util.DLog("[slide] sprint=%s locked=%s ground=%s buttonCrouch=%s phys=%s speed=%.0f head=%.0f stand=%.0f",
                tostring(sprinting), tostring(locked), tostring(onGround), tostring(buttonCrouch),
                tostring(physCrouched), speed, h, stand)
        end
    end

    if sliding then
        slideT = slideT + dtMs
        local target = speedAt(slideT)
        -- Hit a wall: actual speed far below the commanded one
        if slideT > 150 and speed < target * 0.3 then blockedMs = blockedMs + dtMs else blockedMs = 0 end
        if not onGround then airMs = airMs + dtMs else airMs = 0 end
        if slideT >= cfg.DurationMs then
            stopSlide(mc, "done")
        elseif blockedMs >= 120 then
            stopSlide(mc, "blocked")
        elseif airMs >= 100 then
            stopSlide(mc, "airborne")
        else
            thrust(mc, target)
            fastCrouch(mc, dtMs)
            -- Light rumble of the ground, fading with the speed
            local amp = cfg.HapticAmplitude * 0.5 * target / math.max(startSpeed, 1)
            Haptics.SetContinuous(Haptics.LEFT, "slide", amp, 0.2)
            Haptics.SetContinuous(Haptics.RIGHT, "slide", amp, 0.2)
        end
        pushHistory(h)
        return
    end

    local peak = peakHeight()
    if heightSettled then pushHistory(h) else history = {} end
    local pressed = buttonPressAt ~= nil and clock - buttonPressAt <= 0.15
    if not pressed then buttonPressAt = nil end

    -- Slide: sprinting (the game may end the sprint as soon as it crouches,
    -- so allow a short grace) and a crouch button press or a quick duck.
    local wasSprinting = clock - lastSprintAt <= 0.2
    if cooldown <= 0 and wasSprinting and onGround and speed >= cfg.MinSpeed then
        local button = pressed and cfg.Trigger ~= "head"
        local ducked = heightSettled and peak ~= nil and peak - h >= cfg.CrouchDropCm and cfg.Trigger ~= "button"
        if button or ducked then
            buttonPressAt = nil
            if locked then locked = false end
            startSlide(mc, speed, h, peak or h, button and not ducked)
            thrust(mc, speedAt(0))
            return
        end
    end

    -- No sprint while crouched
    local wantLock = cfg.NoSprintWhileCrouched and (buttonCrouch or physCrouched)
    if wantLock ~= locked then
        locked = wantLock
        Util.DLog("[slide] sprint %s (%s)", locked and "locked" or "unlocked",
            buttonCrouch and "button crouch" or (physCrouched and "physical crouch" or "standing"))
    end
    holdSprint(mc, locked, true)
end

-- True while the slide owns the sprint state (sliding, or bIsSprinting held
-- for the sprint lines / crouch lock): nobody else may start or stop a sprint.
function Slide.HoldsSprint()
    return sliding or sprintHeld
end

-- Tweaks turned off (F7): give everything back to the game and start clean
-- when they are turned on again.
function Slide.Stop()
    local pawn = Player.GetPawn()
    local mc = pawn and movement(pawn)
    if sliding then stopSlide(mc, "disabled") end
    if mc then holdSprint(mc, false) end
    sprintHeld, locked, physCrouched = false, false, false
    standRef, history, lastPos, buttonPressAt = nil, {}, nil, nil
    velX, velY = 0, 0
end

function Slide.Init(config)
    cfg = config
    cfg.Trigger = cfg.Trigger or "both"
    cfg.CrouchDropCm = cfg.CrouchDropCm or 25
    cfg.CrouchWindowMs = cfg.CrouchWindowMs or 250
    cfg.CrouchSettleMs = cfg.CrouchSettleMs or 1000
    cfg.LandSettleMs = cfg.LandSettleMs or 500
    cfg.MinSpeed = cfg.MinSpeed or 250
    cfg.SpeedBoost = cfg.SpeedBoost or 1.6
    cfg.MaxSpeed = cfg.MaxSpeed or 1600
    cfg.DurationMs = cfg.DurationMs or 1400
    cfg.EndSpeedFactor = cfg.EndSpeedFactor or 0.4
    cfg.CooldownMs = cfg.CooldownMs or 600
    cfg.ThrusterStepMs = cfg.ThrusterStepMs or 30
    cfg.HapticAmplitude = cfg.HapticAmplitude or 0.3
    cfg.CrouchDownMs = cfg.CrouchDownMs or 300
    if cfg.KeepSprintLines == nil then cfg.KeepSprintLines = true end
    if cfg.NoSprintWhileCrouched == nil then cfg.NoSprintWhileCrouched = true end
    Util.Log("Slide enabled (trigger=%s, drop=%.0f cm in %d ms, min speed=%.0f cm/s, %d ms)",
        cfg.Trigger, cfg.CrouchDropCm, cfg.CrouchWindowMs, cfg.MinSpeed, cfg.DurationMs)
end

return Slide
