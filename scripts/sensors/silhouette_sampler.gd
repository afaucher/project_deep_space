extends RefCounted

# M26 -- sensor-dot silhouette sampling (design_ideas/ship_outline_rendering.md
# "v2 -- sensor dots"; implementation_plans/m26_sensor_dot_outlines_design.md).
#
# Pure static math on dicts/Rect2/Vector2 -- ZERO Node/physics dependencies.
# This is deliberately NOT a physics-space raycast (no intersect_ray): the
# sweep already knows a contact exists (physics/sensor detection did that
# job); this module only asks "where, analytically, would a ray along this
# bearing first touch one of the target's authored component rects" so the
# nav panel can draw a measured silhouette instead of a ground-truth blob.
# Reused geometry: the same ray-vs-AABB slab test as Ship.take_damage()'s
# raymarch clip, at coarser (per-bin, not per-2px-step) grain.

# ---------------------------------------------------------------------------
# ray_rect_hit -- analytic ray/AABB slab test.
#
# Contract (pinned, not incidental):
#   - Returns the entry distance t >= 0 along `dir` (need NOT be normalized;
#     the returned t is in units of `dir`'s own length) at which the ray
#     first enters `rect`, or -1.0 if the ray never enters it.
#   - Origin already inside the rect: returns 0.0 (the ray "enters" at zero
#     distance -- it's already touching the skin from the inside). This
#     mirrors Ship.take_damage()'s own raymarch, which clamps tmin to 0 for
#     exactly this case rather than reporting a negative/undefined entry.
#   - Ray parallel to a face (dir component ~0 on that axis): that axis
#     contributes no constraint IF the origin's coordinate on the axis
#     already lies within the rect's [min, max] on that axis (inclusive --
#     grazing exactly on the edge counts as a hit, not a miss); otherwise the
#     ray can never enter the slab on that axis and the whole test misses
#     regardless of the other axis, so returns -1.0 immediately.
#   - Rect entirely behind the origin along `dir` (tmax < 0): returns -1.0.
#   - Clean miss (tmin > tmax after both axes): returns -1.0.
# ---------------------------------------------------------------------------
static func ray_rect_hit(origin: Vector2, dir: Vector2, rect: Rect2) -> float:
	const EPS := 0.0000001
	var tmin := -INF
	var tmax := INF

	var mins := rect.position
	var maxs := rect.position + rect.size

	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		var d: float = dir[axis]
		var o: float = origin[axis]
		if absf(d) < EPS:
			# Parallel to this axis' slab faces -- only survives if origin is
			# already within [min, max] on this axis (edge-inclusive).
			if o < mins[axis] or o > maxs[axis]:
				return -1.0
			continue
		var t1 := (mins[axis] - o) / d
		var t2 := (maxs[axis] - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = max(tmin, t1)
		tmax = min(tmax, t2)

	if tmin > tmax:
		return -1.0
	if tmax < 0.0:
		return -1.0 # rect is entirely behind the origin

	return max(0.0, tmin)

# ---------------------------------------------------------------------------
# sample -- nearest entry point across every component rect, in the TARGET's
# local frame. `sensor_pos_local` and `bearing` (radians) are both already
# expressed in that same target-local frame by the caller (ship.gd builds the
# transform chain -- see the comment on the call site). Returns the entry
# Vector2 (target-local) of the NEAREST hit rect, or null if the bearing
# misses every component (a legitimate "your ray passed clean through empty
# space between components" result, not an error).
# ---------------------------------------------------------------------------
static func sample(components: Array, sensor_pos_local: Vector2, bearing: float):
	var dir := Vector2.RIGHT.rotated(bearing)
	var nearest_t := INF
	var nearest_point = null

	for comp in components:
		var rect: Rect2 = comp.get("rect", Rect2())
		var t := ray_rect_hit(sensor_pos_local, dir, rect)
		if t < 0.0:
			continue
		if t < nearest_t:
			nearest_t = t
			nearest_point = sensor_pos_local + dir * t

	return nearest_point

# ---------------------------------------------------------------------------
# subtense_bins -- which of a sensor's angular bins cover a target's angular
# subtense, given the target's bounding radius (M25's get_bounding_radius()).
# Pure trig, no dict access beyond the plain values passed in.
#
# sensor_bearing_to_target: angle (radians, sensor-frame convention already
#   resolved by the caller, i.e. this is rel_angle/cone_local_angle style,
#   same convention _run_sensor_sweep uses) from the sensor to the target
#   center.
# num_bins / arc_width: the sensor's own bin count and total swept arc.
# target_dist / target_radius: distance to and bounding radius of the target
#   -- half-angle subtended = asin(clamp(radius/dist, 0, 1)).
#
# Returns {"lo": int, "hi": int} inclusive bin-index range (clamped to
# [0, num_bins - 1]) covering [bearing - half_angle, bearing + half_angle].
# If the target is closer than its own radius (degenerate/overlapping),
# subtends the full arc (lo=0, hi=num_bins-1) rather than dividing by ~0.
# ---------------------------------------------------------------------------
static func subtense_bins(sensor_bearing_to_target: float, num_bins: int, arc_width: float, target_dist: float, target_radius: float) -> Dictionary:
	if num_bins <= 0 or arc_width <= 0.0:
		return {"lo": 0, "hi": -1} # empty range -- no bins to sample

	if target_dist <= target_radius:
		return {"lo": 0, "hi": num_bins - 1}

	var half_angle: float = asin(clampf(target_radius / target_dist, 0.0, 1.0))
	var bin_angle: float = arc_width / float(num_bins)
	var half_arc: float = arc_width / 2.0

	# Map bearing into the sensor's own cone-local angle space, same
	# convention _run_sensor_sweep uses (cone_local_angle = rel_angle +
	# half_arc, then bin_idx = floor(cone_local_angle / bin_angle)).
	var rel_angle: float = wrapf(sensor_bearing_to_target, -PI, PI)
	var lo_angle: float = rel_angle - half_angle + half_arc
	var hi_angle: float = rel_angle + half_angle + half_arc

	var lo_bin: int = int(floor(lo_angle / bin_angle))
	var hi_bin: int = int(floor(hi_angle / bin_angle))

	lo_bin = clampi(lo_bin, 0, num_bins - 1)
	hi_bin = clampi(hi_bin, 0, num_bins - 1)
	if lo_bin > hi_bin:
		var tmp := lo_bin
		lo_bin = hi_bin
		hi_bin = tmp

	return {"lo": lo_bin, "hi": hi_bin}
