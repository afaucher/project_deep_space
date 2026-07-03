# M14 — Cluster Sim Bubble (physics LOD + dormant records)

**Campaign milestone 1 of 7. DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
This is the foundation the other six campaign milestones lean on — build it to
the contract or they inherit a rewrite.

**Shipped:** `scripts/cluster/cluster_entity.gd` (the authoritative record),
`liveness_policy.gd` (bubble / full-sim / degraded, one configurable object),
`cluster_manager.gd` (promote/demote + dead-reckon + reconcile). Acceptance:
`scripts/tests/test_cluster_bubble.gd` green — momentum survives a dormancy
round-trip, bubble hysteresis holds, live-count stays bounded and independent of
total N at fixed density (the cost proof), and a body at ±500k simulates finite.
The `ROUTE_TICK` tier and the in-game Campaign(dev) smoke-entry are deferred to
M15 (built against the real bootstrap rather than a throwaway).

**Goal:** decouple *map size* from *sim cost*. A cluster holds hundreds of
entities spread across a ±500k arena; only the neighborhood of the player's
viewpoint is ever a live physics scene. Everything else is a cheap record that
dead-reckons forward with no `RigidBody2D`, no AI, no sensor fusion. Prove the
live entity count — and therefore the O(N²) per-frame fusion cost in
`ship.gd::_physics_process` — stays **bounded regardless of total cluster size.**

Not in scope: the cluster *data format* / loader (that's M15), any new content
(wormhole, fields, traffic). M14 stands up the machinery and exercises it with
synthetic records in a test harness.

## 1. Why this first, and the one hard requirement

The sim ceiling isn't float precision, it's the fusion sweep: `_physics_process`
correlates contacts every frame, ~O(N²) across live entities, and it's already
the heaviest per-frame cost. If the whole cluster were live, a populated home
cluster would tank the frame. So liveness must be gated — and gated behind a
**swappable policy**, because the decision (start with a bubble; keep full-sim
and degraded modes reachable later, per the resolved decision in
[campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md) §1) means
the *which-is-live* rule cannot be hardcoded into the promotion plumbing.

The hard requirement, stated once: **a dormant record is the authoritative state
of an entity; going live *attaches* a physics body to that record and going
dormant *detaches* and writes state back.** Promotion/demotion is attach/detach
on a shared record. Get this contract right and `FullSim` / `Degraded` are later
config; get it wrong and they're a rewrite.

## 2. The pieces

### `ClusterEntity` — the authoritative record
A `RefCounted` (not a Node — dormant records must not cost the scene tree). Holds
everything needed to (a) dead-reckon while dormant and (b) reconstruct a live
body on demand:

- identity: `id`, `hull_script` (the `res://scripts/ships/*.gd` to instantiate),
  `iff_tags`, `kind` (`STATION | ASTEROID | BEACON | TRAFFIC | WORMHOLE | PLAYER`),
  `is_static` (stations/beacons/wormhole never move → skip dead-reckon).
- kinematics (authoritative when dormant, synced from the body when live):
  `pos: Vector2`, `vel: Vector2`, `rot: float`, `ang_vel: float`.
- `live_node` — the instantiated body when live, else `null`.
- `behavior` — opaque config passed to the AI on promote (route list for traffic,
  etc.). Unused by M14's movers; carried now so M17/M20 don't reshape the record.

### `ClusterManager` — the promote/demote engine
A new `Node` (`scripts/cluster/cluster_manager.gd`) that owns all records and,
each tick, reconciles liveness against a **viewpoint** (the player ship's
position for now; abstract it so a free camera can drive it later).

- `promote(rec)`: `rec.hull_script.new()`; set `position/rotation` **then** add as
  child **then** set `linear_velocity/angular_velocity` (Godot resets body state
  on tree-enter / `_ready` normalization — set velocity *after* `add_child` or it
  is clobbered; see §5). Attach the AI tree, wire `iff_tags`/`owner_id`, store
  `live_node`.
- `demote(rec)`: read `position/rotation/linear_velocity/angular_velocity` back
  into the record **immediately**, null-out `live_node`, then `queue_free()` the
  node. Read-back-before-free is mandatory — `queue_free` is deferred, so the
  record must become the source of truth the same frame or the manager double-counts.
- `tick(dt)`: for each dormant mover (`!is_static`), `rec.pos += rec.vel * dt`;
  then run the liveness policy over every record vs. the viewpoint and
  promote/demote the deltas. Live bodies are physics-authoritative — no
  dead-reckon while live.

### `LivenessPolicy` — the swappable rule
Interface: `classify(rec, viewpoint) -> int` returning `LIVE | ROUTE_TICK |
DEAD_RECKON`. M14 ships:

- **`BubblePolicy(promote_r, demote_r)`** — `LIVE` inside `promote_r`, stays live
  until outside `demote_r` (`demote_r > promote_r` → **hysteresis**, no
  boundary thrash). Everything else `DEAD_RECKON`. This is the default.
- **`FullSimPolicy`** — always `LIVE`. Viable only for small clusters / the
  benchmark harness; the "run the full sim later" escape hatch, already wired.
- **`DegradedPolicy(near_r, far_r)`** — `LIVE` inside `near_r`, `ROUTE_TICK` in
  the mid-ring, `DEAD_RECKON` beyond. Stub in M14 (treats `ROUTE_TICK` as
  `DEAD_RECKON`); the mid-ring route-tick is the M20 traffic-fidelity upgrade and
  is the same lever as the "dormant fidelity" open decision.

Which policy is live comes from config (a `DebugSettings` knob +
`ClusterManager` default) so switching is one line, per the contract.

## 3. Scope (phases)

- **M14a — Record + promote/demote round-trip. DONE.** `ClusterEntity`,
  `ClusterManager` with `promote`/`demote`, exact state round-trip. A record
  promotes to a live body whose `pos/vel/rot/ang_vel` match, demotes with the
  record updated and the node freed, and a promote→demote→promote cycle
  **preserves momentum** (the ship keeps its velocity across a dormancy
  round-trip). Test phase A.
- **M14b — Liveness policy + bubble. DONE.** The `LivenessPolicy` (one
  configurable object: bubble with hysteresis, full-sim, degraded — the latter
  `ROUTE_TICK` tier stubbed as dead-reckon). `ClusterManager.tick` drives
  promote/demote off the policy against a viewpoint. Only in-band records go
  live, and an entity parked between `promote_r` and `demote_r` does **not**
  thrash. Test phase B.
- **M14c — Dormant dead-reckon + cost proof. DONE.** Dormant movers advance by
  `vel*dt`; the acceptance benchmark. Verified: (1) seeding 40 vs 400 records at
  fixed density and sweeping the viewpoint edge-to-edge keeps live-count bounded
  **and** ≈equal across the 10× size difference (fusion cost, ~live², does not
  scale with total records); (2) a body promoted at ±500k coasts with finite
  physics — the float32 smoke-check. Test phases C + D.

Order was forced: a → b → c.

## 4. Integration & tests

- **Integration is minimal in M14.** Add `ClusterManager` alongside `main.gd`'s
  host path but keep the existing sandbox spawn working — for now the manager is
  exercised by a test harness that seeds synthetic records, not by rewiring the
  live sandbox (that lands with the M15 loader). The F-key sandbox spawns stay as
  they are; M15 folds them into "add a record + force-live."
- **Test:** `scripts/tests/test_cluster_bubble.gd`, run headless via
  `--run-test test_cluster_bubble` (per CLAUDE.md — never `--check-only`; emit
  `>>> [TEST PASSED] test_cluster_bubble <<<`). Cases map to the phases:
  round-trip momentum (a), bubble membership + hysteresis (b), bounded-live-count
  under a full-arena sweep + ±500k physics smoke (c). Use explicit
  `var x: Array = ...` on any `.filter()`/`.map()` result (GDScript inference trap).

## 5. Risks & gotchas (from this codebase)

- **`RigidBody2D` state ordering on promote.** Setting `linear_velocity` before
  `add_child` (or before `_ready` runs its normalization) gets clobbered. Set
  transform pre-add, velocities post-add; assert the round-trip in M14a so a
  regression here fails loudly.
- **`queue_free` is deferred.** Read state back into the record and mark it
  dormant *before* freeing, or the manager sees a ghost live node for a frame.
- **Hysteresis band vs. speed.** A fast hull can cross a thin band in one frame.
  Size `demote_r - promote_r` comfortably above `max_speed * dt` (bubble radii
  are tens of k; ship speeds are hundreds/sec — ample, but assert it).
- **The player is always live** and is the default viewpoint; never demote it.
- **Dormant ≠ observable.** A dormant entity is not a sensor contact and grants no
  datalink — correct and intended (you can't sense past ~30k anyway). A live ship
  near the bubble edge simply won't see dormant neighbors; note it, don't fix it.
- **Straight-line dead-reckon drifts movers off curved routes.** Fine for M14
  (the "dormant fidelity" open decision defaults to accepting drift until the
  `DegradedPolicy` route-tick lands). The record already carries `behavior` so
  that upgrade doesn't reshape it.

## 6. Open questions

- **Viewpoint source:** player-ship position (simple, what M14 uses) vs. a
  camera/free-look that can roam ahead of the hull. Abstract it; default to the
  ship.
- **Tick cadence:** run the liveness reconcile every physics frame vs. every N
  frames (promote/demote is cheap but not free at hundreds of records). Default
  every frame; revisit if the reconcile itself shows up in a profile.
- **Bubble radius:** tie to max sensor range (~30k) plus a margin so entities are
  live slightly before they become observable (no pop-in on the sensor plot), vs.
  a flat tuned value. Recommendation: `~1.5× max sensor range` as the promote
  radius, demote at `~2×`.
