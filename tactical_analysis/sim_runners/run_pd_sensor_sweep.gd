extends Node

# PD sensor-knob sweep.
#
# PD became very lethal once laser overkill let a single hit punch through a missile
# to its reactor. The intended lever to dial PD back down is the close-in fire-control
# sensor (omni_short_hi_res): its refresh_interval (how often the firing solution
# updates) and num_bins (angular resolution of the tracked position). This sim holds a
# fixed missile threat and sweeps those two knobs, so we can see how PD kill-rate
# degrades as the sensor is made slower / coarser -- and pick a setting that leaves
# massed volleys able to leak through.
#
# Mirrors run_missile_vs_pd.gd's scenario, frontal axis only (PD's best case), but
# overrides the defender's omni_short_hi_res sensor per config. Output columns:
# refresh, bins, range, volley, hits (leaked), destroyed, timeouts.

const Frigate = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const MissileController = preload("res://scripts/missile_controller.gd")
# M48 -- see run_missile_vs_pd.gd's identical comment: these missiles have no
# launcher to inherit a HOSTILE contact snapshot from, and no comms to
# receive a transponder flag, so mark_contact_hostile is the only lever.
const Standing = preload("res://scripts/combat/standing.gd")

var main_node
var log_file: FileAccess

var current_run = 0
var max_runs_per_config = 10

# Sensor knobs to sweep. 0.0 refresh + 36000 bins is the current (max) setting.
var refresh_rates = [0.0, 0.1, 0.25, 0.5]
var bin_counts = [36000, 3600, 720, 180]

# Fixed threat: a mid-size volley at a short and a long contested range.
var ranges = [3500.0, 7000.0]
var volley = 6

var configs = []
var config_idx = 0

var scenario_frames = 0
var max_scenario_frames = 1200 # 20s at 60fps

var f_ship
var missiles = []
var hits = 0
var timeouts = 0

func setup(main) -> void:
	main_node = main
	print("Starting Tactical Sim: PD Sensor Sweep")

	for rr in refresh_rates:
		for nb in bin_counts:
			for r in ranges:
				configs.append({"refresh": rr, "bins": nb, "range": r})

	var csv_path = "res://tactical_analysis/data/pd_sensor_sweep_results.csv"
	log_file = FileAccess.open(csv_path, FileAccess.WRITE)
	if not log_file:
		printerr("Failed to open CSV for writing.")
		get_tree().quit(1)
		return

	log_file.store_line("run_id,refresh,bins,engagement_range,volley,hits,destroyed,timeouts")
	_start_scenario()

func _start_scenario() -> void:
	if config_idx >= configs.size():
		print("PD Sensor Sweep complete. Closing log.")
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

	f_ship = Frigate.new()
	f_ship.name = "DefenderShip_" + str(current_run)
	f_ship.owner_id = 1
	f_ship.iff_tags = ["TEAM_A"]
	# Override the close-in PD sensor's refresh + resolution for this config. Done
	# before add_child (and thus before the first sweep) so the run uses it from t=0.
	for c in f_ship.ship_components:
		if c.get("id", "") == "omni_short_hi_res":
			c["refresh_interval"] = config["refresh"]
			c["num_bins"] = config["bins"]
			break
	# Frontal engagement (PD's strongest case): forward (+X) pointed at the +PI/2
	# spawn bearing, same convention as run_missile_vs_pd's "frontal".
	f_ship.rotation = PI / 2.0
	f_ship.position = Vector2(0, 0)
	main_node.add_child(f_ship)

	var base_range = config["range"]

	for i in range(volley):
		var m = Missile.new()
		m.name = "Missile_" + str(current_run) + "_" + str(i)
		m.owner_id = 2
		m.iff_tags = ["TEAM_B"]

		var angle = randf_range(PI / 2.0 - 0.2, PI / 2.0 + 0.2)
		m.position = Vector2(cos(angle), sin(angle)) * base_range
		m.rotation = m.position.angle_to_point(f_ship.position) + randf_range(-0.1, 0.1)

		main_node.add_child(m)
		missiles.append(m)

		var start_vel = Vector2(cos(m.rotation), sin(m.rotation)) * randf_range(150.0, 250.0)
		m.linear_velocity = start_vel

		var controller = MissileController.new()
		m.add_child(controller)

func _physics_process(_delta: float) -> void:
	if config_idx >= configs.size():
		return

	scenario_frames += 1
	_mark_target_hostile_for_missiles()

	if not is_instance_valid(f_ship) or f_ship.is_dead:
		_finish_scenario()
		return

	var current_active_count = 0
	for i in range(missiles.size() - 1, -1, -1):
		var m = missiles[i]
		if is_instance_valid(m) and not m.is_dead and not m.is_queued_for_deletion():
			current_active_count += 1
			if m.position.distance_to(f_ship.position) < 200:
				hits += 1
				m.queue_free()
				missiles.remove_at(i)
		else:
			missiles.remove_at(i)

	if current_active_count == 0 or scenario_frames > max_scenario_frames:
		if scenario_frames > max_scenario_frames:
			timeouts = current_active_count
		_finish_scenario()

# M48 -- see the const Standing comment above.
func _mark_target_hostile_for_missiles() -> void:
	if not is_instance_valid(f_ship):
		return
	var tid: int = f_ship.get_instance_id()
	for m in missiles:
		if not is_instance_valid(m) or m.is_dead:
			continue
		for c_id in m.active_contacts:
			var c: Dictionary = m.active_contacts[c_id]
			if c.get("instance_id", -1) == tid and c.get("standing", "") != Standing.HOSTILE:
				m.mark_contact_hostile(c_id, "test target")
				break

func _finish_scenario() -> void:
	var config = configs[config_idx]
	var destroyed = volley - hits - timeouts
	log_file.store_line("%d,%s,%d,%d,%d,%d,%d,%d" % [
		current_run, str(config["refresh"]), int(config["bins"]), int(config["range"]),
		volley, hits, destroyed, timeouts])

	_cleanup_current()
	_start_scenario()

func _cleanup_current() -> void:
	if is_instance_valid(f_ship):
		f_ship.queue_free()
	for m in missiles:
		if is_instance_valid(m):
			m.queue_free()
	missiles.clear()
