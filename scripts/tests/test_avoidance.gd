extends Node

# Collision-avoidance acceptance. A ship set to fly straight through where an
# asteroid sits must dodge it (never come within collision distance) yet still
# reach the destination on the far side -- velocity-lookahead avoidance threading
# past an obstacle. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_avoidance
# Needs physics frames. Pass marker per CLAUDE.md.

const Frigate = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const NavAutopilot = preload("res://scripts/nav/nav_autopilot.gd")

const ASTEROID_POS := Vector2(5000, 0)
const DEST := Vector2(10000, 0)
const TIMEOUT := 55.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false
var ship = null
var rock = null
var autopilot = null
var min_rock_dist: float = INF
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Collision Avoidance Tests")

	rock = Asteroid.new()
	rock.name = "Rock"
	rock.position = ASTEROID_POS
	main_node.add_child(rock)   # joins the "obstacles" group in _ready

	ship = Frigate.new()
	ship.name = "Dodger"
	ship.owner_id = 90
	ship.iff_tags = ["TEAM_PLAYER"]
	ship.position = Vector2.ZERO
	main_node.add_child(ship)

	autopilot = NavAutopilot.new()
	ship.add_child(autopilot)
	autopilot.engage([DEST])    # a straight line that passes through the asteroid

func _physics_process(delta: float) -> void:
	if finished or ship == null:
		return
	t += delta
	var d: float = ship.position.distance_to(rock.position)
	if d < min_rock_dist:
		min_rock_dist = d

	if not autopilot.active:
		var collide: float = ship.get_bounding_radius() + rock.get_bounding_radius()
		_assert(min_rock_dist > collide + 20.0,
			"ship should clear the asteroid (min dist %.0f, contact at %.0f)" % [min_rock_dist, collide])
		_assert(ship.position.distance_to(DEST) < 1000.0,
			"ship should still reach the destination past the asteroid (dist %.0f)" % ship.position.distance_to(DEST))
		_finalize()
	elif t > TIMEOUT:
		_assert(false, "TIMEOUT -- never reached the destination (dist %.0f, min rock %.0f)" % [ship.position.distance_to(DEST), min_rock_dist])
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print("Avoidance: cleared the asteroid by %.0fu on the way through." % min_rock_dist)
		print(">>> [TEST PASSED] test_avoidance <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_avoidance <<<")
		get_tree().quit(1)
