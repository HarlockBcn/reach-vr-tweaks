-- Lag probe (Debug only): measures every frame the distance between the real
-- controller, the virtual hand and the weapon, and logs a summary every second
-- when there was movement. Shows which link of the chain lags.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local Probe = {}

local stats = { [0] = nil, [1] = nil }
local prev = { [0] = nil, [1] = nil }
local acc = 0

local function loc(comp)
    local ok, v = pcall(function() return comp:K2_GetComponentLocation() end)
    if ok and v then return { X = v.X, Y = v.Y, Z = v.Z } end
    return nil
end

local function actorLoc(a)
    local ok, v = pcall(function() return a:K2_GetActorLocation() end)
    if ok and v then return { X = v.X, Y = v.Y, Z = v.Z } end
    return nil
end

local function dist(a, b)
    if not a or not b then return nil end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Player motion controllers per hand, from MotionSource ("Left"/"Right")
local function controllers(pawn)
    local res = {}
    for _, mc in ipairs(Util.FindOwnedBy(pawn, { "MotionControllerComponent" })) do
        local ok, src = pcall(function() return mc.MotionSource:ToString() end)
        if ok and src then
            local s = src:lower()
            if s:find("left") then res[0] = res[0] or mc end
            if s:find("right") then res[1] = res[1] or mc end
        end
    end
    return res
end

local function newStats()
    return { vmax = 0, chMin = 1e9, chMax = 0, chSum = 0, hgMin = 1e9, hgMax = 0, n = 0, held = "nothing" }
end

function Probe.Tick(dtMs)
    local pawn = Player.GetPawn()
    if not pawn then return end
    local mcs = controllers(pawn)
    for hand = 0, 1 do
        local mc = mcs[hand]
        local mesh = Util.Prop(pawn, hand == Haptics.LEFT and "HandMeshRootLeftReference" or "HandMeshRootRightReference")
        local c, h = mc and loc(mc), mesh and loc(mesh)
        if c and h then
            local st = stats[hand] or newStats()
            stats[hand] = st
            local p = prev[hand]
            if p then
                local v = dist(c, p) / (dtMs / 1000)
                if v > st.vmax then st.vmax = v end
            end
            prev[hand] = c
            local ch = dist(c, h)
            st.chMin = math.min(st.chMin, ch)
            st.chMax = math.max(st.chMax, ch)
            st.chSum = st.chSum + ch
            st.n = st.n + 1
            local a = Player.Held(hand)
            if a then
                local hg = dist(h, actorLoc(a))
                if hg then
                    st.hgMin = math.min(st.hgMin, hg)
                    st.hgMax = math.max(st.hgMax, hg)
                end
                st.held = a:GetFullName():match("([%w_]+)_C ") or "object"
            end
        end
    end

    acc = acc + dtMs
    if acc >= 1000 then
        acc = 0
        for hand = 0, 1 do
            local st = stats[hand]
            -- only if there was noticeable movement (> 80 cm/s)
            if st and st.n > 0 and st.vmax > 80 then
                local hg = st.hgMax > 0 and string.format(" hand-weapon[%.1f..%.1f]", st.hgMin, st.hgMax) or ""
                Util.Log("[lag] %s %-22s vmax=%4.0f cm/s controller-hand[min %.1f, avg %.1f, max %.1f]%s",
                    hand == Haptics.LEFT and "L" or "R", st.held, st.vmax,
                    st.chMin, st.chSum / st.n, st.chMax, hg)
            end
            stats[hand] = nil
        end
    end
end

return Probe
