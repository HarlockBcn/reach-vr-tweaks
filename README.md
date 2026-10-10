# ReachTweaks

A UE4SS Lua mod for **Reach** (nDreams, Steam AppID 3273480, Unreal Engine 5.4) that:

1. **Agile hands** – removes the sluggish "weight" of held weapons. The game ties a held weapon to the hand with a damped spring (`UAtlasThrowableResolver::ApplyWeight`); the mod makes that spring stiffer and critically damped while the weapon is held (×10 by default).
2. **Bow haptics** – vibration that grows while drawing, tension "clicks" at 25/50/75 %, a buzz at full draw and a kick on release.
3. **Firearm haptics** – a sharp kick with a fading tail on every shot, also on the supporting hand, plus scaling of the game's own weapon vibrations.
4. **Sprint slide** – crouching (ducking your head or pressing the crouch button, "B" by default) while sprinting slides you a few metres in the direction you were running, at the game's crouch height; the sprint speed lines stay on. Afterwards you stand up again (a button slide stays crouched if the button is still held). Sprinting is not possible while crouched. Crouching while walking is unchanged.
5. **Arm-swing sprint** – swinging both arms like a runner while moving with the stick starts the sprint (clicking the stick still works); stop swinging and you walk again. Ducking right after swinging still slides.
6. **Fast startup** – skips the logo / health-warning splash and (optionally) the shader warm-up level.

## Install & play

- **Play**: double-click `Play_ReachTweaks.bat`.
  - The first time it downloads **UE4SS** (open-source mod loader, ~9 MB) from its official GitHub release, verifies its SHA-256 and installs it in `Atlas\Binaries\Win64`.
  - It then copies the mod and starts Reach through Steam.
  - Offline: put a `UE4SS_v*.zip` next to this file and the launcher will use it.
- **Uninstall**: double-click `Uninstall_ReachTweaks.bat`. It removes only what the launcher added.
- While installed, the mod is also active when starting the game from Steam.

## Keys (the game window on the PC must have focus)

| Key | Action |
|---|---|
| **F7** | Toggle all tweaks on/off to compare with the original game. A floating text appears in front of you; two short taps = ON, one long buzz = OFF. Turning them ON re-reads `config.lua` |
| F5 / F6 | (Testing, `TestGuns = true`) spawn the next weapon / spawn the last one again |
| F8 | (Testing) cycle weight-stiffness levels: Mod config → Original → ×3 → ×10 → ×30 → ×100 |

## Configuration

Edit `ReachTweaks\config.lua` and relaunch with `Play_ReachTweaks.bat`. While playing, edit either copy (this package's `ReachTweaks\config.lua` or the installed `Atlas\Binaries\Win64\ue4ss\Mods\ReachTweaks\config.lua`) and press F7 twice (OFF, ON): the mod re-reads the copy whose text changed (the launcher writes the package path into `package_config.txt` next to the installed mod, and copies a newer installed copy back to the package on the next launch). Only `Enabled` and `Debug` changes need a restart.

| Setting | Meaning |
|---|---|
| `Hands.WeightStiffnessMultiplier` | 1 = original; higher = weapon sticks tighter to the hand |
| `Hands.WeightDamping` | 1.0 = no wobble (critical damping) |
| `Hands.Scope` | `"weapons"` (guns and bow) or `"all"` (any throwable) |
| `Bow.*` | Draw / click / full-draw / release vibration amplitudes |
| `BowBody.*` | Experimental, disabled (see Known issues) |
| `Guns.FireAmplitude`, `FireDurationMs` | Shot kick and recoil duration |
| `Guns.NativeHapticScale` | Multiplies the game's own weapon vibrations |
| `Slide.Trigger` | `"both"` (duck your head or press crouch), `"head"` or `"button"` |
| `Slide.CrouchDropCm`, `CrouchWindowMs` | Head drop (cm) within this time that counts as a quick duck |
| `Slide.MinSpeed`, `SpeedBoost`, `MaxSpeed` | Minimum running speed, start speed = running speed × boost (capped) |
| `Slide.DurationMs`, `EndSpeedFactor` | Slide time and final speed (share of the start speed) |
| `Slide.CrouchDownMs` | Time to get fully crouched when a slide starts (the game takes ~870 ms; 0 = game speed) |
| `Slide.KeepSprintLines`, `NoSprintWhileCrouched`, `HapticAmplitude` | Speed lines while sliding, sprint lock while crouched, slide rumble |
| `ArmSprint.MinHandSpeed`, `MaxCorrelation` | How fast each hand must swing (cm/s) and how opposite the hands must move (-1 = perfectly opposite) |
| `ArmSprint.StartMs`, `StopMs`, `MinStick` | Swing time to start, still time to walk again, stick deflection needed |
| `Intro.SkipLogos`, `Intro.SkipShaderWarmup` | Fast startup options |
| `Debug` | Writes details to `ue4ss\Mods\ReachTweaks\ReachTweaks.log` |

## Project layout

```
Play_ReachTweaks.bat / Uninstall_ReachTweaks.bat   entry points
Launcher/ReachTweaks.ps1                           installer / launcher
ReachTweaks/                                       the UE4SS mod (copied into the game)
  config.lua
  Scripts/main.lua        entry point, main loop, F7 toggle
  Scripts/hands.lua       weight-spring patch (agile hands)
  Scripts/bow.lua         bow haptics
  Scripts/bowbody.lua     bow body follow while drawing (experimental, disabled)
  Scripts/guns.lua        firearm haptics
  Scripts/slide.lua       sprint slide
  Scripts/armsprint.lua   arm-swing sprint
  Scripts/keys.lua        keyboard shortcuts (polled on the game thread)
  Scripts/haptics.lua     per-hand vibration mixer (SetHapticsByValue)
  Scripts/player.lua      player / held-object tracking
  Scripts/intro.lua       fast startup
  Scripts/spawner.lua, experiments.lua, notify.lua    test tools (F5/F6/F8, VR text)
  Scripts/diag.lua, lagprobe.lua                      debug diagnostics
tools/                                             reverse-engineering helpers (Python)
```

## Reverse-engineering notes

The game ships `Atlas-Win64-Shipping.pdb`, so class/property/function names and offsets can be recovered without running the game. The helpers in `tools/` do this:

- `pdbpub.py` – dumps PDB public symbols (`rva<TAB>flags<TAB>name`).
- `dis.py` – disassembles functions by name using those symbols (needs `capstone`).
- `propoff.py` – reads reflected property offsets from `FGenericPropertyParams`.
- `u16.py` – searches UTF-16 strings (console variables, etc.).
- `dmp.py` – minimal minidump reader (faulting module + stack scan).

Key findings:

- Weapon heaviness = `UAtlasThrowableResolver::ApplyWeight` (`VectorSpringInterp` / `QuaternionSpringInterp`, mass 1.0) with `LinearStiffness`/`LinearDamping`/`AngularStiffness`/`AngularDamping`. `AtlasGunResolver` derives from it.
- Player locomotion = `UAtlasMovementComponent` (pawn `AtlasMovementComponentReference`, Blueprint subclass `BP_AtlasMovementComponent_C`, movement loop in Blueprint). Sprint: `bIsSprinting` (+0x315), `StartSprint`/`StopSprint` set `Speed` to `RunSpeed`/`WalkSpeed` and broadcast `OnSprintStarted`/`OnSprintEnded`; the sprint input (native `OnSprintInput`) only starts a sprint when `bIsSprinting` is false. The sprint lines are the pawn component `BP_VFX_SprintFX`, which polls `GetIsSprinting` every frame (`PreviouslySprinting`).
- Crouch: physical (head height) or the crouch button, input action `/Game/AtlasProto/Blueprints/Input/Actions/Movement/IA_Crouch` ("B"), handled only in Blueprint by `InpActEvt_IA_Crouch_K2Node_EnhancedInputActionEvent_0`, one event per press (`UEnhancedInputLibrary::GetBoundActionValue` cannot poll it: it only works for value bindings). It toggles `StartButtonCrouch`/`StopButtonCrouch` (`bButtonCrouch`, `bWantsToCrouch`, `bIsCrouching`). Crouching eases `Crouch Height` from ~90 down to `ButtonCrouchHeight` (50) in ~870 ms, which lowers the whole actor. `StopButtonCrouch` alone leaves `bWantsToCrouch` set; `TryUncrouch` → `UnCrouch` gives the real height back. The "On Sprint Started" handler calls `TryUncrouch`, so a sprint stands the player up.
- Thrusters: `AddLinearThruster(FAtlasMovementThrusterLinear)` gives `Direction * Strength` (× `StrengthOverTime` curve over `Duration` if set); non-additive thrusters replace the movement velocity (summed if several), additive ones add to it; expired ones are removed after each movement update; `HasActiveOverrideThrusters` tells whether one is running.
- Sprint slide (`slide.lua`): chains short non-additive thrusters (only when none is active); keeps the lines by writing `bIsSprinting` directly (no `OnSprintStarted`, which would uncrouch); a head slide calls `StartButtonCrouch`, then `StopButtonCrouch` + `TryUncrouch` (+ `UnCrouch`) at the end; drives `Crouch Height` down faster; the crouch lock holds `bIsSprinting` on with walk `Speed` so the sprint input cannot start a sprint. The standing head height is learnt from the measured head height (the game's calibration offset did not match it after a level change); moves over 3 m in one tick are treated as teleports.
- Sprint input: native `OnSprintInput` (bound to `SprintInput`): a non-zero value calls the `StartSprint` logic; a zero value calls `StopSprint` only when `bToggleSprint` (+0x314) is false. `UAtlasMovementComponent` has `LeftMotionController`, `RightMotionController` and `Headset` object properties, and `GetForwardInput` / `GetRightInput` return the stick axes.
- Arm-swing sprint (`armsprint.lua`): per hand, swing = height + forward distance relative to the head; smoothed velocities, windowed RMS per hand and left/right correlation (running = both fast and negatively correlated). Calls `StartSprint` / `StopSprint`, ends only sprints it started, and does nothing while `Slide.HoldsSprint()` (slide or crouch lock).
  Measured in VR (2026-10-10): running arm swing ~220–320 cm/s per hand with correlation -0.65 to -0.9; ordinary hand movement stays below ~100 cm/s or near 0 / positive correlation, so the defaults (80 cm/s, -0.3, start 200 ms) leave a wide margin. Ducking into a slide flips the correlation positive, and the sprint is handed to the slide (`sprint handed to the slide` in the log) before the gesture ends.
- Dead ends (no effect, the resolvers run with `MovementMethod = NoPhysics`): `ObjectPosition/RotationHeaviness`, `MagicNumber_*`, `ResolverLinear/AngularStiffness`, recoil springs, `ND.HandGrab.*` lerp settings.
- UE4SS quirks: `K2_GetComponentsByClass` fails (use `FindAllOf` + owner); `FindAllOf` is exact-class only; pawn hand properties are `NDComponentPath` structs (use the `...Reference` properties); never keep UObjects across ticks; never run Lua off the game thread: `RegisterKeyBind` and `ExecuteWithDelay` callbacks run on UE4SS threads and crashed the game inside UE4SS (keys are polled with `IsInputKeyDown`, delays use `Util.After`).

## Known issues / TODO

- **Bow body while drawing (PARKED 2026-10-10, `bowbody.lua`, `BowBody.Enabled = false`).** With only the grip held the bow follows the hand well; while the string is held the bow *body* follows the bow hand slowly. Constraint: do **not** change how the string behaves (do not touch `BowStringCouplerRef` weights).
  - Cause: `UNDNTResolverBasic::CalculateMotionInternal` (rva 0x46c6ca0) builds one motion per active coupler (weight = motion[+4] * motion[+8]) and `CombineMotionsWithMagnets` (rva 0x46cb280) blends them: per-motion weight = `pow(w / max(maxW, 1e-4), MagneticExponent@0xbc8)`; positions are a weighted average, rotations an incremental slerp. On the bow `MagneticExponent = 0` and both weights are equal, so grip and string motions weigh the same. `MagneticExponent` only helps if the weights differ, which requires changing the string coupler (rejected). `MagneticClippingCoefficient@0xbc4` is not read by these functions.
  - Dead end: `AAtlasBow::TickSmoothNock` and `SmoothAttach*` only ease the **arrow** onto the nock (`TEase` + `SetActorTransform` on the arrow owned by `SmoothAttachCouplerRef`, then `BP_OnArrowNocked`). `OnBowGrabbed` / `OnBowStringGrabbed` only fire BP events.
  - `bowbody.lua` (first attempt): learns the grip offset in controller space and, while drawing, adds `BodyFollow` × error as a world offset to the bow. It has no visible effect: the game overwrites it every frame (our Lua tick runs before the resolvers), so `BodyFollow = 0` by default. Kept for its `[bowbody]` measurements.
  - Measurements (2026-10-10, original game behaviour, `[bowbody]` and `[bowparts]` in the log): the whole bow is rigid (ActorRoot, BowMesh, grip coupler move together; `bApplyMotionToAssociatedMesh` does not split them). Its error against the real controller is the **same with and without the string held**: ~3–8 cm at 150–350 cm/s, ~9–11 cm at 450+ cm/s; the bow covers ~85–100 % of the controller's path in both states. Frame rate does not drop while drawing (~85–88 ticks/s). The lag that exists is the general virtual hand/bow chain lag, present also with the grip only.
  - Open: what the player perceives as slower while drawing is not visible in game-thread positions. Next step candidates: reduce the general bow lag (requires applying corrections after the resolvers, e.g. a post-tick hook), or compare against render-thread late-updated controller poses.
- Height calibration screen is not skipped.
