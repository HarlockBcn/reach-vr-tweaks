-- Diagnostics (Debug = true only): dumps what each hand is holding and the
-- motion parameters of its resolvers. Only writes when something changes.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local Diag = {}

local PROPS = {
    "MovementMethod", "bShouldHandlePhysics",
    "ObjectPositionHeaviness", "ObjectRotationHeaviness",
    "MinLinearVelocityForRotationHeaviness", "MaxLinearVelocityForRotationHeaviness",
    "MinAngularVelocityForRotationHeaviness", "MaxAngularVelocityForRotationHeaviness",
    "ResolverLinearStiffness", "ResolverLinearDamping",
    "ResolverAngularStiffness", "ResolverAngularDamping",
    "MagicNumber_MassKgM3", "MagicNumber_TranslationForceMultiplier", "MagicNumber_RotationDegreesPerSec",
    "LinearRecoilStiffness", "LinearRecoilDamping", "AngularRecoilStiffness", "AngularRecoilDamping",
    "WeightToAddOnFire",
    "HandCouplingSmoothingSpeed", "SmoothingHaltDistance", "MagneticClippingCoefficient", "MagneticExponent",
    "bAnchored", "bUseRecoilSprings", "RecoilRecoveryRate",
    "bSmoothHandCoupling", "OutgoingMotionWeight", "ResolverSiblingWeighting", "MatchScoreMultiplier",
    "CurrentPull", "MinPull", "MaxPull",
    "LinearStiffness", "LinearDamping", "AngularStiffness", "AngularDamping", "bEnvironmentDisablesWeight",
}
local OWNED_CLASSES = {
    "AtlasGunResolver", "AtlasThrowableResolver", "NDNTResolverBasic", "NDNTResolver", "NDNTResolverAlignment",
    "NDNTCoupler", "AtlasPullable",
}

local last = {}

local function describe(obj)
    local parts = {}
    for _, p in ipairs(PROPS) do
        local ok, v = pcall(function() return obj[p] end)
        if ok and (type(v) == "number" or type(v) == "boolean") then
            parts[#parts + 1] = string.format("%s=%s", p, type(v) == "number" and string.format("%.3f", v) or tostring(v))
        end
    end
    return table.concat(parts, " ")
end

local function report(tag, obj)
    if not Util.IsValid(obj) then return end
    local line = obj:GetFullName() .. " | " .. describe(obj)
    if last[tag] ~= line then
        last[tag] = line
        Util.Log("[diag] %s: %s", tag, line)
    end
end

function Diag.Tick()
    local pc = Player.GetController()
    if pc then
        local p = Util.Prop(pc, "Pawn")
        local n = p and p:GetFullName() or "none"
        if last.pcpawn ~= n then last.pcpawn = n; Util.Log("[diag] Controller pawn: %s", n) end
    end
    local pawn = Player.GetPawn()
    report("pawn", pawn)
    if pawn then
        report("HandResolverLeft", Util.Prop(pawn, "HandResolverLeftReference"))
        report("HandResolverRight", Util.Prop(pawn, "HandResolverRightReference"))
    end
    for hand = 0, 1 do
        local name = hand == Haptics.LEFT and "L" or "R"
        local a = Player.Held(hand)
        local held = a and a:GetFullName() or "nothing"
        if last["held" .. name] ~= held then
            last["held" .. name] = held
            Util.Log("[diag] Hand %s holds: %s", name, held)
        end
        if a then
            -- List the object components (once per object)
            local akey = "comps" .. a:GetFullName()
            if not last[akey] then
                last[akey] = true
                for _, c in ipairs(Util.FindOwnedBy(a, OWNED_CLASSES)) do
                    local d = describe(c)
                    Util.Log("[diag]   component: %s%s", c:GetFullName(), d ~= "" and (" | " .. d) or "")
                end
            end
            for i, r in ipairs(Util.FindOwnedBy(a, { "AtlasGunResolver", "NDNTResolverBasic", "NDNTResolver" })) do
                report(string.format("%s.resolver%d", name, i), r)
            end
            local data = Util.Prop(a, "CurrentGunData") or Util.Prop(a, "GunData")
            if data then report(name .. ".gundata", data) end
        end
    end
end

return Diag
