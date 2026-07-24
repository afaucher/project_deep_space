extends Node

# M52 playtest fix -- SOS as battery-backup + generic contact attribute
# (calling session, 2026-07-23), THEN M52 follow-up -- SOS becomes a real
# contact (implementation_plans/m52_sos_as_contact.md), THEN M52 passive
# sync (implementation_plans/m52_sos_passive_sync.md) -- SOS is no longer a
# heartbeat-resent wire event at all; sos_active/sos_nature are plain live
# ship fields, and ship.gd's datalink_relay reconciles active_contacts from
# them continuously, every tick, for anyone in range. Changes covered here:
#
# 1. SOS_BATTERY_RANGE (hail.gd) is now a FLOOR, not a fallback that only
#    kicked in once get_comms_range() hit exactly 0. A comms component
#    merely DAMAGED (reduced range, not fully dead) used to cap SOS at that
#    reduced number -- "the consequence of not being able to call for real
#    help because of a damage roll is high, that breaks the fun." Now SOS
#    always reaches at least the battery floor regardless of comms health,
#    and a comms component still working for MORE than that lets SOS ride
#    the larger number instead. Ported into ship.gd's datalink_relay
#    unchanged by the passive-sync redesign -- still evaluated separately
#    from the ordinary their_comms_range<=0.0 early-out.
# 2. A heard SOS stamps sos/sos_nature/sos_name onto the sender's OWN
#    active_contacts entry -- "sos should be a contact attribute... let's
#    make it more generic." If the receiver already holds a real track, the
#    SOS ONLY annotates it (never overwrites pos/vel/signature/
#    classification -- see test_sos_prefers_live_contact.gd for that
#    specifically). If no track exists, the SOS creates one, classified the
#    bare literal "DISTRESS CALL".
# 3. Turning SOS off is not silent, but there is no longer an explicit "off"
#    broadcast to make it so -- reconciliation re-derives the correct state
#    from sos_active every tick, so within 1-2 ticks of set_sos_active(false)
#    a purely synthetic DISTRESS CALL entry is erased outright, and a real,
#    independently-detected contact has just its sos/sos_nature/sos_name
#    fields cleared (never the contact itself, never pos/vel/signature/
#    classification) -- see ship.gd's _reconcile_sos_contact.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sos_contact_attribute

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

func _kill_comms(ship) -> void:
	for c in ship.ship_components:
		if c.get("type", "") == "comms":
			c["health"] = 0.0

# A Frigate's active sensors reach 40000 units with NO distance falloff
# (only passive EM falls off with range) -- so a "far" receiver at 20-28k
# units is still well within real detection range and would correlate a
# genuine sensor track on the sender within a couple of seconds, silently
# contaminating a test that wants to observe SOS-only behavior (classify_
# contact() overwrites "DISTRESS CALL" the instant a real bin correlates,
# same self-healing ship.gd's own comments describe). Strip sensors
# entirely (test_comms_relay.gd's existing pattern) wherever a test needs a
# receiver whose active_contacts entries can ONLY ever come from SOS.
func _strip_sensors(ship) -> void:
	ship.ship_components = ship.ship_components.filter(func(c): return c["type"] != "sensors")

func setup(main) -> void:
	main_node = main
	print("Starting SOS Battery-Backup + Contact-Attribute Tests")

	await _test_sos_reaches_battery_range_with_dead_comms()
	await _test_sos_attribute_stamped_on_existing_contact()
	await _test_sos_creates_new_distress_contact()
	await _test_sos_off_erases_synthetic_contact()
	await _test_sos_off_clears_stamped_fields_only()

	_finish()

# ---------------------------------------------------------------------------
# A sender with a DESTROYED comms component still reaches a receiver at
# SOS_BATTERY_RANGE -- but NOT a non-SOS hail (the existing "no working
# radio, no send" rule for everything else is unchanged).
# ---------------------------------------------------------------------------
func _test_sos_reaches_battery_range_with_dead_comms() -> void:
	print("\n--- dead comms: SOS still reaches battery range, an ordinary DEMAND does not ---")
	var sender = _make_ship(Frigate, "DeadCommsSender", 800, Vector2.ZERO, ["TEAM_SENDER"])
	_kill_comms(sender)
	_assert(sender.get_comms_range() <= 0.0, "setup: sender's comms component reads as dead (range 0)")

	# Within SOS_BATTERY_RANGE but beyond any real comms range this hull has.
	var far_pos: Vector2 = Vector2(Hail.SOS_BATTERY_RANGE - 2000.0, 0)
	var receiver = _make_ship(Frigate, "FarReceiver", 801, far_pos, ["TEAM_RECEIVER"])
	_strip_sensors(receiver) # this test cares about the SOS-only path, not real detection

	sender.set_sos_active(true, Hail.NATURE_DISABLED)
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	var sender_trk0: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)
	_assert(receiver.active_contacts.has(sender_trk0), "receiver within battery range heard the SOS despite the sender's dead comms")
	_assert(receiver.active_contacts.get(sender_trk0, {}).get("classification", "") == "DISTRESS CALL", "no real track existed, so the SOS created a DISTRESS CALL contact")

	# An ordinary (non-SOS) hail from the same dead-comms sender must still
	# fail to send at all -- the battery floor is SOS-only.
	var demand_seq: int = sender.send_demand(receiver.get_instance_id(), Hail.RUNG_IDENTIFY)
	_assert(demand_seq == -1, "a non-SOS hail from the same dead-comms sender is NOT sent (battery floor is SOS-only)")

	_free_all()

# ---------------------------------------------------------------------------
# When the receiver already holds a real track on the sender, a heard SOS
# stamps sos/sos_nature/sos_name onto that SAME active_contacts entry --
# and does NOT clobber the real classification with the SOS placeholder.
# ---------------------------------------------------------------------------
func _test_sos_attribute_stamped_on_existing_contact() -> void:
	print("\n--- SOS stamps onto an EXISTING contact without touching real detection data ---")
	var sender = _make_ship(Frigate, "KnownSender", 802, Vector2.ZERO, ["TEAM_KNOWN_SENDER"])
	var receiver = _make_ship(Frigate, "KnownReceiver", 803, Vector2(3000, 0), ["TEAM_KNOWN_RECEIVER"])

	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)
	var have_track := false
	var real_classification: String = ""
	for i in range(600): # up to 10s for sensor correlation
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.has(sender_trk):
			have_track = true
			real_classification = receiver.active_contacts[sender_trk].get("classification", "")
			break
	_assert(have_track, "setup: receiver correlated a real sensor track on the sender")
	_assert(real_classification != "DISTRESS CALL", "setup: the pre-existing track carries a REAL classification, not the SOS placeholder")

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var stamped := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if c.get("sos", false):
			stamped = true
			_assert(c.get("sos_nature", "") == Hail.NATURE_UNDER_ATTACK, "sos_nature carries the actual nature sent")
			_assert(c.get("sos_name", "") != "", "sos_name is populated (not blank)")
			_assert(c.get("classification", "") == real_classification, "the merge does NOT overwrite the real classification with DISTRESS CALL")
			break
	_assert(stamped, "the sender's own active_contacts entry got the sos attribute -- generic, not a separate heard_sos-only signal")

	_free_all()

# ---------------------------------------------------------------------------
# M52 follow-up (implementation_plans/m52_sos_as_contact.md item 1, replaces
# the old "no contact -> active_contacts untouched" case): when the receiver
# has NO real track on the sender (comms range >> sensor range -- the whole
# point), the SOS now CREATES a new active_contacts entry -- classified the
# bare literal "DISTRESS CALL", empty signature, sos fields set -- instead of
# only populating the old heard_sos side-channel.
# ---------------------------------------------------------------------------
func _test_sos_creates_new_distress_contact() -> void:
	print("\n--- no existing contact: SOS creates a NEW 'DISTRESS CALL' entry ---")
	var sender = _make_ship(Frigate, "UnseenSender", 804, Vector2(500, 500), ["TEAM_UNSEEN_SENDER"])
	var receiver = _make_ship(Frigate, "DistantReceiver", 805, Vector2(25000, 0), ["TEAM_DISTANT_RECEIVER"])
	_strip_sensors(receiver) # no real detection -- this proves the SOS-only create path

	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)
	_assert(not receiver.active_contacts.has(sender_trk), "setup: no pre-existing contact for the sender")

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var created := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.has(sender_trk):
			created = true
			break
	_assert(created, "the SOS created a new active_contacts entry for a sender we can't sensor-detect")

	var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
	_assert(c.get("classification", "") == "DISTRESS CALL", "the new entry is classified DISTRESS CALL (bare literal, not derived from an empty signature)")
	_assert(c.get("signature", {}).is_empty(), "the new entry's signature is empty -- no real sensor data backs it")
	_assert(c.get("instance_id", -1) == sender.get_instance_id(), "instance_id resolves to the real sending ship")
	_assert(c.get("sos", false), "sos attribute set on the new entry too")
	_assert(c.get("sos_nature", "") == Hail.NATURE_UNDER_ATTACK, "sos_nature carries the actual nature sent")
	_assert(c.get("sos_name", "") != "", "sos_name is populated")
	_assert(c.get("pos", Vector2.ZERO).distance_to(sender.position) < 1.0, "the new entry's position is the sender's real send-time snapshot")

	_free_all()

# ---------------------------------------------------------------------------
# M52 passive sync (implementation_plans/m52_sos_passive_sync.md): turning
# SOS off is not silent, but there is no explicit "off" wire event anymore
# -- datalink_relay's continuous reconciliation re-derives the correct
# state from sos_active every tick. When the matched entry is a SYNTHETIC
# "DISTRESS CALL" contact (nothing else backs it -- no real detection),
# reconciliation erases it outright within 1-2 ticks instead of leaving it
# to decay on its own over the next CONTACT_TIMEOUT.
# ---------------------------------------------------------------------------
func _test_sos_off_erases_synthetic_contact() -> void:
	print("\n--- SOS off: a synthetic DISTRESS CALL contact is erased outright ---")
	var sender = _make_ship(Frigate, "OffSender", 806, Vector2(500, 500), ["TEAM_OFF_SENDER"])
	var receiver = _make_ship(Frigate, "OffReceiver", 807, Vector2(25000, 0), ["TEAM_OFF_RECEIVER"])
	_strip_sensors(receiver) # this proves reconciliation erases the SYNTHETIC entry, not a real one
	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var created := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.get(sender_trk, {}).get("classification", "") == "DISTRESS CALL":
			created = true
			break
	_assert(created, "setup: the SOS created a synthetic DISTRESS CALL entry")

	sender.set_sos_active(false, "")
	var erased := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if not receiver.active_contacts.has(sender_trk):
			erased = true
			break
	_assert(erased, "reconciliation erased the synthetic entry outright, no CONTACT_TIMEOUT wait needed")

	_free_all()

# ---------------------------------------------------------------------------
# M52 passive sync (implementation_plans/m52_sos_passive_sync.md): when the
# matched entry is a REAL, independently-detected contact that got
# sos/sos_nature/sos_name STAMPED onto it, reconciliation clears ONLY those
# three fields -- pos/vel/signature/classification/last_seen_timer are
# untouched, same non-clobber rule as the on-path merge (a real contact
# keeps refreshing via its own sensor detections regardless of SOS, and
# must keep doing so after the distress call ends).
# ---------------------------------------------------------------------------
func _test_sos_off_clears_stamped_fields_only() -> void:
	print("\n--- SOS off: a stamped-onto-a-real-contact entry clears only the sos fields ---")
	var sender = _make_ship(Frigate, "OffStampSender", 808, Vector2.ZERO, ["TEAM_OFF_STAMP_SENDER"])
	var receiver = _make_ship(Frigate, "OffStampReceiver", 809, Vector2(3000, 0), ["TEAM_OFF_STAMP_RECEIVER"])
	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)

	var have_track := false
	var real_classification: String = ""
	for i in range(600): # up to 10s for sensor correlation
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.has(sender_trk):
			have_track = true
			real_classification = receiver.active_contacts[sender_trk].get("classification", "")
			break
	_assert(have_track, "setup: receiver correlated a real sensor track on the sender")

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var stamped := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.get(sender_trk, {}).get("sos", false):
			stamped = true
			break
	_assert(stamped, "setup: the sos attribute stamped onto the real contact")

	sender.set_sos_active(false, "")
	var cleared := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if c.has("sos") and c.get("sos", true) == false:
			cleared = true
			_assert(c.get("sos_nature", "MISSING") == "", "sos_nature cleared to empty")
			_assert(c.get("sos_name", "MISSING") == "", "sos_name cleared to empty")
			_assert(c.get("classification", "") == real_classification, "classification untouched by reconciliation")
			_assert(c.get("instance_id", -1) == sender.get_instance_id(), "instance_id untouched")
			break
	_assert(cleared, "reconciliation cleared the sos fields without erasing the real contact")
	_assert(receiver.active_contacts.has(sender_trk), "the real contact itself is still there -- only its sos attributes were cleared")

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_sos_contact_attribute <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_sos_contact_attribute <<<")
		get_tree().quit(1)
