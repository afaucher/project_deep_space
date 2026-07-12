extends Node

# Focused unit coverage for the two docking-resilience mechanisms added with
# the campaign docking-wedge fix (see test_campaign_dock_health.gd for the
# full story and the end-to-end campaign regression):
#
#   1. CAPTURE_TIMEOUT: a capture that can never settle must free the bay
#      (back to EMPTY, wants_dock cleared) instead of wedging it forever.
#      Simulated deterministically by freezing the captured ship so the
#      servo spring can't move it.
#   2. STRUCTURE-tier angular damping: a station set spinning sheds its spin
#      within a few seconds even with NO station-keeping AI attached.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_docking_resilience

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []
var t: float = 0.0
var phase: int = 0

var station = null
var shuttle = null
var bay = null
var spin_station = null
var capture_seen := false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Docking Resilience Tests")

	# --- Scenario 1 setup: frozen ship wedged mid-capture ---
	station = MediumStation.new()
	station.name = "ResilienceStation"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	station.port_zone = {"radius": 8000.0, "authority": "Resilience Control", "style": "AUTOMATED", "rules": {}}
	main.add_child(station)

	shuttle = CargoShuttle.new()
	shuttle.name = "FrozenShuttle"
	shuttle.owner_id = 2
	shuttle.iff_tags = ["TEAM_PLAYER"]
	shuttle.dockable = true
	main.add_child(shuttle)

	var grant = station.issue_docking_grant(shuttle)
	_assert(grant != null, "scenario 1: grant issued")
	if grant == null:
		_finish()
		return
	for b in station.get_berths():
		if b.slip_id == grant.get("slip_id", ""):
			bay = b
	_assert(bay != null, "scenario 1: assigned bay found")

	# Park the shuttle inside the capture cone, then freeze it so the spring
	# can never seat it -- the capture must abort instead of wedging.
	var approach: Vector2 = bay.global_position + Vector2.RIGHT.rotated(bay.global_rotation) * 600.0
	var xform: Transform2D = shuttle.global_transform
	xform.origin = approach
	PhysicsServer2D.body_set_state(shuttle.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	shuttle.position = approach
	shuttle.wants_dock = true
	shuttle.freeze = true

func _physics_process(delta: float) -> void:
	if phase >= 99:
		return
	t += delta

	match phase:
		0:
			# Wait for the capture to begin.
			if bay != null and bay.state == DockingBay.State.CAPTURING:
				capture_seen = true
				phase = 1
			elif t > 5.0:
				_assert(false, "scenario 1: bay never began capturing the parked shuttle")
				phase = 2
		1:
			# Frozen ship can't settle: the bay must free itself within
			# CAPTURE_TIMEOUT (+margin), clearing the ship's wants_dock.
			if bay.state == DockingBay.State.EMPTY:
				_assert(t < DockingBay.CAPTURE_TIMEOUT + 10.0, "scenario 1: bay freed within the timeout window (t=%.1f)" % t)
				_assert(shuttle.wants_dock == false, "scenario 1: aborted capture cleared wants_dock")
				_assert(bay.captured == null, "scenario 1: bay holds no captured ref after abort")
				phase = 2
			elif bay.state == DockingBay.State.DOCKED:
				_assert(false, "scenario 1: a frozen ship should never reach DOCKED")
				phase = 2
			elif t > DockingBay.CAPTURE_TIMEOUT + 15.0:
				_assert(false, "scenario 1: bay still CAPTURING past the timeout -- wedge not fixed")
				phase = 2
		2:
			# --- Scenario 2 setup: spinning AI-less station sheds spin ---
			_assert(capture_seen, "scenario 1: capture was actually exercised")
			spin_station = MediumStation.new()
			spin_station.name = "SpinStation"
			spin_station.owner_id = 3
			spin_station.iff_tags = ["TEAM_PLAYER"]
			spin_station.position = Vector2(60000, 0)
			main_node.add_child(spin_station)
			spin_station.angular_velocity = 0.4   # the observed campaign wedge spin
			t = 0.0
			phase = 3
		3:
			if abs(spin_station.angular_velocity) < 0.05:
				_assert(true, "scenario 2: STRUCTURE angular damping sheds a 0.4 rad/s bump (t=%.1f)" % t)
				phase = 90
			elif t > 15.0:
				_assert(false, "scenario 2: station still spinning at %.3f rad/s after 15s" % spin_station.angular_velocity)
				phase = 90
		90:
			_finish()

func _finish() -> void:
	phase = 99
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_resilience <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_resilience <<<")
		get_tree().quit(1)
