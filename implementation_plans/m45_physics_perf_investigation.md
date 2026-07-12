# M45 — Physics tick performance investigation (planned, NOT started)

## Symptom

The in-game per-frame physics time readout (the custom "% of a tick"
metric, where the remainder is waiting) reports ~90% consumed in the
CAMPAIGN STARTING SCENE — near Ironhold, with well under 100 ships
around. That budget should be nowhere near full at this entity count;
something is doing far more per-tick work than the scene warrants.

First task for whoever executes this: find and read the metric's own
implementation (it's custom — locate where "% of a tick" is computed and
displayed) and confirm exactly what it measures (physics step only?
physics + per-frame script work? one ship or the whole tree?) before
trusting any number it reports.

## What's actually in the starting scene (census, from home_cluster.gd)

- 3 MediumStations (Ironhold + 2 far hubs), 3 SmallStations, 5
  MobileHomes, 7 Buoys, 1 Wormhole, 2 patrol LACs, 2 cargo shuttles,
  the player: ~24 members of the "ships" group running the full per-frame
  ship sim (sensor fusion, heat/EM, weapons/PD bookkeeping, eng-log
  crossings, transponders).
- ~55 asteroids (18+22+15, at the three outpost fields ~100k+ away from
  spawn — distant for gameplay, but still live RigidBody2Ds under the
  current FullSim liveness policy).
- Total: ~80 physics bodies, ~24 full-sim ships. NOT a large scene.

## Hypotheses, ranked (measure before believing any of them)

1. **Sensor pipeline (the prime suspect).** Every ship's
   _physics_process runs contact decay/correlation/classification per
   frame over its whole contact table, and the active-sweep path
   (angular-bin scan over all colliders) fires on each sensor's
   refresh_interval. Two sub-suspects:
   - **Thundering herd:** every sensor's `timer` starts at 0, so all
     ~24 ships' sweeps fire on the SAME frames forever (refresh_interval
     1.5s at a fixed 60Hz = perfectly synchronized). The average might
     be fine while the spike frames blow the tick budget — matching a
     "90% of a tick" readout.
   - O(ships × colliders) sweep cost itself, plus per-contact M38
     cross-section lookups (cached per class+bucket — verify the cache
     is actually hitting, we've been burned by a bypassed cache before).
2. **Per-component per-frame loops.** Heat/EM simulation iterates every
   component of every ship every frame; M40 added a second full
   component scan (_check_eng_log_crossings); weapon/PD bookkeeping
   scans; `get_total_power_rating()`/`is_component_powered()` re-derive
   aggregates by scanning components on every call — stations carry the
   biggest component lists and there are 11 of them.
3. **AI + steering.** Beehave trees tick per ship; Steering._avoidance
   raycasts/shape-queries for movers (2 patrols, 2 shuttles — small
   count, but queries are per-tick).
4. **State distribution.** main.gd's _distribute_state deep-duplicates
   contacts/hit_traces/eng_log/contract feed per tick. This is
   script-side, not the physics server — whether it lands in the
   user-visible metric depends on what that metric measures (see above).
5. **Physics server itself.** ~80 bodies with convex-hull shapes should
   be trivial broadphase; distant asteroids shouldn't matter. Verify
   rather than assume — if the physics SERVER step (not script) is the
   time sink at 80 bodies, something structural is wrong (e.g.
   monitoring/contact pairs we don't expect).

## Plan of execution

Measure first, attribute second, optimize third, guard last. No
optimization lands without a before/after number from the same harness.

1. **Instrument.** A tiny PerfProbe autoload (begin(tag)/end(tag) using
   Time.get_ticks_usec, aggregated min/avg/max/frame-peak per tag) that
   compiles to near-no-ops unless a DebugSettings knob enables it (the
   OPTIONS registry is the existing pattern). Wrap the big blocks in
   ship._physics_process (sweep, contact bookkeeping, heat/EM, weapons,
   eng-log, repairs), AI tick, _distribute_state, and read
   Performance.TIME_PHYSICS_PROCESS for the engine-side step.
2. **Baseline harness.** A headless sim-runner (tactical_analysis
   pattern) or test that boots the REAL campaign scene (HomeCluster +
   overlay, like test_campaign_dock_health), runs ~30 simulated seconds,
   and dumps the PerfProbe table + per-frame peak distribution to CSV.
   Deterministic via the usual seed; note that --fixed-fps 60 removes
   real-time sleeping, so "% of tick" must be recomputed from measured
   usec against the 16.67ms budget, not read from the live metric.
3. **Attribute.** The table should name the top consumers directly.
   Cross-check by bisection with DebugSettings toggles (sensors off /
   AI off / no asteroid fields / stations only) — two independent
   attributions beat one.
4. **Fix the top offenders only.** Candidates TO BE VALIDATED (not
   pre-decided): stagger sensor timers (randomize initial phase per
   ship — but mind the seeded-RNG determinism rules in CLAUDE.md;
   deterministic stagger by instance index is safer), dirty-flag
   cached component aggregates (power totals, powered-state) instead of
   per-call scans, batch/trim per-frame contact-table work, cheapen
   _distribute_state copies (send deltas or shallow-copy immutable
   entries).
5. **Guard.** A perf smoke test in the suite: campaign scene, N frames,
   assert avg and p95 physics-step usec under a GENEROUS budget (wide
   margin — CI variance and the bit-nondeterminism caveats apply; this
   guards order-of-magnitude regressions, not 5% drift).

## Constraints / cautions

- Don't add instrumentation cost to the hot path when the knob is off —
  the probe itself must be nearly free (a bool check), or it becomes the
  regression.
- The M38/M26 caches (RadarCrossSection buckets, ShipSilhouette loops)
  were built exactly to keep the sensor path cheap — if attribution
  fingers the sweep, FIRST verify the caches are being hit (a bypassed
  cache has happened before) before designing anything new.
- Ship sim correctness invariants (seeded RNG, fixed frame counts,
  robust-margin tests) must survive any optimization — the perf harness
  must not perturb the sim it measures.
- The liveness bubble (M14) is the eventual structural answer for big
  scenes (only the live set pays), but the starting scene is ~24 ships
  under FullSim by DESIGN — 24 ships must be cheap. Re-enabling the
  bubble is not a substitute for finding this hot spot.
