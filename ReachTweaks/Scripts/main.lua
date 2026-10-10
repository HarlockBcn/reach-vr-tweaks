-- ReachTweaks: agile hands with weapons + better bow and firearm haptics.
local VERSION = "1.2.0"

local Util = require("util")

local function modRoot()
    if not debug or not debug.getinfo then return "." end
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$") or "."
end

-- The game's working directory is Binaries\Win64
local okCfg, config
for _, path in ipairs({ modRoot() .. "\\config.lua",
                        "ue4ss\\Mods\\ReachTweaks\\config.lua",
                        "Mods\\ReachTweaks\\config.lua" }) do
    okCfg, config = pcall(dofile, path)
    if okCfg and type(config) == "table" then break end
end
if not okCfg or type(config) ~= "table" then
    Util.Log("Could not read config.lua (%s). Using defaults.", tostring(config))
    config = { Hands = { Enabled = true, WeightStiffnessMultiplier = 10.0, WeightDamping = 1.0, Scope = "weapons" },
               Bow = { Enabled = false }, Guns = { Enabled = false } }
end
Util.Debug = config.Debug == true
if Util.Debug then Util.OpenLog(modRoot() .. "/ReachTweaks.log") end

local Haptics = require("haptics")
local Player = require("player")
local Hands = require("hands")
local Bow = require("bow")
local Guns = require("guns")
local Diag = require("diag")
local Intro = require("intro")
local Spawner = require("spawner")
local Notify = require("notify")
local LagProbe = require("lagprobe")
local TickOrder = require("tickorder")

Player.Init()
if config.Hands.Enabled then Hands.Init(config.Hands) end
if config.Bow.Enabled then Bow.Init(config.Bow) end
if config.Guns.Enabled then Guns.Init(config.Guns) end
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

-- Tick-order fix: from config, toggled at runtime with F9 (testing)
local tickOrderWanted = config.Hands.Enabled and config.Hands.TickOrderFix == true
if tickOrderWanted then TickOrder.Set(true) end
if config.TestGuns then
    Util.SafeCall(function()
        RegisterKeyBind(Key.F9, function()
            ExecuteInGameThread(function()
                tickOrderWanted = not tickOrderWanted
                Util.SafeCall(TickOrder.Set, tickOrderWanted)
                Notify.Show("Tick-order fix: " .. (tickOrderWanted and "ON" or "OFF"),
                    { R = 255, G = 210, B = 80 }, 2.5)
            end)
        end)
    end)
end

-- F7: toggle the tweaks at runtime (to compare with the original game)
local active = true

local function setActive(on)
    active = on
    Haptics.StopAll()
    Haptics.Muted = not on
    if on then
        Notify.Show("ReachTweaks: ON", { R = 80, G = 255, B = 120 })
        if tickOrderWanted then Util.SafeCall(TickOrder.Set, true) end
        -- two short taps
        for h = 0, 1 do Haptics.Pulse(h, 0.6, 60, 0.6, 1.0, true) end
        ExecuteWithDelay(150, function()
            ExecuteInGameThread(function()
                for h = 0, 1 do Haptics.Pulse(h, 0.6, 60, 0.6, 1.0, true) end
            end)
        end)
    else
        if config.Hands.Enabled then Util.SafeCall(Hands.RestoreAll) end
        if Experiments then Util.SafeCall(Experiments.RestoreAll) end
        Util.SafeCall(TickOrder.Set, false)
        if config.Guns.Enabled then Util.SafeCall(Guns.RestoreNative) end
        Notify.Show("ReachTweaks: OFF", { R = 255, G = 90, B = 80 })
        -- one long buzz
        for h = 0, 1 do Haptics.Pulse(h, 0.6, 350, 0.6, 0.3, true) end
    end
    Util.Log("Tweaks %s", on and "ENABLED" or "DISABLED")
end

Util.SafeCall(function()
    RegisterKeyBind(Key.F7, function()
        ExecuteInGameThread(function() Util.SafeCall(setActive, not active) end)
    end)
end)

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
    if not pc then return end
    local dt = realDeltaMs(pc)

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
        if active then step("TickOrder.Tick", TickOrder.Tick) end
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
    if active and config.Bow.Enabled then step("Bow.Tick", Bow.Tick, dt) end
    if active and config.Guns.Enabled then step("Guns.Tick", Guns.Tick, dt) end
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

Util.Log("ReachTweaks %s loaded (hands=%s bow=%s guns=%s debug=%s loop=%s)", VERSION,
    tostring(config.Hands.Enabled), tostring(config.Bow.Enabled),
    tostring(config.Guns.Enabled), tostring(Util.Debug), loopKind)
