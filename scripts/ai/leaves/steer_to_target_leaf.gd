extends "res://addons/beehave/nodes/leaves/action.gd"

# M12c posture & orientation. A broadside attacker reaches its optimal range, turns to
# present its heaviest battery, and then basically DRIFTS while firing -- thrust is only
# spent to (a) reach optimal range, or (b) correct once drift carries it past the
# hysteresis band (too far / too close). Re-presenting the battery as the target's
# bearing changes is free (RCS rotation, no translation), so it is not "maneuvering."
#
#   * |dist - OPTIMAL_RANGE| > RANGE_BAND -> REPOSITION nose-on. Velocity control with an
#     arrival profile (speed scales with the range error) closes or backs off and settles
#     near optimal instead of overshooting. Nose-on because thrust is applied along facing.
#   * within the band -> hold the heaviest broadside on the target and COAST (zero
#     throttle, no braking) -- the massed volley (fire_opportunity + is_group_volley_ready)
#     does the work while the hull drifts.
#
# For a forward-only hull the heaviest group is the nose, so "broadside" collapses to
# nose-on. Returns SUCCESS every tick so the Engage sequence proceeds to firing.
const OPTIMAL_RANGE := 8000.0       # preferred broadside firing distance (outside enemy
                                     # laser, well inside missile range)
const RANGE_BAND := 2000.0          # +/- hysteresis: inside this, present + drift
const REPOSITION_GAIN := 0.5        # arrival: target speed per unit of range error
const MAX_REPOSITION_SPEED := 800.0

func tick(actor: Node, blackboard) -> int:
	if not blackboard.has_value("target_pos"):
		return SUCCESS

	var target_pos = blackboard.get_value("target_pos")
	var to_target = target_pos - actor.position
	var bearing = to_target.angle()
	var range_error = to_target.length() - OPTIMAL_RANGE

	if abs(range_error) > RANGE_BAND:
		# Reposition nose-on. Arrival profile: speed decays as the error shrinks so the
		# ship settles into the band rather than barrelling through it. Negative = reverse.
		var spd = clampf(range_error * REPOSITION_GAIN, -MAX_REPOSITION_SPEED, MAX_REPOSITION_SPEED)
		actor.apply_control_input(0.0, spd, bearing, 1, 1)
	else:
		# At range: present the heaviest broadside and drift (linear_mode 0 + zero throttle
		# applies no force, so the hull coasts instead of braking).
		var heading = bearing - _heaviest_group_heading(actor, bearing)
		actor.apply_control_input(0.0, 0.0, heading, 1, 0)
	return SUCCESS

# Mount heading (relative to ship forward) of the weapon group with the most weapons.
# Ties -- a frigate's matched port/stbd batteries -- break toward whichever side is the
# smaller turn from where the nose currently points, so the ship rolls onto the nearer
# broadside. Returns 0.0 for a forward-heavy hull, i.e. nose-on.
func _heaviest_group_heading(actor: Node, bearing: float) -> float:
	var groups = actor.get_weapon_groups()
	var best_size := -1
	var best_heading := 0.0
	var best_turn := INF
	for gid in groups:
		var ids = groups[gid]
		if ids.is_empty():
			continue
		var gh = float(actor.get_component(ids[0]).get("heading", 0.0))
		var turn = abs(wrapf((bearing - gh) - actor.rotation, -PI, PI))
		if ids.size() > best_size or (ids.size() == best_size and turn < best_turn):
			best_size = ids.size()
			best_heading = gh
			best_turn = turn
	return best_heading
