# Tests that supply the precondition the world never does

A session's worth of findings, and one pattern under three of them.

## The pattern

Three separate mechanisms were built, unit-tested, and green — and could not
run in an actual campaign. Each time, the test constructed the precondition the
world does not supply:

| Mechanism | The test did | The world does |
|---|---|---|
| M59 patrol lane-response | hand-set the patrol's mailbag with `Mailbag.sync_direct` | never fills it — incidents moved only on a DOCK, and the authored patrol route is four waypoints with `loop: true` and no DOCK verb |
| Pirate effectiveness | `pirate_scenarios` starts a pirate at the midpoint of a **14,000u** lane with a victim inbound → 26/36 takes | ~300,000u lanes against a 20,000u detection radius → **0 takes in 15 hunts** |
| M58 transport | tested the dock courier (tier 2) | needed the kin-relay (tier 1) too, which the milestone's own bullet list specified and I did not build |

None of these is a bad test. Each verifies its mechanism correctly. The defect
is that **a test which hands the system its input cannot discover that the input
never arrives.**

This is not fixable by writing more unit tests, because the missing assertion is
about a chain nobody owns: no single leaf, step or director is responsible for
"a patrol has heard of anything", and so no unit test is the natural place to
notice it.

## What does catch it

A **campaign-shaped funnel**: run the real world, count each stage of the chain,
and report WHERE THE COUNT GOES TO ZERO. The empty stage names itself.

`tactical_analysis/sim_runners/information_loop.gd`:

```
1. robberies completed          2. incidents recorded
3. stations holding news        4. notarized warrants
5. patrols holding news         6. lane sweeps started
```

Deliberately NOT a test. There is no correct number yet, and asserting a stage
before its natural rate is known would be inventing a budget. The output is a
diagnosis, not a verdict.

### Two rules learned from building it

**A funnel must lead with its own preconditions.** "0 of 5,206 decisions changed
by risk" reads as *the mechanism is ineffective*. With `risk p95 = 0.0` printed
above it, the same number reads as *the mechanism was never exercised*. Opposite
conclusions from an identical figure, so the precondition check prints ABOVE the
results and says which one applies.

**A funnel must not measure through an instrument known to lie.** Stage 1
initially read `guild.takes_total` — the ledger that books a completed robbery
as `presumed LOST` when the cash-out check-in misses. That is the exact failure
`pirate_scenarios` was written to dodge, reintroduced. The first fix (sum
`loot_takes` across live hulls) was also wrong: a LOST pirate's record is
ERASED, so the count is deleted by the outcome it measures. Robberies are now
counted from the victim's own incident, which survives, with the ledger printed
beside it and a warning when they disagree.

The funnel also caught itself twice — a wrong `Clock` API that ran zero frames,
and a capture pipeline that returned all-zeros because PowerShell wrapped a
native exe's stderr in ErrorRecords. **An all-zero result from a harness
deserves the same suspicion as an all-zero result from the game.**

## The worked example: why campaign piracy lands zero takes

Measured at 6-8 concurrent pirates, 10 haulers, 60 game-minutes — six times the
authored pressure — **15 hunts, 0 takes**.

| Failure | n |
|---|---|
| Never found prey (`hunt time budget spent`) | **8** |
| Reached compliance, lost it to a witness at ~6000u | 2 |
| Victim bolted mid-hold | 1 |
| Ran out of attempts | **0** |

**Speed is not the cause**, and that matters because it is the intuitive suspect
and would have been tuned first. ArmedPinnace is `max_speed 2000` against the
CargoShuttle's `1000`; the low observed capabilities in the comply-or-run log
(287, 299) are the pirate CRUISING at 300 inside `SELECT_VICTIM`, and M52a's
overtaken-check demonstrably works — a hauler ran, was overtaken at 700, and
complied.

The real causes are **encounter geometry** (a 20,000u detection radius on a
300,000u lane — and the pirate's sensor was WORSE than its prey's 22,000) and
**the witness rule at the take** (with 10 haulers, 2 patrols and 13 stations in
one cluster, a pirate working a lane is rarely alone inside 6000u).

## Consequence for M57-M59

All three are downstream of a robbery. Incidents come from robberies, the risk
map from incidents, patrol sweeps from the map. So until encounter rate is
fixed, **none of them can be exercised in a campaign** — `risk p95 = 0.0` across
5,206 routing decisions is the same fact from the other end.

The mechanisms are built and unit-correct. The world does not currently feed
them. That is a different claim from "they work", and worth keeping distinct.

## Status: verified vs built-but-unexercised

| | |
|---|---|
| **Verified in a campaign** | nothing in M57-M59 yet |
| **Built + unit-tested** | incident log, mailbag transport (both tiers), notarization, risk-aware routing, patrol lane response |
| **Measured absent** | robberies at campaign scale (0), and therefore every downstream stage |
| **Instrumented** | the funnel, per-decision counterfactual, risk distribution, latency chain, sweep outcomes |

## In flight

- **Passive array on ArmedPinnace** (45,000u `passive_em`, between civilian
  none and the Frigate's 80,000). Attacks encounter. A/B running against the
  identical config that produced 0 takes.
- **LANE_RUN posture** — proposed, deliberately NOT built while the A/B is in
  flight, because it attacks the same failure and would make neither
  attributable. See `implementation_plans/m51_pirate_guild_design.md`.
