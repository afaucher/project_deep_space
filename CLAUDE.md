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
- **A solo `test_perf_baseline` run right after a full `build.ps1` gate is NOT
  trustworthy — use the in-gate figure.** Observed 2026-07-24: immediately
  after a gate, running it alone reported avg 20.3ms / p95 54.4ms / max 203ms
  (well over budget) while the same tree passed *inside* the gate at avg
  12.0ms / p95 16.1ms. Counterintuitive — solo should have LESS contention —
  and it is not the `TIME_PHYSICS_PROCESS` hold artifact below (p95 != max).
  The likely cause is the gate's export step leaving a fresh ~95MB exe + ~35MB
  zip for the OS/AV to scan, competing for CPU/IO for a while afterwards; the
  mechanism is unconfirmed, the observation is repeatable. Practical rule: when
  a perf number looks alarming, **A/B it** (stash the change, re-run the same
  way) before believing the change caused it — that is what proved the traffic
  director innocent (it reproduced WORSE without the change, identical 35-ship
  census), and either wait for the machine to settle or trust the gate run.
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
- **A mechanical multi-site rewrite (`sed`, replace-all) can't see SCOPE — and
  the resulting parse error cascades into failures that look unrelated.**
  Observed 2026-07-25 moving a field: `self_bins.get("sinks", {})` →
  `rec.industry.get("sinks", {})` was correct at three call sites and broke the
  fourth, whose enclosing function had no `rec` parameter. That is a *parse*
  error, so the script never compiles, so **every script that depends on it
  fails to load** — here `main.gd` — and the suite then reports damage nowhere
  near the cause: `test_perf_baseline` "failed" (read as a perf regression, it
  wasn't), and another test "TIMED OUT after 600s" when it had actually failed
  to load instantly. The real message (`Parse Error: Identifier "rec" not
  declared`) appears ONLY in `test_logs/<name>.err.log`, never in the summary.
  You also can't pre-check cheaply — `--check-only` lies about autoloads (see
  Headless gotchas above). **Practical rule: after any multi-site mechanical
  rewrite, run ONE affected test directly and read its `.err.log` before
  spending ten minutes on a full gate.** A compile failure surfaces there in
  seconds, and a green single test means the cascade class is ruled out.

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
- **Debug log identifiers.** A ship's `name` (`Cluster_<record_id>` for a
  cluster-spawned ship — `cluster_manager.gd`), its claimed transponder/cover
  name, and its bare `get_instance_id()` are three UNRELATED-looking strings
  for the same entity, each used by a different subsystem's `print()` (job
  runner, pirate guild director, hail/damage logs) — a real correlation
  problem once several ships are active at once (M52 overdrive playtesting
  surfaced this directly: "Cluster_9011" in one log line, "'Second Return'"
  in another, no way to tell if they're the same ship). Any new per-ship dev
  print should identify the ship via `Ship.debug_label()` (`ship.gd`) —
  `"<name> \"<claimed name>\""`, omniscient (works for a dark/undercover
  ship too, unlike `get_active_transponder_data()`) — and any log keyed on a
  director's own record (e.g. `pirate_guild.gd`'s ledger) should include the
  raw `record_id` alongside the display name, so a human can match a
  `Cluster_<id>` line from one subsystem to a `(record <id>)` line from
  another.
- **Sensor fusion** (angular-bin sweep → correlate → classify → decay/dead-reckon
  → datalink) lives in `ship.gd`'s `_physics_process`. See
  `design_ideas/real-time-sensor-signal.md` and `contact_tracing_and_cleanup.md`.

## Conventions

- Commit messages use a `feat:`/`fix:` prefix (see `git log`).
- Design decisions get a short doc in `design_ideas/`; milestones get a plan in
  `implementation_plans/`. Prefer adding to those over inline essays.
- **Temporary files go in `tmp/`** (gitignored). Any throwaway output — a test
  dump, a scratch CSV, a debug capture, a one-off script's result — writes
  under `tmp/` (`res://tmp/...` from GDScript; `DirAccess.make_dir_recursive_absolute("res://tmp")`
  first, it's idempotent) so a run never dirties the working tree. Do NOT write
  scratch files to the repo root. Durable artifacts are the exception and are
  named explicitly: test logs → `test_logs/` (also gitignored), tactical-sim
  results → `tactical_analysis/data/*.csv` (tracked on purpose).
