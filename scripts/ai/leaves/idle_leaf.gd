extends "res://addons/beehave/nodes/leaves/action.gd"

# M12 idle: no target in range -- coast and hold current heading. The selector reaches
# this only when acquire_target fails. Patrol / station-keeping behavior is M12e.
func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return SUCCESS
	actor.apply_control_input(0.0, 0.0, actor.rotation, 0, 1)
	return SUCCESS
