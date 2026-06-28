# build.ps1 - Build and package Project Deep Space
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

# 1. Verification
if (-not (Test-Path $godotPath)) {
    Write-Error "Godot executable not found at $godotPath."
    exit 1
}

# 2. Run Automated Tests
# Each test scenario is an independent headless Godot process with its own
# log/err files, so they have no shared state -- launch them all at once
# instead of waiting on each one sequentially. Output is still captured per
# test and printed one at a time afterward so it stays readable instead of
# interleaving across processes.
Write-Host "Running automated test suite (parallel)..." -ForegroundColor Cyan
$testFiles = Get-ChildItem -Path "$PSScriptRoot\scripts\tests\*.gd" -Exclude "test_asteroid.gd"
$testsPassed = $true

# Start-Process -PassThru's returned object doesn't reliably expose ExitCode
# once -RedirectStandardOutput/-Error is also set -- use raw .NET Process
# objects instead, which track exit codes correctly.
$runners = foreach ($file in $testFiles) {
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

    [PSCustomObject]@{ Name = $file.BaseName; Process = $proc; StdOutTask = $stdOutTask; StdErrTask = $stdErrTask; RunnerLog = $runnerLog; RunnerErr = $runnerErr }
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

if (-not $testsPassed) {
    Write-Host "BUILD ABORTED: One or more tests failed." -ForegroundColor Red
    exit 1
}
Write-Host "All tests passed successfully." -ForegroundColor Green

# 3. Check and Install Export Templates
$templateDir = "$env:APPDATA\Godot\export_templates\4.4.1.stable"
if (-not (Test-Path "$templateDir\windows_release_x86_64.exe")) {
    Write-Host "Export templates for 4.4.1.stable not found. Downloading..." -ForegroundColor Cyan
    $tpzPath = "$PSScriptRoot\export_templates.tpz"
    Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz" -OutFile $tpzPath
    
    Write-Host "Extracting templates..." -ForegroundColor Cyan
    Expand-Archive -Path $tpzPath -DestinationPath "$PSScriptRoot\temp_templates" -Force
    
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    Copy-Item -Path "$PSScriptRoot\temp_templates\templates\*" -Destination $templateDir -Recurse -Force
    
    Remove-Item $tpzPath -Force
    Remove-Item "$PSScriptRoot\temp_templates" -Recurse -Force
    Write-Host "Export templates installed successfully." -ForegroundColor Green
}

# 3. Prepare Build Directory
Write-Host "Preparing build directory: $buildDir" -ForegroundColor Cyan
if (Test-Path $buildDir) {
    Remove-Item -Path $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $windowsBuildDir | Out-Null

# 4. Export Windows Desktop Build
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
$zipName = "ProjectDeepSpace_Windows.zip"
$zipPath = "$buildDir\$zipName"
Write-Host "Packaging build into $zipPath..." -ForegroundColor Cyan

$tmpFile = "$windowsBuildDir\ProjectDeepSpace.tmp"
if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }

Compress-Archive -Path "$windowsBuildDir\*" -DestinationPath $zipPath -Force

$exeSize = [math]::Round((Get-Item $exportPath).Length / 1MB, 1)
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)

Write-Host "Build Complete!" -ForegroundColor Green
Write-Host "Executable: $exportPath ($exeSize MB)"
Write-Host "ZIP: $zipPath ($zipSize MB)"
