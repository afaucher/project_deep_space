# test_runner.ps1 - Orchestrates headless Godot tests
param (
    [string]$TestName = ""
)

function Normalize-ProcessPath {
    if ($env:PATH) {
        $env:Path = $env:PATH
        [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
    }
}

Normalize-ProcessPath

$godotPath = "$PSScriptRoot\Godot_v4.4.1-stable_win64.exe"
if (-not (Test-Path $godotPath)) {
    Write-Error "Godot executable not found at $godotPath."
    exit 1
}

. "$PSScriptRoot\import_check.ps1"
Import-IfStale -ProjectRoot $PSScriptRoot -GodotPath $godotPath

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Running Automated Tests for Project Deep Space " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($TestName -eq "") {
    Write-Host "`n[1] Running GDScript syntax validation..." -ForegroundColor Yellow
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
            Write-Host ">>> [TEST FAILED] GDScript syntax validation failed <<<" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host ">>> [TEST PASSED] GDScript syntax validation passed <<<" -ForegroundColor Green

    Write-Host "`n[2] No specific test provided. Orchestration ready." -ForegroundColor Green
    exit 0
}

# 2. Run Specific Test Scenario
Write-Host "`n[2] Running Test Scenario: $TestName" -ForegroundColor Yellow

$logDir = "$PSScriptRoot\test_logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = "$logDir\$TestName.log"
$errFile = "$logDir\$TestName.err.log"
if (Test-Path $logFile) { Remove-Item $logFile }
if (Test-Path $errFile) { Remove-Item $errFile }

# We run Godot headless and pass the test name as an argument.
#
# --fixed-fps 60 DECOUPLES the loop from real time. Headless Godot otherwise
# SLEEPS to hold 60Hz, so a frame-capped sim test runs in real time (e.g.
# test_missile_ai's scenarios = ~32s wall-clock) despite doing milliseconds of
# work -- and real-time sleep does NOT parallelize, so under N-way contention
# the loop can't hold 60Hz and wall-clock slips toward the cap (that was the
# "flaky timeout", never CPU-load). --fixed-fps runs the same fixed 1/60 delta
# with identical frame counts (deterministic) but no sleep -> ~17x faster.
# Determinism also needs main.gd's seed() (the global RNG -- sensor noise,
# missile jink -- was the real flakiness source; see _run_test).
#
# Hard per-test timeout stays as a backstop for a genuinely hung test.
# Raw .NET Process (not Start-Process) so we can (a) enforce the timeout via
# WaitForExit(ms) and (b) read ExitCode reliably alongside redirected output.
$TEST_TIMEOUT_SEC = 600

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $godotPath
$psi.Arguments = "--path `"$PSScriptRoot`" --headless --fixed-fps 60 --run-test `"$TestName`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdOutTask = $proc.StandardOutput.ReadToEndAsync()
$stdErrTask = $proc.StandardError.ReadToEndAsync()

$exitedInTime = $proc.WaitForExit($TEST_TIMEOUT_SEC * 1000)
if (-not $exitedInTime) {
    # Hung: kill the process so the async stdout/stderr pipes close and their
    # ReadToEndAsync tasks complete -- only then is it safe to read .Result
    # (reading it on a still-running process would itself block forever).
    try { $proc.Kill() } catch {}
    $proc.WaitForExit()
}

$logContent = $stdOutTask.Result
$errContent = $stdErrTask.Result
Set-Content -Path $logFile -Value $logContent
if ($errContent -ne "") { Set-Content -Path $errFile -Value $errContent }

if (-not $exitedInTime) {
    Write-Host "`n  >>> [TEST FAILED] $TestName (TIMEOUT -- killed after ${TEST_TIMEOUT_SEC}s) <<<" -ForegroundColor Red
    Write-Host "Test did not exit within the time budget -- treated as a hang. Partial log:"
    Write-Host $logContent
    if ($errContent -ne "") {
        Write-Host "Error Output:"
        Write-Host $errContent
    }
    exit 1
}

if ($proc.ExitCode -eq 0 -and $logContent -match "\[TEST PASSED\]") {
    Write-Host "`n  >>> [TEST PASSED] $TestName <<<" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n  >>> [TEST FAILED] $TestName <<<" -ForegroundColor Red
    Write-Host "Exit Code: $($proc.ExitCode)"
    Write-Host "Log Output:"
    Write-Host $logContent
    if ($errContent -ne "") {
        Write-Host "Error Output:"
        Write-Host $errContent
    }
    exit 1
}
