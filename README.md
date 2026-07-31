# Project Deep Space

A Godot 4.4.1 game.

## Requirements

- **Windows:** PowerShell, using the bundled `Godot_v4.4.1-stable_win64.exe`.
- **Linux:** bash plus the 4.4.1-stable Linux Godot binary at the project root (see "Running tests" for the one-time download).

Both platforms can build the game; Linux can additionally cross-build the Windows release.

## Building

### Windows

```powershell
.\build.ps1
```

### Linux

```bash
./build.sh                  # both targets
./build.sh --target linux   # or: --target windows
```

Either script runs the full test suite first and aborts the build on any failure (`-Force` / `--force` overrides), downloads the ~1.2 GB export templates if they are missing, then exports and packages:

| target | binary | archive |
|---|---|---|
| Windows | `build/windows/ProjectDeepSpace.exe` | `build/ProjectDeepSpace_Windows_v<version>.zip` |
| Linux | `build/linux/ProjectDeepSpace.x86_64` | `build/ProjectDeepSpace_Linux_v<version>.tar.gz` |

The Linux build is packaged as `.tar.gz` rather than `.zip` because zip does not preserve the executable bit — a zipped Linux build extracts non-executable and will not launch.

**Cross-building Windows from Linux needs no wine.** Godot's exporter appends the project `.pck` to a prebuilt `windows_release_x86_64.exe` template, and GodotSteam ships binaries for every platform, so the exporter selects the right `steam_api` automatically.

`export_presets.cfg` is committed. It used to be gitignored, which meant a fresh clone had no export presets and the build died with `This project doesn't have an export_presets.cfg file at its root`. The preset names (`Windows Desktop`, `Linux`) are what the build scripts pass to `--export-release`, so renaming them breaks the build.

## Running the game

```powershell
.\build\windows\ProjectDeepSpace.exe
```

```bash
./build/linux/ProjectDeepSpace.x86_64
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
