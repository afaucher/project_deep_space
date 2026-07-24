extends Node

# M52 playtest fix -- SOS response prefers a live contact over a stale
# snapshot (calling session, 2026-07-23).
#
# M52 follow-up (implementation_plans/m52_sos_as_contact.md item 1): the
# underlying behavior (a real detection's position wins over the SOS
# snapshot) still holds, but the MECHANISM moved from SOSResponseLeaf's old
# consumer-side "prefer live contact if fresh" check to the merge-in point
# itself -- ship.gd's SOS reconciliation NEVER touches pos/vel/signature/
# classification on an EXISTING active_contacts entry, only refreshing the
# sos/sos_nature/sos_name/last_seen_at attributes. So this now asserts
# directly on active_contacts rather than a leaf's commanded heading --
# there's no leaf-side logic left to exercise here.
#
# M52 passive sync (implementation_plans/m52_sos_passive_sync.md): SOS is no
# longer a wire hail carrying a send-time position snapshot -- reconciliation
# (ship.gd's _reconcile_sos_contact, called from datalink_relay every tick)
# reads the sender's LIVE position when it creates a brand-new "DISTRESS
# CALL" entry, then (same as before) never touches pos again once the entry
# exists, real or synthetic. Since the sender doesn't move during either
# test below, that still lands on the same position either way -- the
# "snapshot" framing in the test names/asserts below is now really "the
# sender's position at first-creation time", not a wire-transmitted value.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sos_prefers_live_contact

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")

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

# A Frigate's active sensors reach 40000 units with NO distance falloff --
# both tests below place patrol/sender well within that, and both tests
# want to observe the SOS merge/create path in ISOLATION (a hand-set entry
# staying exactly as set; a fresh snapshot landing exactly as sent). A real
# sensor correlation landing on the same track mid-test would silently
# overwrite pos/classification out from under the assertion, unrelated to
# the SOS behavior actually under test. Strip sensors entirely
# (test_comms_relay.gd's existing pattern) so active_contacts can only ever
# be touched by the SOS wire path here.
func _strip_sensors(ship) -> void:
	ship.ship_components = ship.ship_components.filter(func(c): return c["type"] != "sensors")

func setup(main) -> void:
	main_node = main
	print("Starting SOS-prefers-live-contact Tests")

	await _test_merge_does_not_overwrite_live_contact()
	await _test_new_contact_uses_the_sos_snapshot()

	_finish()

# ---------------------------------------------------------------------------
# The receiver already holds a live contact on the sender at position B
# (e.g. its own sensors, or a relay hop, more current than the SOS). The
# sender's SOS snapshot says A (its real position at send time, deliberately
# different here to prove the point). After the SOS arrives, the contact's
# pos/classification must stay at the live values -- only the sos attributes
# get refreshed.
# ---------------------------------------------------------------------------
func _test_merge_does_not_overwrite_live_contact() -> void:
	print("\n--- merge onto an EXISTING contact does not overwrite its live pos/classification ---")
	var patrol = _make_ship(Frigate, "Patrol", 800, Vector2.ZERO, ["TEAM_PATROL"])
	_strip_sensors(patrol)
	var pos_a := Vector2(0, -20000) # sender's real position at send time (the SOS snapshot)
	var sender = _make_ship(Frigate, "Sender", 850, pos_a, ["TEAM_SENDER"])
	var sender_iid: int = sender.get_instance_id()
	var sender_trk: String = "TRK-%03d" % (abs(sender_iid) % 1000)

	var pos_b := Vector2(20000, 0) # a pre-existing "live" detection's position, deliberately different from A
	patrol.active_contacts[sender_trk] = {
		"instance_id": sender_iid, "pos": pos_b, "vel": Vector2.ZERO,
		"last_seen_at": Engine.get_physics_frames(), "classification": "UNIDENTIFIED VESSEL",
	}

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var stamped := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if patrol.active_contacts.get(sender_trk, {}).get("sos", false):
			stamped = true
			break
	_assert(stamped, "setup: the SOS was heard and merged onto the existing contact")

	var c: Dictionary = patrol.active_contacts.get(sender_trk, {})
	_assert(c.get("pos", Vector2.ZERO) == pos_b, "the merge did NOT overwrite the live contact's position with the SOS snapshot (still B, not A)")
	_assert(c.get("classification", "") == "UNIDENTIFIED VESSEL", "the merge did NOT overwrite the live contact's classification")
	_assert(c.get("sos_nature", "") == Hail.NATURE_UNDER_ATTACK, "the sos attributes DID refresh")

	_free_all()

# ---------------------------------------------------------------------------
# No live contact on the sender at all (comms range >> sensor range, the
# whole reason SOS is useful over sensors alone) -- the new entry ship.gd's
# reconciliation creates uses the sender's own live position at the moment
# of creation (there's simply nothing else to prefer); since the sender
# never moves in this test that's indistinguishable from "the SOS
# snapshot", same result as before this fix.
# ---------------------------------------------------------------------------
func _test_new_contact_uses_the_sos_snapshot() -> void:
	print("\n--- no live contact on the sender -- the new entry uses the SOS snapshot position ---")
	var patrol = _make_ship(Frigate, "Patrol2", 801, Vector2.ZERO, ["TEAM_PATROL2"])
	_strip_sensors(patrol)
	var pos_a := Vector2(0, -20000)
	var sender = _make_ship(Frigate, "Sender2", 851, pos_a, ["TEAM_SENDER2"])
	var sender_iid: int = sender.get_instance_id()
	var sender_trk: String = "TRK-%03d" % (abs(sender_iid) % 1000)
	# Deliberately no active_contacts entry for sender_iid.

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var created := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if patrol.active_contacts.has(sender_trk):
			created = true
			break
	_assert(created, "the SOS created a new entry")
	_assert(patrol.active_contacts.get(sender_trk, {}).get("pos", Vector2.ZERO) == pos_a, "the new entry's position is the SOS snapshot (A) when no live contact exists")

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
