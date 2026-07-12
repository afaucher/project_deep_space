extends Node

# M46 acceptance -- docking channel geometry. Pure fixtures, no scene/physics
# needed -- PortChannel is a static helper. Covers:
#   1. mouth_point + axis_angle derivation.
#   2. sector_polygon derivation and containment.
#   3. lane_edges correctly returning exactly two segments.
#   4. contains() rejects points outside the outer_radius, inside the inner_radius, or off-angle.
#   5. Degenerate inputs (zero/negative outer radius, inner >= outer, zero angle) return empty.
#
# guide_points() was REMOVED (was here as scenario 4): with every station's
# capture_radius (default 5000u) larger than its whole exclusion disc
# (~1584u for a medium station), its min(capture_radius, mouth_dist) always
# resolved to the mouth -- the drawn "docking guide" diamond always sat at
# the FAR edge of the no-fly zone, nowhere near the berth, which was exactly
# the "I can't tell where to hit" bug report. The M34 lane/slip marker
# (navigation_panel.gd's _draw_docking_nav_aids/_draw_lane, predates M46)
# already draws the correct actionable approach guide right down to the
# berth -- this was pure duplication with worse numbers, not a second aid.

const PortChannel = preload("res://scripts/port/port_channel.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("Starting Port Channel (M46) Tests")

	_run_mouth_and_axis_scenario()
	_run_sector_polygon_scenario()
	_run_lane_edges_scenario()
	_run_contains_rejection_scenario()
	_run_degenerate_scenario()

	_finalize()

const STATION_CENTER := Vector2.ZERO
const BERTH_POS := Vector2(200.0, 0.0)
const BERTH_HEADING := 0.0   # outward = +X
const INNER_RADIUS := 300.0
const OUTER_RADIUS := 1500.0
const HALF_ANGLE := PI / 4.0

func _run_mouth_and_axis_scenario() -> void:
	var mouth = PortChannel.mouth_point(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	_assert(mouth != null, "mouth_point: a valid berth resolves a real mouth point")
	if mouth != null:
		_assert(absf(STATION_CENTER.distance_to(mouth) - OUTER_RADIUS) < 0.01,
			"mouth_point: sits exactly on the outer boundary circle")
	
	var theta = PortChannel.axis_angle(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	_assert(absf(theta - 0.0) < 0.01, "axis_angle: heading 0.0 outwards resolves to theta 0.0")

func _run_sector_polygon_scenario() -> void:
	var theta = PortChannel.axis_angle(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	var poly = PortChannel.sector_polygon(STATION_CENTER, theta, INNER_RADIUS, OUTER_RADIUS, HALF_ANGLE)
	_assert(poly.size() >= 3, "sector_polygon: returns a valid polygon with 3+ points")
	_assert(poly.size() > 0 and poly[0] == poly[poly.size() - 1], "sector_polygon: loop is closed")
	
	# The midpoint between inner and outer on the axis should be inside
	var mid = STATION_CENTER + Vector2.RIGHT.rotated(theta) * ((INNER_RADIUS + OUTER_RADIUS) / 2.0)
	_assert(PortChannel.contains(poly, mid), "contains: the central axis midpoint is inside the sector")

func _run_lane_edges_scenario() -> void:
	var theta = PortChannel.axis_angle(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	var edges = PortChannel.lane_edges(STATION_CENTER, theta, INNER_RADIUS, OUTER_RADIUS, HALF_ANGLE)
	_assert(edges.size() == 2, "lane_edges: returns exactly two edges")
	if edges.size() == 2:
		_assert(edges[0].size() == 2 and edges[1].size() == 2, "lane_edges: each edge is a line segment")

func _run_contains_rejection_scenario() -> void:
	var theta = PortChannel.axis_angle(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	var poly = PortChannel.sector_polygon(STATION_CENTER, theta, INNER_RADIUS, OUTER_RADIUS, HALF_ANGLE)
	
	# Point strictly outside the outer radius
	var outside_outer = STATION_CENTER + Vector2.RIGHT.rotated(theta) * (OUTER_RADIUS + 100.0)
	_assert(not PortChannel.contains(poly, outside_outer), "contains: rejects points past outer_radius")
	
	# Point strictly inside the inner keep_out radius
	var inside_inner = STATION_CENTER + Vector2.RIGHT.rotated(theta) * (INNER_RADIUS - 100.0)
	_assert(not PortChannel.contains(poly, inside_inner), "contains: rejects points inside inner_radius")
	
	# Point at correct radius but way off angle
	var off_angle = STATION_CENTER + Vector2.RIGHT.rotated(theta + PI) * ((INNER_RADIUS + OUTER_RADIUS) / 2.0)
	_assert(not PortChannel.contains(poly, off_angle), "contains: rejects points outside half_angle sector")

func _run_degenerate_scenario() -> void:
	var theta = PortChannel.axis_angle(BERTH_POS, BERTH_HEADING, STATION_CENTER, OUTER_RADIUS)
	
	# Zero outer radius
	_assert(PortChannel.sector_polygon(STATION_CENTER, theta, INNER_RADIUS, 0.0).is_empty(),
		"degenerate: outer_radius == 0.0 -> empty polygon")
	_assert(PortChannel.lane_edges(STATION_CENTER, theta, INNER_RADIUS, 0.0).is_empty(),
		"degenerate: outer_radius == 0.0 -> empty edges")
	
	# inner >= outer
	_assert(PortChannel.sector_polygon(STATION_CENTER, theta, OUTER_RADIUS, OUTER_RADIUS - 100.0).is_empty(),
		"degenerate: inner_radius >= outer_radius -> empty polygon")
	_assert(PortChannel.lane_edges(STATION_CENTER, theta, OUTER_RADIUS, OUTER_RADIUS - 100.0).is_empty(),
		"degenerate: inner_radius >= outer_radius -> empty edges")
		
	# zero angle
	_assert(PortChannel.sector_polygon(STATION_CENTER, theta, INNER_RADIUS, OUTER_RADIUS, 0.0).is_empty(),
		"degenerate: half_angle == 0.0 -> empty polygon")
	_assert(PortChannel.lane_edges(STATION_CENTER, theta, INNER_RADIUS, OUTER_RADIUS, 0.0).is_empty(),
		"degenerate: half_angle == 0.0 -> empty edges")

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_port_channel <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_port_channel <<<")
		get_tree().quit(1)
