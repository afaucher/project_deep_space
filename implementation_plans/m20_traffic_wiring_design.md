# M20 — Traffic Wiring (cargo runs = patrol + docking)

**Campaign milestone 7 of 7. DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M18 (route following) and M19 (docking). The join: cargo shuttles that
run a fixed lane of stations, docking at each end, unloading, and moving on —
the living-world payoff of both systems.

**Shipped:** `CargoRunLeaf` (transit → request → yield-to-berth → depart cycle,
resolving the M19 capture/steering hand-off); `Ship.cargo_docking`/
`cargo_captured_seen`; `AITreeFactory.build_cargo()`; manager wiring (a `TRAFFIC`
hull with `behavior.cargo` gets the cargo tree); two cargo lanes in the home
cluster (Ironhold↔Drift Market down the road, Ironhold↔Coldreach outpost), started
on the approach so they don't spawn inside a hull. Acceptance `test_cargo_run.gd`
green (a shuttle completes a full dock at both stations on its lane). Also verified
the campaign menu path end-to-end: `test_campaign_bootstrap.gd` drives the real
`main._bootstrap_campaign()` and confirms the player spawns at the start, the whole
cluster loads into a self-ticking manager, and the neighbourhood promotes.

## 1. The cargo-run behavior

`CargoRunLeaf` (`scripts/ai/leaves/cargo_run_leaf.gd`) drives a shuttle around its
lane (`patrol_route` = station positions, `patrol_loop` = round-trip), with a
two-state cycle per stop:

- **TRANSIT** — cruise toward the next station (drift-cancel lead-pursuit, as
  M18). Within `DOCK_REQUEST_RADIUS` of it, raise `wants_dock` and enter DOCKING.
- **DOCKING** — *yield to the berth*. While the station bay holds the shuttle
  (`docking_bay != null`), coast (no thrust) so capture owns the motion; once the
  bay releases (clears `wants_dock`/`docking_bay` after its load/unload timer),
  advance to the next station and go back to TRANSIT. If a berth isn't free yet,
  hold near the approach point until one is.

The hand-off M19 flagged is resolved here: the shuttle stops steering the moment
it's captured, so its propulsion never fights the capture spring.

## 2. Tree + wiring

- `AITreeFactory.build_cargo()` = `Selector[Disengage, CargoRun, Idle]` — a hauler
  flees when attacked (civilian, unarmed) and otherwise runs its lane.
- `Ship.cargo_docking` / `cargo_captured_seen` — the per-stop dock state (reusing
  `patrol_route`/`patrol_index`/`patrol_loop` for the lane itself).
- Manager: a promoted `TRAFFIC` hull whose `behavior` has `cargo: true` gets
  `build_cargo()`; a plain `route` gets `build_patrol()` (M18); else combat.
- Home cluster: cargo shuttles on set lanes (**not** a full mesh) — a hub↔hub run
  down the beacon road and a hub↔outpost run — starting at Ironhold so they're
  visible from the player's start.

## 3. Validation (`test_cargo_run.gd`)

One shuttle, two nearby stations, `loop = true`. Assert the shuttle **completes a
dock at station 0 and at station 1** within the budget — i.e. it flew a leg,
docked (was actually captured, not just "arrived"), was released, transited to the
other station, and docked there too. Position stays finite. That's the full
patrol→dock→unload→depart→repeat cycle end-to-end.

## 4. Scope / boundary

- **Lanes are fixed** (each shuttle serves its authored pair), per the original
  spec — no dynamic routing/economy.
- **Dormant transit dead-reckons straight** (the open "dormant fidelity" decision):
  a shuttle mid-lane goes dormant off-screen and drifts; on re-promote the cargo
  leaf just resumes toward its current station target. Good enough until the
  `Degraded` policy's route-tick.
- **No cargo/economy payload** — "load/unload" is the dock timer; actual goods are
  a later systems concern.

## 5. Open questions

- **Berth queueing:** the hold-near-approach loiter is minimal; a proper queue is
  later polish if lanes get busy.
- **Comms:** docking clearance / manifest chatter ties into story_driven_comms
  later.
