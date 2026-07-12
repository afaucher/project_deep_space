extends Node

# M19 acceptance -- force-capture soft-dock. A passive cargo shuttle placed off
# the berth with wants_dock=true must be captured, drawn in, settled at the berth
# (proving capture actually moved it), held, then released after the timer. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_docking
# Needs physics frames, so it drives phased checks in _physics_process. Pass
# marker per CLAUDE.md.

const SmallStation = preload("res://scripts/ships/small_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var station = null
var bay = null
var shuttle = null
var start_dist: float = 0.0
var t: float = 0.0
var phase: int = 0          # 0 = approach, 1 = hold-then-release
var dock_time: float = -1.0

const APPROACH_TIMEOUT := 12.0
# Comfortably inside SmallStation's derived capture_radius (~275u for its
# ~184u hull -- see PortZone.derive_capture_radius, a short-range docking
# arm, not the old flat 5000u default) while still meaningfully off the
# berth (>100u -- see the start_dist assertion below).
const START_OFFSET := Vector2(80, 150)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Docking (M19) Tests")

	station = SmallStation.new()
	station.name = "Station"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	main_node.add_child(station)   # _ready grows the bay

	for c in station.get_children():
		if c is DockingBay:
			bay = c
	if bay == null:
		_assert(false, "setup: station should have grown a DockingBay")
		_finalize()
		return

	var berth: Vector2 = bay.global_position
	shuttle = CargoShuttle.new()
	shuttle.name = "Shuttle"
	shuttle.owner_id = 50
	shuttle.iff_tags = ["TEAM_PLAYER"]   # friendly so station PD ignores it
	shuttle.position = berth + START_OFFSET
	shuttle.wants_dock = true
	main_node.add_child(shuttle)

	start_dist = shuttle.position.distance_to(berth)

func _physics_process(delta: float) -> void:
	if finished or bay == null or shuttle == null:
		return
	t += delta

	if phase == 0:
		if bay.state == DockingBay.State.DOCKED:
			dock_time = t
			var port_offset = bay._get_captured_port_offset(shuttle)
			var port_global_offset = port_offset.rotated(shuttle.rotation)
			var err: float = bay._berth_pos_for(shuttle).distance_to(shuttle.position + port_global_offset)
			var spd: float = shuttle.linear_velocity.length()
			_assert(start_dist > 100.0, "shuttle should start well off the berth (was %.0f)" % start_dist)
			_assert(err < bay.pos_tolerance, "docked pose should be within tolerance (err=%.1f)" % err)
			_assert(spd < bay.settle_speed, "docked ship should be settled/slow (spd=%.1f)" % spd)
			_assert(is_finite(shuttle.position.x) and is_finite(shuttle.position.y), "docked position must be finite")
			phase = 1
		elif t > APPROACH_TIMEOUT:
			var d: float = bay.global_position.distance_to(shuttle.position)
			_assert(false, "APPROACH timeout -- never docked (state=%d, dist=%.0f)" % [bay.state, d])
			_finalize()
	elif phase == 1:
		if bay.state == DockingBay.State.EMPTY:
			_assert(shuttle.wants_dock == false, "release should clear the shuttle's dock request")
			_assert(is_finite(shuttle.position.x) and is_finite(shuttle.position.y), "released position must be finite")
			_finalize()
		elif t > dock_time + bay.dock_duration + 3.0:
			_assert(false, "HOLD timeout -- bay never released (state=%d)" % bay.state)
			_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking <<<")
		get_tree().quit(1)
