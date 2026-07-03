# M17 — Nav Computer + Beacon Routing (traversal)

**Campaign milestone 4 of 7 (built last). DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M16 (beacons exist). The player-facing traversal layer: pick a *named*
destination and autopilot routes over the lit beacon graph, direct-heading in the
dark. Also makes the wormhole a route-able destination.

**Shipped:** `NavComputer` (`destinations` + beacon-graph `route` with BFS,
lit/dark/short-hop/severed-edge handling); `NavAutopilot` (flies a route,
disengages + arrests on arrival); campaign wiring in `main.gd` (`_bootstrap_campaign`
stashes the def + grows a player autopilot; `nav_destinations()` / `set_nav_destination()`
hooks for the picker). Acceptance: `test_nav` (routing: on-road chain, severed→direct,
short-hop→direct, dark→direct final leg, named destinations) and `test_nav_autopilot`
(compute a route then actually fly it to the depot, disengage on arrival) green;
`test_campaign_bootstrap` extended to drive the real `main.set_nav_destination` and
confirm the player autopilot engages with a route. The destination-picker **UI**
(dropdown + engage/disengage, manual-input disengage) remains the manual-smoke
integration layer on these hooks.

## 1. The pieces

- **`NavComputer`** (`scripts/nav/nav_computer.gd`, static) — the routing brain,
  working off a `ClusterDef`:
  - `destinations(def)` → named nav targets (stations, beacons, wormhole) with
    positions, for the player to choose from.
  - `route(def, start, dest)` → an ordered list of world-space waypoints ending at
    `dest`. **On the road:** BFS over the beacon graph from the beacon nearest the
    start to the beacon nearest the destination, so you travel the lit chain.
    **In the dark:** a direct `[dest]` when there are no beacons, when the graph is
    *disconnected* (a sabotaged beacon severs an edge → forces manual transit — the
    Phase-2 mechanic falls straight out of this), or for a short hop where the
    destination is nearer than the road entrance. An off-graph destination (the
    wormhole) gets a beacon path as far as it reaches, then a direct final leg.
- **`NavAutopilot`** (`scripts/nav/nav_autopilot.gd`, a Node on a ship) — flies a
  route: lead-pursuit cruise to each waypoint, advance on arrival, and on reaching
  the destination **disengage** and arrest (hand back to the pilot). Reuses the
  exact `apply_control_input` surface — no new movement code.
- **Campaign wiring** (`main.gd`) — `_bootstrap_campaign` stashes the `ClusterDef`
  on the manager and grows a `NavAutopilot` on the player; `set_nav_destination(name)`
  looks the name up, routes from the player's position, and engages the autopilot.
  `nav_destinations()` feeds a picker.

## 2. Coordinate model (the "are we just using X/Y?" answer, realized)

Internally everything is cluster-local X/Y. The player never types coordinates:
they pick a **named** destination; `NavComputer` turns name → position → a
beacon-graph route. The beacon network *is* the routing graph — this is where the
lit road stops being flavor and becomes pathfinding.

## 3. Validation

- **`test_nav.gd`** (sync) — `destinations` lists the named targets; a start→far
  route travels the beacon chain (waypoints are the beacons, ending at dest); a
  **severed edge** collapses the route to direct; a **short hop** goes direct; an
  **off-graph** (dark) destination ends with a direct final leg, not a beacon.
- **`test_nav_autopilot.gd`** (async) — a ship handed a `NavComputer.route` flies
  it to a station and the autopilot disengages on arrival. End-to-end: compute a
  route, then actually fly it.

## 4. Scope / boundary

- **The destination-picker UI** (a dropdown + engage/disengage, and manual helm
  input disengaging autopilot) is the manual-smoke integration layer, wired like
  the menu was — `set_nav_destination` / `nav_destinations` are the hooks. The
  routing + flying are fully headless-tested.
- **BFS (fewest-hops)**, not distance-weighted Dijkstra — correct for the home
  chain; distance weighting is a drop-in refinement if graphs branch.
- **Lit = graph-connected** for now; a richer "beacon powered/alive" gate (so a
  destroyed-but-present beacon still severs the road) layers on later.

## 5. Open questions

- **Re-route on the fly:** recompute when a beacon dies mid-transit vs. only at
  engage. Engage-time for now.
- **Autopilot vs. hazards:** the route follows beacons/positions, not obstacle
  fields — same authoring assumption as patrols (M18).
