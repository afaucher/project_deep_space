extends Node

# M46 acceptance -- docking channel geometry (design_ideas/
# port_zones_and_channels.md "Channel"; implementation_plans/
# m46_m47_port_zone_visuals_roadmap.md M46 scope item 3). Pure fixtures, no
# scene/physics needed -- PortChannel is a static helper (PortZone/NavCorridor
# house style). Covers:
#   1. Channel polygon derivation: contains points on the approach axis
#      between the exclusion boundary and the berth.
#   2. Channel width clears the capture cone (DockingBay's capture hemisphere)
#      with margin -- CHANNEL_HALF_WIDTH is comfortably wider than the M34
#      lane's LANE_HALF_WIDTH, which already threads that same approach
#      region successfully.
#   3. contains() rejects points outside the corridor (off-axis and
#      beyond either endpoint).
#   4. Degenerate inputs (zero/negative radius, berth already outside the
#      boundary, zero/negative half_width) return empty geometry, not a
#      crash.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_port_channel
# Pass marker per CLAUDE.md.

const PortChannel = preload("res://scripts/port/port_channel.gd")
const NavigationPanel = preload("res://scripts/ui/navigation_panel.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("Starting Port Channel (M46) Tests")

	_run_mouth_and_polygon_scenario()
	_run_capture_cone_margin_scenario()
	_run_contains_rejection_scenario()
	_run_degenerate_scenario()

	_finalize()

# ---------------------------------------------------------------------------
# Scenario 1 -- mouth_point + polygon derivation, straight-outward fixture.
# station at origin, berth 200u out along +X, exclusion_radius 1500u.
# ---------------------------------------------------------------------------
const STATION_CENTER := Vector2.ZERO
const BERTH_POS := Vector2(200.0, 0.0)
const BERTH_HEADING := 0.0   # outward = +X
const EXCLUSION_RADIUS := 1500.0
const HALF_WIDTH := 300.0

func _run_mouth_and_polygon_scenario() -> void:
	var mouth = PortChannel.mouth_point(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS)
	_assert(mouth != null, "mouth_point: a berth well inside the boundary resolves a real mouth point")
	if mouth != null:
		_assert(absf(STATION_CENTER.distance_to(mouth) - EXCLUSION_RADIUS) < 0.01,
			"mouth_point: the mouth sits exactly on the exclusion boundary circle (got dist %.2f, want %.2f)" % [STATION_CENTER.distance_to(mouth), EXCLUSION_RADIUS])
		var expected_mouth: Vector2 = BERTH_POS + Vector2.RIGHT.rotated(BERTH_HEADING) * (mouth as Vector2).distance_to(BERTH_POS)
		_assert(mouth.distance_to(expected_mouth) < 0.01,
			"mouth_point: the mouth lies along the berth's outward approach axis from berth_pos")

	var polygon: PackedVector2Array = PortChannel.polygon(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS, HALF_WIDTH)
	_assert(polygon.size() == 5, "polygon: a valid channel returns a closed 4-corner loop (5 points, first repeated)")
	_assert(polygon.size() > 0 and polygon[0] == polygon[polygon.size() - 1],
		"polygon: the loop is closed (first point == last point)")

	# Points ON the approach axis strictly between the mouth and the berth
	# must be contained -- the whole point of the channel is a clear path
	# down that axis.
	if mouth != null and polygon.size() >= 3:
		var m: Vector2 = mouth
		for frac in [0.1, 0.5, 0.9]:
			var pt: Vector2 = m.lerp(BERTH_POS, frac)
			_assert(PortChannel.contains(polygon, pt),
				"polygon.contains: a point %.0f%% along the approach axis (mouth->berth) is inside the channel" % (frac * 100.0))

		# The berth itself and (very near) the mouth are inside too (endpoints).
		_assert(PortChannel.contains(polygon, BERTH_POS),
			"polygon.contains: the berth position itself is inside the channel")
		_assert(PortChannel.contains(polygon, m.lerp(BERTH_POS, 0.01)),
			"polygon.contains: a point just inside the mouth is inside the channel")

# ---------------------------------------------------------------------------
# Scenario 2 -- channel width clears the capture cone with margin. DockingBay
# (scripts/docking/docking_bay.gd) captures anywhere in the forward
# hemisphere within capture_radius -- not a narrow angular cone -- so there's
# no single "cone width" constant to compare against directly. What DOES
# already thread that same approach region successfully is the M34 approach
# lane (LANE_HALF_WIDTH, navigation_panel.gd) -- the channel must be at least
# that wide, with real margin, so a ship following the lane never grazes the
# channel's own hatch-cut edge.
# ---------------------------------------------------------------------------
func _run_capture_cone_margin_scenario() -> void:
	_assert(NavigationPanel.CHANNEL_HALF_WIDTH > NavigationPanel.LANE_HALF_WIDTH,
		"channel width: CHANNEL_HALF_WIDTH (%.0f) is wider than the M34 approach lane's LANE_HALF_WIDTH (%.0f) -- the lane fits inside the channel with margin" % [NavigationPanel.CHANNEL_HALF_WIDTH, NavigationPanel.LANE_HALF_WIDTH])

	# The lane's full width (2x half-width) plus a healthy margin still fits
	# inside the channel's full width -- not just barely wider.
	var lane_full: float = NavigationPanel.LANE_HALF_WIDTH * 2.0
	var channel_full: float = NavigationPanel.CHANNEL_HALF_WIDTH * 2.0
	_assert(channel_full >= lane_full * 1.5,
		"channel width: the channel's full width (%.0f) is at least 1.5x the lane's full width (%.0f) -- real margin, not a hair's-breadth fit" % [channel_full, lane_full])

# ---------------------------------------------------------------------------
# Scenario 3 -- contains() rejects points outside the corridor: off-axis
# (beyond half_width) and beyond either endpoint along the axis.
# ---------------------------------------------------------------------------
func _run_contains_rejection_scenario() -> void:
	var polygon: PackedVector2Array = PortChannel.polygon(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS, HALF_WIDTH)
	var mouth = PortChannel.mouth_point(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS)
	_assert(mouth != null and polygon.size() >= 3, "contains-rejection setup: a valid mouth/polygon exists to test against")
	if mouth == null or polygon.size() < 3:
		return
	var mid: Vector2 = (mouth as Vector2).lerp(BERTH_POS, 0.5)

	# Off-axis: same "along" position as `mid` but well past half_width laterally.
	var off_axis: Vector2 = mid + Vector2(0.0, HALF_WIDTH * 3.0)
	_assert(not PortChannel.contains(polygon, off_axis),
		"polygon.contains: a point far off-axis (3x half_width laterally) is rejected")

	# Beyond the mouth, outside the exclusion boundary entirely.
	var beyond_mouth: Vector2 = mouth + Vector2.RIGHT.rotated(BERTH_HEADING) * 500.0
	_assert(not PortChannel.contains(polygon, beyond_mouth),
		"polygon.contains: a point beyond the mouth (outside the boundary) is rejected")

	# Inward of the berth, back toward the station center past the near end.
	var inward_of_berth: Vector2 = BERTH_POS - Vector2.RIGHT.rotated(BERTH_HEADING) * 500.0
	_assert(not PortChannel.contains(polygon, inward_of_berth),
		"polygon.contains: a point inward of the berth (past the corridor's near end) is rejected")

	# An empty polygon (degenerate caller) never contains anything.
	_assert(not PortChannel.contains(PackedVector2Array(), mid),
		"polygon.contains: an empty polygon rejects every point, no crash")

# ---------------------------------------------------------------------------
# Scenario 4 -- degenerate inputs return empty geometry, not a crash.
# ---------------------------------------------------------------------------
func _run_degenerate_scenario() -> void:
	# Zero exclusion radius -- no exclusion zone authored/derived.
	_assert(PortChannel.mouth_point(BERTH_POS, BERTH_HEADING, STATION_CENTER, 0.0) == null,
		"degenerate: exclusion_radius == 0.0 -> no mouth point")
	_assert(PortChannel.polygon(BERTH_POS, BERTH_HEADING, STATION_CENTER, 0.0, HALF_WIDTH).is_empty(),
		"degenerate: exclusion_radius == 0.0 -> empty polygon")

	# Negative exclusion radius -- malformed, must not crash.
	_assert(PortChannel.mouth_point(BERTH_POS, BERTH_HEADING, STATION_CENTER, -100.0) == null,
		"degenerate: negative exclusion_radius -> no mouth point")

	# Berth already at/outside the boundary -- nothing to cut a channel through.
	var far_berth := Vector2(2000.0, 0.0)
	_assert(PortChannel.mouth_point(far_berth, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS) == null,
		"degenerate: a berth already outside the exclusion boundary -> no mouth point")
	_assert(PortChannel.polygon(far_berth, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS, HALF_WIDTH).is_empty(),
		"degenerate: a berth already outside the exclusion boundary -> empty polygon")

	# Zero/negative half_width -- no width to build a corridor with.
	_assert(PortChannel.polygon(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS, 0.0).is_empty(),
		"degenerate: half_width == 0.0 -> empty polygon")
	_assert(PortChannel.polygon(BERTH_POS, BERTH_HEADING, STATION_CENTER, EXCLUSION_RADIUS, -50.0).is_empty(),
		"degenerate: negative half_width -> empty polygon")

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_port_channel <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_port_channel <<<")
		get_tree().quit(1)
