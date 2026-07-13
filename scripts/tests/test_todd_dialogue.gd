extends Node

# M44 (part 1) acceptance -- Todd's conversation
# (dialogue/characters/todd.dialogue, fiction co-authored in-session -- see
# design_ideas/homefront_family.md), driven through the real DialogueManager
# singleton. Mirrors test_stephanie_dialogue's traversal pattern.
#
# Covers:
#   - the M43 placeholder is gone; first contact greets by VOICE ("I know
#     that voice"), never by ship (fiction-fragile -- see the family doc)
#   - first contact sets todd_found and completes the talk_todd objective
#     via missions.notify_talked_to (the designed TALK_TO hook), advancing
#     check_on_todd to deliver_present
#   - the Prell callback line is offered ONLY if the player actually asked
#     Prell about Todd (asked_prell_about_todd, set by prell.dialogue's ask
#     branch -- also covered here), and lands "why I like Prell"
#   - the handoff is DOCK-GATED: undocked gets "dock and I'll hand it
#     over" and no item; docked gets the sealed present granted exactly
#     once (todd_present_given guards re-grant even after the item is
#     later consumed by delivery). The present stays UNDISCLOSED in Todd's
#     dialogue -- the reveal belongs to Stephanie's payoff (see
#     design_ideas/homefront_family.md)
#   - revisit (todd_found set) skips the greeting for the antenna status
#     line and flows straight to the handoff
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_todd_dialogue

const MobileHome = preload("res://scripts/ships/mobile_home.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _find_response(line, needle: String):
	if line == null:
		return null
	for r in line.responses:
		if r.is_allowed and needle in r.text:
			return r
	return null

func setup(main) -> void:
	main_node = main
	print("Starting Todd Dialogue (M44 part 1) Tests")
	StoryState.reset()
	await _run()
	_finish()

func _run() -> void:
	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "DialogueManager singleton not available")
		return
	var dm = Engine.get_singleton("DialogueManager")

	var home = MobileHome.new()
	home.name = "Claim42"
	home.ship_name = "Claim 42"
	home.owner_id = 1
	home.iff_tags = ["TEAM_CIVILIAN"]
	home.position = Vector2.ZERO
	main_node.add_child(home)   # _ready grows the home's open docking bay
	var bay = null
	for c in home.get_children():
		if c is DockingBay:
			bay = c
	_assert(bay != null, "mobile home grows a docking bay (the open dock Todd's handoff gates on)")

	var player = CargoShuttle.new()
	player.name = "Cousin"
	player.owner_id = 300
	player.iff_tags = ["TEAM_PLAYER"]
	player.position = Vector2(800, 0)
	main_node.add_child(player)

	var todd_res = load("res://dialogue/characters/todd.dialogue")
	var prell_res = load("res://dialogue/characters/prell.dialogue")
	_assert(todd_res != null and prell_res != null, "todd/prell dialogue resources load")
	if todd_res == null or prell_res == null:
		return

	# Mission context: accepted, search already completed (talking to Todd
	# means being deep inside the search ring; GO_TO_AREA's auto-complete is
	# test_mission_log's coverage, not re-proven here).
	StoryState.set_flag("todd_mission_accepted")
	player.mission_log.start_mission_by_id("check_on_todd")
	player.mission_log.complete_objective("check_on_todd", "search_field")

	var states: Array = [{"station": home, "player": player, "story": StoryState, "missions": player.mission_log}, DialogueScratch.scratch()]

	# --- Prell first: the ask branch records that the player asked ---
	var p_states: Array = [{"station": home, "player": player, "story": StoryState, "missions": player.mission_log}, DialogueScratch.scratch()]
	var p_line = await dm.get_next_dialogue_line(prell_res, "start", p_states)
	var p_ask = _find_response(p_line, "Todd")
	_assert(p_ask != null, "prell: the Todd question is offered")
	if p_ask != null:
		await dm.get_next_dialogue_line(prell_res, p_ask.next_id, p_states)
	_assert(StoryState.has_flag("asked_prell_about_todd"), "prell: asking sets asked_prell_about_todd (even though Prell stonewalls)")

	# --- First contact: voice greeting, flag + objective wiring ---
	var line = await dm.get_next_dialogue_line(todd_res, "start", states)
	_assert(line != null, "todd: 'start' returns a line")
	if line == null:
		return
	_assert("M44 placeholder" not in line.text, "todd: the placeholder is gone")
	_assert("I know that voice" in line.text, "todd: recognizes the player by VOICE, not ship")

	var greet_resp = _find_response(line, "Three weeks")
	_assert(greet_resp != null, "todd: the 'She did. Three weeks' response is offered")
	if greet_resp == null:
		return
	var l2 = await dm.get_next_dialogue_line(todd_res, greet_resp.next_id, states)
	_assert(StoryState.has_flag("todd_found"), "todd: first contact sets todd_found")
	var active_obj: Dictionary = player.mission_log.get_active_objective("check_on_todd")
	_assert(active_obj.get("id", "") == "deliver_present",
		"todd: talk_todd completes via notify_talked_to, mission advances to deliver_present (got '%s')" % active_obj.get("id", ""))

	# --- Antenna beat -> the Prell callback (flag-gated) ---
	# l2 is his "huh. It has been three weeks" beat; continuing reaches the
	# antenna explanation with its responses.
	var antenna_line = await dm.get_next_dialogue_line(todd_res, l2.next_id, states)
	_assert(antenna_line != null and "Prell" in antenna_line.text, "todd: the antenna line credits Prell with the replacement order")
	var callback = _find_response(antenna_line, "never heard of you")
	_assert(callback != null, "todd: the Prell callback response is offered (asked_prell_about_todd is set)")
	var mine_line = null
	if callback != null:
		var cb_line = await dm.get_next_dialogue_line(todd_res, callback.next_id, states)
		_assert(cb_line != null and "why I like Prell" in cb_line.text, "todd: 'And THAT is why I like Prell.'")
		mine_line = await dm.get_next_dialogue_line(todd_res, cb_line.next_id, states)

	# --- The mine, the question, the offer ---
	_assert(mine_line != null and "eating me alive" in mine_line.text, "todd: the mine explanation (doubles, triples, stripping rigs)")
	if mine_line != null:
		var question_line = await dm.get_next_dialogue_line(todd_res, mine_line.next_id, states)
		_assert(question_line != null and "should have called her" in question_line.text, "todd: 'Do you think I should have called her?'")
		var yes = _find_response(question_line, "Yes")
		_assert(yes != null, "todd: the 'Yes.' answer is offered")
		_assert(_find_response(question_line, "worried") != null, "todd: the gentler answer is offered too")
		if yes != null:
			var offer_line = await dm.get_next_dialogue_line(todd_res, yes.next_id, states)
			_assert(offer_line != null and "something for her" in offer_line.text, "todd: 'Then at least I've got something for her.'")
			if offer_line != null:
				var present_line = await dm.get_next_dialogue_line(todd_res, offer_line.next_id, states)
				_assert(present_line != null and "found one" in present_line.text, "todd: the present line (found in a stripped rig)")
				_assert(present_line != null and "one of these" in present_line.text,
					"todd: the present stays UNDISCLOSED -- 'one of these', never named (the reveal is Stephanie's)")
				if present_line != null:
					# Undocked -> the handoff must gate, not grant.
					var gate_line = await dm.get_next_dialogue_line(todd_res, present_line.next_id, states)
					_assert(gate_line != null and "dock" in gate_line.text, "todd: undocked handoff says to dock first")
					_assert(not StoryState.has_item("stephanies_present"), "todd: no item granted while undocked")

	# --- Dock, revisit: antenna status line, then the grant ---
	if bay != null:
		bay.captured = player
		bay.state = DockingBay.State.DOCKED
		player.docking_bay = bay

	var revisit = await dm.get_next_dialogue_line(todd_res, "start", states)
	_assert(revisit != null and "still on order" in revisit.text, "todd: revisit skips the greeting for the antenna status line")
	if revisit != null:
		var grant_line = await dm.get_next_dialogue_line(todd_res, revisit.next_id, states)
		_assert(grant_line != null and "she opens it first" in grant_line.text,
			"todd: docked handoff hands it over sealed (contents undisclosed)")
		_assert(StoryState.has_item("stephanies_present"), "todd: stephanies_present granted while docked")
		_assert(StoryState.has_flag("todd_present_given"), "todd: todd_present_given set on the grant")

	# --- No re-grant, even after delivery consumes the item ---
	StoryState.remove_item("stephanies_present")   # simulate the later delivery
	var again = await dm.get_next_dialogue_line(todd_res, "start", states)
	if again != null:
		var after = await dm.get_next_dialogue_line(todd_res, again.next_id, states)
		_assert(after != null and "on you now" in after.text, "todd: post-grant revisit gets the it's-on-you line")
	_assert(not StoryState.has_item("stephanies_present"), "todd: the present is NEVER re-granted (todd_present_given guards it)")

	StoryState.reset()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_todd_dialogue <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_todd_dialogue <<<")
		get_tree().quit(1)
