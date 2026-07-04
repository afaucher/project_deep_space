extends "res://addons/beehave/nodes/leaves/action.gd"

# Steers a station towards its primary target without translating towards it.
# Arrests any translational drift.
#
# M27 bugfix: this leaf used to read a "primary_target_c_id" blackboard key
# that nothing ever wrote -- AcquireTargetLeaf (the Engage sequence's first
# child, immediately before this leaf) publishes "target_id"/"target_pos"
# instead (see acquire_target_leaf.gd). The mismatch meant this leaf always
# FAILED, which short-circuited build_station()'s Engage Sequence before
# FireOpportunityLeaf (the third child) ever ran -- so a station-tree hull's
# lasers/missiles never fired at a hostile VESSEL contact at all (only
# ship.gd's separate, AI-tree-independent _process_point_defense() path fired
# at INCOMING ORDNANCE). No existing test exercised this leaf, so the dead key
# name was never caught. Reading the keys AcquireTargetLeaf actually sets
# fixes it for every build_station() hull (mine, defence pod, and the
# existing small/medium stations), not just this milestone's new ships.
func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null:
		return SUCCESS

	if not blackboard.has_value("target_id"):
		return FAILURE
	var target_pos = blackboard.get_value("target_pos")

	# Determine desired heading
	var to_target = target_pos - actor.position
	var target_heading = to_target.angle()
	
	# Rotate towards target but do NOT translate (throttle=0)
	actor.apply_control_input(0.0, 0.0, target_heading, 0, 1)
	
	# Oppose current linear velocity to arrest drift
	var drift_vel = actor.linear_velocity
	var rcs_dir = Vector2.ZERO
	if drift_vel.length_squared() > 0.1:
		rcs_dir = -drift_vel # apply_rcs_input will normalize if length > 1
		
	actor.apply_rcs_input(rcs_dir, 0.0)
	
	return SUCCESS
