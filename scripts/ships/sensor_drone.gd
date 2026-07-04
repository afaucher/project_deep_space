extends "res://scripts/ships/ship.gd"
class_name SensorDrone

func _init() -> void:
	max_speed = 0.0
	# No "engines"-type component below, so get_ship_max_thrust()/get_ship_max_torque()
	# are naturally 0.0 -- no need to also zero out a ship-level thrust/torque var.
	# Density unified to the same 20.0 scale as Frigate; derived mass drops from
	# the old flat 200.0 to ~16 as a result. Not used much today, no thrust to
	# retune, so the change is free.
	ship_components = [
		# Hull frame: 4-wall box, outer: (-10,-10) to (10,10), interior: (-8,-8) to (8,8).
		{"id": "hull_top", "type": "hull", "rect": Rect2(-10, -10, 20, 2), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "hull_bot", "type": "hull", "rect": Rect2(-10, 8, 20, 2), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "hull_port", "type": "hull", "rect": Rect2(-10, -8, 2, 16), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(8, -8, 2, 16), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		# Interior: (-8,-8) to (8,8) = 16x16, tiled into quadrants.
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-8, -8, 8, 8), "health": 100.0, "max_health": 100.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "power_rating": 100.0},
		{"id": "comms_array", "type": "comms", "rect": Rect2(0, -8, 8, 8), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 30000.0},
		{"id": "omni_main", "type": "sensors", "rect": Rect2(-8, 0, 16, 8), "health": 50.0, "max_health": 50.0, "density": 20.0,
			"heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0,
			"sensor_type": "active", "active": true, "heading": 0.0, "arc_width": TAU,
			"range": 40000.0, "resolution": 10.0, "timer": 0.0, "refresh_interval": 1.0, "num_bins": 36}
	]
