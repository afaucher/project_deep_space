extends Node

# M53b Pass 1b acceptance (implementation_plans/m53c_demand_routing.md "Phase 0").
# Proves the docking-registry bug the pass fixes is actually fixed: a station's
# registry must survive a demote -> promote cycle, with registry_seq continuing
# STRICTLY upward rather than restarting at 0 on re-promote (the mail merge is
# "my version > your version" -- a reset sequence poisons that compare
# permanently, per the plan doc). Deliberately drives ClusterManager under
# configure_bubble(), NOT configure_full_sim() -- under FULL_SIM nothing ever
# demotes and this test would prove nothing. Pattern (ClusterManager/
# ClusterEntity/LivenessPolicy, synchronous viewpoint+tick()) follows
# test_cluster_bubble.gd. All checks are synchronous (no physics frames needed --
# record_docking_event() is plain data bookkeeping called directly on the live
# node, same shortcut test_docking_registry.gd's trim check uses). Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_registry_survives_demote

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _mk(id: int, pos: Vector2, hull: Script, kind: int, is_static: bool) -> ClusterEntity:
	var e := ClusterEntity.new()
	e.id = id
	e.hull_script = hull
	e.kind = kind
	e.is_static = is_static
	e.pos = pos
	return e

func setup(main) -> void:
	main_node = main
	print("Starting Registry Survives Demote (M53b Pass 1b) Tests")

	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(10000.0, 15000.0)   # BUBBLE, not full-sim -- must actually demote
	m.policy = pol
	main_node.add_child(m)

	var rec := _mk(500, Vector2.ZERO, MediumStation, ClusterEntity.Kind.STATION, true)
	m.add_record(rec)

	# --- Cycle 1: promote, accumulate three registry entries. ---
	m.viewpoint = Vector2.ZERO
	m.tick(0.0)
	_assert(rec.is_live(), "station promotes at the viewpoint")
	if not rec.is_live():
		_finalize(); return

	var node1 = rec.live_node
	node1.record_docking_event("ShipA", "FLAG_CIVILIAN", "DOCKED")
	node1.record_docking_event("ShipA", "FLAG_CIVILIAN", "DEPARTED")
	node1.record_docking_event("ShipB", "FLAG_DRIFT", "DOCKED")

	_assert(node1.get_registry_seq() == 3, "live node's accessor reports seq 3 after three events (got %d)" % node1.get_registry_seq())
	_assert(node1.get_docking_registry().size() == 3, "live node's accessor reports 3 entries (got %d)" % node1.get_docking_registry().size())

	# One canonical store: writes must land on the RECORD, not the node's own
	# local fallback fields -- a dual write would let the record go stale
	# while the station is live.
	_assert(node1.docking_registry.is_empty(), "live node's own local docking_registry field stays empty (record is canonical while attached)")
	_assert(node1.registry_seq == 0, "live node's own local registry_seq field stays 0 (record is canonical while attached)")
	_assert(rec.docking_registry.size() == 3, "the RECORD itself already holds the 3 entries while still live")
	_assert(rec.registry_seq == 3, "the RECORD's registry_seq is already 3 while still live")

	# --- Demote: move the viewpoint past demote_r. ---
	m.viewpoint = Vector2(1e9, 0)
	m.tick(0.0)
	_assert(not rec.is_live(), "station demotes once the viewpoint leaves")

	_assert(rec.docking_registry.size() == 3, "(a) earlier entries survive demote (expected 3, got %d)" % rec.docking_registry.size())
	_assert(rec.registry_seq == 3, "(b) registry_seq survives demote unchanged (expected 3, got %d)" % rec.registry_seq)
	if rec.docking_registry.size() >= 1:
		_assert(rec.docking_registry[0].get("subject_name", "") == "ShipA" and rec.docking_registry[0].get("event", "") == "DOCKED",
			"oldest surviving entry is still ShipA's DOCKED (seq 1), not lost or reordered")

	# --- Cycle 2: re-promote. registry_seq must NOT restart at 0. ---
	m.viewpoint = Vector2.ZERO
	m.tick(0.0)
	_assert(rec.is_live(), "station re-promotes when the viewpoint returns")
	if not rec.is_live():
		_finalize(); return

	var node2 = rec.live_node
	_assert(node2 != node1, "re-promotion built a fresh node (sanity: this is really a new node, not the old one)")
	_assert(node2.get_registry_seq() == 3, "(b) re-promoted node's registry_seq continues at 3, NOT reset to 0 (got %d)" % node2.get_registry_seq())
	_assert(node2.get_docking_registry().size() == 3, "(a) re-promoted node still sees all 3 pre-demote entries (got %d)" % node2.get_docking_registry().size())

	node2.record_docking_event("ShipC", "", "DOCKED")
	_assert(node2.get_registry_seq() == 4, "a new event after re-promote continues the sequence at 4, not restarting at 1 (got %d)" % node2.get_registry_seq())
	_assert(node2.get_docking_registry().size() == 4, "registry now holds 4 entries total across the demote/promote cycle")

	# --- Demote again: full monotonic history must hold across BOTH cycles. ---
	m.viewpoint = Vector2(1e9, 0)
	m.tick(0.0)
	_assert(not rec.is_live(), "station demotes a second time")

	_assert(rec.docking_registry.size() == 4, "all 4 entries (both cycles) survive the second demote (got %d)" % rec.docking_registry.size())
	_assert(rec.registry_seq == 4, "registry_seq ends at 4 (got %d)" % rec.registry_seq)
	var prev_seq: int = 0
	for e in rec.docking_registry:
		var s: int = int(e.get("seq", -1))
		_assert(s == prev_seq + 1, "seq is strictly monotonic +1 across the demote/promote boundary (got %d after %d)" % [s, prev_seq])
		prev_seq = s

	m.queue_free()
	_finalize()

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_registry_survives_demote <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_registry_survives_demote <<<")
		get_tree().quit(1)
