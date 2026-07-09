class_name RadarCrossSection

# M38 -- angle-accurate radar cross-section for active sensors.
# design_ideas/angle_accurate_cross_sections.md +
# implementation_plans/m38_angle_accurate_signatures_design.md
#
# How much of a ship's silhouette projects toward an observer at a given
# bearing ("shadow width" perpendicular to the line of sight), reusing the
# real per-component union silhouette M26 already built and caches per class
# (ShipSilhouette.loops_for) rather than just the AABB. Pure static geometry +
# a per-class cache; no Node deps -- same shape as ShipSilhouette itself.
#
# Kept separate from ShipSilhouette on purpose: that file's contract is
# "return loops" (feeds the outline renderer + collision hull); this one's
# contract is "return a derived scalar" (feeds the sensor model). Mixing them
# would make the outline renderer and the sensor-stat cache invalidate/change
# together for no reason.
#
# signature_multiplier is intentionally NOT applied here -- the cache must
# stay a pure function of hull geometry only. Callers multiply by
# ship.signature_multiplier themselves (see ship.gd::_run_sensor_sweep).

const ShipSilhouette = preload("res://scripts/components/ship_silhouette.gd")

const NUM_BUCKETS := 72
const BUCKET_WIDTH := PI / 36.0 # 5 degrees

# "<script_resource_path>|<bucket_index>" -> float (raw, unmultiplied extent)
static var _cache: Dictionary = {}

# Public entry point used by ship.gd. angle_from_target is a WORLD-frame
# bearing (target -> observer); this converts to the ship's local frame,
# buckets it, and serves/populates the per-class cache.
static func cross_section_at_angle(ship, angle_from_target: float) -> float:
	if ship.get("ship_components") == null:
		return 0.0

	var local_angle: float = wrapf(angle_from_target - ship.rotation, -PI, PI)
	var bucket: int = _bucket_index(local_angle)

	var script = ship.get_script()
	var key: String = "%s|%d" % [script.resource_path if script != null else "", bucket]
	if _cache.has(key):
		return _cache[key]

	var bucket_center: float = bucket * BUCKET_WIDTH
	var extent: float = compute(ship.get("ship_components"), bucket_center, ship)
	_cache[key] = extent
	return extent

static func _bucket_index(local_angle: float) -> int:
	var raw: int = int(round(local_angle / BUCKET_WIDTH))
	return ((raw % NUM_BUCKETS) + NUM_BUCKETS) % NUM_BUCKETS

# Pure geometry: extent of `components`' outer silhouette projected onto the
# axis perpendicular to `bucket_center` (ship-local angle). Falls back to
# ship.get_local_aabb()'s 4 corners if the silhouette has no outer loops (e.g.
# a ship with no rect-bearing components) but the ship still has real AABB
# geometry, so this never silently returns 0 for a ship that clearly exists.
#
# `ship`, when given, routes vertex lookup through ShipSilhouette.loops_for
# (its OWN per-class cache) instead of ShipSilhouette.compute (uncached --
# re-runs the Geometry2D.merge_polygons union from scratch). Without this, the
# expensive union would re-run on every one of this file's 72 bucket
# cache-misses per class instead of once -- exactly the cost this cache exists
# to avoid. `ship` is omitted only by pure-fixture unit tests that hand
# `compute()` a raw components Array with no backing ship instance.
static func compute(components: Array, bucket_center: float, ship = null) -> float:
	var vertices: Array = _outer_vertices(components, ship)
	if vertices.is_empty() and ship != null and ship.has_method("get_local_aabb"):
		var aabb: Rect2 = ship.get_local_aabb()
		if aabb.size.x > 0.0 or aabb.size.y > 0.0:
			vertices = [
				aabb.position,
				aabb.position + Vector2(aabb.size.x, 0.0),
				aabb.position + aabb.size,
				aabb.position + Vector2(0.0, aabb.size.y),
			]
	if vertices.is_empty():
		return 0.0

	var axis: Vector2 = Vector2.RIGHT.rotated(bucket_center + PI / 2.0)
	var min_proj: float = INF
	var max_proj: float = -INF
	for v in vertices:
		var proj: float = (v as Vector2).dot(axis)
		min_proj = min(min_proj, proj)
		max_proj = max(max_proj, proj)
	return max_proj - min_proj

static func _outer_vertices(components: Array, ship = null) -> Array:
	var loops: Array = ShipSilhouette.loops_for(ship) if ship != null else ShipSilhouette.compute(components)
	var vertices: Array = []
	for loop in loops:
		if loop.get("is_hole", false):
			continue
		var pts: PackedVector2Array = loop["points"]
		for p in pts:
			vertices.append(p)
	return vertices
