extends Node

# M34 acceptance -- Docking nav aids (assigned slip highlight + lane)
# (implementation_plans/m31_m36_port_authority_roadmap.md, M34 section).
# Covers the roadmap's 3 test-plan scenarios, all synchronous (no physics
# stepping needed -- DockingBay children are built in _ready(), which already
# ran by the time add_child() returns, same pattern test_docking_permission.gd's
# issuance phase uses):
#   1. Lane geometry from pure fixtures (centerline/edges).
#   2. Assignment binding: a grant for slip 2 highlights bay 2's transform,
#      not bay 1's.
#   3. No grant -> no aid: helper/lookup returns empty, nothing highlighted.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_docking_nav_aids
# Pass marker per CLAUDE.md.

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const NavigationPanel = preload("res://scripts/ui/navigation_panel.gd")
const NavCorridor = preload("res://scripts/nav/nav_corridor.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func setup(main) -> void:
	main_node = main
	print("Starting Docking Nav Aids (M34) Tests")

	_run_lane_geometry_scenario()
	_run_assignment_binding_scenario()
	_run_no_grant_scenario()

	_finalize()

# ---------------------------------------------------------------------------
# Scenario 1 -- Lane geometry, pure fixtures (no scene at all).
# Mirrors test_port_zone.gd's geometry phase style: call the static helpers
# directly with hand-picked Vector2/float fixtures.
# ---------------------------------------------------------------------------
func _run_lane_geometry_scenario() -> void:
	var berth_pos := Vector2(1000.0, -500.0)
	var berth_heading := 0.0   # facing world +X ("outward" from the station)
	var length := 1500.0
	var half_width := 120.0

	# --- lane_path: centerline starts at berth_pos and runs along
	# berth_heading for LANE_LENGTH (waypoint sits `length` back, outward). ---
	var path: PackedVector2Array = NavigationPanel.lane_path(berth_pos, berth_heading, length)
	_assert(path.size() == 2, "lane_path: a 2-point path (waypoint -> berth)")
	if path.size() == 2:
		_assert(path[1] == berth_pos, "lane_path: the path's last point is berth_pos (the centerline ENDS at the berth)")
		var waypoint: Vector2 = path[0]
		_assert(waypoint.distance_to(berth_pos) == length,
			"lane_path: the approach waypoint is exactly LANE_LENGTH from the berth (got %.2f, want %.2f)" % [waypoint.distance_to(berth_pos), length])
		var expected_waypoint: Vector2 = berth_pos + Vector2.RIGHT.rotated(berth_heading) * length
		_assert(waypoint.distance_to(expected_waypoint) < 0.01,
			"lane_path: the waypoint sits along berth_heading's outward axis from the berth")

	# --- A rotated heading: same distance/along-heading invariants hold. ---
	var heading2 := deg_to_rad(37.0)
	var path2: PackedVector2Array = NavigationPanel.lane_path(berth_pos, heading2, length)
	var expected_waypoint2: Vector2 = berth_pos + Vector2.RIGHT.rotated(heading2) * length
	_assert(path2[0].distance_to(expected_waypoint2) < 0.01,
		"lane_path: a rotated berth_heading still places the waypoint along that heading")

	# --- corridor edges: parallel to the centerline at the authored half_width. ---
	var lane: Dictionary = NavigationPanel.lane_corridor(berth_pos, berth_heading, length, half_width)
	var centerline: PackedVector2Array = lane.get("centerline", PackedVector2Array())
	var left_edge: PackedVector2Array = lane.get("left_edge", PackedVector2Array())
	var right_edge: PackedVector2Array = lane.get("right_edge", PackedVector2Array())
	_assert(centerline.size() == 2 and left_edge.size() == 2 and right_edge.size() == 2,
		"lane_corridor: centerline/left_edge/right_edge all have one entry per path point")
	if left_edge.size() == 2 and right_edge.size() == 2:
		for i in range(2):
			var d_left: float = left_edge[i].distance_to(centerline[i])
			var d_right: float = right_edge[i].distance_to(centerline[i])
			_assert(absf(d_left - half_width) < 0.01,
				"lane_corridor: left_edge[%d] is exactly half_width from the centerline (got %.2f)" % [i, d_left])
			_assert(absf(d_right - half_width) < 0.01,
				"lane_corridor: right_edge[%d] is exactly half_width from the centerline (got %.2f)" % [i, d_right])
		# Edges run PARALLEL to the (straight, 2-point) centerline -- the
		# left-edge segment direction equals the centerline segment direction.
		var center_dir: Vector2 = (centerline[1] - centerline[0]).normalized()
		var left_dir: Vector2 = (left_edge[1] - left_edge[0]).normalized()
		var right_dir: Vector2 = (right_edge[1] - right_edge[0]).normalized()
		_assert(center_dir.distance_to(left_dir) < 0.001, "lane_corridor: left_edge runs parallel to the centerline")
		_assert(center_dir.distance_to(right_dir) < 0.001, "lane_corridor: right_edge runs parallel to the centerline")
		# left/right sit on opposite sides of the centerline.
		_assert(left_edge[0].distance_to(right_edge[0]) > half_width,
			"lane_corridor: left_edge and right_edge are on opposite sides of the centerline")

	# --- NavCorridor itself is generic: works for a longer multi-point path
	# too (M36's future buoy-road caller), not just a 2-point docking lane. ---
	var multi_path := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000)])
	var multi: Dictionary = NavCorridor.corridor(multi_path, 50.0)
	_assert(multi.get("centerline", PackedVector2Array()).size() == 3,
		"NavCorridor.corridor: a 3-point path returns a 3-point centerline (generic, not docking-specific)")
	_assert(multi.get("left_edge", PackedVector2Array()).size() == 3 and multi.get("right_edge", PackedVector2Array()).size() == 3,
		"NavCorridor.corridor: edges match the input path's point count for a multi-segment path")

	# --- Degenerate input: fewer than 2 points -> all empty, no crash. ---
	var degenerate: Dictionary = NavCorridor.corridor(PackedVector2Array([Vector2.ZERO]), 50.0)
	_assert(degenerate.get("centerline", PackedVector2Array()).is_empty(),
		"NavCorridor.corridor: a single-point path returns an empty centerline (nothing to draw)")

# ---------------------------------------------------------------------------
# Scenario 2 -- Assignment binding: a grant for slip 2 highlights bay 2's
# transform, not bay 1's. Two hand-built DockingBay children on a controlled
# station (mirrors test_docking_multi.gd's hand-built extra-berth pattern) so
# the test controls slip_id/pose directly instead of depending on how many
# docking_port components medium_station.gd happens to author today.
# ---------------------------------------------------------------------------
func _run_assignment_binding_scenario() -> void:
	var station := MediumStation.new()
	station.name = "AssignStation"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2(5000.0, 2000.0)
	station.port_zone = {"radius": 8000.0, "authority": "Assign Control", "rules": {}}
	main_node.add_child(station)

	# Two extra hand-built bays with distinct slip_ids/poses -- same pattern
	# test_docking_multi.gd uses for hand-made test bays (must set has_servo/
	# rotation itself since these never went through Ship._ready()'s
	# docking_port component loop).
	var bay1 := DockingBay.new()
	bay1.slip_id = "slip_1"
	bay1.position = Vector2(0.0, -300.0)
	bay1.rotation = deg_to_rad(-90.0)
	station.add_child(bay1)

	var bay2 := DockingBay.new()
	bay2.slip_id = "slip_2"
	bay2.position = Vector2(0.0, 300.0)
	bay2.rotation = deg_to_rad(90.0)
	station.add_child(bay2)

	var bays: Array = [bay1, bay2]
	var grant := {"authority": "Assign Control", "zone_authority": "Assign Control", "slip_id": "slip_2", "time_left": 300.0}

	var assigned: Node = NavigationPanel.assigned_bay_for(bays, grant)
	_assert(assigned == bay2, "assignment binding: a grant for slip_2 resolves to bay 2, not bay 1")
	_assert(assigned != bay1, "assignment binding: bay 1 is NOT the resolved bay")
	if assigned != null:
		_assert(assigned.global_position == bay2.global_position,
			"assignment binding: the highlighted berth pose equals bay 2's transform")
		_assert(assigned.global_position != bay1.global_position,
			"assignment binding: the highlighted berth pose is NOT bay 1's transform")
		_assert(assigned.global_rotation == bay2.global_rotation,
			"assignment binding: the highlighted berth heading equals bay 2's heading")

	# The reverse assignment (slip_1) resolves to bay 1, proving this isn't
	# just "always picks the last bay" or some other coincidence.
	var grant1 := {"authority": "Assign Control", "zone_authority": "Assign Control", "slip_id": "slip_1", "time_left": 300.0}
	var assigned1: Node = NavigationPanel.assigned_bay_for(bays, grant1)
	_assert(assigned1 == bay1, "assignment binding: a grant for slip_1 resolves to bay 1")

	# An any-open grant (slip_id == "") has no single assigned bay -- both bays
	# are EMPTY (open) and should show as open, but assigned_bay_for itself
	# must return null (no single lane to draw for any-open, per roadmap).
	var open_grant := {"authority": "Assign Control", "zone_authority": "Assign Control", "slip_id": "", "time_left": 300.0}
	var assigned_open: Node = NavigationPanel.assigned_bay_for(bays, open_grant)
	_assert(assigned_open == null, "any-open grant (slip_id==\"\") has no single assigned bay")
	var open_bays: Array = NavigationPanel.open_bays_for(bays)
	_assert(open_bays.size() == 2, "any-open grant: both untouched (EMPTY-state) bays read as open")

	_free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario 3 -- No grant -> no aid: the helper/lookup returns empty, nothing
# highlighted.
# ---------------------------------------------------------------------------
func _run_no_grant_scenario() -> void:
	var station := MediumStation.new()
	station.name = "NoGrantStation"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	station.port_zone = {"radius": 8000.0, "authority": "NoGrant Control", "rules": {}}
	main_node.add_child(station)

	var bay := DockingBay.new()
	bay.slip_id = "only_slip"
	bay.position = Vector2(0.0, 300.0)
	bay.rotation = deg_to_rad(90.0)
	station.add_child(bay)

	var bays: Array = [bay]

	# null grant (never requested docking).
	_assert(NavigationPanel.assigned_bay_for(bays, null) == null,
		"no grant (null): assigned_bay_for returns null -- nothing to highlight")

	# A grant for a slip that doesn't exist at this station also resolves to
	# nothing (defensive -- shouldn't happen in practice, but must not crash
	# or false-highlight the only bay present).
	var mismatched := {"authority": "NoGrant Control", "zone_authority": "NoGrant Control", "slip_id": "not_a_real_slip", "time_left": 300.0}
	_assert(NavigationPanel.assigned_bay_for(bays, mismatched) == null,
		"a grant for a slip_id with no matching bay resolves to null, not a false match")

	# An empty bays array (station resolution failed / no bays yet) -> empty,
	# no crash.
	var real_grant := {"authority": "NoGrant Control", "zone_authority": "NoGrant Control", "slip_id": "only_slip", "time_left": 300.0}
	_assert(NavigationPanel.assigned_bay_for([], real_grant) == null,
		"an empty bays list resolves to null regardless of grant contents")
	_assert(NavigationPanel.open_bays_for([]).is_empty(),
		"an empty bays list has no open bays either")

	_free_if_valid(station)

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_nav_aids <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_nav_aids <<<")
		get_tree().quit(1)
