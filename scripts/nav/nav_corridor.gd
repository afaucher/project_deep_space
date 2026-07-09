extends RefCounted
class_name NavCorridor

# M34 -- shared corridor geometry helper. A pure static that turns ANY
# polyline (a sequence of world-space waypoints -- not docking-specific) into
# a drawable guide corridor: a centerline (the path itself) plus two edges
# offset perpendicular to each segment by half_width. M34's docking lane is
# the first caller (a 2-point path: approach waypoint -> berth); M36's
# buoy-road corridor is a later caller over a longer multi-point path -- kept
# generic here so both draw the same way (see roadmap M34 scope: "so the
# docking lane AND M36's buoy-road corridor draw the same way").
#
# No scene/node state (RefCounted, one static method) per the PortZone
# template (scripts/port/port_zone.gd) -- testable with hand-picked
# PackedVector2Array fixtures, no scene required.

# Returns {centerline: PackedVector2Array, left_edge: PackedVector2Array,
# right_edge: PackedVector2Array}. centerline is `path` unchanged (pass-
# through, so callers can draw it directly). left_edge/right_edge are `path`
# offset perpendicular to the LOCAL segment direction at each vertex by
# +/- half_width -- at an interior vertex the offset direction is the average
# of the two adjacent segment normals (a plain miter), so the edges stay
# parallel-ish through a bend instead of gapping/overlapping. A path with
# fewer than 2 points has no direction to offset along, so all three arrays
# come back empty (nothing to draw).
static func corridor(path: PackedVector2Array, half_width: float) -> Dictionary:
	var empty := PackedVector2Array()
	if path.size() < 2:
		return {"centerline": empty, "left_edge": empty, "right_edge": empty}

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := path.size()

	for i in range(n):
		var normal: Vector2
		if i == 0:
			normal = _segment_normal(path[0], path[1])
		elif i == n - 1:
			normal = _segment_normal(path[i - 1], path[i])
		else:
			var n_prev := _segment_normal(path[i - 1], path[i])
			var n_next := _segment_normal(path[i], path[i + 1])
			var miter := (n_prev + n_next)
			normal = miter.normalized() if miter.length_squared() > 0.000001 else n_prev

		left.append(path[i] + normal * half_width)
		right.append(path[i] - normal * half_width)

	return {"centerline": path, "left_edge": left, "right_edge": right}

# Perpendicular (left-hand) unit normal of the segment a->b. Zero-length
# segment (coincident points) falls back to Vector2.ZERO -- callers already
# guard path.size() < 2, but two IDENTICAL adjacent points is still possible
# from a degenerate caller, so this stays a safe no-direction rather than a
# divide-by-zero.
static func _segment_normal(a: Vector2, b: Vector2) -> Vector2:
	var dir: Vector2 = b - a
	if dir.length_squared() <= 0.000001:
		return Vector2.ZERO
	return dir.normalized().rotated(PI / 2.0)
