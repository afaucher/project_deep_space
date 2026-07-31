# build.ps1 - Build and package Project Deep Space
param (
    [switch]$Force
)
function Normalize-ProcessPath {
    if ($env:PATH) {
        $env:Path = $env:PATH
        [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
    }
}

Normalize-ProcessPath

Write-Host "Stopping any running instances of the game..." -ForegroundColor Yellow
Stop-Process -Name "ProjectDeepSpace" -ErrorAction SilentlyContinue

$godotPath = "$PSScriptRoot\Godot_v4.4.1-stable_win64.exe"
$buildDir = "$PSScriptRoot\build"
$windowsBuildDir = "$buildDir\windows"
$exportPath = "$windowsBuildDir\ProjectDeepSpace.exe"
$buildVersion = Get-Date -Format "yyyy-MM-dd.HHmmss"

Write-Host "Build Version: $buildVersion" -ForegroundColor Cyan

# 1. Verification
if (-not (Test-Path $godotPath)) {
    Write-Error "Godot executable not found at $godotPath."
    exit 1
}

# Reimport up front, once, before spawning the parallel test runners below --
# each of those also self-checks (test_runner.ps1), but by then this pass
# will have already left nothing stale, so they're just a cheap no-op scan
# rather than N processes racing to reimport into .godot/imported/.
. "$PSScriptRoot\import_check.ps1"
Import-IfStale -ProjectRoot $PSScriptRoot -GodotPath $godotPath

# 2. Syntax Validation
Write-Host "Running GDScript syntax validation..." -ForegroundColor Cyan
$scriptFiles = Get-ChildItem -Path "$PSScriptRoot\scripts" -Recurse -Filter *.gd | Select-Object -ExpandProperty FullName
$godotConsolePath = "$PSScriptRoot\Godot_v4.4.1-stable_win64_console.exe"
if ($scriptFiles.Count -gt 0) {
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $godotConsolePath --headless --check-only --quit $scriptFiles 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorAction

    $output | Write-Host
    if ($exitCode -ne 0) {
        Write-Host "BUILD ABORTED: GDScript syntax validation failed." -ForegroundColor Red
        exit 1
    }
}
Write-Host "GDScript syntax validation passed." -ForegroundColor Green

# 3. Run Automated Tests
# Each test scenario is an independent headless Godot process with its own
# log/err files, so they have no shared state -- launch them all at once
# instead of waiting on each one sequentially. Output is still captured per
# test and printed one at a time afterward so it stays readable instead of
# interleaving across processes.
Write-Host "Running automated test suite (parallel)..." -ForegroundColor Cyan
$allTestFiles = Get-ChildItem -Path "$PSScriptRoot\scripts\tests\*.gd" -Exclude "test_asteroid.gd"

# PERF TESTS RUN ALONE, AFTER EVERYTHING ELSE (2026-07-27).
#
# These measure physics-step wall time. Run inside the parallel batch they
# measure however much CPU they happened to get, i.e. the SCHEDULER rather than
# the game -- which made them worse than useless: two gates tonight failed on
# margins of hundredths of a millisecond while the code was demonstrably fine.
# Measured the same evening, same commit:
#
#   in-gate (12-way parallel)   avg ~15.1 ms   (failed the 16 ms budget twice)
#   solo, 3 runs                avg 10.1 / 9.8 / 9.5 ms
#   committed baseline          avg 10.48 ms
#
# So the code was slightly FASTER than baseline the whole time, and the "gate
# is a lie" figure was contention. A perf test that mostly reports how busy the
# box is will train everyone to ignore it, which costs the one real regression
# it exists to catch.
#
# Serialised here rather than deleted or budget-inflated, because the budget
# should keep meaning what it says. Cost is a few extra seconds of wall clock:
# these are ~22s each and there are two.
#
# NOTE the tail is STILL not trustworthy even solo: Performance.TIME_PHYSICS_
# PROCESS holds stale readings across frames, so p95 == max is common and means
# held values dominated the tail (CLAUDE.md documents this at length). Trust
# `avg`; treat p95/max as "did a spike happen", never as a distribution.
$perfTestNames = @("test_perf_baseline", "test_pd_kill_wave_perf")
$testFiles = $allTestFiles | Where-Object { $perfTestNames -notcontains $_.BaseName }
$perfTestFiles = $allTestFiles | Where-Object { $perfTestNames -contains $_.BaseName }
$testsPassed = $true

# Start-Process -PassThru's returned object doesn't reliably expose ExitCode
# once -RedirectStandardOutput/-Error is also set -- use raw .NET Process
# objects instead, which track exit codes correctly.
# THROTTLE (2026-07-27). This loop used to Start() every test in one pass with
# no cap, then wait on them all in the second loop -- so a full gate launched
# one PowerShell host AND one headless Godot per test file, simultaneously. At
# 134 tests on a 32-core box that is ~4x CPU oversubscription and tens of GB of
# RAM in a single burst, and it crashed the machine outright twice once the
# suite grew past ~130 (several of the newer tests bootstrap the whole home
# cluster rather than a couple of hulls).
#
# Correctness is unaffected either way -- every test runs under --fixed-fps 60,
# so frame counts are identical regardless of contention (see CLAUDE.md). What
# contention DOES change is wall clock, and the perf tests, which were already
# documented as untrustworthy under load. Capping makes those meaningfully less
# noisy as a side effect.
#
# Cap leaves headroom for the OS, the editor and whatever else is running
# rather than saturating every core.
$maxParallel = [Math]::Max(2, [Math]::Min(12, [Environment]::ProcessorCount - 8))
Write-Host "Test concurrency capped at $maxParallel (of $([Environment]::ProcessorCount) logical CPUs)" -ForegroundColor DarkCyan

$runners = @()
foreach ($file in $testFiles) {
    # Hold here until a slot frees. Polling rather than WaitHandle juggling:
    # these are multi-second processes, so a 200ms tick costs nothing and keeps
    # the loop readable.
    while (@($runners | Where-Object { -not $_.Process.HasExited }).Count -ge $maxParallel) {
        Start-Sleep -Milliseconds 200
    }
    $logDir = "$PSScriptRoot\test_logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $runnerLog = "$logDir\$($file.BaseName).runner.log"
    $runnerErr = "$logDir\$($file.BaseName).runner.err.log"
    if (Test-Path $runnerLog) { Remove-Item $runnerLog -Force }
    if (Test-Path $runnerErr) { Remove-Item $runnerErr -Force }
    Write-Host "Launching $($file.BaseName)..."

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\test_runner.ps1`" -TestName $($file.BaseName)"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdOutTask = $proc.StandardOutput.ReadToEndAsync()
    $stdErrTask = $proc.StandardError.ReadToEndAsync()

    # += rather than collecting the loop's output, because the throttle above
    # has to inspect $runners WHILE the loop is still running.
    $runners += [PSCustomObject]@{ Name = $file.BaseName; Process = $proc; StdOutTask = $stdOutTask; StdErrTask = $stdErrTask; RunnerLog = $runnerLog; RunnerErr = $runnerErr }
}

foreach ($r in $runners) {
    $r.Process.WaitForExit()
    Set-Content -Path $r.RunnerLog -Value $r.StdOutTask.Result
    Set-Content -Path $r.RunnerErr -Value $r.StdErrTask.Result

    Write-Host "`n========== $($r.Name) ==========" -ForegroundColor Cyan
    Write-Host $r.StdOutTask.Result
    if ($r.StdErrTask.Result.Trim().Length -gt 0) {
        Write-Host "Runner stderr:"
        Write-Host $r.StdErrTask.Result
    }
    if ($r.Process.ExitCode -ne 0) {
        $testsPassed = $false
    }
}

# --- Perf tests, SERIALISED, with the box otherwise idle ---------------------
# See the note at $perfTestNames. Everything above has exited by now (the wait
# loop is a barrier), so these get the machine to themselves and measure the
# game rather than the scheduler.
if ($perfTestFiles.Count -gt 0) {
    Write-Host "`nRunning perf tests serially (contention would make these meaningless)..." -ForegroundColor Cyan
    foreach ($file in $perfTestFiles) {
        $runnerLog = "$PSScriptRoot\test_logs\$($file.BaseName).runner.log"
        $runnerErr = "$PSScriptRoot\test_logs\$($file.BaseName).runner.err.log"
        if (Test-Path $runnerLog) { Remove-Item $runnerLog -Force }
        if (Test-Path $runnerErr) { Remove-Item $runnerErr -Force }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\test_runner.ps1`" -TestName $($file.BaseName)"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $so = $proc.StandardOutput.ReadToEndAsync()
        $se = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()

        Set-Content -Path $runnerLog -Value $so.Result
        Set-Content -Path $runnerErr -Value $se.Result
        Write-Host "`n========== $($file.BaseName) (serial) ==========" -ForegroundColor Cyan
        Write-Host $so.Result
        if ($se.Result.Trim().Length -gt 0) {
            Write-Host "Runner stderr:"
            Write-Host $se.Result
        }
        if ($proc.ExitCode -ne 0) {
            $testsPassed = $false
        }
    }
}

if (-not $testsPassed) {
    if ($Force) {
        Write-Host "WARNING: One or more tests failed, but -Force was specified. Proceeding with build..." -ForegroundColor Yellow
    } else {
        Write-Host "BUILD ABORTED: One or more tests failed." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "All tests passed successfully." -ForegroundColor Green
}

# 3. Check and Install Export Templates
$templateDir = "$env:APPDATA\Godot\export_templates\4.4.1.stable"
if (-not (Test-Path "$templateDir\windows_release_x86_64.exe")) {
    Write-Host "Export templates for 4.4.1.stable not found. Downloading (~1.2 GB)..." -ForegroundColor Cyan

    # DOWNLOAD AS .zip, NOT .tpz. A .tpz IS an ordinary zip archive -- but
    # Expand-Archive validates the FILE EXTENSION rather than the contents and
    # accepts only ".zip", so handing it the upstream ".tpz" name fails with:
    #   ".tpz is not a supported archive file format. .zip is the only
    #    supported archive file format."
    # The extraction then leaves no temp_templates\templates dir, so the
    # Copy-Item below failed too and the build limped on to die at the export
    # step. Renaming on download is the whole fix; the archive itself is fine
    # and still unpacks to a top-level templates/ folder.
    $tpzPath = "$PSScriptRoot\export_templates.zip"
    $tempExtract = "$PSScriptRoot\temp_templates"

    # PS 5.1 (the Windows 10 default) does not negotiate TLS 1.2 on every box,
    # and GitHub requires it -- force it or the download can fail outright.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # -ErrorAction Stop on every step: these cmdlets raise NON-terminating
    # errors by default, which is why the original failure printed two red
    # blocks and then carried on regardless -- straight past "installed
    # successfully" and into an export that never had a chance. Without this,
    # the try/catch below would not catch them either.
    try {
        # Invoke-WebRequest's progress bar makes a 1.2 GB download roughly an
        # order of magnitude slower in PS 5.1. Suppress it for the transfer.
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz" -OutFile $tpzPath -ErrorAction Stop
        $ProgressPreference = $oldProgress

        Write-Host "Extracting templates..." -ForegroundColor Cyan
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
        Expand-Archive -Path $tpzPath -DestinationPath $tempExtract -Force -ErrorAction Stop

        New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
        Copy-Item -Path "$tempExtract\templates\*" -Destination $templateDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "BUILD ABORTED: could not install export templates. $_" -ForegroundColor Red
        Write-Host "Install them manually via the Godot editor (Editor > Manage Export Templates)." -ForegroundColor Yellow
        exit 1
    } finally {
        if (Test-Path $tpzPath) { Remove-Item $tpzPath -Force }
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    }

    # Verify rather than assume -- the old code printed "installed successfully"
    # unconditionally, which is why the real failure above scrolled past as two
    # red blocks followed by a success message.
    if (-not (Test-Path "$templateDir\windows_release_x86_64.exe")) {
        Write-Host "BUILD ABORTED: export templates did not install to $templateDir." -ForegroundColor Red
        exit 1
    }
    Write-Host "Export templates installed successfully." -ForegroundColor Green
}

# 3. Prepare Build Directory
Write-Host "Preparing build directory: $buildDir" -ForegroundColor Cyan
if (Test-Path $buildDir) {
    Remove-Item -Path $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $windowsBuildDir | Out-Null

# 4. Export Windows Desktop Build
Set-Content -Path "$PSScriptRoot\version.txt" -Value $buildVersion
Write-Host "Exporting Windows Desktop build to $exportPath..." -ForegroundColor Cyan
$godotArgs = "--path `"$PSScriptRoot`" --headless --export-release `"Windows Desktop`" `"$exportPath`""
$process = Start-Process -FilePath $godotPath -ArgumentList $godotArgs -Wait -PassThru -NoNewWindow

# 5. Copy Steam Dependencies
Write-Host "Copying Steam dependencies..." -ForegroundColor Cyan
$steamAppId = "$PSScriptRoot\steam_appid.txt"
if (Test-Path $steamAppId) {
    Copy-Item $steamAppId -Destination $windowsBuildDir
}

# 6. Check if export succeeded
if ($process.ExitCode -ne 0 -or -not (Test-Path $exportPath)) {
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    exit 1
}

Write-Host "Export successful!" -ForegroundColor Green

# 7. Packaging
$zipName = "ProjectDeepSpace_Windows_v$buildVersion.zip"
$zipPath = "$buildDir\$zipName"
Write-Host "Packaging build into $zipPath..." -ForegroundColor Cyan

Set-Content -Path "$windowsBuildDir\version.txt" -Value $buildVersion

$tmpFile = "$windowsBuildDir\ProjectDeepSpace.tmp"
if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }

Compress-Archive -Path "$windowsBuildDir\*" -DestinationPath $zipPath -Force

$exeSize = [math]::Round((Get-Item $exportPath).Length / 1MB, 1)
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)

Write-Host "Build Complete!" -ForegroundColor Green
Write-Host "Executable: $exportPath ($exeSize MB)"
Write-Host "ZIP: $zipPath ($zipSize MB)"

if (-not $testsPassed) {
    Write-Host "`nWARNING: This build contains broken tests (-Force was used)!" -ForegroundColor Yellow
}
