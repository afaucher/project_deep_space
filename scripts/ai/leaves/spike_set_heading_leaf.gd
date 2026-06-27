extends "res://addons/beehave/nodes/leaves/action.gd"

# M12b-spike (THROWAWAY): proves a Beehave ActionLeaf can drive a real Ship through the
# same fly-by-wire intent the helm/player use (apply_control_input). It sets a known
# heading so the spike test can assert the tick actually reached the ship. Delete once
# the M12b leaf library proper exists.
const TEST_HEADING := 1.234

func tick(actor: Node, _blackboard) -> int:
	if actor == null or not actor.has_method("apply_control_input"):
		return FAILURE
	# thrust=0, target_velocity=0, heading=TEST_HEADING, steering_mode=1, linear_mode=1
	actor.apply_control_input(0.0, 0.0, TEST_HEADING, 1, 1)
	return SUCCESS
