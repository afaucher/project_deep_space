extends Node

# M17 acceptance -- end-to-end nav: compute a beacon route, then actually fly it.
# A ship handed NavComputer.route flies through the beacons to a station and the
# autopilot disengages on arrival. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_nav_autopilot
# Needs physics frames. Pass marker per CLAUDE.md.

const NavComputer = preload("res://scripts/nav/nav_computer.gd")
const NavAutopilot = preload("res://scripts/nav/nav_autopilot.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")

const DEST := Vector2(7500, 0)
const TIMEOUT := 35.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false
var ship = null
var autopilot = null
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Nav Autopilot (M17) Tests")

	var def = ClusterDef.new()
	def.bounds = Rect2(-100000, -100000, 200000, 200000)
	for i in range(3):
		def.add_entity({"id": 20 + i, "name": "B" + str(i), "hull": Buoy,
			"kind": ClusterEntity.Kind.BEACON, "pos": Vector2(i * 2500, 0)})
	def.beacon_edges = [[20, 21], [21, 22]]
	def.add_entity({"id": 1, "name": "Depot", "hull": SmallStation,
		"kind": ClusterEntity.Kind.STATION, "pos": DEST})

	ship = Frigate.new()
	ship.name = "Navigator"
	ship.owner_id = 80
	ship.iff_tags = ["TEAM_PLAYER"]
	ship.position = Vector2(-1000, 0)
	main_node.add_child(ship)

	autopilot = NavAutopilot.new()
	ship.add_child(autopilot)
	var route = NavComputer.route(def, ship.position, DEST)
	_assert(route.size() >= 2, "computed route should traverse beacons to the depot (got %d)" % route.size())
	autopilot.engage(route)
	_assert(autopilot.active, "autopilot should engage with a non-empty route")

func _physics_process(delta: float) -> void:
	if finished or ship == null:
		return
	t += delta

	if not autopilot.active:
		# Disengaged -> should be because it arrived at the destination.
		_assert(ship.position.distance_to(DEST) < autopilot.ARRIVAL_RADIUS,
			"autopilot should disengage at the destination (dist=%.0f)" % ship.position.distance_to(DEST))
		_assert(is_finite(ship.position.x) and is_finite(ship.position.y), "arrived position must be finite")
		_finalize()
	elif t > TIMEOUT:
		_assert(false, "TIMEOUT -- autopilot did not reach the destination (dist=%.0f)" % ship.position.distance_to(DEST))
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_nav_autopilot <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_nav_autopilot <<<")
		get_tree().quit(1)
