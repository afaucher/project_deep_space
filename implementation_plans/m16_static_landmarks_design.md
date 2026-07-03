# M16 — Static Landmarks (wormhole, asteroid fields, lit road)

**Campaign milestone 3 of 7. DONE (2026-07-03).** Parent: [campaign_spatial_model.md](../design_ideas/campaign_spatial_model.md).
Depends on M15 (cluster loader). Turns the navigable *skeleton* into a *place*:
the wormhole exists, asteroid fields are real (procedural, bubble-LOD'd), and the
beacon road is validated as continuously lit — and made longer.

**Shipped:** `scripts/wormhole.gd` (Node2D landmark + transit stub); `ClusterDef.asteroid_fields`
+ seeded field expansion in `ClusterLoader`; `ClusterValidator` field-bounds /
road-lit / outpost-on-field checks; `ClusterManager` `is RigidBody2D` guards on
promote/demote (landmarks are transform-only); `HomeCluster` reworked — a 7-beacon
road over ~204k (up from 4/~126k), three fields on the outposts, the Nexus wormhole
in dark space. Acceptance `test_static_landmarks.gd` green (home validates clean +
lit, fields expand deterministically inside radius/bounds, wormhole promotes/demotes
as a Node2D without error, road > 4 beacons; broken fixtures trip each rule);
`test_cluster_loader` (counts now derived from the def) and `test_cluster_bubble`
still green.

**Goal:** add the static content layer with no new behavior — just placed,
sensible, validated landmarks — and extend the validator to prove the map reads
right.

## 1. The pieces

- **Wormhole** (`scripts/wormhole.gd`, new) — the cluster's single exit to the
  Nexus. A `Node2D` landmark (not a physics hull): a placed, named marker with a
  `nav_radius` and an `attempt_transit()` **stub** (no destination cluster yet —
  actual transit is deferred, per the design doc). Placed in *dark space* away
  from the beacon road, per the fiction. Because it isn't a `RigidBody2D`, the
  manager must promote/demote it without touching velocity (see §2).
- **Asteroid fields** — `ClusterDef.asteroid_fields`, a list of
  `{center, radius, count, seed}` descriptors. `ClusterLoader` expands each into
  `count` individual `Asteroid` records via a **seeded** RNG (deterministic →
  testable), uniformly in the disk. The bubble does the LOD for free: a field's
  rocks only go live when the player is inside it. Replaces M15's hand-placed
  sample asteroids.
- **Longer, lit beacon road** — the home road grows from 4 beacons over ~126k to
  **7 beacons over ~204k** (Ironhold → Drift Market, ~25k spacing, well inside the
  50k comms range so zones overlap). Beacons carry a `comms_range` for the
  validator.
- **Validator extensions** (`cluster_validator.gd`):
  - *field in bounds* (error) — the field's disk AABB must sit inside cluster bounds.
  - *field non-empty* (error).
  - *road lit* (warning) — every beacon edge's endpoints within comms range so
    there's no dark gap mid-road. This is what validates the spacing decision.
  - *outpost on field* (warning) — each mining outpost (`role == "outpost"`)
    should sit within an asteroid field.

## 2. Manager change (small)

`ClusterEntity` promotion/demotion assumed a `RigidBody2D` (it set/read
`linear_velocity`/`angular_velocity`). Landmarks like the wormhole are `Node2D`.
Guard both: only touch velocity `if node is RigidBody2D`. Transform (`position`/
`rotation`) is fine for any `Node2D`. Re-run `test_cluster_bubble` after.

## 3. Validation (`test_static_landmarks.gd`)

- Home cluster validates clean: zero errors, and specifically **no** road-lit or
  outpost-off-field warnings (the road really is lit; outposts really are on
  fields).
- Broken fixtures trip: a field spilling out of bounds (error), a road edge
  longer than comms range (road-lit warning), an outpost off every field
  (warning).
- Loader expands fields: after load, `ASTEROID` record count == sum of field
  counts, and every expanded asteroid lies within its field's radius and inside
  bounds (determinism check — same seed, same layout).
- Wormhole promotes/demotes without error (the `Node2D` path through the manager
  — proves the §2 guard), and the record is kind `WORMHOLE`.
- Road length: assert the home road has **> 4 beacons** (the "make it longer"
  requirement, pinned as a regression).

## 4. Scope / boundary

- **No nav yet** — the wormhole is route-*able* (a placed, named entity) but the
  routing/autopilot that flies to it is M17. `attempt_transit` is a stub.
- **No field rendering / sensor puzzle** — the wormhole is a data landmark; a
  visual + sensor/transponder presence is later polish.
- **Fields are static** for now (no drift); drifting fields are a later option.

## 5. Open questions

- **Wormhole sensor/transponder presence:** should it read as a contact (big EM
  anomaly) or stay a pure nav landmark? Deferred; pure landmark for M16.
- **Field drift:** static vs. slow tumble. Static for M16 (deterministic, cheap);
  the record already carries `vel`/`is_static` if we want drift later.
- **Multiple roads / network:** the home road is a single chain. A hub-to-hub
  network (multiple legs sharing bridge beacons) is a later content pass.
