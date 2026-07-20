extends "res://addons/beehave/nodes/leaves/action.gd"

# M50 -- generic job runner (design_ideas/jobs_and_itineraries.md is the
# model; implementation_plans/m50_pirate_tree_design.md pins this file). One
# leaf executes whatever job is currently active on the ship -- new NPC
# classes add DATA (their itinerary) and occasionally a VERB, never new
# machinery here. This file stays small on purpose.
#
# Two-slot model, NOT a stack (see the design doc's "why not a stack"):
# `actor.assignment` (an overriding mission) is read first; if empty, falls
# back to `actor.default_job` (the standing duty). Ship-facing API is
# assign_job()/set_default_job() (ship.gd) -- this leaf only ever READS the
# two fields, so directors/spawners/tests never touch the tree directly.
#
# Step dict shape: {"verb": String, <verb params>, "label": String (opt),
# "on_abort": String (opt), "abort_when": Array (opt), "scratch": Dictionary
# (runner-owned, reset on entry)}.
#
# abort_when is a list of {"cond": String, "on_abort": String, <cond params>}
# dicts -- the runner-evaluated, cheap/ship-knowable conditions from the
# design doc's v1 set (third_party_in_range, victim_lost). Each entry names
# its OWN jump target, because a single step legitimately aborts to
# DIFFERENT places depending on which shared condition fired (the canonical
# hunt job: third_party always jumps to "exfil", victim_lost jumps back to
# "hunt") -- a single step-level label can't express that. Verb-SPECIFIC
# abort reasons (DEMAND_STOP's patience/outpacing, TAKE_ALONGSIDE's bolted
# victim) are instead returned directly by the executor as ABORT, which jumps
# to the step's own singular "on_abort" field (the job step shape jobs_and_
# itineraries.md pins) -- this keeps the runner-level checks generic while
# letting each verb own its own failure semantics.
#
# Leaves in this codebase never return RUNNING (see ai_tree_factory.gd's
# header) -- a job that's still CONTINUEing still returns SUCCESS every tick
# it owns (the runner "owns the tick" per the design doc). FAILURE means
# "nothing to do" -- neither slot holds an active job at the START of this
# tick. A job that completes/aborts-to-nothing DURING this tick still
# returns SUCCESS for the tick that did the work; the NEXT tick (finding
# both slots empty) is what returns FAILURE and lets the tree fall through
# to Idle (or, for the standing-duty slot, nothing -- the assignment simply
# clears and default_job resumes at step 0 if one exists).

const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")

func tick(actor: Node, _blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	var slot: String = ""
	var job: Dictionary = actor.assignment
	if not job.is_empty():
		slot = "assignment"
	else:
		job = actor.default_job
		if not job.is_empty():
			slot = "default_job"

	if slot == "":
		return FAILURE

	var steps: Array = job.get("steps", [])
	var current: int = job.get("current", 0)

	if current < 0 or current >= steps.size():
		_complete_job(actor, slot, job)
		return FAILURE

	var step: Dictionary = steps[current]

	# Scratch is cleared on ENTRY to a step -- including re-entry via an abort
	# jump landing back on a previously-visited index (e.g. the hunt job's
	# victim_lost edge jumping INTERCEPT back to the "hunt" label). Tracking
	# the last-entered index (not just "did scratch exist") is what makes a
	# jump-back count as a fresh entry even though the step dict itself
	# (and its "scratch" key) persists across the whole job's lifetime.
	if job.get("_entered_step", -1) != current:
		step["scratch"] = {}
		job["_entered_step"] = current

	for cond in step.get("abort_when", []):
		if JobSteps.check_abort(actor, job, cond):
			_job_log(actor, "%s ABORT (%s%s) -> '%s'" % [step.get("verb", "?"), cond.get("cond", "?"), _abort_reason(job), cond.get("on_abort", "")])
			_abort_to(job, cond.get("on_abort", ""))
			return SUCCESS

	var result: int = JobSteps.execute(step.get("verb", ""), actor, step, job)

	match result:
		JobSteps.DONE:
			_job_log(actor, "%s done%s" % [step.get("verb", "?"), _done_detail(actor, step, job)])
			job["current"] = current + 1
		JobSteps.ABORT:
			_job_log(actor, "%s ABORT%s -> '%s'" % [step.get("verb", "?"), _abort_reason(job), step.get("on_abort", "")])
			_abort_to(job, step.get("on_abort", ""))
		_: # CONTINUE -- still working, runner owns the tick.
			pass

	if job.get("current", 0) >= steps.size():
		if not job.get("repeat", false):
			_job_log(actor, "job complete (%s slot cleared)" % slot)
		_complete_job(actor, slot, job)

	return SUCCESS

# M52a -- consume the verb/condition-stamped abort cause (job["_abort_reason"],
# set by the executor or condition helper right before it signalled ABORT) so
# every ABORT line carries WHY, not just the jump target. Reads once and clears
# it so a later cause-less abort can't inherit a stale reason. Returns a
# "; <reason>" fragment (or "") for splicing into the log line.
func _abort_reason(job: Dictionary) -> String:
	var reason: String = job.get("_abort_reason", "")
	job.erase("_abort_reason")
	return "; %s" % reason if reason != "" else ""

# One line per step transition when the DebugSettings "job_log" toggle is ON
# -- the console view of an otherwise-invisible job (a pirate's whole hunt
# happens dark and off-lane; these lines are how a playtester watches it).
func _job_log(actor: Node, msg: String) -> void:
	if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
		print("[Job] %s: %s" % [actor.name, msg])

# Verb-aware detail for the DONE line -- the milestones worth a number.
func _done_detail(actor: Node, step: Dictionary, job: Dictionary) -> String:
	match step.get("verb", ""):
		"SELECT_VICTIM":
			var victim_iid: int = job.get("victim_iid", -1)
			return " (victim_iid=%d, victim='%s')" % [victim_iid, _victim_display_name(actor, victim_iid)]
		"INTERCEPT", "DEMAND_STOP", "TAKE_ALONGSIDE":
			return " (victim_iid=%d)" % job.get("victim_iid", -1)
		"RELIGHT":
			return " (as '%s' / %s)" % [step.get("name", ""), step.get("flag", "no flag")]
		_:
			return ""

# Honest name for the SELECT_VICTIM log: what the actor's own sensors/comms
# actually observed, not privileged data it couldn't see. Prefers the
# claimed transponder name from the actor's own active_transponders (the
# same source the contact's "name" field would draw from), falling back to
# the live node's name if the victim never transponded (or the record's
# gone) -- "?" only if neither is available.
func _victim_display_name(actor: Node, victim_iid: int) -> String:
	if victim_iid == -1:
		return "?"
	var claimed: String = actor.active_transponders.get(victim_iid, {}).get("name", "")
	if claimed != "":
		return claimed
	var node = instance_from_id(victim_iid)
	if is_instance_valid(node):
		return node.name
	return "?"

# Jump to the step whose "label" matches `label`; no match (including an
# empty label) means the job is over -- push current past the end so the
# completion check above (or next tick's bounds check) clears it.
func _abort_to(job: Dictionary, label: String) -> void:
	var steps: Array = job.get("steps", [])
	var target_idx: int = -1
	if label != "":
		for i in range(steps.size()):
			if steps[i].get("label", "") == label:
				target_idx = i
				break
	job["current"] = target_idx if target_idx != -1 else steps.size()

# A job past its last step is complete. `repeat: true` re-enters at step 0
# (and drops the entered-step marker so step 0's scratch resets even though
# its index is unchanged from a prior lap); otherwise the slot clears --
# an assignment vanishes entirely, a standing duty just goes empty until
# something sets a new one.
func _complete_job(actor: Node, slot: String, job: Dictionary) -> void:
	if job.get("repeat", false):
		job["current"] = 0
		job.erase("_entered_step")
		return
	if slot == "assignment":
		actor.assignment = {}
	else:
		actor.default_job = {}
