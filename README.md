# ReachTweaks

A UE4SS Lua mod for **Reach** (nDreams, Steam AppID 3273480, Unreal Engine 5.4) that:

1. **Agile hands** – removes the sluggish "weight" of held weapons. The game ties a held weapon to the hand with a damped spring (`UAtlasThrowableResolver::ApplyWeight`); the mod makes that spring stiffer and critically damped while the weapon is held (×10 by default).
2. **Bow haptics** – vibration that grows while drawing, tension "clicks" at 25/50/75 %, a buzz at full draw and a kick on release.
3. **Firearm haptics** – a sharp kick with a fading tail on every shot, also on the supporting hand, plus scaling of the game's own weapon vibrations.
4. **Sprint slide** – crouching (ducking your head or pressing the crouch button, "B" by default) while sprinting slides you a few metres in the direction you were running, at the game's crouch height; the sprint speed lines stay on. Afterwards you stand up again (a button slide stays crouched if the button is still held). Pushing the stick backwards brakes the slide. Pressing crouch while landing from a sprint jump either slides or just crouches and stops (`Slide.LandingCrouch`). Sprinting is not possible while crouched. Crouching while walking is unchanged.
5. **Arm-swing sprint** – swinging both arms like a runner while moving with the stick starts the sprint (clicking the stick still works); stop swinging and you walk again. Ducking right after swinging still slides. Not while climbing (a hand holding a climbable surface).
6. **Sprint speed** – configurable multiplier for the game's sprint speed.
7. **Sprint through jumps** – the game ends the sprint when you jump or land; the mod keeps sprinting through the jump (running speed and speed lines in the air) and after landing while the stick is still pushed, with the stick click or the arm swing.
8. **Grapple only in view** – the grapple drone (hook) only latches onto a bar, ledge or object you can see: pressing grip with the hand pointing behind you (e.g. over the shoulder) or at a target outside the headset view does nothing (optional, `GrappleView`).
9. **Shield throw speed** – the thrown shield flies faster: a multiplier on the game's throw speed and a minimum throw speed (optionally the peak speed of the swing and no slowdown in flight).
10. **Fast startup** – skips the logo / health-warning splash and (optionally) the shader warm-up level.
11. **Save time in the save list** – the menu's save slots show the date of each save; the mod adds the time (e.g. `11/10/2026 03:48`).

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
| `Slide.LandingCrouch`, `LandingWindowMs` | Crouch button while landing from a sprint jump (in the air or up to `LandingWindowMs` after touching the ground): `"slide"` = crouched slide, `"stop"` = crouch and stop running |
| `Slide.BrakeWithStick`, `BrakeDecel`, `BrakeMinStick`, `BrakeStopSpeed` | Push the stick against the slide to brake it: deceleration at full stick (cm/s²), stick deflection needed, speed at which the braked slide ends |
| `Slide.LandSettleMs` | After landing, head ducks are ignored this long (landing from a height dips the head and looked like a duck) |
| `Slide.KeepSprintLines`, `NoSprintWhileCrouched`, `HapticAmplitude` | Speed lines while sliding, sprint lock while crouched, slide rumble |
| `ArmSprint.MinHandSpeed`, `MaxCorrelation` | How fast each hand must swing (cm/s) and how opposite the hands must move (-1 = perfectly opposite) |
| `ArmSprint.BlockWhileClimbing`, `ClimbGraceMs` | No arm-swing sprint while a hand holds a climbable surface and this long after letting go (holding objects or weapons does not count) |
| `ArmSprint.StartMs`, `StillMs`, `StopMs`, `MinStick` | Swing time to start; a hand stopped this long, or no running swing this long, walks again; stick deflection needed |
| `Sprint.SpeedMultiplier` | Sprint speed (1.0 = original); the slide gets faster too, up to `Slide.MaxSpeed` |
| `JumpSprint.KeepInAir`, `MinStick` | Keep sprinting in the air; stick deflection needed on landing to keep sprinting |
| `JumpSprint.LandGraceMs`, `ResumeWindowMs` | Time after landing for the arm swing to start again; stick released this long after landing = no sprint |
| `GrappleView.Enabled`, `ViewAngle` | Grapple only at targets within this angle of where you look (degrees) |
| `GrappleView.HandAimAngle` | A hand pointing further than this from where you look is blocked at once (degrees) |
| `GrappleView.RequireLineOfSight`, `LineOfSightMarginCm` | Also require a clear line from the eyes to the target (off by default: bars mounted on walls counted as hidden) |
| `Shield.ThrowSpeedMultiplier`, `MinThrowSpeed` | Multiplier on the game's throw speed (~2000–2800 cm/s originally) and least throw speed (cm/s) |
| `Shield.UsePeakSpeed`, `PeakWindowMs` | Use the fastest swing speed of the last `PeakWindowMs` when it beats the game's speed (rarely: the measured swing peak is lower) |
| `Shield.KeepSpeed` | Undo small in-flight slowdowns; off by default (the shield only loses speed on bounces) |
| `SaveTime.Format`, `Separator` | Time format appended to the save date (`"%H:%M"` = 24 h, `"%I:%M %p"` = 12 h) and the text between date and time |
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
  Scripts/sprint.lua      sprint speed
  Scripts/jumpsprint.lua  sprint through jumps
  Scripts/grapple.lua     grapple only in view
  Scripts/shield.lua      shield throw speed
  Scripts/savetime.lua    save time in the save list
  Scripts/keys.lua        keyboard shortcuts (polled on the game thread)
  Scripts/haptics.lua     per-hand vibration mixer (SetHapticsByValue)
  Scripts/player.lua      player / held-object tracking
  Scripts/intro.lua       fast startup
  Scripts/spawner.lua, experiments.lua, notify.lua    test tools (F5/F6/F8, VR text)
  Scripts/diag.lua, lagprobe.lua                      debug diagnostics
CHANGELOG.md                                       changes per version (shipped in every release)
tools/release.ps1                                  release builder (version bump, tag, zip)
tools/*.py                                         reverse-engineering helpers (Python)
```

## Releases

The version lives in `ReachTweaks/Scripts/main.lua` (`local VERSION`, shown in the log) and in git tags `vX.Y.Z`; changes are listed in `CHANGELOG.md` ([Semantic Versioning](https://semver.org/): minor = new feature, patch = fix/tuning, major = incompatible config changes).

1. While working, add each change under `## [Unreleased]` in `CHANGELOG.md` (in English).
2. Commit the work, then run `powershell -File toolselease.ps1 -Bump minor` (or `patch` / `major`, or `-Version X.Y.Z`). It checks the tree is clean (only `CHANGELOG.md` may be uncommitted), turns `Unreleased` into the new version with today's date, updates `VERSION` in `main.lua`, commits `Release vX.Y.Z`, tags it and builds the zip.
3. Output in `dist/` (ignored by git): `ReachTweaks-vX.Y.Z.zip` (a `ReachTweaks` folder with the two `.bat` files, `Launcher`, the mod, `CHANGELOG.md` and the player part of this README, i.e. everything before "Project layout") and `ReachTweaks-vX.Y.Z-notes.md` (only this version's changes, to paste on a download page).

The zip is built from the git tag, so local edits, logs, `tools/` and the RE notes never end up in it. `release.ps1` without arguments rebuilds the zip of the current version. Note: `config.lua` is shipped as committed (check `Debug` and `TestGuns` before a release).

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
- Sprint slide (`slide.lua`): chains short non-additive thrusters (only when none is active); keeps the lines by writing `bIsSprinting` directly (no `OnSprintStarted`, which would uncrouch); a head slide calls `StartButtonCrouch`, then `StopButtonCrouch` + `TryUncrouch` (+ `UnCrouch`) at the end; drives `Crouch Height` down faster; the crouch lock holds `bIsSprinting` on with walk `Speed` so the sprint input cannot start a sprint. The standing head height is learnt from the measured head height (the game's calibration offset did not match it after a level change); moves over 3 m in one tick are treated as teleports. Landing from a height dips the head relative to the feet (it looked like a quick duck and started a slide; the original game lands standing), so the head height is ignored while airborne (`bOnGround` false) and for `LandSettleMs` (500 ms) after landing; with Debug the log shows the dip (`[slide] landing settled`).
  Crouch button on landing (v1.8.0): the game ignores the press in the air, and the sprint restarted on landing (`jumpsprint.lua`, `StartSprint` → "On Sprint Started" → `TryUncrouch`) stands the player up, so a button slide started there ran with `bButtonCrouch` false (sliding standing; seen in the log as `buttonCrouch=false` during the slide). Any slide now calls `StartButtonCrouch` while `bButtonCrouch` is false (unless the button was pressed again during the slide; `[slide] not crouched by the game`); a press in the air is kept until the landing. `Slide.LandingCrouch = "stop"` instead crouches (re-asserted for 400 ms) and holds the crouch lock, which ends the sprint (`[slide] crouch on landing`).
- Sprint input: native `OnSprintInput` (bound to `SprintInput`): a non-zero value calls the `StartSprint` logic; a zero value calls `StopSprint` only when `bToggleSprint` (+0x314) is false. `UAtlasMovementComponent` has `LeftMotionController`, `RightMotionController` and `Headset` object properties, and `GetForwardInput` / `GetRightInput` return the stick axes.
- Sprint speed (`sprint.lua`): `RunSpeed` (+0x310, float) is what `StartSprint` copies into `Speed` (+0x31c); `WalkSpeed` is +0x30c. The Blueprint also has `SetRunSpeed` / `SetWalkSpeed` / `SetSpeed` / `GetSpeeds`, so a `RunSpeed` not written by the mod is taken as the game's new value and scaled again; a running sprint gets the new speed at once. Game values (2026-10-10): `RunSpeed` 490 cm/s, `WalkSpeed` 300 cm/s.
- Arm-swing sprint (`armsprint.lua`): per hand, swing = height + forward distance relative to the head; smoothed velocities, windowed RMS per hand (400 ms) and left/right correlation (running = both fast and negatively correlated). Stopping uses a separate 150 ms window per hand: the 400 ms RMS took ~0.9 s (+ `StopMs`) to fall below the threshold after the hands stopped; the short window falls in ~0.35 s, while a swinging hand stays above ~80 % of its RMS at the turning points. A stopped hand also blocks the start (otherwise the 400 ms window, still above the threshold, turned the gesture back on every tick). Calls `StartSprint` / `StopSprint`, ends only sprints it started, and does nothing while `Slide.HoldsSprint()` (slide or crouch lock).
  Measured in VR (2026-10-10): running arm swing ~220–320 cm/s per hand with correlation -0.65 to -0.9; ordinary hand movement stays below ~100 cm/s or near 0 / positive correlation, so the defaults (80 cm/s, -0.3, start 200 ms) leave a wide margin. Ducking into a slide flips the correlation positive, and the sprint is handed to the slide (`sprint handed to the slide` in the log) before the gesture ends.
- Slide braking (v1.10.0): `CalculateMovementInputVector()` (native, no parameters) returns the world-space stick direction, `HeadInput()` or `HandInput()` according to `UAtlasUserSettings::GetMovementInputType`; the deflection comes from `GetForwardInput` / `GetRightInput`. Within ~60° of straight back the slide loses `BrakeDecel` × deflection per second (`[slide] braking`, `end (braked)`).
- Climbing: `UAtlasMovementComponent::CustomMovementModes` (map) holds the movement mode objects; the climbing one derives from `UAtlasMovementModeClimbingBase`, whose `IsEitherHandClimbing()` / `IsHandClimbing(HandCoupler)` tell whether a hand is attached to a climbable surface (`HandAttachTransforms` keyed by coupler). `armsprint.lua` checks `IsEitherHandClimbing` on every mode each tick (`[armsprint] climbing: no sprint`; with Debug the mode classes are logged once).
- Jumps: the native code never calls `StopSprint` (only `execStopSprint`, i.e. Blueprint); the movement Blueprint ends the sprint around jumps (`[armsprint] sprint ended by the game` with the stick held and the arms swinging). `GetTimeSinceJump` = world time − `LastJumpTime` (+0x480), in seconds; `bOnGround` is the ground flag. `jumpsprint.lua` treats a sprint that ends in the air, within 300 ms of the jump or 400 ms of landing as ended by the jump: it calls `StartSprint` once in the air and again on landing if the stick is pushed (at most 3 restarts per jump). `armsprint.lua` keeps its sprint while `JumpSprint.Holds()`.
- Grapple (v1.11.0): the native `UAtlasGrapplingArmComponent` (AtlasGameplay, with `TryGrapple` / `FindGrappleableCoupler` in the PDB) is NOT used in game – only its class default exists. The grapple is the Blueprint component `BP_AtlasGrapplingArm_C` (left hand) / `BP_AtlasGrapplingArm_R_C` (right) on `BP_AtlasPlayer_C`, added by the `AtlasBPGrapplingArmFeature` game feature (not a subclass of the native class; found with `FindAllOf` on the BP names). Its variables: `GrabPressed`, `ActiveGrappleTargetActor` / `ActiveGrappleTargetComponent` / `ActiveGrappleTargetLocation`, `ReachDistance` (1200), `Minimum Reach Distance` (150), `MinReachRadius` (45), `ReachInterval` (0.033 s), `HandCoupleTimer` / `HandCouplerTimerMax` (8; already 8 when a target is found, not the trigger), `ActiveHandCoupler` (NDNTCouplerHand_Left/Right). On grapple the hand couples to the target's `NDNTShapedCoupler` (e.g. `BP_GrapplePoint_Cylinder_C`) and the movement mode becomes `BP_MovementMode_Grapple_C`. The Blueprint keeps the last target after grip is released and only searches while grip is held. `grapple.lua` blocks by setting `ReachDistance` to 1 cm while grip is held and the hand (motion controller forward) points more than `HandAimAngle` from the headset direction, or (after `SettleMs`, once the target is refreshed) the target is more than `ViewAngle` away; a target-blocked press unblocks when that frozen target comes into view; grip released / F7 OFF restores the reach. Pitfalls: judging the stale target or keeping the reach blocked without grip deadlocked the grapple; `PlayerCameraManager:GetCameraRotation` was not readable here (the headset component pose is used); reading every property of the BP component (dump) crashed the game (after `DroneSystem`, a SoftObjectProperty).
- Shield (v1.12.0): the shield in game is the pure Blueprint `BP_AtlasShield_C` (class chain `BP_AtlasShield_C < Actor`, game feature `AtlasBPShieldFeature`), NOT the native `AAtlasShield` (`AtlasCPPShieldFeature`, unused, like the native grapple): its components are `ProjectileMovement` (`ProjectileMovementComponent`), root `SM_Shield` (no physics simulation), `BP_ShieldResolver`, `LeftHandCoupler` / `RightHandCoupler`, `ClimbingCoupler`, `ShieldChargeComponent`, `ShieldTrail`. `shield.lua` samples the shield speed relative to the pawn from the actor locations while a hand holds it (`Player.HandsHolding`), takes the first movement above 100 cm/s within 400 ms of letting go as the throw and rescales `ProjectileMovement.Velocity` (writing the struct works). Measured (2026-10-11): the game throws at ~2000–2800 cm/s while the swing peak measured from the actor locations is only ~650–760 cm/s (the Blueprint scales the hand speed up), so `UsePeakSpeed` rarely applies and `ThrowSpeedMultiplier` does the work (user's choice: 1.75); between bounces the speed stays constant (no drag) and each bounce loses ~10–20 %, so `KeepSpeed` is off. With Debug the log shows the class chain, the Blueprint's property names (names only) and movement components once, then each throw and the flight speed at 50/150/400/1000 ms. For reference, the native `AAtlasShield`: throw speed = |`LocalVelocity`| of the release frame (hand speed relative to the pawn × `VelocityScale`, capped at `MaximumVelocity`), below `ThrowableVelocityThreshold` it auto-stows; in flight `UShieldState_Thrown::UpdateProjectilePhysics` loses ~10 %/s and sets `ProjectileGravityScale` 0 above 1000 cm/s, 1 below 500.
- Save list (v1.13.0): the slots are Blueprint widgets derived from the native `UAtlasSaveSlotWidget` (`/Script/Atlas`, `SaveSlotIndex`, `LevelDataTable`, natives `GetLevelDisplayName` / `GetButtonVisibility` / `GetSaveSlotIndex`) inside `UAtlasSaveGamePageWidget` (`SaveSlot0`..`SaveSlot4`, `SaveSlotWidgets`). The texts are written by the Blueprint in the interface event `IAtlasWidgetSaveInfoInterface::SetWidgetSaveDisplayInfo(FSaveDisplayInfo, bFoundSaveData)` (`/Script/AtlasSystem`); `FSaveDisplayInfo` = `CheckpointName`, `WorldName`, `Timestamp` (`FDateTime`, no reflected fields), `SaveSlotIndex`, from `UAtlasSaveSubsystem::GetSaveSlotDisplayInfos` (cached in its `CachedSaveFileDisplayInfo` map). Save files: `UAtlasSaveSubsystem::IterateSaveFiles` uses `ProjectSavedDir()/SaveGames/` + `GetFormattedSaveNameForSlot(i)` (`Format("{0}{1}", AutoSaveName@+0xc0, i)`) + `.sav` for `i < MaxSaveSlotCount@+0xbc`, i.e. `%LOCALAPPDATA%\Atlas\Saved\SaveGames\AtlasAutoSave<i>.sav`. `UAtlasSaveGame::CreateSnapshot` sets `Timestamp = FDateTime::Now()` (local time); in the file the `Timestamp` tag is at ~1.7 KB (UE 5.4 tag: name, `StructProperty`, `DateTime`, `/Script/CoreUObject`, 4 bytes, int32 size 8, flags byte, int64 ticks). `savetime.lua` reads the ticks from the file, finds the slot widgets (class learnt from hooks on the slot natives, or `FindObjects` on any subclass until a hook fires) and appends the time to the text block that contains the save's year and day. Verified in game (2026-10-11): the main menu slots are `/Game/AtlasProto/Art/UI/FrontendMenu/WBP_Frontend_SaveGameSlot.WBP_Frontend_SaveGameSlot_C` (learnt through `GetLevelDisplayName`; the page's `PopulateSaveSlotWidgetArray` also fires; the Blueprint event `SetWidgetSaveDisplayInfo` is hooked as an extra signal), texts = checkpoint name, date (`10 oct. 2026` with the Spanish culture) and slot number; before they are filled the slots show the placeholders `Save Name` / `Bloque de texto` / `0`. `RegisterHook` does not find `/Script/Atlas.AtlasSaveSubsystem:GetSaveSlotDisplayInfos`.
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
- Save time: the game shows the save date as if the local timestamp were converted to UTC (a save at 01:58 on 25 Jul, Madrid UTC+2, is listed as `24 jul. 2026`; all slots fit: displayed date = date of local time − UTC offset). Such a slot gets no time, because its date text does not contain the local day (`[savetime] slot N ... no date text found` in the log); only saves made between midnight and the UTC offset are affected.
