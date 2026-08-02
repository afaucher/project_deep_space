# M53c — The station economy and demand-driven traffic

Follows M53b Pass 1 (per-station docking registry) and Pass 2 (traffic
director). Pass 3 (skeleton extraction) is **deferred to a third director** —
see [m53bc_traffic_guild.md](m53bc_traffic_guild.md); nothing here depends on it.

**The design is [../design_ideas/station_economy.md](../design_ideas/station_economy.md).**
This file is the build order only — it deliberately does not restate the model,
because an earlier draft of this plan carried its own (wrong) model and drifted
from the design doc within a day.

## What changed from this plan's first draft

Recorded because the reasons generalize:

- The first draft proposed a director-side `service_rate` scalar and "demand =
  dock count, decay-averaged". **Both were wrong.** Dock count measures service
  already rendered, so routing toward it is positive feedback; and a
  director-side scalar cannot be seen, served, or paid for by the player, and
  gives the mail fog nothing real to be stale about.
- The scoring function was a **global optimizer** over cluster welfare. Nobody in
  the fiction wants cluster welfare, and a well-run economy designs the player
  out of a job. Replaced by per-party scoring over *heard* postings.
- Demand therefore moved **onto stations** as stock, and the coupling between
  parties and the world became the **posting**.
- A later pass caught the same error one level down: an authored per-station
  **`rate`** was itself a fudge factor. Throughput is now **derived from converters**
  (in → out, stalling on either), so running out of ore actually stops refined
  production instead of a constant ticking on regardless.

## Phase 0 (a.k.a. M53b Pass 1b) — Move the docking registry onto the record

Repairs a **latent correctness bug** in the committed Pass 1 work (`f6b15af`)
before anything else is built on it. Do this first; it is small.

**The bug.** `docking_registry` and `registry_seq` live on `Ship` (`ship.gd`), not
on the `ClusterEntity` record. `ClusterManager._demote()` reads back **only**
kinematics (pos/rot/vel/ang_vel) and frees the node, so on demote the registry is
destroyed and on re-promote `registry_seq` restarts at **0**. Since the entire mail
merge is `my version > your version`, a holder carrying `Ironhold@v412` would then
hold a version *higher than the source's own* — poisoning that compare permanently.
Pass 1's own doc comment states the invariant this breaks: *"registry_seq is NOT
reset/reused... the sequence must stay monotonic."*

**Severity: latent, not currently biting.** `cluster_manager.gd` defaults to
`policy.configure_full_sim()` (with `configure_bubble(45000, 60000)` commented out
directly above), so nothing demotes in normal play today. But BUBBLE is the
documented intended default in `liveness_policy.gd`, and M53a's 2× cluster makes
FULL_SIM progressively more expensive — so this bites the day BUBBLE is switched
on, most likely during perf work, which is exactly when nobody is looking at mail.
`test_docking_registry` cannot see it because it never demotes.

**A second reason the record must be canonical:** under BUBBLE most stations are
dormant, and parties/directors must be able to read a station's registry *without
being there*. A copy that only exists on the live node is unreadable exactly when
the fog matters.

### Scope

1. `ClusterEntity` gains `docking_registry: Array` and `registry_seq: int`.
2. `Ship` gains a **weak** reference to its record (`WeakRef`, to avoid a
   Node↔RefCounted cycle), set in `ClusterManager._promote()`.
3. `Ship.record_docking_event()` writes to **the record when one is attached**,
   else to its own local array; a read accessor resolves the same way. **One
   canonical store at a time** — never both, or the record goes stale while live.
   The local fallback is what keeps bare `Ship`s (sandbox, existing tests) working.
4. Do **not** add an economy tick here — there is no stock to tick until Phase A.

### Tests

- **New:** a station's registry survives demote → promote, with `registry_seq`
  strictly monotonic across the cycle and earlier entries intact. Must run under
  **`configure_bubble`**, not FULL_SIM, or it proves nothing.
- `test_docking_registry` stays green unchanged (the bare-`Ship` path).
- Full gate green.

## Phase A — Station economy state (no behavior change)

Pure substrate. Nothing reads it yet, which makes it independently verifiable.

### The record fields

Two dicts on `ClusterEntity`, both empty on non-station records (same as
`docking_registry`):

```gdscript
var stocks: Dictionary = {}   # holder_key -> commodity -> bin
var market: Dictionary = {}   # holder_key -> commodity -> price/eligibility policy
```

`"self"` is the station's own bins; **any other key is a party's stockpile at this
location** (trap 5 — do NOT key on the station record). Bin:
`{stock, capacity, target, surplus_line}`. **No `rate` field** — see converters.

- **Bins are FULLY POPULATED for all four classes at load**, even zeros. CLAUDE.md's
  trap is that a missing `Dictionary[key]` aborts the rest of that frame's function;
  a two-level nested lookup doubles that surface. Guaranteeing the inner level means
  only the *holder* lookup needs a `.get()` guard.
- Commodity keys as constants (`Standing.FLAG_*` convention), not bare strings.

### Throughput is DERIVED — converters, not rates

An authored per-station `rate` is the same fudge factor as `service_rate`: Refinery
Prime consuming 3.3 ore/hr is *what happens when a converter runs*, not a property
of the station. Authored as a constant, the causal chain cannot exist.

The `"self"` entry authors industry instead:

```gdscript
"converters": [ { "in": {"ORE": 3.3}, "out": {"REFINED": 2.2}, "rate": 1.0 } ]
"sinks":   {"VOLATILES": 0.45}   # population upkeep -- a genuine constant
"sources": {"ORE": 1.5}          # SCAFFOLDING for mining traffic
```

- `achieved = min(rate, input_availability, output_headroom)` — **partial running
  (decided)**, scaled to the scarcest input, but **zero below a floor fraction** so a
  converter never trickles at 3%.
- **Stalls both ways:** STARVED (no input) and BLOCKED (output bin full because
  nobody is hauling). BLOCKED stops ore consumption too, so backpressure reaches the
  mines.
- **A stalled converter consumes NOTHING** (decided — no idle draw, no upkeep rule).
- **Sinks are separate and never stop.** The population keeps requiring volatiles
  whether or not any industry runs, so a cold refinery still drains volatiles —
  because its people do, not because it does.
- Expose the stall state per converter. STARVED and BLOCKED are **different
  problems with different fixes**, both facts a station knows about itself, so both
  become postable/mailable news later at different values.

### Urgency

`stock < target` → import; `stock > surplus_line` → export; else satisfied. Keys off
**stock**, which is what lets an over-served station flip and gives the secondary
market for free.

### Authoring — do NOT default from `role`

An earlier draft of this plan said rates default from `role`. **That is wrong**:
`role` has only `"hub"` and `"outpost"`, which cannot distinguish Refinery Prime
from Ironhold or ice-rich Coldreach from Slag Bay. The reference table has **eight
distinct profiles**, so role-defaults would be overridden in all eight cases — a
defaulting mechanism that never defaults. Author economy explicitly per station;
derive **only** ore extraction from the field's authored rock count. `role` stays a
port/UI concept.

### The delivery seam

```gdscript
deliver(holder, commodity, amount)   # the ONLY way stock increases
```

The `sources` scaffolding calls it on the economy tick; mining ships later call it
from the same `docking_bay` DOCKED hook haulers already use, so deleting the fake is
one line.

### The tick

A `StationEconomy` RefCounted appended to `ClusterManager.directors` — that array is
already "things ticked with the cluster", so period accumulation comes free. It must
walk **all station records regardless of liveness**: `tick()`'s existing loop skips
`is_static` records entirely, and most stations are dormant under BUBBLE. ~32 scalar
updates per period. Clamps to `[0, capacity]`, **no failure states**.

### Tests

- The design doc's reference table reproduces as the **expected steady state**
  (it is now an oracle, not an input): net flow per commodity settles to ~zero.
- Converter STARVES when input is withheld and output stops; converter BLOCKS when
  the output bin fills, and **ore consumption stops with it**.
- Partial running scales to the scarcest input; below the floor it is zero.
- A stalled converter consumes nothing, while the population sink keeps draining
  volatiles.
- Economy advances for a **dormant** station (this is the one that would silently
  not work if the tick were hung off live nodes).
- Clamps hold at both ends; urgency is 0 at target, 1 at empty, and flips direction
  above `surplus_line`.
- A party holder at the same location keeps its own separate bin (proves the
  `(location, holder)` keying, so trap 5 can't regress).

## Phase B — Postings (stations publish)

- A station converts private stock into a public offer: *who's offering, what's
  wanted, where, how much, **quantity remaining**, **eligibility**, price*.
- **Price is a policy on urgency, not urgency itself**:
  `price = f(urgency) x policy_multiplier(server)`, `f` mildly convex. Urgency stays
  objective and flag-blind; every political decision lives in the multiplier —
  zero-rate own flag, surcharge foreign, embargo at zero (trap 4).
- **Eligibility** is export control: a station may restrict a posting to given
  flags (Coldreach allowing only locally-flagged hulls to carry volatiles). The
  restriction stops **at the source** — once goods are in Ironhold's bins they are
  Ironhold's to sell to anyone, which is what creates the open secondary tier.
- Both dials may respond to urgency, so **protectionism is a luxury of the
  well-supplied**: locals-only when comfortable, anyone-at-a-price in a crisis.
- **Price is news.** A price you know is a price you *heard*, so remote price
  knowledge is provisional and the payout is agreed **in person at the station**.
- Quantity **depletes as served** — not an exclusive claim. A lot must stay small
  relative to a need (Refinery Prime's 16-lot deficit vs a 1-lot hull) so several
  ships can work one run.
- The board is **globally readable for now**, exactly as the registry is in Mail
  phase 1. Phase 3 of the mail vertical gates *visibility*, not structure.
- Deliveries apply at the existing `docking_bay.gd` DOCKED hook — the same
  convergence point the registry uses. **The player uses this hook too.**
- Tests: a posting appears when stock crosses the threshold and closes when
  satisfied; quantity depletes per delivery; payout fixed at acceptance, not
  recomputed on arrival; a HOSTILE ship denied docking cannot serve the posting
  (port control as an economic instrument).

## Phase B2 — Repair consumes stock (damage becomes demand)

Small, and it closes the combat→economy loop. Do it right after postings so the
demand it creates has somewhere to go.

- Gate `Ship._process_repairs` on the host station's stock. `c["type"] == "hull"`
  draws **REFINED**; every other component type draws **GOODS** (~3.3× dearer per
  HP). No new fields — the component taxonomy already carries `type`.
- **Stations are Ships**, so station self-repair is the same code path as
  repairing a docked ship. One mechanism, one ledger.
- **No stock → no repair.** A station out of REFINED cannot fix a hull.
- Tests: repair draws down the right class and stops at zero stock; a docked
  player's repairs move the station's stock (the loop reaching the player);
  station self-repair uses the same path; a large station repair produces a
  demand spike that raises its own postings.

## The soak sims — long-run balance validation (OUT of the normal suite)

Not tests: **`--run-tactical-sim`** runners (CLAUDE.md's established pattern for
long balance runs), writing to `tactical_analysis/data/*.csv`.

**The timescale trap.** Rates are lots/**hour** and bins carry ~24h of buffer, so
"30 minutes of game time" drains ~0.3 lots against a ~14-lot buffer — nothing
visible happens. And 30 game-minutes is not cheap either: at ~12ms/physics-step
the sim runs ~83fps headless, so one game-hour costs ~43 real minutes.

**But the economy needs no physics frames.** It is pure bookkeeping —
`StationEconomy.tick(dt, cluster)` accumulates and runs its pass per period, so
`tick(3600.0)` advances an hour instantly (`test_station_economy_reference`
already does 4 simulated hours in ~11s). That inverts the cost problem: a
bookkeeping soak can run **30 game-DAYS in seconds**.

So two runners with different jobs:

| Runner | Proves | Cost |
| --- | --- | --- |
| **`economy_soak`** — bookkeeping only, no ships | nothing starves; no converter stalls indefinitely; buffers are sized right; nothing pins to a clamp | seconds, for weeks of game time |
| **`economy_traffic`** — real hulls flying and docking | haulers actually SERVE the demand | expensive; meaningless before Phase C |

**Build `economy_soak` now, and expect it to report total collapse.** Coldreach
accumulates VOLATILES to its cap and goes BLOCKED while every other station drains
to zero on air — which is CORRECT: Phases A/B have production and consumption but
**nothing that redistributes**. That run is the *"before"* picture, and it turns
"stations stop starving" into a measurable pass/fail rather than a vibe.

**CORRECTION (2026-07-25), twice over.** An earlier draft said "economy_soak
passing is Phase C's acceptance criterion", and justified skipping a
ships-in-the-loop sim on a timescale argument. Both were wrong:

1. **`economy_soak` cannot validate Phase C.** It runs everything DORMANT with no
   ships, so a ship-side planner moves zero lots in it and it would report
   identical collapse afterwards. It proves only that removing all redistribution
   kills the cluster — which was never in doubt. Keep it as the *baseline*; it is
   not a validation.
2. **The timescale objection was bogus.** "30 game-minutes shows nothing because
   buffers are ~24h" only holds if the measurable is STARVATION. The right
   measurable is **net flow**: a hauler round trip is 12–24 game-minutes and
   delivers a lot, so 30 game-minutes gives 2–3 trips per hull — enough to see
   whether each station's stock trends UP or DOWN. **A station net-negative on a
   commodity it cannot produce will starve; you do not need to watch it happen.**
   At ~83fps headless that is ~21 real minutes. Entirely viable.

So **`economy_traffic` is the real validation and is a REQUIRED Phase C
deliverable**, not a follow-up.

| Runner | Question | Cost |
| --- | --- | --- |
| `economy_soak` (built) | baseline: how fast does it die with no redistribution? | seconds |
| **`economy_traffic` (Phase C)** | **do real hulls actually keep every station net-positive?** | ~21 real min |

Metrics: per station per commodity, net flow (lots/hr, so it is comparable to the
reference table), delivery count, min stock, and time-at-zero. **Verdict = any
station net-negative on a commodity it cannot produce itself.**

### What the first real runs taught (2026-07-25)

Three methodology corrections, all found by running it. Recorded because each
one produced a confident, wrong answer first.

**1. Net flow must be ATTRIBUTED, or repair defames the economy.** Four
independent things move a station's stock: the economy proper
(sinks/converters/sources), repair of docked guests, the station repairing
ITSELF, and trade. `_heal_components` is stock-gated for stations, drawing
REFINED for hull and GOODS for systems — so a station taking collision damage
bleeds exactly the two commodities an economy failure would, and reads
identically in a single net-flow column. The runner now measures all four
separately (repair reconstructed from per-component health deltas run back
through `HULL_HP_PER_LOT`/`SYSTEM_HP_PER_LOT` — the exact inverse of the
forward conversion, so it is not an estimate) and reports economy as the
residual.

**2. The verdict cannot key on the economy residual.** The first attributed
version moved the verdict off net flow onto the economy column, to stop repair
noise causing false failures. That is wrong in a way that is obvious in
hindsight: **the economy rate is negative by definition for any station that
consumes a commodity** — that is what a consumer *is*. Every consumer reported
FAIL regardless of how well it was served, including Ironhold/ORE and Refinery
Prime/ORE while both ran net POSITIVE on healthy trade. Net flow is the honest
measure of "is this station being kept alive"; attribution then explains *why*
it is negative. The verdict now names a cause — `UNSERVED`, `UNDERSUPPLIED`,
`OVER_EXPORTED`, `REPAIR_DRAIN` — because each has a different owner
(routing, fleet size, pricing, navigation).

**3. Sampling from frame zero measures the spawn transient, not the economy.**
Promoting the cluster produces a burst of component damage as bodies resolve
overlap, and the self-repair that pays for it drains REFINED/GOODS hard for
~2 minutes. Averaged across 30 minutes this reported Deepcut GOODS at
**−35.6/hr against an authored sink of −0.15**, and Ironhold GOODS at
**−74/hr against a +1.50 SOURCE**. The per-minute trace is what exposed it:
steep drop for two minutes, then dead flat at *exactly* the authored rate. The
economy was correct the entire time. The runner now flies a 3-minute **settle
window** and re-baselines every counter before measuring.

**Two real findings survived those corrections**, and both are keepers:

- **Hauler repair draw is now ~0.000/hr cluster-wide**, confirming the
  `steering.gd` avoidance fix (single most-urgent threat instead of summed
  perpendiculars) holds at cluster scale, not just in `test_nav_gauntlet`.
- **An all-`FLAG_DRIFT` fleet moves ZERO volatiles**, because Coldreach is the
  cluster's only VOLATILES source and restricts its EXPORT to
  `FLAG_MERIDIAN`. Eligibility working exactly as designed — and a fleet
  categorically unable to lift the one commodity everyone consumes cannot
  answer this sim's question. Haulers now inherit their home station's flag,
  which makes the fleet match the world rather than restate it. This is the
  M53d sovereignty question arriving as a measurement.

**General rule this reinforces:** a sim that reports a number is making a
claim about a mechanism. Check the number against the *authored* rate before
believing it — three times running, the alarming figure was an artifact of how
it was measured, and the trace (not the summary) is what settled it each time.

Note the prerequisite: today **nothing transfers on dock**. Phase B built
`fulfill()`, but the authored haulers still run fixed `CargoRunLeaf` loops with no
delivery wiring — a traffic sim right now would show ships flying and docking
while moving zero lots. Wiring delivery into the dock event is part of Phase C.

## Phase C — The ship-side planner (ONE planner, every ship)

**Supersedes an earlier "fleet operator dispatch" phase.** There is no operator
dispatch pass; an operator scoring for a hull 400k away would need instantaneous
command and control, which contradicts information travelling at hull speed.
Every ship plans for itself.

- `score(posting) = offered_price(posting, THIS ship) − travel_cost(from here)
  − risk_estimate(route, as I understand it)`. **No `flag_affinity` term** — price
  discrimination is station-side, willingness is owner-side (Phase D).
- *"The most profitable route I can see from here; follow it until I get better
  information."* Plans are **routes (2–3 legs), not next-hauls**, and **sticky**.
  Route search stays shallow — deeper lookahead against information this stale is
  false precision and reads as less legible behavior.
- Re-plan on itinerary completion **or** a material information change, with
  **hysteresis** — a competing route must beat the current plan's *remaining* value
  by a margin, or haulers thrash between near-equal routes.
- Built as a longer itinerary on the M50 job runner plus a re-plan leaf ordered
  ahead of `JobRunner` in `build_civilian_job()`. The plan lives in the ship's own
  `behavior` dict, so it survives the ship going dormant.
- Risk comes from *heard* news, which is what lets a hauler fly into an ambush the
  player already knows about.
- Population stays `TrafficGuild`'s job — it owns *how many ships exist*; the board
  owns *what work exists*.
- What this **deletes** versus the old plan: the greedy-per-hull assignment loop,
  reserve-within-fleet quantity bookkeeping, deterministic hull ordering, and the
  operator-side "which of my ships goes where" pass. Two hulls of one owner may now
  plan for the same posting — honest, since without instant coordination a real
  fleet duplicates effort.
- Tests: **anti-collapse first** — over N passes every eligible station is served at
  least once (the test that would have caught the dock-count model); hysteresis
  prevents thrash under small posting updates; a deadhead leg is costed (the
  Deepcut-vs-Ironhold reversal in the design doc's worked table reproduces); a ship
  settles into a circuit rather than oscillating; two ships with different heard-sets
  make different choices from identical world state.

## Phase D — Ownership policy and duties

Layered on the Phase C planner, not a separate planner.

- A policy object the hull **carries**: allowed station flags, risk ceiling / routes
  off limits, range from base, and **duties** (must-serve postings regardless of
  score — how a state fleet does unprofitable domestic work).
- **Duty replaces the flag-affinity weighting.** "Ironhold expects its own fleet to
  carry local mail" is an obligation, and the owner absorbs the cost.
- **Policy travels.** An owner who learns a lane went hot cannot recall a hull
  already out there — it updates policy only where its word reaches (base, office,
  or mail). Company hulls therefore fly on **stale orders**, by the same mechanism
  as everything else.
- Declining dangerous work is a line in the policy, not a withheld assignment; the
  posting stays up and bids toward an independent.
- Deferred to the mail vertical, where they belong: party-held stockpiles, offices
  as staged-mail presence, purchased fleet pictures. **Phase A must still adopt the
  `(location, holder)` shape** so none of it is foreclosed.
- Tests: a flag-constrained hull refuses an eligible foreign posting an
  unconstrained one takes; a duty is served at a payout the planner would otherwise
  reject; a policy update does NOT reach a hull already en route; a risk-ceiling
  change redirects a hull only at its next policy-reachable dock.

## Phase E — Information postings (freshness)

Belongs with Mail phase 2–3, listed here so the dependency is visible.

- A party publishes *"sync any source older than X, paying P"*. Requires the
  **third clock** (`confirmed_at`, per holder per source, merging as a max) — see
  [../design_ideas/mail_network.md](../design_ideas/mail_network.md), "Three
  clocks, not two".
- Test the **sync-farming hazard explicitly**: X must be long relative to trip
  times, or a courier farms two adjacent stations forever.

## Watch items

- **Perf.** `hard_cap` (10) still governs; more DESTINATIONS is not more SHIPS.
  Re-run `test_perf_baseline` in-gate, and per CLAUDE.md **A/B any alarming
  number** before believing this change caused it.
- **Duplicated world constants** must REFERENCE their source (bitten twice
  already: `FoamPhysics.BOUNDARY`, then `navigation_panel.gd`'s world extents).
- **Determinism.** Seeded RNG only; ties broken deterministically.
- **Three degenerate-under-repetition traps**, all the same class — write each
  test before its feature: positive feedback (dock-count demand), thrash (no
  re-plan hysteresis), sync farming (short freshness window).

## Explicitly not this milestone

- Latency-gating the board / relocating parties (Mail phases 2–3).
- Money, credits, or prices as an independent quantity — urgency is the
  proto-price and payout scale stays abstract.
- Physical cargo manifests (M55).
- A `Party` base class. Commit to the posting shape, not the hierarchy.
- Starvation consequences — clamps mean nothing bad happens at the boundaries.

## 2026-08-01 — two known seams, both now scheduled

- **`_risk_estimate()` gets its body in M59.** The stub (`route_planner.gd:312`,
  one call site at `:295`) was left as its own named function precisely so a
  later phase changes one function and not every call site. Because risk is
  subtracted from a payout, "avoid the lane" and "price the lane higher" are the
  same mechanism — no design fork.
- **Mid-flight re-planning is currently omniscient** (`route_planner_leaf.gd:81`
  — fires on a timer from `actor.position` against the live cluster). Tolerable
  for prices, arguably a market feed. NOT tolerable once risk is real: a hauler
  would divert because it learned the lane ahead went bad, which inverts the very
  fiction the stub was written for. M58 closes it with a snapshot stamped onto
  the job at dock, so mid-flight reads what the ship carried out of port.

Both in `m57_m61_information_economy_roadmap.md`. Expect the snapshot change to
move existing traffic-sim numbers — re-baseline rather than treating it as a
regression.
