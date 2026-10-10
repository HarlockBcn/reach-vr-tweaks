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

local function newStats()
    return { vmax = 0, chMin = 1e9, chMax = 0, chSum = 0, hgMin = 1e9, hgMax = 0, n = 0, held = "nothing",
             wMin = 1e9, wMax = -1e9, owMin = 1e9, stepMax = 0, mn = 0 }
end

-- Resolver that moves a held object (bow: BowResolverRef, guns: AtlasGunResolver)
local function motionResolver(actor)
    local r = Util.Prop(actor, "BowResolverRef")
    if r then return r end
    return Util.FindOwnedBy(actor, { "AtlasGunResolver", "AtlasThrowableResolver" })[1]
end

-- Samples the resolver motion of this tick: Weighting is the TLerp alpha used by
-- UNDNTResolverBasic::ApplyMotionModifications (< 1 means the object only
-- covers part of the way to its target each frame).
local function sampleMotion(st, actor)
    local r = motionResolver(actor)
    if not r then return end
    local ok, m = pcall(function() return r:GetMotionThisTick() end)
    if not ok or m == nil then return end
    pcall(function()
        local w, ow = m.Weighting, m.OutgoingMotionWeight
        local f, t = m.From.Translation, m.To.Translation
        local step = dist({ X = f.X, Y = f.Y, Z = f.Z }, { X = t.X, Y = t.Y, Z = t.Z })
        st.wMin = math.min(st.wMin, w)
        st.wMax = math.max(st.wMax, w)
        st.owMin = math.min(st.owMin, ow)
        st.stepMax = math.max(st.stepMax, step)
        st.mn = st.mn + 1
    end)
end

local couplerLogged = false
local function logHandCouplers(pawn)
    if couplerLogged then return end
    couplerLogged = true
    for _, side in ipairs({ "Left", "Right" }) do
        local c = Util.Prop(pawn, "HandCoupler" .. side .. "Reference")
        if c then
            local parts = {}
            for _, prop in ipairs({ "OutgoingMotionWeight", "ResolverSiblingWeighting", "MatchScoreMultiplier",
                                    "bSmoothHandCoupling", "CouplingBias" }) do
                local okp, v = pcall(function() return c[prop] end)
                if okp and (type(v) == "number" or type(v) == "boolean") then parts[#parts + 1] = prop .. "=" .. tostring(v) end
            end
            Util.Log("[lag] hand coupler %s: %s | %s", side, c:GetFullName(), table.concat(parts, " "))
        end
    end
end

function Probe.Tick(dtMs)
    local pawn = Player.GetPawn()
    if not pawn then return end
    logHandCouplers(pawn)
    for hand = 0, 1 do
        local mc = Player.MotionController(hand)
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
                sampleMotion(st, a)
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
                if st.mn > 0 then
                    Util.Log("[lag]   motion: Weighting[%.3f..%.3f] OutgoingMotionWeight min %.3f, max step %.1f cm",
                        st.wMin, st.wMax, st.owMin, st.stepMax)
                end
            end
            stats[hand] = nil
        end
    end
end

return Probe
