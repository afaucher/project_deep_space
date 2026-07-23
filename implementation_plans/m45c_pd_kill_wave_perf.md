# M45c — Point-defense kill-wave perf investigation (planned, NOT started)

## Symptom

M45/M45b measured and fixed the STEADY-STATE campaign tick cost (no active
combat) — post-fix, `test_perf_baseline`'s in-gate numbers are avg 8.45ms /
p95 13.27ms out of a 16.67ms budget (~51%/~80%), matching the user's own
"~50%" observation of the real campaign with 20-30 ships. That investigation
is done and is NOT this milestone's concern.

Separately, the user reported combat/missiles pushing utilization to "100%
and worse." Re-running the existing `tactical_analysis/sim_runners/
perf_combat.gd` sim (3 frigates per side, full AI, forced into immediate
engagement — built as an M45 follow-up for exactly this complaint, quoted in
its own header: *"just adding 3 frigates slows the game down incredibly; 10
extra ships (missiles) in less than a second, and it adds up fast"*) with
fresh numbers this session:

- `pd_assign` (ship.gd's laser point-defense target-assignment loop) hit
  **278,204us — 278ms — in a single physics frame** (`PerfProbe`
  `max_frame_us`, measured via raw `Time.get_ticks_usec`, NOT the
  `TIME_PHYSICS_PROCESS` monitor that's known to hold stale readings across
  frames — this is a real, wall-clock-measured single-frame cost).
- `weapons_pd` (the wrapping tag) shows an almost-identical 278,524us max.
- `ship_tick_total` peaked at 289,491us the same frame.
- The timeline (`tactical_analysis/data/perf_combat_timeline.csv`, this
  session's fresh run) shows per-second-bucket `avg_phys_ms` reaching
  283-291ms for several consecutive seconds around t=5-9s, coinciding with
  the live "ships"-group census first climbing (30 ships / 24 missiles) then
  sharply dropping (13 ships / 7 missiles) — consistent with a missile
  kill-wave: many missiles and PD engagements resolving at once.

278ms is not "100% of a tick" — it's ~17x the entire 16.67ms budget in one
frame, a visible multi-hundred-millisecond freeze. This is a fundamentally
different problem than M45/M45b's steady-state averages: a spike triggered
specifically by dense, simultaneous PD engagement, not a per-tick cost that
scales smoothly with ship count.

## What's structurally happening (confirmed by code reading, not yet isolated by measurement)

**Missiles are full "ships"-group members.** `Missile extends Ship`
(`scripts/ships/missile.gd`) — every in-flight missile pays the complete
per-frame ship sim: sensor sweep, contact correlate/decay, datalink relay,
heat/EM, weapons/PD, eng-log crossings, identical cost profile to a real
ship, not a cheap projectile. A missile volley therefore doesn't add O(1)
PD targets — it multiplies EVERY O(ships) and O(ships²) per-tick cost
M45/M45b already profiled (`sensor_sweep`, `datalink_relay`,
`heat_em_component_loop`, etc. all scale with total "ships"-group size,
missiles included), on top of whatever PD-specific cost this milestone is
about.

**The PD assignment loop's own shape** (`ship.gd`, ~lines 3950-4059,
`PerfProbe` tags `pd_gather`/`pd_sort`/`pd_assign`):

```gdscript
PerfProbe.begin("pd_assign")
var fired_any = true
while not ready_lasers.is_empty() and fired_any:
    fired_any = false
    for t in targets:                    # restarts from targets[0] every outer pass
        if ready_lasers.is_empty(): break
        for w_id in ready_lasers:
            if behavior.can_fire(self, weapon_data, c_id):
                ...
                ready_lasers.erase(w_id)  # Array.erase is itself O(n): linear scan + shift
                fired_any = true
                break
PerfProbe.end("pd_assign")
```

Every single shot fired forces: breaking both inner loops, an O(ready_lasers)
`Array.erase`, and restarting the ENTIRE `for t in targets` scan from index 0
on the next outer-`while` pass. Worst case (many targets, many ready lasers)
this is roughly O(targets × lasers²) per ship, per physics frame, and it
reruns fresh every tick for every ship with ready PD lasers.

**Two prior optimization passes already targeted the PER-PAIR-CHECK cost
specifically, and are confirmed still in place** — read directly this
session, not assumed:
- `ship.gd`'s `ready_weapon_data` dict (comment ~line 3966: *"hundreds of
  thousands of wasted string comparisons in one bad frame"*) caches
  `get_component()` lookups so each (target, laser) pair check doesn't
  rescan the whole `ship_components` array.
- `weapon_behavior.gd`'s base `can_fire()` (comment ~line 16: *"PD's assign
  loop calls can_fire per (target, laser) pair, so that rescan was a real
  per-frame cost under missile saturation"*) uses `ship._component_powered(comp)`
  (dict-direct) instead of an id-based rescan.

Both fixes reduced each PAIR-CHECK to roughly O(1) — but this session's fresh
measurement shows `pd_assign` is STILL the dominant spike source during an
actual kill-wave. Either those fixes' target scenario was smaller than a real
kill-wave produces, or the O(targets × lasers²) LOOP SHAPE itself (iteration
count and GDScript call/dict-access overhead, even at O(1) per iteration) is
enough on its own at kill-wave scale, or something else dominates. **Not yet
determined — needs the same measure-first discipline M45 established,** not
a fix designed from code-reading alone.

**One per-call cost is NOT yet optimized: `LaserBehavior.execute_fire()`
(`scripts/components/weapons/laser_behavior.gd` ~line 46-54) runs a real
physics-server query — `space_state.intersect_shape(...)` — once per
SUCCESSFUL SHOT** (not per pair-check attempted), to resolve the actual hit
target at the aim position. During a kill-wave, many ships each firing
several ready lasers in the same tick means many of these physics queries
landing in one frame — a genuinely different cost source than the
pair-check loop shape above, scaling with shots fired rather than pairs
considered.

## Constraints — correctness properties the CURRENT algorithm guarantees, that any fix MUST preserve

Read from the code and its own comments (`ship.gd` ~line 3985-4028):

1. **Shortest-range laser tried first** — "reserving longer-range lasers for
   farther targets instead of spending them on whatever's first in the
   component list." `ready_lasers` is pre-sorted by `range` ascending before
   assignment.
2. **Least-shot-at target prioritized, then closest** — "we get little
   feedback on hits, so spread shots around." `targets` is pre-sorted by
   `shots_fired` ascending, then `dist` ascending.
3. **Multi-pass concentration**: with fewer targets than ready lasers, ALL
   ready lasers should still fire (possibly several onto the same target)
   rather than leaving extras idle — this is why the outer `while` loop
   re-passes the target list instead of a single O(targets) assignment pass.
4. **`can_fire()` gates real per-pair eligibility** (ammo/cooldown/power/
   arc-of-fire/range — read in full this session, see above) — assignment
   must still only fire a laser at a target it can actually hit; whatever
   replaces the loop shape must call the same eligibility check per
   candidate pair, not skip it for speed.
5. `scripts/tests/test_point_defense.gd` and `scripts/tests/
   test_volley_metering.gd` (confirmed present, not yet read in full) almost
   certainly assert some subset of the above — must be read completely
   before finalizing any fix design, and must NOT be weakened/loosened to
   make new numbers look better (same rule M45b's plan doc held itself to
   for relay-timing tests).

## Hypotheses, ranked (measure before believing any of them — code reading narrows the field but doesn't convict anything yet)

1. **`execute_fire()`'s per-shot `intersect_shape` physics query, multiplied
   by shot volume during a kill-wave.** Unlike the pair-check loop, this
   cost was NOT touched by either prior optimization pass — it's a genuine
   physics-server call per successful shot, and a kill-wave with many ships
   each firing multiple ready lasers per tick could mean dozens to hundreds
   of these queries landing in a single frame. Prime suspect given it's the
   one remaining un-cached, non-trivial per-unit-of-work cost in the whole
   path.
2. **The O(targets × lasers²) loop SHAPE itself, even with each pair-check
   now O(1).** GDScript function-call and dict-access overhead at large
   target×laser counts, repeated across every outer-`while` pass, could
   still add up meaningfully at kill-wave scale purely from iteration count
   — independent of whether any single step is expensive. Needs isolated
   measurement (e.g. a debug knob capping outer-loop passes, or forcing a
   naive single-pass assignment) to quantify this shape's cost separately
   from hypothesis 1.
3. **Missile-as-full-Ship compounding (structural, not itself a bug).** More
   live/dying missiles → more `INCOMING ORDNANCE` targets → feeds directly
   into both hypotheses' scaling terms above, PLUS its own separate steady
   per-ship tick cost (already profiled by M45/M45b) now multiplied by
   missile count specifically during a volley. A missile in a terminal
   phase (about to be intercepted or despawn) arguably doesn't need a full
   sensor-sweep/datalink-relay/heat-EM tick for its remaining fraction of a
   second alive.
4. ~~`can_fire()`'s own per-call cost~~ — **checked directly this session,
   ruled OUT as a standalone hypothesis.** Already O(1) after the two prior
   optimization passes (§ above). Still contributes its baseline O(1) cost
   × however many pair-checks hypothesis 2's loop shape produces, but isn't
   an independent expensive step on its own.
5. **Scene/physics-server churn co-occurring with the kill-wave** (mass
   missile `queue_free()`s, collision-pair changes as ordnance
   despawns/explodes) — an unattributed-remainder candidate, same shape as
   M45's own ~3.19ms/frame unexplained remainder in the steady-state case.
   `perf_combat.gd` already samples `PHYSICS_2D_COLLISION_PAIRS`/
   `PHYSICS_2D_ACTIVE_OBJECTS`/`PHYSICS_2D_ISLAND_COUNT` (see its header
   comment) but doesn't yet report them at the per-second timeline
   granularity — worth surfacing for the spike window specifically.

## Plan of execution (mirrors M45's own: measure first, attribute second, design third, fix fourth, guard last)

1. **Make the kill-wave reproducible.** `perf_combat.gd` does not currently
   seed the RNG (confirmed by grep this session — no `seed()`/`randomize()`
   call in the file) despite CLAUDE.md's explicit determinism rule for
   combat-outcome sims. Add a seed before measuring anything else, so the
   spike's timing and magnitude are comparable run-to-run instead of
   drifting with whatever the global RNG state happens to be.
2. **Read `test_point_defense.gd` and `test_volley_metering.gd` in full**
   to enumerate every assertion the current algorithm's ordering/fairness
   properties must keep satisfying (Constraints § above is a first pass
   from code reading, not from the tests themselves).
3. **Isolate hypotheses 1 vs 2 vs 3 via debug-toggle bisection** — same
   `DebugSettings.OPTIONS` pattern as M45's `perf_sensors`/`perf_ai`/
   `perf_eng_log` knobs:
   - A knob to short-circuit `execute_fire()`'s `intersect_shape` query
     (e.g. resolve the hit against the tracked contact directly when it's
     the obviously-intended target, bypassing the query) — isolates
     hypothesis 1's contribution.
   - A knob capping `pd_assign`'s outer-`while` passes to 1 (naive
     single-pass baseline, fairness properties temporarily relaxed for
     measurement purposes only) — isolates hypothesis 2's contribution.
   - Compare against the missile-count/`INCOMING ORDNANCE`-count series
     already sampled by the timeline, to gauge hypothesis 3's independent
     contribution (does the spike scale with missile census alone, holding
     PD load roughly fixed, in a variant scenario?).
   - Run each knob independently AND together, mirroring M45's own
     bisection cross-check methodology (which caught a real unexplained
     discrepancy that way — don't assume clean separability).
4. **Extend `perf_combat.gd`'s attribution to the kill-wave WINDOW
   specifically**, not just the whole-run average table it already prints —
   e.g. dump the top-tag `PerfProbe` breakdown for just the worst 1-second
   bucket (identified via the timeline's own `max_phys_ms` column), so the
   fix targets the actual spike composition instead of a diluted whole-run
   average. Also surface the collision-pair/active-object samples already
   being collected (hypothesis 5) at the same granularity.
5. **Design the fix from whichever hypothesis the measurement actually
   convicts** — do not pre-commit to an algorithm here. Candidates worth
   having in mind once data decides:
   - If hypothesis 1 convicts: cache or skip the `intersect_shape` hit-
     resolution query when the tracked contact IS the obviously correct hit
     (a locked, fresh, in-arc target rarely needs a broad-phase re-query to
     confirm what's already known) — narrow, targeted, doesn't touch the
     assignment loop's fairness properties at all.
   - If hypothesis 2 convicts: restructure the assignment loop to avoid the
     full target rescan after every single shot — e.g. track a per-target
     "still eligible" cursor/index instead of rebuilding the scan from
     position 0, or pre-bucket targets by which lasers can reach them before
     the assignment passes begin. Must preserve Constraints 1-4 exactly.
   - If hypothesis 3 convicts materially: a cheaper per-frame tick for
     missiles in a terminal/dying phase (skip sensor sweep / datalink relay
     for a missile in its last few frames before despawn, if such a phase
     is cleanly identifiable) — but ONLY if it doesn't change intercept-
     timing-sensitive test outcomes; missile combat tests are outcome-
     sensitive per CLAUDE.md's own margin/majority-assertion guidance, not
     exact-frame assertions, so there's some room, but this is the riskiest
     candidate and should be scoped smallest/last.
6. **Guard.** Given the severity here (278ms, not a tuning nitpick — a
   visible freeze), consider promoting a bounded version of this INTO
   `scripts/tests/` as an actual regression gate (assert `max_phys_ms`
   under some generous-but-meaningful ceiling for a fixed, seeded kill-wave
   scenario), not leaving it purely investigative the way M45 left
   `perf_combat.gd`. M45 stayed investigative because nothing had been
   fixed yet there; once THIS milestone lands a fix, a regression guard
   prevents the spike from silently reappearing.

## Non-goals for this pass (explicit, to keep scope from ballooning)

- **NOT redesigning missile flight/lifecycle wholesale** (e.g. demoting
  missiles out of the "ships" group entirely) unless hypothesis 3's
  measurement shows it's necessary and a narrower terminal-phase skip isn't
  sufficient — that's a much bigger structural change with its own combat-
  outcome-determinism risk, and a candidate for a LATER milestone if this
  one's narrower fixes don't recover enough headroom.
- **NOT touching the steady-state (no-combat) cost path** already measured
  and fixed by M45/M45b.
- **NOT threading/WorkerThreadPool** — same reasoning as M45b's non-goal:
  Godot's own docs state interacting with the scene tree isn't thread-safe,
  and this path is even MORE physics-query-heavy (raycasts AND shape
  queries) than `datalink_relay` was. If this investigation's fixes still
  don't recover enough headroom, a snapshot/compute/apply restructure is a
  candidate for a separate, later pass — not this one.

## Measurement plan / success criteria

- `pd_assign`/`weapons_pd` `max_frame_us` in the SAME (now-seeded, so
  comparable) kill-wave scenario drops by at least an order of magnitude —
  278ms down to low tens of ms at worst, ideally into single-digit-ms
  territory matching the OTHER `PerfProbe` tags' scale.
- No regression in `test_point_defense.gd` / `test_volley_metering.gd`'s
  EXISTING assertions (the fairness/ordering properties in the Constraints
  section, verified by actually reading and re-running them — not just "the
  suite is still green").
- Full `build.ps1` gate green.
- Before/after timeline CSV comparison (same shape as this doc's own fresh
  numbers) showing the kill-wave second(s) no longer spike disproportionately
  relative to the surrounding seconds.
- If a regression guard is added per Plan step 6, it passes on the fixed
  code and would have FAILED on the pre-fix code (verify by running it
  against a stash of the current state, same discipline M45 used for its
  own guard calibration).

## Files likely touched

- `scripts/ships/ship.gd` — the `pd_assign` loop itself (whichever fix
  hypothesis 2 or 3 convicts).
- `scripts/components/weapons/laser_behavior.gd` — `execute_fire()`'s hit
  resolution (if hypothesis 1 convicts).
- `tactical_analysis/sim_runners/perf_combat.gd` — RNG seed, kill-wave-
  window attribution breakdown, collision-pair/active-object reporting at
  timeline granularity.
- `scripts/debug_settings.gd` — new bisection knob(s) for the isolation
  step, same `OPTIONS` pattern as M45.
- Possibly a new `scripts/tests/test_pd_kill_wave_perf.gd` or similar, if
  the guard is promoted into the regression gate (Plan step 6).
- `scripts/tests/test_point_defense.gd`, `test_volley_metering.gd` — read
  in full for existing constraints; only modified if genuinely new coverage
  is needed, never to loosen an existing assertion.

## Findings (executed)

### 1. Reproducibility (plan step 1)

`perf_combat.gd` had no `seed()`/`randomize()` call (confirmed by grep, as
the doc predicted). Added `seed(20260708)` — same constant `_run_test` uses
in `main.gd` — with an `M45C_SEED` env override for sweeping. Post-seed,
re-running the SAME seed three times back-to-back gave byte-identical
`PerfProbe` call counts (`ship_tick_total` calls=28263, `pd_assign`
calls=7655 every time) and `max_frame_us` varying by <2% run-to-run — call
CLAUDE.md's "physics 2D isn't bit-deterministic" caveat noted but the
practical effect at this scenario's scale was small, not the dominant
source of variance turned out to matter here.

**Important scope note:** the SEEDED baseline (seed 20260708) measured
`pd_assign` `max_frame_us` around **9.7-9.9ms**, and a follow-up sweep of 8
more seeds (1-8) found a worst case of **26.1ms** (seed 3) — nowhere near
the doc's originally-reported 278ms. That original number came from an
unseeded run earlier this session; it was not independently reproduced
under `--fixed-fps` with output redirected to a file. This doesn't
contradict the finding below — see the print-I/O explanation, which
plausibly explains why an interactive/unredirected terminal run (more likely
how the original 278ms was captured) could show a much larger stall than a
file-redirected headless run: Windows console rendering of a burst of
`print()` lines is known to be dramatically slower than piping to a file.
The mechanism, direction, and magnitude of the effect (see below) are
unambiguous either way; only the exact peak number wasn't reproduced
under this session's measurement conditions.

### 2. Test constraints (plan step 2)

Read `test_point_defense.gd` and `test_volley_metering.gd` in full. The
doc's Constraints section (1-4) matched the actual test assertions exactly:
shortest-range-laser-first (`_test_weapon_selection_by_range`), least-shot-
target-then-closest (`_test_sort_by_range`, `_test_sort_by_shots_fired`),
and multi-pass concentration (`_test_multiple_lasers_concentrate_on_one_target`,
the regression test for the exact "extra ready lasers sit idle" bug the
multi-pass loop exists to prevent). `test_volley_metering.gd` covers missile
volley-readiness timing (`is_group_volley_ready`), a different subsystem
entirely — no PD-assignment constraints there, not touched by this fix.
None of these tests were modified.

### 3. Bisection (plan step 3) — the actual culprit

Added two `DebugSettings` bisection knobs (`perf_pd_hit_query`,
`perf_pd_multi_pass`, mirroring M45's `perf_sensors`/`perf_ai`/
`perf_eng_log` pattern) to isolate hypotheses 1 and 2 independently. Ran
seed 3 (worst-found) through all four combinations:

| config | pd_assign max_frame_us | weapons_pd max_frame_us | TIME_PHYSICS_PROCESS max |
|---|---|---|---|
| both ON (baseline) | 1,370us | 1,628us | 13.03ms |
| hit_query OFF (H1 isolated) | 1,387us | 1,670us | 12.64ms |
| multi_pass OFF (H2 isolated) | 1,481us | 1,855us | 12.83ms |
| both OFF | 1,359us | 1,634us | 12.67ms |

Neither knob moved the needle beyond noise — hypotheses 1 (`intersect_shape`
query) and 2 (loop shape) are REAL but **negligible** at this scenario's
scale, confirming the two prior optimization passes (`ready_weapon_data`
cache, `_component_powered` cache) already did their job. This directly
contradicts the doc's ranking (H1 ranked #1 suspect) — measurement overruled
code-reading intuition here, exactly per the doc's own caution.

The table above was captured with `ship.gd`'s `COMBAT_DEBUG` const
temporarily forced to `false` for a clean isolation baseline. Comparing that
baseline against the SAME seed 3 with `COMBAT_DEBUG` left at its
then-current value of `true` told the real story:

| `COMBAT_DEBUG` | pd_assign max_frame_us | weapons_pd max_frame_us | TIME_PHYSICS_PROCESS max |
|---|---|---|---|
| `true` (as found) | 26,070us | 26,364us | 35.6ms |
| `false` | 1,444us | 1,783us | 13.1ms |

An **18x** reduction in `pd_assign`'s own peak from toggling ONE unrelated
boolean. `git blame` on `ship.gd`'s `COMBAT_DEBUG` const explained why:
commit `c7794d2` ("Player Fire All ... and quiet combat log spam",
2026-06-27) deliberately set it `false` specifically to fix combat log spam
(~500KB → ~6KB per AI-duel log, per that commit's own message). Ten days
later, commit `3616ecab` ("Add test_station_keeping and fix docking
architecture" — an unrelated change) silently flipped it back to `true`,
almost certainly a leftover from local debugging swept into that commit.
**The comment directly above the const was never updated and still says
"off by default"** — the code silently stopped matching its own documented
intent, which is exactly how this stayed invisible for weeks.

Mechanism, confirmed by reading `execute_fire()` and `_process_point_defense()`
together: `execute_fire()` (called from inside `pd_assign`'s `PerfProbe`
window) calls `body.take_damage()` SYNCHRONOUSLY, which — with
`COMBAT_DEBUG=true` — chains into `[Damage]`/`[Collision]`/reactor-overheat/
`[PD] shooting` `print()` calls, ALL still inside `pd_assign`'s timing
window. During a kill-wave's densest second, dozens of PD shots each
triggering a damage cascade means dozens of `print()` calls land inside a
single physics frame's `pd_assign` measurement. `PerfProbe` measures real
wall-clock time (`Time.get_ticks_usec`), so console/stdout I/O latency for
those prints is indistinguishable from "real" assignment-loop cost in the
attribution table — it's the SAME wall-clock window, whether the time went
to string formatting, syscalls, or a terminal's own scroll/render cost, all
of which the pd_assign block pays for. Hypothesis 3 (missile-as-full-Ship
compounding) was also checked: with `COMBAT_DEBUG=false`, `ship_tick_total`
scales roughly linearly with the 30-ship peak census (matching M45/M45b's
already-characterized steady-state cost × ship count) — no pathological
compounding beyond the expected linear scaling, so per the doc's own
explicit non-goal, left untouched.

### 4. Worst-bucket attribution (plan step 4)

Extended `perf_combat.gd` to snapshot cumulative `PerfProbe` `total_us` per
tag every 60 frames and diff consecutive snapshots to report the top tags
for JUST the worst 1-second bucket (identified via the timeline's own
`max_phys_ms`), not the diluted whole-run average. Post-fix, seed 20260708's
worst bucket (t=5s, 13.15ms) breaks down as `ship_tick_total` 34.1%,
`sensor_sweep` 7.3%, `ai_tree_tick` 6.9%, `heat_em_component_loop` 6.4%,
`weapons_pd` only 2.2% — confirming that after the fix, the remaining
tick-budget pressure at a 30-ship kill-wave peak is the SAME already-
characterized steady-state cost profile from M45/M45b scaled to more ships,
not a PD-specific problem anymore. Pre-fix, the same bucket showed
`weapons_pd` at 2.68% (default seed) to 2.7% of the second even in the
AVERAGED/whole-run view, but the whole-run `max_frame_us` column (a single-
frame peak, finer-grained than a 1s bucket) is where the real spike showed:
21-26ms in one frame, ~15-20% OF THE ENTIRE MEASURED SECOND concentrated
into a single 16.67ms-budget tick.

### 5. Fix (plan step 5)

**Restored `const COMBAT_DEBUG := false` in `scripts/ships/ship.gd`** (was
`true`), with a comment explaining the regression and its history so it
doesn't silently drift again. This is a one-line fix that:
- Does not touch `_process_point_defense()`'s assignment algorithm, ordering,
  or multi-pass concentration AT ALL — Constraints 1-4 are untouched by
  construction, not just "still pass the tests."
- Is the SAME fix `c7794d2` already landed once (deliberately, for the exact
  same log-spam reason) — this milestone's real contribution is diagnosing
  that it had regressed, not inventing a new mitigation.
- Also kept the two bisection knobs (`perf_pd_hit_query`, `perf_pd_multi_pass`)
  as permanent investigation tooling, matching M45's own precedent of
  keeping `perf_sensors`/`perf_ai`/`perf_eng_log` in the codebase after that
  milestone shipped its fix.

**Before/after, same seeds, same DebugSettings knob defaults:**

| seed | before max_phys | after max_phys | before pd_assign max | after pd_assign max | before weapons_pd max | after weapons_pd max |
|---|---|---|---|---|---|---|
| 20260708 (default) | 24.94ms | 13.15ms | 21,441us | 2,536us | 21,594us | 2,816us |
| 1 | 27.61ms | 12.58ms | — | 496us | — | 1,643us |
| 3 | 35.97ms | 12.76ms | 26,152us | 1,496us | 26,364us | 1,864us |
| 4 | 29.58ms | 13.55ms | — | 1,683us | — | 1,948us |
| 5 | 32.92ms | 13.07ms | — | 1,866us | — | 2,140us |

`pd_assign`/`weapons_pd` `max_frame_us` dropped roughly **10-18x** across
every seed tested, landing in low-single-digit-ms territory — matching the
doc's own success criterion ("ideally into single-digit-ms territory
matching the OTHER PerfProbe tags' scale"). The remaining whole-tick
`TIME_PHYSICS_PROCESS` max (~12.6-13.6ms post-fix) is now dominated by
`ship_tick_total`'s already-characterized, non-goal steady-state cost at a
30-ship kill-wave peak (see § 4), not by PD assignment.

### 6. Regression guard (plan step 6)

Added `scripts/tests/test_pd_kill_wave_perf.gd` — a bounded (10s, not
`perf_combat.gd`'s 25s) version of the same 3v3 kill-wave scenario, cheap
enough for the regular `build.ps1` gate. It asserts two independent things:
1. **`ShipScript.COMBAT_DEBUG == false`** directly — the precise, ~free
   guard against the EXACT regression that happened (this is the assertion
   that would have given the clearest failure message if it existed before
   commit `3616ecab`).
2. **`pd_assign`/`weapons_pd` `PerfProbe` `max_frame_us` under 8,000us /
   10,000us** — a broader guard against any future cost spike shaped the
   same way, not just this one flag. Budgets set at ~3x the post-fix
   ceiling observed across 5 seeds (same "~3x the fixed value" margin
   `test_collision_perf.gd` uses), which still leaves >2x headroom below
   the pre-fix floor.

**Calibration check (same discipline as M45's own guard):** ran the new
test against the pre-fix state (`COMBAT_DEBUG := true`, stashed/restored
via direct edit) — all three assertions FAILED as expected
(`pd_assign max_frame_us=15067` vs budget `<8000`; `weapons_pd
max_frame_us=15250` vs budget `<10000`; the direct `COMBAT_DEBUG` check).
Ran again against the fixed code — all three PASSED
(`pd_assign max_frame_us=1523`, `weapons_pd max_frame_us=1814`).

### 7. Full suite (plan step 6, continued)

Ran the complete `scripts/tests/` suite via `build.ps1` (parallel headless
run, all `*.gd` in `scripts/tests/` except `test_asteroid.gd`, including the
new `test_pd_kill_wave_perf.gd`) through to the full export/package step.
Result: **106 `[TEST PASSED]`, 0 `[TEST FAILED]`**, "All tests passed
successfully." — includes `test_point_defense.gd`, `test_volley_metering.gd`,
and the new `test_pd_kill_wave_perf.gd` (14.46s in-gate) all green, plus the
build itself completing (export + package steps ran clean).

### Deviations from the plan doc

- **The convicted cause is not one of the doc's five ranked hypotheses.**
  The doc's own hypotheses 1 (intersect_shape query) and 2 (loop shape) were
  bisected and found NEGLIGIBLE, not dominant, at this scenario's scale —
  the opposite of the doc's ranking. The actual cause (`COMBAT_DEBUG`
  drifting to `true`, print()/console-I/O cost landing inside `pd_assign`'s
  timing window) is closest in spirit to hypothesis 5's "unattributed-
  remainder" framing, but is a specific, previously-unnamed mechanism the
  doc didn't anticipate — found only by following its own "don't assume
  clean separability" bisection discipline and then reading `git blame` on
  what the isolation pointed at. This is a good example of why the doc
  explicitly refused to convict a hypothesis in advance.
- **The exact 278ms figure was not reproduced.** The worst reproduced,
  seeded, file-redirected headless number was 35.97ms (pre-fix, seed 3).
  The gap is plausibly explained (interactive-terminal console I/O being
  far slower than piping to a file — the SAME mechanism, just under harsher
  I/O conditions than this session's batch runs used) but was not directly
  confirmed, since re-creating a live, unredirected terminal session wasn't
  practical from this environment. The fix and guard are still correct and
  well-calibrated regardless: they target the confirmed mechanism (print
  volume inside `pd_assign`'s window), not the specific peak number.
- **Non-goals held.** No missile-lifecycle/group-membership redesign (H3
  confirmed structural, not pathological, at this scenario's scale). No
  changes to the steady-state no-combat path. No threading.
