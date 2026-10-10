-- Messages visible in VR: floating 3D text in front of the head for a few
-- seconds (on-screen debug messages are compiled out of the shipping game).
--
-- No reference to the actor is kept across frames (if the engine destroys it,
-- using the reference crashes the game). The mod's texts are tagged with a
-- value in CustomTimeDilation and looked up again with FindAllOf.
local Util = require("util")
local Player = require("player")
local Spawner = require("spawner")

local Notify = {}

local MARK_BASE = 7.0      -- CustomTimeDilation = MARK_BASE + gen * 0.001
local gen = 0

local function markOf(actor)
    local ok, v = pcall(function() return actor.CustomTimeDilation end)
    if ok and type(v) == "number" and v >= MARK_BASE and v < MARK_BASE + 1 then
        return math.floor((v - MARK_BASE) * 1000 + 0.5)
    end
    return nil
end

-- Destroys the mod texts (all of them, or only one generation)
local function clear(onlyGen)
    for _, a in ipairs(FindAllOf("TextRenderActor") or {}) do
        if Util.IsValid(a) then
            local g = markOf(a)
            if g ~= nil and (onlyGen == nil or g == onlyGen) then
                pcall(function() a:K2_DestroyActor() end)
            end
        end
    end
end

-- color = { R=, G=, B= } in 0..255
function Notify.Show(text, color, seconds)
    local pc = Player.GetController()
    if not pc then return end
    clear(nil)

    local cls = StaticFindObject("/Script/Engine.TextRenderActor")
    if not Util.IsValid(cls) then return end
    -- 70 cm ahead, at eye height, facing the player
    local actor = Spawner.SpawnInFront(cls, pc, 70, 0, 180)
    if not actor then return end

    gen = gen % 900 + 1
    local myGen = gen
    pcall(function() actor.CustomTimeDilation = MARK_BASE + myGen * 0.001 end)

    Util.SafeCall(function()
        local comp = actor.TextRender
        local ftext = FText(text)
        if not pcall(function() comp:K2_SetText(ftext) end) then comp:SetText(ftext) end
        pcall(function() comp:SetHorizontalAlignment(1) end)  -- centered
        pcall(function() comp:SetVerticalAlignment(1) end)
        pcall(function() comp:SetWorldSize(5.0) end)
        pcall(function() comp:SetTextRenderColor({ R = color.R, G = color.G, B = color.B, A = 255 }) end)
    end)
    Util.Log("Message: %s", text)

    -- On expiry it is looked up again by its tag (the old reference is never used)
    Util.After((seconds or 2.5) * 1000, function() clear(myGen) end)
end

return Notify
