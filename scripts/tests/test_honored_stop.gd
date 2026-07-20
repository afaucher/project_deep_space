extends Node

# M49 -- the honored-stop hard guarantees (design_ideas/comms_verbs.md's
# "Stopped-under-compulsion"): ship-level enforcement (compelled_stop), AI
# honor rules (acquire/fire suspenders), RELEASE, and auto-resume. Also folds
# in the cargo comply-or-run speed-ratio decision (comms_verbs.md's "Cargo/
# civilian" policy) -- the milestone spec explicitly says this doesn't need
# its own file ("test_fast_ship_runs").
#
# Mixes test_fire_staleness_gate.gd's synchronous MANUAL-tree/hand-injected-
# contact style (mechanical ship/leaf-level guarantees: fire guard, acquire-
# skip) with test_drift_residents.gd's `await get_tree().physics_frame`
# live-ship style (RELEASE/auto-resume/comply-or-run, which need real comms
# delivery + AI ticking over sim time). Godot 2D physics/timing isn't
# bit-deterministic run-to-run (CLAUDE.md), so live-ship assertions use
# generous settle loops/margins, never exact frames.

const Frigate = preload("res://scripts/ships/frigate.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const AcquireTargetLeaf = preload("res://scripts/ai/leaves/acquire_target_leaf.gd")
const FireOpportunityLeaf = preload("res://scripts/ai/leaves/fire_opportunity_leaf.gd")
const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(script, ship_name: String, owner: int, pos: Vector2, tags: Array = ["TEAM_A"]) -> Node:
	var ship = script.new()
	ship.name = ship_name
	ship.owner_id = owner
	ship.iff_tags = tags
	ship.position = pos
	main_node.add_child(ship)
	spawned.append(ship)
	return ship

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func setup(main) -> void:
	main_node = main
	print("Starting Honored Stop (M49) Tests")

	_test_fire_guard()
	_test_acquire_skip()
	_test_wreck_gate()
	await _test_comply_flow()
	await _test_fast_ship_runs()
	_test_peak_speed_comply()
	await _test_release()
	await _test_auto_resume()

	_finish()

# --- M52a (H1): comply-or-run compares against the threat's PEAK observed
# speed, not the near-zero speed it coasts at once alongside to demand. This
# is the campaign's zero-takes bug: a pirate decelerates to hail range, so at
# demand time it looks stationary and EVERY victim "outran" it and ran, so no
# robbery ever completed. Deterministic (hand-injected contacts, no physics
# frames between ticks -- the leaf is called directly, same style as
# _test_fire_guard). -----------------------------------------------------------
func _test_peak_speed_comply() -> void:
	print("\n--- H1 comply-or-run: peak speed, not demand-time speed ---")
	var shuttle = _make_ship(CargoShuttle, "PeakShuttle", 530, Vector2(400000, 0), ["TEAM_CARGO3"])
	var leaf = ThreatResponseLeaf.new()

	# Case A: a pirate that CHASED fast (peak ~900) then slowed to demand.
	var bb = BlackboardScript.new()
	var iid := 424242
	var trk := "TRK-%03d" % (abs(iid) % 1000)
	shuttle.active_contacts = {trk: {"instance_id": iid, "vel": Vector2(900, 0),
		"pos": Vector2(401000, 0), "last_seen_timer": 0.0, "classification": "UNIDENTIFIED VESSEL"}}
	shuttle.pending_demand = {}
	leaf.tick(shuttle, bb)  # no demand -> records peak 900 for this track
	shuttle.active_contacts[trk]["vel"] = Vector2(15, 0)  # decelerated to hail range
	shuttle.pending_demand = {"rung": Hail.RUNG_STOP, "seq": 7, "sender_iid": iid,
		"sender_pos": Vector2(401000, 0), "sender_flag": Standing.FLAG_PIRATE, "target_iid": shuttle.get_instance_id()}
	leaf.tick(shuttle, bb)
	# RUN sets threat_issuer_iid on the blackboard; COMPLY does not.
	_assert(not bb.has_value("threat_issuer_iid"),
		"peak capability (900) makes a slow-at-demand pirate a COMPLY (old code saw ~0 and RAN)")

	# Case B: a genuinely slow threat (peak ~50) a cargo really can outrun -> RUN.
	# Clear the compulsion Case A's COMPLY set, or the leaf early-returns "held".
	shuttle.compelled_stop = {}
	var bb2 = BlackboardScript.new()
	var iid2 := 434343
	var trk2 := "TRK-%03d" % (abs(iid2) % 1000)
	shuttle.active_contacts = {trk2: {"instance_id": iid2, "vel": Vector2(50, 0),
		"pos": Vector2(402000, 0), "last_seen_timer": 0.0, "classification": "UNIDENTIFIED VESSEL"}}
	shuttle.pending_demand = {}
	leaf.tick(shuttle, bb2)  # records peak 50
	shuttle.pending_demand = {"rung": Hail.RUNG_STOP, "seq": 8, "sender_iid": iid2,
		"sender_pos": Vector2(402000, 0), "sender_flag": Standing.FLAG_PIRATE, "target_iid": shuttle.get_instance_id()}
	leaf.tick(shuttle, bb2)
	_assert(bb2.has_value("threat_issuer_iid"),
		"a genuinely slow threat (peak 50) is still a RUN -- the fix doesn't make everyone comply")

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_honored_stop <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_honored_stop <<<")
		get_tree().quit(1)

# --- Fire guard: compelled_stop suspends fire_weapon (ship.gd) --------------
func _test_fire_guard() -> void:
	print("\n--- Fire guard: compelled_stop suspends fire_weapon ---")
	var ship = _make_ship(Frigate, "FireGuardShip", 500, Vector2.ZERO)
	ship.compelled_stop = {"issuer_iid": -1, "demand_seq": 1, "lost_issuer_timer": 0.0}

	var laser_id := ""
	for w in ship.get_components_by_type("weapons"):
		if w.get("weapon_type", "") == "laser":
			laser_id = w["id"]
			break
	_assert(laser_id != "", "setup sanity: frigate has a laser weapon")

	var cooldown_before: float = ship.get_component(laser_id).get("cooldown", 0.0)
	ship.fire_weapon(laser_id, ship.position + Vector2(4000, 0), "")
	_assert(ship.get_component(laser_id).get("cooldown", 0.0) == cooldown_before,
		"held ship: fire_weapon refuses while compelled_stop is set (cooldown unchanged)")

# --- AI honor: acquire_target_leaf/fire_opportunity_leaf skip a held ship,
# in BOTH directions (the actor itself held; a target that's complied) -------
func _test_acquire_skip() -> void:
	print("\n--- AI honor: no leaf targets/acts on a held ship (both directions) ---")
	var acquire = AcquireTargetLeaf.new()

	# (a) the ACTOR is held -- a held ship doesn't hunt, regardless of what's
	# in weapons range.
	var actor_a = _make_ship(Frigate, "HeldHunter", 501, Vector2.ZERO)
	actor_a.compelled_stop = {"issuer_iid": -1, "demand_seq": 1, "lost_issuer_timer": 0.0}
	actor_a.active_contacts["TGT"] = {"pos": Vector2(3000, 0), "vel": Vector2.ZERO, "classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE", "last_seen_timer": 0.0}
	var r_a = acquire.tick(actor_a, BlackboardScript.new())
	_assert(r_a == acquire.FAILURE, "compelled actor: AcquireTarget returns FAILURE even with a fresh HOSTILE contact in range")

	# (b) the actor is FREE, but the only hostile contact is a compliant
	# stopped ship -- no leaf targets it (customs, arrest, or robbery alike).
	var actor_b = _make_ship(Frigate, "FreeHunter", 502, Vector2.ZERO)
	actor_b.active_contacts["TGT2"] = {"pos": Vector2(3000, 0), "vel": Vector2.ZERO, "classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE", "last_seen_timer": 0.0, "complied_stop": true}
	var r_b = acquire.tick(actor_b, BlackboardScript.new())
	_assert(r_b == acquire.FAILURE, "free actor: AcquireTarget skips a HOSTILE contact carrying complied_stop")

	# fire_opportunity_leaf's own suspender (belt to fire_weapon's).
	var fire_leaf = FireOpportunityLeaf.new()
	var actor_c = _make_ship(Frigate, "HeldShooter", 503, Vector2.ZERO)
	actor_c.compelled_stop = {"issuer_iid": -1, "demand_seq": 1, "lost_issuer_timer": 0.0}
	var laser_id2 := ""
	for w in actor_c.get_components_by_type("weapons"):
		if w.get("weapon_type", "") == "laser":
			laser_id2 = w["id"]
			break
	var bb3 = BlackboardScript.new()
	bb3.set_value("target_id", "TGT3")
	bb3.set_value("target_pos", Vector2(1000, 0))
	actor_c.active_contacts["TGT3"] = {"pos": Vector2(1000, 0), "vel": Vector2.ZERO, "classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE", "last_seen_timer": 0.0}
	var cooldown_before2: float = actor_c.get_component(laser_id2).get("cooldown", 0.0)
	var r_c = fire_leaf.tick(actor_c, bb3)
	_assert(r_c == fire_leaf.SUCCESS, "fire_opportunity_leaf returns SUCCESS (not RUNNING/FAILURE) while suspended")
	_assert(actor_c.get_component(laser_id2).get("cooldown", 0.0) == cooldown_before2,
		"fire_opportunity_leaf: held actor's own suspender holds fire")

# --- Wreck gate: a sticky-HOSTILE contact classified WRECKAGE is never an
# acquirable target -- playtest regression (stations/defense pods kept firing
# on wrecks because Standing.HOSTILE never clears on death; classification
# does flip to WRECKAGE, see Ship.classify_contact) --------------------------
func _test_wreck_gate() -> void:
	print("\n--- Wreck gate: HOSTILE + WRECKAGE classification is never acquired ---")
	var acquire = AcquireTargetLeaf.new()

	# These actors are ticked synchronously and never needed again -- spawn
	# them FAR from the origin (where _test_comply_flow's live shuttle runs)
	# and free them at the end, so three extra frigate bodies don't stack on
	# the later live-ship scenarios' spawn point and perturb their physics.
	var wg_base := Vector2(200000, 200000)
	var actor_wreck = _make_ship(Frigate, "WreckHunter", 504, wg_base)
	actor_wreck.active_contacts["TGT4"] = {"pos": wg_base + Vector2(3000, 0), "vel": Vector2.ZERO, "classification": "WRECKAGE", "standing": "HOSTILE", "last_seen_timer": 0.0}
	var r_wreck = acquire.tick(actor_wreck, BlackboardScript.new())
	_assert(r_wreck == acquire.FAILURE, "AcquireTarget skips a HOSTILE contact classified WRECKAGE")

	var actor_live = _make_ship(Frigate, "LiveHunter", 505, wg_base + Vector2(0, 20000))
	actor_live.active_contacts["TGT5"] = {"pos": actor_live.position + Vector2(3000, 0), "vel": Vector2.ZERO, "classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE", "last_seen_timer": 0.0}
	var r_live = acquire.tick(actor_live, BlackboardScript.new())
	_assert(r_live == acquire.SUCCESS, "AcquireTarget still acquires the same HOSTILE contact when classified UNIDENTIFIED VESSEL")

	# fire_opportunity_leaf's belt-and-suspenders: never fire on a target that
	# has since classified WRECKAGE, even if it's still the published blackboard target.
	var fire_leaf = FireOpportunityLeaf.new()
	var actor_wreck2 = _make_ship(Frigate, "WreckShooter", 506, wg_base + Vector2(0, 40000))
	var laser_id3 := ""
	for w in actor_wreck2.get_components_by_type("weapons"):
		if w.get("weapon_type", "") == "laser":
			laser_id3 = w["id"]
			break
	var bb4 = BlackboardScript.new()
	bb4.set_value("target_id", "TGT6")
	bb4.set_value("target_pos", actor_wreck2.position + Vector2(1000, 0))
	actor_wreck2.active_contacts["TGT6"] = {"pos": actor_wreck2.position + Vector2(1000, 0), "vel": Vector2.ZERO, "classification": "WRECKAGE", "standing": "HOSTILE", "last_seen_timer": 0.0}
	var cooldown_before3: float = actor_wreck2.get_component(laser_id3).get("cooldown", 0.0)
	var r_wreck2 = fire_leaf.tick(actor_wreck2, bb4)
	_assert(r_wreck2 == fire_leaf.SUCCESS, "fire_opportunity_leaf returns SUCCESS (not firing) on a WRECKAGE-classified target")
	_assert(actor_wreck2.get_component(laser_id3).get("cooldown", 0.0) == cooldown_before3,
		"fire_opportunity_leaf: never spends a laser's cooldown on a WRECKAGE-classified target")

	# Done with all three -- remove them so they can't sensor-link into or
	# collide with the later live-ship scenarios.
	for a in [actor_wreck, actor_live, actor_wreck2]:
		spawned.erase(a)
		a.queue_free()

# --- Cargo comply-or-run: SLOW threat -> shuttle complies -------------------
func _test_comply_flow() -> void:
	print("\n--- Cargo comply-or-run: SLOW threat -> shuttle complies ---")
	var shuttle = _make_ship(CargoShuttle, "ComplyShuttle", 510, Vector2.ZERO, ["TEAM_CARGO"])
	# CargoShuttle is deliberately low-accel (design: "mass ~40, accel ~25") --
	# a modest cruising speed so braking to near-zero comfortably fits the
	# settle window below, even at Smooth-mode's reduced throttle authority
	# (the compelled-stop override doesn't touch steering_mode).
	shuttle.linear_velocity = Vector2(250, 0) # cruising -- must observably brake to ~0
	shuttle.add_child(AITreeFactory.build_cargo())

	# Far enough that a moderate closing velocity, sustained across the
	# settle-wait below, never lets the issuer reach (let alone overshoot
	# past) the shuttle -- a receding issuer past the shuttle would read as
	# "moving away" and flip the whole scenario's arithmetic.
	var issuer = _make_ship(Frigate, "SlowIssuer", 511, Vector2(10000, 0), ["TEAM_PIRATE"])
	# A closing velocity comfortably clearing RUN_SPEED_RATIO's (1.3x)
	# threshold against the shuttle's 1000 max_speed (breakeven ~769) --
	# margin against sensor noise / fusion lerp, per issuer.FIRE_STALENESS_MAX.
	issuer.linear_velocity = Vector2(-800, 0)

	var listener = _make_ship(Frigate, "ComplyListener", 512, Vector2(500, 3000), ["TEAM_NEUTRAL"])

	# threat_response_leaf needs a real velocity estimate off a fresh track,
	# or it defaults to "no track -> treat as slow" and would always RUN --
	# wait for MUTUAL fresh tracks before demanding: the shuttle needs one on
	# the issuer for the speed-ratio decision, and the issuer needs one on the
	# shuttle BEFORE the COMPLY lands, or the COMPLY handler's "if I hold a
	# track on the sender" check (ship.gd's comms_inbox) has nothing to stamp
	# complied_stop onto -- COMPLY is a one-shot event, not a sticky retroactive
	# state, per design_ideas/comms_verbs.md.
	var settled := false
	for i in range(360): # up to 6s
		await main_node.get_tree().physics_frame
		var c: Dictionary = _find_contact(shuttle, issuer)
		var ic: Dictionary = _find_contact(issuer, shuttle)
		if (not c.is_empty() and c.get("last_seen_timer", 999.0) <= shuttle.FIRE_STALENESS_MAX
			and not ic.is_empty() and ic.get("last_seen_timer", 999.0) <= issuer.FIRE_STALENESS_MAX):
			settled = true
			break
	_assert(settled, "setup sanity: shuttle and issuer hold mutual fresh tracks before the demand")

	issuer.send_demand(shuttle.get_instance_id(), Hail.RUNG_STOP)

	var complied := false
	for i in range(900): # up to 15s -- low-accel hull rotating onto its drift + braking at Smooth-mode authority
		await main_node.get_tree().physics_frame
		if shuttle.compelled_stop.get("issuer_iid", -1) == issuer.get_instance_id() and shuttle.linear_velocity.length() < 40.0:
			complied = true
			break
	_assert(complied, "shuttle complied: compelled_stop set from the issuer, speed settled near zero (speed=%.1f, compelled_stop=%s)" % [shuttle.linear_velocity.length(), str(shuttle.compelled_stop)])

	var transponder_active := false
	for c in shuttle.ship_components:
		if c.get("type", "") == "comms":
			transponder_active = c.get("transponder_active", false)
	_assert(transponder_active, "shuttle's transponder is forced on (STOP implies IDENTIFY)")

	# The COMPLY broadcast fires the moment compliance is decided (before the
	# settle loop above even starts) -- since the mutual-track wait already
	# guaranteed the issuer held a live track on the shuttle at that instant,
	# the flag should already be there; poll briefly for the SOS + the flag.
	var issuer_saw_comply := false
	var sos_heard := false
	for i in range(180): # up to 3s
		await main_node.get_tree().physics_frame
		if not issuer_saw_comply:
			var ic2: Dictionary = _find_contact(issuer, shuttle)
			issuer_saw_comply = ic2.get("complied_stop", false)
		if not sos_heard:
			sos_heard = listener.heard_sos.has(shuttle.get_instance_id())
		if issuer_saw_comply and sos_heard:
			break
	_assert(issuer_saw_comply, "issuer's own track on the shuttle shows complied_stop (COMPLY was heard)")
	_assert(sos_heard, "shuttle broadcasts SOS(UNDER_ATTACK) on the incident even while complying")

# --- Cargo comply-or-run: threat too slow to catch a fast hull -> RUNS ------
func _test_fast_ship_runs() -> void:
	print("\n--- Cargo comply-or-run: threat can't catch a fast hull -> shuttle RUNS ---")
	var shuttle = _make_ship(CargoShuttle, "RunShuttle", 520, Vector2(20000, 0), ["TEAM_CARGO2"])
	shuttle.add_child(AITreeFactory.build_cargo())

	var issuer = _make_ship(Frigate, "StationaryIssuer", 521, Vector2(23000, 0), ["TEAM_PIRATE2"])
	issuer.linear_velocity = Vector2.ZERO # near-stationary -- trivially outrun

	var listener = _make_ship(Frigate, "RunListener", 522, Vector2(20500, 3000), ["TEAM_NEUTRAL2"])

	var settled := false
	for i in range(360):
		await main_node.get_tree().physics_frame
		var c: Dictionary = _find_contact(shuttle, issuer)
		if not c.is_empty() and c.get("last_seen_timer", 999.0) <= shuttle.FIRE_STALENESS_MAX:
			settled = true
			break
	_assert(settled, "setup sanity: shuttle acquired a fresh track on the issuer before the demand")

	issuer.send_demand(shuttle.get_instance_id(), Hail.RUNG_STOP)

	var ran := false
	var sos_heard := false
	for i in range(600): # up to 10s -- low-accel hull, even at full COMBAT authority
		await main_node.get_tree().physics_frame
		if not ran and shuttle.linear_velocity.length() > 250.0 and shuttle.compelled_stop.is_empty():
			ran = true
		if not sos_heard:
			sos_heard = listener.heard_sos.has(shuttle.get_instance_id())
		if ran and sos_heard:
			break
	_assert(ran, "fast shuttle RUNS instead of complying (speed=%.1f, compelled_stop=%s)" % [shuttle.linear_velocity.length(), str(shuttle.compelled_stop)])
	_assert(sos_heard, "shuttle broadcasts SOS(UNDER_ATTACK) on the incident even while running")
	_assert(shuttle.compelled_stop.is_empty(), "a running shuttle never sets compelled_stop")

# --- RELEASE clears compelled_stop; ship is free to thrust again ------------
func _test_release() -> void:
	print("\n--- RELEASE clears compelled_stop; ship is free to thrust again ---")
	var held = _make_ship(Frigate, "ReleaseHeld", 530, Vector2.ZERO, ["TEAM_HELD"])
	var issuer = _make_ship(Frigate, "ReleaseIssuer", 531, Vector2(3000, 0), ["TEAM_ISSUER"])

	# Directly compel (bypass the delivery path -- already covered by
	# test_hail_protocol.gd; this test is about RELEASE + resumed motion).
	held.pending_demand = {"rung": Hail.RUNG_STOP, "seq": 1, "sender_iid": issuer.get_instance_id(), "sender_pos": issuer.position, "sender_flag": "", "target_iid": held.get_instance_id()}
	held.comply_with_stop()
	_assert(not held.compelled_stop.is_empty(), "setup sanity: held ship is compelled after comply_with_stop()")

	issuer.send_release(held.get_instance_id())

	var released := false
	for i in range(180): # up to 3s
		await main_node.get_tree().physics_frame
		if held.compelled_stop.is_empty():
			released = true
			break
	_assert(released, "RELEASE clears compelled_stop")

	held.apply_control_input(1.0, 0.0, 0.0, 1, 0) # direct throttle, full forward, combat mode
	var speed_before: float = held.linear_velocity.length()
	for i in range(60): # 1s of thrust
		await main_node.get_tree().physics_frame
	_assert(held.linear_velocity.length() > speed_before + 10.0,
		"released ship responds to thrust again (speed %.1f -> %.1f)" % [speed_before, held.linear_velocity.length()])

# --- Auto-resume: a dead/freed issuer doesn't hold a ship forever -----------
func _test_auto_resume() -> void:
	print("\n--- Auto-resume: nobody waits forever on a dead issuer's permission ---")
	var held = _make_ship(Frigate, "AutoResumeHeld", 540, Vector2.ZERO, ["TEAM_HELD2"])
	var issuer = _make_ship(Frigate, "AutoResumeIssuer", 541, Vector2(3000, 0), ["TEAM_ISSUER2"])

	held.pending_demand = {"rung": Hail.RUNG_STOP, "seq": 1, "sender_iid": issuer.get_instance_id(), "sender_pos": issuer.position, "sender_flag": "", "target_iid": held.get_instance_id()}
	held.comply_with_stop()
	_assert(not held.compelled_stop.is_empty(), "setup sanity: held ship is compelled")

	issuer.queue_free()
	spawned.erase(issuer)
	await main_node.get_tree().physics_frame # let the free actually take effect

	# COMPELLED_STOP_LOST_ISSUER_TIMEOUT is 10s -- tick comfortably past it.
	var resumed := false
	for i in range(900): # ~15s
		await main_node.get_tree().physics_frame
		if held.compelled_stop.is_empty():
			resumed = true
			break
	_assert(resumed, "compelled_stop auto-clears once the issuer is gone past the timeout")
