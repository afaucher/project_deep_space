import re

with open('scripts/weapons_panel.gd', 'r') as f:
    content = f.read()

target_logic = """				var btn = weapon_buttons[w_id]["btn"]
				
				var is_in_arc = false
				var is_in_range = false
				var has_target = false
				
				if selected_contact_id != "" and current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
					has_target = true
					var c = current_state["contacts"][selected_contact_id]
					var c_pos = c.get("pos", Vector2.ZERO)
					var s_pos = current_state.get("pos", Vector2.ZERO)
					var s_rot = current_state.get("rot", 0.0)
					
					var w_heading = w_info.get("heading", 0.0)
					var arc_w = w_info.get("arc_width", 6.28318) # TAU
					var w_range = w_info.get("range", 999999.0)
					
					var dist = s_pos.distance_to(c_pos)
					is_in_range = (dist <= w_range)
					
					var angle_to = s_pos.angle_to_point(c_pos)
					var weapon_global_heading = s_rot + w_heading
					var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)
					
					is_in_arc = (abs(rel_angle) <= arc_w / 2.0)
					
				var can_fire = (ammo > 0 and cd <= 0.0 and has_target and is_in_arc)
				if w_info.get("type", "") == "laser":
					can_fire = can_fire and is_in_range
					
				btn.disabled = not can_fire
				
				if not has_target:
					btn.text = "NO LOCK"
				elif ammo <= 0:
					btn.text = "EMPTY"
				elif cd > 0.0:
					btn.text = "COOLDOWN"
				elif not is_in_arc:
					btn.text = "OUT OF ARC"
				elif w_info.get("type", "") == "laser" and not is_in_range:
					btn.text = "OUT OF RANGE"
				else:
					btn.text = "FIRE"
					
	if selected_contact_id == "":"""

# Replace the specific block of logic for btn update
old_logic_pattern = r'				var btn = weapon_buttons\[w_id\]\["btn"\]\n				btn\.disabled = \(ammo <= 0 or cd > 0\.0 or selected_contact_id == ""\)\n				if selected_contact_id == "":\n					btn\.text = "NO LOCK"\n				else:\n					btn\.text = "FIRE"\n					\n	if selected_contact_id == "":'

content = re.sub(old_logic_pattern, target_logic, content, flags=re.DOTALL)

with open('scripts/weapons_panel.gd', 'w') as f:
    f.write(content)
