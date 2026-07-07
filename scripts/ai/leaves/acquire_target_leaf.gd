extends "res://addons/beehave/nodes/leaves/action.gd"

# M12 acquire_target: pick the nearest hostile contact and publish it to the blackboard
# for the steer/fire leaves downstream. "Hostile" today means classification
# "UNIDENTIFIED VESSEL" -- the same rule the legacy controller used and the only
# non-friendly bucket the binary classifier produces (INCOMING ORDNANCE is handled by
# the ship's own point defense, not chased as a maneuver target). Returns FAILURE when
# there is nothing to engage so the parent selector falls through to Idle.
func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
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
		if contact.get("classification", "") != "UNIDENTIFIED VESSEL":
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
