extends "res://addons/beehave/nodes/leaves/action.gd"

# M12 fire_opportunity: the headline fix of this slice. Enumerate EVERY weapon the hull
# carries and attempt to fire each at the current target. Ship.fire_weapon() already
# gates on ammo / cooldown / power / firing arc through the weapon behavior, so this
# naturally fires exactly the weapons that currently bear -- forward laser AND forward
# missile AND any battery that happens to be aligned -- instead of the legacy single
# hardcoded hp_fwd_missile fired once every 10 seconds.
#
# It is capability-driven (reasons over get_components_by_type, never hardpoint ids), so
# the same leaf works on any hull. Fire discipline / metering (don't dump the whole
# magazine, save a massed volley) arrives with weapon groups in M12b.
func tick(actor: Node, blackboard) -> int:
	if not blackboard.has_value("target_id"):
		return SUCCESS

	var target_id = blackboard.get_value("target_id")
	var target_pos = blackboard.get_value("target_pos")
	for w in actor.get_components_by_type("weapons"):
		actor.fire_weapon(w["id"], target_pos, target_id)
	return SUCCESS
