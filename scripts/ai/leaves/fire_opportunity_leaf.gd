extends "res://addons/beehave/nodes/leaves/action.gd"

# M12 fire_opportunity: fire at the current target, capability-driven (reasons over
# get_weapon_groups / get_component, never hardpoint ids), so the same leaf works on any
# hull. Per-type fire discipline (M12a):
#
#   * Lasers fire AT WILL -- hitscan and instant, there is nothing for point defense to
#     intercept, so there is no benefit to holding them.
#   * Missile tubes fire as a SYNCHRONIZED VOLLEY per group: held until every live tube
#     in the group is off cooldown (is_group_volley_ready), then all loosed in the same
#     tick so they saturate PD. Damaged / empty / disabled tubes are not waited on.
#
# At nose-on the forward group has a single tube, so the volley is trivially "ready" and
# fires immediately; the holding behavior only bites once a multi-tube broadside is
# brought to bear (M12c orientation).
func tick(actor: Node, blackboard) -> int:
	if not blackboard.has_value("target_id"):
		return SUCCESS

	var target_id = blackboard.get_value("target_id")
	var target_pos = blackboard.get_value("target_pos")

	# Trigger-side fire discipline (belt to acquire_target_leaf's suspenders --
	# see Ship.FIRE_STALENESS_MAX): even with a published blackboard target,
	# hold fire if its track has vanished or gone stale since acquisition.
	# Never spend a laser's heat, let alone a synchronized missile volley, on
	# a dead-reckoned ghost.
	var contact: Dictionary = actor.active_contacts.get(target_id, {})
	if contact.is_empty() or contact.get("last_seen_timer", 0.0) > actor.FIRE_STALENESS_MAX:
		return SUCCESS

	var groups = actor.get_weapon_groups()
	for gid in groups:
		var ids = groups[gid]
		var has_missiles := false
		for wid in ids:
			if actor.get_component(wid)["weapon_type"] == "missile":
				has_missiles = true
			else:
				# lasers (and any non-missile type): fire at will
				actor.fire_weapon(wid, target_pos, target_id)
		# Missile volley: only when the whole live battery is synced and ready.
		if has_missiles and actor.is_group_volley_ready(gid, "missile"):
			var dist = actor.position.distance_to(target_pos)
			for wid in ids:
				var comp = actor.get_component(wid)
				if comp["weapon_type"] == "missile":
					if dist <= comp["range"]:
						actor.fire_weapon(wid, target_pos, target_id)
	return SUCCESS
