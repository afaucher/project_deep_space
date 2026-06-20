import re

with open('scripts/ship.gd', 'r') as f:
    content = f.read()

# Replace weapons dictionary
weapons_replacement = """var weapons = {
	"hp_fwd_laser": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": 0.0, "arc_width": PI / 3.0, "mount_pos": Vector2(30, -7.5) },
	"hp_fwd_missile": { "type": "missile", "ammo": 10, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": 0.0, "arc_width": PI / 3.0, "mount_pos": Vector2(30, 2.5) },
	
	"hp_port_laser_1": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(17.5, -20) },
	"hp_port_tube_1": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(7.5, -30) },
	"hp_port_tube_2": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-2.5, -30) },
	"hp_port_tube_3": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-12.5, -30) },
	"hp_port_laser_2": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-22.5, -20) },

	"hp_stbd_laser_1": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(17.5, 15) },
	"hp_stbd_tube_1": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(7.5, 15) },
	"hp_stbd_tube_2": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-2.5, 15) },
	"hp_stbd_tube_3": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-12.5, 15) },
	"hp_stbd_laser_2": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-22.5, 15) }
}"""

# Replace ship_components array
components_replacement = """var ship_components: Array = [
	# Layout relative to center (0,0). Forward +X, Right +Y
	{"id": "hull_fwd", "type": "hull", "rect": Rect2(15, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_aft", "type": "hull", "rect": Rect2(-30, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	
	{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 200.0, "max_health": 200.0, "density": 0.9, "heat": 0.0, "em_emission": 0.0},
	{"id": "engine_main", "type": "engines", "rect": Rect2(-35, -10, 5, 20), "health": 300.0, "max_health": 300.0, "density": 0.7, "heat": 0.0, "em_emission": 0.0},
	
	{"id": "hp_sensor_fwd", "type": "sensors", "rect": Rect2(30, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 0.4, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_sensor_omni", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 0.4, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(30, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(30, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(17.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(7.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-2.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-12.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-22.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(17.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(7.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-2.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-12.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-22.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0}
]"""

# Substitute weapons dict
content = re.sub(r'var weapons = \{[\s\S]*?\n\}', weapons_replacement, content, count=1)

# Substitute ship_components array
content = re.sub(r'var ship_components: Array = \[[\s\S]*?\n\]', components_replacement, content, count=1)

# Fix fire_weapon logic
fire_weapon_replacement = """@rpc("any_peer", "call_local")
func fire_weapon(weapon_id: String, target_pos: Vector2, target_contact_id: String) -> void:
	if not is_multiplayer_authority():
		return # Only host executes this
		
	# Verify client owns this ship
	if multiplayer.get_remote_sender_id() != int(name.replace("Ship_", "")) and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
			
	if not weapons.has(weapon_id): return
	if weapons[weapon_id]["ammo"] <= 0: return
	if weapons[weapon_id]["cooldown"] > 0: return
	
	# Verify hardpoint health
	var component_health = 0.0
	for comp in ship_components:
		if comp["id"] == weapon_id:
			component_health = comp["health"]
			break
	if component_health <= 0.0: return # Hardpoint destroyed!
	
	var weapon_data = weapons[weapon_id]
	var w_type = weapon_data["type"]
	
	# Validate target within arc
	if active_contacts.has(target_contact_id):
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
		# Hitscan weapons also check range
		if w_type == "laser":
			var dist = position.distance_to(real_target_pos)
			if dist > weapon_data["range"]: return
			
		var angle_to = position.angle_to_point(real_target_pos)
		
		# Weapon heading is relative to ship rotation
		var weapon_global_heading = rotation + weapon_data["heading"]
		var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)
		
		if abs(rel_angle) > weapon_data["arc_width"] / 2.0: return
	elif w_type == "laser":
		return # Lasers require target lock for hitscan logic currently

	# Consume ammo and set cooldown
	weapons[weapon_id]["ammo"] -= 1
	weapons[weapon_id]["cooldown"] = weapon_data["cooldown_max"]
	
	var global_mount_pos = position + weapon_data["mount_pos"].rotated(rotation)
	var weapon_launch_angle = rotation + weapon_data["heading"]
	
	if w_type == "laser":
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_laser.play()
			
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
		# Find the actual body
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 50.0
		query.shape = shape
		query.transform = Transform2D(0, real_target_pos)
		
		var results = space_state.intersect_shape(query, 32)
		for res in results:
			var body = res["collider"]
			if body == self: continue
			if body.has_method("take_damage"):
				# Ray hits target - simulate from global_mount_pos to real_target_pos
				var hit_dir = (real_target_pos - global_mount_pos).normalized()
				body.take_damage(weapon_data["damage"], real_target_pos, hit_dir)
			elif body.has_method("get_signature"):
				body.queue_free()
				
	elif w_type == "missile":
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_missile.play()
			
		var main_node = get_tree().current_scene
		if not is_instance_valid(main_node): return
		
		var Projectile = load("res://scripts/projectile.gd")
		var proj = Projectile.new()
		
		var target_profile = {}
		if active_contacts.has(target_contact_id):
			target_profile = active_contacts[target_contact_id].duplicate()
			
		proj.fire(
			self,
			global_mount_pos,
			linear_velocity,
			weapon_launch_angle,
			target_profile
		)
		main_node.add_child(proj, true)"""

content = re.sub(r'@rpc\("any_peer", "call_local"\)\nfunc fire_weapon.*?main_node\.add_child\(proj, true\)', fire_weapon_replacement, content, flags=re.DOTALL)

with open('scripts/ship.gd', 'w') as f:
    f.write(content)
