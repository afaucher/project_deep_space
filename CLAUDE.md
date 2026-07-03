# CLAUDE.md

Operational guide for working on this repo with Claude Code. This is the
*how-to-work-here* companion to the design docs (`design_ideas/`) and the
milestone plans (`implementation_plans/`). See `README.md` for build/run.

Godot 4.4.1, GDScript, headless workflow on Windows. The engine is bundled:
`./Godot_v4.4.1-stable_win64.exe`.

## Running tests

Tests live in `scripts/tests/*.gd` and are run by name. Two ways:

```bash
# Via the runner (writes logs to test_logs/, prints a colored summary):
powershell -NoProfile -ExecutionPolicy Bypass -File ./test_runner.ps1 -TestName test_ship_designs

# Direct (simplest to capture output for grepping):
./Godot_v4.4.1-stable_win64.exe --headless --run-test test_ship_designs
```

- **Pass marker:** a passing test prints `>>> [TEST PASSED] <name> <<<` (or the
  older `[TEST PASSED] <name>`). Failures print `[TEST FAILED]` / `ASSERT FAILED`.
- **Reading output:** `test_runner.ps1` writes the real Godot output to
  `test_logs/<TestName>.log` and `test_logs/<TestName>.err.log` — read those.
  Piping the runner's stdout is unreliable; prefer the log file or the direct
  `--run-test` form redirected to a file.
- **Tactical/balance sims:** `--run-tactical-sim <name>` loads
  `res://tactical_analysis/sim_runners/<name>.gd`; results usually land in
  `tactical_analysis/data/*.csv`.

## Headless gotchas (these have cost real time)

- **Do NOT trust `--headless --check-only --script <path>` for validation.** It
  reports *false* parse errors on autoload identifiers (e.g. `DebugSettings`).
  The runner deliberately skips syntax validation for this reason. Validate a
  script by running a test that loads it instead.
- **Run Godot sims one at a time.** Two concurrent headless instances starve
  each other's CPU and produce false test *timeouts*. Sequential only.
- **Kill stragglers** if a run hangs: `taskkill //F //IM Godot_v4.4.1-stable_win64.exe`.
- **`FileAccess.store_line` buffers** — a CSV being written may read back 0 lines
  until the file is flushed/closed.
- Long-running commands get auto-backgrounded by the harness; wait for the
  completion notification, then read the log file.

## GDScript traps hit in this codebase

- **A missing `Dictionary[key]` access aborts the rest of that function for the
  frame** (raises a runtime error, doesn't halt the engine). In a hot path like
  `_physics_process`, one component missing an expected field silently kills the
  ship's whole per-frame update (heat/EM sim, PD, steering) with no crash. Use
  `comp.get("field", default)` for any component field that isn't guaranteed on
  every ship. (This is exactly how a station bug hid: weapon dicts lacked
  `cooldown`, so stations ran no physics at all.)
- **`var x := arr.filter(...)`** fails to compile — inferred typing can't resolve
  an untyped `Array` return. Write `var x: Array = arr.filter(...)`.

## Architecture orientation (pointers, not a re-doc)

- **A ship *is* its parts.** `ship_components` is a list of dicts; mass, sensors,
  weapons, heat/EM all derive from them. See `design_ideas/ship_is_the_parts.md`.
  Runtime scratch fields (`cooldown`, `ammo`, `powered_on`, ...) are normalized
  in `Ship._ready()` — author new ships with the design fields; don't hand-set
  scratch.
- **Contact classification is keyed on EM, not heat** (`ship.gd` →
  `classify_contact`). A live ship/missile is EM-loud (reactor + active seeker);
  a hulk is EM-dark. This is why a freshly-killed ship reads WRECKAGE instantly
  even while still glowing hot.
- **Ship design validation:** `scripts/components/ship_design_validator.gd`
  (structural + overlap + connectivity + banded stats + PD-coherence) against the
  spec chart in `scripts/components/component_spec.gd`. Every catalog ship is
  validated by `test_ship_designs`. Components must not overlap and must form a
  connected (edge-adjacent) body.
- **Debug toggles** live in the `DebugSettings` autoload as a registry (`OPTIONS`
  dict); the top-bar Debug menu builds itself from it. Read with
  `DebugSettings.get_choice("key")`. Add a knob by appending one `OPTIONS` entry.
- **Sensor fusion** (angular-bin sweep → correlate → classify → decay/dead-reckon
  → datalink) lives in `ship.gd`'s `_physics_process`. See
  `design_ideas/real-time-sensor-signal.md` and `contact_tracing_and_cleanup.md`.

## Conventions

- Commit messages use a `feat:`/`fix:` prefix (see `git log`).
- Design decisions get a short doc in `design_ideas/`; milestones get a plan in
  `implementation_plans/`. Prefer adding to those over inline essays.
