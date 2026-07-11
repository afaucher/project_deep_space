extends Node

# M41 acceptance -- ContractFeed pure data assertions.
# implementation_plans/m39_m44_homefront_roadmap.md, "M41 -- Objective
# indicators: contracts are NAV-layer data". Pure-logic test, no scene/physics
# needed (mirrors test_mission_log.gd's lifecycle-case style): a MissionLog
# node + a synthetic ClusterManager holding one sid'd record. Rendering
# itself is NOT tested here (eyeball-verified convention for panel layers per
# CLAUDE.md/the milestone brief) -- only the feed contract.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_contract_feed

const MissionLog = preload("res://scripts/story/mission_log.gd")
const ContractFeed = preload("res://scripts/story/contract_feed.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _canned_mission(id: String, title: String = "Check on Todd") -> Dictionary:
	return {
		"id": id,
		"title": title,
		"giver": "aunt_stephanie",
		"objectives": [
			{"id": "search_field", "kind": "GO_TO_AREA", "text": "Search the Slag Bay field", "target": {"center": Vector2(150000, 110000), "radius": 12000.0}},
			{"id": "talk_todd", "kind": "TALK_TO", "text": "Talk to Todd", "target": {"npc": "Todd"}},
			{"id": "deliver_present", "kind": "DELIVER", "text": "Deliver the present to Aunt Stephanie", "target": {"item": "stephanies_present", "npc": "Aunt Stephanie", "marker_sid": "ironhold"}},
		],
	}

func _make_cluster_manager(ironhold_pos: Vector2) -> Node:
	var manager := ClusterManager.new()
	var rec := ClusterEntity.new()
	rec.id = 1
	rec.name = "Ironhold"
	rec.sid = "ironhold"
	rec.pos = ironhold_pos
	manager.add_record(rec)
	return manager

func setup(main) -> void:
	main_node = main
	print("Starting Contract Feed (M41) Tests")
	StoryState.reset()

	_case_go_to_area()
	StoryState.reset()

	_case_talk_to_no_pos()
	StoryState.reset()

	_case_deliver_marker_sid()
	StoryState.reset()

	_case_indicators_visible_false()
	StoryState.reset()

	_case_completed_mission_emits_nothing()
	StoryState.reset()

	_case_two_active_missions()
	StoryState.reset()

	_finish(main)

# ---------------------------------------------------------------------------
# Active mission with a GO_TO_AREA current objective -> one entry with pos
# (the area's center) and radius (> 0).
# ---------------------------------------------------------------------------
func _case_go_to_area() -> void:
	print("--- GO_TO_AREA -> one entry with pos + radius ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	log.start_mission(_canned_mission("check_on_todd"))

	var manager := _make_cluster_manager(Vector2(0, 0))
	var feed: Array = ContractFeed.build(log, manager)

	_assert(feed.size() == 1, "one active mission -> one contract entry")
	if feed.size() == 1:
		var e: Dictionary = feed[0]
		_assert(e.get("kind", "") == "GO_TO_AREA", "entry kind is GO_TO_AREA")
		_assert(e.get("pos", null) == Vector2(150000, 110000), "entry pos is the area's center")
		_assert(e.get("radius", 0.0) == 12000.0, "entry radius is the area's radius")
		_assert(e.get("mission_id", "") == "check_on_todd", "entry carries the mission id")
		_assert(e.get("title", "") == "Search the Slag Bay field", "entry title is the objective's text")

	_free_if_valid(log)
	_free_if_valid(manager)

# ---------------------------------------------------------------------------
# Advance to TALK_TO Todd -> entry present, pos == null, no radius. Do NOT
# invent a position -- finding Todd IS the gameplay.
# ---------------------------------------------------------------------------
func _case_talk_to_no_pos() -> void:
	print("--- TALK_TO (no marker_sid) -> entry present with pos == null ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	log.start_mission(_canned_mission("check_on_todd"))
	log.complete_objective("check_on_todd", "search_field")

	var manager := _make_cluster_manager(Vector2(0, 0))
	var feed: Array = ContractFeed.build(log, manager)

	_assert(feed.size() == 1, "still one entry (one mission, one active objective)")
	if feed.size() == 1:
		var e: Dictionary = feed[0]
		_assert(e.get("kind", "") == "TALK_TO", "entry kind is TALK_TO")
		_assert(e.get("pos", "unset") == null, "TALK_TO Todd's entry has pos == null (no known position)")
		_assert(e.get("radius", 0.0) == 0.0, "no radius on a non-area entry")

	_free_if_valid(log)
	_free_if_valid(manager)

# ---------------------------------------------------------------------------
# Advance to DELIVER (marker_sid "ironhold") -> pos resolves to the sid'd
# record's pos via the ClusterManager.
# ---------------------------------------------------------------------------
func _case_deliver_marker_sid() -> void:
	print("--- DELIVER w/ marker_sid -> pos resolves via ClusterManager records ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	log.start_mission(_canned_mission("check_on_todd"))
	log.complete_objective("check_on_todd", "search_field")
	log.complete_objective("check_on_todd", "talk_todd")

	var ironhold_pos := Vector2(12345, -6789)
	var manager := _make_cluster_manager(ironhold_pos)
	var feed: Array = ContractFeed.build(log, manager)

	_assert(feed.size() == 1, "one entry for the DELIVER objective")
	if feed.size() == 1:
		var e: Dictionary = feed[0]
		_assert(e.get("kind", "") == "DELIVER", "entry kind is DELIVER")
		_assert(e.get("pos", null) == ironhold_pos, "DELIVER entry's pos resolves to the marker_sid'd record's pos")
		_assert(e.get("radius", 0.0) == 0.0, "no radius on a DELIVER entry")

	# Unresolvable sid (no matching record / no cluster_manager) -> pos stays
	# null rather than guessing.
	var empty_manager := ClusterManager.new()
	var feed_unresolved: Array = ContractFeed.build(log, empty_manager)
	_assert(feed_unresolved.size() == 1 and feed_unresolved[0].get("pos", "unset") == null,
		"an unresolvable marker_sid leaves pos null instead of inventing a position")
	var feed_no_manager: Array = ContractFeed.build(log, null)
	_assert(feed_no_manager.size() == 1 and feed_no_manager[0].get("pos", "unset") == null,
		"a null cluster_manager leaves pos null instead of erroring")

	_free_if_valid(log)
	_free_if_valid(manager)
	_free_if_valid(empty_manager)

# ---------------------------------------------------------------------------
# indicators_visible == false -> the mission emits nothing.
# ---------------------------------------------------------------------------
func _case_indicators_visible_false() -> void:
	print("--- indicators_visible == false -> mission emits nothing ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	var def := _canned_mission("check_on_todd")
	def["indicators_visible"] = false
	log.start_mission(def)

	var manager := _make_cluster_manager(Vector2(0, 0))
	var feed: Array = ContractFeed.build(log, manager)
	_assert(feed.is_empty(), "a muted mission (indicators_visible=false) contributes no contract entries")

	_free_if_valid(log)
	_free_if_valid(manager)

# ---------------------------------------------------------------------------
# A completed mission (all objectives complete) -> nothing (active_missions()
# already excludes it).
# ---------------------------------------------------------------------------
func _case_completed_mission_emits_nothing() -> void:
	print("--- completed mission -> nothing ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	log.start_mission(_canned_mission("check_on_todd"))
	log.complete_objective("check_on_todd", "search_field")
	log.complete_objective("check_on_todd", "talk_todd")
	StoryState.grant_item("stephanies_present")
	log.notify_delivered("Aunt Stephanie")
	_assert(log.get_mission("check_on_todd").get("state", "") == "COMPLETE", "sanity: mission actually completed")

	var manager := _make_cluster_manager(Vector2(0, 0))
	var feed: Array = ContractFeed.build(log, manager)
	_assert(feed.is_empty(), "a COMPLETE mission contributes no contract entries")

	_free_if_valid(log)
	_free_if_valid(manager)

# ---------------------------------------------------------------------------
# Two active missions -> two entries.
# ---------------------------------------------------------------------------
func _case_two_active_missions() -> void:
	print("--- two active missions -> two entries ---")
	var log: Node = MissionLog.new()
	main_node.add_child(log)
	log.start_mission(_canned_mission("check_on_todd", "Check on Todd"))
	log.start_mission(_canned_mission("check_on_someone_else", "Check on Someone Else"))

	var manager := _make_cluster_manager(Vector2(0, 0))
	var feed: Array = ContractFeed.build(log, manager)
	_assert(feed.size() == 2, "two active missions -> two contract entries")

	var mission_ids: Array = []
	for e in feed:
		mission_ids.append(e.get("mission_id", ""))
	_assert(mission_ids.has("check_on_todd") and mission_ids.has("check_on_someone_else"),
		"both missions' ids are represented")

	var ids: Array = []
	for e in feed:
		ids.append(e.get("id", ""))
	_assert(ids[0] != ids[1], "the two entries have distinct ids")

	_free_if_valid(log)
	_free_if_valid(manager)

func _finish(main) -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_contract_feed <<<")
		main.get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_contract_feed <<<")
		main.get_tree().quit(1)
