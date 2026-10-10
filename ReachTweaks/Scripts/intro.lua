-- Fast startup.
-- Original flow (measured): P_PSO (shader warm-up, ~18 s) ->
-- splash with logos and health warning (~12 s) -> TransitionToLevel(menu).
-- When the splash is created (or on P_PSO) we jump straight to the menu level.
local Util = require("util")

local Intro = {}

local SPLASH = "/Script/AtlasSystem.AtlasScreenPartSplashBase"
local FLOW = "/Script/AtlasSystem.AtlasLevelFlowSubsystem"
local PSO_WORLD = "/Game/AtlasProto/Maps/PSO_Lvl/P_PSO"

local cfg
local lastWorld = nil
local startClock = os.time()
local skipped = false
local jumpTime = nil
local retried = false

local function str(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and s then return s end
    ok, s = pcall(function() return v:GetFullName() end)
    if ok and s then return s end
    return tostring(v)
end

local function arg(p)
    local ok, v = pcall(function() return p:get() end)
    if ok then return v end
    return p
end

local function jumpToMenu(pc, reason)
    if skipped then return end
    skipped = true
    jumpTime = os.time()
    local level = cfg.TargetLevel or "P_InteractiveFrontEndMenu"
    Util.Log("[intro] Skipping %s -> %s", reason, level)

    -- 1) The same system the game uses
    --    TransitionToLevel(WorldContext, LevelName, FadeDelay, Options, bDisplayLoadingSplash, LevelTag)
    local flow = StaticFindObject("/Script/AtlasSystem.Default__AtlasLevelFlowSubsystem")
    local ok, err = pcall(function()
        flow:TransitionToLevel(pc, FName(level), 0.0, "", true, {})
    end)
    if ok then return end
    Util.Log("[intro] TransitionToLevel failed (%s); using OpenLevel", tostring(err))

    -- 2) Fallback: engine OpenLevel
    local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    Util.SafeCall(function() statics:OpenLevel(pc, FName(level), true, "") end)
end

function Intro.Tick(pc)
    local ok, w = pcall(function() return pc:GetWorld():GetFullName() end)
    -- Watchdog: if we are still on P_PSO after jumping (black screen), force OpenLevel
    if ok and jumpTime and not retried and w:find(PSO_WORLD, 1, true) and os.time() - jumpTime > 10 then
        retried = true
        local level = cfg.TargetLevel or "P_InteractiveFrontEndMenu"
        Util.Log("[intro] The jump did not load the menu; retrying with OpenLevel")
        local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        Util.SafeCall(function() statics:OpenLevel(pc, FName(level), true, "") end)
    end
    if ok and w ~= lastWorld then
        lastWorld = w
        Util.Log("[intro] +%ds world: %s", os.time() - startClock, w)
        if cfg.SkipShaderWarmup and w:find(PSO_WORLD, 1, true) then
            ExecuteWithDelay(3000, function()
                ExecuteInGameThread(function()
                    local cur = FindFirstOf("PlayerController")
                    if Util.IsValid(cur) then jumpToMenu(cur, "shader warm-up") end
                end)
            end)
        end
    end
end

function Intro.Init(config)
    cfg = config
    local function hook(fn, cb)
        Util.SafeCall(function() RegisterHook(fn, cb) end)
    end

    hook(FLOW .. ":TransitionToLevel", function(_, ctx, levelName, fade, options, splash, tag)
        Util.Log("[intro] +%ds TransitionToLevel level=%s fade=%s options=%s splash=%s",
            os.time() - startClock, str(arg(levelName)), str(arg(fade)), str(arg(options)), str(arg(splash)))
    end)

    Util.SafeCall(function()
        NotifyOnNewObject(SPLASH, function(obj)
            Util.Log("[intro] +%ds Splash created: %s", os.time() - startClock, str(obj))
            if cfg.SkipLogos then
                -- Short wait so the GameInstance finishes setting up
                ExecuteWithDelay(500, function()
                    ExecuteInGameThread(function()
                        local pc = FindFirstOf("PlayerController")
                        if Util.IsValid(pc) then jumpToMenu(pc, "logos and warning") end
                    end)
                end)
            end
        end)
    end)
end

return Intro
