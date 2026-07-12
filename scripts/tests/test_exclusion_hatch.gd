extends Node

# M46 acceptance -- keep-back zone hatch FILL via polygon boolean ops
# (scripts/port/exclusion_hatch.gd). Pure fixtures, no scene/physics needed.
# Covers:
#   1. stripe_rects: non-empty for sane input, each a 4-point rectangle.
#   2. hatch_fragments: every fragment stays within [inner_radius,
#      outer_radius] of center (no leakage inside the keep-out hole or past
#      the outer boundary).
#   3. hatch_fragments with an exclude_polygon (the open channel wedge): no
#      fragment point falls inside the excluded sector, and total hatched
#      area measurably drops.
#   4. inner_radius <= 0 (no keep-out hole authored): the center point is
#      actually covered by a fragment, still bounded by outer_radius.
#   5. Degenerate inputs (zero/negative radii, spacing, stripe_width) return
#      empty, no crash.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_exclusion_hatch

const ExclusionHatch = preload("res://scripts/port/exclusion_hatch.gd")
const PortChannel = preload("res://scripts/port/port_channel.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("Starting Exclusion Hatch (M46) Tests")

	_run_stripe_rects_scenario()
	_run_bounds_scenario()
	_run_exclude_polygon_scenario()
	_run_no_inner_radius_scenario()
	_run_degenerate_scenario()

	_finalize()

const CENTER := Vector2(500.0, -300.0)   # off-origin, so any accidental origin-hardcoding shows up
const INNER := 300.0
const OUTER := 1500.0
const SPACING := 150.0
const STRIPE_W := 60.0

func _run_stripe_rects_scenario() -> void:
	var rects: Array = ExclusionHatch.stripe_rects(CENTER, OUTER, SPACING, STRIPE_W)
	_assert(not rects.is_empty(), "stripe_rects: produces a non-empty stripe field for sane input")
	if not rects.is_empty():
		_assert(rects[0].size() == 4, "stripe_rects: each stripe is a 4-point rectangle")

func _max_dist_from_center(fragments: Array) -> float:
	var max_d := 0.0
	for frag in fragments:
		for pt in frag:
			max_d = max(max_d, CENTER.distance_to(pt))
	return max_d

func _min_dist_from_center(fragments: Array) -> float:
	var min_d := INF
	for frag in fragments:
		for pt in frag:
			min_d = min(min_d, CENTER.distance_to(pt))
	return min_d

func _run_bounds_scenario() -> void:
	var fragments: Array = ExclusionHatch.hatch_fragments(CENTER, OUTER, INNER, SPACING, STRIPE_W)
	_assert(not fragments.is_empty(), "hatch_fragments: produces fragments for a plain annulus")
	if fragments.is_empty():
		return

	# Tessellated-circle tolerance: a 48-gon approximation sits slightly
	# inside the true circle between vertices (max chord error
	# ~ R*(1-cos(pi/48)), a small fraction of a percent of R) -- generous
	# epsilon so the test isn't coupled to CIRCLE_SEGMENTS' exact value.
	var eps := 5.0
	_assert(_max_dist_from_center(fragments) <= OUTER + eps,
		"hatch_fragments: no fragment vertex sits past the outer boundary (max=%.2f, outer=%.1f)" % [_max_dist_from_center(fragments), OUTER])
	_assert(_min_dist_from_center(fragments) >= INNER - eps,
		"hatch_fragments: no fragment vertex sits inside the inner (keep-out) boundary (min=%.2f, inner=%.1f)" % [_min_dist_from_center(fragments), INNER])

	for frag in fragments:
		_assert(frag.size() >= 3, "hatch_fragments: every fragment is a real polygon (3+ points)")

func _run_exclude_polygon_scenario() -> void:
	# A wide sector (generous half_angle so this is a strong, unambiguous
	# exclusion, not a boundary-precision test) centered on angle 0 (+X).
	var wedge: PackedVector2Array = PortChannel.sector_polygon(CENTER, 0.0, INNER, OUTER, deg_to_rad(60.0))
	_assert(wedge.size() >= 3, "exclude scenario setup: the test wedge itself is a real polygon")

	var fragments: Array = ExclusionHatch.hatch_fragments(CENTER, OUTER, INNER, SPACING, STRIPE_W, wedge)
	_assert(not fragments.is_empty(), "hatch_fragments: still produces fragments outside the excluded wedge")

	var leaked := false
	for frag in fragments:
		for pt in frag:
			var rel: Vector2 = pt - CENTER
			var angle_from_axis: float = abs(wrapf(rel.angle(), -PI, PI))
			var r: float = rel.length()
			if angle_from_axis < deg_to_rad(55.0) and r > INNER + 5.0 and r < OUTER - 5.0:
				leaked = true
	_assert(not leaked, "hatch_fragments: no fragment vertex sits well inside the excluded wedge's angular span")

	# The excluded case must produce STRICTLY LESS total AREA than the
	# unexcluded case -- proof the subtraction is actually removing area, not
	# silently ignoring exclude_polygon. NOT vertex count: clipping a big
	# fragment into several smaller ones legitimately RAISES point count
	# even as total area shrinks (a rectangle cut into three pieces goes
	# from 4 points to 12 despite covering less area).
	var unexcluded: Array = ExclusionHatch.hatch_fragments(CENTER, OUTER, INNER, SPACING, STRIPE_W)
	var excluded_area := 0.0
	for f in fragments: excluded_area += ExclusionHatch._polygon_area(f)
	var unexcluded_area := 0.0
	for f in unexcluded: unexcluded_area += ExclusionHatch._polygon_area(f)
	_assert(excluded_area < unexcluded_area,
		"hatch_fragments: excluding the wedge measurably reduces the hatched area (excluded=%.0f, unexcluded=%.0f)" % [excluded_area, unexcluded_area])

func _run_no_inner_radius_scenario() -> void:
	var fragments: Array = ExclusionHatch.hatch_fragments(CENTER, OUTER, 0.0, SPACING, STRIPE_W)
	_assert(not fragments.is_empty(), "hatch_fragments: inner_radius<=0 still produces fragments")
	# With no hole to cut, the exact CENTER point must be COVERED by some
	# fragment (the k=0 stripe passes straight through it). Point-in-polygon
	# containment, NOT vertex proximity -- a long straight stripe fragment's
	# polygon EDGE runs right through the center as a single line segment
	# between two far-apart vertices near the outer boundary; no vertex is
	# emitted AT the center even though the fragment's AREA covers it, so a
	# "does any vertex sit near center" check is testing the wrong thing.
	var contains_center := false
	for frag in fragments:
		if Geometry2D.is_point_in_polygon(CENTER, frag):
			contains_center = true
	_assert(contains_center, "hatch_fragments: with no inner_radius, the center point is covered by some fragment (no hole cut)")

func _run_degenerate_scenario() -> void:
	_assert(ExclusionHatch.hatch_fragments(CENTER, 0.0, INNER, SPACING, STRIPE_W).is_empty(),
		"degenerate: outer_radius == 0.0 -> empty")
	_assert(ExclusionHatch.hatch_fragments(CENTER, OUTER, OUTER, SPACING, STRIPE_W).is_empty(),
		"degenerate: inner_radius == outer_radius -> empty")
	_assert(ExclusionHatch.hatch_fragments(CENTER, OUTER, OUTER + 100.0, SPACING, STRIPE_W).is_empty(),
		"degenerate: inner_radius > outer_radius -> empty")
	_assert(ExclusionHatch.stripe_rects(CENTER, OUTER, 0.0, STRIPE_W).is_empty(),
		"degenerate: spacing == 0.0 -> empty stripe field")
	_assert(ExclusionHatch.stripe_rects(CENTER, OUTER, SPACING, 0.0).is_empty(),
		"degenerate: stripe_width == 0.0 -> empty stripe field")
	_assert(ExclusionHatch.stripe_rects(CENTER, 0.0, SPACING, STRIPE_W).is_empty(),
		"degenerate: outer_radius == 0.0 -> empty stripe field")

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_exclusion_hatch <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_exclusion_hatch <<<")
		get_tree().quit(1)
