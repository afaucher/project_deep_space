extends "res://scripts/ships/ship.gd"
class_name SensorDrone

func _init() -> void:
	max_thrust = 0.0
	max_torque = 0.0
	max_speed = 0.0
	# Density unified to the same 20.0 scale as Frigate; derived mass drops from
	# the old flat 200.0 to ~16 as a result. Not used much today, no thrust to
	# retune (max_thrust is 0.0), so the change is free.
	ship_components = [
		{"id": "hull_center", "type": "hull", "rect": Rect2(-10, -10, 20, 20), "health": 200.0, "max_health": 200.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "power_rating": 100.0},
		{"id": "omni_main", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 50.0, "max_health": 50.0, "density": 20.0,
			"heat": 0.0, "base_em_emission": 50.0, "em_emission": 50.0,
			"sensor_type": "active", "active": true, "heading": 0.0, "arc_width": TAU,
			"range": 40000.0, "resolution": 10.0, "timer": 0.0, "refresh_interval": 1.0, "num_bins": 36}
	]

func _ready() -> void:
	super._ready()
	is_relay = true
