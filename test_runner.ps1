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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Running Automated Tests for Project Deep Space " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Syntax Validation
Write-Host "`n[1] Running GDScript syntax validation..." -ForegroundColor Yellow
$scriptFiles = Get-ChildItem -Path "$PSScriptRoot\scripts" -Recurse -Filter *.gd | Select-Object -ExpandProperty FullName
$godotConsolePath = "$PSScriptRoot\Godot_v4.4.1-stable_win64_console.exe"
if ($scriptFiles.Count -gt 0) {
    & $godotConsolePath --headless --check-only $scriptFiles 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ">>> [TEST FAILED] GDScript syntax validation failed <<<" -ForegroundColor Red
        exit 1
    }
}
Write-Host ">>> [TEST PASSED] GDScript syntax validation passed <<<" -ForegroundColor Green

if ($TestName -eq "") {
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
# Hard per-test timeout: a hung test must FAIL the build, never wedge it
# indefinitely. test_missile_ai (and occasionally others) can flakily fail to
# exit cleanly in headless even after get_tree().quit() -- the test logic is
# bounded (frame-capped), so a process that's still alive well past any
# legitimate run time is hung, not working. We use a raw .NET Process rather
# than Start-Process so we can (a) enforce the timeout via WaitForExit(ms) and
# (b) read ExitCode reliably alongside redirected output (Start-Process
# -PassThru doesn't expose ExitCode once output is redirected).
$TEST_TIMEOUT_SEC = 600

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $godotPath
$psi.Arguments = "--path `"$PSScriptRoot`" --headless --run-test `"$TestName`""
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
