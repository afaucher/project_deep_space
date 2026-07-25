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
