# M50 — Pirate hulls + the piracy job: detailed design

Parent: [m48_m55_economy_piracy_roadmap.md](m48_m55_economy_piracy_roadmap.md);
the composition model is [jobs_and_itineraries.md](../design_ideas/jobs_and_itineraries.md)
(read it first — this doc pins that model to files); verbs are
[comms_verbs.md](../design_ideas/comms_verbs.md). Deliverable: the full
piracy loop runs end-to-end against live traffic — arrive under cover,
hunt dark, rob a shuttle via the M49 protocol, exfil, launder or exit —
built on the generic job runner that traders/workers will reuse.

## New: the job runner (`scripts/ai/jobs/`)

- `scripts/ai/jobs/job_runner_leaf.gd` — Beehave action leaf. Two-slot
  model (jobs_and_itineraries.md — NOT a stack): reads `actor.assignment`
  falling back to `actor.default_job` (ship fields; ship-facing API is
  `assign_job(job)` / `set_default_job(job)` so directors/spawners/tests
  never touch the tree). A completed/aborted-out assignment clears and the
  standing duty resumes at step 0; a completed job with `repeat: true`
  re-enters at step 0. Neither slot populated / both complete → FAILURE
  (tree falls through). Otherwise: evaluate the current step's `abort_when`
  conditions, then dispatch to the executor library; handle CONTINUE
  (return SUCCESS), DONE (advance `current`), ABORT (jump to the step whose
  `label` == this step's `on_abort`; no match → job over). ~90 lines,
  never grows. The pirate's hunt is an ASSIGNMENT (guild-issued in M51,
  test-issued in M50) over an empty standing duty — which also exercises
  the fallback path M52's interdiction will rely on.
- `scripts/ai/jobs/job_steps.gd` — static executor library (preload-const
  convention, like standing.gd/hail.gd). One `static func step_<verb>(actor,
  step: Dictionary) -> int` per verb returning CONTINUE/DONE/ABORT consts.
  Executors are STATELESS — per-step scratch goes in the step dict under
  `"scratch"` (the runner clears it on entry to a step, including re-entry
  via an abort jump). Movement goes through the same
  `Steering.steer` + `apply_control_input` idiom flee/threat_response use.

### Verb semantics (v1)

- `GO_TO {pos, arrive_radius=1500.0, cruise=700.0}` — cruise toward pos
  (Steering avoidance on), DONE inside the radius.
- `GO_DARK {}` — `set_transponder_active(false)`, DONE immediately.
- `RELIGHT {name, flag}` — set transponder custom name + flag +
  active(true), DONE. (The launder relight: a NEW name — the wanted-names
  registry makes the old one a liability.)
- `LOITER_NEAR {pos, radius=2500.0, duration}` — drift/station-keep
  loosely inside the circle, DONE after `duration` accumulated seconds.
- `AWAIT {condition, timeout, ...}` — DONE when the named condition holds,
  ABORT on timeout. v1 conditions (dispatched in job_steps, honesty rule:
  only ship-knowable inputs):
  - `"duration" {seconds}` — plain wait.
  - `"track_quiet" {seconds, clear_range}` — the launder heuristic: we have
    been transponder-dark AND held no fresh contact within `clear_range`
    for `seconds` continuously (reset on any fresh contact). Conservative
    stand-in for "everyone lost my track"; deliberately fallible.
  - `"undocked" {}` — we are not currently captured by a berth (the dock
    dwell: DOCK_AT is done when BERTHED, AWAIT{undocked} rides out the
    hold until the station releases us — the visitor test uses this).
- `DOCK_AT {station_pos}` — find the station near pos ("ships" group +
  `get_port_zone`, cargo_run_leaf's `_find_station_at` pattern), request a
  grant at a controlled bay / raise `wants_dock` at an open one, DONE once
  captured-and-docked. Station auto-release (manual_undock=false) frees us
  afterward, same as cargo shuttles. (Exists for the visitor generality
  test + the trader milestone; the pirate never docks.)
- `EXIT_AT {pos, radius=1500.0}` — GO_TO, then despawn (`queue_free`).
  M51's director records the exit; in M50 it's just gone.
- `SELECT_VICTIM {lane_pos, lurk_radius=2500.0, witness_range}` — the
  pirate-only hunt: loiter near the lane while scoring fresh vessel
  contacts every ~30 ticks. A viable victim: standing NEUTRAL or
  UNREPORTED (prey reports or doesn't — never FRIENDLY-crypto, never a
  complied/looted mark), fresh track, and ALONE — no OTHER fresh vessel
  track within `witness_range` of it. Smallest cross_section preferred
  (unarmed silhouettes ARE small hulls in this catalog; an honest proxy
  until inspection exists). DONE stamps `victim_iid` into the JOB dict
  (`job["victim_iid"]`), where INTERCEPT/DEMAND/TAKE read it.
- `INTERCEPT {}` — close on `job["victim_iid"]`'s track to inside
  comms-hail range (min of both radios, with margin), DONE there; ABORT if
  the track goes stale (lost it).
- `DEMAND_STOP {show_colors=false, patience=25.0}` — if show_colors:
  `set_transponder_flag(JOLLY_ROGER)` + transponder on (the M49
  compliance-weighting beat, already tested). Send DEMAND(STOP) at the
  victim (Hail via `send_demand`). DONE when our track on the victim shows
  `complied_stop` (M49 stamps it on COMPLY receipt). ABORT when the victim
  is outpacing us beyond hail range or `patience` expires un-complied
  (fast hulls run — let them go).
- `TAKE_ALONGSIDE {hold_time=8.0, range=600.0}` — hold within `range` of
  the complied victim; accumulate ONLY while in range and the victim's
  track still shows complied_stop. DONE at `hold_time`: increment
  `actor.loot_takes` (new int field — the M51 guild ledger reads it), set
  `looted = true` on the victim ship (server-side flag, test-visible;
  cargo stays abstract in M50), and send RELEASE to the victim (the robber
  lets you go when it has what it wants — also makes the victim's resume
  snappy instead of waiting out M49's 10s issuer-loss timeout). ABORT if
  complied_stop clears (victim bolted).

### Abort conditions (`abort_when` on any step)

Evaluated by the runner before dispatch, cheap and ship-knowable:

- `third_party_in_range {r}` — any fresh vessel track that is neither the
  victim nor classified FRIENDLY VESSEL within `r` of ME. This is the
  pirate's "witness/patrol closing" read (it cannot know a contact's ROLE —
  a witness is a witness).
- `victim_lost {}` — no fresh track on `job["victim_iid"]`.

Damage/crippled is NOT an abort condition — the reactive Disengage layer
above the runner already owns that (jobs_and_itineraries.md: reactions are
trees).

## The pirate tree + the pirate job

`ai_tree_factory.build_pirate()`:

```
Selector
|-- Disengage (ShouldDisengage -> Flee)     # damage outranks the heist
|-- JobRunner                                # the mission
+-- Idle
```

No Engage branch — a pirate is predatory, not reactive: it attacks via the
job (DEMAND/TAKE), never via acquire_target (economy_and_piracy.md: standing
gates REACTIVE violence only; its victims mark IT hostile through ordinary
attribution).

The canonical hunt job (assembled by tests now, the guild director in M51):

```
GO_TO staging (dark space)            on_abort: -
GO_DARK
SELECT_VICTIM lane                    label: hunt, abort: third_party -> exfil
INTERCEPT                             abort: victim_lost -> hunt, third_party -> exfil
DEMAND_STOP {show_colors}             abort: victim runs/patience -> hunt, third_party -> exfil
TAKE_ALONGSIDE                        abort: victim bolts -> hunt, third_party -> exfil
GO_TO exfil point (dark)              label: exfil
AWAIT track_quiet                     # the launder wait -- fallible heuristic
RELIGHT {new_name, civilian flag}     # ...or EXIT_AT wormhole instead of these two
EXIT_AT / (job complete -> Idle)
```

Cover identity on spawn (transponder_custom_name + a civilian flag) comes
from the spawner in M50 tests; M51 moves it to the guild director.

## Hulls: two delta variants (M24 machinery)

Repurposed civilian designs — same silhouettes, sensors can't out them:

- `scripts/ships/pirate_ore_shuttle.gd` — ore_shuttle + a mining laser
  (the classic desperation refit). Short range, real damage.
- `scripts/ships/armed_pinnace.gd` — pinnace + one light laser.

Route: `Variants.apply` over the base design like pirate_lac.gd. CHECK
ship_variants.gd's op set first — if there's no ADD-component op (pirate_lac
only removes/tunes), author each as a standalone `design()` that composes
the base array + the weapon rect in a free, edge-adjacent slot instead
(validator enforces overlap/connectivity either way). Register in
ship_catalog.gd; `test_ship_designs` covers them like every hull (budget for
EXPECTED_LAYOUT_WARNINGS entries if a warning is frozen-by-design). PD
coherence: these hulls have a weapon and no PD — confirm the validator's
banded expectations for small hulls accept that (the LAC precedent says
yes).

## Victim + world side

- `looted: bool` on Ship (server-side, default false) — set by the take;
  read by tests now, by hunt-mission scoring/economy later. A looted
  shuttle RESUMES its route via existing machinery (RELEASE from the
  pirate, or M49 auto-resume) — no new victim code expected.
- No changes to standing/hail rules — M48/M49 already produce every
  consequence (witnessed demand flips the pirate's track, SOS goes out,
  wanted name is recorded when it's marked).

## Tests

- `test_job_runner` — unit, no combat: scripted micro-jobs assert step
  advancement, scratch reset on entry, abort-edge jump (including jump
  BACKWARD to a label), job-complete → FAILURE, AWAIT duration/timeout,
  `repeat` re-entry, and the two-slot fallback (assignment completes →
  default_job resumes at step 0; assignment aborts out → same).
- `test_visitor_itinerary` — the GENERALITY PROOF: a plain ship runs
  `GO_TO -> DOCK_AT -> AWAIT{undocked} -> EXIT_AT` through the runner
  against a real station; asserts docked then released then departed then
  despawned. This is the trader skeleton, shipped a milestone early on
  purpose.
- `test_pirate_ambush` — e2e mini cluster: pirate (armed_pinnace) arrives
  under cover flag reading NEUTRAL to a watcher, goes dark, lurks; a cargo
  shuttle crosses the lane; assert demand → shuttle complies (M49) → take
  (loot_takes == 1, victim.looted, RELEASE received) → pirate exfils dark
  → relights under the NEW name → reads NEUTRAL again to a fresh observer.
  Robust margins everywhere; seeded RNG; no exact frames.
- `test_pirate_abort` — same setup + a third armed ship closing mid-hunt:
  assert the pirate aborts to exfil (job jumped to the exfil label, victim
  NOT looted, no shots fired by the pirate).
- Full `build.ps1` gate green; watch perf_combat's band (the runner adds
  O(1) per ship per tick; SELECT_VICTIM's scoring is 30-tick-gated).

## Out of scope (lands later)

Guild director + wormhole arrivals/records (M51 — reads loot_takes,
assigns jobs, cover identities). Patrol SOS response + interdiction (M52).
CargoRun/FollowRoute migration onto jobs (mechanical follow-up once the
runner is proven — with the trade directors, M53-ish). Physical cargo,
inspection, pirate reinforcement SOS.
