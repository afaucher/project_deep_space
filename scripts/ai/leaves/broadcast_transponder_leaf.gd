extends "res://addons/beehave/nodes/leaves/action.gd"
class_name BroadcastTransponderLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor.has_method("set_transponder_share_location"):
		actor.set_transponder_share_location(true)
		actor.set_transponder_share_name(true)
		actor.set_transponder_active(true)
	return SUCCESS
