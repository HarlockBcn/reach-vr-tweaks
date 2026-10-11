-- ReachTweaks: agile hands with weapons, better bow and firearm haptics, sprint slide, arm-swing sprint, sprint speed, sprint through jumps, grapple only in view, shield throw speed, save time in the save list.
local VERSION = "1.13.0"

local Util = require("util")

local function modRoot()
    if not debug or not debug.getinfo then return "." end
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$") or "."
end

-- The game's working directory is Binaries\Win64
-- Two copies of config.lua can be edited: the installed one (game folder) and
-- the package one (path written by the launcher in package_config.txt). On
-- load the copy whose text changed since the last read wins (package first),
-- so a reload (F7) picks up whichever file was just edited.
local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

local function configPaths()
    local paths = {}
    local pkg = readFile(modRoot() .. "\\package_config.txt")
    if pkg then
        pkg = pkg:gsub("^%s+", ""):gsub("%s+$", "")
        if pkg ~= "" then paths[#paths + 1] = pkg end
    end
    for _, p in ipairs({ modRoot() .. "\\config.lua",
                         "ue4ss\\Mods\\ReachTweaks\\config.lua",
                         "Mods\\ReachTweaks\\config.lua" }) do
        paths[#paths + 1] = p
    end
    return paths
end

local lastText = {}      -- path -> text read last time
local configPath = nil   -- copy in use

local function loadConfig()
    local texts, changed = {}, nil
    for _, path in ipairs(configPaths()) do
        local text = readFile(path)
        if text then
            texts[#texts + 1] = { path = path, text = text }
            if changed == nil and lastText[path] ~= nil and lastText[path] ~= text then changed = #texts end
        end
    end
    if #texts == 0 then return nil, "config.lua not found" end
    -- Changed copy first; otherwise the one in use; otherwise the first found
    local order = {}
    if changed then order[#order + 1] = texts[changed] end
    for _, t in ipairs(texts) do
        if t.path == configPath then order[#order + 1] = t end
    end
    for _, t in ipairs(texts) do order[#order + 1] = t end
    local err
    for _, t in ipairs(order) do
        local chunk, cerr = load(t.text, "@" .. t.path, "t")
        local ok, cfg = false, cerr
        if chunk then ok, cfg = pcall(chunk) end
        if ok and type(cfg) == "table" then
            for _, x in ipairs(texts) do lastText[x.path] = x.text end
            configPath = t.path
            return cfg
        end
        err = cfg
        -- The copy just edited is broken: report it instead of silently
        -- falling back to the old values
        if changed and t == texts[changed] then return nil, err end
    end
    return nil, err
end

local config, cfgErr = loadConfig()
if config == nil then
    Util.Log("Could not read config.lua (%s). Using defaults.", tostring(cfgErr))
    config = { Hands = { Enabled = true, WeightStiffnessMultiplier = 10.0, WeightDamping = 1.0, Scope = "weapons" },
               Bow = { Enabled = false }, Guns = { Enabled = false } }
end
Util.Debug = config.Debug == true
if Util.Debug then Util.OpenLog(modRoot() .. "/ReachTweaks.log") end
Util.Log("Config: %s", tostring(configPath))

local Haptics = require("haptics")
local Player = require("player")
local Hands = require("hands")
local Bow = require("bow")
local BowBody = require("bowbody")
local Guns = require("guns")
local Diag = require("diag")
local Intro = require("intro")
local Spawner = require("spawner")
local Notify = require("notify")
local LagProbe = require("lagprobe")
local Slide = require("slide")
local ArmSprint = require("armsprint")
local Sprint = require("sprint")
local JumpSprint = require("jumpsprint")
local Grapple = require("grapple")
local Shield = require("shield")
local SaveTime = require("savetime")
local Keys = require("keys")

Player.Init()
if config.Hands.Enabled then Hands.Init(config.Hands) end
if config.Bow.Enabled then Bow.Init(config.Bow) end
local bowBodyOn = config.BowBody ~= nil and config.BowBody.Enabled == true
if bowBodyOn then BowBody.Init(config.BowBody) end
if config.Guns.Enabled then Guns.Init(config.Guns) end
local slideOn = config.Slide ~= nil and config.Slide.Enabled == true
if slideOn then Slide.Init(config.Slide) end
local armSprintOn = config.ArmSprint ~= nil and config.ArmSprint.Enabled == true
if armSprintOn then ArmSprint.Init(config.ArmSprint) end
local sprintOn = config.Sprint ~= nil and config.Sprint.Enabled == true
if sprintOn then Sprint.Init(config.Sprint) end
local jumpSprintOn = config.JumpSprint ~= nil and config.JumpSprint.Enabled == true
if jumpSprintOn then JumpSprint.Init(config.JumpSprint) end
local grappleOn = config.GrappleView ~= nil and config.GrappleView.Enabled == true
if grappleOn then Grapple.Init(config.GrappleView) end
local shieldOn = config.Shield ~= nil and config.Shield.Enabled == true
if shieldOn then Shield.Init(config.Shield) end
local saveTimeOn = config.SaveTime ~= nil and config.SaveTime.Enabled == true
if saveTimeOn then SaveTime.Init(config.SaveTime) end
Intro.Init(config.Intro or {})
local Experiments = nil
if config.TestGuns then
    Spawner.Init()
    Experiments = require("experiments")
    Experiments.Init()
    -- Experiments run on top of the original game: put the hand tweaks aside
    Experiments.BeforeChange = function()
        if config.Hands.Enabled then Hands.RestoreAll() end
    end
end
local function experimenting() return Experiments ~= nil and Experiments.Active() end

-- Re-reads config.lua and copies the new values into the tables the modules
-- already use (they keep a reference to their section). Enabling/disabling a
-- module or Debug still needs a game restart.
local function reloadConfig()
    local new, err = loadConfig()
    if new == nil then
        Util.Log("Config reload failed (%s); keeping the current values", tostring(err))
        return false
    end
    for section, values in pairs(new) do
        local cur = config[section]
        if type(values) == "table" and type(cur) == "table" then
            for k, v in pairs(values) do
                if k ~= "Enabled" then cur[k] = v end
            end
        elseif type(values) ~= "table" and section ~= "Debug" and section ~= "TestGuns" then
            config[section] = values
        end
    end
    if slideOn then Slide.Init(config.Slide) end
    if armSprintOn then ArmSprint.Init(config.ArmSprint) end
    if sprintOn then Sprint.Init(config.Sprint) end
    if jumpSprintOn then JumpSprint.Init(config.JumpSprint) end
    if grappleOn then Grapple.Init(config.GrappleView) end
    if shieldOn then Shield.Init(config.Shield) end
    Util.Log("Config reloaded from %s", tostring(configPath))
    return true
end

-- F7: toggle the tweaks at runtime (to compare with the original game).
-- Turning them back on re-reads config.lua, so it can be edited in game.
local active = true

local function setActive(on)
    active = on
    Haptics.StopAll()
    Haptics.Muted = not on
    if on then
        local reloaded = reloadConfig()
        Notify.Show(reloaded and "ReachTweaks: ON (config reloaded)" or "ReachTweaks: ON (config error!)",
            reloaded and { R = 80, G = 255, B = 120 } or { R = 255, G = 200, B = 60 })
        -- two short taps
        for h = 0, 1 do Haptics.Pulse(h, 0.6, 60, 0.6, 1.0, true) end
        Util.After(150, function()
            for h = 0, 1 do Haptics.Pulse(h, 0.6, 60, 0.6, 1.0, true) end
        end)
    else
        if config.Hands.Enabled then Util.SafeCall(Hands.RestoreAll) end
        if Experiments then Util.SafeCall(Experiments.RestoreAll) end
        if config.Guns.Enabled then Util.SafeCall(Guns.RestoreNative) end
        if armSprintOn then Util.SafeCall(ArmSprint.Stop) end
        if sprintOn then Util.SafeCall(Sprint.Stop) end
        if jumpSprintOn then Util.SafeCall(JumpSprint.Stop) end
        if slideOn then Util.SafeCall(Slide.Stop) end
        if grappleOn then Util.SafeCall(Grapple.Stop) end
        if shieldOn then Util.SafeCall(Shield.Stop) end
        if saveTimeOn then Util.SafeCall(SaveTime.Stop) end
        Notify.Show("ReachTweaks: OFF", { R = 255, G = 90, B = 80 })
        -- one long buzz
        for h = 0, 1 do Haptics.Pulse(h, 0.6, 350, 0.6, 0.3, true) end
    end
    Util.Log("Tweaks %s", on and "ENABLED" or "DISABLED")
end

Keys.Bind("F7", function() setActive(not active) end)

-- Real time between ticks (ms) from the engine clock.
local statics = nil
local lastRealTime = nil
local function realDeltaMs(pc)
    if not Util.IsValid(statics) then statics = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    local ok, t = pcall(function() return statics:GetRealTimeSeconds(pc) end)
    if not ok or type(t) ~= "number" then return 16 end
    local dt = lastRealTime and (t - lastRealTime) * 1000 or 16
    lastRealTime = t
    return Util.Clamp(dt, 1, 100)
end

local slowAcc, dataAcc, diagAcc = 0, 0, 0
local tickCount, rateAcc = 0, 0

-- Traces the first 3 runs of each step (helps locate crashes).
local traced = {}
local function step(name, fn, ...)
    local n = traced[name] or 0
    if Util.Debug and n < 3 then
        traced[name] = n + 1
        Util.Log("-> %s", name)
        Util.SafeCall(fn, ...)
        Util.Log("<- %s", name)
    else
        Util.SafeCall(fn, ...)
    end
end

local function tick()
    local pc = Player.GetController()
    if not pc then
        Util.RunTimers(11)
        return
    end
    local dt = realDeltaMs(pc)
    Util.RunTimers(dt)
    Keys.Tick(pc)

    slowAcc = slowAcc + dt
    dataAcc = dataAcc + dt
    diagAcc = diagAcc + dt

    -- Actual loop rate (haptics need a smooth update)
    tickCount = tickCount + 1
    rateAcc = rateAcc + dt
    if rateAcc >= 10000 then
        Util.DLog("Loop: %.0f ticks/s", tickCount * 1000 / rateAcc)
        tickCount, rateAcc = 0, 0
    end

    step("Intro.Tick", Intro.Tick, pc)
    step("Player.Refresh", Player.Refresh)
    if slowAcc >= 100 then
        slowAcc = 0
        if active and config.Hands.Enabled and not experimenting() then step("Hands.Tick", Hands.Tick) end
        if active and experimenting() then step("Experiments.Tick", Experiments.Tick) end
    end
    if dataAcc >= 2000 then
        dataAcc = 0
        if active and config.Guns.Enabled then step("Guns.ScaleNativeHaptics", Guns.ScaleNativeHaptics) end
    end
    if Util.Debug and diagAcc >= 500 then
        diagAcc = 0
        step("Diag.Tick", Diag.Tick)
    end

    if Util.Debug then step("LagProbe.Tick", LagProbe.Tick, dt) end
    if bowBodyOn then step("BowBody.Tick", BowBody.Tick, dt, active and not experimenting()) end
    if active and config.Bow.Enabled then step("Bow.Tick", Bow.Tick, dt) end
    if active and config.Guns.Enabled then step("Guns.Tick", Guns.Tick, dt) end
    if active and sprintOn then step("Sprint.Tick", Sprint.Tick) end
    -- Before the arm sprint: it must see a jump in progress in the same tick
    if active and jumpSprintOn then step("JumpSprint.Tick", JumpSprint.Tick, dt) end
    -- Arm sprint first: the slide sees a sprint it started in the same tick
    if active and armSprintOn then step("ArmSprint.Tick", ArmSprint.Tick, dt) end
    if active and slideOn then step("Slide.Tick", Slide.Tick, dt) end
    if active and grappleOn then step("Grapple.Tick", Grapple.Tick, dt) end
    if active and shieldOn then step("Shield.Tick", Shield.Tick, dt) end
    if active and saveTimeOn then step("SaveTime.Tick", SaveTime.Tick, dt) end
    step("Haptics.Tick", Haptics.Tick, dt, pc)
end

-- One tick per frame when UE4SS supports it; otherwise the closest option.
local loopKind
if type(LoopInGameThreadAfterFrames) == "function" then
    loopKind = "LoopInGameThreadAfterFrames(1)"
    LoopInGameThreadAfterFrames(1, function() Util.SafeCall(tick) end)
elseif type(LoopInGameThreadWithDelay) == "function" then
    loopKind = "LoopInGameThreadWithDelay(8)"
    LoopInGameThreadWithDelay(8, function() Util.SafeCall(tick) end)
else
    loopKind = "LoopAsync+ExecuteInGameThread"
    local pending = false
    LoopAsync(8, function()
        if not pending then
            pending = true
            ExecuteInGameThread(function()
                Util.SafeCall(tick)
                pending = false
            end)
        end
        return false
    end)
end

Util.Log("ReachTweaks %s loaded (hands=%s bow=%s bowbody=%s guns=%s slide=%s armsprint=%s sprint=%s jumpsprint=%s grapple=%s shield=%s savetime=%s debug=%s loop=%s)", VERSION,
    tostring(config.Hands.Enabled), tostring(config.Bow.Enabled), tostring(bowBodyOn),
    tostring(config.Guns.Enabled), tostring(slideOn), tostring(armSprintOn), tostring(sprintOn), tostring(jumpSprintOn), tostring(grappleOn), tostring(shieldOn), tostring(saveTimeOn), tostring(Util.Debug), loopKind)
