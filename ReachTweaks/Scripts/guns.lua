-- Firearm haptics: sharp kick + decay on each shot, supporting hand
-- included, and scaling of the game's original vibrations.
local Util = require("util")
local Player = require("player")
local Haptics = require("haptics")

local Guns = {}

local GUN_CLASSES = {
    "/Script/AtlasGameplay.AtlasGun",
    "/Script/NDWeapon.NDWEBaseGun",
}
local NATIVE_EFFECTS = { "GunFireHapticEffect", "GunCockingHapticEffect", "GunCockingCompletedHapticEffect" }

local cfg
local now = 0
local lastFire = {}     -- gunKey -> ms of the last detected shot
local lastAmmo = {}     -- gunKey -> ammo on the previous tick
local autoCache = {}    -- gunKey -> bool
local heldSince = { [0] = { key = nil, t = 0 }, [1] = { key = nil, t = 0 } }
local scaledData = {}   -- gun data path -> scale applied
local checkedGuns = {}  -- gunKey -> true (its data was already handled)

local function isGun(actor)
    for _, cp in ipairs(GUN_CLASSES) do
        if Util.IsA(actor, cp) then return true end
    end
    return false
end

local function isAutomatic(gun, key)
    local v = autoCache[key]
    if v == nil then
        local ok, r = pcall(function() return gun:GetIsAutomatic() end)
        v = ok and r == true
        autoCache[key] = v
    end
    return v
end

local function onFire(gun)
    local key = Util.Key(gun)
    -- Avoid duplicates between the hook and ammo-based detection
    if lastFire[key] and now - lastFire[key] < 45 then return end
    lastFire[key] = now

    local hands = Player.HandsHolding(gun)
    if #hands == 0 then  -- enemy shot (or hand not detected)
        Util.DLog("Shot without a player hand: %s", gun:GetFullName())
        return
    end

    -- Main hand = the one that grabbed it first
    table.sort(hands, function(a, b) return heldSince[a].t < heldSince[b].t end)

    local amp = cfg.FireAmplitude
    local dur = cfg.FireDurationMs
    if isAutomatic(gun, key) then
        amp = amp * cfg.AutomaticFactor
        dur = dur * 0.7
    end

    local kickMs = cfg.FireKickMs or 40
    local tail = cfg.FireTailAmplitude or 0.9
    for i, h in ipairs(hands) do
        local a = (i == 1) and amp or amp * cfg.OtherHandFactor
        Haptics.Pulse(h, a, kickMs, a, 1.0)             -- sharp kick at full strength
        Haptics.Pulse(h, a * tail, dur, 0.0, 0.8)       -- recoil fading out
    end
    Util.DLog("Shot: %s (hands %d)", gun:GetFullName(), #hands)
end

function Guns.Tick(dtMs)
    now = now + dtMs
    for hand = 0, 1 do
        local a = Player.Held(hand)
        local key = a and Util.Key(a) or nil
        if heldSince[hand].key ~= key then
            heldSince[hand] = { key = key, t = now }
        end
        if a and isGun(a) then
            if not checkedGuns[key] then
                checkedGuns[key] = true
                Util.SafeCall(Guns.ScaleNativeHaptics, a)
            end
            local ok, ammo = pcall(function() return a:GetCurrentAmmoCount() end)
            if ok and type(ammo) == "number" then
                local prev = lastAmmo[key]
                if prev ~= nil and ammo < prev then onFire(a) end
                lastAmmo[key] = ammo
            end
        end
    end
end

-- Multiplies the scale of the native vibrations defined in the data of a
-- gun the player grabs (an AtlasGunData asset, shared by every gun of that
-- type). Done once per data asset; F7 OFF divides it back.
-- (It used to scan FindAllOf("NDWEGunData") every 2 s: exact class only, so
-- it never found the AtlasGunData subclass and had no effect.)
function Guns.ScaleNativeHaptics(gun)
    local scale = cfg.NativeHapticScale or 1.0
    if scale == 1.0 then return end
    local d = Util.Prop(gun, "CurrentGunData") or Util.Prop(gun, "GunData")
    local path = d and Util.Path(d)
    if not path or scaledData[path] then return end
    scaledData[path] = scale
    for _, prop in ipairs(NATIVE_EFFECTS) do
        Util.SafeCall(function()
            local eff = d[prop]
            local s = eff.HapticEffectScale
            eff.HapticEffectScale = s * scale
            Util.DLog("GunData %s.%s scale %.2f -> %.2f", path, prop, s, s * scale)
        end)
    end
end

-- Undoes the native scaling (when the mod is disabled with F7).
function Guns.RestoreNative()
    for path, scale in pairs(scaledData) do
        local d = StaticFindObject(path)
        if Util.IsValid(d) then
            for _, prop in ipairs(NATIVE_EFFECTS) do
                Util.SafeCall(function()
                    local eff = d[prop]
                    eff.HapticEffectScale = eff.HapticEffectScale / scale
                end)
            end
        end
    end
    scaledData = {}
    checkedGuns = {}
end

function Guns.Init(config)
    cfg = config
    local fns = {
        "/Script/AtlasGameplay.AtlasGun:Fire",
        "/Script/NDWeapon.NDWEGun:Fire",
        "/Script/NDWeapon.NDWEBaseGun:Fire",
    }
    for _, fn in ipairs(fns) do
        Util.SafeCall(function()
            RegisterHook(fn, function(self)
                local gun = self:get()
                if Util.IsValid(gun) then onFire(gun) end
            end)
        end)
    end
end

return Guns
