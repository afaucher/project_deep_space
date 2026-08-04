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
| **D16** | LANE_RUN flips only when **alone**; stalks at sensor limit | **CORRECTED 2026-08-03: mostly BUILT.** LANE_RUN itself shipped (see D27) and the alone-gate is live — `step_select_victim` drops any candidate with another fresh vessel inside `witness_range` (`_R_THIRD_PARTY`), so a victim with company is never viable. **Only the stalk-at-sensor-limit half is unbuilt**; there is no shadowing phase anywhere. This row read "not built" for both halves and was simply stale. |
| **D17** | A prize takes a clean ID from the **finite kit**, making the kit the single currency for cover-running AND prize-taking | **OPEN — not built** |
| **D18** | Do rival bands under one flag read each other as hostile? | **OPEN** |
| **D19** | Is stolen news attributable (does holding it convict)? | **OPEN** |
| **D20** | Kit size as the real dial on pirate aggression, replacing `hunt_seconds` | **OPEN** |
| D21 | Sim slowness blamed on the passive array | **RETRACTED** — refuted by perf_combat (3.65% of tick); real cause was a broken build |
| D22 | A decay half-life must be set against **measured delivery latency**, never in isolation | settled — 5 min → 30 min, news was stale before it landed |
| D23 | Five seeds at 60 game-min **cannot A/B anything** | settled (method) |
| D24 | A sweep and a routine patrol are the **same act** — one weighted draw over hotspots + stations | settled, built |
| D25 | Cargo evens the network but rides on mail; prices are **globally readable**, so the loop does not bite | **superseded by D36 → planned as M64** |
| D26 | Mail urgency as a routing consideration | **superseded by D36 → planned as M64** (`m64_price_fog.md`) |
| D27 | LANE_RUN off by default | **REVERSED by D39** — both the reasoning (D38) and the objective were wrong |
| D39 | **LANE_RUN back ON by default.** The posture exists to raise ENCOUNTER VOLUME for simulation fidelity, not to maximise takes — and it demonstrably does | **NEW 2026-08-03, decided** |
| D40 | **Pirates aim badly — MEASURED.** `efficiency` 0.00/0.05/0.20 against a 0.28–0.44 ceiling; the busiest lane (42–63% of all cargo) was picked 0 times in 3 seeds | **NEW, confirmed** — targeting, not density/sensors |
| D41 | **Cargo does NOT flee pirates — and my test could not have seen it if it did.** 3-game-min window vs ~22-min courier latency | **RETRACTED as untested** — window fixed to 22 min, needs re-run |
| D42 | **Cargo herds onto one lane** (40–63% share). 14 haulers, one argmax, one global board. M64 fog should disperse them WITHOUT irrational noise | **NEW, open** — likely explains UNSERVED |
| D43 | **Weighted draw + outcome-updated per-lane weights** for pirates: prior from the heard board, takes up / empties down, sample never argmax | **NEW, planned in M60d** — makes `returned_empty` productive and the oscillation emergent |
| D38 | **LANE_RUN DOES find prey better** — no-prey aborts 163→142 (4/5 seeds), found-but-failed 3→9. The bottleneck moves from ENCOUNTER to EXECUTION | **NEW 2026-08-03 — reopens the posture question** |
| D28 | A cornered pirate needs a demand handler; `build_pirate` had none, so refusal was 100% structural | settled, built (`OutlawResponseLeaf`) |
| D29 | An authority notarizes what it **HOLDS**, not what docked; gate 2 moves to the **source's** flag | settled, built — 0 → 22 warrants |
| D30 | Patrols pursue at `cruise` 400 and so lose chases | **REFUTED** — bit-identical 5-seed run; `cruise` caps only the catchup term. Reverted |
| D31 | `outpaced` must mean "pulling away", not "far away"; leaving hail range only stops the *channel* | settled, built — outpaced 5 → 0 |
| D32 | **"You cannot shake them" beats "you are slower"** — the outcome of the chase decides, not paper speed | settled, built — 0 → 4 stops |
| D33 | A patrol's stop must *do* something; `HULK_PRIZE` is the short-term answer | **built**, but what a stop should ultimately MEAN is **OPEN** |
| D34 | The shoot-if-justified ladder already existed and was **unreachable** until D29 landed | settled (context) — identity is what makes you shootable |
| D35 | **Crew** is what makes surrender rational again — hull lost either way, crew survives a surrender | **OPEN** — lands in M55 (warships have zero crew space today) |
| D36 | Urgent routes are never risked because of **substitutability**, not a missing payout term; posting **fog** is the fix | **CORRECTED**, planned as **M64** — prerequisite for criterion (3) |
| D37 | The hulk gate keys on the **warrant**; an empty warrant means *uncapped* (colour-flying pirate) | settled for now — reviewed and kept |

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

### LANE_RUN A/B — 5 seed pairs, 60 game-min (2026-08-03)

| metric | OFF -> ON | seeds |
|---|---|---|
| robberies | 10 -> **9** | 2 up / 3 down |
| stations informed | 31 -> 18 | 2 up / 3 down |
| patrols informed | 10 -> 6 | 0 up / 2 down |
| **diverted (cargo)** | 3161 -> **1457** | **0 up / 5 down** |
| notarized | 0 -> 0 | — |

**D27 (decided, BUILT 2026-08-03): LANE_RUN stays OFF by default.**
`pirate_guild.gd:lane_run_enabled` now defaults `false`, and the funnel's
`LANE_RUN` env default moved to 0 to match -- a sim whose default differs from
the shipped default measures a configuration nobody plays. No encounter benefit, and the
only clean 5-of-5 signal is that it HALVES cargo's awareness — same incident
count, far less propagation. Lane-running suppresses the information economy
without buying takes. `lane_run_enabled` remains available; the mechanism for
the propagation loss is NOT established and is deliberately not guessed at.

**My prediction failed.** I expected a lit lane-runner under a cover identity to
make notarization fire for the first time. It stayed 0 in all ten runs — see
below; the cause was never the pirate's identity.

**Caveat added 2026-08-03 on what this A/B actually compared.** The alone-gate
(D16) was already live for BOTH arms, so this was never "lane-run vs park" in
the full sense the posture was designed for — both arms only ever engage
isolated prey. What is still missing from the posture is the STALK phase
(shadowing at sensor limit before closing), so the lane-runner flips as soon as
it finds a lone target rather than trailing it first. The verdict "no encounter
benefit" is therefore about lane TRANSIT alone, and does not retire the posture
idea. Re-run the A/B if the stalk is ever built.

### D28 (NEW, structural): pirates CANNOT comply with a demand

First run of `EngagementProbe`, and it answers criterion (4) outright:

```
interdictions started : 39      COMPLIED (stopped) : 0
refused (patience)    : 27      outpaced           : 0
stop rate             : 0%
```

Zero outpaced means patrols KEEP UP. The subject simply never stops — because
`ThreatResponseLeaf`, the comply-or-run handler, exists **only in
`build_cargo`**:

| tree | leaves |
|---|---|
| `build_cargo` | ShouldDisengage, Flee, **ThreatResponse**, CargoRun, Idle |
| `build_pirate` | ShouldDisengage, Flee, JobRunner, Idle |

A pirate receiving `DEMAND_STOP` has nothing that reads `pending_demand` at all,
so patience expires 100% of the time BY CONSTRUCTION. "Patrols never stop
pirates" was never a tuning problem.

Open design question this forces: **what SHOULD a cornered pirate do?** Comply
and be arrested, run, or fight? Cargo's comply-or-run compares speeds; a pirate
weighing arrest against a firefight is a different calculation, and picking one
is a policy decision, not a port of the cargo leaf.

### D29 (NEW): notarization only reads the DOCKING hull's own log

Confirmed across all ten runs: 18-31 stations HELD robbery news and issued zero
warrants. `Ship.notarize_from(visitor, prev_seq)` walks
`visitor.get_incident_log()`, so a warrant can only ever be issued when the
VICTIM PERSONALLY docks at an own-flag station. News carried by a courier — the
normal case, and the whole point of the mail network — is unnotarizable.

An authority should act on evidence it HOLDS, regardless of who carried it.

**BUILT 2026-08-03** -- `Ship.notarize_held(cluster)` walks every source the
station's mailbag entitles it to read, clamped to the delivered version, with a
per-source high-water mark (`_notarized_seq`) as the dedupe. `notarize_from` and
`notarize_held` now share one `_notarize_entries()` judgement so the filters
cannot drift.

**Gate 2 moved rather than weakened**, and this is the part worth remembering:
own-flag now tests the SOURCE record's flag -- whose citizen was robbed -- not
the courier's. The question was never who carried the letter. A Drift port still
refuses a Meridian victim's robbery out of the same bag, in the same dock, from
the same Drift courier; `test_mail_network` [7b] pins exactly that pair.

The fog survives the change: a robbery on a record the port has never been told
about notarizes nothing, even though the record sits in the same cluster.

**All three findings are the same shape**: a mechanism that cannot fire,
invisible until something counted OUTCOMES rather than attempts.

### D29 measured — the verdict branch closes for the first time (2026-08-03)

Same 5 seeds as the LANE_RUN A/B's OFF column, D29 the only change:

| seed | robberies | stations w/ news | **notarized** | patrols informed | sweeps | verdict branch |
|---|---|---|---|---|---|---|
| 11111 | 2 | 7/13 | **10** | 2/2 | 13 | CLOSED |
| 22222 | 1 | 0/13 | 0 | 0/2 | 11 | evidence never reached a station |
| 33333 | 2 | 8/13 | **7** | 2/2 | 18 | CLOSED |
| 44444 | 1 | 8/13 | **5** | 2/2 | 19 | CLOSED |
| 55555 | 2 | 8/13 | 0 | 2/2 | 14 | pirate ran DARK — correct refusal |

Was 0 in all ten prior runs. **3 of 5 seeds now close end to end**, and both
zeros are explained rather than unexplained: 22222's news never reached any
station at all (stage 3, upstream of notarization), and 55555's robber was
unidentified — an authority refusing to charge "a ship, about this big" is the
designed behaviour, not a failure.

**Read the warrant count correctly**: it is SUMMED ACROSS STATIONS. Two
robberies reading 10 is one verdict held at five ports, each authority issuing
its own — correct, and a genuinely misleading number. The instrument now prints
`(summed over N of M stations holding one)`.

### Two instrument bugs found while reading the above

Both were in the funnel itself — the thing every claim in this ledger rests on.

1. **`haulers holding foreign news: 33 of 14`.** The numerator counted every
   non-station non-authority RECORD (pirates, guild-spawned traffic, anything
   the cluster made); the denominator was the authored hauler count. A ratio
   whose halves count different populations is not a ratio, and this one
   exceeded 100% for ten runs without being questioned.
2. **The warrant sum read as a per-robbery count** (above).

Neither changes a conclusion already drawn, but the corrected hauler figure
changes a PICTURE. Seed 11111 now reads:

```
notarized : 10 (summed over 5 of 13 stations holding one)   <- 2 each = the 2 robberies
haulers   : 33 of 131 civilian hulls (14 authored)          <- 25%, not "236%"
```

So the cluster runs ~131 civilian hulls and roughly a QUARTER of them hold any
foreign news at all. "33 of 14" read like saturation; 25% is a sparse
information economy, and criterion (3) has to be judged against that.

Both bugs are the same failure the preconditions doc is about: an instrument
nobody audits becomes the evidence.

Re-running seed 11111 after the fixes reproduced it exactly -- 2 robberies,
7/13 stations, 10 warrants, 13 sweeps -- so `seed()` is doing its job and these
comparisons are real A/Bs rather than dice.

### D28 BUILT + measured (2026-08-03) — and it exposed D30

`OutlawResponseLeaf` sits between Disengage and JobRunner in `build_pirate`,
the slot `ThreatResponseLeaf` holds in `build_cargo`. A separate leaf, not a
reuse, because the two hulls answer different questions:

> a hauler weighs *"can I outrun this, or do I lose the cargo?"*
> an outlaw weighs *"can I outrun this, or do I lose the SHIP AND MY FREEDOM?"*

So an outlaw runs on a thinner margin (`run_speed_ratio` 1.05 vs cargo's
1.3/1.6). That static is THE dial for patrol effectiveness and is meant to be
swept — but see D30 before touching it.

**Deliberately not built: fight.** `build_pirate` has no Engage leaf at all
(pirates fight through job steps), so a stand-and-fight branch is new combat
machinery, not a policy toggle. Run-or-comply makes stops POSSIBLE, which is
what the goal asks for first, without answering fight-or-surrender by accident.
No SOS either: an outlaw cornered by an authority has nobody to call.

| 5 seeds | before D28 | after D28 |
|---|---|---|
| interdictions | 39 | 12 |
| complied | 0 | 0 |
| refused (patience) | 27 | 4 |
| **outpaced** | **0** | **5** |

**Outpaced 0 -> 5 is the proof the handler fires.** Before, no pirate ever ran
from a patrol; now nearly half of all interdictions end with one running and
getting away. The mechanism works. The OUTCOME is still zero stops.

**Caveat, stated because it would be easy to over-read the table**: adding a
leaf changes `randf()` consumption order, so these runs are NOT seed-matched to
the earlier ones (seed 55555's robberies went 2 -> 4). The outpaced signal is
large and directional; the smaller cells are not a paired comparison.

### D30 (NEW, and it is not a balance problem either)

Why does a pirate outrun a patrol? It should not be able to:

| hull | max_speed |
|---|---|
| LightAttackCraft (patrol) | **2200** |
| ArmedPinnace (pirate) | 2000 |
| PirateOreShuttle (pirate) | 1000 |

The patrol is FASTER than both pirate hulls. It loses the chase because
`InterdictLeaf` builds its `DEMAND_STOP` step without a `cruise`, so
`step_demand_stop` falls through to its **default `cruise` of 400.0** — while
the fleeing pirate runs at `RUN_SPEED` 900 and upward. The patrol pursues at
under a fifth of the speed it owns.

This never mattered before because the subject never ran.

### D30 REFUTED, same day, by its own measurement — and the change reverted

I set both steps' `cruise` to `actor.max_speed` and re-ran the same 5 seeds.
The funnel came back **bit-identical** — every seed, every stage, including the
RNG-sensitive robbery counts. By CLAUDE.md's own rule (identical number =
deterministic, not jitter) that is not a weak effect, it is NO effect: the code
path never behaved differently, so `cruise` was never the binding constraint.

Reading `_pace_at_offset` properly instead of reasoning from the call site:

```gdscript
catchup     = clampf(sqrt(2.0 * accel_max * SAFETY * dist), 0.0, cruise)
desired_vel = target_vel + avoided.normalized() * catchup   # <-- target_vel!
```

`cruise` caps only the CATCHUP term, which is added ON TOP of the target's own
velocity. It was never an absolute speed cap, so "the patrol chases at 400"
was simply false. And since raising the cap changed nothing at all, `catchup`
never reached even the old 400 — the pursuit is **acceleration**-limited, well
below where either cap bites.

**The change was reverted.** A no-op carrying a comment that claims to fix a
chase is worse than no change: the next reader inherits a confident wrong
mechanism. D30's diagnosis is withdrawn; only the observation survives.

**Why "outpaced" actually happens is now UNMEASURED**, and this is the second
time in two days that reasoning from the shape of the code produced a confident
wrong cause (CLAUDE.md already records the `heat_em_component_loop` pair). The
next step is instrumentation of an actual chase — patrol speed, subject speed,
separation, per second — not a third guess.

### D31 — "outpaced" measures the wrong thing (2026-08-03)

Three guesses at why patrols lose chases, all wrong, all propulsion theories:
the `cruise` cap (D30, refuted by a bit-identical run), top speed, acceleration.
`pursuit_trace.gd` — one patrol, one fleeing pirate, real hulls, real leaves —
killed the whole category:

```
patrol accel 115.6 u/s^2  vs  pirate 79.8      patrol also has the higher top speed
separation: 2481 -> 536 -> 1870 -> 760 ...     oscillates, never escapes
hail_range 27000, abort at 32400               separation peaked at 2481
```

**In a clean 1v1 the patrol never loses.** So it is not speed, not acceleration,
not a cap. I should have written that 40-line rig before the first guess.

Instrumenting the geometry instead (`EngagementProbe.opening_summary`) gave the
answer in one run — **median `sep/hail` = 1.00, max 1.00, across every seed.**

That is not a bug, it is DESIGN. `step_intercept` completes at
`dist <= hail_range` on purpose, from a 2026-07-23 playtest decision recorded in
its own header: *"hail from farther away, fly colors, THEN get into position"* —
because the previous behaviour read as "they were trying to board me before the
hail even showed up."

**The contradiction is downstream.** `step_demand_stop` aborts when
`dist > hail_range * 1.2`. A step that deliberately opens at 1.0x leaves the
chase exactly 20% of margin. That was invisible for as long as no subject ever
ran — which was every day until D28 shipped.

So `outpaced` currently means **"it is far away"** when it should mean **"it is
pulling away from me."** An absolute-distance test cannot tell the 1v1 trace's
healthy oscillation (536 -> 1870 -> 760, closing overall) from a genuine escape;
it fires on the 1870 and abandons a chase the patrol was winning.

**Proposed (not yet built): outpaced = losing ground.** Compare separation
against its own recent minimum over a window, abort only when the subject has
genuinely opened the gap, and keep a generous absolute ceiling as a backstop so
a patrol cannot chase across the cluster forever. Its own measurement, alone.

**The pattern, four for four**: D28, D29, D30's observation, and now D31 are all
defaults or tests that were correct only while the mechanism upstream of them
was dead. Fixing one exposes the next.

### D31 BUILT + measured (2026-08-03) — and the chase is a STALEMATE

`step_demand_stop` no longer aborts when the subject crosses 1.2x hail range.
Crossing that line means only that the two hulls cannot talk, so the demand
channel cannot be refreshed — a reason to go quiet, not to give up, and exactly
the channel model `test_demand_lifecycle` already pins ("no RELEASE verb; the
channel expresses that by going quiet"). Verified rather than assumed:
`Hail.send` computes `link_range = min(sender_range, their_range)` and skips
receivers beyond it, so the refresh self-gates with no new plumbing. `patience`
is now the real limiter; a 4.0x hail ceiling remains as a backstop against a
patrol towed across the cluster.

| 5 seeds | before D31 | after |
|---|---|---|
| outpaced | 5 | **0** |
| refused (patience) | 4 | 11 |
| complied | 0 | 0 |

Every abandoned chase converted into a chase the patrol actually stayed with.
The mechanism does what it was meant to. Stops are still zero.

**And a 90s trace says more patience will not fix that**, because the pursuit
does not converge — it settles:

```
t=20  sep  536   patrol 1249  pirate 1259
t=30  sep 1416   patrol 1587  pirate 1364
t=40  sep  796   patrol 1546  pirate 1626
t=60  sep 1090   patrol 1698  pirate 1710
t=70  sep 1123   patrol 1805  pirate 1826
```

Separation oscillates around ~1000u indefinitely. Both hulls climb toward
~1800 and hold near parity. The patrol never reaches standoff; the pirate never
escapes.

**Why that yields no stop**, and it is a near miss: the pirate complies when
`max_speed <= observed_patrol_peak * run_speed_ratio`. Its max is 2000; the
patrol's observed peak sits ~1805, so the test reads 2000 <= 1895 — false, by
about 5%. The pirate keeps running because on paper it IS still marginally
faster, and it is right.

### D32 (OPEN, a real design decision now — not a bug)

Interdiction is currently a pure speed race that near-parity hulls cannot
resolve. Three ways out, and they are genuinely different games:

1. **Patrol hulls outclass pirate hulls** (LAC above 2200). Simplest; makes
   fleeing pointless and interdiction near-automatic.
2. **"You cannot shake them" beats "you are slower".** An outlaw held at close
   range for a sustained stretch concludes the pursuit will not break and heaves
   to, regardless of a 5% paper advantage. Better fiction, and it makes the
   PURSUIT the thing that wins rather than the stat block.
3. **Patrols disable rather than ask.** Weapons enter the interdiction ladder,
   which is a much larger change and turns every stop into a fight.

My recommendation is (2): it is the only one where the outcome follows from what
happened in the chase rather than from a number chosen in advance, and it does
not require touching hull balance or building combat machinery. It is still a
gameplay call and is recorded here rather than made silently.

### D32 BUILT + measured — criterion (4) is non-zero for the first time

The comply rule was a PREDICTION made at demand time ("am I faster on paper?").
D32 adds the OUTCOME actually observed: *I have run for SHAKE_OFF_SECONDS and I
am no further ahead.* `SHAKE_OFF_SECONDS` 15s sits under `PATIENCE_INTERCEPT`
(25s) so the decision is reachable, and over `PATIENCE_MAX` (8s) so a
shoot-on-sight-grade interdiction still expires first.

| seed | interdictions | complied | refused | stop rate |
|---|---|---|---|---|
| 11111 | 2 | 0 | 2 | 0% |
| 22222 | 10 | **2** | 3 | 40% |
| 33333 | 1 | **1** | 0 | 100% |
| 44444 | 0 | — | — | n/a |
| 55555 | 3 | **1** | 2 | 33% |

**0 -> 4 stops across 3 of 5 seeds.** Not a surrender switch: `test_outlaw_
response` S2 now runs 25s — PAST the 15s window, which the original 10s version
never did — and asserts the runner gained more than `SHAKE_OFF_GAIN`; a
genuinely faster pirate opens 3000 -> 11692 and never heaves to.

### D33 (NEW, and it makes the number above nearly meaningless)

**What does a patrol do when it actually catches a pirate? Nothing.**

Traced end to end:

1. `step_demand_stop` sees `complied_stop` -> `DONE`.
2. The interdiction job is `[INTERCEPT, DEMAND_STOP]` — two steps — so DONE on
   the last one means `current >= steps.size()` -> `_complete_job` -> the
   assignment slot is CLEARED.
3. The patrol resumes its route. It stops refreshing the demand, so the pirate's
   `compelled_stop` lapses on the ~6s heartbeat timeout.
4. The pirate resumes its hunt job and carries on.

No arrest, no impound, no escort, no cargo recovery, no crew — grepped, the
concept does not exist anywhere (the only "arrest" in the tree is a docking
servo arresting a hull's motion). And `OFF_ARMED_ROBBERY` is
`expires_after: -1.0` with no `self_resolves_on_id`, so **the warrant never
clears**; being stopped does not discharge it. `InterdictLeaf`'s refusal memory
was stamped at assignment and only clears when the track drops entirely, so the
patrol will not even re-interdict the same hull meanwhile.

**The asymmetry that names it**: the pirate's version of this exact manoeuvre,
`TAKE_ALONGSIDE`, sets `victim.looted = true`, moves cargo, and records an
incident. The pirate's stop changes the world. The patrol's stop changes
nothing.

**So D32's stop rate is a mechanism metric, not an outcome metric.** Optimising
it further would raise a number while the game stayed identical — the same trap
as the 33-of-14 hauler ratio and the summed warrant count, in a third costume.
"Get meaningful engagements happening — THEN refine desired outcomes" turns out
to be two pieces of work and the second is entirely unbuilt.

Candidates for what a stop should MEAN, roughly by cost: cargo recovery to the
victim's flag · a warrant that discharges on submission · escort-to-station ·
impound (the hull stops being a pirate) · crew arrest. **Open — a gameplay
call, deliberately not made here.**

### D34 (context for the above): the escalation ladder already exists

`acquire_target_leaf.gd`'s aggression cap already implements "shoot only if
justified": *"when the ladder is refused, an uncapped offense falls through to
Engage and a capped one does not. A NO_ID hull gets chased and hailed and
refused docking, never shot."* `authorizes_force` is a separate column from
`response_class` so the two can differ — ARMED_ROBBERY authorizes force,
ARMED_THREAT and NO_ID do not.

**It was structurally unreachable for piracy until D29 landed today.** A patrol
can only shoot on a warrant it HOLDS, and notarization read 0 in every prior
run — so no patrol ever held an enforceable armed-robbery warrant, so
`authorizes_force` could never be true for a pirate. A complete, tested ladder
that nothing could climb. **Fifth instance of the pattern.**

This also gives going dark real teeth: an unidentified pirate cannot be
notarized, so no warrant, so no force authorization. **Identity is what makes
you shootable**, and criterion (4) is downstream of the information economy
rather than beside it.

Mechanical limits found while checking: no component targeting exists anywhere,
so "aim for the engines" is new machinery, not a flag. And damage cannot slow a
hull in a straight line — `get_ship_max_thrust()` scales with component health
but `max_speed` is a flat authored field, never derived. Drive damage cuts
ACCELERATION only, which does bite in an oscillating chase but can never make a
pinnace slower than 2000.

### D35 — hulking a prize, and why CREW is what makes the incentive honest

**Built (short term): `HULK_PRIZE`.** A third step on the interdiction job that
destroys a captured hull, appended by `InterdictLeaf` **only when
`Standing.authorizes_force(offence)`** — the same column the aggression cap
already uses to decide whether a refused demand may reach weapons. No new
machinery at all: `Ship.hulk()` exists, and `fire_opportunity`, `flee`,
`interdict`, `sos_response` and `Standing.track_engageable` each already skip a
WRECKAGE contact.

**It feeds a governor that already exists**, which is the real reason this is a
good shortcut rather than a stopgap: a hulked pirate books LOST, driving
`losses` and `loss_streak`; at `losses_per_cap_cut` (2) the guild CUTS ITS CAP
and raises `backoff_factor`. Enforcement thins the ranks and slows arrivals
instead of merely deleting one hull. The lane gets safer through the director's
own feedback loop.

**The tension it creates, stated plainly:** hulking on capture makes surrender
strictly worse than fleeing — and D32 has just taught pirates to surrender when
they cannot shake pursuit. They would comply into destruction. It is harmless
TODAY only because the outlaw's decision has no term for it.

**And CREW is the resolution, not a patch.** The value at risk differs by layer:

| | runs and is caught | heaves to |
|---|---|---|
| **hull** | hulked | hulked |
| **crew** | may die in the fight | survives |

Once crew is simulated, surrender is the CREW-preserving move even though the
ship is lost either way, so heaving to becomes rational again on its own terms.
The outlaw's decision gains a second term — *can I outrun this* AND *what
happens to my people if I cannot* — and that is a better decision than the pure
speed race it is today.

It also gives the patrol's side real weight, and makes the earlier "if we are
not committed to killing them we might let them get away" concrete: hulking a
SURRENDERED ship kills nobody, while firing on a FLEEING one might. The
escalation ladder stops being about damage numbers and starts being about who
dies.

**Interim gate meanwhile:** hulking is tied to the OFFENCE, not to compliance,
so an armed robber loses its hull and a NO_ID or ARMED_THREAT hull that complies
is released. Severity of the act decides the consequence, not whether the
subject was polite about it — which keeps the incentive from inverting for the
capped tiers even before crew exists.

Prerequisite already scoped: `m48_m55_economy_piracy_roadmap.md` carries
`living_quarters` across the fleet and lists "boarding depth (crew, capture-the-
hull — ties into hulk revival contract)" as open. **Every warship currently has
ZERO crew space**, which that roadmap already flags as a catalog problem
predating both cargo and crew — so crew lands there, not here.

### Criterion (3) resolved into its two halves (2026-08-03)

**A fourth instrument bug, and this one was actively lying.** The funnel printed
both of these in the same report:

```
risk p95 / max            : 0.0 / 0.0
>>> RISK WAS ALWAYS ZERO -- the cargo half of M59 is UNTESTED by this run
decisions changed by risk : 1614 of 6685
```

Both cannot be true. `DecisionProbe` sampled `chosen.risk` — the WINNER's risk —
to answer "did risk ever get large enough to matter". **A lane rejected BECAUSE
it was dangerous is by construction not the winner**, so the sample was
systematically zero: survivorship bias in the metric whose entire job was to
validate the rest of the report. The banner is the first thing the funnel tells
you to read, and its own comment says a zero "means something completely
different depending on this number" — it was the number that was broken.

Fixed by sampling what the SEARCH SAW: `best_route` now stamps `max_risk_seen`
over every scored candidate, and the probe records that. Re-measured:

| seed | risk p95 / max (margin 60) | decisions changed | risked anyway |
|---|---|---|---|
| 22222 | 0.0 / 0.0 → correctly UNTESTED | 0 of 6714 | 0 |
| 33333 | **69.1 / 82.8** | **460** of 6701 | 0 |
| 55555 | **78.2 / 96.1** | **1614** of 6685 | 0 |

Self-consistent now: where risk is non-zero decisions change, where it is zero
none do. Seed 22222 — whose news never reached any station — is the control, and
it correctly reports UNTESTED instead of tarring all three.

**First half PROVEN.** "The information economy actually driving route planning"
is measured, not inferred: risk clears the hysteresis margin and redirects
hundreds of decisions per run, and the counterfactual re-scores the same world
with the reader's own news removed, so it cannot be confused with a traffic
histogram.

**Second half FAILS.** `risked_anyway = 0` in every run ever recorded. No hauler
has ever knowingly flown a lane it heard was dangerous. That is exactly the
failure `DecisionProbe`'s own header named in advance: *"a risk term that ONLY
ever makes haulers flee would strangle the lanes it was added to make
interesting… a veto is the failure mode."*

**D36 (CORRECTED 2026-08-03 — my first statement of it was wrong).**

I wrote "risk is subtracted, but nothing pays for danger". That is false. The
payout term already exists and already scales with urgency:

```gdscript
score = payout - travel_cost - risk      # payout = (pickup + dropoff price) x amount
```

`StationEconomy.price()` derives from urgency (illustrative curve 100 x urgency),
which is the mechanism `station_economy.md`'s self-healing cascade depends on:
*"a starved refinery's ore urgency climbs, raising the ore price, pulling haulers
onto the ore lane."* An urgent route DOES pay more, today.

**The actual reason `risked_anyway` is always 0 is SUBSTITUTABILITY.** The winner
is an argmax over ~13 stations x commodities — hundreds of candidate pairs. A
risky lane never has to beat its own payout, only the MARGIN TO THE NEXT-BEST
SUBSTITUTE, and with that many comparable routes that margin is tiny. Measured
risk (p95 69-78) against a payout ceiling near 200/lot is a ~35% penalty, which
reliably loses to *something* safe. Nothing is mispriced; there is simply always
another lane.

**The fix is the MAIL SYSTEM, and this is the loop finally closing.** Prices are
currently GLOBALLY READABLE — every hauler sees every posting's urgency and
plans against a perfect market. Put postings behind the same fog as incidents,
known only through the mailbag, and a hauler knows about a HANDFUL of postings.
Substitutes become scarce, and the urgent risky lane it actually heard about can
win on its merits.

**The fog is what creates the scarcity that makes danger worth accepting.** Same
clamp, same `Mailbag.read_*` shape, applied to postings instead of incidents.
This is D25's "prices are globally readable so the loop doesn't bite yet" and
D26 (mail urgency) turning out to be the same milestone, and it is the
prerequisite for criterion (3)'s second half.

Note what this predicts and therefore what would falsify it: under posting fog,
`risked_anyway` should go ABOVE zero *without any change to the risk term*. If it
does not, substitutability was not the binding constraint after all.

### D37 — what the hulk decision is actually keyed on (settled 2026-08-03: keep as-is for now)

`InterdictLeaf` appends `HULK_PRIZE` when `Standing.force_authorized_by(w)`:

| matched warrant | result |
|---|---|
| has one | `authorizes_force(offence)` — ARMED_ROBBERY yes, ARMED_THREAT / NO_ID no |
| **empty** | **true — uncapped** |

So the WARRANT decides when there is one; when there is not, the FLAG decides
(a hull reaches HOSTILE with no warrant via `known_enemy_flags` — a declared
pirate, engageable on sight).

**The asymmetry this produces, accepted deliberately:** no warrant -> hulked,
caution-grade warrant -> released. Lesser paperwork protects you MORE than none.
That is well-argued for weapons (`acquire_target_leaf`: the two no-warrant paths
are a self-declared enemy and a same-tick warrant stamp at most one tick behind)
and weaker for SEIZURE, which is deliberate and permanent rather than a reflex
in a firefight. Reviewed and kept for now — tightening it to "hulk only on an
actual force-authorizing warrant, never on the bare flag" is a one-line change
at the `InterdictLeaf` call site, leaving `force_authorized_by` untouched for
weapons.

**Why this is the interesting split rather than an implementation detail:**

* **Overt pirate** (colours up) — caught on the FLAG, no warrant required,
  hulked on sight.
* **Covert pirate** (cover identity, running dark) — never reads HOSTILE by
  flag, so it can only be hulked if a **notarized ARMED_ROBBERY warrant** has
  reached that patrol. That is the whole D29 chain: victim records the incident
  -> courier carries it -> own-flag station notarizes -> the warrant relays to
  the patrol.

Flying colours costs you your hull on sight; running covert makes you catchable
ONLY through the information economy. **Criterion (4) sits downstream of the
mail network for exactly the pirates the mail network exists to track** — which
is the loop this whole milestone set was aiming at.

### The bug this nearly hid, worth keeping as a method note

The first hulk gate was written as `Standing.authorizes_force(w.get("offense",
""))`, which returns FALSE for an empty warrant — inverting the no-warrant
branch and sparing precisely the colour-flying pirate nobody doubts. Patrols
released hulls that `AcquireTargetLeaf`, a few nodes away, would have shot.

It was caught because `losses` (PirateGuild's ledger) and `complied`
(EngagementProbe) are produced by DIFFERENT subsystems: 4 stops with 0 losses is
a contradiction, where either number alone reads as success. A `JOB_LOG=1` run
then confirmed `HULKED` fired 0 times with the old gate.

Note also that the missing `HULKED` log line was NOT evidence by itself — it
sits behind a debug toggle the funnel leaves off. **Absence of a gated log is
not absence of the event.** The cross-subsystem disagreement was the real
signal, same shape as `outpaced 0` being the tell in D28.

### First LONG run with all three systems (2026-08-03) — 240 game-min x 4

The funnel had never reported on the ECONOMY at all: the goal is "all three
playing together" and this instrument measured two. A long run could have shown
piracy and patrols working while the economy starved behind them and read as
success. Added `_report_economy()` — deliberately SMALLER than
economy_traffic's verdict and labelled so in its own output, since that runner's
SERVED/UNDERSUPPLIED/OVER_EXPORTED attribution needs per-minute flow accounting
this one does not keep, and porting it would repeat today's duplication bug. It
reports the one verdict computable from end state, the one economy_traffic
checks FIRST as the case where "net flow reads HEALTHY while the station is
dead": **STARVED** — wants it, cannot make it, bin on the floor.

| run | robberies | stops | notarized | guild losses | starved |
|---|---|---|---|---|---|
| authored s11111 | 1 | 0 | 5 (5/13 stations) | 0 | **0 / 24** |
| authored s22222 | 3 | 1 | 13 (8/13) | 1 | **0 / 24** |
| pressed s11111 | 0 | 1 | 0 | 1 | **0 / 24** |
| pressed s22222 | 2 | 0 | 8 (8/13) | 0 | **0 / 24** |

(`authored` = base_cap 1 / max 3, campaign pacing. `pressed` = 3 / 6. Labelled
distinctly per the sim-harness rule against mixing campaign-real with
harness-compressed config.)

**ESTABLISHED — the economy survives four game-hours alongside piracy and
patrols.** No imported bin hit the floor in any run. First time all three have
been measured in one world. The caveat is built into the report: 0 starved is
NOT a SERVED verdict, only "nothing has died".

**ESTABLISHED — the information chain holds at long horizon.** 13 warrants
across 8 of 13 stations off 3 robberies. Notarization, courier delivery and
warrant relay all survive hours, not just the 60-minute window everything until
now was tested in.

**CRITERION (1) IS NOT MET, and this is the honest headline.** Piracy runs
0-3 robberies per FOUR game-hours (~0.25-0.75/hr). One run had ZERO, which makes
every downstream stage unmeasurable in it. "Takes and incidents surface reliably
enough to trust in a long run" is false at authored pressure. And the dominant
pirate outcome is not a take at all — `returned_empty` runs 5-15 per run.
Pirates mostly go out and find nothing, which is the same ENCOUNTER problem the
passive-array work moved once and never solved.

**NOT READ, deliberately**: `pressed` produced FEWER robberies than `authored`
in both seeds (0 vs 1, 2 vs 3). That is the shape hulking-driven cap cuts would
make, and n=2 per config cannot distinguish it from dice. Needs seed-matched
pairs at more seeds. Reporting dice as signal has already happened once in this
work and is not repeating here.

### D38 — LANE_RUN finds prey BETTER; I measured the wrong stage (2026-08-03)

Asked directly whether the two postures differ at FINDING prey. They do, and the
evidence was in the A/B logs the whole time — `step_select_victim`'s two abort
reasons discriminate exactly this, and D27 never counted them:

| seed | "hunt time budget spent" = NO PREY FOUND | "N attempts, nothing taken" = FOUND, NOT LANDED |
|---|---|---|
| | OFF → ON | OFF → ON |
| 11111 | 34 → **21** | 1 → 4 |
| 22222 | 32 → **30** | 1 → 2 |
| 33333 | 37 → **30** | 1 → 3 |
| 44444 | 30 → **28** | 0 → 0 |
| 55555 | 30 → 33 | 0 → 0 |
| **total** | **163 → 142** (−13%, 4 of 5 down) | **3 → 9** (3 up, 0 down) |

**LANE_RUN does the thing it was built to do.** It converts "found nobody" into
"found someone and could not land it" — the encounter stage improves and the
EXECUTION stage becomes the new bottleneck. Invisible in robberies (10 vs 9)
because the funnel's end count sums both failures.

**D27's stated rationale was wrong and is corrected.** "No encounter benefit" was
a claim about a stage I never measured; I read an end outcome and described it as
a property of the middle. The DECISION (off by default) still stands on the
cargo-awareness signal, which was 5-of-5 and remains unexplained — but the reason
given for it was not the reason.

**Why this matters more than the posture**: criterion (1)'s blocker has been
"pirates find no prey", and this is the first evidence that encounter is
*improvable by behaviour* rather than fixed by geometry. It also says the two
failure modes trade off — pushing on encounter moves work into execution, so a
future measurement must watch both or it will read an improvement as a wash
exactly as this one did.

**Method note, the third time today**: the discriminator existed, was documented
in `step_select_victim`'s own header, and CLAUDE.md explicitly warns that
"takes 0" alone cannot tell the two apart. I ran the A/B without turning it on.
An instrument you own and do not read is the same as one you do not have.

### D39 — LANE_RUN back ON. I optimised the wrong objective (2026-08-03)

**What the posture is FOR:** raising encounter volume so the simulation has
enough events downstream to measure anything. It was never for maximising takes.

D27 benched it on a robbery count. Two independent errors, and the second is the
worse one:

1. **Wrong stage.** "No encounter benefit" was a claim about something never
   measured — the robbery count sums BOTH failure modes, so an encounter gain
   landing as an execution failure reads as a wash. D38's abort counts say the
   opposite: empty hunts 163 -> 142 (4 of 5 seeds), contested hunts 3 -> 9.
2. **Wrong objective.** Even granting the take count, takes were not the goal.
   Criterion (1) is *"takes and incidents surface reliably enough to trust in a
   long run"* — that is a FIDELITY criterion, and encounter volume is precisely
   what feeds it. Everything downstream (notarization, patrol response, cargo's
   risk map) has been measuring n≈1 because the funnel is starved of events at
   the top.

So the default is `true` again, and the sim's `LANE_RUN` env default moves back
to 1 to match the shipped default.

**The known cost, carried honestly and still unexplained:** cargo diversions ran
3161 -> 1457, five seeds down and none up, at the same incident count. The
mechanism is NOT established and is deliberately not guessed at — a plausible
story in a comment is how a wrong cause becomes canon. It is a real tradeoff to
re-examine once execution stops losing what encounter now wins.

**The generalisable mistake:** I measured the end of a funnel and reported it as
a property of the middle, then let that stand as a decision about a mechanism
whose stated purpose was something else entirely. When a change targets a
specific STAGE, the acceptance measurement has to be at that stage — and the
objective has to be re-read, not assumed.

### Criterion (4) status, corrected: a MECHANISM, not a RATE (2026-08-03)

I wrote "met mechanically — 0→4 stops". That phrasing carried more than the
evidence. Five ways it is not met:

**1. "Consistently" is not met.** Interdictions per seed: 2, 10, 1, 0, 3 — one
seed had none. At authored pressure over four game-hours, stops were 0, 1, 1, 0.
That is a coin flip, not a rate.

**2. Half the "stops" were probably not pirates — the worst of these.**
Interdiction fires at CAUTION tier too, which is usually an innocent hull that
did not answer a challenge. Only force-authorized stops hulk, and the arithmetic
was `4 stops -> 2 guild losses -> ~2 hulks`. So at most HALF those stops were
pirates; the rest were civilians inspected and released. The criterion says
"stopping some PIRATES" and the counter conflates the two. **EngagementProbe
should record the tier alongside the outcome** — without it, "stop rate" cannot
distinguish enforcement from harassment.

**3. The chain has never fired end-to-end in ONE run.** Notarization, stops and
hulks were each measured, in DIFFERENT runs at DIFFERENT pressure. The specific
sequence — robbery → courier → notarized warrant → *that warrant* driving an
interdiction → stop → hulk — has never been observed in a single run. Same shape
as the preconditions lesson, one level up: every link tested, the chain assumed.

**4. Missing features.** No arrest, cargo recovery or crew (D33). The warrant
never discharges (`expires_after: -1.0`), so it persists against a dead hull
forever. No stalk phase (D16). And "refine desired outcomes" — the second half
of the criterion — has not started.

**5. Suppression is asserted, not measured.** `loss_streak` -> cap cut is real
wiring, but only 2 losses have ever been observed; no cap cut has been seen
firing, and no evidence exists that piracy declines afterwards.

**Correct claim: a patrol CAN stop and seize a pirate. Not: patrols stop pirates
consistently.**

### The selection-criteria chart (2026-08-04) — read this before proposing a fix

Every actor's "where do I go next" decision, taken from the code rather than
from memory. The BLANK CELLS are the plan; nothing here is a guess.

| | **Cargo** (`RoutePlanner`) | **Pirate** (`PirateGuild`) | **Patrol** (`PatrolResponseLeaf`) |
|---|---|---|---|
| **Candidates** | every station pair x commodity (~13 stations) | 24 sampled random hub chords | heard hotspots <=220k + stations <=260k |
| **Score** | `payout - travel_cost - risk` | `_chord_carriers` — how many station-pair LINES pass within 30,000u | hotspot: severity x proximity x recency; station: flat 1.0 |
| **Selection** | **ARGMAX** + hysteresis (15/lot) | **ARGMAX** over the 24 samples | **WEIGHTED DRAW** (D24) |
| **Prices** | **global, unfogged** | none *(Slice A: flag-gated prediction, also unfogged)* | none |
| **Incidents** | fogged (mailbag-clamped) | **none** | fogged (mailbag-clamped) |
| **Own observation** | none | none | none |
| **Memory of outcomes** | none | **none** | none |
| **Optimises** | profit | *geometric convergence* | reported trouble |

Once on station, the per-target rule:

| | criterion |
|---|---|
| **Pirate -> victim** | NEUTRAL/CAUTION, **alone** (nothing else within `witness_range`), then **smallest cross-section** |
| **Patrol -> subject** | HOSTILE standing **or** enforceable warrant; tier decides whether force is authorized |

**What the chart makes obvious, and none of it was obvious before drawing it:**

1. **The pirate is the only actor with no learned input at all.** Cargo and
   patrols both read a fogged channel that updates; the pirate navigates by
   STATIC geometry. `_chord_carriers` returns the same answer on minute 1 and
   minute 240 — a lane that paid yesterday and a lane nobody has ever flown
   score identically. It cannot learn, so it cannot be wrong in a way it can
   detect.
2. **Cargo has a split epistemology.** Prices global, incidents fogged: the two
   inputs to ONE decision come from different worlds, and the fogged one is
   systematically disadvantaged. That is D36, and it is why risk is a veto
   rather than a price.
3. **Only patrols were ever fixed.** D24 replaced their argmax with a weighted
   draw after measuring lock-on. Cargo and pirates still argmax — which is
   exactly the cargo herding (D42) and the pirate stacking risk.
4. **Nobody observes anything.** No actor uses its own sensors to inform
   SELECTION. The pirate has a 45,000u passive array and uses it only for VICTIM
   pick, never for LANE pick — so it cannot notice it is sitting on an empty
   road.
5. **Nobody remembers anything.** No actor carries outcome memory between
   decisions, so no failure teaches anyone.

**The plan is the blank cells, in order:**

| gap | fix | milestone |
|---|---|---|
| pirate score has no traffic term | predict the lane with `scored_routes` | M60d slice A — BUILT, flag-gated |
| prices are unfogged for everyone | postings behind the mailbag | **M64** — keystone for criteria (1) AND (3) |
| cargo + pirate select by argmax | weighted draw (the D24 pattern, twice more) | M60d (pirate, built) / M64 may fix cargo for free |
| nobody remembers outcomes | per-lane weights: takes up, empties down | M60d |
| pirate never observes traffic | dock leg fills the mailbag | M60d + M65 |

### D44 — economic targeting WORKS at the stage it targets (2026-08-04)

M60d slice A built and A/B'd, `ECON_TARGET` off vs on, seed-matched:

| seed | lane overlap OFF -> ON | "found NOBODY" aborts OFF -> ON | takes |
|---|---|---|---|
| 11111 | 0.0000 -> **0.33** | 2 -> **0** | 1 -> 1 |
| 22222 | 0.0216 -> **0.51** | 3 -> **0** | 1 -> 0 |
| 33333 | 0.0554 -> **0.44** | 4 -> **0** | 0 -> 0 |

**The encounter failure is GONE.** No hunt exhausted its time budget having seen
nobody, in either logged seed — and seed 33333 logged `hunt budget spent (4
attempts, nothing taken)`, i.e. it found prey four times and could not land it.
That is an EXECUTION failure, which is the failure mode you only get to have
once encounter works.

**Takes did not move.** Same shape as LANE_RUN: a real fix at the targeted stage,
bottleneck moves rather than clears. The difference is that this time the stage
was measured DIRECTLY rather than inferred from the funnel's end — which is the
whole lesson of D38.

**UNRECONCILED, and not being explained away**: `returned_empty` reads 7 in both
seeds against ONE logged `SELECT_VICTIM` abort. Most hunts end by some path that
is not a logged victim-selection abort. This matters because `returned_empty` is
the signal M60d's per-lane learning would train on — if it counts something other
than "I hunted and found nothing", the learning term trains on noise. Chase
before building the learner.

### D45 — the metric flaw the result exposed

`efficiency` came back 1.03 / 1.44 / 1.31 — ABOVE 1.0, which is the tell that the
denominator was never a ceiling. I had defined it as `sum cargo_share^2`, the
overlap if pirates matched cargo exactly, and called it *"the ceiling any
targeting rule could reach"*. **Matching your prey's distribution is not optimal
play; concentrating harder than it is.** The true optimum is `max(cargo_share)`
— every pirate-second on the single busiest lane.

Now reported as three numbers: `match` (mimicry baseline), `ceiling` (true
optimum), `headroom` (the honest 0..1 score). `efficiency` keeps its name so the
figures already in this ledger stay comparable.

### D42 CORRECTED — the herd MIGRATES, and that changes the problem

120 game-minute trace, bucketed per 10 minutes:

```
   0 min  Coldreach <-> Ironhold        62.6%      50 min  Deepcut <-> Refinery Prime   63.6%
  20 min  Coldreach <-> Ironhold        76.9%      60 min  Deepcut <-> Refinery Prime   79.2%
  30 min  Coldreach <-> Slag Bay        66.7%      80 min  Ironhold <-> Refinery Prime  53.2%
  40 min  Refinery Prime <-> Slag Bay   36.6%     100 min  Coldreach <-> Drift Market   36.7%
```

The herd is real at any instant (40-80% on one lane, only 2-9 lanes active) but
it **moves every 10-30 game-minutes**, and cargo touches 15-16 lanes across a
run. So `station_economy.md`'s self-correction DOES work — deliveries land,
urgency falls, the lane stops winning. The 40-63% aggregate was the time-average
of a wandering peak, which was the alternative I could not distinguish before.

**THE CONSEQUENCE, which is bigger than the correction.** The pirate's target is
**NON-STATIONARY**. That is why static geometry (`_chord_carriers`, identical on
minute 1 and minute 240) fails badly and why live prices worked immediately.

**It is a hard constraint on M60d's per-lane learning**: the learning rate must
be fast relative to ~10-30 minute peak migration, or a learned weight will
confidently chase a peak that has already left. **A slow decay would be worse
than no memory at all.** This is the same class of error as D22 (a half-life
shorter than delivery latency) and the avoidance-window bug — a time constant
set without reference to the timescale of the thing it tracks. Third instance;
it should be a standing check.

### D41 — measurable now, and the design is inadequate

With the window corrected to 22 game-minutes:

| seed | cargo before -> during | ratio |
|---|---|---|
| 11111 | 174 -> 47 | **0.27** |
| 22222 | 232 -> 285 | **1.23** |

One seed drains hard, the other rises. And with a migrating peak I **cannot
separate "cargo fled" from "the peak moved on anyway"** — both produce a falling
ratio. So the corrected window made the measurement possible and revealed the
measurement DESIGN is confounded.

Separating them needs lanes WITH incidents against lanes WITHOUT, both during a
pirate's presence. **No avoidance claim is being made in either direction.**

### D46 — the third exit path: a WITNESS ends the whole hunt (2026-08-04)

`returned_empty` read 7 against ONE `SELECT_VICTIM` abort. Traced one member's
full lifecycle rather than reasoning about it:

```
SELECT_VICTIM done (victim='Mule')         -> INTERCEPT done -> DEMAND_STOP ABORT (patience) -> 'hunt'
SELECT_VICTIM done (victim='Cluster_703')  -> INTERCEPT ABORT (victim_lost)                  -> 'hunt'
SELECT_VICTIM done (victim='Cluster_9500') -> INTERCEPT ABORT (victim_lost)                  -> 'hunt'
SELECT_VICTIM done (victim='Hauler 13')    -> INTERCEPT ABORT (third_party_in_range;
                                               witness TRK-138 at 5094)                      -> 'exfil'
```

**`third_party_in_range` on INTERCEPT aborts to `'exfil'`, not `'hunt'`.** A
witness does not merely spoil that victim — it ENDS THE HUNT and sends the
pirate home. That is the whole missing accounting.

**And it is self-defeating with D44.** Economic targeting puts pirates on the
BUSIEST lane; the busiest lane has the MOST witnesses; so better targeting
produces MORE abandoned hunts. The `alone` requirement bites at INTERCEPT rather
than at SELECT_VICTIM, which is why the earlier hypothesis pointed at the wrong
step.

**ENCOUNTER IS DEFINITIVELY SOLVED**: four victims selected in a single hunt.
Every remaining failure is downstream of finding someone.

| failure in that one trace | n |
|---|---|
| patience expired | 1 |
| `victim_lost` mid-intercept | 2 |
| witness -> abandon entire hunt | 1 |

**D46 (OPEN, and now the biggest single lever on takes): should a witness abort
the HUNT or just that VICTIM?** Aborting to `'hunt'` — pick a different target —
is the obvious alternative to `'exfil'`. As it stands a pirate on a busy lane
gives up entirely the first time anyone else is nearby, which is precisely the
lane it should want to work. Gameplay call, deliberately not made here.

### D47 — `victim_lost` twice in one hunt

The pirate SELECTS a victim and then loses the track while closing, twice in
four attempts. Against a 700u/s hauler with a 45,000u passive array that wants
explaining before it is tuned — candidates are the passive array's refresh
interval, `CONTACT_TIMEOUT`, or the dead-reckon prune, none of them verified.
Not a tactical problem until shown to be one.

### D48 — `RELIGHT done (as '' / DRIFT_CIVILIAN)`

The exfil tail relights the hull under an EMPTY NAME. `{"verb": "RELIGHT",
"from_kit": true}` draws from a kit that nothing maintains, so laundering
produces a nameless ship. This is M65's decorative-identity problem visible in a
live run rather than in code review — and it means the pirate exits under no
identity at all, which no port would accept and no observer could correlate.

### D46 measured — graded witness response, and a lesson I had to relearn

Built behind `intercept_witness_retries` (sim knob `WITNESS_RETRY`): a witness
during INTERCEPT sends the pirate back to `hunt` instead of `exfil`. DEMAND_STOP
and TAKE_ALONGSIDE keep fleeing, because that is what the rule is FOR — you have
hailed, or you are mid-robbery.

**First attempt at judging it was worthless.** I compared TAKES: 1 vs 1 across
three seeds. At 0-1 robberies per run three seeds cannot distinguish anything —
which is D23, *in this ledger, written by me*. I built the change for a
stage-level reason and then judged it on the funnel's end, the exact error that
produced D27's wrong verdict and that D38 exists to prevent. Third time this
session; the rule needs to be mechanical, not remembered: **measure the stage you
changed.**

Stage-level, n=2:

| seed | | victims selected | intercepts done | demands | alongside |
|---|---|---|---|---|---|
| 22222 | off -> on | 12 -> **19** | 7 -> **12** | 7 -> **12** | 4 -> 5 |
| 33333 | off -> on | 18 -> **20** | 8 -> 8 | 8 -> 8 | 4 -> 3 |

Hunt cycles rose in both (+58%, +11%) — the mechanism does what it was built to
do. One seed carried it downstream, one did not.

Note `witness_aborts` RISING under retry (6 -> 10 in 33333) is not a failure:
retrying means more chances to meet a witness. That metric is not clean for this
comparison and I should have seen that before picking it.

**RESOLVED on 8 seed pairs -- DEFAULT NOW ON.**

| metric | OFF -> ON | seeds up / flat / down |
|---|---|---|
| hunt cycles | 121 -> **154** (+27%) | **6 / 2 / 0** |
| demands issued | 88 -> **106** (+20%) | 4 / 3 / 1 |
| takes | 7 -> 8 | 3 / 4 / 1 |

Six-up-none-down on cycles settles it. **Takes staying flat is the FINDING**, not
a disappointment: it locates the remaining bottleneck downstream of the demand.
Defaulted on for D39's reason -- criterion (1) wants encounter volume the sim can
be trusted on, and this is +27% at no measured cost.

Superseded reasoning, kept for the record: Directionally positive, n=2, one seed
flat — inconclusive, not null. Worth stating why this differs from D39, where
leaving LANE_RUN off was WRONG: there the evidence was bad because I measured the
wrong stage. Here the stage is right and the signal is genuinely weak. Shipping
on a 2-seed split would be the same error pointing the other way.

### Where criterion (1) actually stands now

**Encounter is SOLVED** (D44, with omniscient prices behind a flag). One traced
hunt selected FOUR victims. The remaining chain is three separate downstream
failures, each needing its own stage-level measurement:

| failure | evidence | status |
|---|---|---|
| witness ends the hunt | `third_party_in_range -> exfil` on all three steps | D46, flag built, 8-pair run in progress |
| `victim_lost` mid-intercept | 2 of 4 attempts in one trace | D47 — cause unknown, NOT tuning it until measured |
| demand refused / patience | 1 of 4 | shares the D28/D32 machinery |

A takes count cannot resolve any of these, which is why the funnel's end is the
wrong instrument for all three.

### D47 measured — right diagnosis, correct fix, NULL result (2026-08-04)

`victim_lost` fired on `FIRE_STALENESS_MAX` (3.0s) -- a FIRING-SOLUTION bound
deciding whether a chase continues, while the contact itself survives to
`CONTACT_TIMEOUT` (20s).

Two hypotheses killed by reading rather than measuring, which is the cheap half:
GO_DARK disables only the TRANSPONDER (sensors keep running), and the pinnace
sweeps its full 360 degrees every 1.0s -- so neither self-blinding nor cadence.
Then instrumented the abort itself:

```
age 3.0s > 3.0; true range 14175      age 3.0s > 3.0; true range 32420
age 3.0s > 3.0; true range 18164      age 3.0s > 3.0; true range 34217
age 3.0s > 3.0; true range 21819      age 3.0s > 3.0; true range 41851
age 3.0s > 3.0; true range 23575      age 3.0s > 3.0; true range 43329
age 5.5s > 3.0; true range 61132   <- the ONE genuine escape
```

Every victim inside the 45,000u array, contact still HELD (stale, not dropped),
and age EXACTLY 3.0s in 10 of 11 -- clustering at the trip point is the
signature of a threshold that is too tight. A real escape spreads, as the 61km
case did.

Fix: `victim_lost_after`, defaulting to FIRE_STALENESS_MAX so every existing
caller is unchanged; the pirate's hunt passes `pursuit_staleness` 12.0, between
3s and CONTACT_TIMEOUT's 20s. A pirate should quit shortly before its own
tracker does, not four times sooner.

**RESULT: 21 aborts eliminated, every downstream number BIT-IDENTICAL.**

| seed | victim_lost | demands | alongside | takes |
|---|---|---|---|---|
| 11111 | 1 -> 0 | 13 -> 13 | 4 -> 4 | 0 -> 0 |
| 22222 | 9 -> 0 | 12 -> 12 | 5 -> 5 | 1 -> 1 |
| 33333 | 5 -> 0 | 8 -> 8 | 3 -> 3 | 0 -> 0 |
| 66666 | 6 -> 0 | 15 -> 15 | 6 -> 6 | 2 -> 2 |

The abort was BENIGN: it routed to `hunt`, the pirate re-selected -- often the
same victim, now fresh -- and carried on. It cost cycles, not outcomes.

**KEPT, unlike D30's reverted no-op, and the distinction is the point.** D30's
comment asserted a mechanism that was FALSE (`cruise` capping absolute speed).
D47's claim is true and measured: the threshold really was the wrong question and
the aborts really are gone. **A correct rule with a null result is worth keeping;
a wrong story with a null result is not.** The comment records the null so nobody
re-fixes it expecting a win.

### The pattern across three consecutive criterion-(1) fixes

D31, D46 and D47 are all **a rule borrowed from a neighbouring question**:

| | tested | should have tested |
|---|---|---|
| D31 `outpaced` | "is it far away" | "is it pulling away" |
| D46 witness | "should I abandon the trip" | "should I abandon this victim" |
| D47 `victim_lost` | "can I shoot it" | "have I lost it" |

Worth stating as a search heuristic rather than three anecdotes: **when a
behaviour aborts too early, check whether its predicate was written for a
different decision.** Two of the three were real improvements; the third was
null, which is why the heuristic finds candidates, not answers.

### D50 — the robbery was never broken; the pirate stops TICKING it (2026-08-04)

**The fast rig changed the answer.** `alongside_trace.gd` -- two ships, no
economy, 1.5 SECONDS per run -- drives the real `TAKE_ALONGSIDE` against a real
complying victim:

```
gap  3000u -> closest 104, hold completes
gap  8000u -> closest  82, hold completes
gap 20000u -> closest  93, hold completes
```

**The step is sound at every distance the campaign produces.** It closes 20km and
completes the 12s hold with compliance sustained throughout. So D49's
entry-margin fix was addressing a non-problem, which is exactly why it measured
null, and six turns of heartbeat hypotheses were all looking at a working
mechanism.

The rig also caught TWO bugs in its own harness on first run (a missing wait for
ACKNOWLEDGE to reach the pirate's contact; `on_abort: ""` silently reading as
job-complete, CLAUDE.md's own documented trap). Each would have cost a full
campaign run to notice.

**Then instrument what the campaign does that two ships do not.** Two findings:

**1. The pirate barely moves.** Isolated: ~280u/s closing. Campaign: `closest
5499 -> range 5472` -- **27 units in ~16 seconds** -- and one case where it moved
BACKWARDS (20100 -> 18142 is closing, but 16401 -> 16435 is not).

**2. `max tick gap 387 frames` = 6.45s.** The step was not being TICKED for 6.45
seconds -- longer than `HAIL_HEARTBEAT_TIMEOUT` (6.0s). No refresh can go out
while the step is not running, so the hold lapses by exactly the mechanism it is
designed to, and the step then reports "victim bolted".

`build_pirate` is a Selector: `ShouldDisengage -> Flee`, then `OutlawResponse`,
then `JobRunner`. Anything above JobRunner claiming the tick stops the robbery
cold. **The victim did nothing wrong and the message names it as the cause.**

Note n=1 for the tick gap; the movement anomaly is n=4.

**What this changes about the fix.** If the preemption is a PATROL interdicting
the pirate mid-robbery, abandoning is CORRECT behaviour and only the message is
wrong. If it is `ShouldDisengage` firing on ordinary traffic -- and economic
targeting puts pirates on the busiest lane, so there is more of it -- then a
pirate can never rob anyone on a lane worth robbing, and that is the real defect.
**Those need opposite fixes and the instrument does not yet distinguish them.**

**3. A fusion divergence, independent of both.** Seed 22222: the victim's
`compelled_stop` reads **held** while the pirate's CONTACT reports
`complied_stop false`. The contact carries its own `complied_stop_grace`
lifetime, so a pirate can abandon a victim that is still dutifully stopped. Found
only because the abort prints both sides; a takes count could never surface it.

### The method lesson, which is the expensive one

A two-body question was chased through 45-game-minute campaign runs with 14
haulers, 8 pirates and a live economy, three seeds at a time, for SIX turns.
`pursuit_trace.gd` had already established the right pattern that same morning
and answered the patrol-chase question on its first run. **Build the smallest rig
that reproduces the mechanism before instrumenting the big one** -- the campaign
is where RATES are measured, not where mechanisms are debugged.

### D50 status — six candidates eliminated, the gap is NOT yet explained

Stated plainly because the temptation is to keep guessing: **I do not know why
`JobRunner` stops ticking the take for ~6.25 seconds.**

What IS established, and none of it is speculation:

| finding | evidence |
|---|---|
| The take step is SOUND | `alongside_trace.gd`: closes 3k/8k/20k, completes the 12s hold every time |
| The hold channel WORKS | 22-27 refreshes sent AND received on the victim's own counter |
| Victims comply | 17 of 49 demands; **0 ever outpace** |
| The step stops being TICKED | `max tick gap` 387 / 374 / 375 / 376 frames -- consistently ~6.25s |
| The pirate barely moves during the gap | 27 units in ~16s, vs ~280u/s in isolation |

Six candidates, each killed by a measurement rather than an argument:

| candidate | killed by |
|---|---|
| aim point == threshold (D49) | fixed it; `held` still -1.0, takes 3 vs 3 |
| comms range / seq / timer / scratch | all read correct; refreshes land and reset the hold |
| tree structure, `ShouldDisengage` on traffic | fast rig: FULL `build_pirate` + bystander at 2,500u still completes |
| patrol interdicting the pirate | `self=clear` in every abort |
| `OutlawResponseLeaf` starving JobRunner (my code) | `outlaw_flee_ticks` = 0 |
| sim bubble demoting the hull | harness runs `configure_full_sim()` |
| beehave tick throttle | `tick_rate` defaults to 1; no AI budget exists |

**That lead is now CLOSED.** `JobRunnerLeaf` guards the reset on the entered
INDEX -- `if job.get("_entered_step", -1) != current: step["scratch"] = {}` --
so a hunt-loop excursion resets `last_tick_frame` and would report a gap of -1,
not 375. **The ~6.25s gap is real and happens WITHIN a single entry of the
step.** Seven candidates eliminated; the cause is still unknown.

Next instrument, and it should be a FAST one rather than another campaign run:
stamp the frame in `JobRunnerLeaf` itself (not the step) so the gap can be
attributed to "the runner did not run" vs "the runner ran but did not reach this
step". Those are different faults and the current instrument cannot tell them
apart -- the same conflation that made "victim bolted" mean six different
things.

**Cost of this investigation, recorded because it is the finding that
generalises**: six hypotheses, six turns, on a mechanism that was never broken.
`alongside_trace.gd` (1.5s per run) exonerated the take on its FIRST execution
and should have been written before the first hypothesis, not after the sixth --
`pursuit_trace.gd` had already proved the pattern that same morning.

**What this means for criterion (1)**: every stage is solved or explained EXCEPT
this, and the low take rate is now attributable to a single unidentified
scheduling gap rather than to pirate behaviour. That is a much better position
than "pirates never find anyone", and it is not a finished one.

### D50 SOLVED — the pirate disengages mid-robbery (2026-08-04)

**`self=DISENGAGING (386 FleeLeaf ticks stolen)`**, against a measured 387-frame
gap. Exact match.

`build_pirate` is `Selector(Disengage[ShouldDisengage, Flee], OutlawResponse,
JobRunner, Idle)`. When a pirate perceives a threat mid-robbery, `Flee` claims
every tick for ~6.4 seconds. `JobRunner` sits BELOW it, so the hunt job never
runs, never refreshes its own demand, and the VICTIM's compliance lapses on its
6s heartbeat. The step then reports **"victim bolted"** about a ship that never
moved.

It also explains the two anomalies that made no sense on their own: the pirate
"barely moving toward its victim" (it is flying AWAY from something else), and
the fast rig's inability to reproduce any of it (nothing there threatens the
pirate).

**Nine candidates, each eliminated by DIRECT COUNT rather than by argument:**
aim point (D49, fixed and null) · comms range · seq match · timer reset · scratch
persistence · tree structure/bystander · patrol interdiction · OutlawResponse
fleeing (0 ticks) · OutlawResponse held (0 ticks) · sim bubble · beehave throttle.

**TWO OF MY OWN INSTRUMENTS WERE WRONG DURING THIS, and both produced confident
false eliminations:**

1. `runner lag` stamped the frame at the top of `JobRunnerLeaf.tick` and read it
   back INSIDE THE SAME TICK -- computing `now - now`, structurally incapable of
   returning anything but 0. I used that 0 to rule out the entire tree-preemption
   family, which is where the answer actually was.
2. `self=clear` read the pirate's `compelled_stop`/`pending_demand` AT ABORT
   TIME, after the state had already released -- so it reported "clear" for a
   hull that had been fleeing for six seconds.

That is the seventh and eighth instrumentation defect this session, all the same
shape: **a number that cannot express the failure it exists to detect.** Both
happened AFTER writing that exact rule into CLAUDE.md the same morning. Knowing
the rule did not prevent repeating it, which means the guard has to be
structural: **validate an instrument against a case where it MUST report failure
before trusting its output.**

### D51 (OPEN) — is disengaging mid-robbery correct?

The behaviour may be right and only the message wrong. A pirate under threat
SHOULD break off. But three things need deciding:

1. **The log lies.** "victim bolted" names the victim as the cause of a failure
   the pirate chose. That single misleading string is what sent this
   investigation into six wrong hypotheses. Cheapest and most valuable fix
   regardless of the rest.
2. **Should a robbery in progress outrank fleeing?** A pirate 200u from a
   complying victim with 12 seconds to go is throwing away the entire hunt for a
   threat that may be a passing hauler. `ShouldDisengage`'s threshold was never
   tuned against "I am mid-take".
3. **The interaction is invisible.** Nothing in the funnel reports "robbery
   abandoned due to disengage" -- it books as `returned_empty`, which reads as
   "found nobody". Criterion (1) has been measuring pirate FAILURE where the real
   cause is pirate CAUTION.

### D52 — pirates cook themselves on the approach and flee to cool (2026-08-04)

Counted the disengage trigger rather than inferring it:

```
DISENGAGING (373 ticks; heat 373 / damage 0)
DISENGAGING (374 ticks; heat 747 / damage 0)
DISENGAGING (386 ticks; heat 386 / damage 0)
```

**Every disengage is HEAT. Zero are damage.** And `ShouldDisengage` never looks at
contacts at all -- it is hull health and heat only -- so the earlier framing of
"the pirate flees from witnesses" was wrong. Witnesses abort STEPS
(`third_party_in_range`); heat aborts the whole BEHAVIOUR.

**The pirate has TWO heat responses and they fight each other:**

| response | threshold | effect |
|---|---|---|
| thermal throttle | eases from `THERMAL_EASE_START` | cruise cap 1.0 -> `THERMAL_CRUISE_FLOOR` 0.6, graded |
| `ShouldDisengage` | heat >= `DISENGAGE_HEAT_FRACTION` 0.9 | abandon everything and run, held ~6.4s by `HEAT_RECOVER_FRACTION` hysteresis |

The throttle is the proportional response and it already exists. The disengage is
a COMBAT rule -- break off when you are cooking -- living in the branch shared
with warships.

**Applied to a robbery it is backwards.** Holding station 200u from a stopped
victim is LOW throttle, which is how a hull cools. Fleeing is a sprint, which is
how it heats. So the response to overheating is the one action guaranteed not to
fix it, and it costs the take. The sequence is structural: sprint the intercept
-> heat climbs -> demand lands -> heat crosses 0.9 -> flee.

**RETRACTED, same day — this is NOT a borrowed predicate, it is a deliberate
fix with tests.** `452e94f` ("overheat triggers disengage, attribute self-cooked
reactor deaths") and `e7b61a5` ("thermal governor prevents multi-pirate
self-cooking") added it on purpose, pinned by `test_overheat_disengage.gd` (6
assertions) and `test_multi_pirate_thermal.gd`.

The problem it solves is real and worse than the one it causes: two pirates
converging on one victim never exclude EACH OTHER from `Steering.steer`'s
avoidance, so both hold near-max throttle indefinitely, heat pegs, and
`ship.gd`'s periodic check drains the reactor 10 HP/s through a path that
BYPASSES `take_damage()` -- a pirate dying mid-encounter with no visible cause
in any log.

And the hysteresis is not incidental either. From the commit: *"without
hysteresis, the plain threshold made the exact multi-pirate repro WORSE -- a
pirate would resume pacing the instant heat dipped under 0.9, restart from a
drifted-off position with a fresh, larger position error, and spike catchup
speed right back up -- repeated disengage/resume flicker generated MORE heat
spikes than no disengage at all."*

**So the ~6.4s hold-losing window is the deliberate cost of not dying.** My
proposed fix (suppress the heat branch during a hold) would have reintroduced
both the invisible deaths and the flicker. Checking `git log` before proposing a
change to load-bearing behaviour would have caught this in one command.

### The compliance funnel, now fully accounted

| | n |
|---|---|
| demands issued | 27 |
| victim COMPLIED | 14 |
| lost to heat-disengage | 4 |
| lost to witness aborts on DEMAND_STOP / TAKE_ALONGSIDE | ~7 |
| **takes** | **2** |

Note D46 only moved INTERCEPT's witness abort to `hunt`; DEMAND_STOP and
TAKE_ALONGSIDE still route to `exfil`, and they are the larger share here.

**D53 (REFRAMED, and the useful version):** the disengage was tuned against
pirate SURVIVAL and never measured against pirate SUCCESS. 0.9/0.6 were chosen
to stop deaths; nobody knew what they cost in takes. **Now we do: 4 of 14
compliances.** That number is the contribution here, not a fix.

The question is therefore NOT "remove the disengage" -- it is **"why is the
pirate that hot on arrival?"** The heat comes from the approach, and
`_thermal_derate` already derates `_pace_at_offset`'s catchup surge from 75%
heat. Candidates worth measuring before touching anything: does the INTERCEPT
sprint (a separate code path from the pacing surge) run hot enough to arrive
near 0.9, and would arriving cooler remove the problem without weakening the
safety net at all?

Do not touch `DISENGAGE_HEAT_FRACTION` or the hysteresis without re-running
`test_overheat_disengage` and `test_multi_pirate_thermal` -- they exist because
the obvious tunings were tried and were worse.

### D53 answered — the HOLD cooks the pirate, not the approach (2026-08-04)

I predicted the INTERCEPT sprint. Wrong. Heat at hold-entry vs peak:

| entry -> peak | outcome |
|---|---|
| 0.48 -> **0.90** | abort |
| 0.60 -> **0.90** | abort |
| 0.76 -> **0.90** | abort |
| **0.15** -> **0.90** | abort |
| 0.72 -> 0.81 | **take** |
| 0.01 -> 0.65 | **take** |

**A pirate entering at 0.15 still reaches 0.90.** The approach is not what
overheats it -- station-keeping is. Every failure peaks at EXACTLY the 0.90
disengage threshold (cut off the instant it trips); both successes finished
below it.

**So a take is a RACE**: can the hull hold station for `hold_time` (12s) before
its own corrections drive heat to 0.90? Entry heat sets the margin, but the
climb rate varies enormously (0.15->0.90 in one hold, 0.01->0.65 in another),
which points at how much correcting the hull does -- victim drift, standoff
geometry, re-approaches -- rather than at a fixed cost.

**Why station-keeping is expensive at all**: `_pace_at_offset` commands
`target_vel + dir * catchup` every tick, and `_engine_heat_contribution` scales
with `abs(throttle)`. Holding a 200u offset against any drift is continuous
throttle. The isolated rig completes a 12s hold comfortably, so this is about
holds that run LONG -- repeated re-approaches inside one take.

**Three candidate directions, none measured, and NOT to be tried by weakening
the disengage** (D52: that net is tested and load-bearing):
1. `hold_time` 12s -- is a shorter robbery acceptable?
2. cheaper station-keeping during a hold specifically -- the pirate does not
   need catchup authority once it is inside the ring.
3. leave it: a hot pirate breaking off a long robbery is defensible fiction, and
   the cost is now quantified rather than hidden.

**Method note**: this is the second time today a stated hypothesis was killed by
the measurement built to test it (the first: `alongside_trace` exonerating the
take step). Both times the prediction was plausible and specific, which is
exactly why it needed the measurement.

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
