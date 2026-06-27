extends "res://addons/beehave/nodes/leaves/condition.gd"

# M12c disengage trigger. SUCCESS (disengage) when the ship is critically damaged --
# surviving total component health below DISENGAGE_HEALTH_FRACTION of its pristine
# maximum -- otherwise FAILURE so the selector proceeds to Engage. Sits at the top of the
# tree so a hurt ship breaks off and runs instead of trading blows.
#
# Per-instance variation of the threshold (a braver pirate, a fragile civilian) is the
# M12f profile work; a fixed fraction is the first cut. Out-of-ammo / outgunned triggers
# can be OR-ed in here later.
const DISENGAGE_HEALTH_FRACTION := 0.3

func tick(actor: Node, _blackboard) -> int:
	if actor.get_health_fraction() < DISENGAGE_HEALTH_FRACTION:
		return SUCCESS
	return FAILURE
