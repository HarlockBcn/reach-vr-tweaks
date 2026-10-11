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
    Debug = false,

    -- --------------------------------------------------------
    -- FAST STARTUP
    -- --------------------------------------------------------
    Intro = {
        SkipLogos = false,            -- skip logos + health & safety warning (~12 s)
        -- Also skip the shader warm-up level (~18 s). Starts faster, but there
        -- may be hitches the first time each effect is seen.
        SkipShaderWarmup = false,
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
        LandSettleMs = 500,      -- after landing, head ducks are ignored this long (landing from a height dips the head)
        -- Crouch button while landing from a sprint jump (pressed in the air
        -- or right after touching the ground):
        -- "slide" = crouched slide, like a normal slide
        -- "stop"  = crouch and stop running (no slide)
        LandingCrouch = "slide",
        LandingWindowMs = 300,
        BrakeWithStick = true,   -- push the stick against the slide to brake it
        BrakeDecel = 1000,       -- braking at full stick (cm/s per second; ~0.35 s from full slide speed)
        BrakeMinStick = 0.5,     -- stick deflection needed to brake (0..1)
        BrakeStopSpeed = 150,    -- the braked slide ends below this speed (cm/s)   -- a press this long after landing still counts as "while landing"
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
        StillMs = 100,           -- a hand stopped this long = walk again at once
        StopMs = 500,            -- swing no longer like running (e.g. hands together) this long = walk again
        MinStick = 0.3,          -- stick deflection needed (0..1); no sprint while standing still
        HapticAmplitude = 0.15,  -- short tap when the sprint starts (0 = off)
        BlockWhileClimbing = true, -- no arm-swing sprint while a hand holds a climbable surface (objects/weapons don't count)
        ClimbGraceMs = 500,      -- ...and this long after letting go
        WindowMs = 400,          -- internal: time window for the swing measurement
        SmoothMs = 40,           -- internal: hand velocity smoothing
        StillWindowMs = 150,     -- internal: short time window to detect stopped hands
        RetryMs = 500,           -- internal: wait before restarting a sprint the game ended
    },

    -- --------------------------------------------------------
    -- 7) SPRINT SPEED
    -- Scales the game's sprint speed (stick click or arm swing).
    -- With Debug = true the log shows the game's value ([sprint]).
    -- The slide starts from the running speed, so it gets faster
    -- too (up to Slide.MaxSpeed).
    -- --------------------------------------------------------
    Sprint = {
        Enabled = true,
        SpeedMultiplier = 1.2,   -- 1.0 = original; 1.5 = 50 % faster
    },

    -- --------------------------------------------------------
    -- 8) SPRINT THROUGH JUMPS
    -- The game ends the sprint when you jump or land, so you walk
    -- after every jump. This keeps sprinting through the jump and
    -- after landing (stick click or arm swing) while the stick is
    -- still pushed. With Debug = true the log shows [jumpsprint].
    -- --------------------------------------------------------
    JumpSprint = {
        Enabled = true,
        KeepInAir = true,        -- keep sprinting in the air too (running speed and speed lines during the jump)
        MinStick = 0.3,          -- stick deflection needed on landing to keep sprinting (0..1)
        LandGraceMs = 400,       -- after landing, the arm swing has this long to start again
        ResumeWindowMs = 300,    -- stick released this long after landing = walk/stand normally
        JumpWindowMs = 300,      -- internal: a sprint ended this soon after the jump counts as ended by the jump
        MaxRestarts = 3,         -- internal: restarts per jump if the game keeps ending the sprint
    },

    -- --------------------------------------------------------
    -- 9) GRAPPLE ONLY IN VIEW
    -- The grapple drone (hook) only fires at a target you can see:
    -- pointing the hand at a ledge, pole, shield or weapon behind
    -- you or hidden behind a wall does nothing. With Debug = true
    -- the log shows [grapple] (target in view / BLOCKED and why).
    -- --------------------------------------------------------
    GrappleView = {
        Enabled = true,
        ViewAngle = 60,             -- max angle between where you look and the target (degrees)
        HandAimAngle = 90,          -- hand pointing further than this from where you look = blocked at once
        RequireLineOfSight = false, -- also blocked when something hides the target from your eyes (may block bars mounted on walls)
        LineOfSightMarginCm = 100,  -- the sight check stops this short of the target (its own ledge/wall does not hide it)
        SettleMs = 100,             -- internal: wait after pressing grip until the game has picked the new target
    },

    -- --------------------------------------------------------
    -- 10) SHIELD THROW SPEED
    -- Makes the thrown shield faster. The game already throws it at
    -- ~2000-2800 cm/s; ThrowSpeedMultiplier is what changes it most.
    -- With Debug = true the log shows [shield] (game speed, swing
    -- peak and final speed of each throw, speed during the flight,
    -- bounces). Speeds in cm/s (1000 = 10 m/s).
    -- --------------------------------------------------------
    Shield = {
        Enabled = true,
        ThrowSpeedMultiplier = 1.75, -- multiplier on the game's throw speed (1.0 = original)
        MinThrowSpeed = 1000,        -- a thrown shield leaves at least this fast (0 = off)
        -- Use the fastest speed of the swing when it beats the game's speed
        -- (measured in game it is lower, ~650-760 cm/s, so it rarely changes anything)
        UsePeakSpeed = true,
        PeakWindowMs = 150,          -- ...looking back this long before letting go
        -- Undo small slowdowns in flight (measured in game the shield only
        -- loses speed on bounces, so this rarely changes anything)
        KeepSpeed = false,
    },

    -- --------------------------------------------------------
    -- 11) SAVE TIME IN THE SAVE LIST
    -- The menu's save slots show the date of each save; this adds
    -- the time (read from the save file, local time). With
    -- Debug = true the log shows [savetime] (each date text changed,
    -- or the slot's texts when no date was found).
    -- --------------------------------------------------------
    SaveTime = {
        Enabled = true,
        Format = "%H:%M",           -- "%H:%M" = 24 h (14:35), "%I:%M %p" = 12 h (02:35 PM), "%H:%M:%S" with seconds
        Separator = " ",            -- between the date and the time
    },
}
