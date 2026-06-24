extends Node

const Ship = preload("res://scripts/ships/frigate.gd")

var main_node: Node = null
var ship: Ship = null
var time_elapsed: float = 0.0
var test_phase: int = 0
var velocity_at_cutoff: float = 0.0

func setup(main) -> void:
	main_node = main
	print("Test test_inertial_flight initialized.")
	
	# Instantiate a ship as if we're a player
	ship = Ship.new()
	ship.name = "TestShip"
	ship.position = Vector2.ZERO
	main_node.add_child(ship)

func _physics_process(delta: float) -> void:
	if not ship: return
	time_elapsed += delta
	
	if test_phase == 0:
		# Apply forward thrust
		ship.apply_control_input(1.0, 100.0, 0.0, 1, 0)
		if time_elapsed > 2.0:
			ship.apply_control_input(0.0, 100.0, 0.0, 1, 0) # Cut engines
			velocity_at_cutoff = ship.linear_velocity.length()
			print("Engines cut. Velocity at cutoff: ", velocity_at_cutoff)
			if velocity_at_cutoff < 10.0:
				printerr("[TEST FAILED] Ship did not gain significant velocity from thrust.")
				get_tree().quit(1)
			test_phase = 1
	
	elif test_phase == 1:
		# Wait for drifting
		if time_elapsed > 4.0:
			# Verify the velocity hasn't decreased (no drag)
			var current_vel = ship.linear_velocity.length()
			print("Velocity after drifting: ", current_vel)
			if abs(current_vel - velocity_at_cutoff) > 1.0:
				printerr("[TEST FAILED] Ship lost/gained velocity during drift phase! Current: ", current_vel, " Cutoff: ", velocity_at_cutoff)
				get_tree().quit(1)
			else:
				print("[TEST PASSED] Inertial flight constraints validated. Ship is drifting indefinitely.")
				get_tree().quit(0)
