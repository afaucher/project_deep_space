extends RefCounted
class_name PortChannel

# M46 (revised) -- docking channel geometry: the keep-back zone is TWO circles
# (a hard inner keep-out ring just off the hull, and a much larger outer
# boundary allowing off-angle approaches -- see PortZone.derive_keep_out_radius
# / derive_exclusion_radius), and the channel a specific-slip grant opens
# through it is a 90-DEGREE CONE (an annular sector) centered on the assigned
# berth's approach axis, not the earlier narrow rectangle. Both circles gap
# where the cone crosses them ("lines up with inner and outer gaps"); the
# sector's radial edges are the drawn docking-lane edges; a centerline guide
# marks where the docking clamps take over (see guide_points).
#
# Pure static helper, no scene/node state -- PortZone/NavCorridor house style,
# fixture-testable (test_port_channel.gd) with no station/bay/grant object.

# Total cone apex angle is 90 degrees -> half-angle 45, per design: "more like
# 90 degrees from the ideal docking location" so approaches well off the exact
# axis are still legal, with the two big circles doing the actual keep-back.
const CONE_HALF_ANGLE := PI / 4.0

# Arc tessellation for sector_polygon: segments per arc. Originally 8 (~11
# degrees/segment) when this polygon was only ever used to clip a thin
# STROKED line (Geometry2D.clip_polyline_with_polygon) -- indistinguishable
# from a true arc at map zoom there. Raised to 24 (~3.75 degrees/segment at
# the production 90-degree cone) once this polygon was ALSO used to subtract
# FILLED area (ExclusionHatch.hatch_fragments): a chord-approximated arc
# bulges slightly INSIDE the true circle between vertices (sagitta =
# R*(1-cos(half_segment_angle))), and at 8 steps that inward bulge was wide
# enough (order 5-10 world units at a medium station's exclusion_radius) to
# leave a visible sliver of un-subtracted hatch fill poking into the open
# channel near its outer edge -- caught by test_exclusion_hatch's wedge-
# exclusion scenario. At 24 steps the sagitta is under 1 unit even for a
# wider-than-production 120-degree test wedge.
const ARC_STEPS := 24

# Where the berth's approach axis crosses the OUTER boundary circle: a ray
# from berth_pos outward along Vector2.RIGHT.rotated(berth_heading),
# intersected with the circle of `boundary_radius` centered at
# `station_center`. Returns null (no channel to open) when:
#   - boundary_radius <= 0.0 (no exclusion zone authored/derived)
#   - the berth already sits ON or OUTSIDE the boundary (degenerate -- a
#     berth is always meant to sit well inside; guards malformed input)
#   - the outward ray never reaches the boundary (degenerate direction)
# Otherwise returns the world-space mouth point (t >= 0 along the ray).
static func mouth_point(berth_pos: Vector2, berth_heading: float, station_center: Vector2, boundary_radius: float):
	if boundary_radius <= 0.0:
		return null

	var outward: Vector2 = Vector2.RIGHT.rotated(berth_heading)
	if outward.length_squared() <= 0.000001:
		return null

	var rel: Vector2 = berth_pos - station_center
	if rel.length() >= boundary_radius:
		return null # berth already at/outside the boundary -- nothing to cut

	# Ray-circle intersection: |rel + t*outward|^2 == boundary_radius^2,
	# solved for t (outward is a unit vector, so the quadratic's `a` term is 1).
	var b: float = 2.0 * rel.dot(outward)
	var c: float = rel.length_squared() - boundary_radius * boundary_radius
	var disc: float = b * b - 4.0 * c
	if disc < 0.0:
		return null # ray never reaches the boundary (shouldn't happen -- rel is inside)

	var sqrt_disc: float = sqrt(disc)
	var t: float = max((-b + sqrt_disc) / 2.0, (-b - sqrt_disc) / 2.0)
	if t < 0.0:
		return null

	return berth_pos + outward * t

# The cone's center angle as seen FROM the station center: the polar angle of
# the mouth point (the spot where the approach axis exits the boundary). Using
# the mouth rather than the berth's raw heading keeps the wedge centered on
# where the axis actually crosses the circles even for a berth mounted
# off-center on its hull. Returns NAN when there is no mouth (see mouth_point).
static func axis_angle(berth_pos: Vector2, berth_heading: float, station_center: Vector2, boundary_radius: float) -> float:
	var mouth = mouth_point(berth_pos, berth_heading, station_center, boundary_radius)
	if mouth == null:
		return NAN
	return (mouth - station_center).angle()

# The channel cutout: a closed annular-sector polygon spanning
# [theta0 - half_angle, theta0 + half_angle] between inner_radius and
# outer_radius, centered on `center`. This is the region hatching is clipped
# OUT of (the open cone). Callers pass inner_radius = the HULL bounding radius
# (the cut must reach the berth itself, which sits inside the keep-out ring),
# outer_radius = the exclusion boundary. Empty for degenerate input
# (outer <= inner, outer <= 0, half_angle <= 0).
static func sector_polygon(center: Vector2, theta0: float, inner_radius: float, outer_radius: float, half_angle: float = CONE_HALF_ANGLE) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if outer_radius <= 0.0 or outer_radius <= inner_radius or half_angle <= 0.0:
		return empty
	inner_radius = max(inner_radius, 0.0)

	var pts := PackedVector2Array()
	# Inner arc, theta0-ha -> theta0+ha ...
	for i in range(ARC_STEPS + 1):
		var a: float = theta0 - half_angle + (2.0 * half_angle) * (float(i) / ARC_STEPS)
		pts.append(center + Vector2(cos(a), sin(a)) * inner_radius)
	# ...then the outer arc back, theta0+ha -> theta0-ha.
	for i in range(ARC_STEPS + 1):
		var a: float = theta0 + half_angle - (2.0 * half_angle) * (float(i) / ARC_STEPS)
		pts.append(center + Vector2(cos(a), sin(a)) * outer_radius)
	pts.append(pts[0])
	return pts

# The cone's two radial lane edges, spanning the inner keep-out ring's gap
# endpoint to the outer boundary's gap endpoint at theta0 +/- half_angle --
# "the docking lane is an edge around the annulus in that 90-degree cone,
# lines up with inner and outer gaps". Returns [[a1, b1], [a2, b2]] world-
# space segment pairs, or [] for degenerate input.
static func lane_edges(center: Vector2, theta0: float, keep_out_radius: float, outer_radius: float, half_angle: float = CONE_HALF_ANGLE) -> Array:
	if outer_radius <= 0.0 or outer_radius <= keep_out_radius or half_angle <= 0.0:
		return []
	var out: Array = []
	for sgn in [-1.0, 1.0]:
		var a: float = theta0 + sgn * half_angle
		var dir := Vector2(cos(a), sin(a))
		out.append([center + dir * max(keep_out_radius, 0.0), center + dir * outer_radius])
	return out

# Point-in-channel test against a polygon sector_polygon() already built --
# delegates to Geometry2D.is_point_in_polygon (the same primitive
# ship_silhouette.gd/test_collision_shapes.gd already use elsewhere in this
# codebase). A polygon with fewer than 3 points (degenerate/empty) never
# contains anything.
static func contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, polygon)
