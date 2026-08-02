extends Node

# M57 acceptance -- the incident log and the SourceLog primitive under it
# (implementation_plans/m57_m61_information_economy_roadmap.md "M57",
# design_ideas/mail_network.md "The merge is just a version compare").
#
# Pure recording-side test, deliberately: nothing CONSUMES incidents yet (M59
# gives RoutePlanner._risk_estimate a body, M60 the pirate guild), exactly as
# test_docking_registry.gd was written for the registry one milestone earlier.
# What must be true now is that the substrate has the properties the later
# milestones will rest on, because those are the ones that are expensive to
# discover late:
#
#   1. seq is monotonic and IS NOT REWOUND BY A TRIM. Array length is not the
#      clock. If a trim rewound seq, two holders would compare versions wrongly
#      forever after -- silently, and only once logs got long.
#   2. merge is IDEMPOTENT, COMMUTATIVE and LOSSLESS. Holders must converge no
#      matter who syncs with whom, in what order, or how many times.
#   3. merge NEVER ERASES what the receiver knew. This is the specific bug that
#      killed the earlier "snapshot the station's map at dock" design: a
#      wholesale copy means docking at a poorly-informed station makes a hauler
#      FORGET the robbery it personally witnessed. Asserted directly below.
#   4. The record, not the node, is canonical -- an incident survives demote,
#      the same contract pos/vel and docking_registry already hold.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_incident_log

const SourceLog = preload("res://scripts/mail/source_log.gd")
const Incident = preload("res://scripts/mail/incident.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _seqs(log: Array) -> Array:
	var out: Array = []
	for e in log:
		out.append(int(e.get("seq", 0)))
	return out

# Builds a standalone log by appending `n` entries through the real API.
func _make_log(n: int, cap: int, tag: String) -> Array:
	var log: Array = []
	for i in range(n):
		SourceLog.append_entry(log, i + 1,
			Incident.make(Incident.KIND_OVERDUE, "%s_%d" % [tag, i], "DRIFT",
				Vector2(i * 100, 0), tag),
			cap)
	return log

func setup(main) -> void:
	print("Starting Incident Log (M57) Tests")
	_test_append_and_clocks()
	_test_trim_does_not_rewind_seq()
	_test_merge_algebra()
	_test_merge_never_erases()
	_test_record_is_canonical(main)
	_finalize()

# --- 1. Entry shape: two clocks, honest fields. -----------------------------
func _test_append_and_clocks() -> void:
	print("[1] entry shape and the two clocks")
	var log: Array = []
	var e: Dictionary = SourceLog.append_entry(log, 1,
		Incident.make(Incident.KIND_ARMED_ROBBERY, "Second Return", "PIRATE",
			Vector2(1200, -400), "Victim"), 10)
	_assert(e.get("seq", 0) == 1, "seq is stamped from the caller's counter")
	_assert(e.has("stamp"), "stamp (frame clock, age display only) is present")
	_assert(e.get("kind", "") == Incident.KIND_ARMED_ROBBERY, "kind survives")
	_assert(e.get("pos", Vector2.ZERO) == Vector2(1200, -400),
		"pos survives -- the whole reason an incident exists rather than a warrant")
	_assert(e.get("reporter", "") == "Victim", "reporter survives")
	_assert(log.size() == 1, "the entry landed in the log")

	# fields must be COPIED, not aliased -- a caller reusing one dict across
	# appends would otherwise retro-edit every entry it had already written.
	var shared: Dictionary = Incident.make(Incident.KIND_OVERDUE, "A", "DRIFT", Vector2.ZERO, "G")
	var e1: Dictionary = SourceLog.append_entry(log, 2, shared, 10)
	shared["subject_name"] = "MUTATED"
	_assert(e1.get("subject_name", "") == "A",
		"append_entry duplicates fields -- a later mutation cannot reach a written entry")

# --- 2. The property that is expensive to get wrong. ------------------------
func _test_trim_does_not_rewind_seq() -> void:
	print("[2] a trim drops entries but never rewinds the clock")
	var cap := 5
	var log: Array = _make_log(12, cap, "trim")
	_assert(log.size() == cap, "log is capped at %d entries" % cap)
	_assert(_seqs(log) == [8, 9, 10, 11, 12],
		"the OLDEST entries are dropped, newest kept (got %s)" % str(_seqs(log)))
	_assert(SourceLog.high_water(log) == 12,
		"high_water reflects the newest seq, not the array length")
	# The compare that would silently break if a trim reset the counter:
	_assert(SourceLog.has_news_for(12, 5), "a holder at v12 has news for one at v5")
	_assert(not SourceLog.has_news_for(5, 12), "and not the other way round")
	_assert(log.size() != SourceLog.high_water(log),
		"array length and version have diverged -- which is exactly why length must never be the clock")

# --- 3. Convergence algebra. ------------------------------------------------
func _test_merge_algebra() -> void:
	print("[3] merge is idempotent, commutative and lossless")
	var cap := 50
	var a: Array = _make_log(6, cap, "a")
	# `b` is the same source seen further along -- entries 1..9, so it overlaps
	# a's 1..6 and extends past it. Same source => same seq means same fact.
	var b: Array = _make_log(9, cap, "a")

	var ab: Array = SourceLog.merge(a, b, cap)
	var ba: Array = SourceLog.merge(b, a, cap)
	_assert(_seqs(ab) == _seqs(ba), "merge is COMMUTATIVE (%s vs %s)" % [str(_seqs(ab)), str(_seqs(ba))])
	_assert(_seqs(ab) == [1, 2, 3, 4, 5, 6, 7, 8, 9],
		"merge unions and orders by seq (got %s)" % str(_seqs(ab)))

	var twice: Array = SourceLog.merge(ab, b, cap)
	_assert(_seqs(twice) == _seqs(ab), "merge is IDEMPOTENT -- re-syncing changes nothing")
	var self_merge: Array = SourceLog.merge(a, a, cap)
	_assert(_seqs(self_merge) == _seqs(a), "merge(a, a) == a")

	# Disjoint holders: neither is a superset, and both must converge.
	var lo: Array = [{"seq": 2, "kind": "X"}, {"seq": 5, "kind": "X"}]
	var hi: Array = [{"seq": 3, "kind": "X"}, {"seq": 9, "kind": "X"}]
	_assert(_seqs(SourceLog.merge(lo, hi, cap)) == [2, 3, 5, 9],
		"disjoint holders converge to the union, in seq order")

# --- 4. The anti-snapshot property. -----------------------------------------
func _test_merge_never_erases() -> void:
	print("[4] merging a poorly-informed view never erases a well-informed one")
	var cap := 50
	# The hauler personally witnessed a robbery (seq 7). The quiet outpost it
	# docks at knows only old news (seq 1..3). Under the rejected snapshot
	# design the hauler would forget its own eyewitness account on landing.
	var hauler: Array = [{"seq": 7, "kind": Incident.KIND_ARMED_ROBBERY, "pos": Vector2(9000, 9000)}]
	var quiet_port: Array = [{"seq": 1, "kind": "X"}, {"seq": 2, "kind": "X"}, {"seq": 3, "kind": "X"}]

	var after: Array = SourceLog.merge(hauler, quiet_port, cap)
	_assert(_seqs(after) == [1, 2, 3, 7],
		"the hauler KEEPS its own seq 7 and gains the port's 1-3 (got %s)" % str(_seqs(after)))
	var kept := false
	for e in after:
		if int(e.get("seq", 0)) == 7 and e.get("kind", "") == Incident.KIND_ARMED_ROBBERY:
			kept = true
	_assert(kept, "the eyewitness robbery record survived docking at a quieter station")

	# And the cap, applied after the union, drops OLDEST -- so pressure never
	# costs you the newest facts.
	var tight: Array = SourceLog.merge(hauler, quiet_port, 2)
	_assert(_seqs(tight) == [3, 7], "under cap pressure the union keeps the NEWEST (got %s)" % str(_seqs(tight)))

# --- 5. The record is canonical, not the node. ------------------------------
func _test_record_is_canonical(main) -> void:
	print("[5] incidents live on the cluster record and survive demote")
	var ship = CargoShuttle.new()
	ship.name = "Hauler"
	ship.owner_id = 70
	main.add_child(ship)

	# Bare ship (never promoted): writes to the local fallback.
	ship.record_incident(Incident.KIND_ARMED_ROBBERY, "Cover Name", "CIVILIAN", Vector2(500, 0))
	_assert(ship.get_incident_log().size() == 1, "a bare Ship records to its local fallback")
	_assert(ship.get_incident_seq() == 1, "and advances the local counter")

	# Promoted: writes to the record instead, and NEVER to both (a dual write
	# would let the record go stale while the hull is live).
	var rec = ClusterEntity.new()
	rec.id = 4242
	ship.cluster_record_ref = weakref(rec)
	ship.record_incident(Incident.KIND_OVERDUE, "Cluster_9011", "DRIFT", Vector2(1500, 250))
	_assert(rec.incident_log.size() == 1, "a promoted Ship records to its RECORD")
	_assert(rec.incident_seq == 1, "the record owns the counter once attached")
	_assert(ship.incident_log.size() == 1,
		"the local fallback did NOT also receive it (no dual write)")
	_assert(ship.get_incident_log().size() == 1 and
			ship.get_incident_log()[0].get("subject_name", "") == "Cluster_9011",
		"the read side resolves to the record too")

	# Demote: the node goes away, the record keeps the evidence.
	ship.queue_free()
	_assert(rec.incident_log.size() == 1 and
			rec.incident_log[0].get("pos", Vector2.ZERO) == Vector2(1500, 250),
		"the incident (with its position) outlives the hull that recorded it")

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_incident_log <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_incident_log <<<")
		get_tree().quit(1)
