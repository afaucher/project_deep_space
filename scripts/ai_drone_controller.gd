extends Node
class_name AIDroneController

var ship: RigidBody2D
var target_id: String = ""
var fire_timer: float = 0.0

func _ready() -> void:
	ship = get_parent()
	if not ship or not ship.has_method("apply_control_input"):
		set_physics_process(false)
		push_error("AIDroneController must be a child of a Ship")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	if ship.is_dead: return
	
	# Find target
	var best_dist = 999999.0
	target_id = ""
	
	for c_id in ship.active_contacts:
		var contact = ship.active_contacts[c_id]
		# Only target hostile vessels
		if contact.get("classification", "") != "UNIDENTIFIED VESSEL":
			continue
			
		var dist = ship.position.distance_to(contact["pos"])
		if dist < best_dist:
			best_dist = dist
			target_id = c_id
			
	if target_id == "":
		# Idle
		ship.apply_control_input(0.0, 0.0, ship.rotation, 0, 1)
		return
		
	var target = ship.active_contacts[target_id]
	var target_pos = target["pos"]
	var angle_to_target = (target_pos - ship.position).angle()
	var dist_to_target = ship.position.distance_to(target_pos)
	
	# Point sensor at target
	ship.set_sensor_target(target_id)
	
	var fwd_missile = ship.get_component("hp_fwd_missile")
	var has_ammo = not fwd_missile.is_empty() and fwd_missile["ammo"] > 0
	
	if not has_ammo:
		# Evasive maneuvers
		var time_sec = float(Time.get_ticks_msec()) / 1000.0
		# Steer generally away (angle + PI) with a 45-degree sine wave wobble
		var evasion_angle = wrapf(angle_to_target + PI + sin(time_sec * 2.0) * (PI / 4.0), -PI, PI)
		
		ship.apply_control_input(1.0, 800.0, evasion_angle, 1, 1)
		
		if Engine.get_process_frames() % 120 == 0:
			print("[Drone AI] Target: ", target_id, " | Out of ammo! Evading!")
		return
	
	# Maneuver
	var thrust = 0.0
	var target_vel = 0.0
	if dist_to_target > 10000.0:
		thrust = 1.0
		target_vel = 800.0
	elif dist_to_target < 5000.0:
		thrust = -1.0 # Back away
		target_vel = 200.0
	else:
		thrust = 0.0 # Maintain distance
		target_vel = 0.0
		
	# Steer towards target (s_mode = 1 is auto-steer, l_mode = 1 is flight assist)
	ship.apply_control_input(thrust, target_vel, angle_to_target, 1, 1)
	
	# Combat
	fire_timer -= delta
	
	var rel_angle = abs(wrapf(ship.rotation - angle_to_target, -PI, PI))
	if fire_timer <= 0.0:
		if rel_angle < PI / 8.0: # Pointing roughly at target
			if dist_to_target < 25000.0:
				# Fire a missile
				print("[Drone AI] Firing missile at ", target_id, " (Dist: ", round(dist_to_target), "m)")
				ship.fire_weapon("hp_fwd_missile", target_pos, target_id)
				fire_timer = 10.0 # Wait 10 seconds before firing another
	
	# Debug Logging (every 2 seconds to avoid spam)
	if Engine.get_process_frames() % 120 == 0:
		var targeting_str = "No"
		if rel_angle < PI / 8.0: targeting_str = "Yes (Aiming)"
		elif rel_angle < PI / 4.0: targeting_str = "Almost (Turning)"
		
		print("[Drone AI] Target: ", target_id, " | Dist: ", round(dist_to_target), "m | On Target: ", targeting_str, " | Thrust: ", thrust, " | CD: ", max(0.0, snapped(fire_timer, 0.1)))
