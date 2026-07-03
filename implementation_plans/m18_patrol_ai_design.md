# M18 — Route / Patrol AI (ships that move)

**Campaign milestone 5 of 7. DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M16 (things to patrol). The AI has had no waypoint navigation — only
Engage/Idle/StationKeeping. This adds route-following so traffic moves, with
ship-ship separation so patrols don't slam into each other.

**Shipped:** `FollowRouteLeaf` (drift-cancelling lead-pursuit steering +
separation); `Ship.patrol_route`/`patrol_loop`/`patrol_index`;
`AITreeFactory.build_patrol()`; manager wiring (a `TRAFFIC` hull with a
`behavior.route` gets the patrol tree + route on promote); two LAC patrols in the
home cluster (loops around Ironhold and Drift Market). Acceptance `test_patrol.gd`
green (two frigates loop a square route and the closest they ever come stays above
the collision margin); cluster/docking/combat regression all green.

## 1. The pieces

- **`FollowRouteLeaf`** (`scripts/ai/leaves/follow_route_leaf.gd`) — steers the
  actor along `patrol_route` (world-space waypoints) in velocity/cruise mode,
  advancing to the next waypoint on arrival, looping at the end. Returns FAILURE
  when the hull has no route, so the selector falls through to Idle.
  **Separation:** desired heading toward the waypoint is blended with a repulsion
  from nearby ships (stronger the closer they are) — the "don't slam" rule for
  moving hulls.
- **`Ship.patrol_route` / `patrol_loop` / `patrol_index`** — the route, whether it
  loops, and the current target index (the leaf writes it; tests read it).
- **`AITreeFactory.build_patrol()`** — `Selector[Disengage, Engage, FollowRoute,
  Idle]`. A patrolling hull still fights: a hostile makes Engage preempt the
  patrol; when it's clear, FollowRoute resumes. No route → Idle.
- **Manager wiring** — a promoted `TRAFFIC` hull whose `ClusterEntity.behavior`
  carries `{route, loop}` gets `build_patrol()` + its route set; otherwise the
  default combat tree. Stations still get `build_station()`.
- **Home-cluster traffic** — LAC patrols added to the Sovereign Drift (a loop
  around a hub), so launching Campaign shows ships actually moving.

## 2. Steering model

`FollowRouteLeaf` aims the nose along a **drift-cancelling lead-pursuit** vector:
`desired_vel = (dir_to_waypoint + separation) * CRUISE_SPEED`, then steer toward
`desired_vel - current_velocity` (correct the velocity error), falling back to
`desired_vel` once already on course. Driven through
`apply_control_input(0, CRUISE_SPEED, heading, combat, velocity-mode)` — reusing
the exact control surface combat steering uses, no new ship movement code. Arrival
within `ARRIVAL_RADIUS` advances the index; `CRUISE_SPEED` is kept low enough that
even a heavy frigate corners inside `ARRIVAL_RADIUS` rather than orbiting it.

## 3. Validation (`test_patrol.gd`)

Two frigates on the same square loop, started close together:
- **Movement + loop:** each `patrol_index` advances 0→1→2→3 and wraps back to 0
  (proves route-following and looping).
- **No slam:** the closest the two ever come stays above the collision margin
  (proves separation keeps moving patrols apart), positions stay finite.

## 4. Scope / boundary

- **Separation is ship-ship only.** Avoiding stations/asteroids is left to route
  authoring (waypoints in clear space) for now; obstacle avoidance is later polish.
- **Cargo dock-loops are M20.** M18 is patrol movement; wiring shuttles to run
  station→station with a dock at each end (using M19) is the traffic milestone.
- **Dormant patrols dead-reckon straight** (the open "dormant fidelity" decision) —
  a patrol far from the player drifts off its loop until re-promoted, then resumes.
  The `Degraded` policy's route-tick is the eventual fix.

## 5. Open questions

- **Ping-pong vs loop** for open (non-cyclic) routes — `patrol_loop=false` clamps
  at the last waypoint today; a there-and-back mode is easy to add.
- **Separation vs. formation** — pure repulsion scatters; escorts/convoys that
  hold formation are a later behavior.
