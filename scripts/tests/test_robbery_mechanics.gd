extends Node

# M52c -- robbery mechanics acceptance (implementation_plans/
# m52c_robbery_mechanics.md items 1-3): the 2026-07-20 pirate playtest broke
# on two failures that were the same missing concept -- no standoff distance
# and no relative-velocity gate on INTERCEPT/DEMAND_STOP. This file proves
# the fix directly against JobSteps' INTERCEPT/DEMAND_STOP/TAKE_ALONGSIDE,
# bypassing SELECT_VICTIM (job["victim_iid"] is stamped straight onto the
# test's own job dict -- the same "hand-build a job, skip the hunt" shortcut
# every phase below uses) so each phase stays focused on the verb under test.
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames -- physics isn't bit-deterministic run-to-run
# (CLAUDE.md). RNG is seeded by the test runner (main.gd).

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")
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

func _total_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += max(0.0, c.get("health", 0.0))
	return h

func _max_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += c.get("max_health", 0.0)
	return h

func _healthy(ship) -> bool:
	return _total_health(ship) >= _max_health(ship) - 0.01

func setup(main) -> void:
	main_node = main
	print("Starting Robbery Mechanics (M52c) Tests")
	await _phase_1_standoff_intercept()
	await _phase_2_ramming_regression()
	await _phase_3_robbery_theater()
	_finish()

# ---------------------------------------------------------------------------
# Phase 1: hail-from-range sequencing (revised, calling session 2026-07-23:
# playtest read the old order -- INTERCEPT closes all the way to standoff
# AND matches speed BEFORE DEMAND_STOP ever shows colors/sends the demand --
# as "they were already trying to board me before the hail even showed up."
# Now INTERCEPT completes as soon as the victim is within hailing range,
# full stop; DEMAND_STOP shows colors and sends the demand on ITS first
# tick, from wherever that is (still far from boarding range); THEN its own
# pacing closes to standoff and matches speed while the demand is live.
# Asserts each leg of that order explicitly, plus the still-critical
# regression check: ZERO hull contact across the whole encounter.
# ---------------------------------------------------------------------------
func _phase_1_standoff_intercept() -> void:
	print("\n--- Phase 1: INTERCEPT completes from range -> DEMAND_STOP hails immediately -> THEN closes to standoff ---")

	var victim = _make_ship(CargoShuttle, "P1_Victim", 900, Vector2(3200, 600), ["TEAM_P1_VICTIM"])
	victim.linear_velocity = Vector2(0, 150) # constant drift, no AI/job to decelerate it

	var pirate = _make_ship(ArmedPinnace, "P1_Pirate", 901, Vector2.ZERO, ["PIRATE_900"])
	pirate.add_child(AITreeFactory.build_pirate())

	var job := {
		"steps": [
			{"verb": "INTERCEPT"},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0},
		],
		"current": 0,
		"victim_iid": victim.get_instance_id(),
	}
	pirate.assign_job(job)

	var never_contacted := true

	# --- INTERCEPT completes well outside boarding range -- no more waiting
	# to close in AND match speed before handing off to DEMAND_STOP. ---
	var intercept_done := false
	var dist_at_intercept_done := -1.0
	for i in range(600): # up to 10s -- already within hail range at spawn (~3255 vs ~27000), should be near-instant
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if not _healthy(pirate) or not _healthy(victim):
			never_contacted = false
			break
		if job.get("current", 0) >= 1:
			intercept_done = true
			dist_at_intercept_done = pirate.position.distance_to(victim.position)
			break

	_assert(intercept_done, "INTERCEPT reached DONE (current=%d)" % job.get("current", 0))
	if intercept_done:
		_assert(dist_at_intercept_done > JobSteps.INTERCEPT_STANDOFF_DIST * 3.0,
			"INTERCEPT completed from well outside boarding range (dist=%.1f, standoff=%.1f) -- hailing from range, not after already arriving" %
			[dist_at_intercept_done, JobSteps.INTERCEPT_STANDOFF_DIST])

	# --- DEMAND_STOP shows colors + sends the demand on its very first
	# tick, from that same far-away distance -- before any further closing.
	var demand_sent_far_out := false
	for i in range(120): # up to 2s -- fires immediately on entry
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if victim.pending_demand.get("rung", "") == Hail.RUNG_STOP:
			var dist_now: float = pirate.position.distance_to(victim.position)
			demand_sent_far_out = dist_now > JobSteps.INTERCEPT_STANDOFF_DIST * 2.0
			break
	_assert(demand_sent_far_out, "the demand (and showing colors) went out while still well outside standoff range -- fly colors, THEN get into position")

	# --- DEMAND_STOP's own pacing (unchanged M52c convergence math) THEN
	# closes to standoff and matches speed while the demand stays live. ---
	var converged := false
	for i in range(5400): # up to 90s -- generous convergence budget
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if not _healthy(pirate) or not _healthy(victim):
			never_contacted = false
			break # instant fail, no point continuing
		var dist: float = pirate.position.distance_to(victim.position)
		var rel_speed: float = (pirate.linear_velocity - victim.linear_velocity).length()
		if dist <= JobSteps.INTERCEPT_STANDOFF_DIST * 2.0 and rel_speed <= JobSteps.INTERCEPT_SPEED_MATCH_THRESHOLD * 1.5:
			converged = true
			break

	_assert(converged, "closed to near the standoff distance and matched speed eventually, via DEMAND_STOP's own pacing")
	_assert(never_contacted, "zero hull contact damage across the whole encounter")

	_free_all()

# ---------------------------------------------------------------------------
# Phase 2: ramming regression -- the exact playtest shape. The victim holds
# a straight course through the whole DEMAND_STOP phase (no AI to comply, so
# complied_stop never sets). Asserts the pirate paces alongside without ever
# colliding, and the existing patience/outpaced abort still fires cleanly
# once the victim never complies (patience shortened here so the test stays
# fast -- same code path as the 25s production default).
# ---------------------------------------------------------------------------
func _phase_2_ramming_regression() -> void:
	print("\n--- Phase 2: ramming regression -- non-complying victim holds course ---")

	var victim = _make_ship(CargoShuttle, "P2_Victim", 910, Vector2(3200, -600), ["TEAM_P2_VICTIM"])
	victim.linear_velocity = Vector2(300, 0) # holds a straight course, never complies (no AI)

	var pirate = _make_ship(ArmedPinnace, "P2_Pirate", 911, Vector2.ZERO, ["PIRATE_910"])
	pirate.add_child(AITreeFactory.build_pirate())

	var job := {
		"steps": [
			{"verb": "INTERCEPT"},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 6.0},
		],
		"current": 0,
		"victim_iid": victim.get_instance_id(),
	}
	pirate.assign_job(job)

	var never_contacted := true
	var job_finished := false
	for i in range(6600): # up to 110s -- intercept convergence vs. a moving victim + patience + margin
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if not _healthy(pirate) or not _healthy(victim):
			never_contacted = false
			break # instant fail
		if job.get("current", 0) >= job["steps"].size() or (is_instance_valid(pirate) and pirate.assignment.is_empty()):
			job_finished = true
			break

	_assert(never_contacted, "zero hull contact damage while pacing a non-complying, straight-course victim")
	_assert(job_finished, "the job ended (DEMAND_STOP's patience/outpaced abort fired) instead of hanging forever un-complied (current=%d)" % job.get("current", -1))
	if is_instance_valid(victim):
		_assert(victim.compelled_stop.is_empty(), "the victim never actually complied (no AI to ACKNOWLEDGE) -- confirms this was a real non-compliance abort, not a late take")

	_free_all()

# ---------------------------------------------------------------------------
# Phase 3: robbery theater. A victim that DOES comply (CargoShuttle + build_
# cargo() AI, same shape test_pirate_ambush.gd already proves compliant --
# ArmedPinnace easily outruns it so the cargo AI's comply-or-run picks
# comply). Asserts: the pirate closes to the new tightened alongside
# envelope, the 10s+ hold accumulates only once actually inside it (checked
# by comparing real elapsed time since first entering range against hold_
# time, not the whole encounter), and loot_takes/looted flip on DONE.
# ---------------------------------------------------------------------------
func _phase_3_robbery_theater() -> void:
	print("\n--- Phase 3: robbery theater -- complied victim, soft-dock hold ---")

	# No build_cargo() AI here deliberately -- the comply-or-run call (M52a,
	# threat_response_leaf.gd) weighs the pirate's demonstrated PEAK speed
	# against the victim's own max_speed, a heuristic that's a genuine race
	# against exactly when the victim's own sensors first correlate a fresh
	# track on the (initially dark) pirate; test_pirate_ambush.gd already
	# covers that heuristic end to end. This phase is about TAKE_ALONGSIDE's
	# soft-dock/hold-time mechanics (M52c's actual scope), so compliance is
	# driven directly -- the same engage_dead_stop() call the AI itself would
	# make (ship.gd), fired the instant the demand actually arrives.
	var victim = _make_ship(CargoShuttle, "P3_Victim", 920, Vector2(3200, 0), ["TEAM_P3_VICTIM"])

	var pirate = _make_ship(ArmedPinnace, "P3_Pirate", 921, Vector2.ZERO, ["PIRATE_920"])
	pirate.add_child(AITreeFactory.build_pirate())

	var job := {
		"steps": [
			{"verb": "INTERCEPT"},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0},
			{"verb": "TAKE_ALONGSIDE"}, # default hold_time/range -- the tightened M52c theater values
		],
		"current": 0,
		"victim_iid": victim.get_instance_id(),
	}
	pirate.assign_job(job)

	var take_range: float = 200.0 # matches TAKE_ALONGSIDE's new default (job_steps.gd)
	var hold_time: float = 12.0   # matches TAKE_ALONGSIDE's new default (job_steps.gd)

	var never_contacted := true
	var complied := false
	var first_in_range_frame: int = -1
	var taken := false
	for i in range(9000): # up to 150s -- intercept + demand + 12s hold + margin
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if not _healthy(pirate) or not _healthy(victim):
			never_contacted = false
			break # instant fail
		if not complied and victim.pending_demand.get("rung", "") == Hail.RUNG_STOP:
			victim.engage_dead_stop()
			complied = true
		if job.get("current", 0) == 2 and first_in_range_frame == -1:
			if pirate.position.distance_to(victim.position) <= take_range:
				first_in_range_frame = Engine.get_physics_frames()
		if pirate.loot_takes >= 1:
			taken = true
			break

	_assert(complied, "the victim received and acted on the DEMAND(STOP)")

	_assert(never_contacted, "zero hull contact damage across intercept -> demand -> soft-dock hold")
	_assert(taken, "pirate.loot_takes incremented (loot_takes=%d)" % (pirate.loot_takes if is_instance_valid(pirate) else -1))
	_assert(is_instance_valid(victim) and victim.looted, "victim.looted was stamped by the take")

	if taken and first_in_range_frame != -1:
		var took_frame := Engine.get_physics_frames()
		var real_hold_elapsed: float = (took_frame - first_in_range_frame) / 60.0
		print("[P3] first-in-range -> take: %.1fs (hold_time=%.1fs)" % [real_hold_elapsed, hold_time])
		# The clock only accumulates while actually inside `range` (pausing on
		# any excursion, per the step's existing comments/behavior) -- so the
		# wall-clock from first entering range to the take should sit close to
		# hold_time, not run away arbitrarily longer (which would mean it kept
		# accumulating across a state that shouldn't count) nor land under it
		# (which would mean the hold wasn't actually enforced).
		_assert(real_hold_elapsed >= hold_time - 0.5, "the hold actually ran for close to hold_time (%.1fs >= %.1fs)" % [real_hold_elapsed, hold_time])
		_assert(real_hold_elapsed <= hold_time + 20.0, "the hold didn't run away far past hold_time (%.1fs, budget %.1fs + slack)" % [real_hold_elapsed, hold_time])

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_robbery_mechanics <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_robbery_mechanics <<<")
		get_tree().quit(1)
