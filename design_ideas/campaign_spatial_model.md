# Campaign Spatial Model — the Home Cluster

Scoping doc for campaign mode's *space*. Not the narrative (that's
[background.md](background.md)) — this is the spatial/technical foundation the
narrative content will be placed into: how big the world is, how it's
represented, how ships navigate it, and what the Godot physics sim will and
won't tolerate.

Status: **breakdown + foundation**. Milestones get spun into
`implementation_plans/` as we tackle them in turn.

---

## The goal

Sandbox play happens in a ±15k box around the origin. The campaign's mechanics
(beacon roads at comms range, patrols, mining fields, a wormhole across dark
space from its nearest hub) need a *much* bigger arena. This doc defines the
home cluster: ~3 medium stations, a scattering of small mining outposts, placed
asteroid fields, at least one beacon road, light traffic, and a wormhole.

The first question is not "what goes where" — it's "how big can the world be
before the engine falls over," because that answer reshapes everything else.

---

## 1. The hard constraint: what the Godot sim tolerates

Ships (`ship.gd`) and asteroids (`asteroid.gd`) are **`RigidBody2D`** living at
**absolute world coordinates**, and Godot 4's 2D physics uses
**single-precision `float32`** for position. That caps usable world size:

| Distance from origin | float32 ulp (position granularity) |
|---|---|
| 100k | ~0.008 units |
| 500k | ~0.03 units |
| 1M | ~0.06 units |
| 4M | ~0.25 units |
| 8.4M (2^23) | ~1.0 unit |

Ships move at hundreds of units/sec; asteroids drift at tens. At ±500k, a 0.03u
granularity is invisible. Past a few million, position quantizes hard enough
that resting contacts jitter, slow drift stutters, and collision solving
degrades. **±500k is a free, safe budget; ±1M is fine; multi-million is where
it bites.**

Two more sim costs, independent of coordinates:

- **Body count.** Every asteroid is a `RigidBody2D` + `CircleShape2D`; every
  ship too. Godot 2D physics broadphase costs something per live body whether or
  not it's near the player. A "meaningful asteroid field" of hundreds of rocks,
  times several fields, is thousands of live bodies for regions the player
  cannot even see (sensor range ~30k).
- **Sensor fusion is O(contacts) per ship, per frame.** `ship.gd`'s
  `_physics_process` sweeps contacts every frame; globally that's ~O(N²) in live
  entities. This is already the heaviest per-frame cost in the game. It, more
  than float precision, is what caps how much can be *live* at once.

### The architectural response

Three rules fall out, and they happen to match the fiction exactly:

1. **One cluster is live at a time.** Clusters are "isolated by lightyears,"
   connected only through the wormhole → Nexus (an *instanced transition*, not a
   seam you fly across). So we never simulate two clusters at once. This bounds
   the world to a single cluster.

2. **A cluster is data; only a bubble around the player is physics.** The
   cluster is a *descriptor* — a list of placed entities (stations, outposts,
   beacons, asteroid fields, the wormhole) with cluster-local coordinates and a
   beacon graph. Entities within a **simulation radius** of the player's
   viewpoint are instantiated as live `RigidBody2D` + AI + fusion. Everything
   beyond it is a **dormant record**: position + velocity, dead-reckoned
   forward, no body, no fusion, no AI. The player can't sense past ~30k anyway,
   so nothing beyond the bubble is observable — dormancy is free, visually. This
   is the single most important piece to build and everything else leans on it.

   **The bubble is a swappable *liveness policy*, not a hardcoded radius.**
   (Decision: start with the bubble, but keep full-sim and degraded modes on the
   table.) Live and dormant entities share one representation — a dormant record
   is the authoritative state; going live *attaches* a physics body/AI to it and
   going dormant *detaches* and writes state back. Because promotion is
   attach/detach on a common record, the policy that decides *which* entities are
   live is pluggable: `Bubble(radius)` today; `FullSim` (everything live — only
   viable for small clusters / strong hardware) or `Degraded` (near = full,
   mid-ring = cheap route-tick, far = dead-reckon) later, as config, not a
   rewrite. Build the promote/demote plumbing to this contract from day one.

3. **Keep the cluster inside ±500k for v1.** Well within the safe budget, no
   floating-origin machinery needed. If a later cluster must be bigger, a
   floating-origin recenter (shift the world so the player sits near 0,0) is the
   escape hatch — **deferred**, not built now.

The bubble is the crux: it decouples "how big the map is" (data, unbounded-ish)
from "how much is simulated" (bounded, cheap). Author the whole cluster; pay
only for the neighborhood.

---

## 2. Coordinate & navigation model — "are we just using X/Y?"

**Under the hood: yes, X/Y in a cluster-local frame** (units ≈ meters, forward
+X, right +Y, per the ship component convention). That's the truth every system
already speaks — sensors report bearing+range, RCS thrusts along facing.

**Player-facing: no raw coordinates.** Nobody navigates by typing `(452000,
-88000)`. Nav is layered on *named references*:

- **Nav targets are known entities** — a station, a beacon, the wormhole, or any
  resolved contact. "Set course for Beacon 3," "dock at Ironhold," not a number
  pair.
- **The beacon road IS the routing graph.** Beacons at ~comms-range spacing form
  a connected graph whose edges are "lit" legs. Long-range autopilot is
  graph-routing over lit beacons: on the road you get computed, assisted travel
  (the fiction's "high street"); step off it and you fall back to a direct
  heading + dead-reckoning through the dark, steering manually around hazards.
  This makes the beacon network mechanically load-bearing, not just flavor —
  sabotaging a beacon (Phase 2) literally deletes a graph edge and forces manual
  transit.
- **Tactical layer stays bearing+range** relative to your hull, exactly as
  sensors already think.

So: internal truth is cluster-local X/Y; the player selects *named* destinations
and the nav computer routes over the beacon graph where lit, direct-heading
otherwise.

---

## 3. The cluster as data

A cluster is authored as a descriptor (a `.gd`/resource data file, in keeping
with the project's "everything is code-built data" pattern — ships are dicts,
spawns are catalog-driven). Rough shape:

```
ClusterDef:
  bounds:        Rect2 (must sit inside ±500k)
  stations:      [ {hull, cluster_pos, faction/iff, role} ... ]
  asteroid_fields: [ {center, radius, count, density} ... ]
  beacons:       [ {cluster_pos, id} ... ]
  beacon_edges:  [ [beacon_id, beacon_id] ... ]   # the routing graph
  wormhole:      {cluster_pos}
  traffic:       [ {hull, route:[nav_target ...], kind:patrol|cargo} ... ]
```

The **home cluster** (Sovereign Drift), first pass:

- **3 medium stations** — the trade/refinery hubs, spread across the cluster so
  legs between them are real travel (tens of k apart), connected by beacon roads.
- **A scatter of small stations** — mining outposts, each parked at the edge of
  an asteroid field.
- **Asteroid fields in set areas** — clustered, not the current uniform random;
  the mining outposts sit on them, and they double as cover / ambush terrain.
- **≥1 beacon road** — a chain of buoys linking two hubs at ~max-comms spacing.
- **1 wormhole** — near one hub but separated by a stretch of *dark space* (no
  beacons), per the fiction's "unmapped dark between the hub and the stargate."
- **Light traffic** — LAC patrols around hubs, one LAC running the beacon road,
  cargo shuttles bouncing between fixed station pairs.

---

## 4. Entities & subsystems to build (scope notes)

- **Physics-LOD bubble + dormant records** *(foundation)* — instantiate/free
  live bodies as the player's simulation radius sweeps the cluster; dead-reckon
  dormant entities. Everything below assumes this exists.

- **Cluster descriptor + loader** *(foundation)* — the data format above and the
  code that reads it, places dormant records, and hands them to the bubble.

- **Wormhole** *(new entity)* — doesn't exist yet. For v1 (single playable
  cluster) it's a static landmark: a fixed position, a nav-beacon/transponder
  signature so it's classifiable and route-able, and a transit-trigger stub.
  Actual inter-cluster travel is deferred until Cluster 2 exists.

- **Beacon road** — reuse/extend `buoy.gd` (already a static comms relay, range
  50k). A beacon = a graph node + a lit comms/nav zone. **Spacing is a tuning
  call** (see Open Decisions): endpoints "just touching" at 1× range leaves a
  mid-leg coverage gap; ~0.8× range gives continuous overlap.

- **Placed asteroid fields** — replace uniform-random spawn with field
  descriptors (center/radius/count/density), deterministically populated, and
  only instantiated live when the bubble overlaps the field.

- **Route/patrol AI** *(new behavior)* — the AI has no waypoint following today
  (only Engage/Idle/StationKeeping). Add a "follow route" leaf: an ordered list
  of nav targets, loop or ping-pong, built on `apply_control_input`. Slots into
  the tree as the idle-replacement (patrol when no hostile; existing Engage
  still preempts it). Drives LAC patrols and cargo runs alike.

- **Station docking** *(new subsystem, the hardest)* — autonomous approach +
  capture + hold + depart. Stations already carry `docking_port` components to
  use as dock points. **v1 = force-capture soft-dock** (decision): the berth is a
  capture *zone*; while a ship is inside it, the station applies a spring-damper
  force toward the berth pose (spring pulls to the berth position/orientation,
  damping arrests relative velocity), so an in-tolerance arrival is drawn in and
  held physically without a rigid joint. Once settled (low residual velocity), a
  load/unload timer runs, then the capture force releases and the ship departs
  under its own power. Comms handshake for docking instructions per
  [story_driven_comms.md]. Rigid joints/reparent deferred (the "hard-dock"
  path) — the force field gives the physical feel without the joint fiddliness.

- **Traffic wiring** — compose the above: LAC hub patrols (route = loop around a
  station), LAC beacon patrol (route = the beacon chain), cargo shuttles (route
  = a fixed station pair, with a dock/wait at each end). Not full mesh — each
  shuttle has one assigned lane.

---

## 5. Milestones — layers, dependencies, validation

Seven milestones (M14–M20), stacked as five feature layers. Each is its own
`implementation_plans/` doc when we reach it.

### The layers

- **Layer 0 — Substrate.** M14: the sim bubble. *How much is live.*
- **Layer 1 — World data.** M15: cluster descriptor + loader. *Where things are.*
- **Layer 2 — Static content.** M16: wormhole, asteroid fields, beacons. *What's
  in the world* (no behavior — just placed, sensible, navigable).
- **Layer 3 — Systems (three parallel tracks).** M17 nav/routing, M18 patrol AI,
  M19 docking. *What the content can do.* Mutually independent once Layer 2
  exists — schedulable in parallel.
- **Layer 4 — Living world.** M20: traffic wiring. *The world inhabited.* The join
  of all three Layer-3 tracks.

### Dependency DAG

```
M14 bubble ─> M15 loader ─> M16 landmarks ─┬─> M17 nav ──────┐
                                           ├─> M18 patrol ───┼─> M20 traffic
                                           └─> M19 docking ──┘
```

The chain M14→M15→M16 is forced and serial. M17/M18/M19 fan out from M16 and can
land in any order (or concurrently). M20 needs all three. One shared primitive
cuts across M17/M18: a **waypoint-follower** (steer through an ordered list via
`apply_control_input`). Extract it once — M18 wraps it in a behavior leaf +
combat preemption; M17 feeds it a path computed over the beacon graph. Agree its
signature before either track starts so they don't fork it.

### How validation scales with the layer

Fidelity of the test matches the altitude of the feature:

- **Layers 0–1 (data/logic)** → deterministic headless **unit tests**. Exact
  round-trips, exact membership.
- **Layer 2 (static content)** → a **`cluster_validator`** in the mold of
  `ship_design_validator.gd`: assert the *loaded world* is well-formed (in
  bounds, no station overlaps, beacon graph connected, outposts sit on fields,
  road actually lit end-to-end). Run over the authored home cluster exactly as
  `test_ship_designs` runs over the catalog. This is the single highest-leverage
  test asset for the campaign map.
- **Layer 3 (behavior)** → **bounded-time sim tests** (mold of
  `test_classifiers_e2e` / `test_ai_duel`): run the actor N seconds, assert it
  *makes progress* and *holds invariants* (reaches waypoints, settles at berth,
  reroutes when a beacon dies). **Run these under `FullSimPolicy`** so bubble
  churn can't perturb the behavior under test.
- **Bubble-transition (cross-cutting)** → a **separate** suite that deliberately
  forces dormancy round-trips mid-behavior and asserts seamless resume. This is
  the only place `BubblePolicy` is the system under test rather than the fixture.
- **Layer 4 (integration)** → a long **soak**: load the full cluster, run
  60–120s sim, assert emergent invariants (live-count bounded as traffic flows
  through the bubble, cargo completes dock→wait→depart→transit cycles, patrols
  loop, nothing NaNs / gets stuck / overlaps).

Headless proves correctness and invariants, **not game-feel**. Each phase also
gets a manual smoke checkpoint in the running sandbox — is the map legible on the
plot, does traffic read as alive — that no assertion can stand in for.

### Per-milestone validation

- **M14 bubble** — *depends: none.* Promote/demote round-trip preserves momentum;
  bubble membership + hysteresis (no boundary thrash); **cost proof** — sweep the
  viewpoint across a ±500k arena of many records, assert live-count bounded and
  fusion cost flat in total-record-count (must *measure*, not assume); ±500k
  physics smoke (no NaN).
- **M15 loader** — *depends: M14.* Descriptor → exact record set (counts, kinds,
  positions); the `cluster_validator` passes on the authored home cluster;
  load→promote round-trip yields the right live entities near the player.
- **M16 landmarks** — *depends: M15.* Each entity instantiates + classifies right
  (beacon reads as a nav/neutral contact not `UNIDENTIFIED`; wormhole is a
  route-able landmark; a field spawns its N asteroids only when the bubble
  overlaps); **road-lit check** — sample points along the beacon road, assert each
  sits inside some beacon's comms range (this is what validates the spacing
  decision).
- **M17 nav** — *depends: M16.* Graph routing picks the correct lit path on
  hand-built graphs incl. a severed edge; autopilot follows the chain when lit and
  falls back to direct-heading when dark; sabotage-a-beacon-mid-route flips the
  ship to manual. (FullSim.)
- **M18 patrol** — *depends: M16.* Ship visits waypoints in order and loops;
  a hostile preempts the patrol and it resumes when clear; LAC orbits a hub within
  a band. (FullSim, + one bubble-transition case: patrol survives a dormancy
  round-trip.)
- **M19 docking** — *depends: M16.* Shuttle enters the zone → spring-damper settles
  it at the berth at ~zero residual velocity within N sec → timer → releases →
  departs; bad-angle/too-fast approach stays stable (no phase-through, no
  explosion); no rigid joint created. (FullSim physics test.)
- **M20 traffic** — *depends: M17+M18+M19.* The Layer-4 soak above, plus: each
  cargo shuttle serves only its assigned lane (not full mesh); a shuttle that goes
  dormant mid-transit re-promotes near where dead-reckoning predicted (this is the
  empirical test of the "dormant fidelity" decision — too much drift is the signal
  to build `DegradedPolicy`'s route-tick).

---

## 6. Entry & session bootstrap — menu → campaign (sandbox preserved)

Today the menu (`main.tscn`: Host / Join / **Local Test** + a `ShipSelect`
dropdown) funnels every start through `_on_connection_established(is_host)`, which
hard-codes the sandbox bootstrap (`_spawn_asteroids` + `_spawn_player_ship` in a
±15k playground). Campaign needs a *different* bootstrap — load a cluster, stand
up the `ClusterManager`, place the player at a home station — without disturbing
sandbox.

**The fork is a game mode, chosen at the menu, branched at bootstrap:**

- **`enum GameMode { SANDBOX, CAMPAIGN }`** on `main`, default `SANDBOX` — every
  existing path stays byte-for-byte unchanged.
- **Menu:** add a **Campaign** button; rename **Local Test → Sandbox** (the M13c
  rename, folded in). Host/Join stay sandbox. Add the button *programmatically* in
  `_ready` (as `menu_compass` already is) to avoid headless-hostile `.tscn`
  surgery; each button sets `game_mode`, then routes through the same connection
  path.
- **Branch at bootstrap:** `_on_connection_established` splits on `game_mode` —
  `SANDBOX` → the current spawn (**untouched, only branched around**); `CAMPAIGN`
  → `_bootstrap_campaign()` (instantiate `ClusterManager`, load the home
  `ClusterDef`, place the player, hand it the records).

**Single-player only for v1.** The bubble is viewpoint-centric (one player → one
bubble). Co-op campaign means a union of bubbles + replicated dormant records — a
large, separate problem. Campaign routes like Local Test (offline host);
multiplayer stays sandbox. Co-op campaign is deferred (union-of-bubbles is the
extension point).

**It matures across milestones, doubling as each phase's manual smoke check (§5):**

- **M14:** a **Campaign (dev)** entry that bootstraps the *synthetic* bubble
  records from M14's harness — fly around, watch entities promote/demote live.
  This *is* M14's manual smoke checkpoint.
- **M15:** the button loads the real home `ClusterDef`; the dev stub retires.
- **M16/M20:** the same entry progressively fills with landmarks, then traffic —
  no further menu work.

Mode is chosen once at launch; switching modes = relaunch. No world-teardown /
return-to-menu path exists or is built now.

## 7. Decisions

**Resolved:**

- **Simulation model:** bubble + dormant records to start, but built to a
  swappable liveness policy so full-sim or degraded modes come later as config,
  not a rewrite (§1, rule 2).
- **World-size budget:** home cluster capped inside **±500k**; no floating
  origin for v1 (the escape hatch stays documented, unbuilt).
- **Docking:** **force-capture soft-dock** — a berth zone applies a spring-damper
  hold; no rigid joint (§4).

**Still open** (decide at the relevant milestone; defaults in **bold**):

- **Beacon spacing:** continuous overlap (**~0.8× comms range**) vs. endpoints
  touching at 1× (cheaper, mid-leg gap). Affects how "lit" a road really is.
- **Dormant fidelity:** do dormant ships dead-reckon in straight lines (cheap,
  can drift off-route) or tick a lightweight route-follower without physics
  (**accurate, more cost**)? The `Degraded` policy's mid-ring is exactly this
  cheap route-tick, so this and the liveness policy are the same lever. Matters
  for whether traffic stays on its lane while off-screen.
- **Campaign starting hull (M15):** fix the captain's opening ship narratively vs.
  reuse the menu's `ShipSelect` dropdown. Default: **reuse `ShipSelect`** for now;
  narrative-fix later.
