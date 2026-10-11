# ReachTweaks – notes for Claude

UE4SS Lua mod + PowerShell launcher for Reach (nDreams, UE 5.4.2, Steam AppID 3273480). `README.md` is the reference: features, config, project layout, release flow, reverse-engineering (RE) notes and known issues. Read the relevant README section before changing a module.

## Language

Everything in the project is in English: code, comments, config and its comments, log lines, in-game texts, launcher messages, file names, commit messages, CHANGELOG.

## Paths and workflow

- Game: `D:\SteamLibrary\steamapps\common\Atlas`; mod installed in `Atlas\Binaries\Win64\ue4ss\Mods\ReachTweaks`.
- `Launcher\ReachTweaks.ps1 -NoLaunch` reinstalls the mod into the game (fails while the game is running).
- Mod log: `...\ue4ss\Mods\ReachTweaks\ReachTweaks.log` (appended per session; only with `Debug = true`). Verify behaviour from the log; with Debug it has `[perf]` lines every 10 s.
- `config.lua`: the package copy (`ReachTweaks/config.lua`) is the one being edited. F7 OFF/ON in game re-reads it; `Enabled` and `Debug` need a restart.
- Offline check without the game: Python `lupa` (Lua 5.4) is installed; compile every script with `load()` and, for logic changes, run `main.lua` against mocked UE4SS globals (`FindAllOf`, `StaticFindObject`, `RegisterHook`, `LoopInGameThreadAfterFrames`, ...).
- Every feature or fix gets a line under `## [Unreleased]` in `CHANGELOG.md`.
- Releases: `tools/release.ps1 -Bump minor|patch|major`. It ships the working-tree `config.lua` with `Debug`, `TestGuns`, `Intro.SkipLogos` and `Intro.SkipShaderWarmup` forced to `false` (`$ReleaseOff`); the working copy keeps its development values. A new developer-only setting must be added to `$ReleaseOff`.

## Hard rules for mod code

- **Game thread only.** `RegisterKeyBind` and `ExecuteWithDelay` callbacks run on UE4SS threads and crashed the game; keys are polled (`keys.lua`), delays use `Util.After`.
- **Never keep a UObject across ticks** (stale wrappers crashed the game). Keep keys (`Util.Key`) or object paths and look the object up again (`StaticFindObject(path)`).
- **No `FindAllOf` / `FindObjects` in per-tick code or on short timers**: they walk the whole object list (milliseconds). Find once and keep the path (`Util.FindOwnedByCached`), or discover objects from events (e.g. a hand grabbing them).
- Per-tick pawn data: `Player.GetPawn()`, `Player.Movement()`, `Player.PawnKey()` (cached for one tick between `Player.BeginFrame`/`EndFrame`).
- Avoid calls that fail every tick (a failed `pcall` builds an error each time); find which objects answer once and only call those.
- Lua pitfall: `cond and nil or x` is always `x`.
- Never dump every property value of a Blueprint object (crashed the game); list names only.

## UE4SS / game facts

- `K2_GetComponentsByClass` fails: use `FindAllOf(class) + owner` (`Util.FindOwnedBy`). `FindAllOf` is exact-class only; Blueprint classes by short name (`"BP_AtlasBow_C"`).
- Pawn hand properties are `NDComponentPath` structs: use the matching `...Reference` property.
- nDreams often ships a native class but uses a pure Blueprint one in game (grapple, shield): check the class chain in game before relying on PDB analysis.
- Stick axes cannot be faked from Lua (native `FEnhancedInputActionValueBinding` on the movement component at +0x260/+0x270).
- Weapon heaviness = `UAtlasThrowableResolver::ApplyWeight` spring. Dead ends: see README RE notes; also tick prerequisites on `ANDNTConnectionArbiter`. The bow resolver `BP_BowResolver_C` (`UNDNTResolverBasic`) always has motion `Weighting` 1.

## Reverse engineering

The game ships `Atlas-Win64-Shipping.pdb`; helpers are in `tools/` (`pdbpub.py` – regenerate `publics.txt` into a scratch folder first, `dis.py`, `propoff.py`, `u16.py`, `dmp.py` for crash minidumps in `%LOCALAPPDATA%\Atlas\Saved\Crashes`). Grepping the PDB publics for `Z_Construct_UClass_*_Statics::NewProp_*`, `Z_Construct_UFunction_*` and `<Module>\UHT\<File>.gen.cpp` gives class / property / function / module maps; `DependentSingletons` gives parent classes.
