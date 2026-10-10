# ReachTweaks

A UE4SS Lua mod for **Reach** (nDreams, Steam AppID 3273480, Unreal Engine 5.4) that:

1. **Agile hands** – removes the sluggish "weight" of held weapons. The game ties a held weapon to the hand with a damped spring (`UAtlasThrowableResolver::ApplyWeight`); the mod makes that spring stiffer and critically damped while the weapon is held (×10 by default).
2. **Bow haptics** – vibration that grows while drawing, tension "clicks" at 25/50/75 %, a buzz at full draw and a kick on release.
3. **Firearm haptics** – a sharp kick with a fading tail on every shot, also on the supporting hand, plus scaling of the game's own weapon vibrations.
4. **Lighter bow body while drawing** – while the string is held the game averages the bow-hand and string-hand motions, so the bow body follows the bow hand slowly. The mod pulls the bow grip back towards the bow hand (position only; the string and the aim are left to the game).
5. **Fast startup** – skips the logo / health-warning splash and (optionally) the shader warm-up level.

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
| **F7** | Toggle all tweaks on/off to compare with the original game. A floating text appears in front of you; two short taps = ON, one long buzz = OFF |
| F5 / F6 | (Testing, `TestGuns = true`) spawn the next weapon / spawn the last one again |
| F8 | (Testing) cycle weight-stiffness levels: Mod config → Original → ×3 → ×10 → ×30 → ×100 |

## Configuration

Edit `ReachTweaks\config.lua` and relaunch with `Play_ReachTweaks.bat`.

| Setting | Meaning |
|---|---|
| `Hands.WeightStiffnessMultiplier` | 1 = original; higher = weapon sticks tighter to the hand |
| `Hands.WeightDamping` | 1.0 = no wobble (critical damping) |
| `Hands.Scope` | `"weapons"` (guns and bow) or `"all"` (any throwable) |
| `Bow.*` | Draw / click / full-draw / release vibration amplitudes |
| `BowBody.BodyFollow` | 0 = original, 1 = bow grip locked to the hand while drawing |
| `BowBody.BlendMs` | Fade time of the correction when grabbing/releasing the string |
| `Guns.FireAmplitude`, `FireDurationMs` | Shot kick and recoil duration |
| `Guns.NativeHapticScale` | Multiplies the game's own weapon vibrations |
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
  Scripts/bowbody.lua     bow body follow while drawing
  Scripts/guns.lua        firearm haptics
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
- Dead ends (no effect, the resolvers run with `MovementMethod = NoPhysics`): `ObjectPosition/RotationHeaviness`, `MagicNumber_*`, `ResolverLinear/AngularStiffness`, recoil springs, `ND.HandGrab.*` lerp settings.
- UE4SS quirks: `K2_GetComponentsByClass` fails (use `FindAllOf` + owner); `FindAllOf` is exact-class only; pawn hand properties are `NDComponentPath` structs (use the `...Reference` properties); never keep UObjects across ticks.

## Known issues / TODO

- **Bow body while drawing (in progress, `bowbody.lua`).** With only the grip held the bow follows the hand well; while the string is held the bow *body* follows the bow hand slowly. Constraint: do **not** change how the string behaves (do not touch `BowStringCouplerRef` weights).
  - Cause: `UNDNTResolverBasic::CalculateMotionInternal` (rva 0x46c6ca0) builds one motion per active coupler (weight = motion[+4] * motion[+8]) and `CombineMotionsWithMagnets` (rva 0x46cb280) blends them: per-motion weight = `pow(w / max(maxW, 1e-4), MagneticExponent@0xbc8)`; positions are a weighted average, rotations an incremental slerp. On the bow `MagneticExponent = 0` and both weights are equal, so grip and string motions weigh the same. `MagneticExponent` only helps if the weights differ, which requires changing the string coupler (rejected). `MagneticClippingCoefficient@0xbc4` is not read by these functions.
  - Dead end: `AAtlasBow::TickSmoothNock` and `SmoothAttach*` only ease the **arrow** onto the nock (`TEase` + `SetActorTransform` on the arrow owned by `SmoothAttachCouplerRef`, then `BP_OnArrowNocked`). `OnBowGrabbed` / `OnBowStringGrabbed` only fire BP events.
  - Fix: `bowbody.lua` learns the grip coupler (`BowCouplerRef`, a capsule component) position in the bow-hand motion controller space while only the grip is held and the hand is still, and while the string is held adds `BodyFollow` × the error as a world offset to the bow actor (teleport, no sweep). With `Debug = true` it logs `[bowbody]` lines once per second with the grip error (cm) while grip-only and while drawing; F7 switches between mod and original for A/B measurements.
- Height calibration screen is not skipped.
