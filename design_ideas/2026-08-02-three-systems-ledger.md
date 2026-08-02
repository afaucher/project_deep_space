# Pirate / trade / patrol: the road to a long-horizon sim

**Goal.** Show the three systems interacting correctly over a long time horizon,
capped by an economy sim where all three visibly play together.

**Instrument.** `tactical_analysis/sim_runners/information_loop.gd` — the funnel.
It counts each stage of the chain and reports where the count goes to zero.

**Working rules.** Gate before committing. Never stack two variables into one
measurement.

---

## Success criteria (what "playing together" means)

| System | What we need to see |
|---|---|
| **Pirate** | takes and incidents surfacing reliably, not as a rare accident |
| **Cargo** | the information economy driving route planning — and **urgent routes still being risked** |
| **Patrol** | meaningful engagements, consistently; some pirates actually stopped |
| **All three** | one long economy run where the loop closes without hand-holding |

---

## Ledger: policy & gameplay decisions

Decisions that had to be MADE (not bugs) to get the systems coherent.

| # | Decision | Status |
|---|---|---|
| D1 | A warrant is a **verdict** (keyed, overwriting, O(1)); an incident is **evidence** (immutable, positioned). Never merge them. | settled |
| D2 | Aggregation/recency/clustering is the **consuming director's policy**, never baked into the record | settled |
| D3 | The map lives on the **station record**, not on a director | settled |
| D4 | Transport has exactly **two tiers** — free+instant between IFF kin in range, else you must dock. No middle tier. | settled |
| D5 | The dock merge is **asymmetric**: receive freely, give deliberately. Placeholder give-rule = own flag. | settled (rule is a placeholder) |
| D6 | **Two gates on an arriving hull**: the incident is recorded always; a warrant is issued at the station's discretion, own flag only | settled |
| D7 | Notarize **name-identified reports only** — going dark defeats notarization *by design* | settled |
| D8 | `NAME_WITHHELD` is not a name for subject-keying | settled |
| D9 | **Cargo volume is physical** → one global constant. **Person-area is a standard of living** → bands by class. | settled |
| D10 | **Station bins are policy, not physical space**; a station's cargo_bay is structure only | settled |
| D11 | Cargo-bay-derived capacity applies to **ships only** | settled |
| D12 | Pirate station keep-away is sized against the **mail/comms channel** (60,000), not against a future station passive array — passive detects presence, never identity | settled |
| D13 | Never select a lane shorter than **2× keep-away** — no point on it clears both endpoints | settled |
| D14 | Destroying a victim **degrades** the world's knowledge to OVERDUE rather than silencing it | settled |
| **D15** | Stranded cargo after a clamped delivery: hold-and-re-plan, plus an escape hatch (dump after N / forced sale) | **OPEN — pick one in M55a** |
| **D16** | LANE_RUN flips only when **alone**; stalks at sensor limit | **OPEN — not built** |
| **D17** | A prize takes a clean ID from the **finite kit**, making the kit the single currency for cover-running AND prize-taking | **OPEN — not built** |
| **D18** | Do rival bands under one flag read each other as hostile? | **OPEN** |
| **D19** | Is stolen news attributable (does holding it convict)? | **OPEN** |
| **D20** | Kit size as the real dial on pirate aggression, replacing `hunt_seconds` | **OPEN** |

---

## Ledger: fixed or implemented

| Change | Why it was needed |
|---|---|
| **M57** — incidents as evidence (`SourceLog`, `Incident`, record-backed logs, robbery + OVERDUE producers) | patrols could not plan from warrants: no position, one record per (offense, subject) |
| **M58** — mailbag transport, clamped reads, notarization | a civilian's report was legally inert; transport existed, the counter did not |
| **M58 tier 1** — incidents relay by radio, not only on a dock | patrols never dock, so their mailbags were empty forever and M59's patrol half could never fire |
| **M59** — risk-aware routing + patrol lane response, sharing one `RiskMap` | cargo had a deliberate stub; patrols held warrants but never met the subject |
| `subject_key` — `NAME_WITHHELD` false positive | every name-withholding hull shared the key `name:UNKNOWN`; one warrant marked them all |
| `classify_contact` — unmeasured cross-section is not "tiny" | passive-only contacts classified as INCOMING ORDNANCE. **Observed in play**; PD fired once a pirate had passive reach at short range |
| **Passive array** on ArmedPinnace (45,000u) | the predator's sensor (20,000) was *worse than its prey's* (22,000) on 300,000u lanes |
| Keep-away 25k→60k; ring outer 2.5→1.35; huntable-lane filter | keep-away was smaller than the 30,000u radio it existed to clear |
| The funnel + decision probe + latency chain | every link was unit-green while the chain could not run |
| CLAUDE.md: preload class cycles; "a green unit test cannot tell you the input ever arrives" | both cost real time today |

---

## Measurements so far

| Finding | Number |
|---|---|
| Campaign piracy before the passive array | **0 takes / 15 hunts** at 6-8× authored pressure |
| After the passive array | **2 takes**, funnel reached stage 4 |
| Dominant failure | **encounter** — 8 "no prey found" vs **0** attempt-exhaustion |
| Speed as a cause | **ruled out** — pirate 2000 vs hauler 1000; overtaken-check works |
| Risk term | p95 0.0 → **4.6**; **250 of 5199** decisions changed by risk |
| Latency | station ~0.1s (n=1, inside the comms envelope), patrol ~1005s |

---

## In progress 2026-08-02

**Current action: funnel re-baseline.** Three geometry changes and a
classification fix landed AFTER the last measurement, so the "0 -> 2 takes"
result is stale and nothing downstream can be trusted until it is
re-established.

### RETRACTED: "the sim got expensive" was wrong three times over

Measured on a build that actually compiles: **10.2ms/frame — 184s for 5
game-minutes, ~37 wall-seconds per game-minute.** A 30-game-minute run is ~18
minutes and a 60-minute one ~37. The sim is entirely workable and **D21 is
withdrawn.**

Three wrong explanations were given for the same symptom before measuring:

1. **The passive array** — refuted by `perf_combat`: `sensor_sweep` is 3.65% of
   tick, nowhere near enough.
2. **Scenario size** — plausible but never tested, and wrong.
3. **A hang** — partly true for ONE run (a real `while j == i` infinite loop on a
   single-hub cluster, now fixed), but used to explain runs it did not cause.

The actual causes, separated:

| Run | What was really happening |
|---|---|
| 78-minute, 60 game-min, `JOB_LOG=1` | probably ~90% done and killed prematurely |
| 4.5-hour, stuck at "minute 61" | the genuine `_random_hub_pair` infinite loop |
| everything after the lane-id edit | **the build did not compile** — duplicate `pickup_pos` keys in `route_itinerary`, plus an orphaned `if` with no body in the funnel runner |

That third row is the important one. **A script that fails to compile throws
runtime errors every frame in the AI tick**, which looks exactly like "the sim is
slow". Two of my three explanations were built on measurements of a broken
build.

**The check existed and was skipped.** `build.ps1` runs GDScript syntax
validation as its first step. The heartbeat change was committed without gating,
and "verified" with `test_route_planner` — which does not load sim runners, so a
green test proved nothing about the broken file. *Sim runners are covered by no
test; only the gate's syntax validation catches them.*

Also: reading the lane trace as a progress indicator was wrong twice — it only
writes rows while a hauler holds a planner job, AND the file being read was
hours stale (`FileAccess.open(WRITE)` returns null when another Godot process
holds it, so `_sample_trace` silently skipped). The unconditional heartbeat now
prints `game-minute N / TOTAL` on a path no game state can gate, and it works.

### RE-BASELINE, clean build, 30 game-min (2026-08-02)

```
1. robberies completed             : 1  (live hulls 1, ledger 0)
2. incidents recorded              : 1
3. stations holding foreign news   : 0 of 13
   robbery 9504:1: 127,758u from nearest station (comms reach 30,000u)
>>> CHAIN BREAKS AT STAGE 3
```

**Encounter survived the keep-away rise.** 1 take / 30 min against 2 / 60 min
before — the same rate. Raising `_R_STATION_AVOID` to 60,000 and filtering
un-huntable lanes did NOT undo the passive array's gain. That was the open risk;
it is closed.

**The ledger disagreed with ground truth again** (`takes 0` vs 1 real robbery) —
the cash-out mis-booking, caught only because the funnel prints both.

**Stage 4 -> stage 3 is PROGRESS, not regression.** The robbery happened
**127,758u from the nearest station** against a 30,000u comms reach. Previously
robberies happened INSIDE the station envelope, which is why a station once
"learned in 0.1s" and the chain reached stage 4 — that reach was partly an
artifact of pirates working within earshot of help. D12 removed the shortcut, so
the news must now genuinely travel by hull.

**The open question is now the right one:** has a courier ever actually
completed the delivery? Nothing has yet been observed carrying a robbery report
to a port. A 60-game-minute run is in flight to find out.

### Queue after the re-baseline

1. LANE_RUN A/B, and derive WHEN a pirate prefers each posture rather than
   picking a chance value
2. Cargo: urgent routes still risked — the counterfactual can prove this and a
   traffic histogram cannot
3. Patrols: get engagements happening consistently, then decide what outcomes
   we want

### Practical note for whoever runs the sim next

`JOB_LOG=1` is needed for selection-vs-execution diagnosis and is very
expensive; leave it OFF for a plain re-baseline. And pipe to `Select-String`
rather than `| Out-File` — the latter buffers, so a long run looks silent and
you cannot tell progress from a stall.
