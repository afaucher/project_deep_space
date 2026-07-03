extends Node

# M18 acceptance -- patrol/route AI. Two frigates on the same square loop, started
# close together: each must follow the route and loop (patrol_index advances
# 0->1->2->3 and wraps to 0), and the closest the two ever come must stay above the
# collision margin (separation keeps moving patrols from slamming). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_patrol
# Pass marker per CLAUDE.md.

const Frigate = preload("res://scripts/ships/frigate.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const ROUTE := [Vector2(1500, 0), Vector2(1500, 1500), Vector2(0, 1500), Vector2(0, 0)]
const NO_SLAM_MIN := 150.0
const TIMEOUT := 35.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var ships: Array = []
var saw_last: Array = [false, false]   # reached the final waypoint index
var looped: Array = [false, false]     # ...then wrapped back to 0
var min_pair: float = INF
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Patrol AI (M18) Tests")
	for i in range(2):
		var s = Frigate.new()
		s.name = "Patrol_%d" % i
		s.owner_id = 70 + i
		s.iff_tags = ["TEAM_PLAYER"]
		s.position = Vector2(250.0 if i == 0 else -250.0, 0.0)   # 500u apart
		s.patrol_route = ROUTE.duplicate()
		s.patrol_loop = true
		main_node.add_child(s)
		s.add_child(AITreeFactory.build_patrol())
		ships.append(s)

func _physics_process(delta: float) -> void:
	if finished or ships.size() < 2:
		return
	t += delta

	var d: float = ships[0].position.distance_to(ships[1].position)
	if d < min_pair:
		min_pair = d

	for i in range(2):
		var idx: int = ships[i].patrol_index
		if idx == ROUTE.size() - 1:
			saw_last[i] = true
		if saw_last[i] and idx == 0:
			looped[i] = true

	if looped[0] and looped[1]:
		_assert(min_pair > NO_SLAM_MIN,
			"patrols came within %.0fu (< %.0f safe) -- they slammed" % [min_pair, NO_SLAM_MIN])
		for s in ships:
			_assert(is_finite(s.position.x) and is_finite(s.position.y), "patrol position must be finite")
		_finalize()
	elif t > TIMEOUT:
		_assert(false, "TIMEOUT -- patrols did not loop (idx=%d/%d, looped=%s)" % [ships[0].patrol_index, ships[1].patrol_index, str(looped)])
		print("Timeout reached. Ship 0 pos: ", ships[0].position, ", idx: ", ships[0].patrol_index)
		print("Timeout reached. Ship 1 pos: ", ships[1].position, ", idx: ", ships[1].patrol_index)
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_patrol <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_patrol <<<")
		get_tree().quit(1)
