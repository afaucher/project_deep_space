extends Node

# M27 acceptance -- system defence pod (per
# implementation_plans/m27_catalog_expansion_design.md test plan item 6). A
# 6-missile salvo inbound: the pod's PD should intercept a majority (loose
# gate, >= 3 killed before impact -- a smoke test, not a balance sweep, per
# the plan) and the pod must never move (STRUCTURE tier, no engines).
#
# Missile-vs-PD spawning pattern adapted from
# tactical_analysis/sim_runners/run_missile_vs_pd.gd (the existing sim-runner
# infra for this exact scenario shape): missiles spawn hostile-IFF at a
# stand-off range with an initial closing velocity + a MissileController child
# for self-guidance, so each missile flies itself in rather than being
# scripted -- same as that sim's frontal-axis config. A missile that reaches
# proximity-fuse range detonates on the pod (a "leaker"); a missile the pod's
# PD guts along the way dies before ever reaching that range (an
# "intercept") -- same accounting run_missile_vs_pd.gd uses (hits vs.
# destroyed).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_defence_pod
# Pass marker per CLAUDE.md.

const DefencePod = preload("res://scripts/ships/defence_pod.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const MissileController = preload("res://scripts/missile_controller.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const POD_POS := Vector2.ZERO
const POD_STATIONKEEP_TOLERANCE := 30.0
const NUM_MISSILES := 6
const MIN_INTERCEPTS := 3          # loose gate per the plan (smoke test, not a balance sweep)
# 3000u: inside the pod's PD sensor/laser envelope with margin, and matches
# the range band where tactical_analysis/data/missile_vs_pd_results.csv shows
# a defended hull reliably wins most engagements (the 5000-7000u band in that
# same data shows much higher variance run-to-run -- this test wants a
# reliable smoke-test signal, not a worst-case range probe).
const SALVO_RANGE := 3000.0
const IMPACT_DIST := 200.0         # matches run_missile_vs_pd.gd's own "hit" distance
const MAX_FRAMES := 1200           # 20s at 60fps, matches run_missile_vs_pd.gd's scenario cap

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var pod = null
var missiles: Array = []
var frames: int = 0
var hits: int = 0                  # leakers that reached the pod
var max_pod_drift: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Defence Pod (M27) Tests")

	pod = DefencePod.new()
	pod.name = "DefencePod"
	pod.owner_id = 600
	pod.iff_tags = ["TEAM_POD"]
	pod.position = POD_POS
	main_node.add_child(pod)
	pod.add_child(AITreeFactory.build_station())

	# Salvo spread evenly around the full circle (one missile roughly per
	# cardinal quadrant, per the plan's "covering all four quadrants") rather
	# than bunched into one narrow frontal arc -- inbound-velocity seeding
	# adapted from run_missile_vs_pd.gd. This is the honest engagement shape
	# for a ring station with all-around PD: an attacker doesn't get to pick
	# the one axis with the least coverage, and tactical_analysis's own data
	# shows a broadside-style spread (multiple weapon groups bearing at once)
	# clears salvos far more reliably than a single narrow frontal axis.
	for i in range(NUM_MISSILES):
		var m = Missile.new()
		m.name = "SalvoMissile_%d" % i
		m.owner_id = 601 + i
		m.iff_tags = ["TEAM_HOSTILE"]

		var angle = (TAU / float(NUM_MISSILES)) * float(i) + randf_range(-0.2, 0.2)
		m.position = Vector2(cos(angle), sin(angle)) * SALVO_RANGE
		m.rotation = m.position.angle_to_point(pod.position) + randf_range(-0.1, 0.1)

		main_node.add_child(m)
		missiles.append(m)

		var start_vel = Vector2(cos(m.rotation), sin(m.rotation)) * randf_range(150.0, 250.0)
		m.linear_velocity = start_vel

		var controller = MissileController.new()
		m.add_child(controller)

func _physics_process(delta: float) -> void:
	if finished:
		return
	frames += 1

	if is_instance_valid(pod):
		var drift: float = pod.position.distance_to(POD_POS)
		max_pod_drift = max(max_pod_drift, drift)

	var any_active := false
	for i in range(missiles.size() - 1, -1, -1):
		var m = missiles[i]
		if is_instance_valid(m) and not m.is_dead and not m.is_queued_for_deletion():
			any_active = true
			if m.position.distance_to(pod.position if is_instance_valid(pod) else POD_POS) < IMPACT_DIST:
				hits += 1
				m.queue_free()
				missiles.remove_at(i)
		else:
			missiles.remove_at(i)

	if not is_instance_valid(pod) or (not any_active and missiles.is_empty()) or frames > MAX_FRAMES:
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true

	var intercepts: int = NUM_MISSILES - hits
	print("Defence pod salvo result: %d/%d missiles intercepted, %d leaker(s) hit the pod." % [intercepts, NUM_MISSILES, hits])

	_assert(is_instance_valid(pod), "pod should still be alive/valid at the end of the run")
	if is_instance_valid(pod):
		_assert(max_pod_drift <= POD_STATIONKEEP_TOLERANCE,
			"pod should never move (max drift %.1fu > tolerance %.1fu)" % [max_pod_drift, POD_STATIONKEEP_TOLERANCE])

	_assert(intercepts >= MIN_INTERCEPTS,
		"pod PD should intercept a majority of the salvo (loose gate >= %d/%d, got %d)" % [MIN_INTERCEPTS, NUM_MISSILES, intercepts])

	if failures.is_empty():
		print(">>> [TEST PASSED] test_defence_pod <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_defence_pod <<<")
		get_tree().quit(1)
