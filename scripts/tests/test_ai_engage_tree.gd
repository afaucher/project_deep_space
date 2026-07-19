extends Node

# M12 (minimal engage slice): proves the new Beehave AI fires MORE than the legacy
# controller did. The legacy ai_drone_controller fired only hp_fwd_missile (every 10s)
# and never touched the lasers. With a target dead ahead in laser range, the new
# fire_opportunity leaf must fire BOTH the forward laser AND the forward missile.
#
# Assertions key off firing evidence (non-racy): the forward missile starts at
# 10 ammo and Ship.fire_weapon consumes one on a successful shot; the forward
# laser is reactor-powered (no ammo field at all -- see ship.gd's
# normalization), so its own "fired" evidence is a nonzero cooldown instead
# (snapped to cooldown_max the instant it fires, same detection
# test_fire_staleness_gate.gd's _lasers_on_cooldown() uses). Laser-fired is
# the load-bearing assertion -- it is exactly what the legacy AI never achieved.
const Frigate = preload("res://scripts/ships/frigate.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
# M48 -- the buoy needs a declared flag the drone's default
# known_enemy_flags=[FLAG_PIRATE] recognizes, or it never reads HOSTILE.
const Standing = preload("res://scripts/combat/standing.gd")

var drone: Frigate
var frames := 0

func setup(main) -> void:
	print("Test test_ai_engage_tree initialized.")

	drone = Frigate.new()
	drone.name = "Ship_1"
	drone.owner_id = 1
	drone.iff_tags = ["TEAM_A"]
	drone.position = Vector2.ZERO
	drone.rotation = 0.0 # facing +X
	main.add_child(drone)
	drone.add_child(AITreeFactory.build_default())

	# Target dead ahead, inside the forward laser's 4 km range.
	var target = Buoy.new()
	target.name = "Target"
	target.position = Vector2(2500, 0)
	target.linear_velocity = Vector2.ZERO
	main.add_child(target)
	target.set_transponder_flag(Standing.FLAG_PIRATE)

func _physics_process(_delta: float) -> void:
	frames += 1

	var laser = drone.get_component("hp_fwd_laser")
	var missile = drone.get_component("hp_fwd_missile")
	var laser_fired = not laser.is_empty() and laser.get("cooldown", 0.0) > 0.0
	var missile_fired = not missile.is_empty() and missile.get("ammo", 10) < 10

	if laser_fired and missile_fired:
		print("Drone fired forward laser (cooldown %.2f) AND forward missile (ammo %d) by frame %d." % [laser.get("cooldown", 0.0), missile["ammo"], frames])
		print(">>> [TEST PASSED] test_ai_engage_tree <<<")
		get_tree().quit(0)
		return

	# 900 frames = 15s at 60fps: ample for detection, classification, and firing.
	if frames >= 900:
		var fails: Array = []
		if not laser_fired:
			fails.append("forward laser never fired (cooldown still %s) -- AI not using all weapons that bear" % laser.get("cooldown", "?"))
		if not missile_fired:
			fails.append("forward missile never fired (ammo still %s)" % missile.get("ammo", "?"))
		for f in fails:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_ai_engage_tree <<<")
		get_tree().quit(1)
