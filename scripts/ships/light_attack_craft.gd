extends "res://scripts/ships/ship.gd"
class_name LightAttackCraft

# M9c -- cheap, fast, darty interceptor. Paper armor, single short laser +
# light missile. Engine is oversized for its mass on purpose -- that's what
# makes it fast (see design_ideas/ship_parameter_table.md pattern #2).
# Tier LIGHT. Targets: mass ~14, accel ~110.
#
# M24: design() extracted so variants (see pirate_lac.gd) can compose this
# hull's loadout via Variants.apply() without inheriting LightAttackCraft's
# _init directly (GDScript parent-_init ordering makes subclass mutation
# fragile -- see ship_variants.gd file header). design() returns the exact
# authored component array verbatim (copy-pasted, not retyped) -- the fidelity
# guard is test_ship_variants.gd item 5 plus test_ship_designs staying green.
static func design() -> Array:
	return [
		# Layout relative to center (0,0). Forward +X, Right +Y
		{"id": "hull_port_wing", "type": "hull", "rect": Rect2(-15, -10, 25, 5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd_wing", "type": "hull", "rect": Rect2(-15, 5, 25, 5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_port", "type": "hull", "rect": Rect2(5, -5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fill_stbd", "type": "hull", "rect": Rect2(5, 2.5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fwd_port", "type": "hull", "rect": Rect2(10, -10, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_fwd_stbd", "type": "hull", "rect": Rect2(10, 7.5, 5, 2.5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-5, -5, 10, 10), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 55.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-15, -5, 10, 10), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 50.0, "thrust_rating": 2500.0, "torque_rating": 5000.0},

		{"id": "comms_array", "type": "comms", "rect": Rect2(5, -2.5, 5, 5), "health": 25.0, "max_health": 25.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 30000.0},

		{"id": "omni_fwd_fc", "type": "sensors", "rect": Rect2(10, -2.5, 5, 5), "health": 25.0, "max_health": 25.0, "density": 20.0, "heat": 0.0, "base_em_emission": 8.0, "em_emission": 8.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 25000.0, "arc_width": PI / 1.5, "num_bins": 60, "refresh_interval": 0.5, "timer": 0.0, "heading": 0.0},

		{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(10, -7.5, 5, 5), "health": 55.0, "max_health": 55.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "cooldown": 0.0, "cooldown_max": 0.8, "range": 3000.0, "damage": 250.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(10, 2.5, 5, 5), "health": 55.0, "max_health": 55.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 4, "cooldown": 0.0, "cooldown_max": 15.0, "range": 12000.0, "heading": 0.0, "arc_width": PI / 3.0},
	]

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	max_speed = 2200.0
	max_omega = 4.5
	max_heat = 130.0
	ship_components = design()
	super()
