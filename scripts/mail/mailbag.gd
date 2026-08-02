extends RefCounted

# M58 -- the mailbag: what THIS holder knows, and how current it believes that
# knowledge to be (design_ideas/mail_network.md, "Three clocks, not two").
#
#   bag: source_id -> {"version": int, "confirmed_at": int}
#
# A holder's entire knowledge state is a VERSION VECTOR OF INTEGERS. It stores
# no content whatsoever. Content is global -- every source's log sits on its own
# ClusterEntity record, readable in principle by anyone -- and a holder's reads
# are CLAMPED to its delivered version for that source. **That clamp is the
# fog.** There is no private per-ship copy of the world to keep in sync, no
# per-fact reconciliation, and the whole thing is serializable and deterministic.
#
# This is the part worth not re-deriving: the obvious implementation (each ship
# carries copies of the facts it has heard) is strictly worse -- it costs memory
# per hull, it makes merges O(facts) instead of O(sources), and it has no way to
# express "I checked and nothing had changed".
#
# TWO HOLDER-SIDE CLOCKS, both merging as `max`:
#
#   version       -- how much of that source's log I am entitled to read.
#   confirmed_at   -- when I last SYNCED that source, whether or not anything
#                     had changed. Frame stamp (the M56 idiom).
#
# Why the second one is not redundant: version measures CONTENT, confirmed_at
# measures UNCERTAINTY. If a quiet outpost has had no docks, v12 is still
# perfectly correct -- what has gone stale is my confidence that it is *still*
# v12. A courier arriving with "Deepcut@v12, confirmed a minute ago" has
# therefore delivered something real even though no version moved. Without this
# clock that delivery is unrepresentable, and "nothing happened" becomes
# unsellable -- which would make a courier route a lottery that only pays when
# there happens to be news.
#
# DO NOT "simplify" confirmed_at away by reading the entry stamp of a log's
# tail. A quiet source's newest entry can be hours old while a holder's
# knowledge of it is a minute old. Those are different facts.
#
# Both clocks being monotonic is what keeps merge order-independent and
# idempotent, so holders converge no matter who syncs with whom, in what order,
# or how many times.

# The delivered version for one source, or 0 if this holder has never heard of
# it. 0 means "read nothing", not "read everything" -- an unknown source is
# invisible, which is the correct default for a fog model.
static func version_of(bag: Dictionary, source_id: int) -> int:
	return int(bag.get(source_id, {}).get("version", 0))

static func confirmed_at_of(bag: Dictionary, source_id: int) -> int:
	return int(bag.get(source_id, {}).get("confirmed_at", 0))

static func knows(bag: Dictionary, source_id: int) -> bool:
	return bag.has(source_id)

# Records a DIRECT sync with a source: I read this source's own log myself, so
# my version is exactly its current seq and my confidence is now.
#
# Clamped upward only (`max`), never assigning blindly -- a holder that had
# somehow heard of a NEWER version through a third party must not be walked
# backwards by touching the source itself. Monotonic in, monotonic out.
static func sync_direct(bag: Dictionary, source_id: int, source_seq: int, now: int) -> void:
	var cur: Dictionary = bag.get(source_id, {})
	bag[source_id] = {
		"version": maxi(int(cur.get("version", 0)), source_seq),
		"confirmed_at": maxi(int(cur.get("confirmed_at", 0)), now),
	}

# Merges `from` INTO `into` (mutates and returns `into`), per-source `max` on
# both clocks. This is the whole transport operation -- kin-relay and dock-merge
# are the same call, differing only in who is allowed to make it and how often.
#
# Idempotent, commutative and monotonic, all falling out of `max` rather than
# being enforced. Crucially it can only ever ADVANCE the receiver: merging a
# poorly-informed view into a well-informed one is a no-op, so docking at a
# quiet outpost cannot make a hauler forget the robbery it witnessed. (That was
# the specific defect in the rejected "snapshot the station's map at dock"
# design -- see the M58 notes in the roadmap.)
static func merge(into: Dictionary, from: Dictionary) -> Dictionary:
	for source_id in from:
		var theirs: Dictionary = from[source_id]
		var mine: Dictionary = into.get(source_id, {})
		into[source_id] = {
			"version": maxi(int(mine.get("version", 0)), int(theirs.get("version", 0))),
			"confirmed_at": maxi(int(mine.get("confirmed_at", 0)), int(theirs.get("confirmed_at", 0))),
		}
	return into

# One direction of a sync: everything `from_bag`'s holder has heard, PLUS that
# holder's own log read first-hand, delivered into `to_bag`.
#
# The two steps are different and both are needed. `merge` carries third-party
# news -- what the giver heard from elsewhere, only as fresh as its own last
# courier -- and is what lets news travel more than one hop. `sync_direct`
# records that the receiver has now read the giver's OWN log with its own eyes,
# which is the only way confirmed_at ever gets a genuinely current stamp.
#
# Deliberately ONE direction per call. An automatic two-way merge would hand a
# port your fresher picture for free and flatten the whole information economy;
# callers make the give and the receive as separate, separately-gated decisions.
static func deliver(to_bag: Dictionary, from_bag: Dictionary,
		from_source_id: int, from_source_seq: int, now: int) -> void:
	merge(to_bag, from_bag)
	if from_source_id >= 0:
		sync_direct(to_bag, from_source_id, from_source_seq, now)

# "Do I have mail for you?" -- true if this holder is ahead on ANY source.
# Cheap enough to ask on every dock; it is a walk over sources, not facts.
static func has_news_for(mine: Dictionary, theirs: Dictionary) -> bool:
	for source_id in mine:
		if version_of(mine, source_id) > version_of(theirs, source_id):
			return true
		if confirmed_at_of(mine, source_id) > confirmed_at_of(theirs, source_id):
			return true
	return false

# THE FOG, in one function: every source's incident log is globally reachable,
# and this returns only the entries this holder's delivered version entitles it
# to see. A source the holder has never heard of contributes nothing at all.
#
# Returns flat entries with `source_id` stamped on, since a consumer building a
# risk map cares where a report came from (and how stale that source is) as much
# as what it says.
static func read_incidents(cluster, bag: Dictionary) -> Array:
	var out: Array = []
	if cluster == null or not is_instance_valid(cluster):
		return out
	for rec in cluster.records:
		var v: int = version_of(bag, rec.id)
		if v <= 0:
			continue
		for e in rec.incident_log:
			if int(e.get("seq", 0)) <= v:
				var view: Dictionary = e.duplicate()
				view["source_id"] = rec.id
				view["source_confirmed_at"] = confirmed_at_of(bag, rec.id)
				out.append(view)
	return out
