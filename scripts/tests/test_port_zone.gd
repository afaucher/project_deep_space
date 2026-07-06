extends Node

# M31 acceptance -- Port Zone spatial substrate. Covers the 4 roadmap items:
#   1. PortZone.contains geometry (pure fixtures, no scene)
#   2. Enter/exit fire exactly once (edge-detection + hysteresis, not one-per-frame)
#   3. An open station (port_zone == {}) never sets current_port_zone
#   4. Nearest-wins when two controlled zones overlap
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_port_zone
# Pass marker per CLAUDE.md.
#
# Event tally note: main.gd's _distribute_state() clears ship.transient_events
# each frame, but ONLY for ships registered in its `players` dict -- these test
# ships are added directly via main_node.add_child(...), never via
# main_node.players[...], so _distribute_state() never iterates or clears them.
# We still tally defensively per-frame (reading transient_events every physics
# tick and draining into a running counter) so the test doesn't depend on that
# implementation detail either way.

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const PortZone = preload("res://scripts/port/port_zone.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

# A Ship is a RigidBody2D. Writing `.position` directly from a script gets
# clobbered the next physics tick when the physics server syncs its own
# internal transform back onto the node (the server, not the last script
# write, owns the transform for a non-sleeping body). To actually teleport a
# ship across frames (rather than fly it via thrust, which these tests don't
# need -- they're testing zone geometry/edge-detection, not flight feel) we
# have to push the new transform through PhysicsServer2D directly.
func _teleport(ship, pos: Vector2) -> void:
	var xform: Transform2D = ship.global_transform
	xform.origin = pos
	PhysicsServer2D.body_set_state(ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	ship.position = pos # keep the Node2D-side value consistent within this same frame

# ---------------------------------------------------------------------------
# Phase machine. Each phase sets up its own nodes, is driven for some frames by
# _physics_process, then advances. Phases run sequentially (not in parallel)
# so ships from an earlier phase don't leak zone membership into a later one.
# ---------------------------------------------------------------------------
enum Phase {
	GEOMETRY,        # 1: pure PortZone.contains fixtures, no frames needed
	ENTER_EXIT,      # 2: fly a ship across a controlled zone's boundary
	OPEN_STATION,    # 3: an uncontrolled station never sets current_port_zone
	NEAREST_WINS,    # 4: two overlapping zones -> nearer authority wins
	DONE,
}
var phase: int = Phase.GEOMETRY
var t: float = 0.0

# --- Phase 2 state ---
var ee_station = null
var ee_ship = null
var ee_enter_count: int = 0
var ee_exit_count: int = 0
var ee_sub_phase: int = 0   # 0 = fly in, 1 = hold inside, 2 = fly out, 3 = settled outside

# --- Phase 3 state ---
var open_station = null
var open_ship = null

# --- Phase 4 state ---
var near_station_a = null   # farther, bigger zone
var near_station_b = null   # nearer, smaller zone (overlaps A)
var near_ship = null

func setup(main) -> void:
	main_node = main
	print("Starting Port Zone (M31) Tests")
	_run_geometry_phase()

# ---------------------------------------------------------------------------
# Phase 1 -- Geometry (pure, no scene/frames needed)
# ---------------------------------------------------------------------------
func _run_geometry_phase() -> void:
	var center := Vector2(1000.0, -500.0)
	var radius := 2000.0

	# Inside: well within the radius.
	_assert(PortZone.contains(center, radius, center) == true,
		"contains: the center point itself must be inside")
	_assert(PortZone.contains(center, radius, center + Vector2(500.0, 0.0)) == true,
		"contains: a point 500u from center (< 2000u radius) must be inside")

	# Outside: well beyond the radius.
	_assert(PortZone.contains(center, radius, center + Vector2(5000.0, 0.0)) == false,
		"contains: a point 5000u from center (> radius) must be outside")

	# Boundary-minus-epsilon: just inside the edge must read true.
	var just_inside := center + Vector2(radius - 0.5, 0.0)
	_assert(PortZone.contains(center, radius, just_inside) == true,
		"contains: a point radius-0.5u from center must be inside (boundary-minus-epsilon)")

	# Exactly on the boundary is inclusive (<=).
	var on_boundary := center + Vector2(radius, 0.0)
	_assert(PortZone.contains(center, radius, on_boundary) == true,
		"contains: a point exactly at radius must be inside (inclusive boundary)")

	# Just past the boundary must read false.
	var just_outside := center + Vector2(radius + 0.5, 0.0)
	_assert(PortZone.contains(center, radius, just_outside) == false,
		"contains: a point radius+0.5u from center must be outside")

	phase = Phase.ENTER_EXIT
	_setup_enter_exit_phase()

# ---------------------------------------------------------------------------
# Phase 2 -- Enter/exit fire exactly once (edge detection + hysteresis)
# ---------------------------------------------------------------------------
# Station at origin with an 2000u zone (own radius, not the real medium_station
# 8000u default -- shrunk here purely so the test doesn't need to fly absurd
# distances; the geometry/logic under test doesn't care about the magnitude).
const EE_RADIUS := 2000.0
const EE_MARGIN := 200.0 # must match Ship.PORT_ZONE_EXIT_MARGIN

func _setup_enter_exit_phase() -> void:
	t = 0.0
	ee_station = MediumStation.new()
	ee_station.name = "EEStation"
	ee_station.owner_id = 1
	ee_station.iff_tags = ["TEAM_PLAYER"]
	ee_station.position = Vector2.ZERO
	ee_station.port_zone = {"radius": EE_RADIUS, "authority": "Ironhold Control", "rules": {}}
	main_node.add_child(ee_station)

	ee_ship = CargoShuttle.new()
	ee_ship.name = "EEShuttle"
	ee_ship.owner_id = 50
	ee_ship.iff_tags = ["TEAM_PLAYER"]
	# Start well outside the zone (+margin) so phase 0 (fly in) has a clean start.
	ee_ship.position = Vector2(EE_RADIUS + EE_MARGIN + 3000.0, 0.0)
	main_node.add_child(ee_ship)

func _drain_events(ship) -> void:
	for ev in ship.transient_events:
		if ev.get("type", "") == "zone_enter":
			ee_enter_count += 1
		elif ev.get("type", "") == "zone_exit":
			ee_exit_count += 1
	ship.transient_events.clear()

func _step_enter_exit(delta: float) -> void:
	t += delta
	_drain_events(ee_ship)

	match ee_sub_phase:
		0:
			# Fly straight in toward the station, well past the entry radius.
			var target: Vector2 = Vector2(EE_RADIUS * 0.3, 0.0)
			_teleport(ee_ship, ee_ship.position.move_toward(target, 4000.0 * delta))
			if ee_ship.position.distance_to(target) < 10.0:
				ee_sub_phase = 1
				t = 0.0
		1:
			# Hold well inside the zone for a few frames -- must NOT re-fire enter.
			if t > 0.5:
				_assert(ee_enter_count == 1,
					"enter should fire exactly once on crossing in (got %d)" % ee_enter_count)
				_assert(ee_ship.current_port_zone == "Ironhold Control",
					"current_port_zone should be set to the authority name while inside")
				ee_sub_phase = 2
				t = 0.0
		2:
			# Fly straight out past radius + margin (clear of the hysteresis band).
			var target2: Vector2 = Vector2(EE_RADIUS + EE_MARGIN + 3000.0, 0.0)
			_teleport(ee_ship, ee_ship.position.move_toward(target2, 4000.0 * delta))
			if ee_ship.position.distance_to(target2) < 10.0:
				ee_sub_phase = 3
				t = 0.0
		3:
			# Settled well outside -- must NOT re-fire exit, and must have fired
			# exactly once total.
			if t > 0.5:
				_assert(ee_exit_count == 1,
					"exit should fire exactly once on crossing out (got %d)" % ee_exit_count)
				_assert(ee_ship.current_port_zone == null,
					"current_port_zone should clear to null once outside")
				_finish_enter_exit_phase()

func _finish_enter_exit_phase() -> void:
	ee_station.queue_free()
	ee_ship.queue_free()
	phase = Phase.OPEN_STATION
	t = 0.0
	_setup_open_station_phase()

# ---------------------------------------------------------------------------
# Phase 3 -- Open station (port_zone == {}) never sets current_port_zone
# ---------------------------------------------------------------------------
func _setup_open_station_phase() -> void:
	open_station = SmallStation.new()
	open_station.name = "OpenStation"
	open_station.owner_id = 1
	open_station.iff_tags = ["TEAM_PLAYER"]
	open_station.position = Vector2.ZERO
	main_node.add_child(open_station)

	_assert(open_station.get_port_zone().is_empty(),
		"an uncontrolled station's get_port_zone() must be empty by default")

	open_ship = CargoShuttle.new()
	open_ship.name = "OpenShuttle"
	open_ship.owner_id = 51
	open_ship.iff_tags = ["TEAM_PLAYER"]
	# Fly straight through where a zone WOULD be (well within where an 8000u
	# radius would reach) to prove no membership is ever recorded.
	open_ship.position = Vector2(500.0, 0.0)
	main_node.add_child(open_ship)

func _step_open_station(delta: float) -> void:
	t += delta
	open_ship.transient_events.clear() # nothing expected; keep it quiet regardless
	if t > 0.5:
		_assert(open_ship.current_port_zone == null,
			"a ship near an uncontrolled station must never get current_port_zone set")
		open_station.queue_free()
		open_ship.queue_free()
		phase = Phase.NEAREST_WINS
		t = 0.0
		_setup_nearest_wins_phase()

# ---------------------------------------------------------------------------
# Phase 4 -- Nearest wins between two overlapping controlled zones
# ---------------------------------------------------------------------------
func _setup_nearest_wins_phase() -> void:
	near_station_a = MediumStation.new()
	near_station_a.name = "AuthorityFar"
	near_station_a.owner_id = 1
	near_station_a.iff_tags = ["TEAM_PLAYER"]
	near_station_a.position = Vector2(-3000.0, 0.0)
	near_station_a.port_zone = {"radius": 6000.0, "authority": "Authority Far", "rules": {}}
	main_node.add_child(near_station_a)

	near_station_b = MediumStation.new()
	near_station_b.name = "AuthorityNear"
	near_station_b.owner_id = 2
	near_station_b.iff_tags = ["TEAM_PLAYER"]
	near_station_b.position = Vector2(3000.0, 0.0)
	near_station_b.port_zone = {"radius": 6000.0, "authority": "Authority Near", "rules": {}}
	main_node.add_child(near_station_b)

	near_ship = CargoShuttle.new()
	near_ship.name = "NearestShuttle"
	near_ship.owner_id = 52
	near_ship.iff_tags = ["TEAM_PLAYER"]
	# Placed inside BOTH zones (|x|=1000 from each center, well under 6000u) but
	# closer to station B (3000-1000=2000u) than station A (1000+3000=4000u).
	near_ship.position = Vector2(1000.0, 0.0)
	main_node.add_child(near_ship)

func _step_nearest_wins(delta: float) -> void:
	t += delta
	if t > 0.5:
		_assert(near_ship.current_port_zone == "Authority Near",
			"ship inside two overlapping zones must report the NEARER authority (got %s)" % str(near_ship.current_port_zone))
		near_station_a.queue_free()
		near_station_b.queue_free()
		near_ship.queue_free()
		phase = Phase.DONE
		_finalize()

func _physics_process(delta: float) -> void:
	if finished:
		return
	match phase:
		Phase.ENTER_EXIT:
			if ee_station != null and ee_ship != null:
				_step_enter_exit(delta)
		Phase.OPEN_STATION:
			if open_station != null and open_ship != null:
				_step_open_station(delta)
		Phase.NEAREST_WINS:
			if near_station_a != null and near_station_b != null and near_ship != null:
				_step_nearest_wins(delta)
		_:
			pass

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_port_zone <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_port_zone <<<")
		get_tree().quit(1)
