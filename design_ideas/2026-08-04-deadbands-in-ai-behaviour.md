# Deadbands in AI behaviour: never aim at the line you test

## The rule

**If a behaviour STEERS TOWARD a target and TESTS a threshold, the aim point must
sit strictly inside the threshold.** Equivalently: entering and leaving a state
should use different numbers.

A controller that converges asymptotically onto its target — which every pacing,
steering and station-keeping routine in this codebase does — will settle ON the
aim point, not past it. If the test is at the same distance, the agent hovers
at the boundary and any overshoot, drift or target motion leaves it just
outside. Forever.

## The bug that motivated this (D49, 2026-08-04)

`TAKE_ALONGSIDE` paced to a standoff point `range` from the victim and started
its hold only once `dist <= range`. **The aim point WAS the threshold.**

Measured: `held -1.0s` on every failed alongside — the hold never once started.
One pirate spent **~46 seconds at 354u** from a victim it had already stopped,
sent **23 demand refreshes of which the victim received and honoured 22**, and
never covered the last 154 units. The compliance then lapsed on its 6s heartbeat
purely because the approach never finished, and the step blamed the victim
("victim bolted").

Six hypotheses were burned on the *heartbeat* — comms range, wrong-timer reset,
seq mismatch, sender radio, scratch persistence, abort ordering — every one
wrong, because the channel was working perfectly and the pirate simply never
arrived. Fix applied: aim at `range * TAKE_ALONGSIDE_ENTRY_FRACTION` (0.6), leaving the
test where it was.

**IT DID NOT RESOLVE THE SYMPTOM.** Re-measured on two seeds: `held` is still
-1.0 on every failed alongside and takes are unchanged (3 vs 3). The
aim-point-equals-threshold defect is real and the fix is the right shape for it,
but it is **not** the binding constraint on arrival -- something else prevents
the pirate closing the last few hundred units, still unidentified.

That distinction matters for this document: the RULE below stands on its own
reasoning and on five existing instances in the tree, **not** on D49 being cured
by it. A principle argued from a fix that did not work would be a principle
resting on nothing.

## The codebase already does this — it was half-applied

| deadband | where | which half |
|---|---|---|
| `TAKE_ALONGSIDE_EXIT_SLACK` 1.25 | job_steps | **exit** only — the entry margin was missing, which is exactly D49 |
| `PORT_ZONE_EXIT_MARGIN` 200 | ship.gd | exit — stops enter/exit thrash on a zone boundary |
| `HYSTERESIS_MARGIN` 15/lot | route_planner | switching cost — a new route must BEAT the current one by a margin |
| `SEEKER_EDGE_MARGIN` 10 deg | missile_controller | keeps a target off the FOV edge "so it doesn't fall out next frame" |
| `CLEARANCE_MARGIN` 25 | docking_bay | approach clearance |
| `DECIDE_INTERVAL_FRAMES` 1800 | patrol_response_leaf | a TEMPORAL deadband — "a sweep is a commitment, not a per-frame opinion" |

So the idiom is established and understood; D49 was the one place the entry half
was omitted. `SEEKER_EDGE_MARGIN`'s comment is the clearest statement of the
principle already in the tree.

## Two symptoms, one bug

* **Never arrives / hovers** — aim point at or outside the test. D49.
* **Chatters** — state flips every tick because one threshold serves both
  directions. This is what `PORT_ZONE_EXIT_MARGIN` and
  `TAKE_ALONGSIDE_EXIT_SLACK` exist to stop.

They are the same defect with opposite signs, and both are invisible in
aggregate counters: the agent looks busy, the tally reads zero.

## WHEN A DEADBAND IS THE WRONG FIX — this is the important half

A deadband makes a threshold *robust*. It does nothing for a threshold that is
asking the *wrong question*, and it will HIDE one by making the symptom
intermittent instead of constant.

Three fixes in this same milestone were borrowed-predicate bugs, not deadband
bugs:

| | tested | should have tested |
|---|---|---|
| D31 `outpaced` | "is it far away" | "is it **pulling away**" |
| D46 witness | "abandon the trip" | "abandon **this victim**" |
| D47 `victim_lost` | "can I **shoot** it" | "have I **lost** it" |

D31 is the cautionary one: it *had* a margin (1.2x hail range) and was still
wrong, because the margin was applied to the wrong quantity. Widening it would
have masked the problem for longer.

**Diagnostic order:**

1. Is the predicate asking the question this decision actually needs? If not, fix
   the predicate — a deadband here is a coat of paint.
2. Only then: does the agent steer toward the same number it is tested against?
   If so, add the entry margin.

## Practical guidance

* Name the aim point and the test separately, even when they start equal. A
  single constant serving both is the shape of the bug.
* Prefer a **fraction** of the test distance (`* 0.6`) over a subtracted
  constant, so the margin scales when the range is retuned — the same reasoning
  `MIN_HOTSPOT_WEIGHT` uses against `WEIGHT_PER_INCIDENT`, and the mis-scaling
  `HYSTERESIS_MARGIN` hit when `LOT_SIZE` changed.
* When a step has an ENTRY and an EXIT condition, write both explicitly. If only
  one exists, the other is not "unnecessary", it is unexamined.
* **Instrument arrival, not just success.** `held -1.0s` — a field recording
  that the hold never STARTED — is what finally located D49, and it had been in
  the output for several turns before it was read. A counter that only reports
  outcomes cannot distinguish "tried and failed" from "never began".
