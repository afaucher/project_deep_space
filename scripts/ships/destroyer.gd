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
		# --- AFT SECTION (-60 to -50) ---
		{"id": "engine_main", "type": "engines", "rect": Rect2(-60, -10, 10, 20), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 100.0, "thrust_rating": 15000.0, "torque_rating": 25000.0},
		{"id": "hp_aft_pd", "type": "weapons", "rect": Rect2(-60, -15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 0.5, "range": 5000.0, "damage": 1000.0, "heading": PI, "arc_width": PI / 2.0},
		{"id": "hull_aft_port_1", "type": "hull", "rect": Rect2(-55, -25, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_aft_port_2", "type": "hull", "rect": Rect2(-55, -15, 5, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_aft_stbd", "type": "hull", "rect": Rect2(-55, 10, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- AFT MID SECTION (-50 to -40) ---
		{"id": "hull_aft_mid_port", "type": "hull", "rect": Rect2(-50, -25, 10, 25), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_aft_mid_stbd", "type": "hull", "rect": Rect2(-50, 0, 10, 25), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- AFT REACTOR (-40 to -30) ---
		{"id": "reactor_aft", "type": "reactor", "rect": Rect2(-40, -6, 10, 12), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 250.0},
		{"id": "hull_reactor_aft_port", "type": "hull", "rect": Rect2(-40, -25, 10, 19), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_reactor_aft_stbd", "type": "hull", "rect": Rect2(-40, 6, 10, 19), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- ZIPPER SECTION (-30 to +20) ---
		# Z1 (-30 to -25)
		{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(-30, -25, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_stbd_z1", "type": "hull", "rect": Rect2(-30, 10, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Z2 (-25 to -20)
		{"id": "hull_port_z2", "type": "hull", "rect": Rect2(-25, -25, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(-25, 10, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},

		# Z3 (-20 to -15)
		{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-20, -25, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_stbd_z3", "type": "hull", "rect": Rect2(-20, 10, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Z4 (-15 to -10)
		{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(-15, -25, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 1000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_port_inner_z4", "type": "hull", "rect": Rect2(-15, -20, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-15, 10, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},

		# Z5 (-10 to -5)
		{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-10, -25, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(-10, 20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 1000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_stbd_inner_z5", "type": "hull", "rect": Rect2(-10, 10, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Z6 (-5 to 0)
		{"id": "hull_port_z6", "type": "hull", "rect": Rect2(-5, -25, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-5, 10, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},

		# Z7 (0 to 5)
		{"id": "hp_port_tube_4", "type": "weapons", "rect": Rect2(0, -25, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_stbd_z7", "type": "hull", "rect": Rect2(0, 10, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Z8 (5 to 10)
		{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(5, -25, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 1000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_port_inner_z8", "type": "hull", "rect": Rect2(5, -20, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_stbd_tube_4", "type": "weapons", "rect": Rect2(5, 10, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},

		# Z9 (10 to 15)
		{"id": "hull_port_z9", "type": "hull", "rect": Rect2(10, -25, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(10, 20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 1000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
		{"id": "hull_stbd_inner_z9", "type": "hull", "rect": Rect2(10, 10, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# Z10 (15 to 20)
		{"id": "hull_port_z10", "type": "hull", "rect": Rect2(15, -25, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd_z10", "type": "hull", "rect": Rect2(15, 10, 5, 15), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- SPINE SECTION (-30 to +20, Y=-10 to 10) ---
		{"id": "hull_spine_aft", "type": "hull", "rect": Rect2(-30, -10, 15, 20), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_spine_top1", "type": "hull", "rect": Rect2(-15, -10, 15, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "omni_main", "type": "sensors", "rect": Rect2(-15, -5, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0, "switchable": true, "powered_on": true, "sensor_type": "active", "active": true, "range": 40000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 2.0, "timer": 0.0, "heading": 0.0},
		{"id": "passive_em", "type": "sensors", "rect": Rect2(-10, -5, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "sensor_type": "passive_em", "active": true, "range": 80000.0, "arc_width": TAU, "num_bins": 360, "refresh_interval": 1.0, "timer": 0.0, "heading": 0.0},
		{"id": "hull_spine_fill1", "type": "hull", "rect": Rect2(-5, -5, 5, 10), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "omni_short_hi_res", "type": "sensors", "rect": Rect2(-15, 0, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 5.0, "em_emission": 5.0, "switchable": true, "powered_on": true, "sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 36000, "refresh_interval": 0.0, "timer": 0.0, "heading": 0.0},
		{"id": "omni_collision", "type": "sensors", "rect": Rect2(-10, 0, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "sensor_type": "active", "active": true, "range": 1500.0, "arc_width": TAU, "num_bins": 8, "refresh_interval": 0.1, "timer": 0.0, "heading": 0.0},
		{"id": "hull_spine_bot1", "type": "hull", "rect": Rect2(-15, 5, 15, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		
		{"id": "hull_spine_top2", "type": "hull", "rect": Rect2(0, -10, 20, 7), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "comms_array", "type": "comms", "rect": Rect2(0, -3, 6, 6), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 60000.0},
		{"id": "hull_spine_mid1", "type": "hull", "rect": Rect2(6, -3, 14, 0.5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "dir_high_res", "type": "sensors", "rect": Rect2(6, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 20.0, "em_emission": 20.0, "switchable": true, "powered_on": true, "sensor_type": "active", "active": true, "range": 40000.0, "arc_width": PI / 6.0, "num_bins": 30, "refresh_interval": 0.5, "timer": 0.0, "heading": 0.0},
		{"id": "hull_spine_mid3", "type": "hull", "rect": Rect2(11, -2.5, 9, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_spine_mid2", "type": "hull", "rect": Rect2(6, 2.5, 14, 0.5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_spine_bot2", "type": "hull", "rect": Rect2(0, 3, 20, 7), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- FWD REACTOR (20 to 30) ---
		{"id": "reactor_fwd", "type": "reactor", "rect": Rect2(20, -6, 10, 12), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 300.0},
		{"id": "hull_reactor_fwd_port", "type": "hull", "rect": Rect2(20, -25, 10, 19), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_reactor_fwd_stbd", "type": "hull", "rect": Rect2(20, 6, 10, 19), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},

		# --- BOW SECTION (30 to 60) ---
		{"id": "hull_bow_main", "type": "hull", "rect": Rect2(30, -25, 15, 50), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hp_fwd_tube_1", "type": "weapons", "rect": Rect2(45, -12.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_tube_2", "type": "weapons", "rect": Rect2(45, 7.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 30000.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(55, -2.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 5000.0, "damage": 1000.0, "heading": 0.0, "arc_width": PI / 3.0},
		{"id": "hull_bow_port", "type": "hull", "rect": Rect2(45, -25, 10, 12.5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_bow_mid1", "type": "hull", "rect": Rect2(45, -7.5, 15, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_bow_laser_back", "type": "hull", "rect": Rect2(45, -2.5, 10, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_bow_mid2", "type": "hull", "rect": Rect2(45, 2.5, 15, 5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_bow_stbd", "type": "hull", "rect": Rect2(45, 12.5, 10, 12.5), "health": 1500.0, "max_health": 1500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	]
	super()
