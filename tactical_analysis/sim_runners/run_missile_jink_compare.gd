extends Node

# Missile jink x PD-refresh interaction.
#
# Jink only helps if the PD firing solution can go stale between sensor refreshes, so
# its value is coupled to omni_short_hi_res.refresh_interval. This sweeps jink (off/on)
# against a few refresh rates (bins fixed at 3600) to find where evasion starts paying
# off. Same frontal scenario as run_missile_vs_pd.
#
# Output columns: jink (0/1), refresh, bins, volley, range, hits (leaked), destroyed, timeouts.

const Frigate = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const MissileController = preload("res://scripts/missile_controller.gd")

var main_node
var log_file: FileAccess

var current_run = 0
var max_runs_per_config = 10

var jink_modes = [0, 1]            # DebugSettings.MissileJink.OFF / ON
var refreshes = [0.0, 0.1, 0.25]   # omni_short_hi_res.refresh_interval
var pd_bins = 3600                 # fixed; bins above ~3600 don't change PD (see sensor sweep)
var volleys = [5, 6, 8]
var ranges = [3500.0, 7000.0]

var configs = []
var config_idx = 0

var scenario_frames = 0
var max_scenario_frames = 1200

var f_ship
var missiles = []
var hits = 0
var timeouts = 0

func setup(main) -> void:
	main_node = main
	print("Starting Tactical Sim: Missile Jink x Refresh")

	for j in jink_modes:
		for rr in refreshes:
			for v in volleys:
				for r in ranges:
					configs.append({"jink": j, "refresh": rr, "volley": v, "range": r})

	var csv_path = "res://tactical_analysis/data/missile_jink_compare_results.csv"
	log_file = FileAccess.open(csv_path, FileAccess.WRITE)
	if not log_file:
		printerr("Failed to open CSV for writing.")
		get_tree().quit(1)
		return

	log_file.store_line("run_id,jink,refresh,bins,volley,engagement_range,hits,destroyed,timeouts")
	_start_scenario()

func _start_scenario() -> void:
	if config_idx >= configs.size():
		print("Jink x Refresh complete. Closing log.")
		log_file.close()
		get_tree().quit(0)
		return

	var config = configs[config_idx]
	if current_run >= max_runs_per_config:
		current_run = 0
		config_idx += 1
		_start_scenario()
		return

	DebugSettings.set_choice("missile_jink", config["jink"])

	current_run += 1
	scenario_frames = 0
	hits = 0
	timeouts = 0
	missiles.clear()

	f_ship = Frigate.new()
	f_ship.name = "DefenderShip_" + str(current_run)
	f_ship.owner_id = 1
	f_ship.iff_tags = ["TEAM_A"]
	for c in f_ship.ship_components:
		if c.get("id", "") == "omni_short_hi_res":
			c["refresh_interval"] = config["refresh"]
			c["num_bins"] = pd_bins
			break
	f_ship.rotation = PI / 2.0 # frontal
	f_ship.position = Vector2(0, 0)
	main_node.add_child(f_ship)

	var num_missiles = config["volley"]
	var base_range = config["range"]

	for i in range(num_missiles):
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

func _finish_scenario() -> void:
	var config = configs[config_idx]
	var destroyed = config["volley"] - hits - timeouts
	log_file.store_line("%d,%d,%s,%d,%d,%d,%d,%d,%d" % [
		current_run, int(config["jink"]), str(config["refresh"]), pd_bins,
		int(config["volley"]), int(config["range"]), hits, destroyed, timeouts])

	_cleanup_current()
	_start_scenario()

func _cleanup_current() -> void:
	if is_instance_valid(f_ship):
		f_ship.queue_free()
	for m in missiles:
		if is_instance_valid(m):
			m.queue_free()
	missiles.clear()
