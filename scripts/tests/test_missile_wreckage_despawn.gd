extends Node

# Regression test for MissileController.WRECKAGE_LINGER (combat perf follow-up):
# a DEAD missile -- fuel-out dud or PD kill that never detonated -- must drift
# as wreckage for a bounded linger and then DESPAWN. Before this, duds hulked
# but were never freed, so every long fight accumulated full-price Ship
# instances forever (the perf_combat dead-ship census measured ~19% of the
# "ships" group dead and climbing). Detonation frees immediately and is
# covered by test_missile_ai; this test covers the two non-detonation paths:
#
#   1. Fuel-out dud: a missile with nothing to lock flies straight, hulks at
#      FUEL_LIFETIME (goes EM-dark -- wreckage), NOT freed yet (linger is the
#      point: sensors should get to see the corpse drift), then frees by
#      FUEL_LIFETIME + WRECKAGE_LINGER.
#   2. Killed dud: a missile hulked by damage (the PD-gutted case, forced
#      directly here) frees by WRECKAGE_LINGER after death -- its fuel clock
#      stopped with it, so the linger runs on its own wreckage clock.
#
# Both missiles run simultaneously, far apart, so the whole test is one
# window of FUEL_LIFETIME + WRECKAGE_LINGER (~136 simulated seconds --
# --fixed-fps 60 keeps the wall-clock cost to a few seconds).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_missile_wreckage_despawn

const Missile = preload("res://scripts/ships/missile.gd")
const MissileControllerScript = preload("res://scripts/missile_controller.gd")

const FUEL_FRAMES := 900          # FUEL_LIFETIME 15s * 60
const LINGER_FRAMES := 7200       # WRECKAGE_LINGER 120s * 60
const MARGIN_FRAMES := 90         # 1.5s of slack around each boundary

var main_scene
var frame := 0
var dud                  # missile A: fuel-out path
var killed               # missile B: dead-by-damage path
var failures: Array = []
var checked_dud_hulked := false
var checked_killed_freed := false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_scene = main
	print("=== test_missile_wreckage_despawn: dud + killed missiles must despawn after linger ===")

	# Missile A: no target anywhere in sensor range -- flies straight until
	# fuel-out. 500k units away from missile B so neither ever sees the other.
	dud = Missile.new()
	dud.name = "DudMissile"
	dud.owner_id = 11
	dud.iff_tags = ["TEAM_A"]
	dud.position = Vector2.ZERO
	main_scene.add_child(dud)
	dud.add_child(MissileControllerScript.new())

	# Missile B: hulked immediately (stands in for a PD hit that gutted the
	# hull without setting off the warhead -- same is_dead wreckage state).
	killed = Missile.new()
	killed.name = "KilledMissile"
	killed.owner_id = 12
	killed.iff_tags = ["TEAM_A"]
	killed.position = Vector2(500000, 0)
	main_scene.add_child(killed)
	killed.add_child(MissileControllerScript.new())
	killed.hulk()

func _physics_process(_delta: float) -> void:
	frame += 1

	# Killed dud: dead at frame 0, must be freed by LINGER + margin -- and
	# must still exist shortly before the linger expires (not freed early).
	if frame == LINGER_FRAMES - MARGIN_FRAMES:
		_assert(is_instance_valid(killed), "killed missile still drifts as wreckage just before its linger expires")
	if frame == LINGER_FRAMES + MARGIN_FRAMES and not checked_killed_freed:
		checked_killed_freed = true
		_assert(not is_instance_valid(killed), "killed missile despawned within WRECKAGE_LINGER (+margin) of dying")

	# Fuel-out dud: alive until FUEL_LIFETIME, wreckage during the linger,
	# freed after.
	if frame == FUEL_FRAMES - MARGIN_FRAMES:
		_assert(is_instance_valid(dud) and not dud.is_dead, "dud missile still alive just before fuel-out")
	if frame == FUEL_FRAMES + MARGIN_FRAMES and not checked_dud_hulked:
		checked_dud_hulked = true
		var valid_and_dead: bool = is_instance_valid(dud) and dud.is_dead
		_assert(valid_and_dead, "dud missile hulked at fuel-out but still lingers as wreckage")
	if frame == FUEL_FRAMES + LINGER_FRAMES + MARGIN_FRAMES:
		_assert(not is_instance_valid(dud), "dud missile despawned within WRECKAGE_LINGER (+margin) of fuel-out")
		_finish()

func _finish() -> void:
	set_physics_process(false)
	if failures.is_empty():
		print(">>> [TEST PASSED] test_missile_wreckage_despawn <<<")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("  FAIL: ", msg)
		printerr(">>> [TEST FAILED] test_missile_wreckage_despawn <<<")
		get_tree().quit(1)
