extends Node

# Verifies the menu's Campaign path end to end by calling the REAL
# main._bootstrap_campaign() -- the function the CAMPAIGN button ultimately
# triggers (button -> _on_campaign_pressed -> _on_connection_established ->
# _bootstrap_campaign). Asserts the player is spawned at the authored start, the
# whole home cluster is loaded into a self-ticking ClusterManager parented to
# main, and the initial promote lit the neighbourhood. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_campaign_bootstrap
# Pass marker per CLAUDE.md.

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	print("Starting Campaign Bootstrap (menu path) Tests")

	# Drive the exact bootstrap the CAMPAIGN button triggers.
	main._bootstrap_campaign()

	var def = HomeCluster.build()

	# Player spawned at the authored start.
	_assert(main.players.has(1), "bootstrap: player ship (id 1) should be spawned")
	if main.players.has(1):
		_assert(main.players[1].position.distance_to(def.player_start) < 1.0,
			"bootstrap: player should be at player_start %s" % str(def.player_start))

	# A ClusterManager parented to main, holding the whole cluster and tracking the player.
	var mgr = null
	for c in main.get_children():
		if c is ClusterManager:
			mgr = c
	_assert(mgr != null, "bootstrap: a ClusterManager should be added to main")
	if mgr != null:
		var exp_total: int = def.entities.size()
		for f in def.asteroid_fields:
			exp_total += int(f["count"])
		_assert(mgr.records.size() == exp_total,
			"bootstrap: manager should hold the whole home cluster (%d vs %d)" % [mgr.records.size(), exp_total])
		_assert(main.players.has(1) and mgr.viewpoint_node == main.players[1],
			"bootstrap: manager viewpoint should track the player ship (self-tick)")

		# The initial tick promoted the neighbourhood: adjacent hub live, distant dormant.
		var ironhold = _rec(mgr, 1)
		var drift = _rec(mgr, 2)
		_assert(ironhold != null and ironhold.is_live(), "bootstrap: adjacent hub (Ironhold) should be live")
		_assert(drift != null and not drift.is_live(), "bootstrap: distant hub (Drift Market) should be dormant")

	# M17 nav integration through the real main hooks: destinations + route/engage.
	var nav_dests = main.nav_destinations()
	_assert(nav_dests.size() > 0, "nav: nav_destinations() should list targets after bootstrap")
	_assert(_has_dest(nav_dests, "Nexus Wormhole"), "nav: destinations should include the wormhole")
	if main.players.has(1):
		var engaged = main.set_nav_destination("Drift Market")
		_assert(engaged, "nav: set_nav_destination('Drift Market') should route and engage")
		var ap = main.players[1].get_node_or_null("NavAutopilot")
		_assert(ap != null and ap.active and ap.route.size() > 0, "nav: player autopilot should be engaged with a route")

	if failures.is_empty():
		print(">>> [TEST PASSED] test_campaign_bootstrap <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_campaign_bootstrap <<<")
		get_tree().quit(1)

func _rec(mgr, id: int):
	for r in mgr.records:
		if r.id == id:
			return r
	return null

func _has_dest(dests: Array, dname: String) -> bool:
	for d in dests:
		if d["name"] == dname:
			return true
	return false
