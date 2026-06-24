extends Node

const Frigate = preload("res://scripts/ships/frigate.gd")

var main_node
var log_file: FileAccess

var current_run = 0
var total_runs = 10
var scenario_frames = 0
var max_scenario_frames = 3600 # 60 seconds max

var base_range = 3000.0

var ship_a
var ship_b

func setup(main) -> void:
	main_node = main
	print("Starting Tactical Sim: Time To Kill (Lasers)")
	
	log_file = FileAccess.open("res://tactical_analysis/data/time_to_kill_results.csv", FileAccess.WRITE)
	if not log_file:
		printerr("Failed to open CSV for writing.")
		get_tree().quit(1)
		return
		
	log_file.store_line("run_id,engagement_range,axis,ttk_seconds,winner,loser_health")
	_start_scenario()

func _start_scenario() -> void:
	if current_run >= total_runs:
		print("Tactical Sim Complete. Closing log.")
		log_file.close()
		get_tree().quit(0)
		return
		
	current_run += 1
	scenario_frames = 0
	
	# Spawn Ship A (Player)
	ship_a = Frigate.new()
	ship_a.name = "ShipA_" + str(current_run)
	ship_a.owner_id = 1
	ship_a.iff_tags = ["TEAM_A"]
	ship_a.position = Vector2(randf_range(-100, 100), base_range / 2)
	# Face up
	ship_a.rotation = -PI / 2.0 + randf_range(-0.1, 0.1)
	main_node.add_child(ship_a)
	
	# Spawn Ship B (Enemy)
	ship_b = Frigate.new()
	ship_b.name = "ShipB_" + str(current_run)
	ship_b.owner_id = 2
	ship_b.iff_tags = ["TEAM_B"]
	ship_b.position = Vector2(randf_range(-100, 100), -base_range / 2)
	# Face down
	ship_b.rotation = PI / 2.0 + randf_range(-0.1, 0.1)
	main_node.add_child(ship_b)

func _physics_process(delta: float) -> void:
	if current_run > total_runs:
		return
		
	scenario_frames += 1
	
	var a_alive = is_instance_valid(ship_a) and not ship_a.is_dead
	var b_alive = is_instance_valid(ship_b) and not ship_b.is_dead
	
	if a_alive and b_alive:
		ship_a.target_heading = (ship_b.position - ship_a.position).angle()
		ship_b.target_heading = (ship_a.position - ship_b.position).angle()
		ship_a.target_thrust = 1.0
		ship_b.target_thrust = 1.0
		
		# Force them to fire lasers at each other
		_fire_lasers(ship_a, ship_b)
		_fire_lasers(ship_b, ship_a)
		
	if not a_alive or not b_alive or scenario_frames > max_scenario_frames:
		var ttk = scenario_frames / 60.0
		var winner = "Timeout"
		var loser_health = 0.0
		
		if a_alive and not b_alive:
			winner = "ShipA"
			loser_health = 0.0
		elif b_alive and not a_alive:
			winner = "ShipB"
			loser_health = 0.0
		elif not a_alive and not b_alive:
			winner = "Draw"
		else:
			winner = "Timeout"
			loser_health = ship_b.health # Assuming ShipA is the baseline we care about
			
		log_file.store_line(str(current_run) + "," + str(base_range) + ",head-on," + str(ttk) + "," + winner + "," + str(loser_health))
		print("Run " + str(current_run) + " completed: " + winner + " won in " + str(ttk) + "s")
		
		_cleanup_current()
		_start_scenario()

func _fire_lasers(shooter, target) -> void:
	# Populate active contacts so fire_weapon works (it checks active_contacts for target_id)
	var t_id = "target_" + str(target.owner_id)
	shooter.active_contacts[t_id] = {
		"pos": target.position,
		"vel": target.linear_velocity,
		"classification": "UNIDENTIFIED VESSEL"
	}
	
	# Fire all frontal lasers
	for w_id in ["hp_fwd_laser", "hp_port_laser_1", "hp_stbd_laser_1"]:
		if shooter.weapons.has(w_id) and shooter.weapons[w_id]["ammo"] > 0 and shooter.weapons[w_id]["cooldown"] <= 0:
			shooter.fire_weapon(w_id, target.position, t_id)

func _cleanup_current() -> void:
	if is_instance_valid(ship_a):
		ship_a.queue_free()
	if is_instance_valid(ship_b):
		ship_b.queue_free()
