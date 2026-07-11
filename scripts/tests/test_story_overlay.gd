extends Node

# M42 acceptance -- the story overlay MECHANISM itself
# (implementation_plans/m39_m44_homefront_roadmap.md, "Story data
# architecture: the overlay" + "M42 -- Characters v1"). A SYNTHETIC overlay +
# character registry (not the real Ironhold content -- test_stephanie_dialogue
# covers that) driven through the real ClusterLoader -> ClusterManager
# pipeline against TWO promoted MediumStation entities plus one MobileHome,
# mirroring test_campaign_docking_isolation.gd's setup (a real manager, real
# _promote(), distinct per-instance identity -- the exact trap the port-
# authority rebrand fixed, now extended to casts/patches/overrides).
#
# Covers:
#   - distinct casts land on the right stations (character_name + resolved
#     dialogue resource), and do NOT bleed onto the other station
#   - cast injection APPENDS -- MediumStation's self-appended port-control
#     NPC survives
#   - a port patch lands (services.repairs == "free") AND the rebranded
#     authority survives it (patch must not clobber "Station A Control")
#   - a synthetic component_overrides entry collapses a MobileHome's
#     comms_array range
#   - the cast NPC shows up in the live transponder broadcast
#     (get_active_transponder_data())
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_story_overlay

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const MobileHome = preload("res://scripts/ships/mobile_home.gd")

# Synthetic character registry -- same static interface as
# scripts/story/characters.gd (get_character(id) -> Dictionary), deliberately
# NOT the real one, so this test exercises the generic mechanism rather than
# duplicating test_stephanie_dialogue's real-content coverage.
class SyntheticCharacters:
	extends RefCounted
	static func get_character(id: String) -> Dictionary:
		var reg := {
			"char_a": {"name": "Test Char A", "role": "tester", "dialogue": "res://dialogue/port_control.dialogue"},
			"char_b": {"name": "Test Char B", "role": "tester", "dialogue": "res://dialogue/port_control.dialogue"},
		}
		return reg.get(id, {})

# Synthetic overlay -- same static interface as
# scripts/story/home_cluster_overlay.gd (get_entry(sid) -> Dictionary).
class SyntheticOverlay:
	extends RefCounted
	static func get_entry(sid: String) -> Dictionary:
		var ov := {
			"station_a": {"cast": ["char_a"], "port": {"services": {"repairs": "free"}}},
			"station_b": {"cast": ["char_b"]},
			"home_x": {"component_overrides": {"comms_array": {"range": 1500.0}}},
		}
		return ov.get(sid, {})

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("Starting Story Overlay (M42) Tests")

	var manager := ClusterManager.new()
	manager.policy.configure_full_sim()
	manager.live_parent = main
	main.add_child(manager)

	var def := ClusterDef.new()
	def.name = "Overlay Test Cluster"
	def.bounds = Rect2(-10000, -10000, 200000, 200000)
	def.player_start = Vector2.ZERO
	def.add_entity({"id": 1, "sid": "station_a", "name": "Station A", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(0, 0), "iff_tags": [], "is_static": true})
	def.add_entity({"id": 2, "sid": "station_b", "name": "Station B", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(50000, 0), "iff_tags": [], "is_static": true})
	def.add_entity({"id": 3, "sid": "home_x", "name": "Home X", "hull": MobileHome,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(100000, 0), "iff_tags": ["TEAM_CIVILIAN"], "is_static": true})
	# An unreferenced station (no sid) must take the overlay no-op fast path cleanly.
	def.add_entity({"id": 4, "name": "Station Plain", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(150000, 0), "iff_tags": [], "is_static": true})

	ClusterLoader.load_into(def, manager, SyntheticOverlay, SyntheticCharacters)
	manager.tick(0.0)

	var rec_a = _rec(manager, 1)
	var rec_b = _rec(manager, 2)
	var rec_x = _rec(manager, 3)
	var rec_plain = _rec(manager, 4)
	_assert(rec_a != null and rec_a.is_live(), "station A should be promoted live")
	_assert(rec_b != null and rec_b.is_live(), "station B should be promoted live")
	_assert(rec_x != null and rec_x.is_live(), "home X should be promoted live")
	_assert(rec_plain != null and rec_plain.is_live(), "the unreferenced (no-sid) station should still promote fine")
	if rec_a == null or rec_b == null or rec_x == null or rec_plain == null:
		_finish()
		return

	var node_a = rec_a.live_node
	var node_b = rec_b.live_node
	var node_x = rec_x.live_node
	var node_plain = rec_plain.live_node

	# --- Distinct casts land on the right stations, no bleed ---
	var found_a = _find_npc(node_a.available_npcs, "Test Char A")
	var found_b = _find_npc(node_b.available_npcs, "Test Char B")
	_assert(found_a != null, "station A's available_npcs should include Test Char A")
	_assert(found_b != null, "station B's available_npcs should include Test Char B")
	_assert(_find_npc(node_a.available_npcs, "Test Char B") == null, "station A must NOT carry station B's cast")
	_assert(_find_npc(node_b.available_npcs, "Test Char A") == null, "station B must NOT carry station A's cast")
	# node_plain is a MediumStation too, so it still self-appends its own
	# port-control NPC (available_npcs won't be empty) -- the overlay
	# mechanism just must not add any of the synthetic test cast to it.
	_assert(_find_npc(node_plain.available_npcs, "Test Char A") == null and _find_npc(node_plain.available_npcs, "Test Char B") == null,
		"the unreferenced (no-sid) station should gain no synthetic cast")
	if found_a != null:
		_assert(found_a.default_dialogue != null, "Test Char A's NPCProfile should resolve a dialogue resource")

	# --- Cast injection must APPEND, not clobber MediumStation's self-appended port-control NPC ---
	var port_control_present := false
	for npc in node_a.available_npcs:
		if npc.character_name != "Test Char A":
			port_control_present = true
	_assert(port_control_present, "station A's port-control NPC must survive cast injection (append, not clobber)")

	# --- Port patch lands AND rebranded authority survives it ---
	var zone_a: Dictionary = node_a.get_port_zone()
	_assert(zone_a.get("authority", "") == "Station A Control",
		"station A's rebranded authority must survive the overlay port patch, got '%s'" % zone_a.get("authority", ""))
	var services: Dictionary = zone_a.get("services", {})
	_assert(services.get("repairs", "") == "free", "station A's port_zone should carry the overlay's services.repairs == 'free' patch")
	var zone_b: Dictionary = node_b.get_port_zone()
	_assert(not zone_b.has("services"), "station B (no port patch authored) should not gain a services key")

	# --- component_overrides lands on the node's component dict ---
	var comp: Dictionary = node_x.get_component("comms_array")
	_assert(not comp.is_empty(), "home X should have a comms_array component")
	_assert(comp.get("range", -1.0) == 1500.0,
		"home X's comms_array range should be overridden to 1500.0, got %s" % str(comp.get("range", -1.0)))

	# --- Transponder broadcast includes the cast NPC ---
	var t_data: Dictionary = node_a.get_active_transponder_data()
	var npc_names: Array = []
	for n in t_data.get("npcs", []):
		npc_names.append(n.get("name", ""))
	_assert("Test Char A" in npc_names, "station A's transponder broadcast should include the cast NPC 'Test Char A'")

	_finish()

func _find_npc(npcs, cname: String):
	for n in npcs:
		if n.character_name == cname:
			return n
	return null

func _rec(m, id: int):
	for r in m.records:
		if r.id == id:
			return r
	return null

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_story_overlay <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_story_overlay <<<")
		get_tree().quit(1)
