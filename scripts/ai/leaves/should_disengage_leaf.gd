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

# M52 playtest fix -- overheat disengage (calling session, 2026-07-22): a ship
# that's about to take direct reactor damage from its OWN heat (ship.gd's
# current_heat >= max_heat check, ~line 2408) can't fight effectively like
# that -- it needs to break off and let heat bleed down before max_heat
# itself starts draining the reactor, the same "hurt, so run" logic already
# applied to health. Set below 1.0 (the point damage actually starts) so
# this fires BEFORE the reactor takes a scratch, not after -- proactive, not
# reactive. Confirmed root cause: two ships pacing the same target (job_
# steps.gd's _pace_at_offset) never exclude EACH OTHER from Steering's
# avoidance, only the shared target, so they can fight indefinitely and hold
# near-max throttle -- job_steps.gd's own _thermal_derate softens that
# specific case, but this is the general backstop for ANY sustained-heat
# cause (combat maneuvering, weapon-fire heat, anything), not just pacing.
const DISENGAGE_HEAT_FRACTION := 0.9

# Hysteresis (calling session, 2026-07-22, second pass -- the plain threshold
# above made test_multi_pirate_thermal's exact repro WORSE, not better: heat
# still pegged at max_heat and killed a pirate anyway). Root cause: without
# hysteresis, the instant heat dips back under DISENGAGE_HEAT_FRACTION (one
# tick of coasting is often enough), the tree resumes JobRunner -> _pace_at_
# offset immediately -- but resuming from a drifted-off position means a
# FRESH, LARGER position error, so the catchup term spikes again right at
# resume. Repeated disengage/resume flicker right at the boundary produced
# MORE heat spikes than the smooth derate-only approach it was meant to
# backstop. Fix: once disengaging for heat, stay disengaged until heat drops
# to HEAT_RECOVER_FRACTION (well below the trigger, not just back under it)
# -- same "don't re-trigger right at the edge" idea TAKE_ALONGSIDE_EXIT_SLACK
# (job_steps.gd) already uses for an analogous boundary-flicker problem.
const HEAT_RECOVER_FRACTION := 0.6

func tick(actor: Node, blackboard) -> int:
	if actor.get_health_fraction() < DISENGAGE_HEALTH_FRACTION:
		return SUCCESS

	var heat_ratio: float = (actor.current_heat / actor.max_heat) if actor.max_heat > 0.0 else 0.0
	# blackboard is null in isolated/no-tree test contexts -- degrade to a
	# plain threshold check with no hysteresis rather than crash.
	if blackboard == null:
		return SUCCESS if heat_ratio >= DISENGAGE_HEAT_FRACTION else FAILURE

	if blackboard.get_value("heat_disengaging", false):
		if heat_ratio > HEAT_RECOVER_FRACTION:
			return SUCCESS
		blackboard.set_value("heat_disengaging", false)
		return FAILURE

	if heat_ratio >= DISENGAGE_HEAT_FRACTION:
		blackboard.set_value("heat_disengaging", true)
		return SUCCESS
	return FAILURE
