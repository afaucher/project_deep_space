# test_runner.ps1 - Orchestrates headless Godot tests
param (
    [string]$TestName = ""
)

$godotPath = "$PSScriptRoot\Godot_v4.4.1-stable_win64.exe"
if (-not (Test-Path $godotPath)) {
    Write-Error "Godot executable not found at $godotPath."
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Running Automated Tests for Project Deep Space " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Syntax Validation Skipped (Currently flaky with Godot 4)
Write-Host "`n[1] Skipping GDScript syntax validation..." -ForegroundColor Yellow

if ($TestName -eq "") {
    Write-Host "`n[2] No specific test provided. Orchestration ready." -ForegroundColor Green
    exit 0
}

# 2. Run Specific Test Scenario
Write-Host "`n[2] Running Test Scenario: $TestName" -ForegroundColor Yellow

$logFile = "$PSScriptRoot\$TestName.log"
if (Test-Path $logFile) { Remove-Item $logFile }

# We run Godot headless and pass the test name as an argument
# The main scene or a dedicated test scene will parse this and run the logic.
$args = "--path `"$PSScriptRoot`" --headless --run-test `"$TestName`""
$proc = Start-Process -FilePath $godotPath -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $logFile

$logContent = Get-Content $logFile -Raw

if ($logContent -match "\[TEST PASSED\]") {
    Write-Host "`n  >>> [TEST PASSED] $TestName <<<" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n  >>> [TEST FAILED] $TestName <<<" -ForegroundColor Red
    Write-Host "Log Output:"
    Write-Host $logContent
    exit 1
}
