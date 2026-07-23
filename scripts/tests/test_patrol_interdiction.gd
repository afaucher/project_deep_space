extends Node

# M52 -- patrol/station interdiction + SOS response acceptance
# (implementation_plans/m52_patrol_interdiction.md's "Tests" section). Proves
# the 2026-07-20 playtest regression is closed: a patrol/station holding a
# HOSTILE contact demands surrender BEFORE it fires, honors compliance, and
# still engages a refused demand exactly once (no re-demand loop) -- plus the
# response-class patience split, the ignored-challenge -> NO_ID -> intercept
# pipeline, and SOS response breaking a patrol off its route.
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames (Godot 2D physics/timing isn't bit-deterministic
# run-to-run, CLAUDE.md). RNG is seeded by the test runner (main.gd).
#
# Several phases attribute a hit directly via ship.take_damage(..., attacker_
# iid) rather than firing a real weapon -- the same effect a landed shot has
# (ASSAULT warrant + eager HOSTILE cache stamp, ship.gd), and the pattern
# M52c's own tests use for driving compliance directly (engage_dead_stop()).

const Frigate = preload("res://scripts/ships/frigate.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const InterdictLeaf = preload("res://scripts/ai/leaves/interdict_leaf.gd")

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

func _trk_for(ship: Node) -> String:
	return "TRK-%03d" % (abs(ship.get_instance_id()) % 1000)

# A Frigate's active sensors reach 40000 units with NO distance falloff --
# Phase 6's cast all sit well within that of each other. Phase 6 is entirely
# about the SOS/active_contacts mechanism (not real sensor detection), and
# its stale-SOS sub-case forces last_seen_timer high then waits for the
# CONTACT_TIMEOUT prune -- a real sensor correlation landing on the SAME
# track in the meantime would keep refreshing last_seen_timer right back
# down, making the prune never observable. Strip the patrol's sensors
# entirely (test_comms_relay.gd's existing pattern) so its active_contacts
# can only ever be populated by SOS/relay in this phase.
func _strip_sensors(ship: Node) -> void:
	ship.ship_components = ship.ship_components.filter(func(c): return c["type"] != "sensors")

func _has_contact(observer: Node, target: Node) -> bool:
	return observer.active_contacts.has(_trk_for(target))

func _max_weapon_cooldown(ship: Node) -> float:
	var m := 0.0
	for w in ship.get_components_by_type("weapons"):
		m = max(m, w.get("cooldown", 0.0))
	return m

func _count_demand_stop(receiver: Node, sender: Node) -> int:
	var n := 0
	for h in receiver.last_hails:
		if h.get("verb", "") == Hail.VERB_DEMAND and h.get("rung", "") == Hail.RUNG_STOP and h.get("sender_iid", -1) == sender.get_instance_id():
			n += 1
	return n

func _free_all() -> void:
	var freed: Array = spawned.duplicate()
	for s in freed:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	# Wait for the deferred frees to actually land before the next phase spawns
	# fresh ships -- queue_free() only takes effect at end-of-frame, and a new
	# ship spawned at the SAME position one frame early would otherwise get its
	# sensor return proximity-correlated onto the OLD (still-live, still-
	# HOSTILE) contact record of the ship it's replacing.
	for i in range(10):
		var all_gone := true
		for s in freed:
			if is_instance_valid(s):
				all_gone = false
				break
		if all_gone:
			break
		await main_node.get_tree().physics_frame

func setup(main) -> void:
	main_node = main
	print("Starting Patrol Interdiction (M52) Tests")
	await _phase_1_challenge_before_fire_and_refusal()
	await _phase_2_compliance_holds_and_resumes()
	await _phase_3_response_class_patience()
	await _phase_4_station_playtest_regression()
	await _phase_5_ignored_challenge_to_intercept()
	await _phase_6_sos_response()
	_finish()

# ---------------------------------------------------------------------------
# Phase 1: challenge-before-fire, then refusal -> engage, with no re-demand
# loop. A HOSTILE contact (attributed via take_damage, same effect a landed
# shot has) that never complies (no AI, holds position) must be demanded
# BEFORE any shot (weapons cooldown stays 0 the whole time up to the demand),
# then -- once the (test-shortened) patience expires un-complied -- actually
# engage, with exactly one DEMAND(STOP) ever logged (the refusal-memory
# invariant: no infinite re-demand loop).
# ---------------------------------------------------------------------------
func _phase_1_challenge_before_fire_and_refusal() -> void:
	print("\n--- Phase 1: challenge-before-fire, then refusal -> engage (no re-demand loop) ---")

	var patrol = _make_ship(Frigate, "P1_Patrol", 800, Vector2.ZERO, ["TEAM_PATROL_1"])
	patrol.add_child(AITreeFactory.build_patrol())

	var attacker = _make_ship(Frigate, "P1_Attacker", 801, Vector2(2000, 0), ["TEAM_ATTACKER_1"])
	# No AI tree -- never complies, holds position.

	var have_contact := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if _has_contact(patrol, attacker):
			have_contact = true
			break
	_assert(have_contact, "patrol correlated a sensor track on the attacker before the simulated hit")

	patrol.take_damage(50.0, patrol.position, Vector2.RIGHT, "kinetic", attacker.get_instance_id())

	var never_fired_before_demand := true
	var demand_received := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(attacker):
			break
		if _max_weapon_cooldown(patrol) > 0.0 and not demand_received:
			never_fired_before_demand = false
		if attacker.pending_demand.get("rung", "") == Hail.RUNG_STOP and attacker.pending_demand.get("sender_iid", -1) == patrol.get_instance_id():
			demand_received = true
			break

	_assert(demand_received, "the attacker received a DEMAND(STOP) from the patrol (pending_demand=%s)" % str(attacker.pending_demand))
	_assert(never_fired_before_demand, "patrol's weapons stayed cold (cooldown==0) the entire time until the demand was actually sent")
	_assert(patrol.assignment.get("victim_iid", -1) == attacker.get_instance_id(), "InterdictLeaf assigned the demand job against the attacker")

	var demand_count_at_arrival := _count_demand_stop(attacker, patrol)
	_assert(demand_count_at_arrival == 1, "exactly one DEMAND(STOP) logged on the attacker's own hail history at this point (got %d)" % demand_count_at_arrival)

	# Speed up the remaining wait -- the attacker never complies (no AI), so
	# shorten the assigned job's DEMAND_STOP patience so the refusal-abort ->
	# engage transition happens quickly instead of waiting the full 25s
	# production default.
	if patrol.assignment.has("steps") and patrol.assignment["steps"].size() > 1:
		patrol.assignment["steps"][1]["patience"] = 2.0

	var engaged := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(attacker):
			break
		if _max_weapon_cooldown(patrol) > 0.0:
			engaged = true
			break

	_assert(engaged, "patrol engaged (fired) after the demand went unanswered -- refusal -> engage")

	var demand_count_after := _count_demand_stop(attacker, patrol)
	_assert(demand_count_after == 1, "still exactly one DEMAND(STOP) on record right after engaging -- no re-demand loop (got %d)" % demand_count_after)

	for i in range(120): # hold 2s more and confirm the count still doesn't grow
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(attacker):
			break
	var demand_count_final := _count_demand_stop(attacker, patrol)
	_assert(demand_count_final == 1, "DEMAND(STOP) count stays at 1 even while the patrol continues engaging (got %d)" % demand_count_final)

	await _free_all()

# ---------------------------------------------------------------------------
# Phase 2: compliance -> hold, zero shots ever, job clears, patrol resumes
# FollowRoute (not stuck idle forever).
# ---------------------------------------------------------------------------
func _phase_2_compliance_holds_and_resumes() -> void:
	print("\n--- Phase 2: compliance -> hold, no fire, resume patrol route ---")

	var patrol = _make_ship(Frigate, "P2_Patrol", 802, Vector2.ZERO, ["TEAM_PATROL_2"])
	patrol.patrol_route = [Vector2(0, 30000), Vector2(30000, 30000)]
	patrol.patrol_loop = true
	patrol.add_child(AITreeFactory.build_patrol())

	var attacker = _make_ship(Frigate, "P2_Attacker", 803, Vector2(2000, 0), ["TEAM_ATTACKER_2"])
	# No AI -- compliance is driven directly the instant the demand arrives
	# (engage_dead_stop(), the same M52c Phase 3 pattern).

	var have_contact := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if _has_contact(patrol, attacker):
			have_contact = true
			break
	_assert(have_contact, "patrol correlated a sensor track on the attacker before the simulated hit")

	patrol.take_damage(50.0, patrol.position, Vector2.RIGHT, "kinetic", attacker.get_instance_id())

	var never_fired := true
	var complied := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(attacker):
			break
		if _max_weapon_cooldown(patrol) > 0.0:
			never_fired = false
		if not complied and attacker.pending_demand.get("rung", "") == Hail.RUNG_STOP and attacker.pending_demand.get("sender_iid", -1) == patrol.get_instance_id():
			attacker.engage_dead_stop()
			complied = true
			break
	_assert(complied, "the attacker received and acted on the DEMAND(STOP)")

	var held := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(attacker):
			break
		if _max_weapon_cooldown(patrol) > 0.0:
			never_fired = false
		if attacker.compelled_stop.get("issuer_iid", -1) == patrol.get_instance_id():
			held = true
			break
	_assert(held, "the attacker's compliance was held (compelled_stop=%s)" % str(attacker.compelled_stop))

	var assignment_cleared := false
	for i in range(600): # up to 10s -- DEMAND_STOP DONE clears the assignment
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol):
			break
		if _max_weapon_cooldown(patrol) > 0.0:
			never_fired = false
		if patrol.assignment.is_empty():
			assignment_cleared = true
			break
	_assert(assignment_cleared, "the patrol's job cleared once the victim complied")
	_assert(never_fired, "zero shots were ever fired across the whole encounter")

	# Resume: the patrol keeps moving (its route, not stuck idle) after the
	# job clears -- record position at clear time and confirm it moves on.
	var pos_at_clear: Vector2 = patrol.position
	var moved := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol):
			break
		if patrol.position.distance_to(pos_at_clear) > 500.0:
			moved = true
			break
	_assert(moved, "the patrol resumed moving (FollowRoute) after the job cleared, not stuck idle")
	_assert(patrol.assignment.is_empty(), "the patrol did not re-demand the still-complied attacker")

	await _free_all()

# ---------------------------------------------------------------------------
# Phase 3: response-class patience differs end to end -- a RESPONSE_MAX-class
# warrant (ARMED_ROBBERY) gets a shorter DEMAND_STOP patience than a
# RESPONSE_INTERCEPT-class one (ASSAULT), read off the ACTUAL assigned job,
# not Standing.response_class() in isolation.
# ---------------------------------------------------------------------------
func _phase_3_response_class_patience() -> void:
	print("\n--- Phase 3: response-class patience differs (MAX vs INTERCEPT) ---")

	var patrol_a = _make_ship(Frigate, "P3A_Patrol", 810, Vector2.ZERO, ["TEAM_PATROL_3A"])
	patrol_a.add_child(AITreeFactory.build_patrol())
	var attacker_a = _make_ship(Frigate, "P3A_Attacker", 811, Vector2(2000, 0), ["TEAM_ATTACKER_3A"])
	attacker_a.set_transponder_custom_name("Robber A")
	attacker_a.set_transponder_active(true)

	var patrol_b = _make_ship(Frigate, "P3B_Patrol", 812, Vector2(60000, 0), ["TEAM_PATROL_3B"])
	patrol_b.add_child(AITreeFactory.build_patrol())
	var attacker_b = _make_ship(Frigate, "P3B_Attacker", 813, Vector2(62000, 0), ["TEAM_ATTACKER_3B"])
	attacker_b.set_transponder_custom_name("Assaulter B")
	attacker_b.set_transponder_active(true)

	var have_names := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if patrol_a.active_transponders.get(attacker_a.get_instance_id(), {}).get("name", "") == "Robber A" \
		and patrol_b.active_transponders.get(attacker_b.get_instance_id(), {}).get("name", "") == "Assaulter B":
			have_names = true
			break
	_assert(have_names, "both patrols correlated the attackers' claimed transponder names")

	patrol_a.post_warrant(Standing.OFF_ARMED_ROBBERY, "Robber A", {}, "test MAX-class")
	patrol_b.post_warrant(Standing.OFF_ASSAULT, "Assaulter B", {}, "test INTERCEPT-class")

	var assigned_a := false
	var assigned_b := false
	var patience_a := -1.0
	var patience_b := -1.0
	for i in range(900): # up to 15s -- worst-case sensor recompute lag
		await main_node.get_tree().physics_frame
		if not assigned_a and patrol_a.assignment.get("victim_iid", -1) == attacker_a.get_instance_id():
			assigned_a = true
			patience_a = patrol_a.assignment["steps"][1].get("patience", -1.0)
		if not assigned_b and patrol_b.assignment.get("victim_iid", -1) == attacker_b.get_instance_id():
			assigned_b = true
			patience_b = patrol_b.assignment["steps"][1].get("patience", -1.0)
		if assigned_a and assigned_b:
			break

	_assert(assigned_a, "InterdictLeaf assigned a demand job against the MAX-class (ARMED_ROBBERY) target")
	_assert(assigned_b, "InterdictLeaf assigned a demand job against the INTERCEPT-class (ASSAULT) target")
	if assigned_a and assigned_b:
		_assert(patience_a < patience_b, "MAX-class patience (%.1f) is shorter than INTERCEPT-class patience (%.1f)" % [patience_a, patience_b])
		_assert(is_equal_approx(patience_a, InterdictLeaf.PATIENCE_MAX), "MAX-class patience matches InterdictLeaf.PATIENCE_MAX (%.1f), got %.1f" % [InterdictLeaf.PATIENCE_MAX, patience_a])
		_assert(is_equal_approx(patience_b, InterdictLeaf.PATIENCE_INTERCEPT), "INTERCEPT-class patience matches InterdictLeaf.PATIENCE_INTERCEPT (%.1f), got %.1f" % [InterdictLeaf.PATIENCE_INTERCEPT, patience_b])

	await _free_all()

# ---------------------------------------------------------------------------
# Phase 4: the exact playtest regression. A station holding a fresh HOSTILE
# contact (player fired on it) demands surrender instead of attacking
# outright; the player complying is held, not executed.
# ---------------------------------------------------------------------------
func _phase_4_station_playtest_regression() -> void:
	print("\n--- Phase 4: exact playtest regression -- station demands, doesn't instant-attack; compliance held ---")

	var station = _make_ship(SmallStation, "P4_Station", 820, Vector2.ZERO, ["TEAM_STATION_4"])
	station.add_child(AITreeFactory.build_station())

	var player = _make_ship(Frigate, "P4_Player", 821, Vector2(2000, 0), ["TEAM_PLAYER_4"])
	# No AI -- player-analog test ship (M52c Phase 3's pattern).

	var have_contact := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if _has_contact(station, player):
			have_contact = true
			break
	_assert(have_contact, "station correlated a sensor track on the player before the simulated hit")

	# The player "fires on the station" -- the 2026-07-20 playtest's exact trigger.
	station.take_damage(50.0, station.position, Vector2.RIGHT, "kinetic", player.get_instance_id())

	var never_fired_before_demand := true
	var demand_received := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(station) or not is_instance_valid(player):
			break
		if _max_weapon_cooldown(station) > 0.0 and not demand_received:
			never_fired_before_demand = false
		if player.pending_demand.get("rung", "") == Hail.RUNG_STOP and player.pending_demand.get("sender_iid", -1) == station.get_instance_id():
			demand_received = true
			break

	_assert(demand_received, "the station demanded a stop instead of attacking outright (pending_demand=%s)" % str(player.pending_demand))
	_assert(never_fired_before_demand, "station's weapons stayed cold until the demand was sent -- no instant attack")

	player.engage_dead_stop()

	var held := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(station) or not is_instance_valid(player):
			break
		if _max_weapon_cooldown(station) > 0.0:
			never_fired_before_demand = false
		if player.compelled_stop.get("issuer_iid", -1) == station.get_instance_id():
			held = true
			break
	_assert(held, "the player's compliance was held (compelled_stop=%s)" % str(player.compelled_stop))

	var still_never_fired := true
	for i in range(300): # 5s more -- the station must not execute a held target
		await main_node.get_tree().physics_frame
		if not is_instance_valid(station) or not is_instance_valid(player):
			break
		if _max_weapon_cooldown(station) > 0.0:
			still_never_fired = false
			break
	_assert(still_never_fired, "station never fired on the held, complying player")
	_assert(never_fired_before_demand, "station's weapons stayed cold across the whole encounter (pre-demand AND while held)")

	await _free_all()

# ---------------------------------------------------------------------------
# Phase 5: ignored IDENTIFY challenge -> OFF_NO_ID warrant -> InterdictLeaf
# picks it up (the whole M52 item-3 loop, end to end).
# ---------------------------------------------------------------------------
func _phase_5_ignored_challenge_to_intercept() -> void:
	print("\n--- Phase 5: ignored IDENTIFY challenge -> NO_ID warrant -> InterdictLeaf ---")

	var control = _make_ship(Frigate, "P5_Control", 830, Vector2.ZERO, ["TEAM_CONTROL_5"])
	control.port_zone = {"radius": 8000.0, "authority": "TestControl5"}

	var patrol = _make_ship(Frigate, "P5_Patrol", 831, Vector2(3000, 2000), ["TEAM_PATROL_5"])
	patrol.add_child(AITreeFactory.build_patrol())

	var dark_ship = _make_ship(Frigate, "P5_Dark", 832, Vector2(3000, 0), ["TEAM_DARK_5"])
	dark_ship.set_transponder_active(false) # never relights

	var challenged := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if dark_ship.pending_demand.get("rung", "") == Hail.RUNG_IDENTIFY and dark_ship.pending_demand.get("sender_iid", -1) == patrol.get_instance_id():
			challenged = true
			break
	_assert(challenged, "the dark ship got a DEMAND(IDENTIFY) from the patrol")

	var warrant_posted := false
	var picked_up := false
	for i in range(2700): # up to 45s -- ~20s challenge window + recompute + intercept-assignment margin
		await main_node.get_tree().physics_frame
		if not is_instance_valid(patrol) or not is_instance_valid(dark_ship):
			break
		if not warrant_posted:
			for key in patrol.warrants:
				if patrol.warrants[key].get("offense", "") == Standing.OFF_NO_ID:
					warrant_posted = true
					break
		if patrol.assignment.get("victim_iid", -1) == dark_ship.get_instance_id():
			picked_up = true
			break

	_assert(warrant_posted, "an OFF_NO_ID warrant was posted after the identify challenge went unanswered")
	_assert(picked_up, "InterdictLeaf picked up the NO_ID-warranted contact and assigned a demand job against it")

	await _free_all()

# ---------------------------------------------------------------------------
# Phase 6: SOS response. A patrol on a far-off route hears a distress call and
# breaks off to close the distance; a stale SOS is never adopted; after one
# incident resolves, a LATER, different SOS is still picked up.
# ---------------------------------------------------------------------------
func _phase_6_sos_response() -> void:
	print("\n--- Phase 6: SOS response -- responds, stale doesn't, later different SOS after resolve ---")

	var patrol = _make_ship(Frigate, "P6_Patrol", 840, Vector2.ZERO, ["TEAM_PATROL_6"])
	_strip_sensors(patrol)
	patrol.patrol_route = [Vector2(0, 25000), Vector2(25000, 25000)]
	patrol.patrol_loop = true
	var patrol_tree: Node = AITreeFactory.build_patrol()
	patrol.add_child(patrol_tree)

	var victim1 = _make_ship(Frigate, "P6_Victim1", 841, Vector2(-12000, 3000), ["TEAM_VICTIM6A"])
	var victim2 = _make_ship(Frigate, "P6_Victim2", 842, Vector2(12000, -6000), ["TEAM_VICTIM6B"])
	var stale_sender = _make_ship(Frigate, "P6_Stale", 843, Vector2(-8000, -3000), ["TEAM_STALE6"])

	var bb = patrol_tree.blackboard

	# --- sub-case: a stale SOS is never adopted. ---
	# M52 follow-up (implementation_plans/m52_sos_as_contact.md): SOS is now
	# a heartbeat toggle (set_sos_active) creating/refreshing a real
	# "DISTRESS CALL" active_contacts entry, decaying on the normal
	# CONTACT_TIMEOUT clock -- no more separate heard_sos/HEARD_SOS_TTL
	# side-channel. sos_responding_to is now keyed by track id (the
	# active_contacts key), not instance id.
	var stale_trk: String = _trk_for(stale_sender)
	stale_sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)

	var heard_stale := false
	for i in range(300): # up to 5s for the broadcast to land
		await main_node.get_tree().physics_frame
		if patrol.active_contacts.has(stale_trk):
			heard_stale = true
			break
	_assert(heard_stale, "patrol heard the stale-sender's SOS (a DISTRESS CALL contact)")

	# Stop the heartbeat (incident "resolved") and force the contact stale
	# immediately -- skip the real 20s CONTACT_TIMEOUT wait, mutating the
	# same last_seen_timer field ship.gd's own contact-decay loop reads.
	stale_sender.set_sos_active(false, "")
	if patrol.active_contacts.has(stale_trk):
		patrol.active_contacts[stale_trk]["last_seen_timer"] = 9999.0

	var stale_pruned := false
	for i in range(60):
		await main_node.get_tree().physics_frame
		if not patrol.active_contacts.has(stale_trk):
			stale_pruned = true
			break
	_assert(stale_pruned, "the stale SOS contact was pruned by CONTACT_TIMEOUT")
	_assert(bb.get_value("sos_responding_to", "") != stale_trk, "the patrol never adopted the stale SOS as its response target")

	# --- sub-case: a fresh SOS breaks off the route. ---
	var victim1_trk: String = _trk_for(victim1)
	var start_dist: float = patrol.position.distance_to(victim1.position)
	victim1.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)

	var adopted := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if bb.get_value("sos_responding_to", "") == victim1_trk:
			adopted = true
			break
	_assert(adopted, "the patrol adopted victim1's SOS as its response target")

	var closed_in := false
	for i in range(600): # up to 10s of closing
		await main_node.get_tree().physics_frame
		if patrol.position.distance_to(victim1.position) < start_dist - 500.0:
			closed_in = true
			break
	_assert(closed_in, "the patrol broke off its route and closed the distance toward the SOS marker")

	# --- sub-case: a LATER, different SOS is picked up once the first
	# resolves. Simulate resolution directly (the resolution MECHANISM --
	# arrival radius/staleness/hostile-preempt -- is the leaf's own logic,
	# already exercised above and by the stale sub-case) so this sub-case
	# stays focused on "the slot frees up and a later call still lands".
	bb.erase_value("sos_responding_to")
	victim1.set_sos_active(false, "") # stop the heartbeat so it can't recreate the contact
	patrol.active_contacts.erase(victim1_trk)

	var settled := false
	for i in range(60):
		await main_node.get_tree().physics_frame
		if not bb.has_value("sos_responding_to"):
			settled = true
			break
	_assert(settled, "the patrol's SOS-response slot cleared once the first incident resolved")

	var victim2_trk: String = _trk_for(victim2)
	victim2.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)
	var adopted2 := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		if bb.get_value("sos_responding_to", "") == victim2_trk:
			adopted2 = true
			break
	_assert(adopted2, "after the first SOS resolved, the patrol adopted a LATER, different SOS")

	await _free_all()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_patrol_interdiction <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_patrol_interdiction <<<")
		get_tree().quit(1)
