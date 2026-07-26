# M53d — Meridian economic sovereignty (deferred)

Split out of the M53c economy design
([../design_ideas/station_economy.md](../design_ideas/station_economy.md)) on
2026-07-24 so the commerce **mechanism** could be settled without also settling
the world **balance**. Nothing in M53c depends on this; the interstate-commerce
gates and the dispatch score work regardless of who holds which monopoly.

## The problem

Under the M53c resource assignment, the two Meridian colonies are pure ore
sources with no domestic source for anything else:

| Class | Meridian's own source | Where they actually get it |
| --- | --- | --- |
| ORE | Halvorsen Claim, Corvus Yards | — (they export it) |
| VOLATILES | **none** | Coldreach — a *home* outpost |
| REFINED | **none** | Refinery Prime — *home* |
| GOODS | **none** | Ironhold — *home*, via home's wormhole |

So Meridian breathes home's air, repairs with home's steel, and imports through
home's port. That is not a peer sovereign — it is two mining camps operating at
home's pleasure, and home could end them by declining to trade.

**Why it matters:** it makes M53a's jurisdiction seam decorative. Warrants not
being mutually enforceable hardly matters when one side holds every utility. And
the interesting political content — sour relations producing *pressure and
smuggling* rather than instant capitulation — is unreachable.

All three cluster chokepoints are currently home's: Coldreach (only VOLATILES),
Refinery Prime (only REFINED), Ironhold (only GOODS import + all export). There
is no configuration in which home *needs* Meridian, so there is nothing to
negotiate over and nothing for a private carrier to arbitrage.

## The goal is interdependence, not parity (decided)

Cross-flag sourcing is **wanted** — a ship under one flag visiting a neutral
state to source materials is the traffic this milestone exists to create. The
seam only means something if ships routinely have to cross it. So the target is
not that each sovereign is self-sufficient; it is that **no sovereign is
self-sufficient.**

## Options

**A — Meridian is a spur of a bigger power elsewhere.** They import through their
own channel (a second wormhole, or dedicated freighters through the Nexus) and
are supplied from outside the cluster. Their weakness becomes a long, cuttable
supply line rather than dependence on home. *Weakness: reduces the cross-seam
trade this milestone wants.*

**B1 — Coldreach is Meridian too (LEADING, and it is a one-line change).**
Flip Coldreach from home to Meridian, so Meridian holds Corvus Yards, Halvorsen
Claim **and** Coldreach. Meridian then owns the cluster's only VOLATILES source.
No new production chain, no fifth commodity class, no new station — just a flag.

*It makes the border real.* By x-coordinate the split is already contiguous:

| Meridian (west) | x | Home (centre + east) | x |
| --- | --- | --- | --- |
| Corvus Yards | −300000 | Ironhold | 0 |
| Halvorsen Claim | −280000 | Refinery Prime | +80000 |
| **Coldreach** | **−140000** | Deepcut | +180000 |
| | | Slag Bay | +300000 |
| | | Drift Market | +400000 |

A western sphere of influence with a frontier, and Ironhold as a capital sitting
on the line — rather than scattered colonies.

*Coldreach becomes the border town.* It is **Ironhold's nearest neighbour** at
228k (vs 310k to Refinery Prime, 372k to Slag Bay), so the highest-volume
interstate lane is also the shortest. And the authored cargo lane **701 "Ore
Barge" already runs Ironhold↔Coldreach** — an existing lane becomes the political
artery. Customs, smuggling, tension, and both flags' hulls in one port.

*The leverage balances.* Home depends on Meridian for **VOLATILES** —
existential and fast. Meridian depends on home for REFINED, GOODS import, and
**all export access** — economic and slow. Home holds three levers, Meridian holds
one, but it is air. Mutual assured disruption, which is what explains why they
coexist despite the seam instead of one absorbing the other. Meridian's entire
export income flowing through home's port is a grievance to keep, not fix.

*Credibility:* ice is where ice is. Geology is not political, and borders get
drawn *around* resources precisely because of that.

*Cost — a flag audit in the style of M53a Slice A:*
- `home_cluster.gd`: Coldreach gains `meridian_iff` + `FLAG_MERIDIAN`
  (`warrant_authority` follows automatically from the existing `_station` helper).
- Cargo lane 701 becomes Meridian-flagged → `TrafficGuild.population_targets`
  shifts from `{DRIFT: 2, MERIDIAN: 2}` to `{DRIFT: 1, MERIDIAN: 3}`.
- Test audit for anything asserting Coldreach's flag/standing:
  `test_meridian_cargo_run`, patrol/interdiction tests, possibly
  `test_drift_residents`.
- **Verify:** whether a home patrol loop currently covers Coldreach. A home patrol
  orbiting what is now foreign space may be *interesting* (authority it cannot
  exercise where it flies) rather than wrong — but the seam tests should surface
  it deliberately.

**B2 — Corvus Yards as fabricator (alternative to B1).** The name is the tell
(as Coldreach and Refinery Prime were): *"Yards"* means fabrication. Corvus
consumes REFINED + ORE and produces **GOODS**, a domestic substitute for what
home imports through the Nexus; home's dependence then comes from an import cap.
Needs no fifth class either, but it is a new production chain and a rate rebalance
rather than a flag flip — and it makes home's dependence *gradual* (slowed repair)
where B1 makes it *sharp* (no air). Keep as the fallback, or as a later addition
on top of B1.

**C — Meridian genuinely is a client state, on purpose.** Keep the asymmetry but
make it *content*: the colonies are hostages, the seam is about extraction and
resentment, and the story is decolonisation. Legitimate — but it should be a
decision, not an accident of a rate table.

## Open levers (both change numbers, not prose)

- **Is the GOODS import cap the right lever?** Capping Ironhold's import below
  total demand is what forces home to need Meridian, and makes the shortfall
  show up as *slowed repair and degrading systems* rather than a cliff. The
  alternative — Corvus holding a true monopoly on some tier — is sharper but
  makes home's dependence sudden.
- **Does Meridian get a refinery?** Without one they cannot repair structurally
  without home's REFINED, which is a hard leash. Fine as a starting condition and
  a story engine, but if Meridian is ever meant to be able to *defy* home they
  need one — and that is a station addition, not a rate change.

## Not blocked by this

- M53c phases A–E (state, postings, dispatch, independents, freshness).
- The interstate-commerce gates (admission / eligibility / price) — they are
  mechanism, and work under any balance.
- The dispatch score's `flag_affinity` weighting — already parameterized, so a
  changed balance is a config change.

---

# RESOLUTION (2026-07-25) — RARE, margins, and refined-as-export

Settled in the calling session after the first `economy_traffic` runs made the
real problem measurable. Two decisions, taken together.

## The finding that forced it: the cluster is balanced to EXACTLY zero margin

Tallying the authored rates cluster-wide:

| Class | Supply/hr | Demand/hr | Margin |
| --- | --- | --- | --- |
| ORE | 8.9 | 8.9 (Ironhold export 5.6 + Refinery Prime 3.3) | **0.0** |
| VOLATILES | 2.60 (Coldreach) | 2.60 (seven stations) | **0.0** |
| REFINED | 2.20 (Refinery Prime) | 2.20 (seven stations) | **0.0** |
| GOODS | 1.50 (Ironhold import) | 1.50 (seven stations) | **0.0** |

Supply equals demand to the decimal on all four. That is the reference table
made real, and it is the equilibrium of a system with **no losses** — which
this system is not. Three consequences, all observed:

1. **It makes trade structurally impossible, which is the same finding as "no
   EXPORT posting ever opens."** A producer running at exactly 100% of demand
   never accumulates a surplus; `surplus_line` gates exports on surplus;
   therefore no export posting can ever open for REFINED or GOODS. These were
   logged as two separate problems. They are one.
2. **Cargo in flight is a permanent deficit.** A lot in a hold is at neither
   source nor sink, and a zero-margin system has no spare production to refill
   the pipeline.
3. **ORE contention is unresolved.** Ironhold's export (5.6) and Refinery
   Prime (3.3) need *precisely* all 8.9, and urgency-priced bidding hands ore
   to whoever is nearest zero. Ironhold sits at zero, so it outbids — starving
   the converter that makes ALL the cluster's REFINED. Measured: Refinery Prime
   producing 1.112/hr against 2.2 authored, exactly 50%. An ore shortfall does
   not stay an ore shortfall; it becomes a refined famine for seven stations.
   The designed cascade, arriving uninvited as the resting state.

**Scarcity has to be an event before it can be a story.** Every rate below is
chosen to make the cluster solvent at rest, so that losing a mining ship
*means* something.

## Decision 1 — RARE, a fifth class

A pure export good: produced only in Meridian space, consumed by nobody in the
cluster, leaving through Ironhold's wormhole gate like ORE does today.

- **Balance and pricing are ORDINARY.** Same urgency scale, no intrinsic
  per-commodity value, no special multiplier. It is hard currency in the
  fiction, not in the code — and it should stay that way until something
  actually needs it to be otherwise.
- **Anyone may carry it.** Meridian controls the SALE, not the carriage — a
  purchase monopoly, deliberately weaker than Coldreach's carriage restriction
  on VOLATILES.
- **Halvorsen Claim and Corvus Yards produce it, Coldreach does not.** Splits
  the two kinds of leverage across different stations instead of stacking every
  card at one.

### Why this is the right shape: the two monopolies are ASYMMETRIC

- **Coldreach's air is existential and fast.** Home stops breathing. Meridian's
  lever is lethal, which makes it a nuclear option rather than an everyday one.
- **Meridian's RARE is economic and slow, and home can block it for free.**
  Ironhold does not consume rare — outside buyers do — so home can close the
  gate at no cost to itself while Meridian loses its entire income.

So home is structurally the stronger party in a standoff, and Meridian's only
counter is escalation. That is *why they coexist* instead of one absorbing the
other, and it falls out of the commodity graph — no diplomacy system, no
scripted relationship, no new mechanism. It also self-enforces: with no
domestic consumer, a closed gate fills Meridian's RARE bins to capacity and
BLOCKS production through the backpressure that already exists.

## Decision 2 — export REFINED, not raw ORE

The cluster currently ships out more unprocessed rock (5.6/hr) than it adds
value to (3.3/hr). That is a colony, not an industrial base, and it is the
direct cause of the contention in finding 3 above.

**Destination:** the next cluster's shipyard. The export is not into a void —
home refines ore into structure and Meridian sells exotics, and both feed hull
construction beyond the Nexus. That is what makes the outside want both goods,
and it is a content hook, not just a sink.

## The new numbers

| Class | Supply/hr | Demand/hr | Margin |
| --- | --- | --- | --- |
| ORE | 8.9 (unchanged) | 7.4 = Refinery Prime **6.6** + Ironhold raw export **0.8** | +1.5 (20%) |
| REFINED | **4.4** (Refinery Prime, same 2:3 conversion) | 3.8 = upkeep 2.2 + Ironhold export **1.6** | +0.6 (16%) |
| VOLATILES | **3.20** (Coldreach, was 2.60) | 2.60 | +0.6 (23%) |
| GOODS | **1.85** (Ironhold import, was 1.50) | 1.50 | +0.35 (23%) |
| RARE | **0.80** (Halvorsen 0.40 + Corvus 0.40) | 0.65 (Ironhold export) | +0.15 (23%) |

Per-station changes:

- **Refinery Prime** — converter `{in: ORE 6.6, out: REFINED 4.4}` (was 3.3/2.2).
  Ratio unchanged; it simply runs at the scale the cluster's ore supports.
- **Ironhold** — ORE sink 5.6 → **0.8**; REFINED sink 0.50 → **2.10** (0.50
  population upkeep + 1.60 export); GOODS source 1.50 → **1.85**; new RARE sink
  **0.65**. Still the only gate.
- **Coldreach** — VOLATILES source 2.60 → **3.20**.
- **Halvorsen Claim / Corvus Yards** — new RARE source **0.40** each.

Refined leaves at 2:1 against raw ore, so "mostly refined" is true by volume as
well as by value — which matters while price carries no per-commodity term.

## Verification

`economy_soak` (30 game-days, seconds, no physics) answers whether the margins
hold at rest. `economy_traffic` answers whether the fleet realises them. The
acceptance bar is the one the sim already reports: no station net-negative on a
commodity it cannot produce, with `UNSERVED` rows going to zero — and now with
a real expectation that EXPORT postings actually open, which no run to date has
seen for REFINED or GOODS.

## Blast radius

`Commodity.ALL` is data-driven and `ensure_holder` auto-populates bins, so a
fifth class mostly propagates itself. The churn is the 8×4 reference table in
[../design_ideas/station_economy.md](../design_ideas/station_economy.md)
becoming 8×5, `test_station_economy_reference`'s expectations, and one more row
per station in both sim CSVs.

---

## AMENDMENT — export belongs on the Nexus hauler, not on sinks

The rate table above expresses export as **Ironhold sinks** (REFINED 1.60 of
its 2.10, RARE 0.65). That is deliberate scaffolding with a known lifespan,
and it should be read that way rather than as the intended design.

**The target shape:** the cluster's largest freighter comes through the Nexus
wormhole periodically, docks at Ironhold, takes **whatever Ironhold is willing
to give up**, and leaves. TrafficGuild already spawns transient wormhole
freighters that arrive at the wormhole, dock, and `EXIT_AT` it — the code's own
comment says they "rebalance nothing; just make the road busy." That is the
export mechanism sitting there fully routed and carrying zero cargo; it needs
`pending_delivery` on its `DOCK_AT` steps, which is exactly what
`RoutePlanner.route_itinerary()` already emits.

**Why this is strictly better than a sink:**

- **"Whatever Ironhold is willing to give up" is already modelled.** A station
  posts an EXPORT for stock above `surplus_line`. Willingness *is* the posting;
  the hauler is just a very large buyer that clears the board.
- **Export becomes the RESIDUAL CLAIMANT rather than a competitor.** A sink
  bids at full urgency and can outbid domestic demand — which is exactly how
  Ironhold's old 5.6/hr ore export starved Refinery Prime to 50% output. A
  freighter taking only posted surplus *structurally cannot* do that. It also
  means export rates need no precise tuning: **the margin is the export.**
- **Ironhold stops being a sink and becomes a warehouse.** If freighters stop
  coming, stock backs up, bins hit capacity, converters BLOCK, and the cascade
  runs backwards into Refinery Prime through machinery that already exists. A
  constant sink can never model an interrupted outside.
- **It fixes the merged-sink wart.** Ironhold's REFINED 2.10 is population
  upkeep and export fused together because the model allows one sink per
  commodity. With a freighter, upkeep stays a sink and export is a ship —
  independently disruptable, so "the shipyard cancelled its order" no longer
  starves Ironhold's own people.
- **Export becomes physical and interdictable.** A pirate can rob the shipment;
  a blockade actually stops trade; "home controls export access" becomes home's
  patrols sitting between Meridian and the gate. Geography, not a rule.
- **It gives the economy a rhythm.** Stock accumulates, the hauler pulses, stock
  drains. *"The Nexus hauler comes in two days"* is something a player can plan
  a run around; a constant invisible drain is not.
- **The Meridian squeeze becomes non-violent and visible.** RARE warehouses at
  Ironhold. To pressure Meridian, home simply does not load it — no blockade, no
  shots, just a hold that does not open.

**Two knobs replace five export sinks:** visit interval and hold size. At ~3
lots/hr of exportable surplus against ~24h bins, a visit every 12–18 game-hours
arrives to 40–55 lots waiting — which is what justifies it being the largest
hull in the game rather than merely a big one.

**Verified feasible (2026-07-25):** `test_dock_approach`'s Nexus scenarios
confirm a HEAVY `Freighter` (mass ~300, accel 8–12, max_speed ~400) berths at a
MediumStation cleanly — solo, zero contacts, 0.00% station HP. Arriving into
live shuttle traffic it needed the approach-discipline and avoidance-projection
fixes to be safe (2.90% → 0.14% station HP), because collision damage scales
with reduced mass and a 300-mass hull turns a shuttle-sized graze into 2890 HP.
Docking works; the ferry-out alternative is not needed.

**Staging:** keep the sinks until the M53d rates are validated end to end, then
replace them. Changing rates and moving export onto ships in one step makes an
unstable result uninterpretable — which is the same confound that produced three
false findings in the session that authored this plan.
