extends Node

# M52 playtest fix -- SOS as battery-backup + generic contact attribute
# (calling session, 2026-07-23). Two changes:
#
# 1. SOS_BATTERY_RANGE (hail.gd) is now a FLOOR, not a fallback that only
#    kicked in once get_comms_range() hit exactly 0. A comms component
#    merely DAMAGED (reduced range, not fully dead) used to cap SOS at that
#    reduced number -- "the consequence of not being able to call for real
#    help because of a damage roll is high, that breaks the fun." Now SOS
#    always reaches at least the battery floor regardless of comms health,
#    and a comms component still working for MORE than that lets SOS ride
#    the larger number instead.
# 2. A heard SOS now also stamps sos/sos_nature/sos_name onto the sender's
#    OWN active_contacts entry, if the receiver already holds a real track
#    on them -- "sos should be a contact attribute... let's make it more
#    generic." heard_sos (the NAV/comms-layer channel for a sender with NO
#    real track -- comms range >> sensor range) is untouched; this only
#    ANNOTATES a real, already-existing contact, never manufactures one
#    (the M41 hazard contract_feed.gd's header warns about).
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

func setup(main) -> void:
	main_node = main
	print("Starting SOS Battery-Backup + Contact-Attribute Tests")

	await _test_sos_reaches_battery_range_with_dead_comms()
	await _test_sos_attribute_stamped_on_existing_contact()
	await _test_sos_attribute_absent_without_a_contact()

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

	sender.send_sos(Hail.NATURE_DISABLED)
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	_assert(receiver.heard_sos.has(sender.get_instance_id()), "receiver within battery range heard the SOS despite the sender's dead comms")

	# An ordinary (non-SOS) hail from the same dead-comms sender must still
	# fail to send at all -- the battery floor is SOS-only.
	var demand_seq: int = sender.send_demand(receiver.get_instance_id(), Hail.RUNG_IDENTIFY)
	_assert(demand_seq == -1, "a non-SOS hail from the same dead-comms sender is NOT sent (battery floor is SOS-only)")

	_free_all()

# ---------------------------------------------------------------------------
# When the receiver already holds a real track on the sender, a heard SOS
# stamps sos/sos_nature/sos_name onto that SAME active_contacts entry.
# ---------------------------------------------------------------------------
func _test_sos_attribute_stamped_on_existing_contact() -> void:
	print("\n--- SOS stamps onto an EXISTING contact, and clears once the SOS ages out ---")
	var sender = _make_ship(Frigate, "KnownSender", 802, Vector2.ZERO, ["TEAM_KNOWN_SENDER"])
	var receiver = _make_ship(Frigate, "KnownReceiver", 803, Vector2(3000, 0), ["TEAM_KNOWN_RECEIVER"])

	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)
	var have_track := false
	for i in range(600): # up to 10s for sensor correlation
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.has(sender_trk):
			have_track = true
			break
	_assert(have_track, "setup: receiver correlated a real sensor track on the sender")

	sender.send_sos(Hail.NATURE_UNDER_ATTACK)
	var stamped := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if c.get("sos", false):
			stamped = true
			_assert(c.get("sos_nature", "") == Hail.NATURE_UNDER_ATTACK, "sos_nature carries the actual nature sent")
			_assert(c.get("sos_name", "") != "", "sos_name is populated (not blank)")
			break
	_assert(stamped, "the sender's own active_contacts entry got the sos attribute -- generic, not a separate heard_sos-only signal")
	_assert(receiver.heard_sos.has(sender.get_instance_id()), "heard_sos is ALSO still populated -- the nav-layer channel is unchanged, not replaced")

	# Force it stale immediately (skip the real 90s HEARD_SOS_TTL wait --
	# same CLAUDE.md-style shortcut test_patrol_interdiction.gd's SOS phase
	# already uses) and confirm the mirrored attribute clears too.
	receiver.heard_sos[sender.get_instance_id()]["age"] = 9999.0
	var cleared := false
	for i in range(60):
		await main_node.get_tree().physics_frame
		var c2: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if not c2.get("sos", false) and not receiver.heard_sos.has(sender.get_instance_id()):
			cleared = true
			break
	_assert(cleared, "the mirrored sos attribute clears once the SOS ages out -- an otherwise-fresh contact doesn't carry a stale distress flag forever")

	_free_all()

# ---------------------------------------------------------------------------
# When the receiver has NO real track on the sender (comms range >> sensor
# range -- the whole point), heard_sos still populates but active_contacts
# is NEVER touched -- no synthetic/phantom contact gets manufactured.
# ---------------------------------------------------------------------------
func _test_sos_attribute_absent_without_a_contact() -> void:
	print("\n--- no real track on the sender: heard_sos populates, active_contacts stays untouched ---")
	var sender = _make_ship(Frigate, "UnseenSender", 804, Vector2.ZERO, ["TEAM_UNSEEN_SENDER"])
	# Well outside sensor range but inside comms/battery range.
	var receiver = _make_ship(Frigate, "DistantReceiver", 805, Vector2(25000, 0), ["TEAM_DISTANT_RECEIVER"])

	sender.send_sos(Hail.NATURE_UNDER_ATTACK)
	var heard := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.heard_sos.has(sender.get_instance_id()):
			heard = true
			break
	_assert(heard, "receiver heard the SOS via the comms channel despite no sensor track")

	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)
	_assert(not receiver.active_contacts.has(sender_trk), "no synthetic active_contacts entry was manufactured for a sender we can't actually see (M41 hazard avoided)")

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
