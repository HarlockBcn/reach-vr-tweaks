-- Bow haptics: vibration rising with the draw, tension "clicks",
-- a buzz at full draw and a kick when the arrow is released.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local Bow = {}

local BOW_CLASS = "/Script/AtlasGameplay.AtlasBow"
local PULLABLE_CLASS = "/Script/AtlasGameplay.AtlasPullable"

local cfg
local bow = nil            -- held bow
local bowHand = nil
local stringHand = nil
local stringGrabbed = false
local pullableBowKey = nil
local prevPull = 0
local lastClick = 0
local fullDrawTime = 0
local cooldownMs = 0
local baseDist = nil

local CLICKS = { 0.25, 0.5, 0.75 }

-- Looked up every tick (object references are never kept across ticks).
local function findPullable(actor)
    local key = Util.Key(actor)
    local p = Util.FindOwnedBy(actor, { "AtlasPullable" })[1]
    if pullableBowKey ~= key then
        pullableBowKey = key
        Util.DLog("Bow: pullable %s", p and p:GetFullName() or "NOT FOUND (using distance between hands)")
    end
    return p
end

local function handLocation(hand)
    local p = Player.GetPawn()
    if not p then return nil end
    local comp = Util.Prop(p, hand == Haptics.LEFT and "HandMeshRootLeftReference" or "HandMeshRootRightReference")
    if not comp then return nil end
    local ok, v = pcall(function() return comp:K2_GetComponentLocation() end)
    if ok and v then return v end
    return nil
end

local function handDistance()
    local a, b = handLocation(Haptics.LEFT), handLocation(Haptics.RIGHT)
    if not a or not b then return nil end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function currentPull()
    local p = findPullable(bow)
    if p then
        local ok, v = pcall(function() return p:GetNormalisedPull() end)
        if ok and type(v) == "number" then return Util.Clamp(v, 0, 1) end
        ok, v = pcall(function()
            local maxP = p.MaxPull
            local minP = p.MinPull
            return (p.CurrentPull - minP) / math.max(maxP - minP, 0.001)
        end)
        if ok and type(v) == "number" then return Util.Clamp(v, 0, 1) end
    end
    -- Fallback: distance between hands since the string was grabbed (~60 cm = full draw)
    if not stringGrabbed then return 0 end
    local d = handDistance()
    if not d then return 0 end
    if baseDist == nil then baseDist = d end
    return Util.Clamp((d - baseDist) / 60.0, 0, 1)
end

local function fire(pullAtRelease)
    if cooldownMs > 0 then return end
    cooldownMs = 300
    local strength = 0.4 + 0.6 * pullAtRelease
    local amp = cfg.ReleaseAmplitude * strength
    local dur = cfg.ReleaseDurationMs
    if bowHand then Haptics.Pulse(bowHand, amp, dur, 0.1, 1.0) end
    if stringHand then Haptics.Pulse(stringHand, amp * 0.8, dur * 0.7, 0.0, 1.0) end
    Util.DLog("Bow: shot (draw %.2f)", pullAtRelease)
end

local function clearTension()
    for h = 0, 1 do Haptics.SetContinuous(h, "bow", 0) end
end

local function resolveStringHand()
    if stringHand ~= nil then return stringHand end
    if bowHand ~= nil then return Haptics.Other(bowHand) end
    return cfg.DefaultStringHand == "left" and Haptics.LEFT or Haptics.RIGHT
end

function Bow.Tick(dtMs)
    if cooldownMs > 0 then cooldownMs = cooldownMs - dtMs end

    local hand, actor = Player.HandHoldingClass({ BOW_CLASS })
    if not actor then
        if bow then clearTension() end
        bow, bowHand, stringHand, stringGrabbed, prevPull = nil, nil, nil, false, 0
        return
    end
    bow, bowHand = actor, hand

    local pull = currentPull()
    local sHand = resolveStringHand()

    -- Release: sudden drop of the draw
    if prevPull > 0.25 and pull < prevPull * 0.4 then
        fire(prevPull)
    end

    if pull > 0.02 then
        local shaped = pull ^ 1.6
        local amp = cfg.TensionMinAmplitude + (cfg.TensionMaxAmplitude - cfg.TensionMinAmplitude) * shaped
        local freq = 0.2 + 0.6 * pull
        if pull >= 0.97 then
            fullDrawTime = fullDrawTime + dtMs
            -- buzz with a slight ripple so the wood "creaks"
            local wobble = 0.85 + 0.15 * math.sin(fullDrawTime / 40.0)
            amp = math.max(amp, cfg.FullDrawAmplitude * wobble)
            freq = 0.9
        else
            fullDrawTime = 0
        end
        Haptics.SetContinuous(sHand, "bow", amp, freq)
        Haptics.SetContinuous(bowHand, "bow", amp * cfg.BowHandFactor, freq)

        -- Clicks when crossing thresholds upwards
        for i, t in ipairs(CLICKS) do
            if prevPull < t and pull >= t and lastClick < i then
                Haptics.Pulse(sHand, cfg.ClickAmplitude, 25, 0.2, 1.0)
                lastClick = i
            end
        end
    else
        clearTension()
        lastClick = 0
        fullDrawTime = 0
    end
    if pull < 0.1 then lastClick = 0 end

    prevPull = pull
end

function Bow.Init(config)
    cfg = config
    local function hook(fn, cb)
        Util.SafeCall(function() RegisterHook(BOW_CLASS .. ":" .. fn, cb) end)
    end
    hook("OnBowStringGrabbed", function(self, coupler, other)
        stringGrabbed = true
        baseDist = nil
        local o = other and other:get()
        local h = o and Player.HandOfCoupler(o)
        if h ~= nil then stringHand = h end
        if stringHand ~= nil then Haptics.Pulse(stringHand, 0.35, 30, 0.0, 0.6) end
        Util.DLog("Bow: string grabbed (hand %s)", tostring(stringHand))
    end)
    hook("OnBowStringReleased", function()
        if stringGrabbed and prevPull > 0.25 then fire(prevPull) end
        stringGrabbed = false
        baseDist = nil
    end)
    hook("BP_OnArrowNocked", function()
        local h = resolveStringHand()
        Haptics.Pulse(h, 0.45, 35, 0.0, 0.8)
        if bowHand then Haptics.Pulse(bowHand, 0.25, 30, 0.0, 0.8) end
    end)
end

return Bow
