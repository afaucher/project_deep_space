# Project Deep Space

A Godot 4.4.1 game.

## Requirements

- Windows (uses bundled `Godot_v4.4.1-stable_win64.exe`)
- PowerShell

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

Tests run headless via Godot and live in `scripts/tests/*.gd`. Run a single test:

```powershell
.\test_runner.ps1 -TestName test_missile_ai
```

Logs are written to `<TestName>.log` / `<TestName>.err.log` in the project root.
