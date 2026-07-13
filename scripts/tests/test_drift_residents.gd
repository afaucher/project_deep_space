extends Node

# M43 acceptance -- the Drift residents & the silent home
# (implementation_plans/m39_m44_homefront_roadmap.md, "M43" incl. the
# revised-at-pickup notes). The REAL story overlay/registry content
# (scripts/story/home_cluster_overlay.gd, scripts/story/characters.gd)
# driven through the real ClusterLoader -> ClusterManager pipeline, plus the
# real home_cluster.gd geometry checked at the def level. test_story_overlay
# covers the generic overlay MECHANISM against synthetics; this proves the
# authored M43 content.
#
# Covers:
#   1. Def geometry: all five homes sit inside the expanded Slag Bay field,
#      and the check_on_todd search ring covers every home.
#   2. Overlay application on promoted homes: right resident on the right
#      home (dialogue resolved), anonymous homes broadcast "UNKNOWN" (with
#      their NPC still riding along -- hailable, just nameless), named homes
#      broadcast their names, Claim 42's comms range is collapsed to 1500.
#   3. Live datalink: an observer 5000u from Claim 42 never receives its
#      transponder (silent -- CAN'T talk) while receiving the anonymous
#      home's "UNKNOWN" broadcast at range (WON'T talk); an observer inside
#      1500u receives Claim 42 by name. Todd's home classifies as a VESSEL,
#      never WRECKAGE (EM-loud -- reactor on, only the transmitter is dead).
#   4. Dialogue gating through the real DialogueManager: breadcrumb/Todd
#      responses hidden before todd_mission_accepted, offered after (Wex's
#      reply carries the buried clue; Prell's nested brush-off traverses).
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_drift_residents

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const MobileHome = preload("res://scripts/ships/mobile_home.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const HomeClusterOverlay = preload("res://scripts/story/home_cluster_overlay.gd")
const StoryCharacters = preload("res://scripts/story/characters.gd")
const MissionCatalog = preload("res://scripts/story/mission_catalog.gd")
const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")

# Home entity ids in home_cluster.gd.
const HOME_IDS := [200, 201, 202, 203, 204]
const DATALINK_SETTLE_FRAMES := 60

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

# Same is_allowed-filtering rule as test_stephanie_dialogue/_port_control_comms:
# line.responses always contains every compiled response; a gated-out one just
# carries is_allowed=false. A gated response must not read as "offered".
func _find_response(line, needle: String):
	for r in line.responses:
		if r.is_allowed and needle in r.text:
			return r
	return null

func setup(main) -> void:
	main_node = main
	print("Starting Drift Residents (M43) Tests")
	StoryState.reset()
	_run_def_geometry_check()
	await _run_live_cluster_checks()
	_finish()

# ---------------------------------------------------------------------------
# 1. Def-level geometry: the real home_cluster.gd authored layout.
# ---------------------------------------------------------------------------
func _run_def_geometry_check() -> void:
	print("--- Def geometry: five homes inside the expanded Slag Bay field ---")
	var def = HomeCluster.build()

	_assert(def.asteroid_fields.size() >= 1, "home cluster authors at least one asteroid field")
	if def.asteroid_fields.is_empty():
		return
	var field: Dictionary = def.asteroid_fields[0]
	var center: Vector2 = field["center"]
	var radius: float = field["radius"]
	_assert(radius >= 16000.0, "Slag Bay field expanded to at least 16k (got %.0f)" % radius)

	var search: Dictionary = MissionCatalog.get_mission("check_on_todd")["objectives"][0]["target"]
	_assert(search["center"] == center, "check_on_todd search ring is centered on the Slag Bay field")

	var homes_found: int = 0
	for e in def.entities:
		if not (e.get("id", -1) in HOME_IDS):
			continue
		homes_found += 1
		var d: float = center.distance_to(e["pos"])
		_assert(d <= radius, "%s sits inside the field (%.0fu of %.0fu)" % [e["name"], d, radius])
		_assert(d <= search["radius"], "%s sits inside the check_on_todd search ring" % e["name"])
	_assert(homes_found == 5, "all five homes are authored (found %d)" % homes_found)

# ---------------------------------------------------------------------------
# 2 + 3 + 4. Promote the five homes (real sids, real overlay/registry) into a
# compact synthetic layout sized for the datalink-range assertions, run the
# live checks, then the DialogueManager gating checks.
# ---------------------------------------------------------------------------
func _run_live_cluster_checks() -> void:
	print("--- Live cluster: overlay application, datalink range gate, classification ---")
	var manager := ClusterManager.new()
	manager.policy.configure_full_sim()
	manager.live_parent = main_node
	main_node.add_child(manager)

	# Real sids + real overlay content; SYNTHETIC positions -- Claim 42 at the
	# origin with the others spread 8k+ away, so observer distances below are
	# exact and no other home confounds the range assertions.
	var def := ClusterDef.new()
	def.name = "Drift Residents Test Cluster"
	def.bounds = Rect2(-50000, -50000, 100000, 100000)
	def.player_start = Vector2.ZERO
	var homes := {
		"claim_42": {"id": 201, "name": "Claim 42", "pos": Vector2.ZERO},
		"hermits_rest": {"id": 200, "name": "Hermit's Rest", "pos": Vector2(8000, 0)},
		"deep_freeze": {"id": 202, "name": "The Deep Freeze", "pos": Vector2(-8000, 0)},
		"lucky_strike": {"id": 203, "name": "Lucky Strike", "pos": Vector2(0, 8000)},
		"rock_bottom": {"id": 204, "name": "Rock Bottom", "pos": Vector2(8000, 8000)},
	}
	for sid in homes.keys():
		var h: Dictionary = homes[sid]
		def.add_entity({"id": h["id"], "sid": sid, "name": h["name"], "hull": MobileHome,
			"kind": ClusterEntity.Kind.STATION, "pos": h["pos"], "iff_tags": ["TEAM_CIVILIAN"], "is_static": true})

	ClusterLoader.load_into(def, manager, HomeClusterOverlay, StoryCharacters)
	manager.tick(0.0)

	var nodes := {}
	for r in manager.records:
		if r.is_live():
			for sid in homes.keys():
				if homes[sid]["id"] == r.id:
					nodes[sid] = r.live_node
	_assert(nodes.size() == 5, "all five homes promoted live (got %d)" % nodes.size())
	if nodes.size() != 5:
		return

	# --- Overlay application: right resident on the right home ---
	var expected_cast := {
		"hermits_rest": "Mae & Gus", "deep_freeze": "Wex",
		"lucky_strike": "Dost", "rock_bottom": "Prell", "claim_42": "Todd",
	}
	for sid in expected_cast.keys():
		var npc = _find_npc(nodes[sid].available_npcs, expected_cast[sid])
		_assert(npc != null, "%s's cast includes %s" % [sid, expected_cast[sid]])
		if npc != null:
			_assert(npc.default_dialogue != null, "%s's dialogue resource resolves" % expected_cast[sid])

	# --- Broadcast shape: named vs anonymous vs collapsed ---
	var t_named: Dictionary = nodes["hermits_rest"].get_active_transponder_data()
	_assert(t_named.get("name", "") == "Hermit's Rest", "named home broadcasts its ship name (got '%s')" % t_named.get("name", ""))
	for sid in ["lucky_strike", "rock_bottom"]:
		var t_anon: Dictionary = nodes[sid].get_active_transponder_data()
		_assert(t_anon.get("name", "") == "UNKNOWN", "%s broadcasts 'UNKNOWN' (got '%s')" % [sid, t_anon.get("name", "")])
		var npc_names: Array = []
		for n in t_anon.get("npcs", []):
			npc_names.append(n.get("name", ""))
		_assert(expected_cast[sid] in npc_names, "%s's resident still rides the anonymous broadcast (hailable)" % sid)
	_assert(nodes["claim_42"].get_comms_range() == 1500.0,
		"Claim 42's comms range is collapsed to 1500 (got %.0f)" % nodes["claim_42"].get_comms_range())

	# --- Live datalink: two observers, the range gate in actual physics ---
	var far_obs = _spawn_observer("FarObserver", 400, Vector2(5000, 0))    # 5000u from Claim 42
	var near_obs = _spawn_observer("NearObserver", 401, Vector2(1000, 0)) # 1000u from Claim 42
	for i in range(DATALINK_SETTLE_FRAMES):
		await main_node.get_tree().physics_frame

	var claim_iid: int = nodes["claim_42"].get_instance_id()
	_assert(not far_obs.active_transponders.has(claim_iid),
		"5000u out: Claim 42's transponder is NOT received (silent home -- CAN'T talk)")
	var anon_iid: int = nodes["lucky_strike"].get_instance_id()
	var far_anon: Dictionary = far_obs.active_transponders.get(anon_iid, {})
	_assert(far_anon.get("name", "") == "UNKNOWN",
		"5000u+ out: the anonymous home IS received, as 'UNKNOWN' (won't talk, but answers)")
	var near_claim: Dictionary = near_obs.active_transponders.get(claim_iid, {})
	_assert(near_claim.get("name", "") == "Claim 42",
		"inside 1500u: Claim 42's transponder appears, by name (got '%s')" % near_claim.get("name", ""))

	# --- Classification: Todd's home reads as a live VESSEL, never WRECKAGE ---
	var claim_contact: Dictionary = {}
	for c in far_obs.active_contacts.values():
		if c.get("instance_id", -1) == claim_iid:
			claim_contact = c
	_assert(not claim_contact.is_empty(), "5000u out: Claim 42 shows up as a sensor contact at all")
	if not claim_contact.is_empty():
		var cls: String = claim_contact.get("classification", "")
		_assert("VESSEL" in cls, "Claim 42 classifies as a VESSEL (got '%s')" % cls)
		_assert("WRECKAGE" not in cls, "Claim 42 must never read as WRECKAGE (reactor's on; only the transmitter is dead)")

	await _run_dialogue_gating_checks(nodes, near_obs)

	_free_if_valid(far_obs)
	_free_if_valid(near_obs)

# ---------------------------------------------------------------------------
# 4. Breadcrumb gating through the real DialogueManager.
# ---------------------------------------------------------------------------
func _run_dialogue_gating_checks(nodes: Dictionary, player) -> void:
	print("--- Dialogue gating: breadcrumbs mission-gated, clue traverses ---")
	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "DialogueManager singleton not available")
		return
	var dm = Engine.get_singleton("DialogueManager")

	var wex_res = _find_npc(nodes["deep_freeze"].available_npcs, "Wex").default_dialogue
	var prell_res = _find_npc(nodes["rock_bottom"].available_npcs, "Prell").default_dialogue

	# Before the flag: no Todd questions anywhere.
	StoryState.reset()
	var states: Array = [{"station": nodes["deep_freeze"], "player": player, "story": StoryState, "missions": player.mission_log}, DialogueScratch.scratch()]
	var line = await dm.get_next_dialogue_line(wex_res, "start", states)
	_assert(line != null, "wex: 'start' returns a line")
	if line != null:
		_assert(_find_response(line, "Todd") == null, "wex: no Todd question offered before the mission is accepted")
		_assert(_find_response(line, "passing through") != null, "wex: small talk offered regardless of mission state")

	# After the flag: the breadcrumb opens, and Wex's reply carries the clue.
	StoryState.set_flag("todd_mission_accepted")
	line = await dm.get_next_dialogue_line(wex_res, "start", states)
	var ask = _find_response(line, "Todd") if line != null else null
	_assert(ask != null, "wex: 'Ask about Todd.' offered once the mission is accepted")
	if ask != null:
		var reply = await dm.get_next_dialogue_line(wex_res, ask.next_id, states)
		_assert(reply != null, "wex: asking yields his rambling reply")
		if reply != null:
			_assert("spinward" in reply.text and "storm" in reply.text,
				"wex: the reply buries the real clue (snapped antenna, spinward edge)")

	# Prell's nested brush-off traverses end to end.
	var p_states: Array = [{"station": nodes["rock_bottom"], "player": player, "story": StoryState, "missions": player.mission_log}, DialogueScratch.scratch()]
	var p_line = await dm.get_next_dialogue_line(prell_res, "start", p_states)
	var p_ask = _find_response(p_line, "Todd") if p_line != null else null
	_assert(p_ask != null, "prell: the Todd question is offered once the mission is accepted")
	if p_ask != null:
		var p_reply = await dm.get_next_dialogue_line(prell_res, p_ask.next_id, p_states)
		_assert(p_reply != null and "Don't know him" in p_reply.text, "prell: doesn't know Todd")
		var press = _find_response(p_reply, "lives in this field") if p_reply != null else null
		_assert(press != null, "prell: the press-further response is offered")
		if press != null:
			var p_final = await dm.get_next_dialogue_line(prell_res, press.next_id, p_states)
			_assert(p_final != null and "We done" in p_final.text, "prell: pressing gets the brush-off, conversation over")

	StoryState.reset()

func _spawn_observer(name: String, owner: int, pos: Vector2):
	var s = CargoShuttle.new()
	s.name = name
	s.owner_id = owner
	s.iff_tags = ["TEAM_PLAYER"]
	s.position = pos
	main_node.add_child(s)
	return s

func _find_npc(npcs, cname: String):
	for n in npcs:
		if n.character_name == cname:
			return n
	return null

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_drift_residents <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_drift_residents <<<")
		get_tree().quit(1)
