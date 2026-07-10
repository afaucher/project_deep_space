extends Ship
class_name MediumStation

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	
	ship_components = [
		# --- Central Hub (X=-50..50, Y=-20..20) ---
		{
			"id": "hub_1",
			"type": "living_quarters",
			"rect": Rect2(-50, -20, 100, 40),
			"health": 6000.0, "max_health": 6000.0, "density": 20.0,
		},
		
		# --- Forward Arm (X=50..130, Y=-20..20) ---
		{
			"id": "comms_fwd",
			"type": "comms",
			"rect": Rect2(50, -20, 20, 40),
			"health": 1500.0, "max_health": 1500.0, "density": 20.0,
			"range": 30000.0,
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
			"range": 30000.0,
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
		
		# --- Docking Ports ---
		{
			"id": "dock_main", "type": "docking_port",
			"rect": Rect2(-10, 190, 20, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
			"heading": PI / 2.0, "has_servo": true,
		},
		# M40 -- second berth ("Fold-in -- a second Ironhold berth",
		# implementation_plans/m39_m44_homefront_roadmap.md M40 section). Two
		# NPC cargo shuttles loop through Ironhold and the player also wants to
		# dock; home base must never bounce the player for a berth a shuttle is
		# occasionally sitting in. Mirrored onto the PORT hull face (opposite
		# dock_main's STARBOARD face): edge-adjacent to hull_port_cap
		# (Rect2(-60,-190,120,10) -- shares the y=-190 edge) the same way
		# dock_main is edge-adjacent to hull_stbd_cap, so the layout stays
		# connected without touching any other component's rect.
		{
			"id": "dock_aux", "type": "docking_port",
			"rect": Rect2(-10, -200, 20, 10),
			"health": 2000.0, "max_health": 2000.0, "density": 20.0,
			"heading": -PI / 2.0, "has_servo": true,
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
	ship_name = "Medium Deep Space Station"

	# M31 -- Ironhold is the controlled hub (AUTOMATED authority style, see
	# implementation_plans/m31_m36_port_authority_roadmap.md). Radius picked to
	# comfortably contain the docking approach: the berth sits at 340u and
	# DockingBay's default capture_radius is 5000u (docking_bay.gd), so 8000u
	# gives a couple thousand units of clearance beyond the capture radius for
	# the hail-and-request approach before a ship is even in range to dock --
	# well outside the ~210u hull collision circle. M33 -- `style` is a new
	# top-level key (NOT inside `rules`, which is reserved for M35's rule
	# dispatch): drives the port-control NPC's name + dialogue flavor +
	# reliability (see scripts/port/port_control.gd).
	# M35 -- `rules` is data read by PortRules' rule->handler dispatch
	# (scripts/port/port_rules.gd): `docking_permission_required` is a pure
	# surfacing flag (M32 already enforces the gate unconditionally at any
	# controlled station -- this key only drives the crossing-banner text, see
	# PortRules._docking_permission_summary); `speed_advisory` is the u/s
	# threshold above which the helm's speed readout goes amber while inside
	# this zone (warn-only, no thrust clamp -- see helm_panel.gd).
	port_zone = {
		"radius": 8000.0,
		"authority": "Ironhold Control",
		"style": PortControl.STYLE_AUTOMATED,
		"rules": {
			"docking_permission_required": true,
			"speed_advisory": 200.0,
		},
	}

	# M33 -- the port-control NPC, discoverable via the same transponder path
	# as any other NPC (Ship.get_active_transponder_data() -> comms_panel's
	# NPC list). PUBLIC tier: always visible in range, no vouching needed to
	# hail port control. One shared dialogue resource branches on the
	# station's style itself (see dialogue/port_control.dialogue) -- keeping
	# exactly one small dialogue tree per the roadmap's "wiring, not writing a
	# script" instruction.
	var port_control_npc := NPCProfile.new()
	port_control_npc.character_name = PortControl.get_controller_name(self)
	port_control_npc.faction = port_zone["authority"]
	port_control_npc.tier = NPCProfile.Tier.PUBLIC
	port_control_npc.default_dialogue = load("res://dialogue/port_control.dialogue")
	available_npcs.append(port_control_npc)


