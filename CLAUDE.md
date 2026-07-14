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
./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_ship_designs
```

**Pass `--fixed-fps 60` on direct runs** (the runner already does). Without it,
headless Godot runs the sim in REAL TIME (sleeps to hold 60Hz), so a frame-capped
test takes real wall-clock — test_missile_ai's scenarios = ~32s, most sim tests
several seconds. `--fixed-fps` uses the same 1/60 delta and identical frame
counts (fully deterministic) but stops sleeping → ~17x faster.

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
- **The "flaky sim timeout" was real-time throttling, not CPU starvation.**
  Headless sleeps to hold 60Hz (see `--fixed-fps` above); real-time sleep does
  NOT parallelize, so under N-way contention the loop can't hold 60Hz and
  wall-clock slips toward the runner's cap. `--fixed-fps 60` (now in the runner)
  fixes it — a 32-core box never legitimately needed 10 minutes for a 20s
  scenario. Combined with the RNG seed below, sims are fast AND deterministic.
- **Tests seed the global RNG** (`seed()` in `main.gd`'s `_run_test`). The global
  `randf`/`randi` — per-frame sensor position/velocity noise (`ship.gd`), missile
  jink — is otherwise entropy-seeded per launch, which made combat-OUTCOME tests
  flaky run-to-run. Do NOT remove the seed; if a new combat test is flaky, that's
  the first thing to check.
- **Godot 2D physics is NOT bit-deterministic run-to-run** (contact-solver/float
  ordering), even with the RNG seeded + a fixed delta. A long combat sim's exact
  outcome jitters — assert *robustly* (margins/majorities, e.g. test_ai_duel),
  not on an exact frame or a unanimous sweep.
- **Kill stragglers** if a run hangs: `taskkill //F //IM Godot_v4.4.1-stable_win64.exe`.
- **`Performance.TIME_PHYSICS_PROCESS` HOLDS stale readings across frames** —
  it refreshes on its own cadence, so one slow frame's value is re-read for
  many consecutive per-frame samples (a 160ms kill-wave stall once poisoned
  ~3s of samples). Averages/percentiles built from per-frame reads of this
  monitor overreport badly: the combat perf sim's monitor-based avg claimed
  17.9ms while direct wall-clock deltas (`Time.get_ticks_usec` between physics
  frames — honest under `--fixed-fps`, which never sleeps) measured 9.2ms for
  the SAME run. Trust the monitor for "did a spike happen", never for
  averages; `perf_combat.gd` samples both side by side. `p95 == max` in a
  report is the tell that held values dominated the tail.
- **`FileAccess.store_line` buffers** — a CSV being written may read back 0 lines
  until the file is flushed/closed.
- Long-running commands get auto-backgrounded by the harness; wait for the
  completion notification, then read the log file.
- **A sleeping RigidBody2D's collision shape does NOT follow a script-side
  reposition.** Godot puts an idle body (near-zero velocity, no forces) to
  sleep; once asleep, neither `.position = ...` nor
  `PhysicsServer2D.body_set_state(rid, BODY_STATE_TRANSFORM, xform)` alone
  updates its broad/narrow-phase collision data — `intersect_shape`/
  `intersect_ray` keep finding it at its OLD location indefinitely (not just
  one frame), even though `.position`/`.global_position` correctly report the
  new value. Confirmed by direct repro: a Frigate at rest, teleported to
  500,000 units away, still triggered a 5000-range sensor's `intersect_shape`
  query every tick, forever — `.position` printed the new location but the
  physics-server geometry never moved. The fix is to explicitly wake it:
  `body.sleeping = false` after the reposition. `test_docking_resilience.gd`
  and friends already use `body_set_state` to teleport test ships (the ONLY
  reliable way — plain `.position=` isn't enough either), but do this
  immediately at setup, before the body has a chance to fall asleep; a test
  that teleports an already-settled/idle ship mid-run needs the explicit
  wake-up too, or its sensor/LOS assertions will silently test against a
  ghost location.

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
