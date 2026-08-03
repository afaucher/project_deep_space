extends Node

# WHY DOES A 2200-SPEED PATROL LOSE A CHASE TO A 900-SPEED RUNNER?
#
# This exists because I got the answer wrong by reading code. D30 claimed the
# patrol pursued at `cruise` 400 (the step default InterdictLeaf never
# overrides); setting it to max_speed produced a BIT-IDENTICAL 5-seed funnel,
# which proves cruise was never the binding constraint. `_pace_at_offset` caps
# only the CATCHUP term and adds it ON TOP of the target's velocity --
# `desired_vel = target_vel + dir * catchup` -- so the call site never said what
# I read into it. That was the second confident wrong cause in two days
# (CLAUDE.md already records the heat_em_component_loop pair).
#
# So this runner does not test a hypothesis. It stages the exact geometry the
# funnel produces -- one patrol, one fleeing pirate, real hulls, real leaves --
# and PRINTS THE PHYSICS every game-second: both speeds, the separation, and
# the hail range whose 1.2x multiple is what actually declares "outpaced". The
# answer should be readable off the table without any theory.
#
# Deliberately NOT a test: there is no correct number here, and turning a
# diagnosis into an assertion before knowing the mechanism is how a wrong budget
# gets frozen into the gate.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim pursuit_trace

const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const OutlawResponseLeaf = preload("res://scripts/ai/leaves/outlaw_response_leaf.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")
const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")

const DT := 1.0 / 60.0
# 90s is well past the 25s patience a real interdiction gets -- long enough to
# show that the chase SETTLES rather than converging. Measured 2026-08-03:
# separation oscillates around ~1000u indefinitely (536 @20s, 1416 @30s, 796
# @40s, 1090 @60s, 1123 @70s) with both hulls climbing toward ~1800. It is a
# stalemate, not a slow loss, which is why more patience alone buys nothing.
const TRACE_SECONDS := 90

var main_node: Node = null

func setup(main) -> void:
	main_node = main
	seed(20260803)
	print("=== pursuit_trace: why does the patrol lose the chase? ===")
	await _trace()
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

func _trace() -> void:
	# Standoff-ish opening range, matching what INTERCEPT hands to DEMAND_STOP.
	var patrol = _make(LightAttackCraft, "TracePatrol", 700, Vector2.ZERO, ["TEAM_LAW"])
	var pirate = _make(ArmedPinnace, "TracePirate", 701, Vector2(2500, 0), ["TEAM_P"])

	print("  hulls: patrol max_speed=%.0f  pirate max_speed=%.0f" % [patrol.max_speed, pirate.max_speed])
	print("  patrol thrust=%.0f mass=%.0f -> accel=%.1f u/s^2" % [
		patrol.get_ship_max_thrust(), patrol.mass,
		patrol.get_ship_max_thrust() / maxf(patrol.mass, 0.001)])
	print("  pirate thrust=%.0f mass=%.0f -> accel=%.1f u/s^2" % [
		pirate.get_ship_max_thrust(), pirate.mass,
		pirate.get_ship_max_thrust() / maxf(pirate.mass, 0.001)])

	# Let both hulls acquire each other before the demand goes out.
	for i in range(360):
		await get_tree().physics_frame
		if not _contact(patrol, pirate).is_empty():
			break

	var runner = JobRunnerLeaf.new()
	var patrol_bb = BlackboardScript.new()
	var outlaw = OutlawResponseLeaf.new()
	var pirate_bb = BlackboardScript.new()

	# The same job InterdictLeaf assigns -- DEMAND_STOP with patience, tagged
	# interdict_tier so this is the patrol's stop and not a pirate's robbery.
	patrol.assignment = {
		"steps": [{"verb": "DEMAND_STOP", "patience": 9999.0, "on_abort": ""}],
		"current": 0, "victim_iid": pirate.get_instance_id(), "interdict_tier": "HOSTILE",
	}

	print("")
	print("   t | patrol_spd  pirate_spd |  separation | hail_rng  outpaced_at | note")
	print("  ---+------------------------+-------------+-----------------------------")

	var frames := 0
	var declared := ""
	while frames < TRACE_SECONDS * 60:
		runner.tick(patrol, patrol_bb)
		outlaw.tick(pirate, pirate_bb)
		await get_tree().physics_frame
		frames += 1

		if frames % 60 != 0:
			continue
		var c: Dictionary = _contact(patrol, pirate)
		var hail_rng: float = JobSteps._hail_range_to(patrol, pirate.get_instance_id())
		var sep: float = patrol.position.distance_to(pirate.position)
		var note := ""
		if c.get("complied_stop", false):
			note = "COMPLIED"
		elif hail_rng > 0.0 and sep > hail_rng * 1.2:
			note = "OUTPACED (abort fires here)"
			if declared == "":
				declared = "t=%ds" % (frames / 60)
		print("  %3d | %9.0f  %10.0f | %11.0f | %7.0f  %11.0f | %s" % [
			frames / 60, patrol.linear_velocity.length(), pirate.linear_velocity.length(),
			sep, hail_rng, hail_rng * 1.2, note])

		if patrol.assignment.is_empty():
			print("  (patrol's job ended -- abort or completion)")
			break

	print("")
	print("  READ THIS AS: if the patrol's speed never approaches its 2200 max, the")
	print("  chase is acceleration- or command-limited, not speed-capped. If the")
	print("  separation grows while the patrol is FASTER than the pirate, the")
	print("  pursuit is not pointed at the target.")
	if declared != "":
		print("  outpaced first declared at %s" % declared)
