---
name: economy-balance
description: >
  Change station economy rates, add commodities, and validate cluster balance
  for Project Deep Space. Use when editing sources/sinks/converters, adding a
  commodity class, adjusting bin capacities, diagnosing starvation or stalled
  converters, or reading the economy sim results. Covers the mandatory
  supply/demand tally, why margin is a precondition rather than a preference,
  the two-stage validation ladder, and the measurement traps that have
  repeatedly produced confident wrong answers.
---

# Economy Balance Skill

## Project Context

- **Stack**: Godot 4.x + GDScript
- **Key files**:
  - Director: `scripts/directors/station_economy.gd`
  - Commodity classes: `scripts/economy/commodity.gd`
  - Authored rates: `scripts/cluster/home_cluster.gd` (`_economy_*` functions)
  - Bin sizing: `home_cluster.gd`'s `_bin()`
  - Record state: `scripts/cluster/cluster_entity.gd` (`stocks`, `market`, `industry`)
  - Ship-side routing: `scripts/ai/route_planner.gd`
  - Sims: `tactical_analysis/sim_runners/{economy_soak,economy_traffic}.gd`
  - Design: `design_ideas/station_economy.md`, `implementation_plans/m53d_meridian_sovereignty.md`

---

## 1. ALWAYS tally supply vs demand before changing a rate

Cluster-wide, per commodity. This is not optional and it is not obvious from
reading any single station — the imbalance only exists in the sum.

```
supply  = sum of every station's sources[C] + every converter's out[C]
demand  = sum of every station's sinks[C]   + every converter's in[C]
```

Watch for the two entries that are easy to miss:

- **A converter's input is demand.** Refinery Prime's `{in: {ORE: 3.3}}` is 3.3
  ORE/hr of demand, not a free transformation.
- **An export sink is demand too**, and it competes at full urgency with
  domestic consumers. Ironhold's ORE sink was export-through-the-wormhole and
  outbid the refinery for the same ore.

## 2. Margin is a PRECONDITION for trade, not a balance preference

This is the single most important thing in this file.

An EXPORT posting only opens when a bin is above its `surplus_line`. A producer
running at exactly 100% of demand **never accumulates a surplus**, so it can
never post an export, so its commodity can never be hauled anywhere — at any
fleet size, with any router.

Discovered 2026-07-25: the home cluster was authored with supply == demand to
the decimal on all four commodities. That reads as elegant balance and is
actually a system that cannot trade. It also means:

- **Cargo in flight is a permanent deficit.** A lot in a hold is at neither
  source nor sink, and a zero-margin system has no spare production to refill
  the pipeline.
- **Anything that competes at max urgency wins and starves the rest.** A
  station at zero stock outbids everyone, so a shortfall in an input cascades
  into a famine of whatever that input produces.

**Rule: author supply above domestic demand (~15-25% is a reasonable start).**
The surplus is what gets exported and what makes trade exist at all.

## 3. `_bin()` derives geometry from the rate — changing a rate moves the bin

```gdscript
capacity     = max(50.0, abs(rate_hint) * 24.0)   # ~24h of throughput, floor 50
target       = capacity * 0.5
surplus_line = capacity * 0.85
```

Consequences worth knowing before you are surprised by them:

- A **low-rate bin hits the 50-lot floor**, so it holds far more than 24h and
  takes proportionally longer to climb from `target` to `surplus_line` — up to
  ~29 real hours before its first export posting can open on a fresh world.
  This is why sims need a warmup.
- Every bin starts at `target` (== `stock`), which is SATISFIED — no posting at
  all. A fresh cluster has nothing to haul until imbalance accumulates.

## 4. The validation ladder — cheapest instrument that can answer the question

Never debug balance through a physics sim.

| Stage | Runner | Answers | Cost |
|---|---|---|---|
| 0 | pen and paper | Does supply exceed demand per commodity? (§1) | seconds |
| 1 | `economy_soak` | Does the mechanism run — converters, bins, a new commodity — without erroring? | **seconds** for 30 game-days |
| 2 | `economy_traffic` | Does a real fleet actually keep stations served? | ~20 real minutes |

`StationEconomy.tick()` is pure bookkeeping — it needs no physics frames, which
is why stage 1 covers weeks in seconds.

**`economy_soak` CANNOT validate balance, and expecting it to is a trap I fell
into while writing this file.** It runs nothing that redistributes: no ships,
no hauling. So every consumer starves and every producer pins at capacity
*regardless of how the rates are authored* — a well-margined cluster and a
hopeless one produce identical soak output. What it is genuinely good for is
that a run completes cleanly: no missing-key errors, a newly added commodity
populating everywhere it should, converters entering the states you expect.

**Solvency is a cluster-wide arithmetic property (stage 0), and whether the
fleet realises it is stage 2.** There is no cheap simulation shortcut between
those two.

```bash
./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim economy_soak
```

## 5. Reading results: check measured against AUTHORED before believing anything

**Three separate times this produced a confident wrong answer.** The economy was
correct every time; the measurement was not.

- **If `economy/hr` matches the authored rate, the economy is fine** — whatever
  looks wrong is elsewhere. A correctly-clamped partial (a converter throttling
  on missing input, a source blocked by a full bin) is also correct: that is
  backpressure working.
- **Use the attribution columns, never raw `net_flow`.** Four independent things
  move a station's stock: the economy proper, repair of docked guests, the
  station repairing ITSELF, and trade. Station self-repair draws REFINED (hull)
  and GOODS (systems) — *exactly* the commodities an economy failure would
  drain — so a navigation problem is indistinguishable from an economy failure
  in a single net column.
- **Never key a verdict on the economy residual.** It is negative BY DEFINITION
  for any station that consumes a commodity — that is what a consumer is. Key on
  net flow and use attribution to explain *why*.
- **Discard a settle window before sampling.** Promotion produces a burst of
  collision damage and the self-repair paying for it; sampled from frame zero it
  reported a −0.15/hr sink as **−35.6/hr**, and a +1.50 SOURCE as −74/hr.
- **The per-hour trace, not the summary, is what settles an argument.** In every
  case above the trace showed a short transient then dead-flat at exactly the
  authored rate.

## 6. Eligibility can silently zero out a whole commodity

`market.<C>.eligible_flags` restricts who may lift a posting. A fleet with the
wrong flag sees **no route at all** rather than an error — the posting is simply
invisible to it.

Observed: an all-`FLAG_DRIFT` hauler fleet moved **zero** volatiles
cluster-wide, because Coldreach is the only VOLATILES source and restricts
export to `FLAG_MERIDIAN`. Everything was working exactly as designed and the
sim could not answer its own question.

**When a commodity shows zero trade, check eligibility before touching rates.**

## 7. Adding a commodity class

`Commodity.ALL` is data-driven and `StationEconomy.ensure_holder()` populates
bins for every class, so a new commodity mostly propagates itself. What does
NOT propagate:

- The reference table in `design_ideas/station_economy.md` (N stations × M
  classes) and `test_station_economy_reference`'s expectations.
- One extra row per station in both sim CSVs.
- Any commodity with **no domestic consumer** must have somewhere to go, or
  producer bins fill, hit capacity, and BLOCK production. (That backpressure is
  usually the desired behavior — it is how a closed export gate stalls an
  economy on its own — but it should be deliberate.)

## 8. Design invariants — do not break these while tuning

- **The decision lives where the information lives.** No global optimizer, no
  operator dispatch. Every ship plans for itself from its own position and flag.
- **Need and terms are separate.** `urgency` is objective and flag-blind;
  `price = f(urgency) × policy_multiplier(server)`. Do not encode "who we like"
  into urgency.
- **Postings are the only coupling.** Quantity depletes as served; it is not an
  exclusive claim, and several servers may spend acceptances against the same
  bin.
- **Converters derive their own throughput.** Do not author a separate sink for
  a converter's input — the converter's `in` IS the consumption.
