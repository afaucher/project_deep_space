extends "res://scripts/ships/ship.gd"
class_name CargoShuttle

# M9c -- slow civilian hauler. Unarmed, fragile, big cargo volume, low accel.
# Tier LIGHT. See implementation_plans/m9c_ship_designs.md and
# design_ideas/ship_parameter_table.md for targets (mass ~40, accel ~25).
# Follows the frigate.gd structural template: set ship_components and
# ship_tier BEFORE super() so Ship._init()'s duplicate(true) deep-copies it.
func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	max_speed = 1000.0
	max_omega = 2.0
	max_heat = 150.0
	ship_components = [
		# Layout relative to center (0,0). Forward +X, Right +Y
		{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 180.0, "max_health": 180.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 180.0, "max_health": 180.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fwd", "type": "hull", "rect": Rect2(5, -5, 10, 10), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_port", "type": "hull", "rect": Rect2(0, -5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_stbd", "type": "hull", "rect": Rect2(0, 2.5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 50.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-25, -10, 10, 20), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 40.0, "thrust_rating": 2500.0, "torque_rating": 6000.0},

		{"id": "comms_array", "type": "comms", "rect": Rect2(-5, -5, 5, 10), "health": 30.0, "max_health": 30.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 22000.0},

		{"id": "omni_main", "type": "sensors", "rect": Rect2(0, -2.5, 5, 5), "health": 30.0, "max_health": 30.0, "density": 20.0, "heat": 0.0, "base_em_emission": 8.0, "em_emission": 8.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 22000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 1.5, "timer": 0.0, "heading": 0.0},

		# Unarmed -- the validator allows a ship with zero weapons components.
	]
	super()
