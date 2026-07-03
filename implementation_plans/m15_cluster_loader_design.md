# M15 — Cluster Descriptor + Loader + Bootstrap

**Campaign milestone 2 of 7. DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M14 (the sim bubble). Turns the synthetic test records from M14 into
an *authored* home cluster, and makes it launchable from the menu.

**Shipped:** `cluster_def.gd`, `cluster_loader.gd`, `cluster_validator.gd`,
`home_cluster.gd`; `ClusterManager` self-tick (`viewpoint_node` + `_physics_process`);
`main.gd` GameMode fork + programmatic Campaign button + `_bootstrap_campaign`.
Acceptance `test_cluster_loader.gd` green (home cluster validates clean, broken
fixture trips each rule, loader populates, bootstrap promotes the adjacent hub /
leaves a distant one dormant); `test_cluster_bubble` still green after the
manager change.

**Fixed alongside M15 (pre-existing, also affected the sandbox):** promoting a
station had exposed three latent station bugs — laser PD lacking `base_em_emission`/
`em_pulse` (`laser_behavior.gd:69`), search-dish sensors lacking `timer`
(`ship.gd:1029`), and the station AI leaves calling an undefined `apply_rcs_input`.
Each aborted the station's `_physics_process`/AI tick via the CLAUDE.md missing-key
trap, leaving stations inert. Fixed in `ship.gd`: the `_ready` scratch-field
normalization now defaults the sensor/laser fields, and `apply_rcs_input` is
implemented as an omnidirectional RCS command integrated in `_physics_process`
(stations have no engines, so RCS is their only thrust for drift-arrest/heading).
Verified: `test_cluster_loader` runs clean (zero script errors) and the ship-physics
regression suite (`test_point_defense`, `test_ai_duel`, `test_classifiers_e2e`,
`test_signature_bleed`, `test_component_states`, `test_volley_metering`,
`test_ship_designs`) stays green.

**Goal:** the world becomes data. Author a cluster as a `ClusterDef` (bounds +
placed entities + beacon graph + player start), load it into a `ClusterManager`,
and validate it is well-formed with a `ClusterValidator` in the exact mold of
`ship_design_validator.gd`. Then wire the menu `GameMode` fork so **Campaign**
boots the home cluster while **Sandbox** is untouched.

## 1. The M15 / M16 boundary (so scope doesn't bleed)

M15 is the **data layer + loader + validator + bootstrap**. It places entities
that already have hulls — stations (`medium_station.gd`, `small_station.gd`),
beacons (`buoy.gd`), individual asteroids — as point records, and stands up the
routing-graph *data*. It does **not** add new entity types or behavior.

M16 is **static content enrichment**: the new wormhole entity, procedural
asteroid *fields* (a field descriptor → many asteroids, live only when the bubble
overlaps), and the beacon *lit-zone* / road-spacing semantics. So M15's validator
checks what it can already check (ids, bounds, station overlap, edge integrity,
graph connectivity); M16 extends it with field + road-lit checks.

## 2. The pieces

- **`ClusterDef`** (`cluster_def.gd`, RefCounted) — the authored description:
  `name`, `bounds: Rect2`, `player_start: Vector2`, `entities: Array` of dicts
  `{id, name, hull:Script, kind, pos, iff_tags, is_static, behavior}`, and
  `beacon_edges: Array` of `[id, id]`. Pure data, project-style (a ship is a
  `.gd` of dicts; a cluster is the same, one level up).
- **`HomeCluster`** (`home_cluster.gd`) — `static build() -> ClusterDef`
  constructing the Sovereign Drift: 3 medium-station hubs, 3 small-station mining
  outposts, a 4-beacon road linking two hubs (edges chained), a handful of sample
  asteroids by an outpost, and a `player_start` next to a hub. (Wormhole + real
  asteroid fields are M16.)
- **`ClusterLoader`** (`cluster_loader.gd`) — `static load_into(def, manager)`:
  each entity dict → a `ClusterEntity` record → `manager.add_record`. No physics;
  the policy decides what goes live.
- **`ClusterValidator`** (`cluster_validator.gd`) — `static validate(def) ->
  {ok, violations}`, `ok` false iff any error-severity violation (warnings don't
  block), mirroring `ShipDesignValidator`. Checks: unique ids (error), in-bounds
  (error), station non-overlap (error), beacon edges reference real beacons
  (error), beacon graph connected (warning).
- **`ClusterManager` self-tick** — add `viewpoint_node` + a `_physics_process`
  that, when set, drives `viewpoint = node.position; tick(delta)` each frame. Null
  in tests (they drive `tick` manually), the player ship in the live game.
- **Menu / bootstrap fork** (`main.gd`) — `enum GameMode { SANDBOX, CAMPAIGN }`
  (default SANDBOX); a programmatically-added **Campaign** button; a branch in
  `_on_connection_established` → `_bootstrap_campaign()` which loads the home
  cluster, spawns the player at `player_start`, points the manager's viewpoint at
  the player, and ticks. Sandbox path is branched around, not refactored. Live
  bodies parent to `main` (where sandbox ships already live) so rendering/behavior
  is identical.

## 3. Scope (phases)

- **M15a — Descriptor + loader.** `ClusterDef`, `ClusterLoader`; records land in a
  manager with correct kind/pos/iff.
- **M15b — Validator.** `ClusterValidator`; the home cluster validates clean; a
  deliberately-broken fixture trips each rule.
- **M15c — Home cluster.** `HomeCluster.build()`; the authored map, validated.
- **M15d — Bootstrap + menu fork.** `GameMode`, Campaign button, self-ticking
  manager, `_bootstrap_campaign`. Sandbox unaffected.

## 4. Validation

- **Headless (`test_cluster_loader.gd`):** validator clean on the home cluster
  (warnings printed, zero errors); a broken fixture trips each error rule;
  `load_into` yields the right record count + kind histogram; and the **bootstrap
  logic** — set viewpoint to `player_start`, tick, assert the adjacent hub goes
  live and a distant hub stays dormant (this is `_bootstrap_campaign` minus the
  menu button, so the load→place→promote path is proven without needing UI).
- **Regression:** re-run `test_cluster_bubble` after the `ClusterManager`
  self-tick change; confirm M14 still green.
- **Manual smoke (not headless-able):** launch, click **Campaign**, confirm the
  home hub is there and flying toward the next hub promotes/demotes entities. The
  menu button + render can't be asserted headlessly — this is the eyeball check
  §5 of the design doc calls for.

## 5. Risks & gotchas

- **`.filter()` needs `var x: Array = ...`** (inference trap) — used in the
  validator.
- **`main.gd` is the one non-headless-testable change.** Keep `_bootstrap_campaign`
  thin (it just calls the tested loader) so the untested surface is glue only.
- **Live-body parent.** Parent live entities to `main` (Node2D), not the manager
  Node, so transforms/rendering match sandbox ships exactly.
- **Player is the viewpoint and must never demote** — it's spawned as a normal
  ship (not a cluster record), so the manager never manages it. Good.

## 6. Open questions

- **Campaign starting hull:** reuse `ShipSelect` (default) vs. narrative-fixed.
- **Beacon road spacing:** the home road is placed ~evenly for now; the real
  spacing-vs-lit-coverage tuning is an M16 decision (road-lit validator check).
- **Manager tick cadence:** self-tick every physics frame; revisit if the
  reconcile shows up in a profile at full cluster population (M20).
