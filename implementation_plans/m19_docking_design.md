# M19 — Docking (force-capture soft-dock)

**Campaign milestone 6 of 7 (built early, by request). DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M16 (stations exist). Independent of nav (M17) and patrol (M18) — a
docking test just places a shuttle in the capture zone; no route AI needed.

**Shipped:** `scripts/docking/docking_bay.gd` (mass-normalized spring-damper
capture → settle → hold → release, one-occupant with a per-hull claim so
multi-berth stations don't double-capture); `Ship.dockable`/`wants_dock`/
`docking_bay` + `get_berths()` hook, bays grown in `_ready`; berths on the
stations (clear of the hull collision circle); `CargoShuttle.dockable`.
Acceptance: `test_docking` (single shuttle captures/settles/releases) and
`test_docking_multi` (four shuttles → four berths, distinct capture, and the
closest any two ever came stayed > 150u — no slamming) both green; ship-physics
regression (`test_point_defense`, `test_ai_duel`, `test_ship_designs`) unaffected.

**Goal:** autonomous approach → capture → hold → depart, via the resolved
force-capture soft-dock: a berth applies a spring-damper hold, no rigid joint.

## 1. The model

- **A berth is a pose.** `DockingBay` (`scripts/docking/docking_bay.gd`, a `Node2D`)
  is placed at a berth offset on a station; its own global transform *is* the
  target pose. A station grows one bay per berth in `Ship._ready` (via an
  overridable `get_berths()`), positioned clear of the hull's collision circle.
- **Capture is mass-normalized spring-damper.** While a dockable ship that has
  requested docking is inside `capture_radius`, the bay applies
  `force = mass * (K_SPRING*pos_err - K_DAMP*vel)` and the analogous torque toward
  berth heading. Mass-normalized so behaviour is ship-mass-independent;
  `K_DAMP ≈ 2*sqrt(K_SPRING)` is ~critical (draws in, doesn't overshoot). No joint.
- **Settle → hold → release.** When within `pos_tolerance` and slower than
  `settle_speed`, the bay latches `DOCKED` and runs a `dock_duration` load/unload
  timer (still servoing to hold the ship seated), then releases and clears the
  ship's dock request so it departs under its own power.
- **Eligibility.** `Ship.dockable` (CargoShuttle sets it) + `Ship.wants_dock` (the
  request). Only a dockable, docking-seeking ship is captured — a warship or a
  passing shuttle that hasn't requested is ignored. (In M20 the route AI raises
  `wants_dock` on arrival; for M19 the test sets it.)

## 2. Why force, not joint

Rigid joints on `RigidBody2D` at these scales are finicky and overkill for civilian
traffic that just loads/unloads. A spring-damper capture gives the physical
"tractor pulls you into the berth and holds you" feel, degrades gracefully (bad
approach → still drawn in or simply not captured), and needs no special teardown.

## 3. Scope / boundary

- Berths sit **outside** the station's collision circle so capture doesn't fight
  the hull's physics body.
- **No comms handshake** yet (station "docking instructions") — a later polish;
  the mechanic is the capture. Newton's-third-law reaction on the (massive)
  station is ignored.
- One berth per station for now; multi-berth is just more `get_berths()` entries.

## 4. Validation (`test_docking.gd`)

Spawn a small station (which grows its bay) + a passive cargo shuttle offset from
the berth with `wants_dock = true`; step physics and assert:
- the bay captures it and it **settles** at the berth (moved >500u in, ends within
  `pos_tolerance`, speed < `settle_speed`) — i.e. capture actually worked, it
  didn't start there;
- the bay reaches `DOCKED`, then **releases** after `dock_duration` (state back to
  `EMPTY`, `wants_dock` cleared);
- position stays finite throughout (no fling / NaN).

## 5. Open questions

- **Comms handshake** (docking clearance / instructions) — deferred; wire to
  story_driven_comms later.
- **Capture-vs-AI hand-off:** when the route shuttle (M18/M20) is captured, its own
  steering must yield to the bay. For M19 the shuttle is passive; M20 resolves the
  hand-off (raise `wants_dock`, stop steering).
- **Berth contention:** two shuttles racing one berth. One-occupant bay already
  serializes; a queue is later polish.
