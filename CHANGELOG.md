# Changelog

All notable changes to ReachTweaks. Versions follow [Semantic Versioning](https://semver.org/):
MAJOR for incompatible changes (e.g. config settings renamed or removed), MINOR for new features,
PATCH for bug fixes and tuning.

Add new entries under **Unreleased**; `tools/release.ps1` turns that section into the next version.

## [Unreleased]
### Changed
- Performance: no more whole-object-list searches during play. Before, the mod searched every object in the game every frame while holding the bow (string pull), 20 times a second while holding a weapon (agile hands), every frame in the main menu (arm-swing sprint), and every 2-3 s for the shield, the gun haptic data and the grapple. Components are now found once and remembered by path; the shield is found when you grab it.
- Performance: the pawn and its movement component are read once per frame instead of once per module; held-object refresh (backed by the grab/release hooks), keyboard polling and level checks run less often; the climbing check only queries the climbing movement mode.
- Debug: `[perf]` lines in the log every 10 s with the mod's time per frame and per module, and how many frames took 2 ms or more.

### Fixed
- Save time: the fallback search for save slot widgets (the whole object list) ran every 3 s for the entire session instead of only until the save list was seen.
- `Guns.NativeHapticScale` had no effect (it looked for the wrong data class). It now scales the data of the gun you grab. The default is now 1.0 so the feel does not change; set 1.5 for stronger game vibrations.

## [1.13.0] - 2026-10-11
### Added
- Save time in the save list: the menu's save slots show the time of each save next to its date (`SaveTime.Format`, `SaveTime.Separator`).

### Known issues
- Saves made between midnight and your UTC offset get no time (the game itself shows them with the previous day).

## [1.12.0] - 2026-10-11
### Added
- Shield throw speed: the thrown shield flies faster (`Shield.ThrowSpeedMultiplier`, default 1.75, and `Shield.MinThrowSpeed`); optional use of the swing's peak speed and no slowdown in flight.

## [1.11.0] - 2026-10-11
### Added
- Grapple only in view: the grapple only latches onto targets you can see; pressing grip with the hand pointing behind you or at a target outside the headset view does nothing (`GrappleView`).

## [1.10.0] - 2026-10-11
### Added
- Brake the sprint slide by pushing the stick backwards (`Slide.BrakeWithStick`, `BrakeDecel`, `BrakeMinStick`, `BrakeStopSpeed`).

## [1.9.0] - 2026-10-11
### Fixed
- Moving the hands while climbing no longer starts the arm-swing sprint (`ArmSprint.BlockWhileClimbing`, `ClimbGraceMs`).

## [1.8.0] - 2026-10-11
### Added
- Crouch on landing from a sprint jump: choose a crouched slide or crouch and stop running (`Slide.LandingCrouch`, `LandingWindowMs`).

### Fixed
- Pressing crouch while landing from a jump no longer slides you standing up.

## [1.7.0] - 2026-10-11
### Added
- Sprint through jumps: the sprint (speed and speed lines) is kept in the air and after landing while the stick is pushed (`JumpSprint`).

### Fixed
- Landing from a height no longer starts a head slide (`Slide.LandSettleMs`).

## [1.6.0] - 2026-10-10
### Added
- Sprint speed multiplier (`Sprint.SpeedMultiplier`).

### Changed
- The arm-swing sprint stops faster after the arms stop (~0.45 s instead of ~1 s, `ArmSprint.StillMs`).

### Fixed
- The arm-swing sprint no longer flickers on and off right after stopping.

## [1.5.0] - 2026-10-10
### Added
- Arm-swing sprint: swinging both arms like a runner while moving with the stick starts the sprint (`ArmSprint`).

## [1.4.0] - 2026-10-10
### Added
- Sprint slide: crouching (ducking your head or pressing crouch) while sprinting slides you a few metres (`Slide`).
- No sprinting while crouched.
- F7 OFF/ON re-reads `config.lua`, so settings can be tuned while playing.

### Fixed
- Crashes when pressing F5–F8.

## [1.3.0] - 2026-10-10
### Added
- Experimental bow body follow while drawing (`BowBody`, disabled by default: no visible effect yet).

## [1.2.0] - 2026-10-10
First version under version control.

### Added
- Agile hands: held weapons follow the hand without the sluggish "weight" (`Hands`).
- Bow haptics: draw vibration, tension clicks, full-draw buzz and release kick (`Bow`).
- Firearm haptics: shot kick on both hands and scaling of the game's weapon vibrations (`Guns`).
- Fast startup: skips the logo / health-warning screens and optionally the shader warm-up (`Intro`).
- F7 toggles all tweaks on/off to compare with the original game.
- Launcher: installs UE4SS (SHA-256 verified) and the mod, launches the game; uninstaller.
