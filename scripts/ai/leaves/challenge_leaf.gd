extends "res://addons/beehave/nodes/leaves/action.gd"

# M49 -- patrol challenge (design_ideas/comms_verbs.md's "Patrol" policy):
# DEMAND(IDENTIFY) any fresh, CAUTION vessel contact found inside
# controlled space (a station's port zone) and within comms-link range.
# Inserted in build_patrol AFTER Engage, BEFORE FollowRoute
# (ai_tree_factory.gd) -- cheap side-effect work that ALWAYS returns FAILURE
# so the tree still falls through to FollowRoute, same "leaf that never
# claims the tick" shape broadcast_transponder_leaf.gd uses in build_station.
#
# Perf: the discovery scan (fresh CAUTION contacts x zone membership x
# comms range) is gated to run every SCAN_INTERVAL_TICKS physics ticks, not
# every tick -- the only new periodic work this milestone adds (per the
# roadmap's perf guardrail). Window bookkeeping for already-challenged tracks
# runs every tick but is O(challenged), which stays tiny (a patrol rarely has
# more than a couple of open challenges at once).
const Hail = preload("res://scripts/comms/hail.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const SCAN_INTERVAL_TICKS := 30
const CHALLENGE_WINDOW_FRAMES := 1200 # ~20s @ 60Hz physics tick rate
# How long a track must be CONTINUOUSLY unreporting before it is worth asking.
# Comfortably longer than a datalink relay round (DATALINK_RELAY_HZ, phase
# offset per ship) plus sensor-fusion settle, so an honest ship whose
# transponder is merely a few ticks behind is never challenged at all.
const SILENT_GRACE_FRAMES := 300 # ~5s @ 60Hz

func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	_check_windows(actor, blackboard)

	var frame: int = Engine.get_physics_frames()
	var last_scan: int = blackboard.get_value("challenge_last_scan_frame", -SCAN_INTERVAL_TICKS)
	if frame - last_scan < SCAN_INTERVAL_TICKS:
		return FAILURE
	blackboard.set_value("challenge_last_scan_frame", frame)

	var self_range: float = actor.get_comms_range()
	if self_range <= 0.0:
		return FAILURE

	var challenged: Dictionary = blackboard.get_value("challenged", {})
	# How long a track must stay CAUTION before it is worth asking. See
	# SILENT_GRACE_FRAMES.
	var silent_since: Dictionary = blackboard.get_value("challenge_silent_since", {})
	# Tracks we have ALREADY convicted (see _check_windows). Read here so a
	# conviction stops the questioning -- see the skip below.
	var ignored: Dictionary = blackboard.get_value("challenge_ignored", {})

	for c_id in actor.active_contacts:
		if challenged.has(c_id):
			continue
		var c: Dictionary = actor.active_contacts[c_id]
		if c.get("standing", "") != Standing.CAUTION:
			# Reporting (or judged some other way) -- forget any silence timer,
			# and forget the conviction too. A hull that relit has answered the
			# question; if it goes dark again later that is a NEW offense and it
			# deserves to be asked again rather than being permanently mute to us.
			silent_since.erase(c_id)
			ignored.erase(c_id)
			continue

		# ASK ONCE, THEN ESCALATE -- never ask again.
		#
		# This is the playtest's "we periodically get re-hailed while sitting
		# with comms off", and it is a feedback loop the patrol drives against
		# ITSELF. _check_windows convicts an unanswered challenge by posting a
		# NO_ID warrant and then ERASING the `challenged` entry (deliberately --
		# a challenge voided by the subject leaving must be re-issuable when it
		# returns). But a NO_ID warrant itself resolves to standing CAUTION --
		# the same tier a silent hull already sits in -- so one scan later this
		# loop re-read the patrol's OWN verdict as fresh evidence of silence,
		# found the silence timer long expired, and fired an identical
		# DEMAND(IDENTIFY) with a new seq. Twenty seconds later it convicted
		# again, and so on forever.
		#
		# The tier was spelled UNREPORTED at the time, which is why nobody saw
		# it: the loop read "UNREPORTED" and understood "has never identified
		# itself", when what the string actually meant by then was "there is
		# something here I cannot resolve" -- including a warrant this very
		# patrol had just written. Renaming it to CAUTION (2026-07-27) makes the
		# misreading visible, but does NOT make it impossible, which is why this
		# guard stays: a conviction is still caution-tier, and caution-tier is
		# still what a challenge looks for.
		#
		# Nothing downstream could catch it: the seq is genuinely new every
		# time, so ship.gd's refresh suppression correctly lets each one
		# through, and post_warrant is keyed by (offense, subject) so the
		# warrant silently overwrote itself while the HAILS list grew without
		# bound. Eleven identical DEMAND(IDENTIFY) lines from one patrol in the
		# playtest capture, still climbing.
		#
		# The ladder already has an answer for a refusal, and it is not asking
		# louder: the warrant is posted, InterdictLeaf owns the subject, and
		# DEMAND(STOP) is the next rung. Re-asking is both spam and wrong
		# fiction -- we already ruled on this ship.
		if ignored.has(c_id):
			continue

		# A FRESHLY ACQUIRED TRACK IS NOT A SILENT ONE. Every contact begins
		# CAUTION and only becomes NEUTRAL once the datalink relay actually
		# delivers a transponder (DATALINK_RELAY_HZ, with a per-ship phase
		# offset), so at campaign start a patrol sees EVERYTHING as unreporting
		# for a moment -- the player, the haulers, and the station it is
		# guarding -- and challenged all of them at once. That is the campaign
		# playtest's "DEMAND IDENTIFY immediately on start", and the reason
		# Patrol Alpha was observed hailing Ironhold.
		#
		# The offense is REFUSING to identify, which is a sustained state, so
		# require the silence to be sustained before asking. This also makes the
		# challenge cheap to satisfy honestly: anyone whose transponder is
		# simply a few relay ticks behind is never asked at all.
		var first_silent: int = silent_since.get(c_id, -1)
		if first_silent < 0:
			silent_since[c_id] = frame
			continue
		if frame - first_silent < SILENT_GRACE_FRAMES:
			continue
		if Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
			continue
		if not _in_controlled_space(actor, c.get("pos", Vector2.ZERO)):
			continue

		var target_node = _resolve_track_node(actor, c_id)
		if target_node == null:
			continue
		var their_range: float = target_node.get_comms_range()
		if their_range <= 0.0:
			continue
		var link_range: float = min(self_range, their_range)
		if actor.position.distance_to(target_node.position) > link_range:
			continue

		Hail.send(actor, target_node, {"verb": Hail.VERB_DEMAND, "rung": Hail.RUNG_IDENTIFY})
		challenged[c_id] = {"expire_frame": frame + CHALLENGE_WINDOW_FRAMES}

	# Drop silence timers for tracks we no longer hold at all, so a re-acquired
	# contact starts its grace afresh rather than inheriting an old timestamp.
	var stale_silent: Array = []
	for k in silent_since:
		if not actor.active_contacts.has(k):
			stale_silent.append(k)
	for k in stale_silent:
		silent_since.erase(k)

	blackboard.set_value("challenge_silent_since", silent_since)
	blackboard.set_value("challenged", challenged)
	blackboard.set_value("challenge_ignored", ignored)
	return FAILURE

# Per-tick window bookkeeping over already-issued challenges: a track that
# relights (standing goes NEUTRAL) within the window resolves quietly
# (recorded in challenge_resolved -- testable state, see test_patrol_
# challenge.gd); one that's still CAUTION when the window expires is
# recorded in challenge_ignored -- the M52 assessment input (no standing
# change, no engagement in M49).
func _check_windows(actor: Node, blackboard) -> void:
	var challenged: Dictionary = blackboard.get_value("challenged", {})
	if challenged.is_empty():
		return
	var ignored: Dictionary = blackboard.get_value("challenge_ignored", {})
	var resolved: Dictionary = blackboard.get_value("challenge_resolved", {})
	var frame: int = Engine.get_physics_frames()
	var to_erase: Array = []
	for trk in challenged.keys():
		var entry: Dictionary = challenged[trk]
		var c: Dictionary = actor.active_contacts.get(trk, {})
		var standing: String = c.get("standing", "")
		if standing == Standing.NEUTRAL:
			resolved[trk] = true # relit within the window -- resolved
			to_erase.append(trk)
			continue
		if frame >= entry.get("expire_frame", 0):
			# A SILENT CONTACT ONLY MEANS SOMETHING IF WE COULD STILL HEAR IT.
			# Issuing the challenge above already gates on comms range; this
			# expiry path never did, so a hull that was challenged legitimately
			# and then simply LEFT was convicted for not answering a question
			# the patrol could no longer hear the answer to. Comms is
			# deliberately shorter than sensor reach -- being able to see
			# something you cannot hail is the intended asymmetry, the little
			# bit of omniscience you have to close distance to earn -- so
			# outside that range "not reporting" is a fact about OUR DEAFNESS,
			# not about them.
			#
			# This is the campaign playtest's A1 and A3 in one mechanism
			# (design_ideas/2026-07-26-campaign_playtest.md): the player is
			# challenged at spawn, moves off as anyone would, the window lapses
			# out of comms range, a NO_ID warrant lands, compute_standing reads
			# it as HOSTILE, and the home station opens fire. "If you move the
			# station opens fire" is literal.
			#
			# Voided, not deferred: the entry is erased either way, so the
			# patrol may challenge again the moment the contact is back in
			# range. Keeping it pending instead would accumulate challenges
			# against every hull that ever wandered off.
			var still_in_comms: bool = false
			var subject_node = _resolve_track_node(actor, trk)
			if subject_node != null and is_instance_valid(subject_node):
				var their_r: float = subject_node.get_comms_range()
				var our_r: float = actor.get_comms_range()
				if their_r > 0.0 and our_r > 0.0:
					still_in_comms = actor.position.distance_to(subject_node.position) <= min(our_r, their_r)
			if standing == Standing.CAUTION and still_in_comms:
				ignored[trk] = true
				# M52 -- suspicion assessment folded into the warrant pipeline
				# (implementation_plans/m52_patrol_interdiction.md item 3): an
				# ignored IDENTIFY challenge posts a NO_ID warrant against
				# whatever this actor could actually see (claimed name is
				# empty for a true CAUTION contact -- subject_key falls
				# back to the signature). Closes the loop end to end: next
				# fusion tick's compute_standing reads it via warrant_index ->
				# HOSTILE -> InterdictLeaf picks it up.
				var claimed_name: String = actor.active_transponders.get(c.get("instance_id", -1), {}).get("name", "")
				actor.post_warrant(Standing.OFF_NO_ID, claimed_name, c.get("signature", {}), "ignored identify challenge")
			to_erase.append(trk)
	for trk in to_erase:
		challenged.erase(trk)
	blackboard.set_value("challenged", challenged)
	blackboard.set_value("challenge_ignored", ignored)
	blackboard.set_value("challenge_resolved", resolved)

# v1 controlled-space gate: inside ANY station's port zone (same "ships"
# group discovery pattern cargo_run_leaf.gd's _find_station_at uses).
func _in_controlled_space(actor: Node, world_pos: Vector2) -> bool:
	var tree = actor.get_tree()
	if tree == null:
		return false
	for s in tree.get_nodes_in_group("ships"):
		if not s.has_method("get_port_zone"):
			continue
		var zone: Dictionary = s.get_port_zone()
		if zone.is_empty():
			continue
		if s.position.distance_to(world_pos) <= zone.get("radius", 0.0):
			return true
	return false

# Contacts are tracks, not nodes -- to address the hail we need the target
# node. Resolve by scanning the "ships" group for the node whose derived
# TRK id matches (bounded: only called on the rare challenge send, not
# per-contact per-tick).
func _resolve_track_node(actor: Node, trk_id: String) -> Node:
	var tree = actor.get_tree()
	if tree == null:
		return null
	for s in tree.get_nodes_in_group("ships"):
		if s == actor:
			continue
		if Ship.track_id(s.get_instance_id()) == trk_id:
			return s
	return null
