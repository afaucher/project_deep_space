extends Node

# M53b Pass 1 acceptance -- the per-station docking registry
# (implementation_plans/m53bc_traffic_guild.md "Pass 1", design_ideas/
# mail_network.md "Docking registry (per station)"). Pure instrumentation:
# nothing consumes docking_registry yet, so this test proves the RECORDING
# side only -- the right entries land in the right station's log, in order,
# on both convergence-point transitions (DOCKED arrival, DOCKED->EMPTY
# departure), via BOTH docking paths that funnel through DockingBay:
#
#   - NPC path:    station.issue_docking_grant(ship) called DIRECTLY (the
#                   same call cargo_run_leaf.gd / job_steps.gd make), then
#                   wants_dock=true -- mirrors real NPC AI, not a shortcut.
#   - Player path:  PortControl.request_docking(station, ship) -- the shared
#                   dialogue/fast-path entry point.
#
# A THIRD station proves seq is per-station (doesn't collide/interleave with
# StationA's counter). Phase-driven synchronous machine, same style as
# test_docking_permission.gd. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_docking_registry

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const PortControl = preload("res://scripts/port/port_control.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var t: float = 0.0
const TIMEOUT := 25.0

var station_a = null   # hosts BOTH the NPC-path and player-path docks
var bay_npc = null
var bay_player = null
var shuttle_npc = null
var shuttle_player = null

var station_b = null   # proves per-station seq isolation
var bay_b = null
var shuttle_b = null

var npc_docked_seen: bool = false
var player_docked_seen: bool = false
var b_docked_seen: bool = false

var npc_departed_seen: bool = false
var player_departed_seen: bool = false
var b_departed_seen: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _bays(st) -> Array:
	var out: Array = []
	for c in st.get_children():
		if c is DockingBay:
			out.append(c)
	return out

func _approach_pos(bay) -> Vector2:
	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	return bay.global_position + fwd * 200.0

func setup(main) -> void:
	main_node = main
	print("Starting Docking Registry (M53b Pass 1) Tests")

	# --- Station A: two berths, one NPC dock, one player dock. ---
	station_a = MediumStation.new()
	station_a.name = "StationA"
	station_a.owner_id = 1
	station_a.position = Vector2.ZERO
	main_node.add_child(station_a)
	var bays_a: Array = _bays(station_a)
	_assert(bays_a.size() >= 2, "StationA should grow two DockingBays (dock_main/dock_aux)")
	if bays_a.size() < 2:
		_finalize(); return
	bay_npc = bays_a[0]
	bay_player = bays_a[1]

	# NPC path: mirror cargo_run_leaf.gd / job_steps.gd EXACTLY -- call the
	# station's issue_docking_grant() directly (no PortControl involved),
	# then raise wants_dock. This is the path grant-hooking would have missed.
	shuttle_npc = CargoShuttle.new()
	shuttle_npc.name = "NpcShuttle"
	shuttle_npc.owner_id = 60
	shuttle_npc.iff_tags = ["TEAM_PLAYER"]
	shuttle_npc.position = _approach_pos(bay_npc)
	main_node.add_child(shuttle_npc)
	var npc_grant = station_a.issue_docking_grant(shuttle_npc)
	_assert(npc_grant != null, "NPC path: issue_docking_grant succeeds (berth free)")
	shuttle_npc.wants_dock = true

	# Player path: the shared comms/fast-path entry point.
	shuttle_player = CargoShuttle.new()
	shuttle_player.name = "PlayerShuttle"
	shuttle_player.owner_id = 61
	shuttle_player.iff_tags = ["TEAM_PLAYER"]
	shuttle_player.position = _approach_pos(bay_player)
	main_node.add_child(shuttle_player)
	var outcome: Dictionary = PortControl.request_docking(station_a, shuttle_player)
	_assert(outcome.get("outcome", "") == "granted", "player path: request_docking grants (was '%s')" % outcome.get("outcome", ""))

	# --- Station B: a second, independent station -- proves per-station seq. ---
	station_b = MediumStation.new()
	station_b.name = "StationB"
	station_b.owner_id = 2
	station_b.position = Vector2(400000, 0)   # far away, no cross-station interaction
	# MediumStation hardcodes authority "Ironhold Control" and slip ids
	# "dock_main"/"dock_aux" -- issue_docking_grant()'s pool check scans ALL
	# ships tree-wide for a live grant with the SAME authority string (by
	# design: one real Ironhold, one shared pool). Two MediumStation
	# instances in the same test would therefore fight over each other's
	# slip reservations unless given distinct authorities -- give StationB
	# its own so it's a genuinely independent station for this test.
	station_b.port_zone["authority"] = "Outpost Control"
	main_node.add_child(station_b)
	var bays_b: Array = _bays(station_b)
	_assert(bays_b.size() >= 1, "StationB should grow at least one DockingBay")
	if bays_b.is_empty():
		_finalize(); return
	bay_b = bays_b[0]

	shuttle_b = CargoShuttle.new()
	shuttle_b.name = "OtherStationShuttle"
	shuttle_b.owner_id = 62
	shuttle_b.iff_tags = ["TEAM_PLAYER"]
	shuttle_b.position = _approach_pos(bay_b)
	main_node.add_child(shuttle_b)
	var b_grant = station_b.issue_docking_grant(shuttle_b)
	_assert(b_grant != null, "StationB NPC path: issue_docking_grant succeeds")
	shuttle_b.wants_dock = true

	# Sanity: registries start empty, seq starts at 0 (first entry will be seq=1).
	_assert(station_a.docking_registry.is_empty(), "StationA registry starts empty")
	_assert(station_a.registry_seq == 0, "StationA registry_seq starts at 0")
	_assert(station_b.docking_registry.is_empty(), "StationB registry starts empty")
	_assert(station_b.registry_seq == 0, "StationB registry_seq starts at 0")

func _physics_process(delta: float) -> void:
	if finished:
		return
	t += delta
	if t > TIMEOUT:
		_assert(false, "TIMEOUT before all docks/departures observed (npc_docked=%s player_docked=%s b_docked=%s npc_dep=%s player_dep=%s b_dep=%s)" % [
			npc_docked_seen, player_docked_seen, b_docked_seen, npc_departed_seen, player_departed_seen, b_departed_seen])
		_finalize()
		return

	if not npc_docked_seen and bay_npc.state == DockingBay.State.DOCKED:
		npc_docked_seen = true
		_check_arrival(station_a, shuttle_npc, "NPC")
	if not player_docked_seen and bay_player.state == DockingBay.State.DOCKED:
		player_docked_seen = true
		_check_arrival(station_a, shuttle_player, "player")
	if not b_docked_seen and bay_b.state == DockingBay.State.DOCKED:
		b_docked_seen = true
		_check_arrival(station_b, shuttle_b, "StationB NPC")

	if npc_docked_seen and not npc_departed_seen and bay_npc.state == DockingBay.State.EMPTY:
		npc_departed_seen = true
		_check_departure(station_a, shuttle_npc, "NPC")
	if player_docked_seen and not player_departed_seen and bay_player.state == DockingBay.State.EMPTY:
		player_departed_seen = true
		_check_departure(station_a, shuttle_player, "player")
	if b_docked_seen and not b_departed_seen and bay_b.state == DockingBay.State.EMPTY:
		b_departed_seen = true
		_check_departure(station_b, shuttle_b, "StationB NPC")

	if npc_departed_seen and player_departed_seen and b_departed_seen:
		_final_checks()
		_finalize()

# Two bays on the SAME station can settle into DOCKED on the very same
# physics frame (both shuttles start symmetric distances out) -- both
# entries land in docking_registry that tick, so "read the array tail"
# would nondeterministically grab the OTHER ship's entry depending on
# append order. Look up by (subject_name, event) instead -- unambiguous
# since each ship gets a distinct randomized name (Ship._init()).
func _find_entry(station, subject_name: String, event: String) -> Dictionary:
	for e in station.docking_registry:
		if e.get("subject_name", "") == subject_name and e.get("event", "") == event:
			return e
	return {}

func _check_arrival(station, shuttle, label: String) -> void:
	var expected_name: String = shuttle.get_active_transponder_data().get("name", "")
	var entry: Dictionary = _find_entry(station, expected_name, "DOCKED")
	_assert(not entry.is_empty(), "%s: registry has a DOCKED entry for '%s' after DOCKED" % [label, expected_name])
	if entry.is_empty():
		return
	_assert(int(entry.get("seq", 0)) > 0, "%s: seq starts at/above 1" % label)
	_assert(typeof(entry.get("stamp", null)) == TYPE_INT, "%s: stamp is an int (frame stamp)" % label)
	# Plain serializable data -- no Object refs anywhere in the entry.
	for k in entry:
		var v = entry[k]
		_assert(typeof(v) == TYPE_INT or typeof(v) == TYPE_STRING, "%s: entry field '%s' is plain int/string, not an object ref (was type %d)" % [label, k, typeof(v)])

func _check_departure(station, shuttle, label: String) -> void:
	var expected_name: String = shuttle.get_active_transponder_data().get("name", "")
	var entry: Dictionary = _find_entry(station, expected_name, "DEPARTED")
	_assert(not entry.is_empty(), "%s: registry has a DEPARTED entry for '%s' after release" % [label, expected_name])

func _final_checks() -> void:
	# StationA saw exactly two dock/undock pairs (NPC + player) -> 4 entries,
	# seq 1..4, strictly monotonic increasing by exactly 1 per entry.
	var reg_a: Array = station_a.docking_registry
	_assert(reg_a.size() == 4, "StationA registry has exactly 4 entries (2 docks + 2 departures), got %d" % reg_a.size())
	var prev_seq: int = 0
	for e in reg_a:
		var s: int = int(e.get("seq", -1))
		_assert(s == prev_seq + 1, "StationA seq is strictly monotonic +1 per entry (got %d after %d)" % [s, prev_seq])
		prev_seq = s
	_assert(station_a.registry_seq == 4, "StationA registry_seq ends at 4")

	# StationB is independent: its own counter started fresh at 1, NOT
	# continuing StationA's count -- proves no cross-station seq collision.
	var reg_b: Array = station_b.docking_registry
	_assert(reg_b.size() == 2, "StationB registry has exactly 2 entries (1 dock + 1 departure), got %d" % reg_b.size())
	if reg_b.size() >= 1:
		_assert(int(reg_b[0].get("seq", -1)) == 1, "StationB's own seq starts at 1, independent of StationA's counter")
	_assert(station_a.registry_seq != station_b.registry_seq or (station_a.registry_seq == 4 and station_b.registry_seq == 2), "StationA and StationB seq counters are independent (a=%d, b=%d)" % [station_a.registry_seq, station_b.registry_seq])

	# Both StationA subjects are distinguishable (different ships, different
	# names) -- proves the registry doesn't just log a bare "someone docked".
	if reg_a.size() >= 4:
		var names: Array = []
		for e in reg_a:
			names.append(e.get("subject_name", ""))
		_assert(names[0] != "" and names[1] != "", "StationA's two docking subjects both carry a non-empty declared name")

	_check_trim_semantics()

# Directly exercise the trim/cap behavior (M~200 entries would be too slow to
# drive through real physics) -- calls record_docking_event() on a scratch
# station far past the cap and checks the array stays bounded while seq keeps
# climbing UNRESET, matching the spec ("do NOT reset or reuse registry_seq
# when trimming").
func _check_trim_semantics() -> void:
	# Instantiated but deliberately NOT added to the tree -- record_docking_
	# event() is plain data bookkeeping with no physics/_ready dependency, so
	# driving it directly here avoids 225 unnecessary node-lifecycle frames.
	var scratch = MediumStation.new()
	scratch.owner_id = 99
	var cap: int = Ship.DOCKING_REGISTRY_CAP
	for i in range(cap + 25):
		scratch.record_docking_event("Ghost", "", "DOCKED" if i % 2 == 0 else "DEPARTED")
	_assert(scratch.docking_registry.size() == cap, "registry stays capped at DOCKING_REGISTRY_CAP (%d) after exceeding it, got %d" % [cap, scratch.docking_registry.size()])
	_assert(scratch.registry_seq == cap + 25, "registry_seq keeps climbing UNRESET past the cap (expected %d, got %d)" % [cap + 25, scratch.registry_seq])
	var oldest: Dictionary = scratch.docking_registry[0]
	_assert(int(oldest.get("seq", -1)) == 25 + 1, "oldest surviving entry is the first one NOT dropped (expected seq %d, got %d)" % [26, int(oldest.get("seq", -1))])
	var newest: Dictionary = scratch.docking_registry[scratch.docking_registry.size() - 1]
	_assert(int(newest.get("seq", -1)) == cap + 25, "newest entry's seq matches the final registry_seq (monotonic post-trim)")
	scratch.free()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_registry <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_registry <<<")
		get_tree().quit(1)
