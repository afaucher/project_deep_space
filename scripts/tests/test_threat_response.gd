extends Node

# Unit tests for ThreatResponseLeaf's comply-or-run decision (scripts/ai/
# leaves/threat_response_leaf.gd) -- the cargo/civilian AI's response to a
# DEMAND(STOP). Full end-to-end encounters already exercise this leaf
# incidentally (test_demand_lifecycle.gd, test_honored_stop.gd, test_pirate_
# ambush.gd), but nothing pins the DECISION LOGIC directly: the run/stop
# speed-ratio threshold, the pirate-flag weighting, or the M52a "overtaken
# mid-flight" reconsideration. Complying always means actually stopping (not
# just acknowledging) -- the M52d ACKNOWLEDGE/STOP decoupling is a PLAYER-
# only affordance (comms_panel.gd's two buttons); the AI has no "buy time"
# nuance and always calls engage_dead_stop() directly, per the leaf's own
# header comment.
#
# Ticks the leaf DIRECTLY (leaf.tick(actor, blackboard)) against a real Ship
# instance for its fields/methods, with a bare Blackboard() -- no full
# behavior tree needed for the decision logic itself, so most of this stays
# fast (no physics loop). One end-to-end scenario at the bottom exercises
# the real wire hail protocol through build_cargo()'s actual tree.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_threat_response

const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Standing = preload("res://scripts/combat/standing.gd")
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

func _make_blackboard() -> Blackboard:
	var bb := Blackboard.new()
	bb.blackboard = {}
	return bb

# Stamps a fresh, in-range sensor track for `issuer` onto `victim` (the leaf
# reads active_contacts to look up the issuer's velocity, same shape sensor
# fusion would have produced) and a pending STOP demand from it.
func _demand_stop(victim, issuer, sender_flag: String = "") -> void:
	var issuer_trk: String = "TRK-%03d" % (abs(issuer.get_instance_id()) % 1000)
	victim.active_contacts[issuer_trk] = {
		"instance_id": issuer.get_instance_id(), "pos": issuer.position, "vel": issuer.linear_velocity,
		"last_seen_timer": 0.0, "classification": "UNIDENTIFIED VESSEL",
	}
	victim.pending_demand = {"rung": Hail.RUNG_STOP, "seq": victim.pending_demand.get("seq", 0) + 1,
		"sender_iid": issuer.get_instance_id(), "sender_flag": sender_flag, "sender_pos": issuer.position}

func setup(main) -> void:
	main_node = main
	print("Starting ThreatResponseLeaf (comply-or-run) Tests")

	_test_cannot_outrun_complies()
	_test_can_outrun_runs()
	_test_pirate_flag_weighs_toward_compliance()
	_test_overtaken_mid_flight_gives_up()
	await _test_sos_broadcast_once_per_incident()
	_test_already_held_does_nothing()
	await _test_end_to_end_wire_compliance()

	_finish()

# ---------------------------------------------------------------------------
# A victim that can't outrun the threat's demonstrated speed (even with the
# 1.3x margin) complies: engage_dead_stop() actually fires (compelled_stop
# set), not just an ACKNOWLEDGE-only declaration.
# ---------------------------------------------------------------------------
func _test_cannot_outrun_complies() -> void:
	print("\n--- can't outrun the threat: complies (engage_dead_stop, not just acknowledge) ---")
	var victim = _make_ship(CargoShuttle, "SlowVictim", 800, Vector2.ZERO, ["TEAM_SLOW"])
	var issuer = _make_ship(ArmedPinnace, "FastIssuer", 801, Vector2(2000, 0), ["TEAM_FAST_ISSUER"])
	issuer.linear_velocity = Vector2(900, 0) # demonstrated speed; victim.max_speed=1000 < 900*1.3=1170

	_demand_stop(victim, issuer)
	var leaf := ThreatResponseLeaf.new()
	var result: int = leaf.tick(victim, _make_blackboard())

	_assert(result == leaf.SUCCESS, "leaf claims the tick when reacting to a demand")
	_assert(not victim.compelled_stop.is_empty(), "victim actually complied (compelled_stop set)")
	_assert(victim.compelled_stop.get("issuer_iid", -1) == issuer.get_instance_id(), "compelled_stop names the demanding issuer")

	_free_all()

# ---------------------------------------------------------------------------
# A victim that CAN outrun the threat runs instead: threat_issuer_iid is set
# on the blackboard (the active-RUN incident marker), compelled_stop stays
# empty.
# ---------------------------------------------------------------------------
func _test_can_outrun_runs() -> void:
	print("\n--- can comfortably outrun the threat: runs ---")
	var victim = _make_ship(ArmedPinnace, "FastVictim", 802, Vector2.ZERO, ["TEAM_FASTV"]) # max_speed=2000
	var issuer = _make_ship(CargoShuttle, "SlowIssuer", 803, Vector2(2000, 0), ["TEAM_SLOW_ISSUER"])
	issuer.linear_velocity = Vector2(900, 0) # threshold 900*1.3=1170 < victim's 2000

	_demand_stop(victim, issuer)
	var leaf := ThreatResponseLeaf.new()
	var bb := _make_blackboard()
	var result: int = leaf.tick(victim, bb)

	_assert(result == leaf.SUCCESS, "leaf claims the tick when reacting to a demand")
	_assert(victim.compelled_stop.is_empty(), "victim did NOT comply -- it's running instead")
	_assert(bb.get_value("threat_issuer_iid", -1) == issuer.get_instance_id(), "blackboard marks an active RUN incident against the issuer")

	_free_all()

# ---------------------------------------------------------------------------
# Same demonstrated threat speed, only the sender_flag differs -- a shown
# pirate flag weighs the decision toward compliance (RUN_SPEED_RATIO_PIRATE_
# FLAG=1.6 vs the plain RUN_SPEED_RATIO=1.3). A victim whose max_speed sits
# strictly between the two thresholds runs from a non-pirate demand but
# stops for the identical demand shown in pirate colors.
# ---------------------------------------------------------------------------
func _test_pirate_flag_weighs_toward_compliance() -> void:
	print("\n--- identical threat speed, pirate colors vs not: weighs the decision differently ---")
	const THREAT_SPEED := 850.0 # x1.3=1105 (plain), x1.6=1360 (pirate) -- 1200 sits between them

	var victim_a = _make_ship(CargoShuttle, "VictimPlain", 804, Vector2.ZERO, ["TEAM_VA"])
	victim_a.max_speed = 1200.0
	var issuer_a = _make_ship(ArmedPinnace, "IssuerPlain", 805, Vector2(2000, 0), ["TEAM_IA"])
	issuer_a.linear_velocity = Vector2(THREAT_SPEED, 0)
	_demand_stop(victim_a, issuer_a, "") # no flag -- plain ratio
	var leaf_a := ThreatResponseLeaf.new()
	leaf_a.tick(victim_a, _make_blackboard())
	_assert(victim_a.compelled_stop.is_empty(), "non-pirate demand at this speed: victim runs (1200 > 1105)")

	var victim_b = _make_ship(CargoShuttle, "VictimPirate", 806, Vector2.ZERO, ["TEAM_VB"])
	victim_b.max_speed = 1200.0
	var issuer_b = _make_ship(ArmedPinnace, "IssuerPirate", 807, Vector2(2000, 0), ["TEAM_IB"])
	issuer_b.linear_velocity = Vector2(THREAT_SPEED, 0)
	_demand_stop(victim_b, issuer_b, Standing.FLAG_PIRATE) # shown pirate colors -- weighted ratio
	var leaf_b := ThreatResponseLeaf.new()
	leaf_b.tick(victim_b, _make_blackboard())
	_assert(not victim_b.compelled_stop.is_empty(), "IDENTICAL threat speed shown in pirate colors: victim complies instead (1200 < 1360)")

	_free_all()

# ---------------------------------------------------------------------------
# M52a -- overtaken mid-flight: a victim that started running reconsiders
# once the chaser's live PEAK speed demonstrates it can actually catch up,
# even without a fresh demand. Simulated by ticking once to start the RUN,
# then bumping the issuer's observed velocity and ticking again.
# ---------------------------------------------------------------------------
func _test_overtaken_mid_flight_gives_up() -> void:
	print("\n--- overtaken mid-flight: chaser demonstrates it can catch up, victim gives up ---")
	var victim = _make_ship(ArmedPinnace, "OvertakenVictim", 808, Vector2.ZERO, ["TEAM_OV"]) # max_speed=2000
	var issuer = _make_ship(ArmedPinnace, "Chaser", 809, Vector2(2000, 0), ["TEAM_CHASER"])
	issuer.linear_velocity = Vector2(900, 0) # initially slow enough to justify running (1170 < 2000)

	_demand_stop(victim, issuer)
	var leaf := ThreatResponseLeaf.new()
	var bb := _make_blackboard()
	leaf.tick(victim, bb)
	_assert(victim.compelled_stop.is_empty(), "setup: victim started out running")
	_assert(bb.get_value("threat_issuer_iid", -1) == issuer.get_instance_id(), "setup: RUN incident active against the issuer")

	# The chaser now demonstrably closes the gap -- update the live contact's
	# velocity (this is what _update_contact_peaks reads every tick) past the
	# point where victim.max_speed <= live_capability * run_ratio.
	var issuer_trk: String = "TRK-%03d" % (abs(issuer.get_instance_id()) % 1000)
	victim.active_contacts[issuer_trk]["vel"] = Vector2(1600.0, 0) # 1600*1.3=2080 >= victim's 2000
	var result: int = leaf.tick(victim, bb)

	_assert(result == leaf.SUCCESS, "leaf still claims the tick")
	_assert(not victim.compelled_stop.is_empty(), "victim gave up and complied once overtaken -- no fresh demand needed")
	_assert(not bb.has_value("threat_issuer_iid"), "the RUN incident marker cleared")

	_free_all()

# ---------------------------------------------------------------------------
# M52 follow-up (implementation_plans/m52_sos_as_contact.md item 2): SOS is
# no longer a one-shot broadcast -- the deciding tick turns the SOS
# HEARTBEAT on exactly once per incident (whether the victim ends up
# running or complying), and ship.gd's own _physics_process does the actual
# periodic re-sending from there. Verified two ways: (a) a nearby receiver's
# active_contacts entry for the victim picks up the sos attribute (proving
# the wire path actually reaches something, same mechanism SOSResponseLeaf
# reads, test_patrol_interdiction.gd's Phase 6 uses the identical shape),
# and (b) re-ticking the SAME already-decided demand does NOT re-prime the
# heartbeat -- checked directly on victim.sos_heartbeat_timer, race-free
# (see test_demand_lifecycle.gd's S4 for why this is more reliable than
# inferring from the receiver's data, whose last_seen_timer is also reset
# by ordinary real sensor detections at close range).
# ---------------------------------------------------------------------------
func _test_sos_broadcast_once_per_incident() -> void:
	print("\n--- SOS heartbeat turns on exactly once per incident, regardless of comply-or-run ---")
	var victim = _make_ship(CargoShuttle, "SosVictim", 810, Vector2.ZERO, ["TEAM_SOSV"])
	var issuer = _make_ship(ArmedPinnace, "SosIssuer", 811, Vector2(2000, 0), ["TEAM_SOSI"])
	issuer.linear_velocity = Vector2(900, 0) # victim complies (1000 < 1170)
	var receiver = _make_ship(ArmedPinnace, "Receiver", 812, Vector2(1000, 0), ["TEAM_RECV"])

	_demand_stop(victim, issuer)
	var leaf := ThreatResponseLeaf.new()
	var bb := _make_blackboard()
	leaf.tick(victim, bb)

	_assert(victim.sos_active, "the decision turned the SOS heartbeat on")
	_assert(victim.sos_nature == Hail.NATURE_UNDER_ATTACK, "sos_nature is UNDER_ATTACK")
	_assert(victim.sos_heartbeat_timer == victim.SOS_HEARTBEAT_INTERVAL, "heartbeat primed to fire on the very next physics tick")

	var victim_trk: String = "TRK-%03d" % (abs(victim.get_instance_id()) % 1000)
	var frame := 0
	while frame < 60 and not receiver.active_contacts.get(victim_trk, {}).get("sos", false):
		await main_node.get_tree().physics_frame
		frame += 1
	_assert(receiver.active_contacts.get(victim_trk, {}).get("sos", false), "a nearby ship's active_contacts entry for the victim picked up the sos attribute")

	# Re-ticking the SAME already-decided demand (seq unchanged) must NOT
	# re-trigger the decision -- decide-once-per-seq (last_decided_seq) gate.
	leaf.tick(victim, bb)
	_assert(victim.sos_heartbeat_timer != victim.SOS_HEARTBEAT_INTERVAL, "re-ticking the same pending_demand does not re-prime (re-broadcast) the SOS heartbeat")

	_free_all()

# ---------------------------------------------------------------------------
# A victim already held (compelled_stop set) does nothing -- the ship-level
# throttle override owns motion, the leaf just claims the tick and gets out
# of the way (M49 honor rule).
# ---------------------------------------------------------------------------
func _test_already_held_does_nothing() -> void:
	print("\n--- already held: leaf claims the tick and does nothing further ---")
	var victim = _make_ship(CargoShuttle, "HeldVictim", 813, Vector2.ZERO, ["TEAM_HELD"])
	victim.compelled_stop = {"issuer_iid": 999, "demand_seq": 1, "heartbeat_timer": 0.0}

	var leaf := ThreatResponseLeaf.new()
	var result: int = leaf.tick(victim, _make_blackboard())

	_assert(result == leaf.SUCCESS, "leaf claims the tick while held")
	_assert(victim.compelled_stop.get("issuer_iid", -1) == 999, "compelled_stop is untouched")

	_free_all()

# ---------------------------------------------------------------------------
# End to end: a real CargoShuttle running build_cargo(), demanded over the
# actual wire protocol (Ship.send_demand), complies for real -- proves the
# tree wiring (ThreatResponseLeaf sits between Disengage and CargoRun), not
# just the leaf's own decision logic in isolation. The issuer is given time
# to reach full speed BEFORE the demand is sent (real jobs always approach
# to hail range first, so a real victim is never demanded by something
# slower than its live demonstrated speed) -- un-outrunnable from the very
# first decision, so this stays a clean proof of the wiring rather than a
# live-sim replay of the overtaken-mid-flight timing (already pinned exactly
# by _test_overtaken_mid_flight_gives_up, with controlled inputs).
# ---------------------------------------------------------------------------
func _test_end_to_end_wire_compliance() -> void:
	print("\n--- end-to-end: real hail wire, real tree, victim actually complies ---")
	var victim = _make_ship(CargoShuttle, "WireVictim", 814, Vector2.ZERO, ["TEAM_WIREV"])
	victim.add_child(AITreeFactory.build_cargo())
	var issuer = _make_ship(ArmedPinnace, "WireIssuer", 815, Vector2(2000, 0), ["TEAM_WIREI"])
	# No AI tree on the issuer -- its own velocity-control loop would otherwise
	# actively brake it back toward the default target_velocity (0) before
	# sensors ever get a read, since nothing is commanding it to hold speed.
	# apply_control_input (velocity mode) makes the control loop MAINTAIN 900
	# instead of fighting a bare linear_velocity assignment.
	issuer.apply_control_input(0.0, 900.0, 0.0, 1, 1)

	# Let it actually reach ~900 (real mass/thrust acceleration, not instant)
	# AND let the victim correlate a sensor track on it, before demanding --
	# both are realistic preconditions every real job already satisfies.
	var issuer_trk: String = "TRK-%03d" % (abs(issuer.get_instance_id()) % 1000)
	var ready := false
	for i in range(1200): # up to 20s
		await main_node.get_tree().physics_frame
		if issuer.linear_velocity.length() >= 850.0 and victim.active_contacts.has(issuer_trk):
			ready = true
			break
	_assert(ready, "setup: issuer at speed and victim holds a track on it before being demanded")

	issuer.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)

	var complied := false
	for i in range(300): # up to 5s -- un-outrunnable from the first decision, no RUN phase needed
		await main_node.get_tree().physics_frame
		if not victim.compelled_stop.is_empty():
			complied = true
			break
	_assert(complied, "victim complied over the real wire protocol within the tree")

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_threat_response <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_threat_response <<<")
		get_tree().quit(1)
