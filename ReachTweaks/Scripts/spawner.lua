-- Test tool: F5 spawns the next weapon in front of the player,
-- F6 spawns the last one again.
local Util = require("util")
local Player = require("player")

local Spawner = {}

local GUNS = {
    "/Game/AtlasProto/Blueprints/Weapons/Guns/BP_AtlasGun_Handgun",
    "/Game/AtlasProto/Blueprints/Weapons/Guns/BP_AtlasGun_Shotgun_Large",
    "/Game/AtlasProto/Blueprints/Weapons/Guns/BP_AtlasGun_GrenadeLauncher",
}

local index = 0

local function loadClass(pkg)
    local name = pkg:match("([^/]+)$")
    local full = pkg .. "." .. name .. "_C"
    local cls = StaticFindObject(full)
    if not Util.IsValid(cls) then
        Util.SafeCall(function() LoadAsset(pkg) end)
        cls = StaticFindObject(full)
    end
    if Util.IsValid(cls) then return cls end
    Util.Log("Could not load %s", full)
    return nil
end

-- Point in front of the head: dist cm forward, dz cm vertical.
-- yawOffset rotates the object relative to the view direction.
local function spawnPoint(pc, dist, dz, yawOffset)
    local cam = Util.Prop(pc, "PlayerCameraManager")
    if not cam then return nil end
    local loc = cam:GetCameraLocation()
    local rot = cam:GetCameraRotation()
    local yaw = math.rad(rot.Yaw)
    return {
        X = loc.X + math.cos(yaw) * dist,
        Y = loc.Y + math.sin(yaw) * dist,
        Z = loc.Z + dz,
    }, { Pitch = 0, Yaw = rot.Yaw + yawOffset, Roll = 0 }
end

function Spawner.SpawnInFront(cls, pc, dist, dz, yawOffset)
    local loc, rot = spawnPoint(pc, dist, dz, yawOffset)
    if not loc then Util.Log("No camera: cannot spawn the object") return nil end

    -- 1) UE4SS API
    local ok, actor = pcall(function() return pc:GetWorld():SpawnActor(cls, loc, rot) end)
    if ok and Util.IsValid(actor) then return actor end

    -- 2) GameplayStatics (BeginDeferred + FinishSpawning)
    local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local yaw = math.rad(rot.Yaw) / 2
    local transform = {
        Rotation = { X = 0, Y = 0, Z = math.sin(yaw), W = math.cos(yaw) },
        Translation = loc,
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
    ok, actor = pcall(function()
        local a = statics:BeginDeferredActorSpawnFromClass(pc, cls, transform, 1, nil, 0)
        return statics:FinishSpawningActor(a, transform, 0)
    end)
    if ok and Util.IsValid(actor) then return actor end
    Util.Log("Spawn failed: %s", tostring(actor))
    return nil
end

local function spawnIndex(i)
    local pc = Player.GetController()
    if not pc then return end
    local pkg = GUNS[i]
    local cls = loadClass(pkg)
    if not cls then return end
    local actor = Spawner.SpawnInFront(cls, pc, 40, -30, 90)
    if actor then Util.Log("Weapon spawned: %s", actor:GetFullName()) end
end

function Spawner.Init()
    local Keys = require("keys")
    Keys.Bind("F5", function()
        index = index % #GUNS + 1
        spawnIndex(index)
    end)
    Keys.Bind("F6", function()
        if index == 0 then index = 1 end
        spawnIndex(index)
    end)
    Util.Log("Test weapons: F5 = next, F6 = repeat")
end

return Spawner
