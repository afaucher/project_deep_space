extends Node

# M52d -- demand/hold heartbeat and expiry (implementation_plans/
# m52d_hail_ux.md item 1, design revised in review). A demand/hold is a
# CHANNEL the issuer keeps asserting, not a datagram plus a release
# contract: DEMAND_STOP re-sends the demand under the SAME seq every ~2s,
# and TAKE_ALONGSIDE keeps re-sending it to sustain the victim's
# compelled_stop through the whole robbery; the receiver's pending_demand
# and compelled_stop both clear after ~6s of silence
# (Ship.HAIL_HEARTBEAT_TIMEOUT). ONE timeout mechanism covers issuer death,
# out-of-comms, job abort/completion, and lost interest, for BOTH states --
# there is no RELEASE verb (it was removed entirely; a dedicated "stop the
# demand" message is redundant once the channel itself expresses that by
# going quiet). Playtest bug pinned here: "the first demand never went
# away, it was still there when the second pirate got me."
#
# Also covers S6 (design revised in review): Ship.acknowledge() and
# Ship.engage_dead_stop() are DECOUPLED -- acknowledging a demand declares
# receipt only, never compliance, since a player might acknowledge while
# still running to buy time; only engage_dead_stop() actually sets
# compelled_stop.
#
# Style: live ships + real comms delivery (test_honored_stop.gd's settle-
# loop idiom -- physics isn't bit-deterministic, so margins/timeouts, never
# exact frames). Scenario casts spawn on a ~150k-radius ring around the
# origin, one cardinal direction each (comms tops out ~60k, so pairwise
# cluster separation of ~150k-300k is comfortably clear of cross-talk) --
# NOT simply "far apart in a straight line": FoamPhysics.BOUNDARY is a
# 250000-unit world edge that force-teleports anything beyond it back
# toward a pole near (0, +-245000) on the very next physics tick, so
# scenario casts must all stay INSIDE that radius or they get silently
# relocated (and, worse, different scenarios' casts can collapse onto the
# SAME pole point). The pirate job is driven by ticking JobRunnerLeaf
# directly each frame, same "call the leaf directly" style as
# test_job_runner.gd.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_demand_lifecycle

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var ship = Frigate.new()
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

# Wait until the pirate holds a fresh track on the victim (the DEMAND_STOP
# step needs it before it can send).
func _settle_track(pirate, victim) -> bool:
	for i in range(360): # up to 6s
		await main_node.get_tree().physics_frame
		var c: Dictionary = _find_contact(pirate, victim)
		if not c.is_empty() and c.get("last_seen_timer", 999.0) <= pirate.FIRE_STALENESS_MAX:
			return true
	return false

# One-step hunt job: DEMAND_STOP holding position (cruise 0 -- no physical
# approach, this test is about the comms channel, not interception).
func _stop_job(victim_iid: int, patience: float) -> Dictionary:
	return {"steps": [{"verb": "DEMAND_STOP", "patience": patience, "cruise": 0.0}],
		"current": 0, "victim_iid": victim_iid}

func _count_hail_events(ship) -> int:
	var n := 0
	for ev in ship.transient_events:
		if ev.get("type", "") == "hail":
			n += 1
	return n

func setup(main) -> void:
	main_node = main
	print("Starting Demand Lifecycle (M52d) Tests")

	await _test_heartbeat_keeps_alive_then_death_clears()
	await _test_out_of_range_clears()
	await _test_job_abort_clears()
	await _test_refresh_dedup_and_new_demand()
	await _test_hold_stays_alive_while_refreshed()
	await _test_acknowledge_does_not_comply()

	_finish()

# --- S1: refreshes keep the demand alive past the timeout; issuer death
# ends the channel and the ONE timeout path clears it ------------------------
func _test_heartbeat_keeps_alive_then_death_clears() -> void:
	print("\n--- S1: heartbeat keeps demand alive; killed pirate -> expiry clears it ---")
	var pirate = _make_ship("S1Pirate", 600, Vector2.ZERO, ["TEAM_P1"])
	var victim = _make_ship("S1Victim", 601, Vector2(3000, 0), ["TEAM_V1"])

	var settled: bool = await _settle_track(pirate, victim)
	_assert(settled, "S1 setup: pirate holds a fresh track on the victim")

	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()
	pirate.assignment = _stop_job(victim.get_instance_id(), 9999.0)

	# 8s of the job running -- comfortably past the 6s timeout. The demand
	# must land once, keep ONE seq (refreshes, not re-issues), and never
	# lapse.
	var seq_seen: int = -1
	var lapses := 0
	for i in range(480):
		runner.tick(pirate, bb)
		await main_node.get_tree().physics_frame
		var seq_now: int = victim.pending_demand.get("seq", -1)
		if seq_seen == -1 and seq_now != -1:
			seq_seen = seq_now
		elif seq_seen != -1:
			if seq_now == -1:
				lapses += 1
			elif seq_now != seq_seen:
				lapses += 1 # re-issued under a new seq = the channel lapsed
	_assert(seq_seen != -1, "S1: the demand landed (pending_demand set)")
	_assert(lapses == 0, "S1: demand stayed alive under ONE seq for 8s of refreshes (lapses=%d)" % lapses)

	# Kill the issuer: refreshes stop, the channel goes quiet, the demand
	# clears through the heartbeat timeout -- no RELEASE, no cleanup call.
	pirate.queue_free()
	spawned.erase(pirate)
	await main_node.get_tree().physics_frame

	var cleared := false
	for i in range(720): # up to 12s (timeout is 6s -- generous margin)
		await main_node.get_tree().physics_frame
		if victim.pending_demand.is_empty():
			cleared = true
			break
	_assert(cleared, "S1: pending_demand cleared within the heartbeat timeout after the pirate died")
	_assert(victim.compelled_stop.is_empty(), "S1: cleared WITHOUT compliance (compelled_stop never set)")

# --- S2: refreshes that no longer REACH the victim (issuer out of comms
# range) go through the same timeout path ------------------------------------
func _test_out_of_range_clears() -> void:
	print("\n--- S2: issuer out of comms range -> refreshes stop arriving -> expiry ---")
	var pirate = _make_ship("S2Pirate", 610, Vector2(150000, 0), ["TEAM_P2"])
	var victim = _make_ship("S2Victim", 611, Vector2(153000, 0), ["TEAM_V2"])
	await main_node.get_tree().physics_frame

	# Manual heartbeat (no job runner) -- this scenario isolates the
	# RECEIVER's range gating: sends keep happening, deliveries stop.
	var seq: int = pirate.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)
	_assert(seq != -1, "S2 setup: demand dispatched")

	var landed := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if victim.pending_demand.get("seq", -1) == seq:
			landed = true
			break
	_assert(landed, "S2 setup: demand landed on the victim")

	# Refresh on cadence while in range -- demand must hold past the 6s
	# timeout window.
	for i in range(480): # 8s
		if i % 120 == 0:
			pirate.refresh_demand(victim.get_instance_id(), Hail.RUNG_STOP, seq)
		await main_node.get_tree().physics_frame
	_assert(victim.pending_demand.get("seq", -1) == seq,
		"S2: manually-refreshed demand still alive after 8s")

	# Teleport the pirate far out of comms range; keep refreshing -- the
	# sends still fire but never deliver, so the victim's channel goes quiet.
	# Wake-safe teleport (CLAUDE.md's sleeping-RigidBody2D gotcha): a settled
	# ship goes to sleep, and plain `.position=` alone is not reliable for a
	# sleeping body -- body_set_state + explicit wake is the only reliable
	# way (same idiom test_relay_contact_aging.gd uses). Stay INSIDE
	# FoamPhysics.BOUNDARY (250000 from origin) -- past it the world-boundary
	# current force-teleports the ship back toward the pole, which would
	# fight this test's own teleport every tick.
	var far_pos := Vector2(150000, 150000) # ~150k from the victim, well inside the 250k boundary, clear of the other clusters
	var xform: Transform2D = pirate.global_transform
	xform.origin = far_pos
	PhysicsServer2D.body_set_state(pirate.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	pirate.position = far_pos
	pirate.sleeping = false
	var cleared := false
	for i in range(720): # up to 12s
		if i % 120 == 0:
			pirate.refresh_demand(victim.get_instance_id(), Hail.RUNG_STOP, seq)
		await main_node.get_tree().physics_frame
		if victim.pending_demand.is_empty():
			cleared = true
			break
	_assert(cleared, "S2: pending_demand cleared once the issuer left comms range")

# --- S3: the pirate job ABORTING (patience expired) simply stops the
# refreshes -- same ONE timeout path, no per-abort cleanup code --------------
func _test_job_abort_clears() -> void:
	print("\n--- S3: job abort stops refreshes -> same expiry path clears the demand ---")
	var pirate = _make_ship("S3Pirate", 620, Vector2(0, 150000), ["TEAM_P3"])
	var victim = _make_ship("S3Victim", 621, Vector2(3000, 150000), ["TEAM_V3"])

	var settled: bool = await _settle_track(pirate, victim)
	_assert(settled, "S3 setup: pirate holds a fresh track on the victim")

	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()
	pirate.assignment = _stop_job(victim.get_instance_id(), 3.0) # 3s patience, victim never complies

	var landed := false
	var cleared_after_abort := false
	for i in range(900): # up to 15s: ~3s to abort + 6s timeout + margin
		runner.tick(pirate, bb) # returns FAILURE once the job self-cleared; harmless to keep ticking
		await main_node.get_tree().physics_frame
		if not landed and not victim.pending_demand.is_empty():
			landed = true
		if landed and pirate.assignment.is_empty() and victim.pending_demand.is_empty():
			cleared_after_abort = true
			break
	_assert(landed, "S3: demand landed before the abort")
	_assert(pirate.assignment.is_empty(), "S3: patience abort ended the job (assignment cleared)")
	_assert(cleared_after_abort, "S3: victim's pending_demand cleared via the heartbeat timeout after the abort")
	_assert(victim.compelled_stop.is_empty(), "S3: cleared WITHOUT compliance")

# --- S4: refresh dedup guards -- no re-alert, no re-decision/SOS, no
# last_hails spam; a genuinely NEW demand (new seq) still overwrites and
# re-alerts -------------------------------------------------------------------
func _test_refresh_dedup_and_new_demand() -> void:
	print("\n--- S4: a refresh re-triggers NOTHING; a new seq overwrites + re-alerts ---")
	var pirate = _make_ship("S4Pirate", 630, Vector2(-150000, 0), ["TEAM_P4"])
	var victim = _make_ship("S4Victim", 631, Vector2(-147000, 0), ["TEAM_V4"])
	await main_node.get_tree().physics_frame

	var seq: int = pirate.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)
	var landed := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if victim.pending_demand.get("seq", -1) == seq:
			landed = true
			break
	_assert(landed, "S4 setup: demand landed")

	var hail_events_before: int = _count_hail_events(victim)
	var last_hails_before: int = victim.last_hails.size()
	_assert(hail_events_before >= 1, "S4 setup: first receipt raised a 'hail' transient event")

	# The victim's comply-or-run decision is made once, keyed on seq
	# (threat_response_leaf's last_decided_seq) -- tick it to consume the
	# decision (which also broadcasts the incident's ONE SOS), then verify a
	# refresh does NOT re-open it. "No fresh SOS" is observed via the
	# pirate's own heard_sos age: a re-sent SOS would overwrite the entry
	# with age ~0.
	var leaf = ThreatResponseLeaf.new()
	var bb = BlackboardScript.new()
	var first_tick: int = leaf.tick(victim, bb)
	_assert(first_tick == leaf.SUCCESS, "S4: first tick decides (SUCCESS) on the fresh demand")

	for i in range(60): # let the SOS land and age ~1s
		await main_node.get_tree().physics_frame
	var sos_age_before: float = pirate.heard_sos.get(victim.get_instance_id(), {}).get("age", -1.0)
	_assert(sos_age_before > 0.0, "S4 setup: the decision's ONE SOS landed and is aging")

	pirate.refresh_demand(victim.get_instance_id(), Hail.RUNG_STOP, seq)
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	leaf.tick(victim, bb) # tick again against the refreshed demand
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame

	_assert(victim.pending_demand.get("seq", -1) == seq, "S4: refresh kept the SAME demand (seq unchanged)")
	_assert(victim.pending_demand.get("heartbeat_timer", 99.0) < 1.0, "S4: refresh reset the heartbeat timer")
	_assert(_count_hail_events(victim) == hail_events_before, "S4: refresh did NOT re-raise the hail alert event")
	_assert(victim.last_hails.size() == last_hails_before, "S4: refresh did NOT spam the last_hails ring")
	_assert(bb.get_value("last_decided_seq", -1) == seq,
		"S4: the decision stayed keyed to the original seq (refresh opened no new incident)")
	var sos_age_after: float = pirate.heard_sos.get(victim.get_instance_id(), {}).get("age", -1.0)
	_assert(sos_age_after > sos_age_before,
		"S4: no fresh SOS on refresh (heard_sos kept aging: %.2f -> %.2f)" % [sos_age_before, sos_age_after])

	# A genuinely NEW demand (fresh seq) DOES overwrite and re-alert.
	var seq2: int = pirate.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)
	_assert(seq2 > seq, "S4: second demand drew a new seq")
	var overwritten := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if victim.pending_demand.get("seq", -1) == seq2:
			overwritten = true
			break
	_assert(overwritten, "S4: a new demand overwrites the old one (playtest regression)")
	_assert(_count_hail_events(victim) == hail_events_before + 1, "S4: the new demand re-raised the hail alert")

# --- S5: compelled_stop (the HOLD) is heartbeat-kept the SAME way as
# pending_demand -- while TAKE_ALONGSIDE's refresh cadence keeps landing, the
# hold survives well past the timeout; once refreshes stop (job finished/
# aborted), it lapses through the SAME mechanism, no RELEASE message needed.
# Isolates the refresh<->heartbeat mechanics directly (manual refresh_demand
# calls, no job runner/AI needed) -- the full real-comply, real-approach
# arc is covered end-to-end by test_pirate_ambush.gd.
func _test_hold_stays_alive_while_refreshed() -> void:
	print("\n--- S5: TAKE_ALONGSIDE-style refresh keeps the hold alive; stopping lets it lapse ---")
	var pirate = _make_ship("S5Pirate", 640, Vector2(0, -150000), ["TEAM_P5"])
	var victim = _make_ship("S5Victim", 641, Vector2(3000, -150000), ["TEAM_V5"])
	await main_node.get_tree().physics_frame

	# Directly compel the victim under a known seq (bypass the demand/comply
	# dance -- covered end-to-end elsewhere; this test isolates the hold's
	# refresh mechanism).
	var seq := 555555
	victim.pending_demand = {"rung": Hail.RUNG_STOP, "seq": seq, "sender_iid": pirate.get_instance_id(), "sender_pos": pirate.position, "sender_flag": "", "target_iid": victim.get_instance_id()}
	victim.engage_dead_stop()
	_assert(victim.compelled_stop.get("demand_seq", -1) == seq, "S5 setup: victim compelled under the expected seq")

	# Refresh on the JobSteps.DEMAND_REFRESH_FRAMES cadence for LONGER than
	# the 6s heartbeat timeout -- if a refresh weren't landing/matching, the
	# hold would collapse well before this loop ends.
	for i in range(540): # 9s
		if i % 120 == 0: # ~every 2s
			pirate.refresh_demand(victim.get_instance_id(), Hail.RUNG_STOP, seq)
		await main_node.get_tree().physics_frame
	_assert(not victim.compelled_stop.is_empty(), "S5: the hold survived 9s of refreshes (> 6s heartbeat timeout)")

	# Stop refreshing -- same as TAKE_ALONGSIDE finishing/aborting -- and
	# confirm the hold lapses on its own past the timeout, no explicit signal.
	var lapsed := false
	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		if victim.compelled_stop.is_empty():
			lapsed = true
			break
	_assert(lapsed, "S5: once refreshes stop, the hold lapses via the same heartbeat timeout (no RELEASE)")

# --- S6: ACKNOWLEDGE and stopping are DECOUPLED (design revised in review):
# acknowledging a demand declares receipt only -- it must NOT set
# compelled_stop or clear pending_demand, since a player might acknowledge
# while still running, hoping to buy time. engage_dead_stop() (a separate
# action) is what actually complies. Also covers acknowledge()'s generalized
# scope: it works for an IDENTIFY demand too, not just STOP. ---------------
func _test_acknowledge_does_not_comply() -> void:
	print("\n--- S6: acknowledge() alone does not comply; engage_dead_stop() does ---")
	var issuer = _make_ship("S6Issuer", 650, Vector2(150000, -150000), ["TEAM_P6"])
	var victim = _make_ship("S6Victim", 651, Vector2(153000, -150000), ["TEAM_V6"])
	await main_node.get_tree().physics_frame

	# IDENTIFY first: acknowledge() must work for a non-STOP rung (the verb's
	# own generalized meaning -- "I heard you," not STOP-specific).
	var id_seq: int = issuer.send_demand(victim.get_instance_id(), Hail.RUNG_IDENTIFY)
	var id_landed := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if victim.pending_demand.get("seq", -1) == id_seq:
			id_landed = true
			break
	_assert(id_landed, "S6 setup: IDENTIFY demand landed")
	victim.acknowledge()
	await main_node.get_tree().physics_frame
	_assert(victim.compelled_stop.is_empty(), "S6: acknowledging an IDENTIFY demand never sets compelled_stop")

	# Now a STOP demand: acknowledge() must NOT comply.
	var seq: int = issuer.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)
	var landed := false
	for i in range(120):
		await main_node.get_tree().physics_frame
		if victim.pending_demand.get("seq", -1) == seq:
			landed = true
			break
	_assert(landed, "S6 setup: STOP demand landed")

	victim.acknowledge()
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	_assert(victim.compelled_stop.is_empty(), "S6: acknowledge() alone leaves compelled_stop empty (the player might be buying time)")
	_assert(victim.pending_demand.get("seq", -1) == seq, "S6: acknowledge() does NOT clear pending_demand -- the demand stays open")

	# The demand must still be a live, heartbeat-kept channel after a bare
	# acknowledge -- refreshing it from the issuer should still reset its
	# timer (acknowledge didn't secretly resolve it).
	for i in range(240): # 4s -- comfortably under the 6s timeout if it's still alive
		if i % 120 == 0:
			issuer.refresh_demand(victim.get_instance_id(), Hail.RUNG_STOP, seq)
		await main_node.get_tree().physics_frame
	_assert(victim.pending_demand.get("seq", -1) == seq, "S6: the demand survived past its own timeout window via refresh -- acknowledge left it a real, live channel")

	# NOW genuinely comply: engage_dead_stop() reads the SAME still-open
	# pending_demand and actually holds.
	victim.engage_dead_stop()
	_assert(victim.compelled_stop.get("issuer_iid", -1) == issuer.get_instance_id() and victim.compelled_stop.get("demand_seq", -1) == seq,
		"S6: engage_dead_stop() compels against the demand acknowledge() left open, got compelled_stop=%s" % str(victim.compelled_stop))
	_assert(victim.pending_demand.is_empty(), "S6: engage_dead_stop() resolves/clears pending_demand (now genuinely complied with)")

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_demand_lifecycle <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		printerr(">>> [TEST FAILED] test_demand_lifecycle <<<")
		get_tree().quit(1)
