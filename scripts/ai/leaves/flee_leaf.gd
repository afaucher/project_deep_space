extends "res://addons/beehave/nodes/leaves/action.gd"

# M12c disengage action: run from the nearest hostile contact at full burn, nose pointed
# away so thrust drives the ship clear. If nothing hostile is in range there is nothing
# to flee, so just coast. Reached only when should_disengage has fired, so the ship is
# deliberately NOT firing here -- it is breaking off, not fighting. M48: "hostile" is
# the earned Standing.HOSTILE judgment, not raw classification -- flee from the nearest
# contact THIS ship has actually judged hostile.
const Steering = preload("res://scripts/ai/steering.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const FLEE_SPEED := 900.0

func tick(actor: Node, _blackboard) -> int:
	# D50 -- the LAST candidate above JobRunner in build_pirate. `runner lag 387`
	# proves the tree does not reach the runner for ~6.45s during a failed
	# robbery; OutlawResponseLeaf was cleared by direct count (flee 0, held 0),
	# so the Disengage sequence is all that is left. Counted here rather than
	# reasoned about, because six earlier eliminations by reading were wrong.
	actor.set("flee_leaf_ticks", int(actor.get("flee_leaf_ticks")) + 1)
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
		if c.get("standing", "") != Standing.HOSTILE:
			continue
		# Same wreck gate as acquire_target_leaf: a dead ship's sticky HOSTILE
		# standing never clears, but there is nothing to flee from a hulk.
		if c.get("classification", "") == "WRECKAGE":
			continue
		var d = actor.position.distance_to(c["pos"])
		if d < best_dist:
			best_dist = d
			best = c["pos"]
	return best
