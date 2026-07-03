extends Ship
class_name MediumStation

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	
	ship_components = [
		# --- Central Hub (X=-50..50, Y=-20..20) ---
		{
			"id": "docking_port_1",
			"type": "docking_port",
			"rect": Rect2(-50, -20, 100, 40),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		
		# --- Forward Arm (X=50..130, Y=-20..20) ---
		{
			"id": "comms_fwd",
			"type": "comms",
			"rect": Rect2(50, -20, 20, 40),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0,
			"range": 200000.0,
			"transponder_custom_name": "Medium Deep Space Station",
		},
		{
			"id": "reactor_fwd",
			"type": "reactor",
			"rect": Rect2(70, -20, 40, 40),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
			"power_rating": 800.0,
		},
		{
			"id": "sensor_fwd",
			"type": "sensors",
			"rect": Rect2(110, -20, 20, 40),
			"health": 1000.0, "max_health": 1000.0, "density": 20.0,
			"sensor_type": "omni",
			"range": 30000.0,
			"arc_width": TAU,
			"num_bins": 72,
			"refresh_interval": 1.0,
			"heading": 0.0,
		},

		# Dedicated short-range point-defense tracker (see small_station.gd). The
		# 72-bin / 1.0s search dishes are far too coarse and slow to aim the PD
		# turrets. One grade below the frigate's PD sensor (720 bins / 0.25s vs
		# 3600 / 0.1) -- an outpost, not a war station. Range-bounded to 5000.
		{
			"id": "omni_short_pd",
			"type": "sensors",
			"rect": Rect2(70, -50, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"base_em_emission": 5.0, "em_emission": 5.0,
			"sensor_type": "active", "active": true,
			"range": 5000.0, "arc_width": TAU, "num_bins": 720, "refresh_interval": 0.25,
			"timer": 0.0, "heading": 0.0,
		},

		# --- Aft Arm (X=-130..-50, Y=-20..20) ---
		{
			"id": "comms_aft",
			"type": "comms",
			"rect": Rect2(-70, -20, 20, 40),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0,
			"range": 200000.0,
		},
		{
			"id": "reactor_aft",
			"type": "reactor",
			"rect": Rect2(-110, -20, 40, 40),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
			"power_rating": 800.0,
		},
		{
			"id": "sensor_aft",
			"type": "sensors",
			"rect": Rect2(-130, -20, 20, 40),
			"health": 1000.0, "max_health": 1000.0, "density": 20.0,
			"sensor_type": "omni",
			"range": 30000.0,
			"arc_width": TAU,
			"num_bins": 72,
			"refresh_interval": 1.0,
			"heading": PI,
		},
		
		# --- Port Arm (X=-50..50, Y=-180..-20) ---
		{
			"id": "living_quarters_main",
			"type": "living_quarters",
			"rect": Rect2(-50, -180, 100, 160),
			"health": 12000.0, "max_health": 12000.0, "density": 20.0,
		},
		
		# --- Starboard Arm (X=-50..50, Y=20..180) ---
		{
			"id": "cargo_bay_main",
			"type": "cargo_bay",
			"rect": Rect2(-50, 20, 100, 160),
			"health": 12000.0, "max_health": 12000.0, "density": 20.0,
		},
		
		# --- Weapons ---
		# Forward
		{
			"id": "pd_fwd",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(140, -30, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"damage": 800.0, "range": 5000.0, "cooldown_max": 0.4,
			"heading": 0.0, "arc_width": PI / 2.0,
		},
		{
			"id": "missile_fwd",
			"type": "weapons", "weapon_type": "missile",
			"rect": Rect2(140, 10, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"ammo": 40, "range": 50000.0, "cooldown_max": 4.0,
			"heading": 0.0, "arc_width": PI / 2.0,
		},
		# Aft
		{
			"id": "pd_aft",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-160, -30, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"damage": 800.0, "range": 5000.0, "cooldown_max": 0.4,
			"heading": PI, "arc_width": PI / 2.0,
		},
		{
			"id": "missile_aft",
			"type": "weapons", "weapon_type": "missile",
			"rect": Rect2(-160, 10, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"ammo": 40, "range": 50000.0, "cooldown_max": 4.0,
			"heading": PI, "arc_width": PI / 2.0,
		},
		# Port
		{
			"id": "pd_port",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-30, -210, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"damage": 800.0, "range": 5000.0, "cooldown_max": 0.4,
			"heading": -PI / 2.0, "arc_width": PI / 2.0,
		},
		{
			"id": "missile_port",
			"type": "weapons", "weapon_type": "missile",
			"rect": Rect2(10, -210, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"ammo": 40, "range": 50000.0, "cooldown_max": 4.0,
			"heading": -PI / 2.0, "arc_width": PI / 2.0,
		},
		# Starboard
		{
			"id": "pd_stbd",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-30, 190, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"damage": 800.0, "range": 5000.0, "cooldown_max": 0.4,
			"heading": PI / 2.0, "arc_width": PI / 2.0,
		},
		{
			"id": "missile_stbd",
			"type": "weapons", "weapon_type": "missile",
			"rect": Rect2(10, 190, 20, 20),
			"health": 800.0, "max_health": 800.0, "density": 20.0,
			"ammo": 40, "range": 50000.0, "cooldown_max": 4.0,
			"heading": PI / 2.0, "arc_width": PI / 2.0,
		},
		
		# --- Inner Corner RCS (Armpits) ---
		{
			"id": "rcs_fwd_port",
			"type": "rcs",
			"rect": Rect2(50, -30, 10, 10),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0, "thrust_rating": 25000.0, "torque_rating": 25000.0,
		},
		{
			"id": "rcs_fwd_stbd",
			"type": "rcs",
			"rect": Rect2(50, 20, 10, 10),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0, "thrust_rating": 25000.0, "torque_rating": 25000.0,
		},
		{
			"id": "rcs_aft_port",
			"type": "rcs",
			"rect": Rect2(-60, -30, 10, 10),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0, "thrust_rating": 25000.0, "torque_rating": 25000.0,
		},
		{
			"id": "rcs_aft_stbd",
			"type": "rcs",
			"rect": Rect2(-60, 20, 10, 10),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0, "thrust_rating": 25000.0, "torque_rating": 25000.0,
		},
		
		# --- Hull Armor Caps (Wrapping the extremities) ---
		{
			"id": "hull_fwd_cap", "type": "hull",
			"rect": Rect2(130, -30, 10, 60),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_cap", "type": "hull",
			"rect": Rect2(-140, -30, 10, 60),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		{
			"id": "hull_port_cap", "type": "hull",
			"rect": Rect2(-60, -190, 120, 10),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_cap", "type": "hull",
			"rect": Rect2(-60, 180, 120, 10),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		
		# --- Hull Armor Flanks (Sides of the arms) ---
		{
			"id": "hull_fwd_port_flank", "type": "hull",
			"rect": Rect2(60, -30, 70, 10),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_fwd_stbd_flank", "type": "hull",
			"rect": Rect2(60, 20, 70, 10),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_port_flank", "type": "hull",
			"rect": Rect2(-130, -30, 70, 10),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_stbd_flank", "type": "hull",
			"rect": Rect2(-130, 20, 70, 10),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_port_fwd_flank", "type": "hull",
			"rect": Rect2(50, -180, 10, 150),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_port_aft_flank", "type": "hull",
			"rect": Rect2(-60, -180, 10, 150),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_fwd_flank", "type": "hull",
			"rect": Rect2(50, 30, 10, 150),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_aft_flank", "type": "hull",
			"rect": Rect2(-60, 30, 10, 150),
			"health": 3000.0, "max_health": 3000.0, "density": 20.0,
		},
	]
	super()

# One berth below the station, clear of the hull collision circle (~210u) so
# force-capture doesn't fight the physics body. Nose faces the station.
func get_berths() -> Array:
	return [{"pos": Vector2(0, 340), "heading": -PI / 2.0}]
