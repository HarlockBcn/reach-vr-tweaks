-- Tracks the player and what each hand is holding.
local Util = require("util")
local Haptics = require("haptics")

local Player = {}

local PAWN_CLASS = "/Script/Atlas.AtlasPawn"

local pc = nil
local held = { [0] = nil, [1] = nil }   -- actor held by each hand

local searchCooldown = 0

function Player.GetController()
    if Util.IsValid(pc) then return pc end
    pc = nil
    -- FindAllOf is expensive: search at most ~6 times per second
    if searchCooldown > 0 then
        searchCooldown = searchCooldown - 1
        return nil
    end
    searchCooldown = 10
    local candidates = FindAllOf("PlayerController") or {}
    for _, c in ipairs(candidates) do
        if Util.IsValid(c) then
            local ok, local_ = pcall(function() return c:IsLocalController() end)
            if not ok or local_ then
                pc = c
                Util.Log("PlayerController: %s", c:GetFullName())
                break
            end
        end
    end
    return pc
end

-- Always read from the controller: the pawn changes with every level and
-- death, and keeping the reference could leave it dangling.
function Player.GetPawn()
    local c = Player.GetController()
    if c then
        local p = Util.Prop(c, "Pawn")
        if p and Util.IsA(p, PAWN_CLASS) then return p end
    end
    return nil
end

local function handCoupler(hand)
    local p = Player.GetPawn()
    if not p then return nil end
    return Util.Prop(p, hand == Haptics.LEFT and "HandCouplerLeftReference" or "HandCouplerRightReference")
end

-- Returns the root actor the hand is coupled to (or nil).
local function queryHeld(hand)
    local coupler = handCoupler(hand)
    if not coupler then return nil end
    local partners = {}
    local ok, arr = pcall(function() return coupler:GetPartners() end)
    if ok then partners = Util.ArrayToTable(arr) end
    if #partners == 0 then
        local ok2, arr2 = pcall(function() return coupler.CurrentPartners end)
        if ok2 then partners = Util.ArrayToTable(arr2) end
    end
    for _, partner in ipairs(partners) do
        local owner = Util.GetOwner(partner)
        if owner then return owner end
    end
    return nil
end

function Player.Refresh()
    for hand = 0, 1 do
        held[hand] = queryHeld(hand)
    end
end

function Player.Held(hand)
    local a = held[hand]
    if Util.IsValid(a) then return a end
    held[hand] = nil
    return nil
end

-- Hand(s) holding a given actor.
function Player.HandsHolding(actor)
    local res = {}
    for hand = 0, 1 do
        if Util.SameObject(Player.Held(hand), actor) then res[#res + 1] = hand end
    end
    return res
end

-- Hand holding something of one of the given classes.
function Player.HandHoldingClass(classPaths)
    for hand = 1, 0, -1 do  -- right hand first
        local a = Player.Held(hand)
        if a then
            for _, cp in ipairs(classPaths) do
                if Util.IsA(a, cp) then return hand, a end
            end
        end
    end
    return nil, nil
end

-- Hand a coupler belongs to (if it is a player hand).
function Player.HandOfCoupler(coupler)
    for hand = 0, 1 do
        if Util.SameObject(handCoupler(hand), coupler) then return hand end
    end
    return nil
end

function Player.Init()
    -- Immediate update when a hand grabs or releases something.
    local function hook(fn, hand)
        Util.SafeCall(function()
            RegisterHook(PAWN_CLASS .. ":" .. fn, function()
                held[hand] = queryHeld(hand)
                Util.DLog("%s -> %s", fn, held[hand] and held[hand]:GetFullName() or "nothing")
            end)
        end)
    end
    hook("OnLeftHandCoupled", Haptics.LEFT)
    hook("OnLeftHandDecoupled", Haptics.LEFT)
    hook("OnRightHandCoupled", Haptics.RIGHT)
    hook("OnRightHandDecoupled", Haptics.RIGHT)
end

return Player
