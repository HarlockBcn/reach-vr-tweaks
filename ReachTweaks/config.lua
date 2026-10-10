-- ============================================================
--  ReachTweaks - configuration
--  Edit the values and relaunch the game with
--  "Play_ReachTweaks.bat" (it copies this file into the game).
--  In game: edit this file (or the copy in
--  Atlas\Binaries\Win64\ue4ss\Mods\ReachTweaks) and press F7 twice
--  (OFF, ON): turning the tweaks on re-reads the copy you changed.
--  ("Enabled" and "Debug" changes still need a restart.)
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
    -- 3) BOW BODY WHILE DRAWING (experimental, parked)
    -- Tries to pull the bow grip back to the bow hand while the
    -- string is held. It has no visible effect yet (the game
    -- overwrites it), so it is disabled. With Debug = true it
    -- still logs bow lag measurements when enabled.
    -- --------------------------------------------------------
    BowBody = {
        Enabled = false,
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

    -- --------------------------------------------------------
    -- 5) SPRINT SLIDE
    -- Crouch while sprinting to slide a few metres in the direction
    -- you were running. Crouching while walking behaves as in the
    -- original game.
    -- --------------------------------------------------------
    Slide = {
        Enabled = true,
        -- "both" = duck your head or press the crouch button ("B" by default)
        -- "head" = ducking only; "button" = crouch button only
        Trigger = "both",
        CrouchDropCm = 25,       -- how far the head must drop to count as a crouch
        CrouchWindowMs = 250,    -- ...within this time (slow crouches do not slide)
        MinSpeed = 250,          -- minimum running speed to slide (cm/s)
        SpeedBoost = 1.6,        -- slide start speed = running speed x this
        MaxSpeed = 1600,         -- cap for the slide start speed (cm/s)
        DurationMs = 1400,       -- slide length in time (with these values ~6.5 m at full sprint)
        EndSpeedFactor = 0.4,    -- speed at the end of the slide (share of the start)
        KeepSprintLines = true,  -- keep the sprint speed lines while sliding
        NoSprintWhileCrouched = true, -- crouched (button or physically) = no sprint
        CrouchDownMs = 300,      -- time to get fully crouched when a slide starts (game: ~870; 0 = game speed)
        HapticAmplitude = 0.3,   -- light rumble while sliding (0 = off)
        CooldownMs = 600,        -- minimum time between slides
        ThrusterStepMs = 30,     -- internal: length of each movement push
    },

    -- --------------------------------------------------------
    -- 6) ARM-SWING SPRINT
    -- Swing both arms like a runner while moving with the stick to
    -- sprint (clicking the stick still works). Stop swinging to walk
    -- again. Crouching right after swinging still slides.
    -- --------------------------------------------------------
    ArmSprint = {
        Enabled = true,
        MinHandSpeed = 80,       -- how fast each hand must swing (cm/s, average)
        MaxCorrelation = -0.3,   -- hands must move in opposite directions (-1 = perfectly opposite)
        StartMs = 200,           -- swing this long to start sprinting
        StopMs = 500,            -- stop swinging this long to walk again
        MinStick = 0.3,          -- stick deflection needed (0..1); no sprint while standing still
        HapticAmplitude = 0.15,  -- short tap when the sprint starts (0 = off)
        WindowMs = 400,          -- internal: time window for the swing measurement
        SmoothMs = 40,           -- internal: hand velocity smoothing
        RetryMs = 500,           -- internal: wait before restarting a sprint the game ended
    },
}
