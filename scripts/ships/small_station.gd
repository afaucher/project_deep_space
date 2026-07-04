extends Ship
class_name SmallStation

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	
	ship_components = [
		{
			"id": "comms_1",
			"type": "comms",
			"rect": Rect2(-20, -20, 40, 40),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0,
			"range": 30000.0,
		},
		
		# --- Forward Arm (X=20..60, Y=-20..20) ---
		{
			"id": "reactor_1",
			"type": "reactor",
			"rect": Rect2(20, -20, 40, 40),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
			"power_rating": 500.0,
		},
		
		# --- Aft Arm (X=-60..-20, Y=-20..20) ---
		{
			"id": "sensors_1",
			"type": "sensors",
			"rect": Rect2(-60, -20, 40, 40),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0,
			"sensor_type": "omni",
			"range": 20000.0,
			"arc_width": TAU,
			"num_bins": 36,
			"refresh_interval": 1.0,
			"heading": 0.0,
		},

		# Dedicated short-range point-defense tracker. sensors_1 (36 bins / 1.0s)
		# is a strategic search dish -- far too coarse and slow to aim the four PD
		# turrets, which fire at whatever this feeds them. One grade below the
		# frigate's PD sensor (720 bins / 0.25s vs 3600 / 0.1): this is a civilian
		# outpost, not a dedicated war station (that'd be its own class). Range-
		# bounded to 5000 so the resolution stays a close-in defensive tool.
		{
			"id": "omni_short_pd",
			"type": "sensors",
			"rect": Rect2(30, -40, 10, 10),
			"health": 500.0, "max_health": 500.0, "density": 20.0,
			"base_em_emission": 5.0, "em_emission": 5.0,
			"sensor_type": "active", "active": true,
			"range": 5000.0, "arc_width": TAU, "num_bins": 720, "refresh_interval": 0.25,
			"timer": 0.0, "heading": 0.0,
		},

		# --- Port Arm (X=-20..20, Y=-120..-20) ---
		{
			"id": "living_quarters_1",
			"type": "living_quarters",
			"rect": Rect2(-20, -120, 40, 100),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		
		# --- Starboard Arm (X=-20..20, Y=20..120) ---
		{
			"id": "cargo_bay_1",
			"type": "cargo_bay",
			"rect": Rect2(-20, 20, 40, 100),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		
		# --- Weapons (At the extremities) ---
		{
			"id": "pd_fwd",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(70, -10, 20, 20),
			"health": 500.0, "max_health": 500.0, "density": 20.0,
			"damage": 500.0, "range": 4000.0, "cooldown_max": 0.5,
			"heading": 0.0, "arc_width": PI / 2.0,
		},
		{
			"id": "pd_aft",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-90, -10, 20, 20),
			"health": 500.0, "max_health": 500.0, "density": 20.0,
			"damage": 500.0, "range": 4000.0, "cooldown_max": 0.5,
			"heading": PI, "arc_width": PI / 2.0,
		},
		{
			"id": "pd_port",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-10, -150, 20, 20),
			"health": 500.0, "max_health": 500.0, "density": 20.0,
			"damage": 500.0, "range": 4000.0, "cooldown_max": 0.5,
			"heading": -PI / 2.0, "arc_width": PI / 2.0,
		},
		{
			"id": "pd_stbd",
			"type": "weapons", "weapon_type": "laser",
			"rect": Rect2(-10, 130, 20, 20),
			"health": 500.0, "max_health": 500.0, "density": 20.0,
			"damage": 500.0, "range": 4000.0, "cooldown_max": 0.5,
			"heading": PI / 2.0, "arc_width": PI / 2.0,
		},
		
		# --- Inner Corner RCS (Armpits) ---
		{
			"id": "rcs_fwd_port",
			"type": "rcs",
			"rect": Rect2(20, -30, 10, 10),
			"health": 500.0, "max_health": 500.0, "density": 20.0, "thrust_rating": 10000.0, "torque_rating": 10000.0,
		},
		{
			"id": "rcs_fwd_stbd",
			"type": "rcs",
			"rect": Rect2(20, 20, 10, 10),
			"health": 500.0, "max_health": 500.0, "density": 20.0, "thrust_rating": 10000.0, "torque_rating": 10000.0,
		},
		{
			"id": "rcs_aft_port",
			"type": "rcs",
			"rect": Rect2(-30, -30, 10, 10),
			"health": 500.0, "max_health": 500.0, "density": 20.0, "thrust_rating": 10000.0, "torque_rating": 10000.0,
		},
		{
			"id": "rcs_aft_stbd",
			"type": "rcs",
			"rect": Rect2(-30, 20, 10, 10),
			"health": 500.0, "max_health": 500.0, "density": 20.0, "thrust_rating": 10000.0, "torque_rating": 10000.0,
		},
		
		# --- Hull Armor Caps (Wrapping the extremities) ---
		{
			"id": "hull_fwd_cap", "type": "hull",
			"rect": Rect2(60, -20, 10, 40),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_cap", "type": "hull",
			"rect": Rect2(-70, -20, 10, 40),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		{
			"id": "hull_port_cap", "type": "hull",
			"rect": Rect2(-20, -130, 40, 10),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_cap", "type": "hull",
			"rect": Rect2(-20, 120, 40, 10),
			"health": 4000.0, "max_health": 4000.0, "density": 20.0,
		},
		
		# --- Hull Armor Flanks (Sides of the arms) ---
		{
			"id": "hull_fwd_port_flank", "type": "hull",
			"rect": Rect2(30, -30, 30, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_fwd_stbd_flank", "type": "hull",
			"rect": Rect2(30, 20, 30, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_port_flank", "type": "hull",
			"rect": Rect2(-60, -30, 30, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_aft_stbd_flank", "type": "hull",
			"rect": Rect2(-60, 20, 30, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_port_fwd_flank", "type": "hull",
			"rect": Rect2(20, -120, 10, 90),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_port_aft_flank", "type": "hull",
			"rect": Rect2(-30, -120, 10, 90),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_fwd_flank", "type": "hull",
			"rect": Rect2(20, 30, 10, 90),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
		{
			"id": "hull_stbd_aft_flank", "type": "hull",
			"rect": Rect2(-30, 30, 10, 90),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
		},
	]
	super()
	ship_name = "Small Outpost"

# One berth below the station, clear of the hull collision circle (~150u) so
# force-capture doesn't fight the physics body. Nose faces the station.
func get_berths() -> Array:
	return [{"pos": Vector2(0, 240), "heading": -PI / 2.0}]
