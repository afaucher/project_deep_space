extends Node

# M53a Pass 2 -- proves a PEER-flagged hauler (Meridian Combine, not home)
# works end to end with port control: fly a leg, get captured/held/released
# at one station, transit, dock at the other too. Same shape as
# test_cargo_run.gd (M20 acceptance), swapped to the peer identity the two
# new colonies actually use (home_cluster.gd's Halvorsen Claim/Corvus Yards
# lanes): OreShuttle hull, FLAG_MERIDIAN transponder, TEAM_MERIDIAN crypto --
# confirms the docking/port-control path doesn't secretly assume home
# identity anywhere.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_meridian_cargo_run
# Pass marker per CLAUDE.md.

const SmallStation = preload("res://scripts/ships/small_station.gd")
const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const MERIDIAN_IFF := ["TEAM_MERIDIAN"]
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
	print("Starting Meridian Cargo Run (M53a) Tests")

	for pos in [STATION_A, STATION_B]:
		var st = SmallStation.new()
		st.owner_id = 13
		st.iff_tags = MERIDIAN_IFF
		st.warrant_authority = [Standing.FLAG_MERIDIAN]   # M52b default-to-own-flag
		st.position = pos
		main_node.add_child(st)
		st.set_transponder_flag(Standing.FLAG_MERIDIAN)

	shuttle = OreShuttle.new()
	shuttle.name = "Meridian Runner"
	shuttle.owner_id = 702
	shuttle.iff_tags = MERIDIAN_IFF
	shuttle.position = Vector2(4500, 0)     # in transit, outside A's request radius
	shuttle.patrol_route = [STATION_A, STATION_B]
	shuttle.patrol_loop = true
	main_node.add_child(shuttle)
	shuttle.set_transponder_flag(Standing.FLAG_MERIDIAN)
	shuttle.add_child(AITreeFactory.build_cargo())

var test_ticks = 0
func _physics_process(delta: float) -> void:
	if finished or shuttle == null:
		return
	t += delta
	test_ticks += 1
	if test_ticks % 60 == 0:
		print("Tick: ", test_ticks, " Pos: ", shuttle.position, " Bay: ", shuttle.docking_bay, " CargoDocking: ", shuttle.cargo_docking)

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
		var transponder: Dictionary = shuttle.get_active_transponder_data()
		_assert(transponder.get("flag", "") == Standing.FLAG_MERIDIAN, "shuttle should keep flying its peer flag throughout the run, got " + str(transponder))
		_finalize()
	elif t > TIMEOUT:
		_assert(false, "TIMEOUT -- shuttle did not dock at both stations (docked=%s, idx=%d, docking=%s)" % [str(docked_stations.keys()), shuttle.patrol_index, str(shuttle.cargo_docking)])
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_meridian_cargo_run <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_meridian_cargo_run <<<")
		get_tree().quit(1)
