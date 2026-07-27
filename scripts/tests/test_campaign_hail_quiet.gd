extends Node

# Campaign playtest follow-up, 2026-07-27: "we still get duplicate hails
# continuously on campaign start -- every few seconds, maybe 30 in the log",
# "I also see bystander spam", and "Patrol Alpha looks to be hailing everyone
# from our overheard log - even to Ironhold!"
#
# Three separate causes were found and fixed:
#   1. Demand heartbeats (every 2s) were suppressed only for the ADDRESSED
#      ship, so every bystander logged each re-assert as a brand-new hail.
#   2. Hails addressed to OTHER ships were ringed into last_hails even though
#      build_vessel_entries can never display them, evicting the player's own
#      hail history from an 8-slot ring.
#   3. ChallengeLeaf had no minimum silence, so at campaign start -- when every
#      contact is briefly UNREPORTED because the datalink has not delivered
#      transponders yet -- a patrol challenged EVERYTHING at once, including
#      the station it guards.
#
# Those each have a focused unit test. This one is the END-TO-END check the
# playtest actually asked for: drive the REAL campaign bootstrap, let it run,
# and assert the player's hail log is quiet. Unit tests could not have caught
# any of the three, because all three only appear once several ships are live
# in one cluster.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_campaign_hail_quiet

const Hail = preload("res://scripts/comms/hail.gd")
const Standing = preload("res://scripts/combat/standing.gd")

# 90 game-seconds: past ChallengeLeaf's 5s silence grace, past its 20s window,
# and through several 2s heartbeat cadences.
const RUN_FRAMES := 5400

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _hail_log_lines(ship: Node) -> Array:
	var out: Array = []
	for e in ship.eng_log:
		var t: String = str(e.get("text", ""))
		if "DEMAND" in t or "hail" in t.to_lower() or "Distress" in t:
			out.append(t)
	return out

func setup(main) -> void:
	main_node = main
	print("Starting Campaign Hail Quiet check (playtest follow-up)")

	main._bootstrap_campaign()

	var player = main.players.get(1, null)
	_assert(player != null, "bootstrap: the player ship exists")
	if player == null:
		_finish(); return

	# The player flies the home flag with the transponder ON -- exactly what
	# _spawn_player_ship authors. A reporting ship should never be challenged
	# at all once the relay has caught up.
	_assert(not player.get_active_transponder_data().is_empty(),
		"bootstrap: the player is reporting a transponder (so has nothing to be challenged for)")

	for i in range(RUN_FRAMES):
		await main_node.get_tree().physics_frame

	var lines: Array = _hail_log_lines(player)
	print("  -- player hail-related log lines over %d frames: %d" % [RUN_FRAMES, lines.size()])
	for l in lines:
		print("     %s" % l)

	# THE HEADLINE. The playtest saw ~30 accumulating every few seconds. There
	# is no exact right number -- a patrol legitimately hailing once is fine --
	# but a steady stream is the bug. 90 game-seconds of a quiet home cluster
	# should be single digits.
	_assert(lines.size() < 10,
		"the player's hail log is QUIET over 90 game-seconds (got %d lines; the playtest saw ~30 and climbing)"
			% lines.size())

	# No line may repeat. Every one of the three bugs produced literal repeats:
	# the same demand re-logged per heartbeat, or the same challenge re-issued.
	var seen: Dictionary = {}
	var dupes: Array = []
	for l in lines:
		if seen.has(l):
			if not dupes.has(l):
				dupes.append(l)
		seen[l] = true
	_assert(dupes.is_empty(),
		"no hail log line repeats (repeats were the whole symptom; got %s)" % str(dupes))

	# last_hails is what the comms panel's HAILS section renders. Nothing
	# addressed to another ship may occupy one of its 8 slots.
	var my_iid: int = player.get_instance_id()
	var misfiled: int = 0
	for h in player.last_hails:
		var t_iid: int = h.get("target_iid", -1)
		if t_iid != my_iid and t_iid != -1:
			misfiled += 1
	_assert(misfiled == 0,
		"the player's last_hails holds only hails addressed to them (or broadcasts) -- %d misfiled" % misfiled)

	# The specific report: a patrol challenging the station it is guarding.
	# Nothing in the cluster should be challenging a hull that is reporting.
	var reporting_challenged: Array = []
	for s in main_node.get_tree().get_nodes_in_group("ships"):
		if not is_instance_valid(s) or s == player:
			continue
		if s.pending_demand.get("rung", "") != Hail.RUNG_IDENTIFY:
			continue
		if not s.get_active_transponder_data().is_empty():
			reporting_challenged.append(s.name)
	_assert(reporting_challenged.is_empty(),
		"no REPORTING hull is sitting under an identify demand (Ironhold included) -- got %s"
			% str(reporting_challenged))

	# And the player specifically: reporting from spawn, so never challenged.
	_assert(player.pending_demand.get("rung", "") != Hail.RUNG_IDENTIFY,
		"the player -- reporting since spawn -- is not under an identify demand")

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_campaign_hail_quiet <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_campaign_hail_quiet <<<")
		get_tree().quit(1)
