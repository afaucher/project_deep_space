extends Node

# M39 acceptance -- MissionLog pure lifecycle + GO_TO_AREA proximity on a real
# ship. implementation_plans/m39_m44_homefront_roadmap.md, "M39 -- Story
# state & mission log". Sequential phases (mirrors test_port_control_comms.gd
# style): most of this is synchronous logic run straight from setup(); the
# GO_TO_AREA proximity check needs real physics frames (MissionLog's own
# _physics_process, 0.5s accumulator), so that part runs as a timed phase.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_mission_log

const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

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

# A Ship is a RigidBody2D -- writing `.position` directly gets clobbered next
# physics tick when the physics server syncs its own transform back onto the
# node. Teleport through PhysicsServer2D directly so the move actually sticks
# (same trick test_port_control_comms.gd's _teleport uses).
func _teleport(ship, pos: Vector2) -> void:
	var xform: Transform2D = ship.global_transform
	xform.origin = pos
	PhysicsServer2D.body_set_state(ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	ship.position = pos

func _make_shuttle(name: String, owner: int, pos: Vector2) -> Node:
	var s = CargoShuttle.new()
	s.name = name
	s.owner_id = owner
	s.iff_tags = ["TEAM_PLAYER"]
	s.position = pos
	main_node.add_child(s)
	return s

func _canned_mission(id: String) -> Dictionary:
	return {
		"id": id,
		"title": "Check on Todd",
		"giver": "aunt_stephanie",
		"objectives": [
			{"id": "find_field", "kind": "GO_TO_AREA", "text": "Search Claim 42's field.", "target": {"center": Vector2(5000, 5000), "radius": 1000.0}},
			{"id": "talk_todd", "kind": "TALK_TO", "text": "Hail Todd.", "target": {"npc": "Todd"}},
			{"id": "deliver_present", "kind": "DELIVER", "text": "Deliver the present to Stephanie.", "target": {"item": "stephanies_present", "npc": "aunt_stephanie"}},
		],
	}

func setup(main) -> void:
	main_node = main
	print("Starting Mission Log (M39) Tests")
	StoryState.reset()

	_run_lifecycle_cases()
	StoryState.reset()

	_run_go_to_area_case()

# ---------------------------------------------------------------------------
# Pure-logic lifecycle cases: duplicate rejection, ordered objective
# completion, TALK_TO, DELIVER gating on StoryState items, mission
# completion, and signal firing.
# ---------------------------------------------------------------------------
func _run_lifecycle_cases() -> void:
	print("--- Lifecycle: start/duplicate/ordering/signals ---")
	var log: Node = MissionLogClass().new()
	main_node.add_child(log)

	var started_ids: Array = []
	var completed_objs: Array = []
	var completed_missions: Array = []
	log.mission_started.connect(func(id): started_ids.append(id))
	log.objective_completed.connect(func(mid, oid): completed_objs.append([mid, oid]))
	log.mission_completed.connect(func(id): completed_missions.append(id))

	var def = _canned_mission("check_on_todd")
	_assert(log.start_mission(def) == true, "start_mission returns true for a fresh id")
	_assert(started_ids.has("check_on_todd"), "mission_started signal fired with the right id")
	_assert(log.start_mission(def) == false, "start_mission rejects a duplicate id")
	_assert(started_ids.count("check_on_todd") == 1, "duplicate start does not re-fire mission_started")

	var mission = log.get_mission("check_on_todd")
	_assert(mission != null, "get_mission returns the started mission")
	_assert(mission["state"] == "ACTIVE", "fresh mission state is ACTIVE")
	_assert(mission["indicators_visible"] == true, "indicators_visible defaults to true")
	_assert(log.active_missions().size() == 1, "active_missions lists the one started mission")

	# Ordering: the active objective must be find_field first -- completing
	# talk_todd or deliver_present out of order must be refused.
	var active_obj: Dictionary = log.get_active_objective("check_on_todd")
	_assert(not active_obj.is_empty() and active_obj["id"] == "find_field", "first active objective is find_field (in-order)")

	_assert(log.complete_objective("check_on_todd", "talk_todd") == false, "completing an out-of-order objective is refused")
	_assert(log.complete_objective("check_on_todd", "deliver_present") == false, "completing a later out-of-order objective is refused")

	_assert(log.complete_objective("check_on_todd", "find_field") == true, "completing the in-order objective (find_field) succeeds")
	_assert(completed_objs.has(["check_on_todd", "find_field"]), "objective_completed signal fired for find_field")

	active_obj = log.get_active_objective("check_on_todd")
	_assert(not active_obj.is_empty() and active_obj["id"] == "talk_todd", "active objective advances to talk_todd")

	# TALK_TO via notify_talked_to.
	_assert(log.notify_talked_to("SomeoneElse") == false, "notify_talked_to for a non-matching npc completes nothing")
	_assert(log.notify_talked_to("Todd") == true, "notify_talked_to('Todd') completes the matching TALK_TO objective")
	_assert(completed_objs.has(["check_on_todd", "talk_todd"]), "objective_completed signal fired for talk_todd")

	active_obj = log.get_active_objective("check_on_todd")
	_assert(not active_obj.is_empty() and active_obj["id"] == "deliver_present", "active objective advances to deliver_present")

	# DELIVER: refused without the item, succeeds with it, consumes it.
	_assert(log.notify_delivered("aunt_stephanie") == false, "notify_delivered refused without the required quest item")
	_assert(log.get_mission("check_on_todd")["state"] == "ACTIVE", "mission still ACTIVE after a refused delivery")

	StoryState.grant_item("stephanies_present")
	_assert(StoryState.has_item("stephanies_present") == true, "StoryState now carries the present")
	_assert(log.notify_delivered("SomeoneElse") == false, "notify_delivered to the wrong npc still refused even with the item")
	_assert(StoryState.has_item("stephanies_present") == true, "a refused delivery to the wrong npc does not consume the item")

	_assert(log.notify_delivered("aunt_stephanie") == true, "notify_delivered succeeds once the item is present and npc matches")
	_assert(StoryState.has_item("stephanies_present") == false, "delivering consumes the quest item")
	_assert(completed_objs.has(["check_on_todd", "deliver_present"]), "objective_completed signal fired for deliver_present")

	_assert(log.get_mission("check_on_todd")["state"] == "COMPLETE", "mission state flips to COMPLETE once the last objective completes")
	_assert(completed_missions.has("check_on_todd"), "mission_completed signal fired")
	_assert(log.active_missions().is_empty(), "active_missions no longer lists the completed mission")

	_free_if_valid(log)

# ---------------------------------------------------------------------------
# GO_TO_AREA proximity: a real ship carrying the log is teleported inside the
# radius -> completes; teleported outside -> does not.
# ---------------------------------------------------------------------------
var go_t: float = 0.0
var go_phase: int = 0
var go_ship = null
const GO_TIMEOUT := 5.0

func _run_go_to_area_case() -> void:
	print("--- GO_TO_AREA proximity on a real ship ---")
	go_ship = _make_shuttle("MissionShip", 500, Vector2(0, 0))

	var def := {
		"id": "area_check",
		"title": "Area Check",
		"giver": "test",
		"objectives": [
			{"id": "reach_area", "kind": "GO_TO_AREA", "text": "Reach the area.", "target": {"center": Vector2(20000, 0), "radius": 1000.0}},
		],
	}
	_assert(go_ship.mission_log.start_mission(def) == true, "GO_TO_AREA case: mission started on the real ship's mission_log")

	# Outside the radius first -- must NOT complete.
	_teleport(go_ship, Vector2(0, 0))
	go_t = 0.0
	go_phase = 0

func _physics_process(delta: float) -> void:
	if finished or go_ship == null:
		return
	go_t += delta
	match go_phase:
		0:
			if go_t > 1.0:
				var obj: Dictionary = go_ship.mission_log.get_active_objective("area_check")
				_assert(not obj.is_empty() and obj["id"] == "reach_area", "GO_TO_AREA case: objective NOT completed while outside the radius")
				# Now teleport inside the radius and let the 0.5s accumulator tick.
				_teleport(go_ship, Vector2(20000, 0))
				go_t = 0.0
				go_phase = 1
		1:
			var mission = go_ship.mission_log.get_mission("area_check")
			if mission != null and mission["state"] == "COMPLETE":
				_assert(true, "GO_TO_AREA case: objective completes once the ship is teleported inside the radius")
				_finish()
			elif go_t > GO_TIMEOUT:
				_assert(false, "GO_TO_AREA case: objective never completed within timeout after entering the radius")
				_finish()

func MissionLogClass() -> GDScript:
	return load("res://scripts/story/mission_log.gd")

func _finish() -> void:
	if finished:
		return
	finished = true
	_free_if_valid(go_ship)
	if failures.is_empty():
		print(">>> [TEST PASSED] test_mission_log <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_mission_log <<<")
		get_tree().quit(1)
