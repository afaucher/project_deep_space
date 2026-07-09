# M38 -- Angle-Accurate Signatures (Radar Cross-Section + Active-Sensor EM)

Status: SHIPPED 2026-07-09.

## Shipped notes / friction found during independent verification

- **Cache bypass, fixed before commit**: the first implementation pass had
  `RadarCrossSection._outer_vertices` call `ShipSilhouette.compute(components)`
  (the uncached geometry function) instead of `ShipSilhouette.loops_for(ship)`
  (its own per-class cache). That meant every one of the 72 bucket
  cache-misses per ship class re-ran the expensive `Geometry2D.merge_polygons`
  union from scratch -- exactly the cost this file's own cache exists to avoid,
  just spread across 72 calls instead of every call. Fixed by routing through
  `ShipSilhouette.loops_for(ship)` whenever a `ship` is available (the
  cache-key param already threaded `ship` through `compute()` for the AABB
  fallback, just wasn't using it for the vertex lookup). The pure-fixture unit
  test path (`RadarCrossSection.compute(comps, angle)`, no `ship`) still falls
  back to the uncached `ShipSilhouette.compute()`, since there's no ship class
  to key a cache off.
- **Pre-existing bug surfaced by more accurate classification, fixed alongside
  this milestone (not introduced by it)**: `test_ai_duel` went from a clean
  3/3-win pass to 3/3 draws once M38 landed. Root cause, confirmed via
  `git blame` (code from 2026-06-20/24/25, well before this session): reactor
  overheat damage (`ship.gd`, the `current_heat >= max_heat` block) drains
  reactor `health` directly instead of routing through `take_damage()`, so it
  never hit `take_damage()`'s own `is_sys_destroyed("reactor") -> hulk()`
  death check. A reactor cooked to 0 health this way became a "zombie hulk" --
  `is_dead` stayed `false`, but `em_signature` genuinely dropped to 0 once
  nothing was powered, so `classify_contact` (correctly, by design) read it as
  WRECKAGE and nothing would re-target it, stalling the fight to a draw at the
  frame cap. More angle-accurate cross-section/EM changed this particular
  fixed-seed duel's combat timing enough to reach the overheat threshold before
  the fight would otherwise resolve -- the bug was always there, M38 just
  changed the odds of hitting it in this one scenario. Fixed by adding the same
  death check after the overheat-damage loop, mirroring `take_damage()`'s
  check exactly. Verified: baseline (pre-M38) 3/3 win without the fix, M38
  without the fix 3/3 draw, M38 with the fix 3/3 win again -- confirmed via
  direct `git stash`/re-run, not just the subagent's report.
- Full `build.ps1` suite (every test, all ~65) passes clean with both fixes in
  place.
- **Follow-up (2026-07-09): cache-miss now precomputes the whole class in one
  pass.** The initial cache still filled one bucket at a time -- a class's
  first 72 real sensor-sweep queries (spread across however many frames it
  took different bearings to come up) each triggered their own miss, even
  though `ShipSilhouette.loops_for`'s own cache meant the expensive union was
  already paid for after the very first one. `cross_section_at_angle` now
  calls `_warm_class` on the first miss, which fetches the class's outer
  vertices once and projects all 72 buckets in the same pass -- a class hits
  the miss path at most once, ever, and every other bucket (even ones never
  directly queried yet) is already a hit. Re-verified against the full
  regression set above.

Closes the gap identified while auditing `design_ideas/angle_accurate_cross_sections.md`
against the current code: `cross_section` is still a flat scalar (never implemented),
and `Utils.get_directional_em` (the directional EM math shipped alongside M2/the
sensor-fusion work) only ever runs on the `passive_em` sensor path -- active
sensors (`omni_search`, `dir_search`, `omni_pd`, `collision`) report a target's raw,
un-filtered `em_signature` total regardless of aspect.

Two independent fixes, sharing one call site (`ship.gd`'s `_run_sensor_sweep`):

1. **Cross-section becomes angle-accurate** for active-sensor detections (radar
   reflectivity -- how much of *your own* sensor's signal bounces back, a function
   of the target's silhouette as presented to you).
2. **EM gets direction-weighted on active sensors too** (facing matters even
   against a radar lock), but keeps active detection distance-independent --
   confirmed with the user: "No falloff (yet), just directional" for active. Only
   `passive_em` keeps the existing distance-falloff term.

## 1. Cross-section: algorithm and cost

### What "angle-accurate" means here
Not just the doc's simplest form (project the AABB). Reuse the real per-component
union silhouette M26 already built and caches per class
(`ShipSilhouette.loops_for`, `scripts/components/ship_silhouette.gd`) so an
asymmetric hull (a wing, a sensor mast offset to one side) actually shows a
different cross-section at different aspects, not just a bounding-box
approximation. This is a strict superset of the doc's proposal, built on
machinery that already exists and is already cached per ship class.

### The math
Given the target's outer silhouette loop(s) (ship-local space, holes excluded --
a hole can never extend the silhouette's extent, so only outer rings matter for
projection) and a bearing `theta` (ship-local, target -> observer):

- Projection axis = the line *perpendicular* to the line of sight:
  `axis = Vector2.RIGHT.rotated(theta + PI/2)`.
- Cross-section = `max(dot(v, axis) for v in outer_vertices) - min(dot(v, axis) for v in outer_vertices)`.
- This is the same "shadow width" projection the design doc specifies, just run
  against the real hull footprint instead of only the AABB corners.

### Cost, and why we cache
A per-vertex O(N) projection (N = outer-loop vertex count, typically 10-40 for
catalog hulls) is cheap in isolation, but `_run_sensor_sweep` runs per sensor per
ship, gated only by each sensor's own `refresh_interval` (`omni_pd` refreshes
every 0.15s, `collision` every 0.1s) and iterates every contact in range
(`intersect_shape(..., 128)`). In a multi-ship scenario that's O(ships x sensors x
contacts x N) worth of trig+dot-product work every refresh tick -- non-trivial
at tactical-sim scale, even though any single call is cheap.

Fix: cache by **rounded angle bucket per ship class**, same shape as
`ShipSilhouette._cache` (keyed by script `resource_path`, since geometry is a
pure function of the authored design -- every instance of a class shares it).

- Bucket width: 5 degrees (`PI / 36`), 72 buckets covering the full circle --
  hulls aren't guaranteed fore/aft or port/starboard symmetric (see the defence
  pod's ring), so the cache must cover all 360 degrees, not just a quarter-circle
  mirrored.
- Cache key: `"<script_resource_path>|<bucket_index>"` -> `float` (extent).
- On a cache miss: compute once via the projection above, store, return. Every
  subsequent query for that class + bucket is an O(1) dict lookup -- the
  per-tick cost collapses to "round an angle, hash a string" for every ship
  after the first sweep touches each of its 72 buckets (which happens within
  a few seconds of normal maneuvering; a worst case of 72 cache-miss computations
  per class, ever, not per instance).
- `signature_multiplier` (the existing per-ship tunable knob) is applied on top
  of the cached raw extent, not baked into the cache, so the cache stays a pure
  function of hull geometry only.

### Where it plugs in
New static helper, `RadarCrossSection.cross_section_at_angle(ship, angle_from_target) -> float`
in a new `scripts/components/radar_cross_section.gd` (sibling to
`ship_silhouette.gd`, same "pure static + per-class cache" shape -- not folded
into `ShipSilhouette` itself, since that file's contract is "return loops," not
"return a derived scalar," and mixing concerns there would make the outline
renderer and the sensor-stat cache invalidate/change together for no reason).

- Guard: only called when `collider.get("ship_components") != null` (mirrors
  `ShipSilhouette.loops_for`'s own null-check). Asteroids, mines, and anything
  else that implements `get_signature()` without `ship_components` keeps
  whatever fixed `cross_section` its own script reports (e.g. `asteroid.gd`'s
  `collision_radius * 2.0` diameter) -- untouched.
- Wiring in `ship.gd::_run_sensor_sweep`: today `angle` (bearing sensor->target,
  used for binning) and, only inside the `passive_em` branch, `angle_from_target`
  (bearing target->sensor, used by `Utils.get_directional_em`) are computed
  separately with the *same* underlying trig, just negated
  (`(collider.position - origin).angle()` vs `(origin - collider.position).angle()`).
  Fold to one computation: `angle = (collider.position - origin).angle()`,
  `angle_from_target = wrapf(angle + PI, -PI, PI)`, hoisted above the
  sensor-type branch so both the EM and cross-section overrides can use it.
- For any sensor type that is *not* `passive_em` (i.e. all four active kinds):
  `sig["cross_section"] = RadarCrossSection.cross_section_at_angle(collider, local_angle_from_target) * collider.signature_multiplier`.
  `passive_em` bins already `sig.erase("cross_section")` immediately after (line
  ~1741 today) -- skip computing it at all on that path rather than computing
  then discarding.
- The `cross_section` *property* on `Ship` (`ship.gd:782`) is untouched --
  still the flat `min(aabb.size.x, aabb.size.y) * signature_multiplier`. It
  remains the right value for "my own ship's nominal RCS stat" displays with no
  external observer bearing to compute against (weapons_panel, spider_chart,
  contacts_panel's self-row, if any) and is also the safe fallback whenever a
  caller has no bearing at all.

### Known risk to verify once built
`test_classify_ships.gd` asserts every catalog ship's `cross_section >=
ORDNANCE_CS_THRESHOLD` at whatever fixed aspect that test's fixture uses. The
new angle-dependent minimum (narrowest projected silhouette width) could, for a
non-rectangular hull, come in *below* the old flat `min(aabb.size.x,
aabb.size.y)` at some aspects -- the old value was the AABB's beam, not
necessarily the true silhouette's narrowest projection. Needs a sweep-across-all-
aspects check added to that test (or a new one) as part of implementation, not
left to be caught by accident.

## 2. EM: extend directional weighting to active sensors, keep distance falloff passive-only

Per the user's explicit call: active sensors get the *directional* term, not the
distance term.

```gdscript
# angle_from_target computed once above (shared with cross-section, see 1.)
var em_power = Utils.get_directional_em(sig, angle_from_target)  # now unconditional

if sensor.get("sensor_type", "active") == "passive_em":
    var received_em = em_power * (EM_FALLOFF_REFERENCE_DISTANCE / max(EM_FALLOFF_REFERENCE_DISTANCE, dist))
    if received_em < PASSIVE_EM_NOISE_FLOOR:
        continue
    sig["em_noise"] = received_em
else:
    sig["em_noise"] = em_power
```

- `Utils.get_directional_em` itself needs no changes -- it's already a pure
  function of `(sig, angle_from_target)` with no sensor-type awareness, so
  reusing it for both paths is a call-site change only.
- `PASSIVE_EM_NOISE_FLOOR` gating and the distance-falloff multiply stay
  exclusively inside the `passive_em` branch -- an active sensor that already
  detected the target physically (range/arc/LOS via `intersect_shape` +
  `intersect_ray`) still always reports *some* EM number, just now direction-
  weighted instead of the flat total.
- Cost: `get_directional_em` is O(emitters on the ship, typically 3-6) with no
  caching needed -- same as it already costs on the passive path today, just now
  also paid on the (more frequent, e.g. `omni_pd` at 0.15s) active paths. No
  caching required; this is not the expensive part.

### Existing test impact
`test_component_states.gd`'s directional-EM unit tests
(`_received_em_power`/`_total_received_em`, lines ~301-385) test `Utils`
directly and are unaffected. `test_signature_bleed.gd` and any test asserting
an exact active-sensor `em_noise` number end-to-end will need re-checking --
those numbers change from "flat `em_signature` total" to "direction-weighted"
now that the override is unconditional.

## Implementation order
1. `Utils`/`RadarCrossSection` additions + their own unit tests (pure, no Node
   deps -- same style as `test_component_states.gd`'s `_received_em_power`
   table).
2. `ship.gd::_run_sensor_sweep` wiring (angle hoist, cross-section override on
   active paths, EM override unconditional).
3. Re-run full regression, paying specific attention to
   `test_classify_ships.gd`, `test_classifiers.gd`, `test_classifiers_e2e.gd`,
   `test_signature_bleed.gd`, `test_component_states.gd` for any exact-value
   assertions that shift.
4. New test(s): cross-section-vs-angle sweep (bow/broadside/stern extents in
   the expected order for an asymmetric fixture hull), active-sensor EM now
   varies with facing (bow-on vs tail-on gives different reported `em_noise`
   for the same target at the same range).
