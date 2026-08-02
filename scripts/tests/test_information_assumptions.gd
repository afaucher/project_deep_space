extends Node

# M57 -- a TRIPWIRE, not a feature test.
#
# implementation_plans/m57_m61_information_economy_roadmap.md §0 records fifteen
# facts about the existing code that the M57-M61 design rests on. Those were
# verified by reading the tree on 2026-08-01, which means they were true once
# and nothing stops them quietly ceasing to be. A refactor that moves the
# datalink gate or un-seals personal-origin warrants would not fail any existing
# test -- it would fail a PLAYTEST, months later, as "why do patrols know things
# they shouldn't".
#
# So this file asserts the load-bearing subset directly. Read a failure here as
# "a documented assumption changed", not necessarily "a bug was introduced":
#
#   * If the change was UNINTENTIONAL, the roadmap just caught a real regression.
#   * If the change was INTENTIONAL -- M59 gives _risk_estimate a body, and this
#     file's C1 check is SUPPOSED to fail then -- update §0's claims table in the
#     same commit, then update the assertion here. The failure is the reminder to
#     do the first thing, which is the entire point of the tripwire.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_information_assumptions

const Standing = preload("res://scripts/combat/standing.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(_main) -> void:
	print("Starting Information Model Assumptions (M57 tripwire) Tests")
	_c1_risk_seam()
	_c3_relay_gate()
	_c5_personal_origin_seal()
	_c6_warrant_index_is_keyed()
	_c13_logs_live_on_the_record()
	_finalize()

# --- C1: the cargo risk seam is a deliberate stub. --------------------------
# M59 replaces this. When it does, THIS ASSERTION SHOULD FAIL -- update §0 and
# this check together. Until then, a non-zero return would mean risk-aware
# routing shipped without the transport that makes it honest, which is the
# failure mode the seam's own comment was written to prevent.
func _c1_risk_seam() -> void:
	print("[C1] RoutePlanner._risk_estimate is still a stub")
	_assert(RoutePlanner._risk_estimate(null, null) == 0.0,
		"_risk_estimate returns 0.0 -- risk-aware routing is NOT live yet (M59 flips this)")

# --- C3: the relay gate is crypto-kin only. ---------------------------------
# The whole two-tier transport model (and M61's competing bands under one flag)
# rests on disjoint IFF tag sets being unable to share, so that isolation is the
# DEFAULT rather than something to build.
func _c3_relay_gate() -> void:
	print("[C3] datalink shares only between overlapping IFF tag sets")
	_assert(Ship._iff_tags_overlap(["TEAM_HOME"], ["TEAM_HOME", "TEAM_AUX"]),
		"overlapping tags are kin")
	_assert(not Ship._iff_tags_overlap(["TEAM_RED_BAND"], ["TEAM_BLUE_BAND"]),
		"DISJOINT tags cannot relay -- rival bands under one flag are isolated by default")
	_assert(not Ship._iff_tags_overlap([], ["TEAM_HOME"]),
		"a ship with no tags is nobody's kin")
	_assert(Ship.DATALINK_RELAY_HZ >= 10.0,
		"relay cadence stays effectively instant (tier 1 is free and fast, by design)")

# --- C5: a civilian's warrant is sealed until an authority co-signs. --------
# This is WHY patrols cannot currently respond to piracy: the transport works,
# the report is legally inert. M58's notarization step is the fix, and it only
# makes sense while this remains true.
func _c5_personal_origin_seal() -> void:
	print("[C5] personal-origin warrants do not propagate")
	var victim_iid := 111
	var other_iid := 222
	_assert(Standing.scoped_origin(Standing.FLAG_DRIFT, []) == "",
		"a hull with no warrant_authority scopes its warrant PERSONAL (origin_flag \"\")")
	_assert(Standing.scoped_origin(Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT]) == Standing.FLAG_DRIFT,
		"an authority for its own flag scopes it to that flag")

	var personal: Dictionary = Standing.make_warrant(
		Standing.OFF_ARMED_ROBBERY,
		{"claimed_name": "Second Return", "iid": 999},
		{"iid": victim_iid, "flag": Standing.FLAG_DRIFT},
		"", "evt1", "took cargo")
	_assert(Standing.warrant_enforceable_by(personal, [Standing.FLAG_DRIFT], other_iid) == false,
		"a SEALED report is not enforceable by a patrol, even one of the victim's own flag")
	_assert(Standing.warrant_enforceable_by(personal, [], victim_iid) == true,
		"the issuer can still act on its own report")

	var notarized: Dictionary = Standing.make_warrant(
		Standing.OFF_ARMED_ROBBERY,
		{"claimed_name": "Second Return", "iid": 999},
		{"iid": victim_iid, "flag": Standing.FLAG_DRIFT},
		Standing.FLAG_DRIFT, "evt1", "took cargo")
	_assert(Standing.warrant_enforceable_by(notarized, [Standing.FLAG_DRIFT], other_iid) == true,
		"once co-signed with a flag, any holder of that flag can enforce it (this is M58's payoff)")

# --- C6: warrants stay a keyed VERDICT store. -------------------------------
# The reason incidents are a separate record instead of fields bolted onto a
# warrant: this lookup runs per contact per fusion tick and must stay a keyed
# read, never a scan over a history.
func _c6_warrant_index_is_keyed() -> void:
	print("[C6] warrant lookup is a keyed index, not a scan")
	var observer_iid := 333
	var skey: String = Standing.subject_key("Second Return", {})
	var w: Dictionary = Standing.make_warrant(
		Standing.OFF_ARMED_ROBBERY,
		{"claimed_name": "Second Return", "iid": 999},
		{"iid": observer_iid, "flag": Standing.FLAG_DRIFT},
		Standing.FLAG_DRIFT, "evt1", "took cargo")
	var idx: Dictionary = Standing.build_warrant_index({w["event_key"]: w}, [Standing.FLAG_DRIFT], observer_iid)
	_assert(idx is Dictionary, "the index is a Dictionary (O(1) lookup, not a list walk)")
	_assert(idx.has(skey), "it is keyed by SUBJECT -- the key compute_standing looks up (got keys %s)" % str(idx.keys()))

# --- C13: source logs live on the record, not the live node. ----------------
# "Put the map on the station, not the director" needs no new architecture --
# this is the precedent, and it already survives demote.
func _c13_logs_live_on_the_record() -> void:
	print("[C13] docking registry and incident log both live on ClusterEntity")
	var rec = ClusterEntity.new()
	_assert("docking_registry" in rec and "registry_seq" in rec,
		"docking_registry + registry_seq are RECORD fields (the M57 precedent)")
	_assert("incident_log" in rec and "incident_seq" in rec,
		"incident_log + incident_seq joined them on the record, not on a director")
	_assert(rec.incident_log.is_empty() and rec.incident_seq == 0,
		"both default empty on every record -- meaningless on entities that never record")

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_information_assumptions <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_information_assumptions <<<")
		get_tree().quit(1)
