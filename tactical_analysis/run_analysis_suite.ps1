# run_analysis_suite.ps1 - Orchestrates the entire tactical analysis pipeline
function Normalize-ProcessPath {
    if ($env:PATH) {
        $env:Path = $env:PATH
        [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
    }
}

Normalize-ProcessPath

$godotPath = "$PSScriptRoot\..\Godot_v4.4.1-stable_win64.exe"
$pythonPath = "python"
$projectRoot = "$PSScriptRoot\.."

# M9e: shard a tactical sim across K headless Godot processes, then merge the
# per-shard CSVs back into the single canonical CSV filename that
# aggregate_and_chart.py already reads (it is NOT shard-aware -- the merge is
# what keeps its input contract unchanged). Returns $true on full success;
# returns $false (but still merges whatever shards succeeded) if any shard
# process exited non-zero, so a partial failure doesn't silently produce an
# incomplete-looking canonical CSV without at least a warning upstream.
function Invoke-ShardedSim {
    param(
        [Parameter(Mandatory = $true)][string]$SimName,
        [Parameter(Mandatory = $true)][string]$CsvBase
    )

    $logicalCores = [Environment]::ProcessorCount
    $K = [Math]::Max(2, [Math]::Min(8, $logicalCores - 2))

    Write-Host "Sharding '$SimName' across $K processes (logical cores: $logicalCores)..." -ForegroundColor Cyan
    $startTime = Get-Date

    # Raw .NET Process objects, not Start-Process -PassThru -- see build.ps1's
    # parallel test-launch comment: Start-Process's returned object doesn't
    # reliably expose ExitCode once output redirection is also involved, so we
    # use System.Diagnostics.Process directly to track exit codes correctly.
    $runners = for ($i = 0; $i -lt $K; $i++) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $godotPath
        $psi.Arguments = "--path `"$projectRoot`" --headless --run-tactical-sim `"$SimName`" --shard-index $i --shard-count $K"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $stdOutTask = $proc.StandardOutput.ReadToEndAsync()
        $stdErrTask = $proc.StandardError.ReadToEndAsync()

        [PSCustomObject]@{ Index = $i; Process = $proc; StdOutTask = $stdOutTask; StdErrTask = $stdErrTask }
    }

    $anyFailed = $false
    foreach ($r in $runners) {
        $r.Process.WaitForExit()
        if ($r.Process.ExitCode -ne 0) {
            $anyFailed = $true
            Write-Warning "$SimName shard $($r.Index) exited with code $($r.Process.ExitCode)."
            Write-Host $r.StdOutTask.Result
            if ($r.StdErrTask.Result.Trim().Length -gt 0) {
                Write-Host "Shard $($r.Index) stderr:" -ForegroundColor Yellow
                Write-Host $r.StdErrTask.Result
            }
        }
    }

    $elapsed = (Get-Date) - $startTime
    Write-Host "$SimName shards finished in $([Math]::Round($elapsed.TotalSeconds, 1))s (K=$K)." -ForegroundColor Cyan

    # Merge: header from the first shard found, then data rows (header line
    # skipped) appended from every shard, in shard-index order, written to the
    # canonical (non-sharded) CSV filename aggregate_and_chart.py expects.
    $shardFiles = Get-ChildItem -Path "$CsvBase.shard_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name
    $canonicalCsv = "$CsvBase.csv"

    if (-not $shardFiles -or $shardFiles.Count -eq 0) {
        Write-Warning "No shard CSVs found for $SimName at $CsvBase.shard_*.csv -- nothing to merge."
        return -not $anyFailed
    }

    $headerWritten = $false
    $mergedLines = New-Object System.Collections.Generic.List[string]
    foreach ($shardFile in $shardFiles) {
        $lines = Get-Content -Path $shardFile.FullName
        if ($lines.Count -eq 0) { continue }
        if (-not $headerWritten) {
            $mergedLines.Add($lines[0])
            $headerWritten = $true
        }
        if ($lines.Count -gt 1) {
            $mergedLines.AddRange([string[]]$lines[1..($lines.Count - 1)])
        }
    }

    Set-Content -Path $canonicalCsv -Value $mergedLines
    $dataRowCount = $mergedLines.Count - 1
    Write-Host "Merged $($shardFiles.Count) shard CSVs -> $canonicalCsv ($dataRowCount data rows)." -ForegroundColor Green

    foreach ($shardFile in $shardFiles) {
        Remove-Item -Path $shardFile.FullName -Force
    }

    return -not $anyFailed
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Running Tactical Analysis Engine Suite        " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# 1. Run Missile vs PD simulation (sharded)
Write-Host "`n[1] Running Missile vs Point Defense Simulation..." -ForegroundColor Yellow
$missilePdOk = Invoke-ShardedSim -SimName "run_missile_vs_pd" -CsvBase "$PSScriptRoot\data\missile_vs_pd_results"
if ($missilePdOk) {
    Write-Host "Simulation completed successfully." -ForegroundColor Green
} else {
    Write-Warning "Missile vs PD simulation had one or more failed shards. Proceeding with partial data."
}

# 2. Run Time-To-Kill simulation
# NOTE: run_time_to_kill.gd is currently BROKEN (dead shooter.weapons.* API --
# see m9_ship_catalog_design.md M9f, which will repair and generalize it).
# Its failure must NOT abort the suite or block aggregation/report generation
# for the (working) missile-vs-PD data, so we run it un-sharded and swallow a
# non-zero exit code with a clear warning instead of exiting.
Write-Host "`n[2] Running Time-To-Kill Simulation..." -ForegroundColor Yellow
Write-Warning "Time-To-Kill sim (run_time_to_kill) is known-broken pending M9f and is NOT sharded. A failure here is expected and will not abort the suite."
$args = "--path `"$projectRoot`" --headless --run-tactical-sim `"run_time_to_kill`""
$proc = Start-Process -FilePath $godotPath -ArgumentList $args -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Warning "TTK simulation failed with exit code $($proc.ExitCode). This is expected pending M9f -- continuing to aggregation."
} else {
    Write-Host "Simulation completed successfully." -ForegroundColor Green
}

# 3. Run Python Aggregation Script
# Runs regardless of step 1/2 sim failures so the report still generates for
# whatever canonical CSVs exist (aggregate_and_chart.py already warns and
# skips missing files cleanly).
Write-Host "`n[3] Aggregating Data and Generating Report..." -ForegroundColor Yellow
$pyArgs = "$PSScriptRoot\scripts\aggregate_and_chart.py"
$pyProc = Start-Process -FilePath $pythonPath -ArgumentList $pyArgs -Wait -PassThru -NoNewWindow -WorkingDirectory "$projectRoot"
if ($pyProc.ExitCode -ne 0) {
    Write-Error "Python aggregation script failed."
    exit 1
}
Write-Host "Report generation completed successfully." -ForegroundColor Green

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " Tactical Analysis Complete!                   " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
