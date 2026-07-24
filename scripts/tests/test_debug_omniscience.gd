extends Node

# F9 omniscience debug map view (see implementation_plans -- "expand debug map
# view to all cluster entities"). Verifies main._get_debug_entities() covers
# every ClusterEntity.Kind actually present in the campaign home cluster (not
# just PLAYER/TRAFFIC), and that the packet shape it returns is plain
# serializable data: [{"pos": Vector2, "kind": int, "name": String}, ...].
# Drives the real bootstrap path (main._bootstrap_campaign(), same as
# test_campaign_bootstrap.gd) so this is an end-to-end check of the actual
# function the F9 packet field calls, not a hand-built fixture. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_debug_omniscience
# Pass marker per CLAUDE.md.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	print("Starting Debug Omniscience (F9 map view) Tests")

	main._bootstrap_campaign()

	var entities: Array = main._get_debug_entities()
	_assert(entities.size() > 0, "debug_entities: should return entries once a campaign cluster is loaded")

	var kinds_seen := {}
	for entity in entities:
		_assert(entity.has("pos"), "debug_entities: every entry should have a 'pos' key")
		_assert(entity.has("kind"), "debug_entities: every entry should have a 'kind' key")
		_assert(entity.has("name"), "debug_entities: every entry should have a 'name' key")
		_assert(entity.get("pos") is Vector2, "debug_entities: 'pos' should be a Vector2")
		_assert(entity.get("kind") is int, "debug_entities: 'kind' should be an int")
		kinds_seen[entity.get("kind")] = true

	# The home cluster's authored def includes at minimum a station, the
	# wormhole, and an expanded asteroid field (~69 records) -- confirms the
	# view covers more than just PLAYER/TRAFFIC now.
	_assert(kinds_seen.has(ClusterEntity.Kind.STATION), "debug_entities: should include at least one STATION")
	_assert(kinds_seen.has(ClusterEntity.Kind.ASTEROID), "debug_entities: should include at least one ASTEROID")
	_assert(kinds_seen.has(ClusterEntity.Kind.WORMHOLE), "debug_entities: should include the WORMHOLE")
	_assert(kinds_seen.size() >= 3, "debug_entities: should cover multiple distinct kinds (saw %d)" % kinds_seen.size())

	# Off by default, and _distribute_state gates the packet field on the flag
	# (only _get_debug_entities() itself is exercised above -- this pins the
	# default so the omniscience view doesn't leak on unless F9 was pressed).
	_assert(main.debug_show_all_entities == false, "debug_entities: F9 toggle should default to off")

	if failures.is_empty():
		print(">>> [TEST PASSED] test_debug_omniscience <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_debug_omniscience <<<")
		get_tree().quit(1)
