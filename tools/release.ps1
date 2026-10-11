<#
  ReachTweaks - release builder

  Bumps the version, commits, tags and builds the player zip in dist\.
  The zip is built from the git tag (committed files only), so a release
  never contains local edits, logs or reverse-engineering files.

  config.lua: the release ships the development config.lua as it is in the
  working tree (uncommitted edits included), with the developer settings
  Debug, TestGuns, Intro.SkipLogos and Intro.SkipShaderWarmup forced to
  false. That version is what the release commit stores; the working tree
  copy keeps the development values.

  Usage (from the repo root):
    powershell -File tools\release.ps1 -Bump minor     new feature   1.13.0 -> 1.14.0
    powershell -File tools\release.ps1 -Bump patch     bug fix       1.13.0 -> 1.13.1
    powershell -File tools\release.ps1 -Bump major     breaking      1.13.0 -> 2.0.0
    powershell -File tools\release.ps1 -Version 1.20.0 explicit version
    powershell -File tools\release.ps1                 rebuild the zip of the current version

  Before a release: write the changes under "## [Unreleased]" in CHANGELOG.md
  and commit (only CHANGELOG.md and config.lua may be left uncommitted; both
  go into the release commit, config.lua with the release settings).
#>
param(
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
# Read git's UTF-8 output correctly (changelog text)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root      = Split-Path -Parent $PSScriptRoot
$MainLua   = Join-Path $Root 'ReachTweaks\Scripts\main.lua'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$ConfigRel = 'ReachTweaks/config.lua'
$Config    = Join-Path $Root 'ReachTweaks\config.lua'
# Developer settings that are always off in a release
$ReleaseOff = @('Debug', 'TestGuns', 'SkipLogos', 'SkipShaderWarmup')
$Dist      = Join-Path $Root 'dist'
# What a player needs; everything else (tools, RE notes) stays out
$Payload   = @('Play_ReachTweaks.bat', 'Uninstall_ReachTweaks.bat', 'Launcher', 'ReachTweaks', 'CHANGELOG.md', 'README.md')
$Utf8      = New-Object Text.UTF8Encoding($false)

function Info($m) { Write-Host "[release] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[release] $m" -ForegroundColor Green }

function Invoke-Git {
    # Continue: git writes warnings to stderr, which 'Stop' would turn into errors
    $ErrorActionPreference = 'Continue'
    $out = & git -C $Root @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $out" }
    return @($out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
}

function Test-GitPath($rev, $path) {
    $ErrorActionPreference = 'Continue'
    & git -C $Root cat-file -e "${rev}:$path" 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-CurrentVersion {
    $m = [regex]::Match([IO.File]::ReadAllText($MainLua), 'local VERSION = "(\d+\.\d+\.\d+)"')
    if (-not $m.Success) { throw 'VERSION not found in main.lua' }
    return $m.Groups[1].Value
}

function Get-NextVersion($cur) {
    if ($Version) {
        if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version '$Version' (expected X.Y.Z)" }
        if ([version]$Version -le [version]$cur) { throw "Version $Version is not above $cur" }
        return $Version
    }
    $v = [version]$cur
    switch ($Bump) {
        'major' { return "$($v.Major + 1).0.0" }
        'minor' { return "$($v.Major).$($v.Minor + 1).0" }
        'patch' { return "$($v.Major).$($v.Minor).$($v.Build + 1)" }
    }
}

# config.lua text with the developer settings set to false (each must be
# found exactly once, so a renamed setting stops the release)
function Set-ReleaseFlags($text) {
    foreach ($key in $ReleaseOff) {
        $re = "(?m)^(\s*$key\s*=\s*)(true|false)\b"
        $n = [regex]::Matches($text, $re).Count
        if ($n -ne 1) { throw "config.lua: expected one '$key = true/false' line, found $n" }
        $text = [regex]::Replace($text, $re, '${1}false')
    }
    return $text
}

# Text of one version's section (without its heading)
function Get-ChangelogSection($text, $name) {
    $m = [regex]::Match($text, "(?ms)^## \[$([regex]::Escape($name))\][^\n]*\n(.*?)(?=^## \[|\z)")
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Trim()
}

function New-Release($cur, $new) {
    $dirty = Invoke-Git status --porcelain --untracked-files=no
    $dirty = @($dirty | Where-Object { $_ -and $_ -notmatch '\s(CHANGELOG\.md|ReachTweaks/config\.lua)$' })
    if ($dirty.Count) { throw "Commit or discard these changes first:`n$($dirty -join "`n")" }
    if (Invoke-Git tag --list "v$new") { throw "Tag v$new already exists" }

    $log = [IO.File]::ReadAllText($Changelog)
    $notes = Get-ChangelogSection $log 'Unreleased'
    if (-not $notes) { throw 'CHANGELOG.md: the "## [Unreleased]" section is empty. Describe the changes there first.' }

    $date = Get-Date -Format 'yyyy-MM-dd'
    $log = [regex]::Replace($log, '(?m)^## \[Unreleased\][^\n]*\n', "## [Unreleased]`n`n## [$new] - $date`n", 1)
    [IO.File]::WriteAllText($Changelog, $log, $Utf8)

    $lua = [IO.File]::ReadAllText($MainLua)
    $lua = $lua -replace 'local VERSION = "\d+\.\d+\.\d+"', "local VERSION = `"$new`""
    [IO.File]::WriteAllText($MainLua, $lua, $Utf8)

    Invoke-Git add -- $Changelog $MainLua | Out-Null

    # Release config: the working copy with the developer settings off, staged
    # directly (the working tree file keeps the development values)
    $cfg = Set-ReleaseFlags ([IO.File]::ReadAllText($Config))
    $tmpCfg = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmpCfg, $cfg, $Utf8)
        $hash = (Invoke-Git hash-object -w "--path=$ConfigRel" -- $tmpCfg)[0]
        Invoke-Git update-index --cacheinfo "100644,$hash,$ConfigRel" | Out-Null
    } finally {
        Remove-Item $tmpCfg -ErrorAction SilentlyContinue
    }
    Invoke-Git commit -q -m "Release v$new" -m $notes | Out-Null
    Invoke-Git tag -a "v$new" -m "ReachTweaks v$new" -m $notes | Out-Null
    Ok "Version $cur -> $new, committed and tagged v$new"
}

function Build-Zip($ver) {
    $tag = "v$ver"
    if (-not (Invoke-Git tag --list $tag)) { throw "Tag $tag not found. Create the release with -Bump or -Version." }
    $paths = @($Payload | Where-Object { Test-GitPath $tag $_ })

    New-Item -ItemType Directory -Force $Dist | Out-Null
    $name  = "ReachTweaks-v$ver"
    $tmp   = Join-Path ([IO.Path]::GetTempPath()) ("reachtweaks_" + [guid]::NewGuid())
    $stage = Join-Path $tmp 'ReachTweaks'
    $raw   = Join-Path $tmp 'raw.zip'
    New-Item -ItemType Directory -Force $stage | Out-Null
    try {
        # git applies .gitattributes (CRLF for .bat/.ps1) when exporting
        Invoke-Git archive --format=zip -o $raw $tag -- @paths | Out-Null
        Expand-Archive -Path $raw -DestinationPath $stage -Force
        Remove-Item $raw

        # Developer settings off (also when rebuilding an older tag)
        $cfgFile = Join-Path $stage 'ReachTweaks\config.lua'
        if (Test-Path $cfgFile) {
            [IO.File]::WriteAllText($cfgFile, (Set-ReleaseFlags ([IO.File]::ReadAllText($cfgFile))), $Utf8)
        }

        # Player README: everything before the developer sections
        $readme = Join-Path $stage 'README.md'
        if (Test-Path $readme) {
            $txt = [IO.File]::ReadAllText($readme)
            $cut = $txt.IndexOf("`n## Project layout")
            if ($cut -gt 0) { $txt = $txt.Substring(0, $cut).TrimEnd() + "`n" }
            $txt = $txt -replace '^# ReachTweaks', "# ReachTweaks v$ver"
            [IO.File]::WriteAllText($readme, $txt, $Utf8)
        }

        # Timestamps = build time: the launcher copies the installed config.lua
        # back over the package one only when the installed one is newer
        $now = Get-Date
        $files = Get-ChildItem $stage -Recurse -File
        $files | ForEach-Object { $_.LastWriteTime = $now }

        # Entries written one by one: ZipFile.CreateFromDirectory on .NET Framework
        # stores "\" in the paths, which some unzip tools do not understand
        $zip = Join-Path $Dist "$name.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in $files) {
                $entry = 'ReachTweaks/' + $f.FullName.Substring($stage.Length + 1).Replace('\', '/')
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $entry,
                    [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # This version's notes alone, ready to paste on a download page
    $notes = $null
    if (Test-GitPath $tag 'CHANGELOG.md') {
        $notes = Get-ChangelogSection ((Invoke-Git show "${tag}:CHANGELOG.md") -join "`n") $ver
    }
    if ($notes) {
        [IO.File]::WriteAllText((Join-Path $Dist "$name-notes.md"), "# ReachTweaks v$ver`n`n$notes`n", $Utf8)
    }

    Ok ("Built dist\{0}.zip ({1:N0} KB)" -f $name, ((Get-Item $zip).Length / 1KB))
    if ($notes) { Write-Host "`n$notes`n" }
}

# ------------------------------------------------------------------
try {
    $cur = Get-CurrentVersion
    if ($Bump -or $Version) {
        $new = Get-NextVersion $cur
        New-Release $cur $new
        Build-Zip $new
    } else {
        Info "No -Bump/-Version: rebuilding the zip of the current version $cur"
        Build-Zip $cur
    }
    exit 0
} catch {
    Write-Host "[release] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
