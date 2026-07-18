extends "res://addons/beehave/nodes/leaves/action.gd"

const Standing = preload("res://scripts/combat/standing.gd")

# M12 acquire_target: pick the nearest hostile contact and publish it to the blackboard
# for the steer/fire leaves downstream. M48: "hostile" is now the earned, per-observer
# standing judgment (Standing.HOSTILE) rather than the raw classification bucket --
# see implementation_plans/m48_standings_flags_design.md (INCOMING ORDNANCE is handled
# by the ship's own point defense, not chased as a maneuver target). Returns FAILURE
# when there is nothing to engage so the parent selector falls through to Idle.
func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	# M49 -- a held ship doesn't hunt (design_ideas/comms_verbs.md's honored
	# stop); the tree falls through to Idle, and the ship-level throttle
	# override (ship.gd's _physics_process) owns motion regardless.
	if not actor.compelled_stop.is_empty():
		return FAILURE

	var max_weapon_range = 0.0
	for comp in actor.ship_components:
		if comp.get("type") == "weapons" and comp.has("range"):
			max_weapon_range = max(max_weapon_range, comp["range"])
	var engagement_radius = max_weapon_range * 1.5

	var best_id := ""
	var best_dist := INF
	for c_id in actor.active_contacts:
		var contact = actor.active_contacts[c_id]
		if contact.get("standing", "") != Standing.HOSTILE:
			continue
		# M49 -- no leaf targets a compliant stopped ship (comms_verbs.md's
		# honor rule): stopped for customs, arrest, or robbery, it's off the
		# table regardless of standing.
		if contact.get("complied_stop", false):
			continue
		# Fire discipline (Ship.FIRE_STALENESS_MAX): a track nobody has
		# actually seen in a while is a dead-reckoned guess about where a
		# ship USED to be -- never worth acquiring as a weapons target.
		# Without this gate the AI chased and volleyed at ghosts coasting
		# toward CONTACT_TIMEOUT (and, before the relay echo-lock fix, at
		# permanently-frozen ones).
		if contact.get("last_seen_timer", 0.0) > actor.FIRE_STALENESS_MAX:
			continue
		var d = actor.position.distance_to(contact["pos"])
		if d > engagement_radius:
			continue
		if d < best_dist:
			best_dist = d
			best_id = c_id

	if best_id == "":
		return FAILURE

	blackboard.set_value("target_id", best_id)
	blackboard.set_value("target_pos", actor.active_contacts[best_id]["pos"])
	if actor.has_method("set_sensor_target"):
		actor.set_sensor_target(best_id)
	return SUCCESS
