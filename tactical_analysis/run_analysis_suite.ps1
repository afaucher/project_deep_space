# run_analysis_suite.ps1 - Orchestrates the entire tactical analysis pipeline

$godotPath = "$PSScriptRoot\..\Godot_v4.4.1-stable_win64.exe"
$pythonPath = "python"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Running Tactical Analysis Engine Suite        " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# 1. Run Missile vs PD simulation
Write-Host "`n[1] Running Missile vs Point Defense Simulation..." -ForegroundColor Yellow
$args = "--path `"$PSScriptRoot\..`" --headless --run-tactical-sim `"run_missile_vs_pd`""
$proc = Start-Process -FilePath $godotPath -ArgumentList $args -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Error "Godot simulation failed with exit code $($proc.ExitCode)"
    exit 1
}
Write-Host "Simulation completed successfully." -ForegroundColor Green

# 2. Run Time-To-Kill simulation
Write-Host "`n[2] Running Time-To-Kill Simulation..." -ForegroundColor Yellow
$args = "--path `"$PSScriptRoot\..`" --headless --run-tactical-sim `"run_time_to_kill`""
$proc = Start-Process -FilePath $godotPath -ArgumentList $args -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Error "TTK simulation failed with exit code $($proc.ExitCode)"
    exit 1
}
Write-Host "Simulation completed successfully." -ForegroundColor Green

# 3. Run Python Aggregation Script
Write-Host "`n[3] Aggregating Data and Generating Report..." -ForegroundColor Yellow
$pyArgs = "$PSScriptRoot\scripts\aggregate_and_chart.py"
$pyProc = Start-Process -FilePath $pythonPath -ArgumentList $pyArgs -Wait -PassThru -NoNewWindow -WorkingDirectory "$PSScriptRoot\.."
if ($pyProc.ExitCode -ne 0) {
    Write-Error "Python aggregation script failed."
    exit 1
}
Write-Host "Report generation completed successfully." -ForegroundColor Green

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " Tactical Analysis Complete!                   " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
