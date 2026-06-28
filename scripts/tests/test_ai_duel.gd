extends Node

# M12c verification: frigate-vs-frigate duel, new Beehave AI vs the legacy controller on
# identical hulls, last one alive wins. The new AI brings its broadside to bear and
# volleys its 3-tube battery (massed fire that saturates PD); the legacy AI trickles one
# forward missile that the new AI's PD swats. The new AI must win EVERY trial.
#
# This is the real superiority test the project wanted -- it only becomes decisive (not a
# mutual-PD stalemate) now that M12a (fire_group / synchronized volley) and M12c
# (broadside orientation) both exist.
const Frigate = preload("res://scripts/ships/frigate.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const LegacyAI = preload("res://scripts/ai_drone_controller.gd")

const TRIALS := 3
const MAX_FRAMES := 3000          # 50s cap per duel
const START_RANGE := 8000.0       # the new AI's optimal broadside range
# A "win" is decisive dominance of the EXCHANGE, not a lucky reactor hit. A clean is_dead
# kill needs a missile to happen to destroy a critical component (stochastic even while
# one ship is ground to dust), and absolute damage dealt in the time cap varies with PD
# luck -- so we measure lopsidedness: the new AI must survive, inflict real damage, and
# take far less than it deals. The dominance RATIO + new's survival are the real
# superiority signal; MIN_DAMAGE_DEALT is only a floor to reject "nothing happened".
#
# That floor was recalibrated down (1000 -> 500) after laser overkill made PD far more
# lethal against missiles: the new AI's missile volleys now get intercepted much more, so
# it lands ~750-1500 on the legacy ship per duel instead of the old 2000-3500 -- while
# still ending at ~full HP itself (new_lost ~= 0, so the ratio is effectively infinite).
# 500 still means a couple of missiles genuinely connected, i.e. a real exchange occurred.
const MIN_DAMAGE_DEALT := 500.0   # legacy must actually be hurt (a real fight happened)
const DOMINANCE_RATIO := 4.0      # legacy must lose at least this many times the new AI's loss

var main_node
var trial := 0
var global_trial := 0
var frames := 0
var ship_new
var ship_legacy
var full_health := 0.0            # pristine total health of a fresh frigate
var results: Array = []           # one entry per trial: "new" / "legacy" / "draw"

func setup(main) -> void:
	main_node = main
	print("Test test_ai_duel initialized.")
	_start_trial()

func _start_trial() -> void:
	frames = 0
	var origin = Vector2(global_trial * 300000.0, 0.0)  # isolate trials in space

	ship_new = Frigate.new()
	ship_new.name = "NewAI"
	ship_new.owner_id = 1
	ship_new.iff_tags = ["TEAM_A"]
	ship_new.position = origin
	ship_new.rotation = 0.0
	main_node.add_child(ship_new)
	ship_new.add_child(AITreeFactory.build_default())

	ship_legacy = Frigate.new()
	ship_legacy.name = "LegacyAI"
	ship_legacy.owner_id = 2
	ship_legacy.iff_tags = ["TEAM_B"]
	ship_legacy.position = origin + Vector2(START_RANGE, 0)
	ship_legacy.rotation = PI
	main_node.add_child(ship_legacy)
	ship_legacy.add_child(LegacyAI.new())

	if full_health == 0.0:
		full_health = _total_health(ship_new)  # pristine, captured before any combat

func _total_health(ship) -> float:
	# A vaporized ship (reactor breach -> queue_free) is a freed instance: treat
	# it as a total loss, since that's exactly what it is.
	if not is_instance_valid(ship):
		return 0.0
	var h = 0.0
	for c in ship.ship_components:
		h += max(0.0, c["health"])
	return h

func _physics_process(_delta: float) -> void:
	frames += 1
	# A vaporized ship is freed, so guard before touching it -- gone counts as dead.
	var new_dead = not is_instance_valid(ship_new) or ship_new.is_dead
	var legacy_dead = not is_instance_valid(ship_legacy) or ship_legacy.is_dead
	if not (new_dead or legacy_dead or frames >= MAX_FRAMES):
		return

	var new_h = _total_health(ship_new)
	var legacy_h = _total_health(ship_legacy)
	var new_lost = full_health - new_h
	var legacy_lost = full_health - legacy_h
	var dominant = legacy_lost >= MIN_DAMAGE_DEALT and legacy_lost >= DOMINANCE_RATIO * new_lost
	var outcome := "draw"
	if new_dead and not legacy_dead:
		outcome = "legacy"
	elif not new_dead and (legacy_dead or dominant):
		outcome = "new"
	results.append(outcome)
	print("Trial %d: winner=%s at frame %d (new lost %.0f, legacy lost %.0f)" % [
		trial, outcome, frames, new_lost, legacy_lost])

	if is_instance_valid(ship_new):
		ship_new.queue_free()
	if is_instance_valid(ship_legacy):
		ship_legacy.queue_free()

	trial += 1
	global_trial += 1
	if trial < TRIALS:
		_start_trial()
	else:
		_evaluate()

func _evaluate() -> void:
	var new_wins = results.count("new")
	print("Duel results: ", results, " (new won %d/%d)" % [new_wins, TRIALS])
	if new_wins == TRIALS:
		print(">>> [TEST PASSED] test_ai_duel <<<")
		get_tree().quit(0)
	else:
		printerr("  ASSERT FAILED: new AI did not win every duel (%s)" % [results])
		print(">>> [TEST FAILED] test_ai_duel <<<")
		get_tree().quit(1)
