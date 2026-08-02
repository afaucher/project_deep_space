extends RefCounted

# M57 -- the incident record: EVIDENCE, as distinct from a warrant's VERDICT.
# (design_ideas/2026-08-01-patrol_director_and_reporting.md §4c.)
#
# A warrant answers "is this hull wanted right now": keyed (offense, subject),
# overwriting, read O(1) per contact per fusion tick via warrant_index. That
# shape is correct and is NOT changing -- the rejected alternative (bolt a
# position and a re-post counter onto the warrant) is recorded in
# implementation_plans/m52b_warrants.md with its reasons.
#
# An incident answers "what happened, where": one immutable record per
# occurrence, appended to the observer's own source log, never overwritten.
# Three robberies by one pirate are three incidents. Whether that is one problem
# or three, how much last week weighs against this morning, whether to cluster
# by lane -- all of that is the READING director's policy, deliberately not
# encoded here. You can always re-derive a verdict from evidence; you can never
# recover evidence from a verdict.
#
# Consumers (none of them exist yet -- this milestone only produces):
#   * traffic guild / RoutePlanner._risk_estimate -- avoid or price the lane (M59)
#   * patrol director -- the same map, opposite sign (M59)
#   * pirate guild -- prey density and enforcement heat, per lane (M60)

# Incident kinds. Deliberately NOT the same vocabulary as Standing's offenses:
# an offense is a legal judgement, a kind is what was observed. OVERDUE is the
# clearest case -- nobody committed "overdue", a hull simply stopped reporting,
# and that is exactly the sort of ambiguous evidence a director should be
# allowed to weigh for itself.
const KIND_ARMED_ROBBERY := "ARMED_ROBBERY"   # a take completed against this hull
const KIND_OVERDUE := "OVERDUE"               # a member stopped checking in
const KIND_ATTACKED := "ATTACKED"             # took hostile fire (M59+ producer)
const KIND_PIRATE_SIGHTED := "PIRATE_SIGHTED" # colours seen (M59+ producer)

# Builds the field dict for SourceLog.append_entry, which adds `seq` and
# `stamp`. Kept as a constructor rather than inline dict literals at each call
# site so the shape stays uniform across producers in three different
# subsystems -- a missing `pos` would silently make an incident useless to
# exactly the consumers it exists for.
#
# `subject_name`/`subject_flag` are what the OTHER party was publicly claiming,
# never omniscient truth -- same discipline as the docking registry, where a
# dark ship records as "". An incident naming a cover identity is honest
# evidence; an incident naming the hull's real owner would be a director
# cheating through a witness.
# `signature` is the observed sensor signature of the subject, when the reporter
# had one -- carried as EVIDENCE (a consumer correlating sightings across
# reports wants it), explicitly NOT as an identity.
#
# It is not an identity because Standing.subject_key's signature branch is only
# a fallback for unnamed subjects, and a weak one: it keys on
# `iff_tags + cross_section`, where iff_tags is a crypto set SHARED BY A WHOLE
# BAND and cross_section is a per-tick lerp of an angle-dependent reading. So it
# identifies a group, unstably. Ship.notarize_from refuses to issue a warrant
# from a signature-only report for exactly those two reasons.
#
# Empty is a legitimate value -- a victim that never held a track on its
# attacker genuinely has nothing to offer here.
static func make(kind: String, subject_name: String, subject_flag: String,
		pos: Vector2, reporter: String, signature: Dictionary = {}) -> Dictionary:
	return {
		"kind": kind,
		"subject_name": subject_name,
		"subject_flag": subject_flag,
		"pos": pos,
		"reporter": reporter,
		"signature": signature.duplicate(true) if not signature.is_empty() else {},
	}
