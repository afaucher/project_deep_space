extends Node

# M56 -- multi-hop timestamp preservation (implementation_plans/
# m56_contact_freshness_timestamps.md, "the multi-hop timestamp question").
#
# A relayed EXISTING contact must carry the ORIGINAL detecting ship's
# last_seen_at UNCHANGED through every hop -- relaying is NOT a fresh
# detection, so a relay hop must never re-stamp the value to "now". Getting
# this wrong (re-stamping on every hop) makes every relayed contact look
# perfectly fresh forever, silently breaking CONTACT_TIMEOUT pruning for
# anything relayed -- worse than the bug M56 set out to fix.
#
# Setup: a 3-ship bridge, A -- B -- C, each pair within comms range but A-C
# beyond it (same geometry style as test_sos_relay_bridge.gd), all with
# sensors stripped so nothing here can be explained by real (re-)detection --
# the ONLY source of truth for the injected track is the synthetic entry
# stamped directly onto A below, and the ONLY way it can reach B or C is the
# ordinary datalink relay. A back-dated last_seen_at (2s old at injection,
# simulating "a real detection A made a couple seconds ago, not this
# instant") is used deliberately rather than "now" -- that's what makes it
# possible to tell "preserved" (stays pinned at the same frame number,
# including at C after 2 hops) apart from "re-stamped on relay" (would climb
# toward Engine.get_physics_frames() at each hop / each subsequent tick).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_relay_multihop_timestamp

const Frigate = preload("res://scripts/ships/frigate.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, pos: Vector2) -> Node:
	var s = Frigate.new()
	s.name = ship_name
	s.owner_id = spawned.size() + 1
	s.iff_tags = ["TEAM_BRIDGE_TS"]
	s.position = pos
	# No real detection allowed to muddy the picture -- the injected synthetic
	# contact below must be the ONLY source of this track's data at every hop.
	s.ship_components = s.ship_components.filter(func(c): return c["type"] != "sensors")
	main_node.add_child(s)
	spawned.append(s)
	return s

func setup(main) -> void:
	main_node = main
	print("=== test_relay_multihop_timestamp: a relayed contact's last_seen_at is the ORIGINAL detection, preserved through every hop ===")

	var a = _make_ship("A", Vector2(0, 0))
	var b = _make_ship("B", Vector2(20000, 0))
	var c = _make_ship("C", Vector2(42000, 0))

	_assert(a.position.distance_to(c.position) > a.get_comms_range(),
		"setup: A-C distance exceeds comms range -- C can only ever hear A via the B relay hop")

	var trk := "TRK-777"
	var frames_per_sec: float = Engine.physics_ticks_per_second
	var original_stamp: int = Engine.get_physics_frames() - int(2.0 * frames_per_sec)
	a.active_contacts[trk] = {
		"instance_id": -54321, # no real node owns this id -- nothing can re-detect and re-stamp it
		"pos": Vector2(5000, 5000),
		"vel": Vector2.ZERO,
		"resolution": TAU,
		"pos_timer": 0.0,
		"signature": {},
		"classification": "UNIDENTIFIED VESSEL",
		"last_seen_at": original_stamp,
	}

	var frame := 0
	var b_hop := -1
	var c_hop := -1
	while frame < 600: # up to 10s -- generous margin for a 2-hop relay chain
		await main_node.get_tree().physics_frame
		frame += 1
		if b_hop == -1 and b.active_contacts.has(trk):
			b_hop = frame
		if c_hop == -1 and c.active_contacts.has(trk):
			c_hop = frame
		if c_hop != -1:
			break

	_assert(b_hop != -1, "B (1 hop from A) received the relayed contact")
	_assert(c_hop != -1, "C (2 hops from A, beyond A's own comms range) received the relayed contact")
	print("  hop timing (physics frames since injection): B=%d, C=%d" % [b_hop, c_hop])

	# A's own copy must never have moved -- A never re-detects (sensors
	# stripped) and never imports a "fresher" copy of its own track back from
	# B/C (the exact-tie-keeps-local rule -- see test_relay_tie_break_keeps_local
	# -- means even a perfect round-trip echo of A's own stamp can't overwrite
	# it). This is the baseline every hop below is compared against.
	_assert(a.active_contacts.get(trk, {}).get("last_seen_at", -1) == original_stamp,
		"A's own last_seen_at is untouched (still the original injected stamp)")

	if b_hop != -1:
		_assert(b.active_contacts[trk].get("last_seen_at", -1) == original_stamp,
			"B's relayed last_seen_at (1 hop) equals A's ORIGINAL stamp, not the moment B received it")
	if c_hop != -1:
		_assert(c.active_contacts[trk].get("last_seen_at", -1) == original_stamp,
			"C's relayed last_seen_at (2 hops) equals A's ORIGINAL stamp, not the moment C received it")

	# The real regression this guards: re-stamping on relay would make the
	# value climb toward "now" at every subsequent tick instead of sitting
	# still. Run the sim further and confirm C's stamp is STILL pinned at the
	# original value, not creeping upward tick over tick.
	if c_hop != -1:
		for i in range(120): # +2s of continued relay traffic
			await main_node.get_tree().physics_frame
		_assert(c.active_contacts.get(trk, {}).get("last_seen_at", -1) == original_stamp,
			"C's last_seen_at is STILL the original stamp 2s later -- relaying never re-stamps an existing contact to \"now\"")

	_free_all()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_relay_multihop_timestamp <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_relay_multihop_timestamp <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
