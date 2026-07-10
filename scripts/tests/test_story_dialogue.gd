extends Node

# M39 acceptance -- story state + mission log driven through the REAL
# DialogueManager singleton, mirroring test_port_control_comms.gd's
# "dialogue traversal" pattern (implementation_plans/m39_m44_homefront_roadmap.md,
# "M39 -- Story state & mission log": "a dialogue-driven test where a
# .dialogue mutation starts a mission and a later condition branches on a
# story flag").
#
# dialogue/test_story.dialogue's "Check on Todd for me." response mutation
# does:
#   do story.set_flag("todd_mission_offered")
#   do missions.start_mission(station.canned_mission())
#
# DialogueManager mutation expressions don't reliably parse an inline
# Dictionary literal (nested {center: Vector2(...), ...} target dicts
# especially), so per the brief we expose a test helper method
# (`canned_mission()`) on the "station" test object handed into
# extra_game_states -- the exact shape port_control.dialogue already uses
# (`do result = station.request_docking_via_control(player)`): a `do` line
# calling a method that does the real work, not inline literals.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_story_dialogue

const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

# Minimal stand-in for "the station/NPC host" extra_game_states slot --
# mirrors how port_control.dialogue's tests hand in a real MediumStation, but
# here we only need one canned-mission-returning method, not a whole station.
class TestMissionGiver:
	extends Node
	func canned_mission() -> Dictionary:
		return {
			"id": "check_on_todd",
			"title": "Check on Todd",
			"giver": "aunt_stephanie",
			"objectives": [
				{"id": "find_field", "kind": "GO_TO_AREA", "text": "Search Claim 42's field.", "target": {"center": Vector2(5000, 5000), "radius": 1000.0}},
				{"id": "talk_todd", "kind": "TALK_TO", "text": "Hail Todd.", "target": {"npc": "Todd"}},
			],
		}

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _make_shuttle(name: String, owner: int, pos: Vector2) -> Node:
	var s = CargoShuttle.new()
	s.name = name
	s.owner_id = owner
	s.iff_tags = ["TEAM_PLAYER"]
	s.position = pos
	main_node.add_child(s)
	return s

func setup(main) -> void:
	main_node = main
	print("Starting Story Dialogue (M39) Tests")
	StoryState.reset()
	await _run_dialogue_flow()

func _run_dialogue_flow() -> void:
	print("--- Dialogue traversal: story flag + mission grant via DialogueManager ---")

	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "story dialogue: DialogueManager singleton not available")
		_finalize()
		return

	var giver := TestMissionGiver.new()
	main_node.add_child(giver)
	var player = _make_shuttle("StoryDialoguePlayer", 300, Vector2(9999, 9999))

	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/test_story.dialogue")
	_assert(resource != null, "story dialogue: test_story.dialogue loads")
	if resource == null:
		_free_if_valid(giver); _free_if_valid(player)
		_finalize()
		return

	var states: Array = [{"station": giver, "player": player, "story": StoryState, "missions": player.mission_log}]

	# Before accepting: no flag, no mission.
	_assert(StoryState.has_flag("todd_mission_offered") == false, "story dialogue: flag not set before the conversation")
	_assert(player.mission_log.get_mission("check_on_todd") == null, "story dialogue: mission not started before the conversation")

	var line = await dm.get_next_dialogue_line(resource, "start", states)
	_assert(line != null, "story dialogue: 'start' cue returns a line")
	if line == null:
		_free_if_valid(giver); _free_if_valid(player)
		_finalize()
		return

	var accept_resp = null
	for r in line.responses:
		if r.text == "Check on Todd for me.":
			accept_resp = r
	_assert(accept_resp != null, "story dialogue: a 'Check on Todd for me.' response is offered")
	if accept_resp == null:
		_free_if_valid(giver); _free_if_valid(player)
		_finalize()
		return

	var line2 = await dm.get_next_dialogue_line(resource, accept_resp.next_id, states)
	_assert(line2 != null, "story dialogue: accepting yields a reply line")

	# THE mutations: the flag is set and the mission is started on the
	# player's real MissionLog, driven entirely through DialogueManager.
	_assert(StoryState.has_flag("todd_mission_offered") == true, "story dialogue: 'do story.set_flag(...)' set the flag")
	var mission = player.mission_log.get_mission("check_on_todd")
	_assert(mission != null, "story dialogue: 'do missions.start_mission(...)' started the mission on the player's mission_log")
	if mission != null:
		_assert(mission["state"] == "ACTIVE", "story dialogue: started mission is ACTIVE")
		_assert(mission["objectives"].size() == 2, "story dialogue: started mission carries both canned objectives")

	# A later conditional line branches on the story flag (the "status_check"
	# cue): with the flag set, it should read the "still owe me a visit" line,
	# not the "everything's quiet" default.
	var status_line = await dm.get_next_dialogue_line(resource, "status_check", states)
	_assert(status_line != null, "story dialogue: 'status_check' cue returns a line")
	if status_line != null:
		_assert("still owe me a visit" in status_line.text, "story dialogue: condition branches on story.has_flag(...) to the post-accept text (got: '%s')" % status_line.text)

	_free_if_valid(giver); _free_if_valid(player)
	_finalize()

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_story_dialogue <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_story_dialogue <<<")
		get_tree().quit(1)
