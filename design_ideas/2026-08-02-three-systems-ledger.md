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

### Deferred, NOT being worked: the sim got expensive

A 60-game-minute run at 6-8 pirates / 10 haulers consumed **4,665 CPU-seconds
over 78 wall-minutes and did not finish**. Earlier runs of the same shape
completed. Two changes from this session are the likely cause, and both are
mine:

- **The passive array.** Each pirate now sweeps a 45,000u omni `passive_em` with
  180 bins. Sweep coverage scales with AREA, so that is ~5x the old 20,000u
  sensor, on 6-8 hulls at once — and CLAUDE.md already records sensor sweep as
  the dominant per-tick cost. More contacts in range also means more fusion and
  more `compute_standing` downstream.
- **The classification fix**, pushing the same way: passive-only contacts that
  used to short-circuit as INCOMING ORDNANCE now classify as VESSELS, so they
  go through standing computation and warrant-index lookups instead. The gate
  moved 9.425 -> 9.809ms avg, small there, but the gate scenario has no
  passive-heavy pirates in it.

**CORRECTED 2026-08-02, same day.** A parallel `perf_combat` run largely
REFUTES the sensor hypothesis and undermines the framing:

- `sensor_sweep` is **3.65% of tick** (607 us/frame), about a fifth of
  `ship_tick_total`. Multiplying one hull's sweep 5x across 6-8 pirates is worth
  a couple of ms, not the ~27ms/frame the funnel sim runs at. Sensors are not
  dominant enough to be the cause.
- The real difference is SCENARIO SIZE. `perf_combat` runs 6 frigates peaking at
  30 ships and clocks **3.6ms wall-clock/frame**. `information_loop` runs the
  whole home cluster — 13 stations, five asteroid fields, beacons, traffic, the
  economy and three directors. Categorically heavier, and always was.
- **"The sim got expensive" was unsupported.** Earlier funnel runs were never
  TIMED, so there is no before-measurement to regress against. What is actually
  known: a 60-game-minute run at the heaviest config yet, with `JOB_LOG=1`, did
  not finish in 78 minutes. That is evidence about the CONFIGURATION chosen, not
  about a code change.

Lesson worth keeping: an unfalsifiable "it feels slower" turns into a wrong
attribution the moment it is written down as a cause. The perf run cost ten
minutes and killed it.

**D21 (OPEN, DEFERRED — and now much weaker): how expensive is a pirate allowed
to be to simulate?** A real constraint on the long-horizon goal rather than a tuning
detail — the deliverable IS a long sim, and the encounter fix made that sim
materially more costly. **Deliberately not being optimised now**: chasing it
before the re-baseline would mean tuning against numbers we have not measured,
and it would stack a second variable onto the geometry changes already in
flight.

Levers if confirmed, cheapest-fidelity-cost first:

| Lever | Effect |
|---|---|
| `num_bins` 180 -> 90 | halves binning; passive yields bearing only, so resolution matters least |
| `refresh_interval` 1.0 -> 2.0 | halves sweep frequency; a lurker does not need 1Hz |
| range 45,000 -> 35,000 | -40% area, but directly undoes the encounter gain — try last |

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
