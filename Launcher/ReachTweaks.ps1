<#
  ReachTweaks - launcher / installer
  - Finds Reach (Steam AppID 3273480)
  - Installs UE4SS the first time (official GitHub release, SHA-256 verified)
  - Copies/updates the ReachTweaks mod
  - Launches the game through Steam

  Usage:
    ReachTweaks.ps1              install/update and launch
    ReachTweaks.ps1 -NoLaunch    install/update only
    ReachTweaks.ps1 -Uninstall   remove everything this launcher installed
#>
param(
    [switch]$Uninstall,
    [switch]$NoLaunch,
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$AppId       = 3273480
$ModName     = 'ReachTweaks'
$Ue4ssApi    = 'https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$ModSource   = Join-Path $PackageRoot $ModName
$ManifestName = 'ReachTweaks.install.json'

function Info($m)  { Write-Host "[ReachTweaks] $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "[ReachTweaks] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[ReachTweaks] $m" -ForegroundColor Yellow }

function Get-SteamLibraries {
    $libs = @()
    $steam = $null
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
        try {
            $p = Get-ItemProperty $k -ErrorAction Stop
            if ($p.SteamPath)   { $steam = $p.SteamPath; break }
            if ($p.InstallPath) { $steam = $p.InstallPath; break }
        } catch {}
    }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libs += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    $libs += 'D:\SteamLibrary'
    return $libs | Select-Object -Unique
}

function Find-Game {
    if ($GameDir) { $cands = @($GameDir) } else {
        $cands = Get-SteamLibraries | ForEach-Object { Join-Path $_ 'steamapps\common\Atlas' }
    }
    foreach ($c in $cands) {
        $bin = Join-Path $c 'Atlas\Binaries\Win64'
        if (Test-Path (Join-Path $bin 'Atlas-Win64-Shipping.exe')) { return $bin }
    }
    throw 'Reach not found. Use: ReachTweaks.ps1 -GameDir "X:\path\steamapps\common\Atlas"'
}

function Get-Ue4ssModsDir($bin) {
    if (Test-Path (Join-Path $bin 'ue4ss\UE4SS.dll')) { return Join-Path $bin 'ue4ss\Mods' }
    if (Test-Path (Join-Path $bin 'UE4SS.dll'))       { return Join-Path $bin 'Mods' }
    return $null
}

function Get-Ue4ssZip {
    # 1) Local zip next to the launcher (offline install)
    $local = Get-ChildItem $PackageRoot -Filter 'UE4SS_v*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($local) { Info "Using local UE4SS: $($local.Name)"; return $local.FullName }

    # 2) Official release
    Info 'Checking the latest UE4SS release on GitHub...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri $Ue4ssApi -Headers @{ 'User-Agent' = 'ReachTweaks' }
    $asset = $rel.assets | Where-Object { $_.name -match '^UE4SS_v.*\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'UE4SS zip not found in the release.' }
    $dest = Join-Path ([IO.Path]::GetTempPath()) $asset.name
    Info ("Downloading {0} ({1:N1} MB)..." -f $asset.name, ($asset.size / 1MB))
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing -Headers @{ 'User-Agent' = 'ReachTweaks' }
    if ($asset.digest -and $asset.digest -match '^sha256:(.+)$') {
        $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
        if ($hash -ne $Matches[1].ToUpper()) {
            Remove-Item $dest -Force
            throw 'UE4SS SHA-256 mismatch. Download aborted.'
        }
        Ok 'SHA-256 verified.'
    } else {
        Warn 'The release does not publish a SHA-256; could not verify.'
    }
    return $dest
}

function Set-IniValue($file, $key, $value) {
    if (-not (Test-Path $file)) { return }
    $txt = Get-Content $file -Raw
    $pattern = "(?m)^(\s*$([regex]::Escape($key))\s*=\s*).*$"
    if ($txt -match $pattern) {
        $txt = [regex]::Replace($txt, $pattern, "`${1}$value")
        [IO.File]::WriteAllText($file, $txt)
    }
}

function Install-Ue4ss($bin, $manifest) {
    $zip = Get-Ue4ssZip
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ue4ss_" + [guid]::NewGuid())
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $added = @()
    foreach ($item in Get-ChildItem $tmp) {
        $target = Join-Path $bin $item.Name
        if (-not (Test-Path $target)) { $added += $item.Name }
        Copy-Item $item.FullName $bin -Recurse -Force
    }
    Remove-Item $tmp -Recurse -Force
    $manifest.ue4ssItems = $added
    $manifest.ue4ssInstalledByUs = $true

    # No GUI console (it opens another window, annoying in VR)
    $ini = Get-ChildItem $bin -Recurse -Filter 'UE4SS-settings.ini' | Select-Object -First 1
    if ($ini) {
        Set-IniValue $ini.FullName 'GuiConsoleEnabled' '0'
        Set-IniValue $ini.FullName 'GuiConsoleVisible' '0'
        Set-IniValue $ini.FullName 'ConsoleEnabled' '0'
    }
    Ok 'UE4SS installed.'
}

function Install-Mod($bin, $manifest) {
    $modsDir = Get-Ue4ssModsDir $bin
    if (-not $modsDir) { throw 'UE4SS is not installed correctly.' }
    $dst = Join-Path $modsDir $ModName

    # Keep the user's config if it was edited in the game folder
    $cfgDst = Join-Path $dst 'config.lua'
    $cfgSrc = Join-Path $ModSource 'config.lua'
    if ((Test-Path $cfgDst) -and ((Get-Item $cfgDst).LastWriteTime -gt (Get-Item $cfgSrc).LastWriteTime)) {
        Copy-Item $cfgDst $cfgSrc -Force
        Info 'The game copy of config.lua was newer; copied back to the package.'
    }

    # Keep the mod log across reinstalls
    $logDst = Join-Path $dst 'ReachTweaks.log'
    $logBak = $null
    if (Test-Path $logDst) {
        $logBak = Join-Path ([IO.Path]::GetTempPath()) 'ReachTweaks.log.bak'
        Copy-Item $logDst $logBak -Force
    }
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $ModSource $dst -Recurse -Force
    if ($logBak) { Move-Item $logBak $logDst -Force }
    # Lets the mod re-read the package config too (F7 reload), so either copy can be edited in game
    [IO.File]::WriteAllText((Join-Path $dst 'package_config.txt'), (Resolve-Path $cfgSrc).Path)
    $modsTxt = Join-Path $modsDir 'mods.txt'
    if (Test-Path $modsTxt) {
        # Only ReachTweaks: the UE4SS sample mods (console, cheats...)
        # can crash the game and are not needed.
        $lines = Get-Content $modsTxt | Where-Object { $_ -notmatch "^\s*$ModName\s*:" } |
            ForEach-Object { $_ -replace '^(\s*[^;\s][^:]*?)\s*:\s*1\s*$', '$1 : 0' }
        $lines = @("$ModName : 1") + $lines
        Set-Content $modsTxt $lines -Encoding ASCII
    } else {
        New-Item -ItemType File -Path (Join-Path $dst 'enabled.txt') -Force | Out-Null
    }
    $manifest.modDir = $dst
    Ok "Mod copied to $dst"
}

function Read-Manifest($bin) {
    $f = Join-Path $bin $ManifestName
    if (Test-Path $f) { return Get-Content $f -Raw | ConvertFrom-Json }
    return [pscustomobject]@{ ue4ssInstalledByUs = $false; ue4ssItems = @(); modDir = $null }
}

function Save-Manifest($bin, $m) {
    $m | ConvertTo-Json | Set-Content (Join-Path $bin $ManifestName) -Encoding UTF8
}

function Uninstall-All($bin) {
    $m = Read-Manifest $bin
    $modsDir = Get-Ue4ssModsDir $bin
    if ($modsDir) {
        $d = Join-Path $modsDir $ModName
        if (Test-Path $d) { Remove-Item $d -Recurse -Force; Ok 'Mod removed.' }
        $modsTxt = Join-Path $modsDir 'mods.txt'
        if (Test-Path $modsTxt) {
            (Get-Content $modsTxt) | Where-Object { $_ -notmatch "^\s*$ModName\s*:" } | Set-Content $modsTxt -Encoding ASCII
        }
    }
    if ($m.ue4ssInstalledByUs) {
        foreach ($i in $m.ue4ssItems) {
            $p = Join-Path $bin $i
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
        Ok 'UE4SS removed.'
    } else {
        Warn 'UE4SS was not installed by this launcher; leaving it as is.'
    }
    $mf = Join-Path $bin $ManifestName
    if (Test-Path $mf) { Remove-Item $mf -Force }
    Ok 'Uninstall complete. Reach is back to its original state.'
}

function Wait-ForModLog($bin) {
    $log = Get-ChildItem $bin -Recurse -Filter 'UE4SS.log' -ErrorAction SilentlyContinue | Select-Object -First 1
    $logPath = if ($log) { $log.FullName } else { Join-Path (Split-Path (Get-Ue4ssModsDir $bin)) 'UE4SS.log' }
    $start = Get-Date
    Info 'Waiting for the game to start (max. 2 min)...'
    while (((Get-Date) - $start).TotalSeconds -lt 120) {
        Start-Sleep -Seconds 3
        if ((Test-Path $logPath) -and (Get-Item $logPath).LastWriteTime -gt $start) {
            $txt = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
            if ($txt -match '\[ReachTweaks\] ReachTweaks .* loaded') { Ok 'Mod active in game. Enjoy!'; return }
            if ($txt -match '\[ReachTweaks\] ERROR') { Warn "The mod reported errors; check $logPath" ; return }
        }
    }
    Warn "Could not confirm the mod loaded. Check $logPath"
}

# ------------------------------------------------------------------
try {
    $bin = Find-Game
    Info "Reach found at $bin"

    if (Get-Process -Name 'Atlas-Win64-Shipping' -ErrorAction SilentlyContinue) {
        throw 'Reach is running. Close it before installing or uninstalling.'
    }

    if ($Uninstall) { Uninstall-All $bin; exit 0 }

    $manifest = Read-Manifest $bin
    if (-not (Get-Ue4ssModsDir $bin)) { Install-Ue4ss $bin $manifest }
    Install-Mod $bin $manifest
    Save-Manifest $bin $manifest

    if (-not $NoLaunch) {
        Info 'Launching Reach through Steam...'
        Start-Process "steam://rungameid/$AppId"
        Wait-ForModLog $bin
    }
    exit 0
} catch {
    Write-Host "[ReachTweaks] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
