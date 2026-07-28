extends "res://addons/beehave/nodes/leaves/action.gd"

const Standing = preload("res://scripts/combat/standing.gd")

# M12 acquire_target: pick the nearest hostile contact and publish it to the blackboard
# for the steer/fire leaves downstream. M48: "hostile" is now the earned, per-observer
# standing judgment (Standing.HOSTILE) rather than the raw classification bucket --
# see implementation_plans/m48_standings_flags_design.md (INCOMING ORDNANCE is handled
# by the ship's own point defense, not chased as a maneuver target). Returns FAILURE
# when there is nothing to engage so the parent selector falls through to Idle.
func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	# M49 -- a held ship doesn't hunt (design_ideas/comms_verbs.md's honored
	# stop); the tree falls through to Idle, and the ship-level throttle
	# override (ship.gd's _physics_process) owns motion regardless.
	if not actor.compelled_stop.is_empty():
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
		# ENGAGEMENT POLICY -- this actor's own, deliberately kept here rather
		# than in the shared helper below. A patrol/station fires only on a
		# flagged target; a pirate tree may one day fire on anybody, and that
		# difference must not be locked out by a shared function.
		if contact.get("standing", "") != Standing.HOSTILE:
			continue
		# TRACK VALIDITY -- wreckage, the M49 honor rule (a complied ship is
		# off the table regardless of standing) and fire-discipline staleness.
		# Shared with the player's weapons console (Standing.track_engageable),
		# because those three are mechanical rather than policy and nobody
		# benefits from the two disagreeing -- the four-copies lesson from A2.
		if not Standing.track_engageable(contact):
			continue
		# THE AGGRESSION CAP (campaign playtest 2026-07-26, A3). HOSTILE is a
		# COLOR, not a firing authorization, and this leaf used to treat the two
		# as the same thing -- every path that could paint a contact red also
		# pointed guns at it. That is how the playtest's player, flying clean,
		# got shot by the home station for not answering an ID challenge: an
		# ignored challenge posts NO_ID, NO_ID reads HOSTILE, and HOSTILE was
		# the whole test.
		#
		# Standing.authorizes_force is the gate (see its offense-table note for
		# why response_class could not be reused). The demand ladder is
		# unaffected -- InterdictLeaf still intercepts and demands a stop on any
		# HOSTILE, which is the intended enforcement for a capped offense; what
		# changes is that when the ladder is refused, an uncapped offense falls
		# through to Engage and a capped one does not. A NO_ID hull gets chased
		# and hailed and refused docking, never shot.
		#
		# NO MATCHING WARRANT MEANS UNCAPPED, deliberately. Two live paths reach
		# HOSTILE without one: a known-enemy flag (compute_standing rule 3 -- a
		# declared pirate is engageable on sight, unchanged) and the eager
		# same-tick cache stamps in take_damage/the aggression witness, which
		# always post their warrant in the same breath, so the miss is at most a
		# one-tick lag on a warrant that does authorize force anyway.
		if not _force_authorized(actor, contact):
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
	return SUCCESS

# Resolve the warrant behind a HOSTILE contact and ask whether it puts weapons
# on the table. Same subject-key derivation InterdictLeaf uses to pick its
# demand patience (claimed name if we have received a transponder, else the
# track signature) against the same per-observer, already-filtered
# warrant_index -- so an unenforceable warrant, which never colored the contact
# HOSTILE in the first place, cannot authorize force either.
func _force_authorized(actor: Node, contact: Dictionary) -> bool:
	var claimed_name: String = actor.active_transponders.get(contact.get("instance_id", -1), {}).get("name", "")
	var skey: String = Standing.subject_key(claimed_name, contact.get("signature", {}))
	var w: Dictionary = actor.warrant_index.get(skey, {})
	if w.is_empty():
		return true   # flag-declared enemy / eager stamp -- uncapped, see tick()
	return Standing.authorizes_force(w.get("offense", ""))
