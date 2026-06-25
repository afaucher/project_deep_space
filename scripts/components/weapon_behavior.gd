class_name WeaponBehavior

# Owns ALL preconditions for firing a weapon component (ammo, cooldown, power,
# arc) — Ship.fire_weapon()/_process_point_defense() never check these themselves,
# they delegate entirely to whichever behavior handles this component's weapon_type.
func can_fire(ship: Ship, comp: Dictionary, target_contact_id: String) -> bool:
	if comp["ammo"] <= 0 or comp["cooldown"] > 0.0:
		return false
	if not ship.is_component_powered(comp["id"]):
		return false
	if ship.active_contacts.has(target_contact_id):
		var real_target_pos = ship.active_contacts[target_contact_id]["pos"]
		var angle_to = (real_target_pos - ship.position).angle()
		var weapon_global_heading = ship.rotation + comp["heading"]
		var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)
		if abs(rel_angle) > comp["arc_width"] / 2.0:
			return false
	return true

func execute_fire(ship: Ship, comp: Dictionary, target_pos: Vector2, target_contact_id: String) -> void:
	pass # override per class

func tick(ship: Ship, comp: Dictionary, delta: float) -> void:
	# Default: no lifecycle pulse, em_emission is just the authored baseline.
	# Override per class to add charge-up/fire-pulse decay (see LaserBehavior).
	comp["em_emission"] = comp.get("base_em_emission", 0.0)

func _consume_default(comp: Dictionary) -> void:
	comp["ammo"] -= 1
	comp["cooldown"] = comp["cooldown_max"]
