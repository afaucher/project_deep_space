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
#
# PRECOMPUTES the whole 72-bucket table for a class on its first miss (see
# _warm_class), rather than filling one bucket per miss. ShipSilhouette's own
# per-class cache means the expensive part (the polygon union) is already
# paid for after the first call either way; once vertices are in hand,
# projecting all 72 buckets costs barely more than projecting one. So a class
# hits this cache-miss path AT MOST ONCE ever, instead of up to 72 times
# spread across however many sensor-sweep frames it takes different bearings
# to be queried -- the whole point of caching in the first place.
static func cross_section_at_angle(ship, angle_from_target: float) -> float:
	if ship.get("ship_components") == null:
		return 0.0

	var script = ship.get_script()
	var class_key: String = script.resource_path if script != null else ""

	var local_angle: float = wrapf(angle_from_target - ship.rotation, -PI, PI)
	var bucket: int = _bucket_index(local_angle)
	var key: String = "%s|%d" % [class_key, bucket]

	if not _cache.has(key):
		_warm_class(class_key, ship)

	return _cache.get(key, 0.0)

static func _bucket_index(local_angle: float) -> int:
	var raw: int = int(round(local_angle / BUCKET_WIDTH))
	return ((raw % NUM_BUCKETS) + NUM_BUCKETS) % NUM_BUCKETS

# Fills every bucket for `class_key` in one pass: fetches the class's outer
# silhouette vertices ONCE (via ShipSilhouette.loops_for's own per-class
# cache, or the AABB-corners fallback), then projects them onto all 72
# bucket axes. After this call, every bucket for this class is a cache hit --
# there is no partial/lazy state to leave behind.
static func _warm_class(class_key: String, ship) -> void:
	var vertices: Array = _vertices_with_fallback(ship.get("ship_components"), ship)
	for b in range(NUM_BUCKETS):
		var bucket_center: float = b * BUCKET_WIDTH
		_cache["%s|%d" % [class_key, b]] = _project(vertices, bucket_center)

# Pure geometry: extent of `components`' outer silhouette projected onto the
# axis perpendicular to `bucket_center` (ship-local angle). Exposed
# separately (uncached, single-bucket) so tests can drive exact fixtures
# without a backing ship/class-cache -- see test_radar_cross_section.gd.
static func compute(components: Array, bucket_center: float, ship = null) -> float:
	return _project(_vertices_with_fallback(components, ship), bucket_center)

static func _project(vertices: Array, bucket_center: float) -> float:
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

# Falls back to ship.get_local_aabb()'s 4 corners if the silhouette has no
# outer loops (e.g. a ship with no rect-bearing components) but the ship
# still has real AABB geometry, so this never silently returns 0 for a ship
# that clearly exists.
#
# `ship`, when given, routes vertex lookup through ShipSilhouette.loops_for
# (its OWN per-class cache) instead of ShipSilhouette.compute (uncached --
# re-runs the Geometry2D.merge_polygons union from scratch). `ship` is
# omitted only by pure-fixture unit tests that hand compute() a raw
# components Array with no backing ship instance.
static func _vertices_with_fallback(components: Array, ship = null) -> Array:
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
	return vertices

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
