extends Node

# M12 superiority regression: the new Beehave AI must beat the retained legacy
# AIDroneController consistently. Both fly the SAME hull (Frigate) against an identical
# buoy; we measure frames-to-kill and require the new AI to win EVERY trial.
#
# Why time-to-kill vs a shared target rather than a head-to-head duel: a direct duel
# between two single-missile-trickle frigates stalemates today -- each ship's point
# defense swats the other's lone missiles, so neither dies (that is precisely the gap
# massed fire / M12a closes). The new AI's decisive, un-interceptable edge right now is
# that fire_opportunity also fires the forward LASER, which the legacy controller never
# touches. Against a PD-less buoy that edge shows up cleanly and repeatably as a faster
# kill. Once M12a lands, a true duel test can be added.
const Frigate = preload("res://scripts/ships/frigate.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const LegacyAI = preload("res://scripts/ai_drone_controller.gd")

const TRIALS_PER_AI := 3
const MAX_FRAMES := 1800          # 30s cap per trial
const TARGET_RANGE := 2500.0      # inside the forward laser's 4 km range
const NO_KILL := MAX_FRAMES + 1   # sentinel: target survived the cap

enum { PHASE_NEW, PHASE_LEGACY }

var main_node
var phase := PHASE_NEW
var trial := 0
var global_trial := 0             # never resets -- used to space trials far apart
var frames := 0
var ship
var buoy
var new_times: Array = []
var legacy_times: Array = []

func setup(main) -> void:
	main_node = main
	print("Test test_ai_vs_legacy initialized.")
	_start_trial()

func _trial_origin() -> Vector2:
	# Each trial lives in its own pocket of space so stray missiles from a prior
	# trial can never reach this trial's ship or buoy.
	return Vector2(global_trial * 200000.0, 0.0)

func _start_trial() -> void:
	frames = 0
	var origin = _trial_origin()

	ship = Frigate.new()
	ship.name = "AIShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = origin
	ship.rotation = 0.0 # facing +X, toward the buoy
	main_node.add_child(ship)

	if phase == PHASE_NEW:
		ship.add_child(AITreeFactory.build_default())
	else:
		ship.add_child(LegacyAI.new())

	buoy = Buoy.new()
	buoy.name = "Buoy"
	buoy.position = origin + Vector2(TARGET_RANGE, 0)
	buoy.linear_velocity = Vector2.ZERO
	main_node.add_child(buoy)

func _physics_process(_delta: float) -> void:
	frames += 1
	var killed = (not is_instance_valid(buoy)) or buoy.is_dead or buoy.health <= 0.0
	if not killed and frames < MAX_FRAMES:
		return

	var t = frames if killed else NO_KILL
	if phase == PHASE_NEW:
		new_times.append(t)
	else:
		legacy_times.append(t)

	if is_instance_valid(ship): ship.queue_free()
	if is_instance_valid(buoy): buoy.queue_free()

	trial += 1
	global_trial += 1
	if trial < TRIALS_PER_AI:
		_start_trial()
	elif phase == PHASE_NEW:
		phase = PHASE_LEGACY
		trial = 0
		_start_trial()
	else:
		_evaluate()

func _evaluate() -> void:
	var new_worst = new_times.max()
	var legacy_best = legacy_times.min()
	print("New AI kill frames:    ", new_times)
	print("Legacy AI kill frames: ", legacy_times)

	# Strong claim: the new AI's SLOWEST kill still beats the legacy AI's FASTEST.
	if new_worst < legacy_best:
		print("New AI killed faster in every trial (worst new %d < best legacy %d)." % [new_worst, legacy_best])
		print(">>> [TEST PASSED] test_ai_vs_legacy <<<")
		get_tree().quit(0)
	else:
		printerr("  ASSERT FAILED: new AI not consistently faster -- new %s vs legacy %s" % [new_times, legacy_times])
		print(">>> [TEST FAILED] test_ai_vs_legacy <<<")
		get_tree().quit(1)
