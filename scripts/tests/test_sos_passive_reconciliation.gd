extends Node

# M52 passive sync (implementation_plans/m52_sos_passive_sync.md) -- the
# doc's "Key new test": the battery-floor + dead-comms + passive-sync case,
# paired with an off-clears-fast sub-case (sos_active flips false) and a
# death-STICKS-on sub-case (the opposite -- a hulk that was broadcasting SOS
# when it died is the future rescue-tug dispatch signal, design_ideas/
# tugs.md, and must NOT clear), plus the "fly back into sensor range while a
# stale entry might still exist" scenario from the session that motivated
# this redesign.
#
# Every other SOS test either predates this milestone (test_sos_contact_
# attribute.gd, test_sos_prefers_live_contact.gd, test_sos_relay_bridge.gd)
# or exercises SOS as a side effect of AI/UI behavior (test_hail_protocol.gd,
# test_demand_lifecycle.gd, test_threat_response.gd, test_patrol_
# interdiction.gd, test_contacts_panel_sos.gd). This file is dedicated to
# the passive-reconciliation mechanism itself, end to end.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sos_passive_reconciliation

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = Frigate.new()
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

func _strip_sensors(ship) -> void:
	ship.ship_components = ship.ship_components.filter(func(c): return c["type"] != "sensors")

func _trk_for(ship: Node) -> String:
	return "TRK-%03d" % (abs(ship.get_instance_id()) % 1000)

# CLAUDE.md's sleeping-RigidBody2D gotcha (test_relay_contact_aging.gd's
# existing pattern): plain `.position =` on a settled/sleeping body leaves
# the PhysicsServer's collision geometry at the OLD spot indefinitely, even
# though `.position` itself reads correctly -- explicit body_set_state +
# waking is the only reliable teleport.
func _teleport(ship: Node, pos: Vector2) -> void:
	var xform: Transform2D = ship.global_transform
	xform.origin = pos
	PhysicsServer2D.body_set_state(ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	ship.position = pos
	ship.sleeping = false

func setup(main) -> void:
	main_node = main
	print("Starting SOS Passive Reconciliation Tests")

	await _test_battery_floor_then_off_clears_within_ticks()
	await _test_battery_floor_then_death_sticks_on()
	await _test_fly_back_into_range_does_not_stick_stale_sos()
	await _test_rising_edge_notification()

	_finish()

# ---------------------------------------------------------------------------
# The battery floor (hail.gd's SOS_BATTERY_RANGE) survived the passive-sync
# redesign: a sender with comms fully destroyed, sos_active true, within the
# floored range but beyond any real comms range this hull could ever reach,
# still gets picked up. Paired with turning SOS off: reconciliation clears
# the entry within 1-2 ticks -- there is no explicit "off" message anymore
# for it to depend on, this IS the whole mechanism.
# ---------------------------------------------------------------------------
func _test_battery_floor_then_off_clears_within_ticks() -> void:
	print("\n--- battery floor: dead-comms sender heard, then sos_active=false clears it fast ---")
	var sender = _make_ship("FloorOffSender", 900, Vector2.ZERO, ["TEAM_FLOOR_OFF"])
	_kill_comms(sender)
	_assert(sender.get_comms_range() <= 0.0, "setup: sender's comms reads dead (range 0)")

	var far_pos: Vector2 = Vector2(Hail.SOS_BATTERY_RANGE - 2000.0, 0)
	var receiver = _make_ship("FloorOffReceiver", 901, far_pos, ["TEAM_FLOOR_OFF_RX"])
	_strip_sensors(receiver) # isolate the SOS-only path from real detection
	var sender_trk: String = _trk_for(sender)

	sender.set_sos_active(true, Hail.NATURE_DISABLED)
	var heard := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.get(sender_trk, {}).get("classification", "") == "DISTRESS CALL":
			heard = true
			break
	_assert(heard, "the floor survived the redesign -- receiver heard the dead-comms sender's SOS")

	sender.set_sos_active(false, "")
	var cleared_frame := -1
	for i in range(10): # generous -- should clear within 1-2 ticks
		await main_node.get_tree().physics_frame
		if not receiver.active_contacts.has(sender_trk):
			cleared_frame = i + 1
			break
	_assert(cleared_frame != -1 and cleared_frame <= 3,
		"reconciliation erased the entry within a couple of ticks of sos_active going false (took %s), no off-message involved" % (str(cleared_frame) if cleared_frame != -1 else "never"))

	_free_all()

# ---------------------------------------------------------------------------
# Same battery-floor setup, but the sender dies outright instead of toggling
# SOS off (hulk() sets is_dead, never itself touches sos_active, and
# set_sos_active bails on is_dead so nothing can ever change it again).
# Deliberately the OPPOSITE of the sos_active->false case: a wreck that was
# crying for help when it died must STAY a DISTRESS CALL contact,
# indefinitely -- this is the intended dispatch signal for a future rescue
# tug to find and tow the hulk (design_ideas/tugs.md: "the casualty can be
# a live-but-dead-reactor ship... or a hulk"). Ran well past the ordinary
# CONTACT_TIMEOUT to prove this isn't just "hasn't decayed yet" -- the
# reconciled entry's own last_seen_at reset to "now" (every tick sos_in_range is
# true) means it never reaches that clock regardless, but running the sim
# out this far is the honest way to demonstrate "stuck on", not infer it.
# ---------------------------------------------------------------------------
func _test_battery_floor_then_death_sticks_on() -> void:
	print("\n--- battery floor: dead-comms sender heard, then dying leaves SOS stuck on (tow rescue signal) ---")
	var sender = _make_ship("FloorDeathSender", 902, Vector2.ZERO, ["TEAM_FLOOR_DEATH"])
	_kill_comms(sender)

	var far_pos: Vector2 = Vector2(Hail.SOS_BATTERY_RANGE - 2000.0, 0)
	var receiver = _make_ship("FloorDeathReceiver", 903, far_pos, ["TEAM_FLOOR_DEATH_RX"])
	_strip_sensors(receiver)
	var sender_trk: String = _trk_for(sender)

	sender.set_sos_active(true, Hail.NATURE_DISABLED)
	var heard := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.get(sender_trk, {}).get("classification", "") == "DISTRESS CALL":
			heard = true
			break
	_assert(heard, "setup: receiver heard the dead-comms sender's SOS")

	sender.hulk() # dies mid-broadcast; sos_active is left true, same as a real kill would leave it
	_assert(sender.sos_active, "setup: dying does not itself clear sos_active")
	_assert(sender.is_dead, "setup: sender is now a hulk")

	for i in range(1500): # ~25s sim -- comfortably past CONTACT_TIMEOUT (20s)
		await main_node.get_tree().physics_frame
	_assert(receiver.active_contacts.has(sender_trk), "the DISTRESS CALL entry is still there long after the sender died and well past CONTACT_TIMEOUT")
	var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
	_assert(c.get("sos", false) == true, "sos still reads true on the hulk's entry -- stuck on, not cleared")
	_assert(c.get("classification", "") == "DISTRESS CALL", "still classified as a distress call, not decayed or pruned")

	_free_all()

# ---------------------------------------------------------------------------
# The exact bug #2 scenario from the session's conversation: a real,
# independently-detected contact gets sos:true stamped while classification
# has already self-healed to something real (not the synthetic "DISTRESS
# CALL" literal). The sender then leaves range with SOS still nominally
# active from the receiver's stale point of view, and later flies BACK into
# range with SOS actually off by then. Under the old event/snapshot design
# nothing would ever re-touch the stale sos fields once classification had
# healed (no wire event ever arrives to clear it, and a continuously-
# detected contact never decays to force a fresh create). Passive sync fixes
# this by construction: reconciliation re-derives sos state from CURRENT
# live truth every tick, regardless of what sensor correlation did to
# classification in the same tick.
# ---------------------------------------------------------------------------
func _test_fly_back_into_range_does_not_stick_stale_sos() -> void:
	print("\n--- fly back into range: a real contact's sos badge does not stick stale ---")
	var sender = _make_ship("FlybackSender", 904, Vector2.ZERO, ["TEAM_FLYBACK"])
	var receiver = _make_ship("FlybackReceiver", 905, Vector2(3000, 0), ["TEAM_FLYBACK_RX"])
	# Both keep their sensors AND comms -- this is deliberately the "real,
	# independently-detected contact" case (test_sos_contact_attribute.gd's
	# stamped-onto-existing-contact case), not the synthetic-entry case.
	var sender_trk: String = _trk_for(sender)

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var real_classification: String = ""
	var stamped := false
	for i in range(300): # up to 5s for sensor correlation + the sos stamp
		await main_node.get_tree().physics_frame
		var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if c.get("sos", false) and c.get("classification", "") != "" and c.get("classification", "") != "DISTRESS CALL":
			stamped = true
			real_classification = c.get("classification", "")
			break
	_assert(stamped, "setup: sos stamped onto a REAL, already-classified contact (not a synthetic DISTRESS CALL entry)")

	# SOS ends and the sender leaves range in the SAME beat (no frame yielded
	# between the two) -- reconciliation never gets a chance to run the
	# clear before the candidate drops out of self_comms_range entirely, so
	# the entry is left "still sitting there" with a stale sos:true, exactly
	# the precondition the old design could never recover from cleanly.
	sender.set_sos_active(false, "")
	_teleport(sender, Vector2(500000, 500000))
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	var mid_c: Dictionary = receiver.active_contacts.get(sender_trk, {})
	_assert(not mid_c.is_empty(), "setup: a couple of frames out of range is nowhere near CONTACT_TIMEOUT -- the entry is still sitting there")
	_assert(mid_c.get("sos", false) == true, "setup: sos is still stuck true -- the sender left range before reconciliation could clear it, reproducing the stale precondition")

	# Now actually reproduce the "flies back into SENSOR range" moment: the
	# sender returns, real sensor correlation immediately re-fires (never
	# lets last_seen_at go stale), and reconciliation must show sos:false on
	# that SAME return -- not just at the moment it left.
	_teleport(sender, Vector2(3000, 0))
	var settled := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		var c: Dictionary = receiver.active_contacts.get(sender_trk, {})
		if not c.is_empty() and c.get("classification", "") == real_classification:
			settled = true
			_assert(c.get("sos", true) == false, "sos did NOT stick true on return -- reconciliation cleared it despite continuous real re-detection")
			_assert(c.get("sos_nature", "MISSING") == "", "sos_nature cleared too")
			_assert(c.get("sos_name", "MISSING") == "", "sos_name cleared too")
			break
	_assert(settled, "setup: the contact re-settled to its real classification after the sender flew back into range")

	_free_all()

# ---------------------------------------------------------------------------
# The doc's local, wire-free edge-triggered notification: a rising edge
# (false -> true) in reconciliation's own verdict appends exactly one
# last_hails entry (matching what a first-receipt hail does today) and logs
# an eng_log line. Staying true on subsequent ticks must NOT spam either
# ring; a falling edge needs no log entry at all.
# ---------------------------------------------------------------------------
func _test_rising_edge_notification() -> void:
	print("\n--- rising edge: heard-a-distress-call logs exactly once, not every tick ---")
	var sender = _make_ship("EdgeSender", 906, Vector2.ZERO, ["TEAM_EDGE"])
	var receiver = _make_ship("EdgeReceiver", 907, Vector2(3000, 0), ["TEAM_EDGE_RX"])
	_strip_sensors(receiver) # isolate the SOS-only path
	var sender_trk: String = _trk_for(sender)

	_assert(receiver.last_hails.is_empty(), "setup: no prior hails")

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var heard := false
	for i in range(120): # up to 2s
		await main_node.get_tree().physics_frame
		if receiver.active_contacts.has(sender_trk):
			heard = true
			break
	_assert(heard, "setup: receiver heard the SOS")
	_assert(receiver.last_hails.size() == 1, "the rising edge logged exactly ONE last_hails entry, got %d" % receiver.last_hails.size())
	if not receiver.last_hails.is_empty():
		var h: Dictionary = receiver.last_hails[receiver.last_hails.size() - 1]
		_assert(h.get("verb", "") == Hail.VERB_SOS, "the logged entry is shaped like an SOS hail")
		_assert(h.get("sender_iid", -1) == sender.get_instance_id(), "the logged entry identifies the real sender")

	# Staying true for several more ticks must not spam the ring.
	for i in range(30):
		await main_node.get_tree().physics_frame
	_assert(receiver.last_hails.size() == 1, "staying active for more ticks did NOT add more last_hails entries, got %d" % receiver.last_hails.size())

	# A falling edge logs nothing.
	sender.set_sos_active(false, "")
	for i in range(10):
		await main_node.get_tree().physics_frame
	_assert(receiver.last_hails.size() == 1, "turning SOS off did NOT add a last_hails entry (falling edges are silent), got %d" % receiver.last_hails.size())

	# A SECOND rising edge (a later, distinct incident) logs again.
	sender.set_sos_active(true, Hail.NATURE_DISABLED)
	var heard_again := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if receiver.last_hails.size() == 2:
			heard_again = true
			break
	_assert(heard_again, "a later, distinct rising edge logged a SECOND last_hails entry, got %d" % receiver.last_hails.size())

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_sos_passive_reconciliation <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_sos_passive_reconciliation <<<")
		get_tree().quit(1)
