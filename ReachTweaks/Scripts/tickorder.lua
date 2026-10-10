-- Tick-order fix (experimental, F9).
-- Held objects are moved by the nTeract arbiter (ANDNTConnectionArbiter::Tick ->
-- ProcessIslands). If the arbiter ticks before the motion controllers update
-- their pose, held objects use last frame's controller pose and trail the hand
-- by about one frame, while empty hands are attached straight to the controller.
-- Making the controllers a tick prerequisite of the arbiter removes that frame.
local Util = require("util")
local Player = require("player")

local TickOrder = {}

local enabled = false
local linked = {}      -- [arbiterKey .. ":" .. controllerKey] = true (keys only)

local function arbiters()
    local out = {}
    for _, a in ipairs(FindAllOf("NDNTConnectionArbiter") or {}) do
        if Util.IsValid(a) then out[#out + 1] = a end
    end
    return out
end

local function controllers()
    local pawn = Player.GetPawn()
    if not pawn then return {} end
    return Util.FindOwnedBy(pawn, { "MotionControllerComponent" })
end

-- Links every motion controller of the current pawn to every arbiter.
-- Called periodically: pawns and arbiters change with levels.
function TickOrder.Tick()
    if not enabled then return end
    for _, arb in ipairs(arbiters()) do
        for _, mc in ipairs(controllers()) do
            local k = Util.Key(arb) .. ":" .. Util.Key(mc)
            if not linked[k] then
                local ok, err = pcall(function() arb:AddTickPrerequisiteComponent(mc) end)
                linked[k] = true
                Util.Log("[tick] arbiter %s now ticks after %s (%s)", arb:GetFullName(),
                    mc:GetFullName(), ok and "ok" or tostring(err))
            end
        end
    end
end

local function unlinkAll()
    for _, arb in ipairs(arbiters()) do
        for _, mc in ipairs(controllers()) do
            if linked[Util.Key(arb) .. ":" .. Util.Key(mc)] then
                pcall(function() arb:RemoveTickPrerequisiteComponent(mc) end)
            end
        end
    end
    linked = {}
end

function TickOrder.Set(on)
    enabled = on
    if on then
        TickOrder.Tick()
    else
        unlinkAll()
    end
    Util.Log("[tick] tick-order fix %s", on and "ON" or "OFF")
end

function TickOrder.Enabled() return enabled end

return TickOrder
