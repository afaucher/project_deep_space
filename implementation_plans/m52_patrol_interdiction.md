# M52 (base) — Patrol interdiction + SOS response

The last unbuilt piece of M52 (design_ideas/economy_and_piracy.md /
implementation_plans/m48_m55_economy_piracy_roadmap.md's M52 section). M52a
(pirate viability), M52b (warrants), M52c (robbery mechanics), M52d (hail
lifecycle) are all built. This is the other side of the encounter: what a
**patrol or station does** when it holds a HOSTILE contact. Today it does
nothing but shoot.

## Root cause (confirmed by playtest, 2026-07-20)

Spawned a pirate, fired on it (making the player HOSTILE per M52b's witnessed-
aggression warrant post), and the home station attacked the player directly
with no demand and no way to surrender. Read from `ai_tree_factory.gd`:
`build_station`'s `Engage` branch is `AcquireTarget -> StationSteerToTarget ->
FireOpportunity` — straight from "found a HOSTILE contact" to "fire," no step
in between. `build_patrol`'s `Engage` is the same shape. M52b built the
warrant *data* layer (an ASSAULT warrant posts correctly, `response_class`
INTERCEPT per the taxonomy) and M52c built the *mechanics* to close on and
demand a target without ramming it — but nothing reads a HOSTILE contact's
warrant and runs the demand-before-fire sequence. This milestone wires that
up, using M52c's INTERCEPT/DEMAND_STOP job steps as-is (no changes needed
there) and M52b's `response_class` to set how much patience the demand gets.

`AcquireTargetLeaf` already refuses to target a `complied_stop` contact
(M49's honor rule) — so "honor surrender" is already true structurally once a
demand actually lands; this milestone only needs to make sure a demand gets
sent BEFORE weapons, not add a separate honor check.

## Design

### 1. Challenge-before-engage (patrol + station)

New leaf, `InterdictLeaf`, inserted into both `build_patrol` and
`build_station` (ai_tree_factory.gd) **between Disengage and Engage**:

- If `actor.assignment` is non-empty, return FAILURE immediately (a demand
  job — or any other assignment — is already running; don't stomp it).
- Otherwise scan `active_contacts` for a fresh (not stale, not `WRECKAGE`,
  not `complied_stop`) contact with `standing == Standing.HOSTILE` that this
  actor has **not already demanded and been refused by** (see "Refusal
  memory" below). If found, look up the matching warrant via
  `Standing.subject_key` + `actor.warrant_index` to read its `offense`, then
  `Standing.response_class(offense)` to pick DEMAND_STOP's `patience`:
  `RESPONSE_MAX` -> short (e.g. 8.0s — "shoot-on-sight-ish, but still one
  demand," per warrants.md's response-level framing), `RESPONSE_INTERCEPT` ->
  normal (25.0s, matching JobSteps' existing default). No matching warrant
  (e.g. HOSTILE via `known_enemy_flags` instead) -> INTERCEPT's default
  patience.
- Assign `actor.assignment` = a 2-step job `[{"verb": "INTERCEPT"},
  {"verb": "DEMAND_STOP", "show_colors": false, "patience": <chosen>,
  "on_abort": ""}]` with `victim_iid` stamped directly (same shape M52c's
  test fixtures use — `SELECT_VICTIM` is a pirate-hunt concept, irrelevant
  here since the target is already known via standing/warrant).
  `show_colors: false` — a patrol/station isn't undercover, transponder
  state is whatever it already is.
- Always returns FAILURE (side-effect leaf, same idiom as `ChallengeLeaf`/
  `BroadcastTransponderLeaf`) — `JobRunnerLeaf`, next in the selector, picks
  up the freshly-assigned job on the SAME tick and starts ticking it
  (returns SUCCESS), which is what actually pre-empts `Engage` below it:
  while the job runs, `JobRunner` claims every tick and `Engage` never gets
  evaluated. This is the whole "demand surrender BEFORE weapons" contract —
  no new gating needed on `Engage` itself.

Selector order becomes:
```
Disengage -> Interdict -> JobRunner -> Engage -> Challenge -> FollowRoute -> Idle   (patrol)
Disengage -> Interdict -> JobRunner -> Engage -> StationKeepingIdle                  (station, inside build_station's inner selector)
```
(`build_station`'s tree has an outer `RootSequence` wrapping
`BroadcastTransponder` + an inner `ActionSelector` — `Interdict`/`JobRunner`
slot into that inner selector, same relative position as patrol.)

Two outcomes once the job runs:
- **DEMAND_STOP DONE** (victim complied) — job completes, `assignment`
  clears. Next tick: `Interdict` sees `complied_stop` on that contact and
  skips it (doesn't re-demand), `AcquireTarget` also skips it (M49 honor
  rule) -> `Engage` FAILURE -> patrol falls through to `FollowRoute` (resumes
  patrol, per the roadmap's "honor surrender, resume patrol"), station falls
  to `StationKeepingIdle`. No further "capture" gameplay — matches the
  roadmap's own note that what "held" means long-term is M54+ content; this
  milestone only guarantees the stop-shooting contract.
- **DEMAND_STOP ABORT** (patience expired un-complied, or victim outpaced —
  JobSteps' existing logic, unchanged) — job ends, `assignment` clears. Next
  tick: `Interdict` must NOT immediately re-assign the same demand (see
  below) — falls through to `Engage`, which now fires, since the contact is
  still HOSTILE and still not `complied_stop`. This is "engage on refusal."
- **Return fire while the demand job is running**: no special handling
  needed — `Disengage` already outranks everything (a crippled patrol
  flees), and if the ship isn't crippled it just keeps pacing/demanding.
  If the roadmap's "engage... on refusal/return fire" wants return-fire to
  cut the demand short rather than wait out the full patience, that's a
  reasonable stretch add (e.g. an `abort_when` condition checking recent
  damage from this attacker) but not required for v1 — a MAX-response
  warrant's short patience covers the common case (sustained assault/armed
  robbery) reasonably well already.

**Refusal memory (needed — an infinite-loop trap otherwise):** without
something remembering "we already demanded this iid and got refused,"
`Interdict` re-triggers the instant `assignment` clears (HOSTILE persists,
`complied_stop` is still false) and the ship demands the SAME target forever,
never reaching `Engage`. Mirror the existing pattern
`JobSteps._blacklist_victim`/`VICTIM_BLACKLIST_FRAMES` already uses for
pirates re-picking a failed victim (job_steps.gd:56-64) — keep a frame-
stamped cooldown dict on the tree's own blackboard (e.g.
`blackboard.set_value("interdict_refused", {iid: expire_frame})`), stamped
when `Interdict` next runs and observes the contact is HOSTILE again with no
fresh demand ever having succeeded... concretely: simplest correct rule is
"never demand the same iid twice while it remains continuously HOSTILE and
tracked" — a bare `Dictionary` of iid -> true on the blackboard, checked
before assigning and set right after assigning (not waiting to observe the
abort — assign-once-per-standing-color is sufficient and simpler). Clear an
iid's entry when the contact is no longer in `active_contacts` at all (died,
went stale) so a LATER, unrelated HOSTILE spell against the same ship (e.g. a
new warrant after a long gap) gets a fresh demand. Implementer's call on
exact bookkeeping; the important invariant is "no re-demand loop," proven by
a test (see below).

### 2. SOS response (patrol only)

New leaf, `SOSResponseLeaf`, inserted into `build_patrol` between `Engage`
and `Challenge` (a closer HOSTILE contact — including one the SOS itself
reported — still wins via `Engage` above it; SOS response is what gets the
patrol close enough to sense one in the first place, per the roadmap's
"comms range >> sensor range — fly to the marker"):

- Read `actor.heard_sos` (already populated end-to-end by the M49 wire
  protocol — `Ship.send_sos`/the `VERB_SOS` receive branch/TTL decay, nothing
  currently reads it). Pick the freshest entry with no responder assigned yet
  (blackboard-tracked, e.g. `blackboard.set_value("sos_responding_to",
  sender_iid)` so an already-committed response doesn't restart toward a
  newer, farther call every tick — resolve one at a time).
  Note `heard_sos["age"]` was renamed/aged as this ship keeps hearing it, and the position field (`sos["pos"]`) is a
  snapshot from send time (the caller may have moved since) — fine for v1,
  "fly to the marker" means the marker, not a live track.
- Steer toward `sos["pos"]` (`_cruise_toward`-equivalent — reuse
  `Steering.steer` the way every other leaf in this file's neighborhood
  does, or just call `JobSteps._cruise_toward` if visibility allows;
  implementer's call) at the patrol's normal cruise speed. Return SUCCESS
  while en route (claims the tick, pre-empting `FollowRoute`/`Challenge`
  below).
- Give up (clear `sos_responding_to`, return FAILURE, resume patrol) once:
  arrived within some close radius (e.g. 1000u — nothing to do once there if
  no HOSTILE ever correlates, the scene has simply resolved), OR the
  `heard_sos` entry for that sender goes stale (`HEARD_SOS_TTL` already
  expires it — ship.gd:2799-2808), OR a HOSTILE contact gets acquired first
  (Engage above already wins the tick in that case; this leaf should also
  self-clear rather than fight it — check for that and bail).

### 3. Suspicion assessment — folded into the warrant pipeline, not new scoring

The roadmap bullet describes a standalone "blackboard scoring" system for
loiter/ignored-challenge/wanted-name. Building a parallel suspicion tier
would duplicate machinery M52b already built for exactly this ("observed,
typed, revocable records with response levels"). Cheaper and more coherent:
treat each suspicion SIGNAL as a **warrant post** using the existing offense
taxonomy, which already has `OFF_NO_ID` and `OFF_OPERATOR_FLAGGED` entries
(`standing.gd:226-228`) with `RESPONSE_INTERCEPT` already assigned — they
just aren't posted by anything yet:

- `ChallengeLeaf._check_windows` already tracks `challenge_ignored[trk] =
  true` (challenge_leaf.gd:92) when a `DEMAND(IDENTIFY)` window expires
  un-relit, but only records it on the blackboard — nothing acts on it. Add
  one call: `actor.post_warrant(Standing.OFF_NO_ID, <claimed name if any>,
  <the contact's signature>, "ignored identify challenge")` right where
  `ignored[trk] = true` is set. This one line closes the whole loop: ignored
  challenge -> NO_ID warrant -> next fusion tick's `compute_standing` reads
  it via `warrant_index` -> HOSTILE -> `InterdictLeaf` picks it up next tick.
  No new scoring code, no new tree node — the existing M52b pipeline was
  already built to carry exactly this.
- Loiter-off-lane and wanted-name detection are explicitly **parked** here —
  genuinely new signals with their own tuning questions (what counts as
  "loitering," and `is_wanted`/`add_wanted` already exist in standing.gd but
  nothing populates the wanted-names registry yet — that's a content
  question, not a mechanics one). Not blocking: the concrete, playtest-
  confirmed gap (no demand before fire) is fully closed by items 1-2 above
  without them. Log as a follow-up, same as M52c parked player autopilot.

## Tests

- **Challenge-before-fire**: a patrol (or station) holding a fresh HOSTILE
  contact never fires its first shot before a DEMAND(STOP) has actually been
  sent (assert on the hail log / `sent_hails`, not just absence of damage —
  weapons cooldown staying at zero across the approach is the collision-free
  proof M52c's tests already use the same pattern for).
- **Refusal -> engage**: a HOSTILE contact that never complies (no AI, holds
  course/stays put) — patience expires, the patrol/station THEN fires
  (weapon cooldown moves), and it does NOT re-demand in a loop first (assert
  exactly one DEMAND(STOP) sent, or a small bounded number, not unbounded).
- **Compliance -> hold, no fire, resume patrol**: a HOSTILE contact that
  complies — zero shots fired ever, and the patrol's job clears and
  `FollowRoute`/`StationKeepingIdle` resumes (not stuck idle forever).
- **Response-class patience**: a `RESPONSE_MAX`-class warrant (e.g.
  `ARMED_ROBBERY`) gets a shorter demand window than a `RESPONSE_INTERCEPT`-
  class one (e.g. `ARMED_THREAT`) — assert the two patience values actually
  differ end to end, not just that `Standing.response_class` returns the
  right string in isolation.
- **The exact playtest regression**: player fires on a station (or a patrol
  witnesses it) -> the responder demands surrender instead of attacking
  outright; player complying is held, not executed (reuses `engage_dead_
  stop()` on the player-analog test ship, same as M52c's Phase 3 pattern).
- **Ignored challenge -> warrant -> intercept**: a fresh UNREPORTED contact
  in controlled space that never answers a `DEMAND(IDENTIFY)` within the
  challenge window ends up with an `OFF_NO_ID` warrant posted against it,
  and (given enough time for the next fusion tick) subsequently gets
  demanded via the new `InterdictLeaf` path.
- **SOS response**: a patrol beyond sensor range but within comms range of
  an `UNDER_ATTACK` SOS breaks off its route and closes on the reported
  position; a stale/expired SOS does not (and does not permanently latch —
  the patrol can still respond to a LATER, different SOS).
- Regression: existing patrol/station/challenge/warrant/pirate test suites
  (`test_patrol_challenge.gd` if present, `test_pirate_ambush.gd`,
  `test_pirate_abort.gd`, `test_warrant_pull.gd`, `test_standing_*.gd`,
  `test_robbery_mechanics.gd`) must keep passing unchanged — this milestone
  adds a new leaf to existing trees, it must not change pirate-side behavior
  (pirates never run `build_patrol`/`build_station`) or the warrant/standing
  machinery itself.

## Non-goals (parked, see item 3)

- Loiter-off-lane detection, wanted-name registry population/UI.
- Any real "capture" mechanic beyond holding fire (confiscation, fines,
  standing decay) — M54+ per the roadmap's own note.
- Return-fire-cuts-the-demand-short (noted as a reasonable stretch in item 1,
  not required — MAX-response's short patience covers the urgent cases).

## Findings (as-built)

Implemented directly (single pass, no subagent handoff). All three design
items built as scoped; no non-goals touched.

- **Item 1, `InterdictLeaf`** (`scripts/ai/leaves/interdict_leaf.gd`, new) —
  wired between `Disengage` and `Engage` in both `build_patrol` and
  `build_station` (`ai_tree_factory.gd`). Scans `active_contacts` for a
  fresh, non-wreck, non-`complied_stop` `Standing.HOSTILE` contact not
  already in the refusal-memory dict, looks up its warrant via
  `Standing.subject_key` + `actor.warrant_index`, and picks patience
  (`PATIENCE_MAX = 8.0` for `Standing.RESPONSE_MAX`, `PATIENCE_INTERCEPT =
  25.0` otherwise — matches `JobSteps.step_demand_stop`'s own 25.0 default so
  a no-matching-warrant HOSTILE gets the same patience as an explicit
  INTERCEPT-class offense, per the plan). Assigns `actor.assignment = {
  "steps": [{"verb": "INTERCEPT"}, {"verb": "DEMAND_STOP", "show_colors":
  false, "patience": <chosen>, "on_abort": ""}], "current": 0, "victim_iid":
  <iid>}` and always returns FAILURE so `JobRunnerLeaf` (next in the
  selector) claims the tick the same frame.
- **Item 2, `SOSResponseLeaf`** (`scripts/ai/leaves/sos_response_leaf.gd`,
  new) — wired between `Engage` and `Challenge` in `build_patrol` only.
  Commits to the freshest `actor.heard_sos` entry (blackboard
  `"sos_responding_to"`), steers toward its snapshot `pos` at 500u/s
  (`Steering.steer` + `apply_control_input`, the same idiom every neighboring
  leaf in this file uses), and gives up on any of the three plan conditions:
  arrived (1000u), the entry aged out of `heard_sos` (TTL already erases it,
  `ship.gd`), or a fresh HOSTILE is already held (self-clear check, since
  `Engage` above already wins the tick whenever that's structurally true).
- **Item 3, ignored-challenge → `OFF_NO_ID`** — one call added in
  `challenge_leaf.gd`'s `_check_windows`, exactly where `ignored[trk] = true`
  was already being set: `actor.post_warrant(Standing.OFF_NO_ID, claimed_name,
  c.get("signature", {}), "ignored identify challenge")` (`claimed_name` is
  `""` for a true UNREPORTED contact, so `subject_key` falls back to the
  signature key — matches the taxonomy's existing `OFF_NO_ID` →
  `RESPONSE_INTERCEPT` entry, nothing new added to `standing.gd`).

### Refusal-memory design (the loop-prevention invariant)

Went with the plan's own "simplest correct rule": a plain `iid -> true`
dict on the tree's own blackboard (`"interdict_refused"`), stamped the
instant a demand job is **assigned** (not on the eventual abort — "assign-
once-per-standing-color"). Every tick, before target selection, the dict is
pruned of any iid no longer present in `active_contacts` at all (dead, or
dead-reckoned past `CONTACT_TIMEOUT` and pruned) — so a later, unrelated
HOSTILE spell against a re-acquired track gets a fresh demand, but a
continuously-tracked refused target never re-triggers. No expiry timer
(unlike `JobSteps.VICTIM_BLACKLIST_FRAMES`'s frame-stamped cooldown) — a
patrol/station's own long-lived contact isn't the pirate's "victim moved on,
try someone else" case; "never re-demand while it stays continuously
HOSTILE and tracked" is the exact invariant the plan asked for, and
`test_patrol_interdiction`'s Phase 1 proves it directly (exactly one
`DEMAND(STOP)` logged, checked both right after the demand arrives and again
after the patrol has been engaging for several more seconds).

### Deviation: a comms-less hull needs an explicit gate

Not anticipated by the plan doc (which was scoped from the playtest's
patrol/station read, not from the M27 mine acceptance test) and found only
by running the full regression suite: `test_mine.gd`'s Mine hull carries no
comms component at all (see its own header comment — `mark_contact_hostile`
is its only legal way to flip a contact HOSTILE, since it can't receive a
transponder flag either). Once `InterdictLeaf` sat in `build_station`, a
`mark_contact_hostile`'d drifting LAC got the mine a full `[INTERCEPT,
DEMAND_STOP]` job it had no way to ever complete: `_hail_range_to` reads
0 with no comms, so `INTERCEPT`'s DONE condition (`close_enough AND
rel_speed <= threshold`) could only be satisfied by physically closing to
the bare standoff distance and matching a moving target's velocity — the
mine hull has no engines, so INTERCEPT never converged, `JobRunner` claimed
every tick indefinitely, and `Engage`/`FireOpportunity` never ran again. The
regression showed up exactly as `test_mine.gd` predicts a broken wreck-gate
would: unbounded excursion (5146u, cap 1200u — the job's own steering
commands, not station-keeping) and the hostile LAC crossing through
completely unharmed.

Fixed with one added gate in `InterdictLeaf`, mirroring `ChallengeLeaf`'s own
identical guard for the identical reason: `if actor.get_comms_range() <=
0.0: return FAILURE` right after the assignment-non-empty check. A hull that
can't send a demand in the first place falls straight through to `Engage`
exactly as it did before this milestone — "demand before weapons" only
applies where a demand is actually possible to send. Re-verified `test_mine`
green after the fix; the rest of the regression suite was unaffected by
either the bug or the fix (no other catalog hull is comms-less and armed).

### Test coverage (`scripts/tests/test_patrol_interdiction.gd`, new)

Six phases, all plan-doc scenarios covered (33 assertions total):

1. Challenge-before-fire + refusal → engage in one scenario (efficient
   reuse: same encounter proves both "weapons stay cold until the demand
   sends" and, after the job's `patience` is shortened mid-flight for test
   speed, "engages after refusal with exactly one `DEMAND(STOP)` ever
   logged" — no re-demand loop, checked twice).
2. Compliance → hold, zero shots ever, job clears, patrol resumes
   `FollowRoute` (position moves measurably after the job clears, proving
   it isn't stuck idle).
3. Response-class patience — two independent patrol/attacker pairs, one
   posted an `OFF_ARMED_ROBBERY` (MAX) warrant and one an `OFF_ASSAULT`
   (INTERCEPT) warrant; asserts the two *assigned jobs'* actual `patience`
   values differ (not just `Standing.response_class` in isolation) and match
   `InterdictLeaf`'s own constants.
4. The exact playtest regression, station side: `SmallStation` +
   `build_station`, hit attributed via `take_damage(..., player_iid)` (same
   effect a landed shot has) — demands instead of instant-attacking,
   compliance (`engage_dead_stop()`, M52c's Phase 3 pattern) is held, never
   executed.
5. Ignored `DEMAND(IDENTIFY)` (test_patrol_challenge.gd's own dark-ship-in-
   zone setup, never relit) → `OFF_NO_ID` warrant posted → `InterdictLeaf`
   picks it up and assigns a demand job against it, end to end.
6. SOS response: a patrol on a long route breaks off toward a fresh SOS
   marker and measurably closes distance; an artificially-staled SOS (age
   forced past `HEARD_SOS_TTL` directly rather than waiting out the real 90s
   — CLAUDE.md-style test shortcut) is pruned and never adopted; after the
   first incident is simulated as resolved (blackboard slot + `heard_sos`
   entry cleared directly — the resolution *mechanism* itself is already
   exercised by the leaf's own logic and the stale sub-case), a later,
   different SOS is still picked up.

One test-isolation bug surfaced and fixed while writing this file, worth
noting since it could bite future test authors in this same style: spawning
phase N+1's ships at the same world positions phase N used, immediately
after `queue_free()`-ing phase N's ships, let phase N+1's fresh sensor
returns proximity-correlate onto phase N's not-yet-actually-freed contact
records (`queue_free()` only takes effect at end-of-frame) — a still-alive,
still-HOSTILE patrol kept firing on what was now a *different* ship simply
because it spawned in the old target's exact spot. Fixed by making the
shared `_free_all()` helper `await` up to 10 physics frames until every
freed node reports `not is_instance_valid()` before the next phase spawns.

### Verification

- All eight named regression baselines plus `test_patrol_interdiction` run
  individually before AND after (baseline captured by `git stash`-ing the
  M52 changes, running clean, then popping): identical pass/fail in both
  passes — every listed test green except `test_pirate_ambush`, which fails
  identically in both (same three assertions, same Phase 4/5 root cause
  already tracked in `implementation_plans/m52d_hail_ux.md`'s Findings — not
  a new failure).
- Full gate (`build.ps1`): first run surfaced `test_mine` as a genuine new
  failure (see the comms-less-hull deviation above); after the one-line fix,
  a second full gate run came back with only the pre-existing
  `test_pirate_ambush` failure. `test_ai_duel` (the CLAUDE.md-documented
  possibly-flaky physics test) passed cleanly on this run.
- `git status`: working tree holds exactly the intended diff (`ai_tree_
  factory.gd`, `challenge_leaf.gd` modified; `interdict_leaf.gd`,
  `sos_response_leaf.gd`, `test_patrol_interdiction.gd` new) plus the
  pre-existing untracked `contacts_dump.txt`/`.uid` files this milestone
  never touched. `tactical_analysis/data/*` perf-baseline churn from running
  the sims was reverted (`git checkout --`) both times it appeared, per
  CLAUDE.md.
