extends Node

# M52 playtest fix -- SOS response prefers a live contact over a stale
# snapshot (calling session, 2026-07-23). Ship.send_sos() snapshots the
# sender's REAL position at send time ("pos": position); heard_sos ages
# correctly (HEARD_SOS_TTL, and a future relay hop would age it further).
# But SOSResponseLeaf used to navigate toward that snapshot UNCONDITIONALLY,
# even when the responder ALREADY holds (or has since gained) a live sensor
# contact on the same sender -- a continuously-updated track that's always
# fresher than a fixed report, especially once the ship has actually moved
# since sending. Fixed: prefer active_contacts' live position whenever a
# fresh track exists, fall back to the SOS snapshot only when it doesn't
# (comms range >> sensor range -- the whole reason heard_sos exists at all).
#
# Ticks the leaf DIRECTLY (leaf.tick(actor, blackboard)) against a real Ship
# for its fields/methods -- no full behavior tree or physics loop needed,
# same fast pattern test_threat_response.gd uses for ThreatResponseLeaf.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sos_prefers_live_contact

const SOSResponseLeaf = preload("res://scripts/ai/leaves/sos_response_leaf.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(script, ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _make_blackboard() -> Blackboard:
	var bb := Blackboard.new()
	bb.blackboard = {}
	return bb

func setup(main) -> void:
	main_node = main
	print("Starting SOS-prefers-live-contact Tests")

	_test_prefers_live_contact_over_stale_snapshot()
	_test_falls_back_to_snapshot_without_a_contact()

	_finish()

# ---------------------------------------------------------------------------
# A stale SOS snapshot says the sender is at A; the responder ALSO holds a
# live, fresh contact on the sender showing it's actually at B (it moved).
# The commanded heading must point toward B, not A.
# ---------------------------------------------------------------------------
func _test_prefers_live_contact_over_stale_snapshot() -> void:
	print("\n--- stale SOS snapshot at A, live contact says B -- responds toward B ---")
	var patrol = _make_ship(Frigate, "Patrol", 800, Vector2.ZERO, ["TEAM_PATROL"])
	var sender_iid := 12345

	var pos_a := Vector2(0, -20000)   # the stale, send-time snapshot position
	var pos_b := Vector2(20000, 0)    # where the sender actually is now (live contact)

	patrol.heard_sos[sender_iid] = {"verb": "SOS", "nature": "UNDER_ATTACK", "pos": pos_a, "name": "Distressed", "age": 45.0}

	var sender_trk: String = "TRK-%03d" % (abs(sender_iid) % 1000)
	patrol.active_contacts[sender_trk] = {
		"instance_id": sender_iid, "pos": pos_b, "vel": Vector2.ZERO,
		"last_seen_timer": 0.0, "classification": "UNIDENTIFIED VESSEL",
	}

	var leaf := SOSResponseLeaf.new()
	var bb := _make_blackboard()
	var result: int = leaf.tick(patrol, bb)

	_assert(result == leaf.SUCCESS, "leaf claims the tick, en route to respond")
	_assert(bb.get_value("sos_responding_to", -1) == sender_iid, "committed to responding to the sender")

	var dir_commanded: Vector2 = Vector2.RIGHT.rotated(patrol.target_heading)
	var dir_to_a: Vector2 = (pos_a - patrol.position).normalized()
	var dir_to_b: Vector2 = (pos_b - patrol.position).normalized()
	_assert(dir_commanded.dot(dir_to_b) > dir_commanded.dot(dir_to_a),
		"commanded heading points toward the LIVE contact position (B), not the stale SOS snapshot (A)")
	_assert(dir_commanded.dot(dir_to_b) > 0.9, "commanded heading points essentially straight at the live contact")

	_free_all()

# ---------------------------------------------------------------------------
# No live contact on the sender at all (comms range >> sensor range, the
# whole reason heard_sos exists) -- falls back to the SOS snapshot, same as
# before this fix.
# ---------------------------------------------------------------------------
func _test_falls_back_to_snapshot_without_a_contact() -> void:
	print("\n--- no live contact on the sender -- falls back to the SOS snapshot ---")
	var patrol = _make_ship(Frigate, "Patrol2", 801, Vector2.ZERO, ["TEAM_PATROL2"])
	var sender_iid := 54321
	var pos_a := Vector2(0, -20000)

	patrol.heard_sos[sender_iid] = {"verb": "SOS", "nature": "UNDER_ATTACK", "pos": pos_a, "name": "Distressed2", "age": 5.0}
	# Deliberately no active_contacts entry for sender_iid.

	var leaf := SOSResponseLeaf.new()
	var bb := _make_blackboard()
	leaf.tick(patrol, bb)

	var dir_commanded: Vector2 = Vector2.RIGHT.rotated(patrol.target_heading)
	var dir_to_a: Vector2 = (pos_a - patrol.position).normalized()
	_assert(dir_commanded.dot(dir_to_a) > 0.9, "commanded heading points at the SOS snapshot when no live contact exists")

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_sos_prefers_live_contact <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_sos_prefers_live_contact <<<")
		get_tree().quit(1)
