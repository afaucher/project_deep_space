extends "res://scripts/ships/ship.gd"
class_name Destroyer

# M9c -- big true warship. Heavy armor + reactor armor, full broadside suite,
# rear PD, sluggish. Must out-armor and out-gun the frigate while being
# slower. Tier HEAVY. Targets: mass ~210, accel ~28, hull health ~7600
# (clearly > frigate's 4000).
func _init() -> void:
	ship_tier = ComponentSpec.Tier.HEAVY
	max_speed = 750.0
	max_omega = 1.0
	max_heat = 400.0
	ship_components = [
		# Layout relative to center (0,0). Forward +X, Right +Y
		{"id": "hull_fwd", "type": "hull", "rect": Rect2(22, -22, 22, 44), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_port", "type": "hull", "rect": Rect2(-22, -22, 44, 16), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(-22, 6, 44, 16), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_aft", "type": "hull", "rect": Rect2(-44, -22, 22, 44), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		# Reactor armor: a dedicated armored core wrapping the reactors.
		{"id": "hull_core", "type": "hull", "rect": Rect2(-13, -9, 26, 18), "health": 1600.0, "max_health": 1600.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Two redundant reactors, nested inside hull_core's footprint.
		{"id": "reactor_fwd", "type": "reactor", "rect": Rect2(-7, -6, 14, 12), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 300.0},
		{"id": "reactor_aft", "type": "reactor", "rect": Rect2(-12, -5, 12, 10), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 250.0},

		{"id": "engine_main", "type": "engines", "rect": Rect2(-48, -5, 10, 36), "health": 500.0, "max_health": 500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 100.0, "thrust_rating": 5900.0, "torque_rating": 16000.0},

		{"id": "comms_array", "type": "comms", "rect": Rect2(0, -3, 6, 6), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 60000.0},

		# Sensors: a frigate-class suite, reusing the frigate's tuned values
		# (especially omni_short_hi_res's PD fire-control tuning) rather than
		# re-deriving them.
		{"id": "dir_high_res", "type": "sensors", "rect": Rect2(44, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 20.0, "em_emission": 20.0, "switchable": true, "powered_on": true,
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
			"sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 36000, "refresh_interval": 0.0, "timer": 0.0, "heading": 0.0},
		{"id": "passive_em", "type": "sensors", "rect": Rect2(-5, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"sensor_type": "passive_em", "active": true, "range": 80000.0, "arc_width": TAU, "num_bins": 360, "refresh_interval": 1.0, "timer": 0.0, "heading": 0.0},
		{"id": "omni_collision", "type": "sensors", "rect": Rect2(0, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"sensor_type": "active", "active": true, "range": 1500.0, "arc_width": TAU, "num_bins": 8, "refresh_interval": 0.1, "timer": 0.0, "heading": 0.0},

		# Weapons: full broadside suite.
		{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(44, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 5000.0, "damage": 600.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_tube_1", "type": "weapons", "rect": Rect2(44, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_tube_2", "type": "weapons", "rect": Rect2(44, -10, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": 0.0, "arc_width": PI / 3.0},

		{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(25, -27, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-30, -27, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(15, -42, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(2, -42, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-11, -42, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_port_tube_4", "type": "weapons", "rect": Rect2(-24, -42, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},

		{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(25, 22, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-30, 22, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(15, 27, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(2, 27, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-11, 27, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_tube_4", "type": "weapons", "rect": Rect2(-24, 27, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},

		# Rear point-defense laser -- fast, fills the frigate's aft blind spot.
		{"id": "hp_aft_pd", "type": "weapons", "rect": Rect2(-49, -2.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 0.5, "range": 3000.0, "damage": 300.0, "heading": PI, "arc_width": PI / 2.0},
	]
	super()
