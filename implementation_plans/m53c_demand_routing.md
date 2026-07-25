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
- Demand therefore moved **onto stations** as stock + rates, and the coupling
  between parties and the world became the **posting**.

## Phase A — Station economy state (no behavior change)

Pure substrate. Nothing reads it yet, which makes it independently verifiable.

- `stock` / `capacity` / `target` / `surplus_line` / `rate` per commodity class —
  **four classes: ORE / VOLATILES / REFINED / GOODS** — keyed by
  **`(location, holder)`, NOT by station** (trap 5). A station is just the holder
  that owns the port; a private company's warehouse at that same station is another
  holder in the same shape. Dormant-safe and serializable. VOLATILES is locally
  sourced (Coldreach only) and GOODS import-only (Ironhold only); that asymmetry is
  the point, not an oversight.
- **Urgency direction keys off STOCK, not `rate`**: `stock < target` → import,
  `stock > surplus_line` → export, else satisfied. Rate says which way a holder
  *drifts*; stock says which way it currently *wants*. This is what lets an
  over-served station flip to wanting its surplus gone — and the secondary market
  falls out of it with no extra mechanism.
- Rates default from the already-authored, currently-unused `role`
  ("hub"/"outpost"), with per-station overrides. **Ore production derives from
  the authored asteroid-field rock counts** (32/22/18/18/15) — not a new number.
- Ticks with the cluster, including while outside the sim bubble. Clamps to
  `[0, capacity]`, **no failure states**.
- `urgency(station, commodity)` as the single derived read.
- Tests: rates integrate correctly across dormant/promoted transitions; clamps
  hold at both ends; urgency is 0 at target and 1 at empty; the reference case
  in the design doc reproduces (net flow balances to zero per commodity).

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
