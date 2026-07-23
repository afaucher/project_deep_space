# Project Deep Space

A Godot 4.4.1 game.

## Requirements

- Windows with PowerShell (uses bundled `Godot_v4.4.1-stable_win64.exe`), OR
- Linux with bash (see setup below)

## Building

```powershell
.\build.ps1
```

This runs the full test suite first (aborting the build on any failure), downloads export templates if missing, then exports a release build to `build\windows\ProjectDeepSpace.exe` and zips it to `build\ProjectDeepSpace_Windows.zip`.

## Running the game

```powershell
.\build\windows\ProjectDeepSpace.exe
```

## Running tests

Tests run headless via Godot and live in `scripts/tests/*.gd`. Logs are written to `test_logs/<TestName>.log` / `.err.log`.

### Windows

```powershell
.\test_runner.ps1 -TestName test_missile_ai
```

### Linux

One-time setup — download the 4.4.1-stable Linux build and place it at the project root:

```bash
curl -LO https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip Godot_v4.4.1-stable_linux.x86_64.zip
chmod +x Godot_v4.4.1-stable_linux.x86_64
rm Godot_v4.4.1-stable_linux.x86_64.zip
```

Then:

```bash
./test_runner.sh test_missile_ai
```

The bash runner mirrors the PowerShell one — same `--fixed-fps 60`, same stale-import pre-check, same 600s hang timeout, same pass/fail exit codes.
