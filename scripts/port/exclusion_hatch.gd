extends RefCounted
class_name ExclusionHatch

# M46 (revised) -- keep-back zone hatch FILL via POLYGON BOOLEAN OPS instead
# of hand-derived ray/circle line-segment math (the earlier
# navigation_panel.exclusion_hatch_lines approach, now removed). That
# per-line math only ever punched a hole for ONE inner boundary (the hull);
# extending it to also respect keep_out_radius AND the open channel wedge
# meant re-deriving ray/circle intersections by hand for every new boundary,
# and it never actually got the keep-out ring treatment (design_ideas/
# port_zones_and_channels.md: "we draw the diagonal strips through the inner
# ring").
#
# Polygon ops sidestep this generically: build a field of diagonal stripe
# RECTANGLES covering the whole disc, then INTERSECT with the outer boundary
# circle and SUBTRACT the inner boundary circle (and the open channel wedge,
# when present) via Geometry2D's built-in polygon clipper -- the exact same
# primitive ship_silhouette.gd already uses for hull-outline boolean ops
# (Geometry2D.clip_polygons/merge_polygons; is_polygon_clockwise to detect a
# hole-wound result fragment). Any future boundary shape is one more clip
# call, not new math.
#
# Pure static helper, no scene/node state -- PortZone/PortChannel/NavCorridor
# house style (RefCounted, static funcs only), fixture-testable with no
# station/bay object required.

const CIRCLE_SEGMENTS := 48

static func _circle_polygon(center: Vector2, radius: float, segments: int = CIRCLE_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

# The raw diagonal stripe field: parallel 45-degree rectangles, `spacing`
# world units apart center-to-center, `stripe_width` wide, long enough
# (1.5x outer_radius each side of center, along the stripe direction) to
# span clear across a circle of `outer_radius` regardless of which offset
# band a given stripe sits in -- intersect_polygons trims each one to its
# exact visible extent, so overshoot here costs nothing but a slightly
# larger input polygon. World-space output, centered on `center` (caller
# doesn't need to translate).
static func stripe_rects(center: Vector2, outer_radius: float, spacing: float, stripe_width: float) -> Array:
	var out: Array = []
	if outer_radius <= 0.0 or spacing <= 0.0 or stripe_width <= 0.0:
		return out
	var u := Vector2(1.0, 1.0).normalized()
	var v := Vector2(1.0, -1.0).normalized()
	var half_len: float = outer_radius * 1.5
	var half_w: float = stripe_width * 0.5
	var k_min: int = int(ceil(-(outer_radius + stripe_width) / spacing))
	var k_max: int = int(floor((outer_radius + stripe_width) / spacing))
	for k in range(k_min, k_max + 1):
		var o: float = float(k) * spacing
		var mid: Vector2 = center + v * o
		out.append(PackedVector2Array([
			mid - u * half_len - v * half_w,
			mid + u * half_len - v * half_w,
			mid + u * half_len + v * half_w,
			mid - u * half_len + v * half_w,
		]))
	return out

# Minimum fragment area to keep -- filters float-precision slivers (a
# near-tangent intersect/clip can emit a degenerate near-zero-area artifact),
# nothing else. NOT a hole-winding filter: an earlier version skipped any
# Geometry2D.is_polygon_clockwise() fragment (mirroring ship_silhouette.gd's
# convention for ITS pipeline, folding hull outlines) -- but that convention
# doesn't hold for a plain rect-vs-circle intersect_polygons() result, and
# test_exclusion_hatch caught it discarding a real, large, obviously-solid
# fragment (a stripe crossing dead center with no inner_radius to cut it).
# A genuine INTERIOR HOLE can't actually occur for this module's inputs
# anyway: a thin stripe rectangle (stripe_width, tens of units) can't be wide
# enough to fully surround a subtracted circle/wedge (hundreds to thousands
# of units) and still have solid material connecting all the way around it --
# so there's no hole to defend against, only degenerate slivers to drop.
const MIN_FRAGMENT_AREA := 1.0

static func _polygon_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5

# The final drawable hatch fragments for an annulus (center, inner_radius ->
# outer_radius), with an optional wedge (`exclude_polygon` -- e.g.
# PortChannel.sector_polygon's open-cone cutout) subtracted on top. Each
# fragment is a simple polygon ready for CanvasItem.draw_colored_polygon().
# inner_radius <= 0 skips the inner-circle subtraction entirely (nothing to
# cut -- e.g. a zone with no keep-out ring authored).
static func hatch_fragments(center: Vector2, outer_radius: float, inner_radius: float, spacing: float, stripe_width: float, exclude_polygon: PackedVector2Array = PackedVector2Array()) -> Array:
	var out: Array = []
	if outer_radius <= 0.0 or outer_radius <= inner_radius:
		return out

	var outer_circle: PackedVector2Array = _circle_polygon(center, outer_radius)
	var inner_circle: PackedVector2Array = _circle_polygon(center, inner_radius) if inner_radius > 0.0 else PackedVector2Array()
	var has_exclude: bool = exclude_polygon.size() >= 3

	for rect in stripe_rects(center, outer_radius, spacing, stripe_width):
		var pieces: Array = Geometry2D.intersect_polygons(rect, outer_circle)
		if inner_circle.size() >= 3:
			var next: Array = []
			for piece in pieces:
				next.append_array(Geometry2D.clip_polygons(piece, inner_circle))
			pieces = next
		if has_exclude:
			var next2: Array = []
			for piece in pieces:
				next2.append_array(Geometry2D.clip_polygons(piece, exclude_polygon))
			pieces = next2
		for piece in pieces:
			if piece.size() >= 3 and _polygon_area(piece) >= MIN_FRAGMENT_AREA:
				out.append(piece)
	return out
