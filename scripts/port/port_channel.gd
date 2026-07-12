extends RefCounted
class_name PortChannel

# M46 -- docking channel geometry (design_ideas/port_zones_and_channels.md
# "Channel"). With a grant assigned to a specific slip, a corridor-shaped cut
# opens through the exclusion disc's hatching from the exclusion boundary to
# the berth, aligned with the berth's own approach axis (the same outward
# heading convention navigation_panel.gd's lane_path/lane_corridor already
# use: Vector2.RIGHT.rotated(berth_heading) points OUT of the station along
# the berth's facing).
#
# Pure static helper, no scene/node state -- PortZone/NavCorridor house style
# (RefCounted, static funcs only) so this is directly fixture-testable
# (test_port_channel.gd) with no station/bay/grant object required.

# Where the berth's approach axis crosses the exclusion boundary circle: a ray
# from berth_pos outward along Vector2.RIGHT.rotated(berth_heading),
# intersected with the circle of `exclusion_radius` centered at
# `station_center`. Returns null (nothing to cut a channel through) when:
#   - exclusion_radius <= 0.0 (no exclusion zone authored/derived)
#   - the berth already sits ON or OUTSIDE the boundary (degenerate -- a
#     berth is always meant to sit well inside the disc; this guards a
#     malformed/edge-case input rather than asserting it can't happen)
#   - the outward ray never reaches the boundary (degenerate direction)
# Otherwise returns the world-space mouth point (t >= 0 along the ray).
static func mouth_point(berth_pos: Vector2, berth_heading: float, station_center: Vector2, exclusion_radius: float):
	if exclusion_radius <= 0.0:
		return null

	var outward: Vector2 = Vector2.RIGHT.rotated(berth_heading)
	if outward.length_squared() <= 0.000001:
		return null

	var rel: Vector2 = berth_pos - station_center
	if rel.length() >= exclusion_radius:
		return null # berth already at/outside the boundary -- nothing to cut

	# Ray-circle intersection: |rel + t*outward|^2 == exclusion_radius^2,
	# solved for t (outward is a unit vector, so the quadratic's `a` term is 1).
	var b: float = 2.0 * rel.dot(outward)
	var c: float = rel.length_squared() - exclusion_radius * exclusion_radius
	var disc: float = b * b - 4.0 * c
	if disc < 0.0:
		return null # ray never reaches the boundary (shouldn't happen -- rel is inside)

	var sqrt_disc: float = sqrt(disc)
	var t1: float = (-b + sqrt_disc) / 2.0
	var t2: float = (-b - sqrt_disc) / 2.0
	var t: float = max(t1, t2) # the forward (outward-facing) intersection
	if t < 0.0:
		return null

	return berth_pos + outward * t

# The channel's 4-corner rectangle (closed loop -- first point repeated at the
# end, matching the PackedVector2Array shape Geometry2D.is_point_in_polygon/
# clip_polyline_with_polygon expect), half_width wide, spanning mouth_point()
# -> berth_pos. Empty (no geometry) for any degenerate input: no mouth
# (see mouth_point()'s null cases), a zero-length span (mouth == berth_pos),
# or half_width <= 0.0.
static func polygon(berth_pos: Vector2, berth_heading: float, station_center: Vector2, exclusion_radius: float, half_width: float) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if half_width <= 0.0:
		return empty

	var mouth = mouth_point(berth_pos, berth_heading, station_center, exclusion_radius)
	if mouth == null:
		return empty

	var span: Vector2 = berth_pos - mouth
	if span.length_squared() <= 0.000001:
		return empty

	var normal: Vector2 = span.normalized().rotated(PI / 2.0)
	var p1: Vector2 = mouth + normal * half_width
	var p2: Vector2 = berth_pos + normal * half_width
	var p3: Vector2 = berth_pos - normal * half_width
	var p4: Vector2 = mouth - normal * half_width
	return PackedVector2Array([p1, p2, p3, p4, p1])

# Point-in-channel test against a polygon `polygon()` already built --
# delegates to Geometry2D.is_point_in_polygon (the same primitive
# ship_silhouette.gd/test_collision_shapes.gd already use elsewhere in this
# codebase) rather than re-deriving an oriented-rectangle check, so it works
# for whatever polygon shape a caller hands it, not just this module's own
# rectangle. A polygon with fewer than 3 points (degenerate/empty) never
# contains anything.
static func contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, polygon)
