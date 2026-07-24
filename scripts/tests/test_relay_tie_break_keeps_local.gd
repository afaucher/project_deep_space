extends Node

# M56 -- relay freshest-wins exact-tie rule (implementation_plans/
# m56_contact_freshness_timestamps.md). Freshest-wins on absolute frame
# stamps is "bigger last_seen_at wins" -- but the old duration-based design
# (last_seen_timer, always inflated by +delta on every hop) made an EXACT
# TIE between a local copy and an incoming relayed copy structurally
# impossible: a relayed reading could never equal a fresh local one, only be
# strictly worse. Absolute stamps don't have that guarantee -- two ships can
# genuinely stamp the identical physics frame. Documented rule (ship.gd's
# datalink_relay merge, the `if relayed_last_seen_at > c.get("last_seen_at", 0):`
# comparison): on an EXACT tie, KEEP LOCAL -- do not import. The comparison
# is strict `>`, so a tie (neither side strictly newer) simply fails the
# condition and nothing gets overwritten.
#
# Setup: two comms-linked ships A and B, sensors stripped (so nothing here
# can be explained by real detection), each independently holding its OWN
# entry for the SAME track id, stamped with the IDENTICAL last_seen_at frame
# but carrying DIFFERENT positions -- so a wrongly-imported (`>=`) merge is
# immediately visible as "my position just became the other ship's position".
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_relay_tie_break_keeps_local

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
	s.iff_tags = ["TEAM_TIEBREAK"]
	s.position = pos
	s.ship_components = s.ship_components.filter(func(c): return c["type"] != "sensors")
	main_node.add_child(s)
	spawned.append(s)
	return s

func setup(main) -> void:
	main_node = main
	print("=== test_relay_tie_break_keeps_local: an exact last_seen_at tie keeps the local copy, does not import ===")

	var a = _make_ship("A", Vector2(0, 0))
	var b = _make_ship("B", Vector2(10000, 0)) # well within default comms range, clear LOS

	var trk := "TRK-TIE"
	var tie_stamp: int = Engine.get_physics_frames()

	var pos_a := Vector2(1000, 1000)
	var pos_b := Vector2(9000, 9000)

	var base_contact := {
		"instance_id": -24680, # no real node owns this id
		"vel": Vector2.ZERO,
		"resolution": TAU,
		"pos_timer": 0.0,
		"signature": {},
		"classification": "UNIDENTIFIED VESSEL",
		"last_seen_at": tie_stamp,
	}
	var a_contact: Dictionary = base_contact.duplicate(true)
	a_contact["pos"] = pos_a
	a.active_contacts[trk] = a_contact
	var b_contact: Dictionary = base_contact.duplicate(true)
	b_contact["pos"] = pos_b
	b.active_contacts[trk] = b_contact

	# A few ticks -- both directions of the relay get a fair chance to run;
	# an exact tie must never resolve either way, on any tick.
	for i in range(10):
		await main_node.get_tree().physics_frame
		_assert(a.active_contacts.get(trk, {}).get("pos", Vector2.ZERO) == pos_a,
			"tick %d: A's local copy is untouched (still A's own position, not B's)" % i)
		_assert(b.active_contacts.get(trk, {}).get("pos", Vector2.ZERO) == pos_b,
			"tick %d: B's local copy is untouched (still B's own position, not A's)" % i)
		_assert(a.active_contacts.get(trk, {}).get("last_seen_at", -1) == tie_stamp,
			"tick %d: A's last_seen_at is still the tied stamp" % i)
		_assert(b.active_contacts.get(trk, {}).get("last_seen_at", -1) == tie_stamp,
			"tick %d: B's last_seen_at is still the tied stamp" % i)

	_free_all()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_relay_tie_break_keeps_local <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_relay_tie_break_keeps_local <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
