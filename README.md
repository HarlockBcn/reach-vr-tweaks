# ReachTweaks

A UE4SS Lua mod for **Reach** (nDreams, Steam AppID 3273480, Unreal Engine 5.4) that:

1. **Agile hands** – removes the sluggish "weight" of held weapons. The game ties a held weapon to the hand with a damped spring (`UAtlasThrowableResolver::ApplyWeight`); the mod makes that spring stiffer and critically damped while the weapon is held (×10 by default).
2. **Bow haptics** – vibration that grows while drawing, tension "clicks" at 25/50/75 %, a buzz at full draw and a kick on release.
3. **Firearm haptics** – a sharp kick with a fading tail on every shot, also on the supporting hand, plus scaling of the game's own weapon vibrations.
4. **Fast startup** – skips the logo / health-warning splash and (optionally) the shader warm-up level.

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

- **Bow body is sluggish while the string is drawn (next task).** With only the grip held, the bow follows the hand well. While the string is held with the other hand, the bow *body* follows the bow hand slowly. Goal: make the bow body lighter/more agile while drawing, configurable, **without changing how the string behaves** (do not touch `BowStringCouplerRef` weights).
  - Known facts: `BP_BowResolver_C` derives from `UNDNTResolverBasic` (no weight spring; `HandCouplingSmoothingSpeed = 0.3` only acts right after grabbing). Motion `Weighting` is always 1.0. Tick-order prerequisites had no effect. When both bow couplers are active, `UNDNTResolverBasic::CombineMotionsWithMagnets` (rva 0x46cb280) averages the motions; per-motion weight = `pow(motion[+4] / max(param, eps), MagneticExponent@0xbc8)`, and `MagneticExponent = 0` on the bow, so grip and string motions weigh the same.
  - Leads: (1) `AAtlasBow` smooth-attach/nock smoothing: `SmoothAttachDuration`, `SmoothAttachBlendDuration`, `SmoothAttachExponent`, `SmoothAttachEasingFunc`, `SmoothAttachCouplerRef`, native `TickSmoothNock`; (2) bias the combiner towards the grip motion via `MagneticExponent` / `MagneticClippingCoefficient` on the bow resolver (needs the meaning of motion field +4 and the float param); (3) measure with `lagprobe.lua` (bow-hand controller-hand distance with and without the string held: ~16-22 cm vs ~13 cm at rest).
- Height calibration screen is not skipped.
