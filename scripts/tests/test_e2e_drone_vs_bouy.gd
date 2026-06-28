extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

var drone_ship: Ship
var bouy: Buoy

func setup(main_node: Node) -> void:
	print("Starting E2E Test: Drone vs Bouy")
	
	# Create Drone
	drone_ship = Ship.new()
	drone_ship.name = "Ship_1"
	drone_ship.owner_id = 1
	drone_ship.iff_tags = ["TEAM_A"]
	drone_ship.position = Vector2(0, 0)
	drone_ship.rotation = 0.0 # Pointing right
	main_node.add_child(drone_ship)
	
	# Add the M12 Beehave behavior tree (replaces the legacy AIDroneController).
	drone_ship.add_child(AITreeFactory.build_default())
	
	# Add Bouy
	bouy = Buoy.new()
	bouy.name = "Bouy_1"
	bouy.position = Vector2(5000.0, 0) # 5km away
	main_node.add_child(bouy)

var frames = 0
func _physics_process(delta: float) -> void:
	frames += 1
	# A vaporized buoy (reactor breach -> queue_free) is a freed instance -- that
	# counts as destroyed, so guard before touching .is_dead/.health.
	var bouy_destroyed = not is_instance_valid(bouy) or bouy.is_dead or bouy.health <= 0

	# Run for up to 30 seconds (1800 frames at 60fps)
	if frames >= 1800:
		if bouy_destroyed:
			print(">>> [TEST PASSED] Bouy was destroyed by drone.")
			get_tree().quit(0)
		else:
			print(">>> [TEST FAILED] Bouy survived after 30 seconds. Health: ", bouy.health)
			get_tree().quit(1)

	# If buoy dies early, we win!
	if bouy_destroyed:
		print(">>> [TEST PASSED] Bouy was destroyed early at frame ", frames)
		get_tree().quit(0)
