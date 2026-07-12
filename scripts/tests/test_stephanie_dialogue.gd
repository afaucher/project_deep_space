extends Node

# M42 acceptance -- Aunt Stephanie's dialogue (dialogue/characters/aunt_stephanie.dialogue),
# a structural skeleton with EVERY spoken line a bracketed placeholder per the
# HARD CONSTRAINT (fiction is co-authored -- see the roadmap's M44 note),
# driven through the REAL DialogueManager singleton. Mirrors
# test_story_dialogue.gd's traversal pattern and test_repair_services.gd's
# real-docking pattern, but promotes a real Ironhold via ClusterManager with
# the REAL story overlay (scripts/story/home_cluster_overlay.gd) + character
# registry (scripts/story/characters.gd) -- test_story_overlay.gd already
# covers the generic overlay mechanism against synthetics; this proves the
# actual authored content wires together end to end.
#
# Covers:
#   - the mission-offer response is visible before todd_mission_accepted, and
#     the status response is NOT
#   - accepting sets the flag AND starts check_on_todd on the player's real
#     MissionLog (3 objectives, first is GO_TO_AREA)
#   - re-entering 'start' after accepting shows the status response instead
#     of the offer
#   - the repairs branch refuses an undocked player (no active_repairs
#     registration) and registers a docked one (station.begin_repairs via the
#     dialogue mutation, same as M40's direct-call tests)
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_stephanie_dialogue

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const HomeClusterOverlay = preload("res://scripts/story/home_cluster_overlay.gd")
const StoryCharacters = preload("res://scripts/story/characters.gd")
const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")

const DOCK_WAIT_MAX_FRAMES := 900

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _med_bay(st) -> Node:
	for c in st.get_children():
		if c is DockingBay:
			return c
	return null

# NOTE: DialogueManager's line.responses array includes EVERY compiled
# response regardless of its `[if cond /]` gate -- each just carries an
# `is_allowed` bool from evaluating that condition (see
# dialogue_manager.gd's _get_responses()/_check_condition(); filtering is
# left to the caller -- comms_panel.gd's _process_dialogue() now does this
# same is_allowed check before building a button, see the M42 comment
# there). These helpers mirror that: a gated-out response must not be
# treated as "offered".
func _find_response(line, needle: String):
	for r in line.responses:
		if r.is_allowed and needle in r.text:
			return r
	return null

func _find_response_exact(line, text: String):
	for r in line.responses:
		if r.is_allowed and r.text == text:
			return r
	return null

func setup(main) -> void:
	main_node = main
	print("Starting Stephanie Dialogue (M42) Tests")
	StoryState.reset()
	await _run()

func _run() -> void:
	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "stephanie dialogue: DialogueManager singleton not available")
		_finish()
		return

	var manager := ClusterManager.new()
	manager.policy.configure_full_sim()
	manager.live_parent = main_node
	main_node.add_child(manager)

	var def := ClusterDef.new()
	def.name = "Stephanie Test Cluster"
	def.bounds = Rect2(-10000, -10000, 20000, 20000)
	def.player_start = Vector2.ZERO
	def.add_entity({"id": 1, "sid": "ironhold", "name": "Ironhold", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2.ZERO, "iff_tags": ["TEAM_PLAYER"], "is_static": true})

	# The REAL overlay + registry -- proves the actual authored content
	# (scripts/story/home_cluster_overlay.gd's "ironhold" entry, aunt_stephanie
	# in scripts/story/characters.gd) resolves through the full pipeline.
	ClusterLoader.load_into(def, manager, HomeClusterOverlay, StoryCharacters)
	manager.tick(0.0)

	var rec = null
	for r in manager.records:
		if r.id == 1:
			rec = r
	_assert(rec != null and rec.is_live(), "ironhold should be promoted live")
	if rec == null or not rec.is_live():
		_finish()
		return
	var station = rec.live_node

	var stephanie_npc = null
	for npc in station.available_npcs:
		if npc.character_name == "Aunt Stephanie":
			stephanie_npc = npc
	_assert(stephanie_npc != null, "ironhold's available_npcs should include Aunt Stephanie (from the overlay's cast)")
	if stephanie_npc == null:
		_finish()
		return
	var resource = stephanie_npc.default_dialogue
	_assert(resource != null, "Aunt Stephanie's NPCProfile should resolve dialogue/characters/aunt_stephanie.dialogue")
	if resource == null:
		_finish()
		return

	var dm = Engine.get_singleton("DialogueManager")

	var player = CargoShuttle.new()
	player.name = "StephaniePlayer"
	player.owner_id = 300
	player.iff_tags = ["TEAM_PLAYER"]
	player.dockable = true
	player.position = Vector2(50000, 50000)   # far from Ironhold -> undocked
	main_node.add_child(player)

	var states: Array = [{"station": station, "player": player, "story": StoryState, "missions": player.mission_log}, DialogueScratch.scratch()]

	# --- Phase 1: mission offer visible pre-flag, status not yet visible ---
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	_assert(line != null, "stephanie: 'start' cue returns a line")
	if line == null:
		_free_if_valid(player); _finish()
		return

	var offer_resp = _find_response(line, "something's bugging you")
	var status_resp = _find_response(line, "Any word from Todd")
	_assert(offer_resp != null, "stephanie: mission-offer response visible before todd_mission_accepted is set")
	_assert(status_resp == null, "stephanie: status response should NOT be visible before accepting")

	var repairs_resp = _find_response_exact(line, "Ask about repairs.")
	_assert(repairs_resp != null, "stephanie: 'Ask about repairs.' response is offered")

	# --- Phase 2: repairs refused while undocked ---
	if repairs_resp != null:
		var repair_line = await dm.get_next_dialogue_line(resource, repairs_resp.next_id, states)
		_assert(repair_line != null, "stephanie: repairs response yields a reply line")
		_assert(not station.active_repairs.has(player.get_instance_id()), "stephanie: undocked player is not registered for repairs")
		# The conversation must LOOP: continuing past her refusal line drops
		# back into the same menu (greeting line with responses attached),
		# never ending the conversation -- the same regression class as the
		# port-control => END bug (a denied player had to re-hail to retry).
		if repair_line != null:
			var after_refusal = await dm.get_next_dialogue_line(resource, repair_line.next_id, states)
			_assert(after_refusal != null, "stephanie: conversation continues past the repair refusal instead of ending")
			if after_refusal != null:
				_assert(_find_response_exact(after_refusal, "Ask about repairs.") != null,
					"stephanie: after the refusal the menu returns ('Ask about repairs.' offered again)")

	# --- Phase 3a: hearing the pitch does NOT commit -- asking what's wrong
	# must never auto-accept; the mutations moved onto the explicit player
	# accept line ("the player should always have an accept line").
	line = await dm.get_next_dialogue_line(resource, "start", states)
	offer_resp = _find_response(line, "something's bugging you")
	_assert(offer_resp != null, "stephanie: mission-offer response still visible before accepting")
	var pitch_line = null
	if offer_resp != null:
		pitch_line = await dm.get_next_dialogue_line(resource, offer_resp.next_id, states)
		_assert(pitch_line != null, "stephanie: asking yields her pitch line")
		_assert(not StoryState.has_flag("todd_mission_accepted"), "stephanie: hearing the pitch does NOT set the flag")
		_assert(player.mission_log.get_mission("check_on_todd") == null, "stephanie: hearing the pitch does NOT start the mission")
		_assert(pitch_line == null or _find_response(pitch_line, "I'll go check on him") != null,
			"stephanie: the pitch offers an explicit accept line")
		_assert(pitch_line == null or _find_response(pitch_line, "things to do first") != null,
			"stephanie: the pitch offers an explicit decline line")

	# --- Phase 3b: declining leaves everything unset and loops back ---
	if pitch_line != null:
		var decline_resp = _find_response(pitch_line, "things to do first")
		if decline_resp != null:
			var decline_line = await dm.get_next_dialogue_line(resource, decline_resp.next_id, states)
			_assert(decline_line != null, "stephanie: declining yields her comeback line")
			_assert(not StoryState.has_flag("todd_mission_accepted"), "stephanie: declining does NOT set the flag")
			_assert(player.mission_log.get_mission("check_on_todd") == null, "stephanie: declining does NOT start the mission")
			if decline_line != null:
				var after_decline = await dm.get_next_dialogue_line(resource, decline_line.next_id, states)
				_assert(after_decline != null and _find_response(after_decline, "something's bugging you") != null,
					"stephanie: after declining, the menu returns and the offer is still available")

	# --- Phase 3c: explicit accept fires the mutations ---
	line = await dm.get_next_dialogue_line(resource, "start", states)
	offer_resp = _find_response(line, "something's bugging you")
	if offer_resp != null:
		pitch_line = await dm.get_next_dialogue_line(resource, offer_resp.next_id, states)
		var accept_resp = _find_response(pitch_line, "I'll go check on him") if pitch_line != null else null
		_assert(accept_resp != null, "stephanie: accept line present on the second ask too")
		if accept_resp != null:
			var accept_line = await dm.get_next_dialogue_line(resource, accept_resp.next_id, states)
			_assert(accept_line != null, "stephanie: accepting yields a reply line")
			_assert(StoryState.has_flag("todd_mission_accepted"), "stephanie: accepting sets todd_mission_accepted")
			var mission = player.mission_log.get_mission("check_on_todd")
			_assert(mission != null, "stephanie: accepting starts check_on_todd on the player's real mission_log")
			if mission != null:
				_assert(mission["objectives"].size() == 3, "stephanie: check_on_todd should carry 3 objectives, got %d" % mission["objectives"].size())
				if mission["objectives"].size() > 0:
					_assert(mission["objectives"][0]["kind"] == "GO_TO_AREA",
						"stephanie: first objective should be GO_TO_AREA, got '%s'" % mission["objectives"][0]["kind"])

	# --- Phase 4: re-entering start shows the status response instead of the offer ---
	line = await dm.get_next_dialogue_line(resource, "start", states)
	_assert(line != null, "stephanie: re-entering 'start' after accepting returns a line")
	if line != null:
		offer_resp = _find_response(line, "something's bugging you")
		status_resp = _find_response(line, "Any word from Todd")
		_assert(offer_resp == null, "stephanie: mission-offer response should be gone after accepting")
		_assert(status_resp != null, "stephanie: status response should be shown after accepting")

	# --- Phase 5: dock the player and confirm the repairs mutation registers them ---
	await _dock_and_check_repairs(dm, resource, station, player, states)

	_free_if_valid(player)
	StoryState.reset()
	_finish()

func _dock_and_check_repairs(dm, resource, station, player, states) -> void:
	var bay = _med_bay(station)
	_assert(bay != null, "stephanie: station grows a DockingBay")
	if bay == null:
		return

	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	player.position = bay.global_position + fwd * 400.0

	var result: Dictionary = station.request_docking_via_control(player)
	_assert(result.get("outcome", "") == "granted", "stephanie: docking request granted")
	player.wants_dock = true

	var frames := 0
	while bay.state != DockingBay.State.DOCKED and frames < DOCK_WAIT_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1
	_assert(bay.state == DockingBay.State.DOCKED, "stephanie: player should reach DOCKED before checking the repairs branch (state=%d)" % bay.state)
	if bay.state != DockingBay.State.DOCKED:
		return

	var line = await dm.get_next_dialogue_line(resource, "start", states)
	_assert(line != null, "stephanie: 'start' cue still returns a line once docked")
	if line == null:
		return
	var repairs_resp = _find_response_exact(line, "Ask about repairs.")
	_assert(repairs_resp != null, "stephanie: 'Ask about repairs.' still offered while docked")
	if repairs_resp != null:
		await dm.get_next_dialogue_line(resource, repairs_resp.next_id, states)
		_assert(station.active_repairs.has(player.get_instance_id()),
			"stephanie: docked player is registered for repairs after the dialogue mutation")

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_stephanie_dialogue <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_stephanie_dialogue <<<")
		get_tree().quit(1)
