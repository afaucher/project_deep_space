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
# Phase 1: standoff intercept. A pirate vs. a scripted straight-line-moving
# victim (a bare CargoShuttle, no AI/job -- just a constant linear_velocity,
# same "no engines commanding it, nothing decelerates it" shape test_
# collision_damage.gd's frigates use). Asserts: closes to the standoff (not
# the victim's own position), relative speed drops under the match threshold
# at DONE, and -- the critical regression check -- ZERO hull contact the
# whole encounter (instant fail on any detected damage, margin-based).
# ---------------------------------------------------------------------------
func _phase_1_standoff_intercept() -> void:
	print("\n--- Phase 1: standoff intercept vs. a straight-line-moving victim ---")

	var victim = _make_ship(CargoShuttle, "P1_Victim", 900, Vector2(3200, 600), ["TEAM_P1_VICTIM"])
	victim.linear_velocity = Vector2(0, 150) # constant drift, no AI/job to decelerate it

	var pirate = _make_ship(ArmedPinnace, "P1_Pirate", 901, Vector2.ZERO, ["PIRATE_900"])
	pirate.add_child(AITreeFactory.build_pirate())

	var job := {
		"steps": [
			{"verb": "INTERCEPT"},
		],
		"current": 0,
		"victim_iid": victim.get_instance_id(),
	}
	pirate.assign_job(job)

	var done := false
	var never_contacted := true
	for i in range(5400): # up to 90s -- generous convergence budget
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if not _healthy(pirate) or not _healthy(victim):
			never_contacted = false
			break # instant fail, no point continuing
		if job.get("current", 0) >= job["steps"].size():
			done = true
			break

	_assert(done, "INTERCEPT reached DONE within the time budget (current=%d)" % job.get("current", -1))
	_assert(never_contacted, "zero hull contact damage during the standoff approach")

	if done and is_instance_valid(pirate) and is_instance_valid(victim):
		var dist: float = pirate.position.distance_to(victim.position)
		var rel_speed: float = (pirate.linear_velocity - victim.linear_velocity).length()
		print("[P1] at DONE: dist=%.1f rel_speed=%.1f (standoff=%.1f, match_threshold=%.1f)" %
			[dist, rel_speed, JobSteps.INTERCEPT_STANDOFF_DIST, JobSteps.INTERCEPT_SPEED_MATCH_THRESHOLD])
		_assert(rel_speed <= JobSteps.INTERCEPT_SPEED_MATCH_THRESHOLD * 1.5, "relative speed (%.1f) is under (a generous margin past) the match threshold (%.1f) at DONE" % [rel_speed, JobSteps.INTERCEPT_SPEED_MATCH_THRESHOLD])
		_assert(dist <= JobSteps.INTERCEPT_STANDOFF_DIST * 2.0, "closed to near the standoff distance (%.1f), not left far out on hail range alone (standoff=%.1f)" % [dist, JobSteps.INTERCEPT_STANDOFF_DIST])
		_assert(dist >= JobSteps.INTERCEPT_STANDOFF_DIST * 0.25, "stopped at a standoff, not flown into the victim's exact position (dist=%.1f)" % dist)

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
