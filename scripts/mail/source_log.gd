extends RefCounted

# M57 -- the source-log primitive (design_ideas/mail_network.md, "The merge is
# just a version compare").
#
# THIS IS NOT A NEW DESIGN. It is the docking registry's mechanics, extracted so
# a second source log doesn't copy them. That code (ship.gd's
# record_docking_event / DOCKING_REGISTRY_CAP, M53b Pass 1b) already got every
# subtle part right, and each is preserved here verbatim in intent:
#
#   * ONE WRITER per source. A source's log is append-only and incremented by
#     that source alone, which is what makes "whose version is higher" a total
#     order with no per-fact reconciliation. Nobody else ever appends.
#   * SEQ IS NEVER RESET OR REUSED, INCLUDING ON A TRIM. The counter is the
#     ordering clock; array length is not. Trimming old entries must not make a
#     later "do I have newer than you?" compare wrong -- see merge() below,
#     which is exactly the compare that would break.
#   * TWO CLOCKS PER ENTRY. `seq` orders (logical clock, merge only); `stamp` is
#     Engine.get_physics_frames() and is for AGE DISPLAY ONLY, never ordering
#     (the M56 frame-stamp idiom). A holder-side third clock, `confirmed_at`,
#     exists per (holder, source) and is M58's business, not an entry field --
#     see the mail doc's "Three clocks, not two".
#   * PLAIN SERIALIZABLE DATA. Entries hold ints/strings/Vector2 only -- no
#     object refs, no node handles -- so a log can be merged and serialized
#     across ships. An entry that captured a Node would be unmergeable the
#     moment the node died, which is precisely when the record matters most.
#
# Deliberately NOT here: the holder-side mailbag ({source, version,
# confirmed_at} version vector) and the read-clamp that IS the fog. Those are
# M58. This file is only "a source owns an append-only log with a monotonic
# counter", which is the substrate both milestones stand on.

# Appends one entry, stamping the two clocks, and trims to `cap` oldest-first.
#
# The CALLER increments and passes `seq` (rather than this function owning the
# counter) because the counter's home varies -- ClusterEntity.registry_seq for a
# promoted station, the Ship's own fallback field otherwise -- and GDScript has
# no by-reference int. Keeping the increment at the call site next to the field
# it belongs to is clearer than passing a holder + field name.
#
# `fields` is duplicated, never aliased: the caller usually builds it inline,
# but a caller that reuses one dict across appends would otherwise mutate every
# entry it had already written.
static func append_entry(log: Array, seq: int, fields: Dictionary, cap: int) -> Dictionary:
	var entry: Dictionary = fields.duplicate()
	entry["seq"] = seq
	entry["stamp"] = Engine.get_physics_frames()
	log.append(entry)
	while log.size() > cap:
		log.pop_front() # oldest first; seq deliberately NOT rewound
	return entry

# Merges two views of THE SAME source's log and returns a fresh array.
#
# Union keyed on `seq`, because a source is single-writer and append-only, so a
# seq identifies an entry uniquely and forever -- two holders that both hold
# seq 41 hold the same fact, and no reconciliation is possible or needed.
#
# The three properties the mail model depends on, all falling out of "union on a
# unique key" rather than needing to be enforced:
#   * IDEMPOTENT   -- merge(a, a) == a
#   * COMMUTATIVE  -- merge(a, b) == merge(b, a)
#   * MONOTONIC    -- the result is a superset of both inputs (before the cap)
# so holders converge regardless of who syncs with whom, in what order, or how
# many times. That is the whole reason this shape was chosen over a "latest
# snapshot wins" copy, which loses whatever the receiver knew and the sender
# did not.
#
# The cap is applied AFTER the union, oldest-first, so a merge can legitimately
# drop entries that survived in one input. That is intended: a holder keeps the
# newest `cap` facts it has ever seen, and `seq` staying monotonic is what keeps
# the compare correct once they are gone.
static func merge(a: Array, b: Array, cap: int) -> Array:
	var by_seq: Dictionary = {}
	for e in a:
		by_seq[e.get("seq", 0)] = e
	for e in b:
		by_seq[e.get("seq", 0)] = e
	var keys: Array = by_seq.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(by_seq[k])
	while out.size() > cap:
		out.pop_front()
	return out

# "Do I have mail for you?" -- the whole delivery test, per the mail doc.
static func has_news_for(my_seq: int, their_seq: int) -> bool:
	return my_seq > their_seq

# Highest seq present in a log view, or 0 for an empty one. Note this is NOT
# interchangeable with the holder's seq counter: a trimmed log's counter stays
# ahead of its own tail, which is the point of not rewinding it.
static func high_water(log: Array) -> int:
	var hi: int = 0
	for e in log:
		hi = maxi(hi, int(e.get("seq", 0)))
	return hi
