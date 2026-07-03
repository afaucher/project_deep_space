extends Node

# M20 acceptance -- cargo runs (patrol + docking). One shuttle, two nearby
# stations, looping lane. The shuttle must complete a full dock at BOTH stations:
# fly a leg, get captured/held/released at one, transit to the other, dock there
# too. Proves the transit -> dock -> unload -> depart -> repeat cycle end to end.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_cargo_run
# Pass marker per CLAUDE.md.

const SmallStation = preload("res://scripts/ships/small_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const STATION_A := Vector2(0, 0)
const STATION_B := Vector2(8000, 0)
const TIMEOUT := 50.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var shuttle = null
var docked_stations := {}     # set of lane indices where a dock completed
var prev_docking := false
var docking_station := -1
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Cargo Run (M20) Tests")

	for pos in [STATION_A, STATION_B]:
		var st = SmallStation.new()
		st.owner_id = 1
		st.iff_tags = ["TEAM_PLAYER"]
		st.position = pos
		main_node.add_child(st)

	shuttle = CargoShuttle.new()
	shuttle.name = "Hauler"
	shuttle.owner_id = 60
	shuttle.iff_tags = ["TEAM_PLAYER"]
	shuttle.position = Vector2(4500, 0)     # in transit, outside A's request radius
	shuttle.patrol_route = [STATION_A, STATION_B]
	shuttle.patrol_loop = true
	main_node.add_child(shuttle)
	shuttle.add_child(AITreeFactory.build_cargo())

func _physics_process(delta: float) -> void:
	if finished or shuttle == null:
		return
	t += delta

	# A dock "completes" when cargo_docking falls from true to false (bay released
	# us and we advanced). Record which lane station it was.
	var docking: bool = shuttle.cargo_docking
	if docking and not prev_docking:
		docking_station = shuttle.patrol_index
	if prev_docking and not docking:
		docked_stations[docking_station] = true
	prev_docking = docking

	if docked_stations.has(0) and docked_stations.has(1):
		_assert(is_finite(shuttle.position.x) and is_finite(shuttle.position.y), "shuttle position must be finite")
		_finalize()
	elif t > TIMEOUT:
		_assert(false, "TIMEOUT -- shuttle did not dock at both stations (docked=%s, idx=%d, docking=%s)" % [str(docked_stations.keys()), shuttle.patrol_index, str(shuttle.cargo_docking)])
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_cargo_run <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_cargo_run <<<")
		get_tree().quit(1)
