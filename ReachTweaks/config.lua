-- ============================================================
--  ReachTweaks - configuration
--  Edit the values and relaunch the game with
--  "Play_ReachTweaks.bat" (it copies this file into the game).
-- ============================================================
return {
    -- Write detailed information to ReachTweaks.log and ue4ss\UE4SS.log
    Debug = true,

    -- --------------------------------------------------------
    -- FAST STARTUP
    -- --------------------------------------------------------
    Intro = {
        SkipLogos = true,            -- skip logos + health & safety warning (~12 s)
        -- Also skip the shader warm-up level (~18 s). Starts faster, but there
        -- may be hitches the first time each effect is seen.
        SkipShaderWarmup = true,
        TargetLevel = "P_InteractiveFrontEndMenu",  -- main menu level
    },

    -- --------------------------------------------------------
    -- TESTING: F5 spawns the next weapon in front of you
    -- (Handgun, shotgun, grenade launcher), F6 repeats the last
    -- one, F8 cycles weight-stiffness experiments.
    -- The game window on the PC must have focus.
    -- --------------------------------------------------------
    TestGuns = true,

    -- --------------------------------------------------------
    -- 1) AGILE HANDS
    -- The game ties held weapons to the hand with a spring
    -- (stiffness and damping). Low stiffness makes the weapon lag,
    -- wobble and cap its speed.
    -- --------------------------------------------------------
    Hands = {
        Enabled = true,
        WeightStiffnessMultiplier = 10.0,  -- 1 = original; higher = tighter to the hand
        WeightDamping = 1.0,               -- 1.0 = no wobble (critical damping)
        -- "weapons" = guns and bow only; "all" = any throwable object
        Scope = "weapons",
    },

    -- --------------------------------------------------------
    -- 2) BOW
    -- Amplitudes from 0.0 to 1.0
    -- --------------------------------------------------------
    Bow = {
        Enabled = true,
        TensionMinAmplitude = 0.05,  -- vibration when starting to draw
        TensionMaxAmplitude = 0.55,  -- vibration at full draw
        BowHandFactor = 0.35,        -- share felt by the hand holding the bow
        ClickAmplitude = 0.8,        -- "clicks" when passing 25/50/75 %
        FullDrawAmplitude = 0.7,     -- buzz while held at full draw
        ReleaseAmplitude = 1.0,      -- kick when the arrow is released
        ReleaseDurationMs = 90,
        -- Used when the game does not report which hand draws the string
        DefaultStringHand = "right", -- "right" or "left"
    },

    -- --------------------------------------------------------
    -- 3) BOW BODY WHILE DRAWING
    -- While the string is held, the game averages the bow hand and
    -- the string hand, so the bow body follows the bow hand slowly.
    -- This pulls the bow grip back to the bow hand. Only the bow
    -- position is corrected: the string and the aim are untouched.
    -- --------------------------------------------------------
    BowBody = {
        Enabled = true,
        BodyFollow = 0.0,   -- 0 = original game, 1 = grip locked to the hand
        BlendMs = 150,      -- fade in/out time when grabbing/releasing the string
    },

    -- --------------------------------------------------------
    -- 4) FIREARMS
    -- --------------------------------------------------------
    Guns = {
        Enabled = true,
        FireAmplitude = 1.0,         -- kick strength of each shot (max 1.0)
        FireKickMs = 40,             -- duration of the full-strength kick
        FireTailAmplitude = 0.9,     -- strength of the fading recoil tail (share of the kick)
        FireDurationMs = 120,        -- duration of the fading recoil tail
        AutomaticFactor = 0.75,      -- automatic weapons: slightly weaker, shorter kick
        OtherHandFactor = 0.7,       -- supporting hand when held with two hands
        -- Multiplies the game's original weapon vibrations (1 = unchanged)
        NativeHapticScale = 1.5,
    },
}
