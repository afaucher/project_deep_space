# M52c — Robbery mechanics: stop meaning stop, alongside meaning alongside

Sub-milestone from the 2026-07-20 pirate playtest (design_ideas/
2026-07-20-pirate_playtest.md). The player got stopped by pirates twice and
both encounters broke the fantasy:

- **Pirate 1 rammed the player and killed itself.**
- **Pirate 2 logged `INTERCEPT done` without ever stopping.**
- Expected instead: match speeds → come alongside (possibly dock) → 10+
  seconds visibly stealing cargo → undock → depart.

## Root causes (read from job_steps.gd, confirmed against the log)

Both bugs are the same missing concept: **the intercept steps have no
relative-velocity control and no standoff distance.**

- `step_intercept` (job_steps.gd) DONEs on `dist <= hail_range` — pure
  proximity. The pirate never decelerates; "intercept" is a drive-by.
- `step_intercept` and `step_demand_stop` both steer via
  `_cruise_toward(actor, victim_pos, ...)` — dead at the victim's CURRENT
  position, no lead, no standoff radius. Against an AI victim that
  complies (stops dead), the pirate arrives at a stationary point: fine.
  Against a moving PLAYER, it's a pursuit curve that terminates in the
  player's hull — the ramming death was structural, not bad luck.
- `step_take_alongside` holds station near a victim that is already
  STOPPED (`_hold_station` + in-range check against a compliant target).
  The "match speeds and lock on" behavior the playtest expected for the
  stop itself simply doesn't exist anywhere in the chain.

## Behaviors to build

1. **Standoff intercept.** INTERCEPT closes to a standoff point OFFSET
   from the victim (e.g. 300–500u abeam), never the victim's own position,
   and DONE requires BOTH inside-hail-range AND relative speed under a
   threshold — an intercept you can't collide out of and can't flyby
   through. This is the piracy-job twin of the docking approach problem
   the port work already solved once (keep-out cone, approach geometry) —
   steal the shape, not the code.
2. **Speed-match hold during the stop.** DEMAND_STOP against a still-moving
   victim should PACE it (match velocity at the standoff offset), not
   chase its position — the pirate flies formation while the demand
   clock runs. A victim that complies decelerates; the pace naturally
   becomes a stationary alongside. A victim that runs opens the gap and
   the existing outpaced/patience aborts fire unchanged.
3. **The visible robbery.** TAKE_ALONGSIDE gets its theater: hold_time
   raised to 10s+ (playtest ask), and the hold requires the alongside
   station actually kept (drift out of the envelope pauses the clock —
   already true — but the envelope tightens to genuinely-alongside, not
   600u "nearby"). Whether this becomes a REAL ship-to-ship dock
   (DockingBay-style capture between two ships) is this milestone's one
   open design call:
   - **Soft-dock (recommended first step):** formation-lock at a fixed
     offset — pirate zeroes relative velocity and holds the offset
     rigidly (same station-keeping the docking bay's capture spring
     approximates), no physics joint. Cheap, robust, reads correctly at
     game scale.
   - **Hard-dock:** an actual DockingBay-style capture between hulls.
     Real contact, real constraint — but ship-to-ship docking machinery
     (moving bay, mutual approach, undock push against a mobile partner)
     is new physics surface with M28-30-collision-era risk written all
     over it. Defer unless soft-dock reads badly in play.
4. **~~Autopilot dead stop (player-side).~~ PARKED (calling session,
   2026-07-22).** Reconsidered after M52d's ACKNOWLEDGE/STOP correction:
   dead-stop-in-place is a helm/autopilot function, and shares its shape
   with a future maintain-distance/follow mode (both are "match target
   velocity/position," one at zero) — it deserves its own design doc and
   a real implementation pass, not a bolt-on comms-panel button. The
   comms-panel STOP button that would have triggered this is hidden
   (`comms_panel.gd`). `Ship.engage_dead_stop()` still exists (AI uses it
   directly) and is the natural landing spot when autopilot lands.
   **M52c proceeds on items 1–3 only** — the pirate-side standoff/pacing/
   robbery-theater work does not depend on the player having a one-input
   dead stop; a player can still brake manually via helm controls, same
   as before this milestone.

## Tests

- Intercept standoff: pirate vs a scripted straight-line mover — closes to
  standoff, relative speed under threshold at DONE, zero hull contact over
  the encounter (margin-based; collision damage = instant fail).
- Ramming regression: the exact playtest shape — victim holds course
  through the demand — pirate paces alongside, never collides, patience
  abort fires cleanly if no compliance.
- Robbery theater: complied victim → pirate closes to alongside envelope,
  10s hold accumulates only inside it, RELEASE + departure after.
- Dead stop: from cruise, engage DEAD STOP → velocity under threshold
  within expected braking time, holds against drift.

## Findings (as-built)

Implemented directly (single pass, no subagent handoff). Items 1-3 built
per this doc's scope; item 4 (autopilot dead stop) stayed parked exactly as
scoped — no helm/autopilot code touched, `comms_panel.gd`'s STOP button
stays hidden.

**All three items built, with two deviations from the plan's literal
wording surfaced by actually running the movement against a live physics
sim (a throwaway debug trace was needed to find both — the design read
soundly on paper and only broke empirically):**

- **Item 1, standoff intercept** — `JobSteps.step_intercept` now targets a
  point OFFSET from the victim (`_standoff_offset`: perpendicular to the
  victim's own heading, 400u by default — the design doc's 300-500u band,
  side picked once per step-entry from the actor's current bearing so it
  doesn't loop around). DONE requires BOTH `dist <= hail_range` (or the
  standoff distance, for a jammed/no-comms edge case) AND relative speed
  `<= 50 u/s` (`INTERCEPT_SPEED_MATCH_THRESHOLD`, comfortably under Ship's
  own `COMPLIED_STOP_SPEED_LIMIT` of 80). Confirmed by `test_robbery_
  mechanics`' Phase 1: closes to ~391u (target 400) with relative speed
  ~49 u/s at DONE, zero hull contact across the whole encounter.
- **Item 2, speed-match hold during DEMAND_STOP** — `step_demand_stop`'s
  movement swapped from `_cruise_toward(victim's raw position)` to the same
  `_pace_at_offset` INTERCEPT uses (shared helper, as the plan suggested).
  A victim that never complies (Phase 2's ramming-regression test: constant
  300u/s straight course, no AI to ACKNOWLEDGE) gets paced at the standoff
  the whole time — zero contact — until DEMAND_STOP's existing patience
  timeout (unchanged logic, just given a shorter 6s in the test) aborts
  cleanly.
- **Item 3, robbery theater (soft-dock)** — `step_take_alongside`'s
  defaults: `hold_time` 8.0 → **12.0**s, `range` 600.0 → **200.0**u (the
  plan's "10.0+" and "150-250u" bands). `pirate_guild.gd`'s real hunt-job
  step dict updated to match (the only production job-building call site —
  test fixtures in `test_pirate_ambush.gd`/`test_pirate_abort.gd` pass
  their OWN explicit `hold_time`/`range` literals and were deliberately
  left alone, since they're pinning their own scenario, not the production
  default). The hold is a true soft-dock: `_pace_at_offset` with
  `exclude_pos` = the victim (so generic collision-avoidance doesn't fight
  the tight hold) zeroes RELATIVE velocity at the offset, extending
  `_hold_station`'s "actively brake, don't coast" idea from a stationary
  target to a moving one. Confirmed by Phase 3: closes to the tightened
  envelope, hold runs 12.4s (>= the 12.0s default, not run away past it),
  loot_takes/looted flip on DONE, zero hull contact throughout.

**Two deviations found by empirical testing, not in the original design:**

1. **A shared `_pace_at_offset(actor, target_pos, target_vel, exclude_pos,
   cruise)` helper**, used by all three verbs (the plan flagged this as
   likely but left it to implementation). Its catch-up speed term is
   `sqrt(2 * a_max * PACE_BRAKING_SAFETY * dist)` — a time-optimal
   "square-root braking curve" mirroring `ship.gd`'s own rotation
   controller (same header phrase: "Time-Optimal Rotational Controller
   (Square-root curve braking)"), NOT the plan's implied "just close the
   gap" shape. A first pass used a plain linear ramp (speed proportional to
   distance); a throwaway debug trace showed it overshooting the pace
   target on every single approach and orbiting for 30-60+ real seconds
   before a lucky pass finally satisfied the speed-match threshold — a
   linear ramp only starts shedding speed within `cruise /
   PACE_POSITION_GAIN` of the target, nowhere near the ship's actual
   thrust/mass stopping distance. The sqrt profile fixed the orbiting
   outright; `PACE_BRAKING_SAFETY` (0.3) derates the assumed accel below
   raw thrust/mass because turning to face the correction direction and the
   velocity-control PID both lag a tick or more behind a perfectly
   instantaneous response — without the derate the ship still consistently
   overshot the standoff point and only satisfied the speed-match threshold
   almost on top of the victim, not at the intended offset.
2. **Hysteresis on TAKE_ALONGSIDE's in-range check**
   (`TAKE_ALONGSIDE_EXIT_SLACK`, 1.25x). The original 600u envelope never
   exposed this; tightening it to 200u did. A debug trace showed the pirate
   genuinely holding formation (position noise + control-loop response
   bouncing +-15-20u around the boundary) while `dist` crossed back and
   forth over the bare `range` cutoff every physics tick, erasing
   `hold_start_frame` each time — a hold that visibly held station never
   accumulated past a few tenths of a second. Fix: once a hold has started,
   it only pauses past `range * 1.25`, not the instant distance ticks over
   `range` itself.

**A third finding was not a bug in my changes at all**: Phase 3's first
draft used a `CargoShuttle` + `AITreeFactory.build_cargo()` victim (same
shape `test_pirate_ambush.gd` uses) and intermittently saw the victim
choose to RUN instead of comply. Root cause traced to the pre-existing
(M52a) `threat_response_leaf.gd` comply-or-run heuristic: it weighs the
pirate's demonstrated peak speed, read off the VICTIM's own sensor
`active_contacts` at the moment the demand is first evaluated — a genuine
race against exactly when the victim's sensors first correlate a fresh
track on the (initially dark) pirate, independent of anything M52c
touches. `test_pirate_ambush.gd` already covers that heuristic end to end
and kept passing throughout (re-verified after every job_steps.gd change).
Rather than fight an unrelated race in a new test, Phase 3 now drives
compliance directly — `victim.engage_dead_stop()`, the same call the AI
itself would make — the instant the demand arrives, keeping the test
scoped to TAKE_ALONGSIDE's own mechanics.

**Verification:**
- `test_pirate_abort`, `test_pirate_guild`: pass, before and after.
- `test_pirate_ambush`: fails identically before and after — Phase 4/5
  (`AWAIT{track_quiet}` → `RELIGHT` → `EXIT_AT` never reached), the exact
  pre-existing bug this doc's own "KNOWN PRE-EXISTING BUG" note and
  `m52d_hail_ux.md`'s Findings already tracked. No new failure mode.
- `test_robbery_mechanics` (new): all 3 phases pass — standoff intercept,
  ramming regression, robbery theater (see per-item summaries above).
- Full `build.ps1` gate: two failures, both pre-existing/unrelated —
  `test_pirate_ambush` (above) and `test_ai_duel` (CLAUDE.md's documented
  5-trial-majority combat flake; re-run 3/3 clean in isolation, and this
  milestone touches no missile/PD/combat code). No other failures.
- `git status` clean of unintended changes: `build.ps1`'s
  `tactical_analysis/data/perf_baseline*.csv` churn reverted
  (`git checkout --`); the pre-existing untracked `contacts_dump.txt` and
  `.uid` files left alone. Touched: `implementation_plans/
  m52c_robbery_mechanics.md`, `scripts/ai/jobs/job_steps.gd`,
  `scripts/directors/pirate_guild.gd`. Added:
  `scripts/tests/test_robbery_mechanics.gd`.

## Fiction parked here (from the playtest, not this milestone)

- **Pirates physically comm in.** The guild stops getting "filed reports"
  for free: check-ins require the member to reach comms range of a relay/
  contact. Full fiction — pirate CONTACTS embedded on stations; the
  pirate must physically reach them to report, and finding/removing these
  people literally tears down the pirate network's information layer.
  Player-facing counter-piracy content; needs the M53a traffic world
  first. Goes with the guild honesty rule (pirate_guild.gd's ledger) —
  the ledger's check-in mechanism is already shaped for this, it just
  currently pretends range is infinite.
