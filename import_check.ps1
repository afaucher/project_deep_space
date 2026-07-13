# import_check.ps1 - Detect and fix stale Godot import caches before a
# headless run.
#
# Godot's headless CLI (--run-test, --check-only, etc.) trusts whatever is
# already sitting in .godot/imported/*.tres -- it does NOT compare source
# mtimes and reimport on load the way the editor's filesystem watcher does.
# Only an explicit `--headless --import` pass (or opening the project in the
# actual editor) regenerates that cache. So hand-editing any imported asset
# (a .dialogue file, most concretely -- see the M39 docking dialogue loop
# fix) outside the editor leaves every headless test silently running
# against the OLD compiled resource until someone thinks to reimport.
#
# This scans every *.import sidecar in the project. As a fast pre-filter it
# compares the source file's mtime against its compiled dest_files
# artifact(s); a dest that is missing or older than its source is a
# *candidate*. Candidates get confirmed against the real signal Godot itself
# uses to decide whether to reimport -- the source_md5 recorded in the
# artifact's own .md5 sidecar -- before declaring anything stale. Content
# hashing every asset on every run would be needlessly slow (hundreds of
# textures/audio files); the mtime pre-filter keeps the common "nothing
# changed" case cheap, and the hash confirmation avoids a permanent false
# "stale" (and a reimport pass on every single run forever after) from
# something merely touching a source file's mtime without changing its
# content -- e.g. a git checkout -- since Godot itself would skip rewriting
# an unchanged-hash artifact and its mtime would never catch up.
#
# Runs one `--headless --import` pass up front if anything is confirmed
# stale -- so a plain `git pull` / hand-edit followed immediately by
# test_runner.ps1 or build.ps1 just works instead of silently testing stale
# data (see the M39 docking dialogue loop fix, which is what surfaced this).
#
# Dot-source this from a caller that already has $PSScriptRoot and
# $godotPath defined, then call: Import-IfStale -ProjectRoot $PSScriptRoot -GodotPath $godotPath

function Test-ImportsStale {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    # A brand-NEW imported-type asset has no .import sidecar at all yet, so
    # the sidecar scan below can't see it -- ResourceLoader.exists() then
    # fails on it in every headless run until an import pass happens (this
    # bit for real when M43 added four new .dialogue files). Checked per
    # extension Godot actually imports in this project (.dialogue is the
    # only hand-authored one) rather than globbing everything, to avoid
    # false-staling extensions Godot ignores.
    $dialogueSources = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.dialogue" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.godot\\' }
    foreach ($src in $dialogueSources) {
        if (-not (Test-Path -LiteralPath "$($src.FullName).import")) { return $true }
    }

    $importFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.import" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.godot\\' }

    foreach ($imp in $importFiles) {
        $content = Get-Content -Raw -LiteralPath $imp.FullName -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $srcMatch = [regex]::Match($content, 'source_file="([^"]+)"')
        if (-not $srcMatch.Success) { continue }
        $srcPath = Join-Path $ProjectRoot ($srcMatch.Groups[1].Value -replace '^res://', '')
        if (-not (Test-Path -LiteralPath $srcPath)) { continue }
        $srcTime = (Get-Item -LiteralPath $srcPath).LastWriteTimeUtc

        # Every compiled output path mentioned in the sidecar (dest_files=[...]
        # and the [remap] path= line both point into .godot/imported/).
        $destMatches = [regex]::Matches($content, '"(res://\.godot/imported/[^"]+)"')
        if ($destMatches.Count -eq 0) { continue }

        foreach ($d in $destMatches) {
            $destPath = Join-Path $ProjectRoot ($d.Groups[1].Value -replace '^res://', '')
            if (-not (Test-Path -LiteralPath $destPath)) { return $true }
            if ($srcTime -le (Get-Item -LiteralPath $destPath).LastWriteTimeUtc) { continue }

            # mtime says "maybe stale" -- confirm against the actual content
            # hash before trusting it.
            $md5Path = [System.IO.Path]::ChangeExtension($destPath, ".md5")
            if (-not (Test-Path -LiteralPath $md5Path)) { return $true }
            $md5Content = Get-Content -Raw -LiteralPath $md5Path -ErrorAction SilentlyContinue
            $recordedMatch = [regex]::Match($md5Content, 'source_md5="([^"]+)"')
            if (-not $recordedMatch.Success) { return $true }

            $actualHash = (Get-FileHash -Algorithm MD5 -LiteralPath $srcPath).Hash
            if ($actualHash -ne $recordedMatch.Groups[1].Value) { return $true }
        }
    }

    return $false
}

function Import-IfStale {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$GodotPath
    )

    if (Test-ImportsStale -ProjectRoot $ProjectRoot) {
        Write-Host "Stale imported resource cache detected (an imported asset -- e.g. a .dialogue file -- changed since it was last compiled). Reimporting..." -ForegroundColor Yellow
        & $GodotPath --headless --path "$ProjectRoot" --import | Out-Null
        Write-Host "Reimport complete." -ForegroundColor Yellow
    }
}
