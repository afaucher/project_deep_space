extends Node

# WHY DOES A PIRATE NEVER REACH BOARDING RANGE OF A SHIP THAT HAS STOPPED?
#
# Built after diagnosing this the expensive way. `held -1.0s` -- the hold never
# starting -- was chased through 45-GAME-MINUTE campaign runs with 14 haulers,
# 8 pirates and a live economy, three seeds at a time, to observe what is
# fundamentally a TWO-BODY problem: one pirate closing on one stationary
# victim. Six hypotheses died in those runs at minutes of wall-clock each.
#
# `pursuit_trace.gd` already established the pattern this morning and answered
# the patrol-chase question on the first run. This is the same idea for the
# take: stage exactly two ships, drive the real step, print the distance every
# game-second, and read the answer off the table.
#
# Deliberately NOT a test: there is no correct number here, and the campaign is
# where rates are measured. This exists to make one mechanism observable.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim alongside_trace

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")
const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const TRACE_SECONDS := 120

var main_node: Node = null

func setup(main) -> void:
	main_node = main
	seed(20260804)
	print("=== alongside_trace: why does the pirate not close the last few hundred units? ===")
	# Campaign failures were measured at 4,000-20,000u, so sweep the range the
	# game actually produces rather than the one that happens to work.
	# D50 -- what breaks the take in a CAMPAIGN that two ships alone do not have?
	# The tick gap says JobRunner was preempted for 6.45s; build_pirate puts
	# ShouldDisengage/Flee and OutlawResponse ABOVE it. Two candidates needing
	# OPPOSITE fixes: a patrol interdicting the pirate (abandoning is CORRECT,
	# only the "victim bolted" message is wrong), or ordinary traffic tripping
	# ShouldDisengage (a real defect, and economic targeting maximises exactly
	# that by parking pirates on the busiest lane).
	#
	# So run the same take with the FULL pirate tree instead of a bare
	# JobRunner, and with a neutral bystander nearby. If the take survives both,
	# neither candidate is it.
	# D53 -- the HOLD is what cooks the pirate (measured: entry 0.15 -> peak 0.90).
	# A perfectly stationary victim is the easy case and completes; a COMPLIED
	# victim keeps residual drift, which the step deliberately paces rather than
	# out-braking, so the pirate re-aims every tick. Torque is charged as heat
	# too, so re-aiming is not free. `drift` reproduces that here.
	await _trace(3000.0, true, false, 0.0)
	print("")
	await _trace(3000.0, true, false, 40.0)
	print("")
	await _trace(3000.0, true, false, 120.0)
	get_tree().quit(0)

func _make(script, nm: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = nm
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	return s

func _contact(observer, target) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func _trace(start_gap: float, full_tree: bool = false, bystander: bool = false, drift: float = 0.0) -> void:
	print("--- opening gap %.0fu | tree=%s | victim drift=%.0fu/s ---" % [
		start_gap, "FULL build_pirate" if full_tree else "bare JobRunner", drift])
	var base := Vector2(300000, 0)
	var pirate = _make(ArmedPinnace, "TracePirate_%d" % int(start_gap), 800, base, ["PIRATE_GUILD"])
	var victim = _make(CargoShuttle, "TraceVictim_%d" % int(start_gap), 801, base + Vector2(start_gap, 0), ["TEAM_CIV"])

	# Let the tracks settle so SELECT/INTERCEPT-equivalent state is realistic.
	for i in range(300):
		await get_tree().physics_frame
		if not _contact(pirate, victim).is_empty():
			break

	# Put the victim in the state the campaign reaches: demanded and COMPLYING.
	var seq: int = pirate.send_demand(victim.get_instance_id(), Hail.RUNG_STOP)
	for i in range(30):
		await get_tree().physics_frame
	if victim.has_method("engage_dead_stop"):
		victim.engage_dead_stop()
	# WAIT FOR THE PIRATE'S CONTACT TO SHOW IT. The step tests
	# `c.get("complied_stop")` on the ISSUER'S fused contact, not the victim's
	# own field -- the ACKNOWLEDGE has to propagate first. Assigning the job in
	# the same breath as engage_dead_stop() aborted it on tick 1, which cost a
	# run to notice and is a harness bug, not a game one.
	var saw_complied := false
	for i in range(240):
		await get_tree().physics_frame
		if _contact(pirate, victim).get("complied_stop", false):
			saw_complied = true
			break
	print("  victim compelled_stop: %s | pirate CONTACT shows complied: %s (seq %d)" % [
		"held" if not victim.compelled_stop.is_empty() else "NO",
		"yes" if saw_complied else "NO", seq])

	# A neutral hull loitering near the victim -- the "ordinary traffic" case.
	var extra = null
	if bystander:
		extra = _make(CargoShuttle, "TraceBystander_%d" % int(start_gap), 802,
			victim.position + Vector2(0, 2500), ["TEAM_CIV2"])

	# FULL TREE puts ShouldDisengage/Flee and OutlawResponse above JobRunner,
	# which is the only structural difference between this rig and a campaign.
	var tree = AITreeFactory.build_pirate() if full_tree else null
	if tree != null:
		pirate.add_child(tree)
	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()
	# `on_abort` LABELLED, not "": CLAUDE.md's rule -- _abort_to("") sets
	# current = steps.size(), which the runner reads as JOB COMPLETE, so an
	# abort would look identical to success. Keeping a reference to the job dict
	# so `_abort_reason` survives the runner clearing the slot.
	var job := {
		"steps": [{"verb": "TAKE_ALONGSIDE", "hold_time": 12.0, "range": 200.0, "on_abort": "stop"},
			{"verb": "AWAIT", "label": "stop", "condition": "clear", "clear_range": 0.0, "timeout": 1.0, "on_abort": ""}],
		"current": 0, "victim_iid": victim.get_instance_id(), "demand_seq": seq,
	}
	pirate.assignment = job

	# Residual drift on the complying victim -- perpendicular, so the pirate must
	# keep re-aiming rather than simply matching a straight line.
	if drift > 0.0:
		victim.linear_velocity = Vector2(0, drift)
	print("     t | separation | pirate_spd | victim_spd | heat | compelled | note")
	var frames := 0
	var min_seen: float = INF
	# TRUE maximum, tracked every frame. The first version printed
	# `current_heat` at the END of the run and labelled it "peak", which is a
	# different number entirely -- a hull that spiked and then cooled reads low.
	# Comparing two configurations on that would have been meaningless.
	var heat_peak: float = 0.0
	while frames < TRACE_SECONDS * 60:
		if tree == null:
			runner.tick(pirate, bb)
		await get_tree().physics_frame
		frames += 1
		var d: float = pirate.position.distance_to(victim.position)
		min_seen = minf(min_seen, d)
		heat_peak = maxf(heat_peak, (pirate.current_heat / pirate.max_heat) if pirate.max_heat > 0.0 else 0.0)
		if frames % 60 != 0:
			continue
		var note := ""
		if pirate.assignment.is_empty():
			note = "job ended"
		print("  %4d | %10.0f | %10.0f | %10.0f | %4.2f | %9s | %s" % [
			frames / 60, d, pirate.linear_velocity.length(), victim.linear_velocity.length(),
			(pirate.current_heat / pirate.max_heat) if pirate.max_heat > 0.0 else 0.0,
			"held" if not victim.compelled_stop.is_empty() else "LAPSED", note])
		if pirate.assignment.is_empty():
			break
	print("  closest approach: %.0f  (hold needs <= 200) | PEAK heat %.2f | final %.2f" % [
		min_seen, heat_peak, (pirate.current_heat / pirate.max_heat) if pirate.max_heat > 0.0 else 0.0])
	if job.has("_abort_reason"):
		print("  abort: %s" % job["_abort_reason"])
	pirate.queue_free()
	victim.queue_free()
	if extra != null:
		extra.queue_free()
