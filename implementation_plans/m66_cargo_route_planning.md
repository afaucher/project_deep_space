# M66 — Cargo route planning: multi-stop and mixed loads

**Status: SCOPED, not built.** For review.

Collects work that until now existed only as scattered ledger decisions (D56,
D57, D59, D60, D71, D72) and one design doc
(`design_ideas/2026-08-04-routing-as-an-optimization-problem.md`). There was no
milestone for it, which is why it kept being rediscovered from different
directions.

Supersedes nothing. `m53c_demand_routing.md` is the planner as BUILT; this is
the change to its decision shape.

## Why now: a station is running out of air

The original motivation was mail urgency (D56/D57) — routing had to become a
state-dependent leg choice before a node reward could ride along on a trip. That
made this milestone an *enabler* for other work, and easy to defer.

**D72 gives it an independent justification.** `economy_traffic`, 180 game-min:

| station | volatiles deliveries | cover | verdict |
|---|---|---|---|
| Refinery Prime | **0** | 5.8 h | **UNSERVED** |
| Slag Bay | 1 | 10.3 h | **UNDERSUPPLIED** |
| Deepcut | **0** | 15.1 h | "ok" only because cover clears the 12h horizon |
| Halvorsen Claim | **0** | 15.1 h | same |
| Ironhold | 7 | | ok |
| Corvus Yards | 4 | | ok |

Coldreach, the cluster's only volatiles source, shipped **13 loads; eleven went
to two destinations and three consumers got zero** — including the most
desperate station in the run. VOLATILES has the shortest buffer in the game
deliberately (*"running out kills people; that should be a live threat you can
watch closing in"*), and the routing model structurally cannot serve it.

Eligibility is ruled out: Ironhold is `SOVEREIGN_DRIFT` and took 7 loads from
Meridian-flagged Coldreach, so the export restriction is not the cause.

## What is actually wrong

Two coupled things, both structural rather than tuning:

**The itinerary is a fixed six steps.** `route_itinerary` emits `GO_TO, DOCK_AT,
AWAIT, GO_TO, DOCK_AT, AWAIT` — one pickup, one dropoff, one `acceptance`, one
`amount`, one `route_commodity`. A second stop is not expressible.

**The search is a pair-shaped argmax.** `scored_routes` emits one route per
`(pickup, dropoff, commodity)` triple and `best_route` takes the max. Every
hauler independently computes the same winner, so *one source with seven small
buyers* resolves to *everyone flies to the biggest buyer*.

Mid-flight is not a state in that model either; it is patched with
`DROPOFF_LEG_START` and `remaining_value()` to stop counting the pickup as sunk
cost. Adding either generalisation below to today's shape means adding a second
patch that must agree with the first forever.

## The model

**State is `(position, cargo, bag)`. The decision is a LEG.** A leg's value
includes the value of the state it lands you in. "At a station" and "in flight
holding ore" become the same computation with different starting cargo, and the
mid-flight special case disappears rather than gaining a sibling.

Two rewards attach to different objects (D56):

| reward | attaches to | condition |
|---|---|---|
| cargo margin | a `(pickup, dropoff)` **pair** — an edge | destination must demand what you hold |
| node reward (later: mail bounty) | **arrival** at a node | none |

**Depth 2 minimum.** Diverting somewhere that does not buy what you carry leaves
you still holding it, so that node is worth `reward + V(node, cargo)` — one leg
past the arrival. Depth 1 is wrong in both directions.

**Objective is reward per unit TIME**, not per trip, or a fat reward justifies an
unbounded detour. `MIN_VIABLE_SCORE`'s "don't fly a loss" floor then applies to
the rate.

Cost is unchanged: depth-2 from a cargo state is `stations x stations x
commodities`, the same order the search already runs at re-plan time.

## Two generalisations that look alike and are not

Conflating these would build the wrong thing and read as a failed change:

| | shape | helps when |
|---|---|---|
| **milk run** | one commodity, one pickup, **many dropoffs** | many buyers each want a little of the same thing from one source |
| **mixed hold** | **many commodities**, one pickup, one dropoff | one buyer wants a little of several things |

**D72's volatiles case needs the milk run.** A mixed hold does nothing for it —
there is only one commodity to carry. Conversely D71's buyer-bound loads (96% of
loads far-end-bound, hull at 3% of capacity) are helped by either, because both
raise buyers-per-trip.

Neither needs bigger holds. `LOT_SIZE` at 4.0 is ~30x the realized load, so M55c
would widen a constraint that is not binding — the hold is empty for want of
buyers per trip, not space.

## Phases

- **M66a — the leg model.** `(position, cargo)` as a first-class state; a leg
  scored by `reward + V(landing state)`; depth 2; reward per unit time. Deletes
  the `DROPOFF_LEG_START` sunk-cost patch rather than extending it. No new
  itinerary shape yet — this is the scoring change alone, and it should be
  behaviour-neutral for an unladen hull with one viable pair, which is the A/B
  that proves it.
- **M66b — variable-length itineraries.** `route_itinerary` emits N stops
  instead of exactly two. Every DOCK_AT carries its own `delivery`, which is the
  seam M55a already settles per-dock, so nothing about the transaction changes.
- **M66c — the milk run.** One pickup, several dropoffs, chosen by the leg model.
  **D72's volatiles case is the acceptance test**: Refinery Prime, Deepcut and
  Halvorsen must stop reading zero deliveries.
- **M66d — the mixed hold.** Primary run plus opportunistic fill: pick the best
  pair as today, then fill residual volume with anything here that sells at a
  reachable destination. O(commodities) extra, no knapsack solver. Dissolves
  D59's laden-remainder escape hatch, because holding cargo you cannot sell at
  this stop stops being an error state.
- **M66e — congestion.** See open decisions.

## Explicitly NOT in this milestone

**No joint optimizer** (D57). The best assignment of 15 haulers across 13
stations is a multi-agent problem, and solving it needs exactly the omniscience
M64 exists to remove. Coordination belongs in the price.

**No mail bounty.** The node-reward slot exists in the model from M66a, but
filling it is the mail-urgency milestone's job (D56/D57), and landing both at
once would stack two variables in one score function.

**No capacity from parts** (M55c) — see above; the constraint is not binding.

## Measurement

Chosen before any result is seen, and the stage this changes is **coverage**, not
takes and not `risked_anyway`:

- **`economy_traffic` UNSERVED/UNDERSUPPLIED rows.** D72 is the baseline: 1
  UNSERVED, 1 UNDERSUPPLIED, plus two consumers at zero deliveries hidden behind
  the 12h cover horizon. This is the number that must move.
- **Deliveries per consumer**, not deliveries in total — the failure is
  distributional, and a total would hide it completely.
- **`CargoProbe`'s per-transfer ledger**: stops per run, and buyers served per
  pickup. That is the direct count of what the milestone changes.
- **Mean lots when laden** (D70's 0.34–0.61) should rise if concentration works,
  but it is a SECONDARY signal — reading it as primary would repeat the LANE_RUN
  error of judging a mechanism at the end of the funnel.

Precondition to lead any report with: **were there ever multiple viable dropoffs
for one pickup?** If not, the milk run has nothing to do and a null result means
nothing.

## Open decisions

1. **Congestion.** Nothing stops every hauler still choosing the same first leg.
   Postings deplete as served, which is a signal, but only after someone docks —
   between planning and arrival all haulers see the same board. D69 measured
   zero contention at the dock today, so this is not currently a problem; a milk
   run may or may not create one. Measure before adding machinery.
2. **Route commitment.** A longer itinerary is a longer commitment. The existing
   hysteresis is `HYSTERESIS_MARGIN` on remaining value; whether an N-stop plan
   should be re-planned mid-run, and against what, is undecided.
3. **Stop count bound.** Unbounded stops invite a hull that never comes home.
   Reward-per-time bounds it economically, but a hard cap may be wanted for
   legibility.
