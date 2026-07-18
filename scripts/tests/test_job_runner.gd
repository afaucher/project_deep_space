extends Node

# M50 -- unit tests for the generic job runner (design_ideas/jobs_and_
# itineraries.md; implementation_plans/m50_pirate_tree_design.md pins the
# test list). No combat, no AI tree -- JobRunnerLeaf.tick(actor, blackboard)
# is called directly against a bare live Ship, same "call the leaf directly"
# style test_honored_stop.gd uses for acquire_target_leaf/fire_opportunity_
# leaf. Scripted micro-jobs built from AWAIT{duration} (fast, deterministic:
# a handful of physics ticks at --fixed-fps 60) exercise the runner's own
# machinery -- step advancement, scratch reset on entry (including re-entry
# via an abort jump), the abort_when vs step-level on_abort split, job-
# complete -> FAILURE, repeat re-entry, and the two-slot assignment/
# default_job fallback -- without needing a single other verb.

const Ship = preload("res://scripts/ships/ship.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_actor(name: String) -> Node:
	var s = Ship.new()
	s.name = name
	s.owner_id = spawned.size() + 900
	s.position = Vector2.ZERO
	main_node.add_child(s)
	spawned.append(s)
	return s

func setup(main) -> void:
	main_node = main
	print("Starting Job Runner (M50) Tests")

	await _test_step_advancement()
	await _test_backward_jump_and_scratch_reset()
	await _test_abort_no_match_job_over()
	await _test_repeat_reentry()
	await _test_two_slot_assignment_completes()
	await _test_two_slot_assignment_aborts()
	await _test_abort_when_generic_dispatch()
	_test_no_job_and_empty_job()

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_job_runner <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_job_runner <<<")
		get_tree().quit(1)

# --- Step advancement: three AWAIT{duration} steps run in order, CONTINUE
# returns SUCCESS every tick, DONE past the last step completes the job. -----
func _test_step_advancement() -> void:
	print("\n--- Step advancement: 3x AWAIT{duration}, CONTINUE=SUCCESS, completion clears ---")
	var actor = _make_actor("StepAdvance")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	var job := {
		"steps": [
			{"verb": "AWAIT", "condition": "duration", "seconds": 0.05},
			{"verb": "AWAIT", "condition": "duration", "seconds": 0.05},
			{"verb": "AWAIT", "condition": "duration", "seconds": 0.05},
		],
		"current": 0,
	}
	actor.assign_job(job)

	var saw_continue_success := false
	var seen_currents: Array = []
	for i in range(300): # up to 5s -- generous vs 3x0.05s
		await main_node.get_tree().physics_frame
		var r: int = runner.tick(actor, bb)
		if actor.assignment.is_empty():
			break
		var cur: int = actor.assignment.get("current", -1)
		if not seen_currents.has(cur):
			seen_currents.append(cur)
		if r == runner.SUCCESS:
			saw_continue_success = true

	_assert(saw_continue_success, "runner returns SUCCESS while a job is CONTINUEing/advancing")
	_assert(seen_currents.has(0) and seen_currents.has(1) and seen_currents.has(2),
		"job visited step indices 0, 1, 2 in order (saw %s)" % str(seen_currents))
	_assert(actor.assignment.is_empty(), "a completed (non-repeat) assignment clears back to {}")

	var r_after: int = runner.tick(actor, bb)
	_assert(r_after == runner.FAILURE, "runner returns FAILURE on the tick after the job is gone")

# --- Abort-edge jump BACKWARD to a label + scratch reset on re-entry. -------
func _test_backward_jump_and_scratch_reset() -> void:
	print("\n--- Abort-edge jump backward + scratch reset on re-entry ---")
	var actor = _make_actor("BackwardJump")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	# Step 0 ("start") always finishes quickly. Step 1 never satisfies its own
	# duration condition (9999s) but times out fast and jumps BACK to "start"
	# via its own (step-level) on_abort -- an executor-returned ABORT, not an
	# abort_when condition.
	var job := {
		"steps": [
			{"label": "start", "verb": "AWAIT", "condition": "duration", "seconds": 0.05},
			{"verb": "AWAIT", "condition": "duration", "seconds": 9999.0, "timeout": 0.05, "on_abort": "start"},
		],
		"current": 0,
	}
	actor.assign_job(job)

	var start_frame_1: int = -1
	var saw_step1 := false
	var start_frame_2: int = -1
	var saw_reentry := false

	for i in range(600): # up to 10s
		await main_node.get_tree().physics_frame
		runner.tick(actor, bb)
		var cur: int = job.get("current", -1)
		if cur == 1 and not saw_step1:
			saw_step1 = true
			start_frame_1 = job["steps"][0].get("scratch", {}).get("start_frame", -1)
		if saw_step1 and cur == 0:
			# The abort tick itself only mutates job["current"] -- step 0's
			# scratch isn't cleared/repopulated until the NEXT tick actually
			# re-enters it (the runner's entry check runs at the top of
			# tick(), before dispatch). Wait for the value to actually change
			# rather than reading one tick too early.
			var sf: int = job["steps"][0].get("scratch", {}).get("start_frame", -1)
			if sf != -1 and sf != start_frame_1:
				saw_reentry = true
				start_frame_2 = sf
				break

	_assert(saw_step1, "job advanced into step 1 (setup sanity)")
	_assert(start_frame_1 != -1, "setup sanity: step 0's scratch recorded a start_frame on its first entry")
	_assert(saw_reentry, "step 1's timeout ABORT jumped backward to label 'start' (step 0)")
	_assert(start_frame_2 != -1 and start_frame_2 > start_frame_1,
		"re-entering step 0 via the abort jump reset its scratch (fresh start_frame %d > original %d)" % [start_frame_2, start_frame_1])

# --- ABORT with no matching label -- job is over (clears, next tick FAILURE). ---
func _test_abort_no_match_job_over() -> void:
	print("\n--- ABORT with no matching on_abort label -- job over ---")
	var actor = _make_actor("NoMatchAbort")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	var job := {
		"steps": [
			{"verb": "AWAIT", "condition": "duration", "seconds": 9999.0, "timeout": 0.05, "on_abort": "nowhere"},
		],
		"current": 0,
	}
	actor.assign_job(job)

	var cleared := false
	for i in range(300):
		await main_node.get_tree().physics_frame
		runner.tick(actor, bb)
		if actor.assignment.is_empty():
			cleared = true
			break
	_assert(cleared, "an ABORT whose on_abort label matches nothing ends the job (assignment clears)")

	var r_after: int = runner.tick(actor, bb)
	_assert(r_after == runner.FAILURE, "runner returns FAILURE once the unresolved-abort job is gone")

# --- repeat: true re-enters at step 0 without clearing the slot. -----------
func _test_repeat_reentry() -> void:
	print("\n--- repeat: true re-enters at step 0, never clears ---")
	var actor = _make_actor("Repeater")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	var job := {
		"steps": [
			{"label": "a", "verb": "AWAIT", "condition": "duration", "seconds": 0.05},
			{"label": "b", "verb": "AWAIT", "condition": "duration", "seconds": 0.05},
		],
		"current": 0,
		"repeat": true,
	}
	actor.assign_job(job)

	var laps := 0
	var was_at_b := false
	for i in range(900): # up to 15s -- comfortably enough for several laps
		await main_node.get_tree().physics_frame
		runner.tick(actor, bb)
		var cur: int = job.get("current", -1)
		if cur == 1:
			was_at_b = true
		elif cur == 0 and was_at_b:
			laps += 1
			was_at_b = false
			if laps >= 2:
				break

	_assert(laps >= 2, "a repeat:true job laps step 0 -> step 1 -> step 0 more than once (laps=%d)" % laps)
	_assert(not actor.assignment.is_empty(), "a repeat:true job never clears its slot")

# --- Two-slot fallback: assignment completes -> default_job resumes at 0. ---
func _test_two_slot_assignment_completes() -> void:
	print("\n--- Two-slot fallback: assignment completes -> default_job resumes at step 0 ---")
	var actor = _make_actor("FallbackComplete")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	var default_job := {
		"steps": [{"verb": "AWAIT", "condition": "duration", "seconds": 9999.0}],
		"current": 0,
		"repeat": true,
	}
	actor.set_default_job(default_job)

	var assignment := {
		"steps": [{"verb": "AWAIT", "condition": "duration", "seconds": 0.05}],
		"current": 0,
	}
	actor.assign_job(assignment)

	var default_started := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		runner.tick(actor, bb)
		if actor.assignment.is_empty():
			var scratch: Dictionary = default_job["steps"][0].get("scratch", {})
			if scratch.has("start_frame"):
				default_started = true
				break
	_assert(actor.assignment.is_empty(), "the completed assignment cleared")
	_assert(default_started, "default_job began executing at step 0 once the assignment cleared (its AWAIT scratch populated)")

# --- Two-slot fallback: assignment aborts out -> default_job resumes at 0. --
func _test_two_slot_assignment_aborts() -> void:
	print("\n--- Two-slot fallback: assignment aborts out -> default_job resumes at step 0 ---")
	var actor = _make_actor("FallbackAbort")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	var default_job := {
		"steps": [{"verb": "AWAIT", "condition": "duration", "seconds": 9999.0}],
		"current": 0,
		"repeat": true,
	}
	actor.set_default_job(default_job)

	# on_abort "" (unset) -- aborts straight to "job over" the moment its
	# timeout fires, with nothing left un-complied about it.
	var assignment := {
		"steps": [{"verb": "AWAIT", "condition": "duration", "seconds": 9999.0, "timeout": 0.05}],
		"current": 0,
	}
	actor.assign_job(assignment)

	var default_started := false
	for i in range(300):
		await main_node.get_tree().physics_frame
		runner.tick(actor, bb)
		if actor.assignment.is_empty():
			var scratch: Dictionary = default_job["steps"][0].get("scratch", {})
			if scratch.has("start_frame"):
				default_started = true
				break
	_assert(actor.assignment.is_empty(), "the aborted-out assignment cleared")
	_assert(default_started, "default_job began executing at step 0 once the assignment aborted out")

# --- abort_when: runner-evaluated, per-condition on_abort target, checked
# BEFORE dispatch (the step's own verb never even runs). ---------------------
func _test_abort_when_generic_dispatch() -> void:
	print("\n--- abort_when: runner-checked condition fires before dispatch, jumps to its OWN target ---")
	var actor = _make_actor("AbortWhen")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	# victim_lost is true whenever job["victim_iid"] is unset/stale -- here
	# it's never set at all, so the condition is true from the very first
	# tick, firing before step "a"'s own AWAIT executor ever runs.
	var job := {
		"steps": [
			{"label": "a", "verb": "AWAIT", "condition": "duration", "seconds": 9999.0,
				"abort_when": [{"cond": "victim_lost", "on_abort": "b"}]},
			{"label": "b", "verb": "AWAIT", "condition": "duration", "seconds": 0.0},
		],
		"current": 0,
	}
	actor.assign_job(job)

	await main_node.get_tree().physics_frame
	runner.tick(actor, bb)

	_assert(job.get("current", -1) == 1, "abort_when's victim_lost fired immediately and jumped to label 'b' (current=%d)" % job.get("current", -1))
	_assert(job["steps"][0].get("scratch", {}).is_empty(), "step 'a's AWAIT executor never dispatched -- abort_when runs before dispatch, scratch untouched")

# --- Neither slot populated / an already-exhausted job -> FAILURE. ---------
func _test_no_job_and_empty_job() -> void:
	print("\n--- No job in either slot -> FAILURE; an empty-steps job -> FAILURE and clears ---")
	var actor = _make_actor("NoJob")
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	_assert(actor.assignment.is_empty() and actor.default_job.is_empty(), "setup sanity: fresh ship has neither slot populated")
	var r: int = runner.tick(actor, bb)
	_assert(r == runner.FAILURE, "neither slot populated -> FAILURE")

	actor.assign_job({"steps": [], "current": 0})
	var r2: int = runner.tick(actor, bb)
	_assert(r2 == runner.FAILURE, "a job with empty steps is already exhausted -> FAILURE")
	_assert(actor.assignment.is_empty(), "the exhausted empty-steps job cleared")
