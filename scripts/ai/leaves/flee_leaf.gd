extends "res://addons/beehave/nodes/leaves/action.gd"

# M12c disengage action: run from the nearest hostile contact at full burn, nose pointed
# away so thrust drives the ship clear. If nothing hostile is in range there is nothing
# to flee, so just coast. Reached only when should_disengage has fired, so the ship is
# deliberately NOT firing here -- it is breaking off, not fighting.
const Steering = preload("res://scripts/ai/steering.gd")
const FLEE_SPEED := 900.0

func tick(actor: Node, _blackboard) -> int:
	var threat_pos = _nearest_hostile_pos(actor)
	if threat_pos == null:
		actor.apply_control_input(0.0, 0.0, actor.rotation, 1, 0) # nothing to flee; coast
		return SUCCESS
	# Run from the threat, but dodge rather than flee straight into an obstacle.
	var away_dir: Vector2 = (actor.position - threat_pos).normalized()
	var avoided: Vector2 = Steering.steer(actor, away_dir, null)
	actor.apply_control_input(0.0, FLEE_SPEED, avoided.angle(), 1, 1) # nose away, full velocity
	return SUCCESS

func _nearest_hostile_pos(actor: Node):
	var best = null
	var best_dist = INF
	for c_id in actor.active_contacts:
		var c = actor.active_contacts[c_id]
		if c.get("classification", "") != "UNIDENTIFIED VESSEL":
			continue
		var d = actor.position.distance_to(c["pos"])
		if d < best_dist:
			best_dist = d
			best = c["pos"]
	return best
