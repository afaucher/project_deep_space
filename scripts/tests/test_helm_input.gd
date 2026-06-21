extends Node

const Ship = preload("res://scripts/ship.gd")

var main_node: Node = null
var time_elapsed: float = 0.0
var test_phase: int = 0
var host_id: int = 1

func setup(main) -> void:
	main_node = main
	print("Test test_helm_input initialized.")
	
	# Manually set host state to avoid Steam Manager headless errors
	main_node.is_host = true
	main_node._spawn_ship(host_id)

func _physics_process(delta: float) -> void:
	if not main_node or not main_node.players.has(host_id): return
	time_elapsed += delta
	
	if test_phase == 0:
		# Wait for Godot to process the connection frame
		if time_elapsed > 0.5:
			# Simulate sending helm input
			# Thrust 1.0, Heading 90 degrees (PI/2), Combat Mode (1)
			main_node.receive_helm_input(1.0, 100.0, PI/2.0, 1, 0)
			print("Sent helm input: thrust 1.0, heading 90deg, combat mode")
			test_phase = 1
			
	elif test_phase == 1:
		if time_elapsed > 1.5:
			# Verify the Ship node received the input
			var ship = main_node.players[host_id]
			var vel = ship.linear_velocity.length()
			var rot_speed = abs(ship.angular_velocity)
			
			if vel > 5.0 and rot_speed > 0.1:
				print("[TEST PASSED] test_helm_input")
				get_tree().quit(0)
			else:
				printerr("[TEST FAILED] Ship did not react to helm input! vel: ", vel, " rot_speed: ", rot_speed)
				get_tree().quit(1)
