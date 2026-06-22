extends Node

const Ship = preload("res://scripts/ship.gd")
const Missile = preload("res://scripts/missile.gd")
const MissileController = preload("res://scripts/missile_controller.gd")

var main_node
var log_file: FileAccess

var current_run = 0
var max_runs_per_config = 10

var ranges = [2000.0, 3500.0, 5000.0, 7000.0]
var axes = ["frontal", "broadside"]
var volleys = [1, 2, 3, 4, 5, 6, 8, 10, 15]

var configs = []
var config_idx = 0

var scenario_frames = 0
var max_scenario_frames = 1200 # 20 seconds at 60fps

var f_ship
var missiles = []
var hits = 0
var timeouts = 0

func setup(main) -> void:
	main_node = main
	print("Starting Tactical Sim: Missile vs PD")
	
	for axis in axes:
		for r in ranges:
			for v in volleys:
				configs.append({"axis": axis, "range": r, "volleys": v})
				
	log_file = FileAccess.open("res://tactical_analysis/data/missile_vs_pd_results.csv", FileAccess.WRITE)
	if not log_file:
		printerr("Failed to open CSV for writing.")
		get_tree().quit(1)
		return
		
	log_file.store_line("run_id,num_missiles,engagement_range,axis,hits,destroyed,timeouts,ship_killed,hits_taken")
	
	_start_scenario()

func _start_scenario() -> void:
	if config_idx >= configs.size():
		print("Tactical Sim Complete. Closing log.")
		log_file.close()
		get_tree().quit(0)
		return
		
	var config = configs[config_idx]
	if current_run >= max_runs_per_config:
		current_run = 0
		config_idx += 1
		_start_scenario()
		return
		
	current_run += 1
	scenario_frames = 0
	hits = 0
	timeouts = 0
	missiles.clear()
	
	f_ship = Ship.new()
	f_ship.name = "DefenderShip_" + str(current_run)
	f_ship.owner_id = 1
	f_ship.iff_tags = ["TEAM_A"]
	
	if config["axis"] == "frontal":
		f_ship.rotation = -PI / 2.0
	else:
		f_ship.rotation = 0.0
		
	f_ship.position = Vector2(0, 0)
	main_node.add_child(f_ship)
	
	var num_missiles = config["volleys"]
	var base_range = config["range"]
	
	for i in range(num_missiles):
		var m = Missile.new()
		m.name = "Missile_" + str(current_run) + "_" + str(i)
		m.owner_id = 2
		m.iff_tags = ["TEAM_B"]
		
		var angle = randf_range(PI/2.0 - 0.2, PI/2.0 + 0.2)
		m.position = Vector2(cos(angle), sin(angle)) * base_range
		m.rotation = m.position.angle_to_point(f_ship.position) + randf_range(-0.1, 0.1)
		
		main_node.add_child(m)
		missiles.append(m)
		
		var start_vel = Vector2(cos(m.rotation), sin(m.rotation)) * randf_range(150.0, 250.0)
		m.linear_velocity = start_vel
		
		var controller = MissileController.new()
		m.add_child(controller)

func _physics_process(delta: float) -> void:
	if config_idx >= configs.size():
		return
		
	scenario_frames += 1
	var config = configs[config_idx]
	
	var any_active = false
	var current_active_count = 0
	
	if not is_instance_valid(f_ship) or f_ship.is_dead:
		# Ship is dead!
		_finish_scenario(config, true)
		return
	
	for i in range(missiles.size() - 1, -1, -1):
		var m = missiles[i]
		if is_instance_valid(m) and not m.is_dead and not m.is_queued_for_deletion():
			any_active = true
			current_active_count += 1
			if m.position.distance_to(f_ship.position) < 200:
				hits += 1
				m.queue_free()
				missiles.remove_at(i)
		else:
			# Destroyed
			missiles.remove_at(i)
			
	if current_active_count == 0 or scenario_frames > max_scenario_frames:
		if scenario_frames > max_scenario_frames:
			timeouts = current_active_count
		_finish_scenario(config, false)

func _finish_scenario(config, ship_killed) -> void:
	var destroyed = config["volleys"] - hits - timeouts
	var sk = 1 if ship_killed else 0
	var hits_taken = hits
	
	log_file.store_line(str(current_run) + "," + str(config["volleys"]) + "," + str(config["range"]) + "," + config["axis"] + "," + str(hits) + "," + str(destroyed) + "," + str(timeouts) + "," + str(sk) + "," + str(hits_taken))
	print("Run " + str(current_run) + " completed: " + str(hits) + " hits, " + str(destroyed) + " destroyed, " + str(timeouts) + " timeouts.")
	
	_cleanup_current()
	_start_scenario()

func _cleanup_current() -> void:
	if is_instance_valid(f_ship):
		f_ship.queue_free()
	for m in missiles:
		if is_instance_valid(m):
			m.queue_free()
	missiles.clear()
