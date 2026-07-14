extends "res://scripts/ships/ship.gd"
class_name Frigate

# The frigate loadout used to live on the Ship base; M9a moved it here so the
# base is a generic, loadout-empty hull and each ship class owns its own
# component array. Set ship_components BEFORE super() so Ship._init()'s
# duplicate(true) still deep-copies it (and initializes iff_tags /
# active_contacts).
func _init() -> void:
	ship_tier = ComponentSpec.Tier.MEDIUM
	ship_components = [
		# Layout relative to center (0,0). Forward +X, Right +Y
		{"id": "hull_fwd", "type": "hull", "rect": Rect2(15, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_aft", "type": "hull", "rect": Rect2(-30, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 200.0, "max_health": 200.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 100.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-35, -10, 5, 20), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 100.0, "thrust_rating": 5000.0, "torque_rating": 10000.0},

		# Comms: gates the datalink relay (M6) -- destroying or powering this off
		# stops the ship both receiving and offering relayed contacts, same as
		# any other component. "range" is the radio's own reach; a link between
		# two ships is capped by the weaker of their two ranges.
		{"id": "comms_array", "type": "comms", "rect": Rect2(5, -5, 5, 5), "health": 60.0, "max_health": 60.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 30000.0},

		# Sensors: each logical sensor is its own physical hardpoint (1:1), replacing the old
		# hp_sensor_fwd/hp_sensor_omni boxes that pooled 5 sensors behind a guessed "parent" id.
		{"id": "dir_high_res", "type": "sensors", "rect": Rect2(30, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 20.0, "em_emission": 20.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 40000.0, "arc_width": PI / 6.0, "num_bins": 30, "refresh_interval": 0.5, "timer": 0.0, "heading": 0.0},
		{"id": "omni_main", "type": "sensors", "rect": Rect2(-5, -5, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 40000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 2.0, "timer": 0.0, "heading": 0.0},
		# Tuned as the ship's close-in fire-control sensor. Two independent fixes,
		# confirmed complementary via a 2x2 ablation (bins x refresh) across the
		# missile-vs-PD tactical sim's full range grid:
		#  - bin_angle = arc_width/num_bins sets the angular quantization of
		#    merged["pos"] in _run_sensor_sweep. 180->36000 bins takes positional
		#    error at ~4000 range from ~140 units (bigger than a missile's own
		#    ~25-unit hitbox -- a guaranteed miss) down to ~0.7 units. Bins alone
		#    fixed short/medium range (2000-5000) but made long range (7000)
		#    WORSE than baseline: by then the missile is moving fast enough that
		#    a precise-but-stale reading drifts past the hitbox before the next
		#    correction, via the dead-reckoning in _physics_process.
		#  - missile_controller.gd steers via continuous proportional navigation
		#    (recomputes desired_heading every physics tick) -- it never holds a
		#    straight line, so dead-reckoning between refreshes lags by however
		#    far it can turn in one refresh window. Refresh alone (0.25s->0.0,
		#    every physics tick) gave a modest flat improvement everywhere but
		#    never got close to reliable on its own -- still capped by 180-bin
		#    quantization error.
		#  - Only with both does PD become reliably lethal (14-15/15) across the
		#    full 2000-7000 range envelope tested. Extra bins are free regardless
		#    -- bins are sparse-allocated per detection, not pre-sized arrays.
		{"id": "omni_short_hi_res", "type": "sensors", "rect": Rect2(0, -5, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 5.0, "em_emission": 5.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 3600, "refresh_interval": 0.1, "timer": 0.0, "heading": 0.0},
		{"id": "passive_em", "type": "sensors", "rect": Rect2(-5, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"sensor_type": "passive_em", "active": true, "range": 80000.0, "arc_width": TAU, "num_bins": 360, "refresh_interval": 1.0, "timer": 0.0, "heading": 0.0},
		{"id": "omni_collision", "type": "sensors", "rect": Rect2(0, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 1500.0, "arc_width": TAU, "num_bins": 8, "refresh_interval": 0.1, "timer": 0.0, "heading": 0.0},

		# Weapons: ammo/cooldown/range/damage/heading/arc_width folded in from the old `weapons` Dict.
		# "mount_pos" dropped — origin is derived via get_component_origin() == rect.position.
		{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(30, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(30, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 10, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": 0.0, "arc_width": PI / 3.0},

		{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(17.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(7.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-2.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-12.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-22.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},

		{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(17.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(7.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-2.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-12.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 15.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-22.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0}
	]
	super()
