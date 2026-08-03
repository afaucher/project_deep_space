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

### THE COURIER NETWORK WORKS — 60 game-min, clean build (2026-08-02)

```
1. robberies completed             : 2
2. incidents recorded              : 2
3. stations holding foreign news   : 6 of 13
5. patrols holding foreign news    : 2 of 2
   reached a station : 2  (median 1343.8s = ~22 game-min)
   robbery 9505:1: 76,950u from nearest station
   robbery 703:1 : 53,833u from nearest station
   decisions changed by risk : 560 of 5216
>>> CHAIN BREAKS AT STAGE 4
```

Two of the four success criteria now have campaign-scale evidence:

- **Trade/mail.** Robberies 54-77km from ANY station — far outside the 30,000u
  comms envelope, so no radio shortcut — and the news still reached 6 stations
  and both patrols, taking ~22 game-minutes to travel. Information genuinely has
  a position and a velocity, measured on a run where it had to be carried.
- **Cargo.** 560 of 5,216 routing decisions differ from their risk-blind
  counterfactual. The information economy is driving route planning.

### D22 (NEW, decided): an incident's half-life must EXCEED its delivery latency

Patrols hold the news 2/2 and started **zero sweeps**. The arithmetic is exact:

| | |
|---|---|
| `RiskMap.RISK_HALF_LIFE_FRAMES` | 18,000 frames = **5 game-min** |
| measured delivery latency | 1,343s = **22 game-min** ~ 4.5 half-lives |
| a fresh incident's weight | 25 |
| its weight ON ARRIVAL | `25 x 0.5^4.5` ~ **1.1** |
| `PatrolResponseLeaf.MIN_HOTSPOT_WEIGHT` | **20** |

**News arrives already decayed below the threshold for acting on it.** The patrol
can never sweep — not because its map is empty, but because everything in it is
stale on arrival.

This is a policy decision, not a tuning nit. The half-life was chosen as "the
damping term for the predator-prey oscillation" BEFORE any latency existed to
compare it against, and latency turned out to be 4x longer. The rule that
generalises: **in a world where information is carried, any decay constant must
be set relative to the measured delivery time, never in isolation.**

Not yet fixed — deliberately one variable at a time, and this is the next one.

### METHOD FAILURE: the funnel sim was never seeded (fixed 2026-08-02)

`pirate_scenarios` calls `seed(20260731)`. `information_loop` did not. So every
run drew different pirate arrivals, lurk points and lanes — and with only **1-2
robberies per game-hour**, every stage downstream is measured at **n <= 2**.

Two consecutive 60-minute runs, same config:

| | run A | run B |
|---|---|---|
| robberies | 2 | 1 |
| stations holding news | 6 of 13 | 2 of 13 |
| patrols holding news | 2 of 2 | **0 of 2** |
| decisions changed by risk | 560 | 116 |

I reported the delta between runs like these as signal. **It was dice.** Run B's
patrols never received any news, so the D22 threshold change was not disproven —
it was never exercised.

Fixed: `seed(int(_envf("SEED", 20260802)))`, overridable so a sweep can vary it
DELIBERATELY. Same seed = a true A/B of one variable. Different seeds = a sample
of the distribution. Both are useful; mixing them silently is not.

**The standing rule this adds:** with events this rare, a single run is an
anecdote. Either fix the seed and change one variable, or run enough seeds to
have a distribution — and say which you did.

Also note run B was internally coherent, not broken: 2 of 13 stations learned,
and neither was a patrol's home station, so the patrols legitimately knew
nothing. Station-to-station needs a courier. That is the mail model working, and
it means patrol delivery depends on WHICH station happens to hear.

### FIVE-SEED VARIANCE BATCH (2026-08-02) — the sample-size answer

Heavy chain-test config (12-15 pirates, 14 haulers, 60 game-min), five seeds:

| seed | robberies | stations | patrols | sweeps | contacts | risk-changed |
|---|---|---|---|---|---|---|
| 11111 | 2 | 8 | 2 | **52** | **20** | 0 |
| 20260802 | 1 | 5 | 2 | 23 | 1 | 0 |
| 22222 | **0** | 0 | 0 | 0 | 0 | 0 |
| 33333 | 1 | 2 | 0 | 0 | 0 | 155 |
| 44444 | 1 | 0 | 0 | 0 | 0 | 2 |

**D23 (NEW): five seeds at 60 game-minutes is NOT enough to A/B anything.**
Robberies range 0-2 (median 1) and one run produced none at all; sweeps 0-52;
risk-changed decisions 0-155. Any comparison at this scale compares noise. The
fix is LENGTH, not width: 60 game-min yields 0-2 robbery events, so every
downstream stage is a near-binary draw. A 3-game-hour run should give 3-6
events, and five seeds of THAT is a usable sample.

**Patrols receiving news is close to a coin flip** — 2 of 5 — and it is BINARY
(0 or 2, never 1). Both patrols share crypto-kin and orbit near stations, so
once a nearby station knows, both learn together.

**When patrols ARE informed, the mechanism works well.** Seed 11111: 52 sweeps
and **20 hostile contacts**. The patrol half is not weak; it is starved. What
gates it is whether news reaches a patrol at all.

**Notarization was 0 in ALL five runs**, consistent with D7 (an authority cannot
charge an unidentified hull, and these pirates run dark). But it means the
VERDICT branch is currently decorative — it has never once fired in a campaign.

**Prediction to test with LANE_RUN:** a lane-runner is LIT under a cover
identity, so `pirate_claimed` is non-empty and notarization SHOULD fire. If it
does, LANE_RUN is what brings the warrant branch alive — and the cover identity
starts getting burned, which is the whole risk half of that posture.

### Patrol behaviour reworked: ONE weighted draw (2026-08-02)

Replaces a threshold + two branches with a single mixed candidate list:

```
[{hotspot, weight = severity x proximity x recency}, ..., {station, weight = 1}, ...]
-> one weighted draw -> GO_TO . loiter . GO_TO home
```

**D24: a sweep and a routine patrol are the SAME ACT** — go somewhere, look,
come home — differing only in why. Expressing that as one draw deleted
`MIN_HOTSPOT_WEIGHT` as a policy gate, the separate routine interval, and the
"sweep or circulate" branch entirely.

It also fixed the stickiness properly. Deterministic argmax parked a patrol on
one report for its whole ~52-minute actionable life (**52 sweeps off 2
incidents**, measured). Now a fresh incident at 25 competes against ~12 stations
at 1, so it wins ~2/3 of draws — dominant, not absolute — and as it decays its
share falls, so attention drifts to newer trouble or back to circulation with no
"this is stale" rule needed. That closes the open "mark a hotspot answered"
question without a cooldown.

`STATION_WEIGHT` is now the single dial for how much patrols wander when nothing
is happening.

**Patrols are now also COURIERS.** The circuit loiters inside a neighbour
station's 30,000u comms envelope, which ticks the tier-1 mailbag relay — so a
circulating patrol carries news BETWEEN stations. Until now the only couriers
were haulers, and haulers go where cargo is, which is precisely where trouble is
not. No docking mechanics required.

**Return leg is STATED**, not inherited from the diamond route resuming.

### What patrols did BEFORE (for the record)

`_patrol()` authors four waypoints at +/-24,000u around a centre with
`{"route": route, "loop": true}`. They never docked and never left except on a
sweep. Because they orbit at 24,000u inside a 30,000u station comms envelope,
they always knew whatever their home station knew — which is why "patrols
informed" was BINARY across seeds (0 or 2, never 1). The failure was never
patrol connectivity; it was **their home station being ignorant**.

### Population, measured (2026-08-02)

| | authored campaign | heavy test config |
|---|---|---|
| Patrols | **2** | 2 |
| Cargo haulers | **5 authored lanes** | +10-14 planner haulers |
| Pirates | **base_cap 1, max_cap 3** | 6-15 |
| Stations | 8 authored (13 station-kind records) | same |

The real campaign runs **1-3 pirates against 2 patrols and ~5 haulers on
300,000u lanes**. A low encounter rate is arithmetic, not a bug — accepted for
now.

### Economy: the shortfalls are THREE problems, not one

From `economy_traffic.csv` (180 sim-min, 8 haulers, commit 05a4bf1):

| Shortfall | Cause | More haulers? |
|---|---|---|
| VOLATILES at Drift Market + Refinery Prime (**0 deliveries**) | sole producer Coldreach is MERIDIAN-flagged; Drift haulers are INELIGIBLE | **no** |
| VOLATILES cluster-wide | supply 0.77/hr vs demand ~2.02/hr | **no** |
| Refinery Prime ORE (-2.56/hr, 19 deliveries) | genuine throughput gap | probably |

Two of three are supply-side and immune to hauler count. Note also **Slag Bay
ORE reads -2.90/hr and is marked `ok`** while Refinery Prime at -2.56 is
UNDERSUPPLIED — the verdict logic is inconsistent and under-reports ORE.

### D25 (OPEN): cargo evens out the network, but routing depends on mail

Prices are **globally readable today** (`route_planner.gd`: "the board is
GLOBALLY READABLE for now — fog/latency gating is Mail phase 3"), so only the
RISK term is fogged. That is why cargo can still even things out.

The moment prices go behind the fog, a feedback loop appears: **unserved ->
fewer visits -> less mail -> postings unheard -> stays unserved.** Worse than
cargo abandonment, which self-corrects when urgency raises price — here the
rising price IS the thing nobody can hear.

Mitigation already in the world: the **seven beacons** on the Ironhold<->Drift
Market road are described by the pirate guild's own tradecraft as "EM-loud
sensor+comms relays that see and report". Making the beacon road a fixed mail
BACKBONE breaks the loop where it matters and leaves off-road genuinely dark —
which matches the fiction and gives beacons a purpose beyond navigation.

**Tuning order: keep prices global until a backbone exists**, then fog them and
use beacon coverage as the connectivity dial.

### D26 (OPEN): no mail urgency exists

`StationEconomy.urgency()` is first-class for goods; the mail layer has none —
`Mailbag.merge` treats every source identically. The only priority is accidental
and by TYPE: warrants ride the instant radio relay, incidents ride the ~22-min
courier.

`mail_network.md` already names the target: *"Information staleness is just
another urgency... a party's picture ages -> informational urgency climbs ->
someone couriers."* `confirmed_at` exists to price exactly this and nothing
reads it. Sequence AFTER M62 — urgency over an untrustworthy supply of news just
prioritises an empty queue.

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
