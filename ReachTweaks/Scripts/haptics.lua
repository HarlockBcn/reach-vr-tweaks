-- Per-hand vibration mixer.
-- Every tick the continuous layers (e.g. bow tension) are combined with the
-- active pulses and the result is sent with APlayerController::SetHapticsByValue.
-- On OpenXR each call lasts very briefly, so it must be refreshed every tick.
local Util = require("util")

local Haptics = {}

-- EControllerHand
Haptics.LEFT = 0
Haptics.RIGHT = 1

local continuous = { [0] = {}, [1] = {} }   -- [hand][layer] = {amp, freq}
local pulses = { [0] = {}, [1] = {} }       -- list of {amp0, amp1, freq, t, dur}
local wasActive = { [0] = false, [1] = false }

-- With the mod disabled (F7) vibrations are ignored unless forced.
Haptics.Muted = false

function Haptics.Other(hand)
    return hand == Haptics.LEFT and Haptics.RIGHT or Haptics.LEFT
end

-- Continuous layer: kept until set to 0/nil.
function Haptics.SetContinuous(hand, layer, amp, freq)
    if hand == nil then return end
    if Haptics.Muted then amp = 0 end
    if amp == nil or amp <= 0 then
        continuous[hand][layer] = nil
    else
        continuous[hand][layer] = { amp = Util.Clamp(amp, 0, 1), freq = freq or 0.5 }
    end
end

-- Pulse: linear amplitude from ampStart to ampEnd over durMs.
function Haptics.Pulse(hand, ampStart, durMs, ampEnd, freq, force)
    if hand == nil or ampStart <= 0 then return end
    if Haptics.Muted and not force then return end
    table.insert(pulses[hand], {
        a0 = Util.Clamp(ampStart, 0, 1),
        a1 = Util.Clamp(ampEnd or 0, 0, 1),
        freq = freq or 1.0,
        t = 0,
        dur = math.max(durMs, 1),
    })
end

function Haptics.StopAll()
    for h = 0, 1 do
        continuous[h] = {}
        pulses[h] = {}
    end
end

-- Call on the game thread every tick.
function Haptics.Tick(dtMs, pc)
    for hand = 0, 1 do
        local amp, freq = 0, 0.5

        for _, c in pairs(continuous[hand]) do
            if c.amp > amp then amp, freq = c.amp, c.freq end
        end

        local list = pulses[hand]
        for i = #list, 1, -1 do
            local p = list[i]
            local k = p.t / p.dur
            local a = p.a0 + (p.a1 - p.a0) * k
            -- pulses add on top of continuous layers so they are felt over the tension
            if a > 0 then
                amp = math.max(amp, math.min(1, a + amp * 0.5))
                freq = p.freq
            end
            p.t = p.t + dtMs
            if p.t >= p.dur then table.remove(list, i) end
        end

        if amp > 0.001 then
            Util.SafeCall(function() pc:SetHapticsByValue(freq, amp, hand) end)
            wasActive[hand] = true
        elseif wasActive[hand] then
            Util.SafeCall(function() pc:SetHapticsByValue(0.0, 0.0, hand) end)
            wasActive[hand] = false
        end
    end
end

return Haptics
