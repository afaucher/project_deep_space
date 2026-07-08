extends "res://scripts/ships/ship.gd"
class_name MobileHome

static func design() -> Array:
	return [
		# Layout relative to center (0,0). Forward +X, Right +Y
		{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 180.0, "max_health": 180.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 180.0, "max_health": 180.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fwd", "type": "hull", "rect": Rect2(5, -5, 10, 10), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_port", "type": "hull", "rect": Rect2(0, -5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_stbd", "type": "hull", "rect": Rect2(0, 2.5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 50.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-25, -10, 10, 20), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 40.0, "thrust_rating": 2500.0, "torque_rating": 6000.0},

		{"id": "comms_array", "type": "comms", "rect": Rect2(-5, -5, 5, 10), "health": 30.0, "max_health": 30.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 30000.0},

		{"id": "omni_main", "type": "sensors", "rect": Rect2(0, -2.5, 5, 5), "health": 30.0, "max_health": 30.0, "density": 20.0, "heat": 0.0, "base_em_emission": 8.0, "em_emission": 8.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 22000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 1.5, "timer": 0.0, "heading": 0.0},

		# Add a living quarters! Sits just outboard of the port hull slab
		# (edge-adjacent along y=-15), clear of the packed interior -- the old
		# Rect2(-5,-10,...) overlapped hull_port and failed the design validator.
		{"id": "living_quarters_1", "type": "living_quarters", "rect": Rect2(-5, -20, 10, 5), "health": 150.0, "max_health": 150.0, "density": 20.0},
		
		# Add a docking port!
		{
			"id": "dock_main",
			"type": "docking_port",
			"rect": Rect2(5, 15, 10, 5),
			"health": 100.0, "max_health": 100.0, "density": 20.0,
			"heading": PI / 2.0, "has_servo": true,
		},
	]

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	max_speed = 1000.0
	max_omega = 2.0
	max_heat = 150.0
	dockable = true   # Can also be docked TO by bigger stations
	ship_components = design()
	super()
