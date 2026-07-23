extends Node

# M33 acceptance -- Port Control comms (the dialogue that issues the grant).
# implementation_plans/m31_m36_port_authority_roadmap.md, M33 "Test plan
# (Fable)" (line 417-439). Six scenarios, run as a sequential phase machine
# (same style as test_docking_permission.gd / test_port_zone.gd):
#   1. Grant mutation path (dialogue's "request docking" mutation issues a
#      real DockingGrant that then docks the ship, via M32's gate).
#   2. Slip allocation: two requesters get two different slips; a third gets
#      "no berths".
#   3. Discovery: NPC appears in comms only in transponder range, disappears
#      out of range.
#   4. Fast-path parity: the one-press button and the dialogue mutation hit
#      the SAME issuance path with the same outcome shape.
#   5. Context flip: DockingControl reads "Request Docking"/"Undock" and the
#      Undock press drives M32's undock to EMPTY.
#   6. Style degradation: AUTOMATED grants immediately; MINIMAL stalls once
#      then succeeds (deterministic counter, no RNG); STAFFED surfaces a
#      personal NPC name (not "...Control").
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_port_control_comms

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const PortControl = preload("res://scripts/port/port_control.gd")
const DockingControl = preload("res://scripts/ui/docking_control.gd")
const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _med_bay(st) -> Node:
	for c in st.get_children():
		if c is DockingBay:
			return c
	return null

func _all_bays(st) -> Array:
	var out: Array = []
	for c in st.get_children():
		if c is DockingBay:
			out.append(c)
	return out

func _make_station(name: String, style: String, owner: int, extra := {}) -> Node:
	var st = MediumStation.new()
	st.name = name
	st.owner_id = owner
	st.iff_tags = ["TEAM_PLAYER"]
	st.position = Vector2.ZERO
	var zone: Dictionary = {
		"radius": 8000.0,
		"authority": name + " Control",
		"style": style,
		"rules": {},
	}
	for k in extra.keys():
		zone[k] = extra[k]
	st.port_zone = zone
	if style == PortControl.STYLE_MINIMAL or style == PortControl.STYLE_STAFFED:
		st.slip_policy = "any_open"
	main_node.add_child(st)
	# MediumStation._init() already appends its own port-control NPC (pointed
	# at the AUTOMATED-flavored default). Refresh the name to match whatever
	# style THIS test station actually declares (constructed after _init()
	# already ran with the AUTOMATED default baked into medium_station.gd).
	if not st.available_npcs.is_empty():
		st.available_npcs[0].character_name = PortControl.get_controller_name(st)
		st.available_npcs[0].faction = zone["authority"]
	return st

# Spawn INSIDE the station's 8000u control zone (Vector2(4000, 4000) ~= 5657u
# out): PortControl.request_docking now denies an out-of-zone requester
# ("out_of_zone" -- see port_control.gd), so being in-zone is a precondition
# for every granted-path scenario here. The old magic spot (9999, 9999) sat
# ~14.1ku out and started failing the moment that check landed.
func _make_shuttle(name: String, owner: int, pos: Vector2) -> Node:
	var s = CargoShuttle.new()
	s.name = name
	s.owner_id = owner
	s.iff_tags = ["TEAM_PLAYER"]
	s.position = pos
	main_node.add_child(s)
	return s

func setup(main) -> void:
	main_node = main
	print("Starting Port Control Comms (M33) Tests")
	await _run_dialogue_traversal_check()
	await _run_dialogue_loop_check()
	await _run_dialogue_out_of_zone_check()
	await _run_dialogue_undock_check()
	_run_scenario_1_grant_mutation()

# ---------------------------------------------------------------------------
# Dialogue-through-DialogueManager smoke check. The scenarios below all call
# Station.request_docking_via_control() directly (the exact method the
# .dialogue "do" line invokes) to keep the phase machine synchronous, but
# that alone doesn't prove dialogue/port_control.dialogue's OWN traversal
# (extra_game_states threading through comms_panel.gd -> DialogueManager ->
# the "do" mutation line -> back out to a dialogue line) actually reaches the
# same method. This runs the real DialogueManager singleton end to end, the
# same way comms_panel.gd's _process_dialogue() does, and checks the grant
# lands on the player ship exactly like the direct-call scenarios expect.
# ---------------------------------------------------------------------------
func _run_dialogue_traversal_check() -> void:
	print("--- Dialogue traversal smoke check (port_control.dialogue via DialogueManager) ---")
	var station = _make_station("DialogueSmoke", PortControl.STYLE_AUTOMATED, 9)
	var player = _make_shuttle("DialogueSmokePlayer", 200, Vector2(4000, 4000))

	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "dialogue traversal: DialogueManager singleton not available")
		return
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/port_control.dialogue")
	_assert(resource != null, "dialogue traversal: port_control.dialogue loads")
	if resource == null:
		_free_if_valid(player); _free_if_valid(station)
		return

	var states: Array = [{"station": station, "player": player}, DialogueScratch.scratch()]
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	_assert(line != null, "dialogue traversal: 'start' cue returns a line")
	if line == null:
		_free_if_valid(player); _free_if_valid(station)
		return

	var docking_resp = null
	for r in line.responses:
		if r.text == "Request docking.":
			docking_resp = r
	_assert(docking_resp != null, "dialogue traversal: a 'Request docking.' response is offered")
	if docking_resp == null:
		_free_if_valid(player); _free_if_valid(station)
		return

	# DialogueResponse carries no extra_game_states field of its own (checked:
	# addons/dialogue_manager/dialogue_response.gd) -- comms_panel.gd's real
	# _on_response_clicked()/_process_dialogue() flow doesn't need one either,
	# since it always rebuilds extra_game_states fresh from
	# _dialogue_game_states() on every call. Mirror that here: reuse the same
	# `states` array built above rather than reading it off the response.
	var line2 = await dm.get_next_dialogue_line(resource, docking_resp.next_id, states)
	_assert(line2 != null, "dialogue traversal: following the response yields a reply line")
	_assert(player.docking_grant != null, "dialogue traversal: the .dialogue mutation issued a real grant on the player ship")
	# The SPOKEN line must match the outcome -- for years the grant was issued
	# while the conversation spoke the else-branch "Negative, we have no open
	# berths" (DialogueManager can't assign `do result = ...` to an undeclared
	# name; see scripts/dialogue_scratch.gd). State-only assertions never
	# caught it; this text assertion pins the fix.
	if line2 != null:
		_assert("Cleared to berth" in line2.text,
			"dialogue traversal: the spoken line reflects the grant (got: %s)" % line2.text)
		_assert(player.docking_grant != null and str(player.docking_grant.get("slip_id", "")) in line2.text,
			"dialogue traversal: the spoken line names the assigned slip")
	# Regression: a grant issued via the comms/dialogue route must actually
	# fly the capture, not just sit as unused permission. wants_dock used to
	# be raised ONLY by the fast-path "Request Docking" button
	# (docking_control.gd) -- a player who talked to Port Control instead got
	# "Cleared to berth X", flew to and sat exactly on the correct berth
	# marker, and nothing ever happened, because the ship was never actually
	# SEEKING capture (DockingBay._dockable_seeking() gates on wants_dock).
	# Fixed by raising it inside PortControl.request_docking() itself (the
	# ONE shared issuance path both routes call), not per-caller.
	_assert(player.get("wants_dock") == true,
		"dialogue traversal: a granted dialogue request also raises wants_dock (the ship actually seeks capture)")
	_assert(player.get("dockable") == true,
		"dialogue traversal: a granted dialogue request also confirms dockable")

	_free_if_valid(player); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Dialogue loop-back smoke check. A rejected request ("no open berths") used
# to `=> END` the conversation outright; a player who got denied had to
# re-hail from scratch to try again. dialogue/port_control.dialogue now
# `=> start`s on both "no_berths" and "stalled" outcomes, so continuing past
# the rejection line should drop back into the same menu (a line with
# "Request docking."/"Never mind." responses attached again), not terminate
# it (get_next_dialogue_line returning null). Drives the real DialogueManager
# singleton end to end, same as the traversal check above, so it exercises
# the actual .dialogue file rather than just PortControl.gd's pure logic.
# ---------------------------------------------------------------------------
func _run_dialogue_loop_check() -> void:
	print("--- Dialogue loop-back smoke check (reject returns to the menu, not END) ---")
	var station = _make_station("DialogueLoop", PortControl.STYLE_AUTOMATED, 10)
	var occupant = _make_shuttle("DialogueLoopOccupant", 201, Vector2(4000, 4000))
	var occupant2 = _make_shuttle("DialogueLoopOccupant2", 203, Vector2(4000, 4000))
	var player = _make_shuttle("DialogueLoopPlayer", 202, Vector2(4000, 4000))

	# Take BOTH of the station's berths first so the dialogue-driven request
	# below is denied. M40 -- MediumStation now authors two docking_port bays
	# (dock_main/dock_aux, "second Ironhold berth"); taking only one berth no
	# longer makes the station full.
	var occ_result: Dictionary = station.request_docking_via_control(occupant)
	_assert(occ_result.get("outcome", "") == "granted", "dialogue loop: setup occupant takes the first berth")
	var occ_result2: Dictionary = station.request_docking_via_control(occupant2)
	_assert(occ_result2.get("outcome", "") == "granted", "dialogue loop: setup occupant2 takes the second berth")

	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "dialogue loop: DialogueManager singleton not available")
		_free_if_valid(occupant); _free_if_valid(occupant2); _free_if_valid(player); _free_if_valid(station)
		return
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/port_control.dialogue")

	var states: Array = [{"station": station, "player": player}, DialogueScratch.scratch()]
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	var docking_resp = null
	for r in line.responses:
		if r.text == "Request docking.":
			docking_resp = r
	_assert(docking_resp != null, "dialogue loop: 'Request docking.' offered")
	if docking_resp == null:
		_free_if_valid(occupant); _free_if_valid(occupant2); _free_if_valid(player); _free_if_valid(station)
		return

	var reject_line = await dm.get_next_dialogue_line(resource, docking_resp.next_id, states)
	_assert(reject_line != null, "dialogue loop: a rejected request still returns a line (the 'no open berths' text)")
	_assert(player.docking_grant == null, "dialogue loop: the rejected request issued no grant")
	if reject_line == null:
		_free_if_valid(occupant); _free_if_valid(occupant2); _free_if_valid(player); _free_if_valid(station)
		return

	# THE regression check: continuing past the rejection must land back on
	# the menu, not end the conversation. Pre-fix (=> END) this returns null.
	var looped_line = await dm.get_next_dialogue_line(resource, reject_line.next_id, states)
	_assert(looped_line != null, "dialogue loop: conversation continues past a reject instead of ending (pre-fix regression: returned null / END)")
	if looped_line != null:
		var has_docking_choice := false
		for r in looped_line.responses:
			if r.text == "Request docking.":
				has_docking_choice = true
		_assert(has_docking_choice, "dialogue loop: reject drops back into the same menu ('Request docking.' offered again)")

	_free_if_valid(occupant); _free_if_valid(occupant2); _free_if_valid(player); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Dialogue out-of-zone smoke check: a requester OUTSIDE the station's control
# zone gets the "out_of_zone" outcome (port_control.gd's geometric gate --
# without it, a grant issued out here would silently expire on the next tick's
# membership check, reading as "granted then nothing happened"), the dialogue
# speaks its dedicated line for it, no grant is issued, and the conversation
# loops back to the menu like every other non-granted outcome.
# ---------------------------------------------------------------------------
func _run_dialogue_out_of_zone_check() -> void:
	print("--- Dialogue out-of-zone smoke check ---")
	var station = _make_station("DialogueFar", PortControl.STYLE_AUTOMATED, 11)
	var player = _make_shuttle("DialogueFarPlayer", 204, Vector2(20000, 0))   # zone radius 8000

	# Direct-call sanity first: the SAME station/ship pair must read
	# out_of_zone through PortControl before we blame the dialogue layer.
	var direct: Dictionary = PortControl.request_docking(station, player)
	_assert(direct.get("outcome", "") == "out_of_zone",
		"out-of-zone dialogue: direct PortControl call reads out_of_zone (got %s)" % str(direct.get("outcome")))

	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/port_control.dialogue")
	var states: Array = [{"station": station, "player": player}, DialogueScratch.scratch()]
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	var docking_resp = null
	for r in line.responses:
		if r.text == "Request docking.":
			docking_resp = r
	if docking_resp == null:
		_assert(false, "out-of-zone dialogue: 'Request docking.' offered")
		_free_if_valid(player); _free_if_valid(station)
		return

	var reply = await dm.get_next_dialogue_line(resource, docking_resp.next_id, states)
	_assert(reply != null, "out-of-zone dialogue: request returns a line")
	if reply != null:
		_assert("outside our control zone" in reply.text,
			"out-of-zone dialogue: speaks the out-of-zone line (got: %s)" % reply.text)
	_assert(player.docking_grant == null, "out-of-zone dialogue: no grant issued")
	if reply != null:
		var looped = await dm.get_next_dialogue_line(resource, reply.next_id, states)
		_assert(looped != null, "out-of-zone dialogue: loops back to the menu instead of ending")

	_free_if_valid(player); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Dialogue undock smoke check: the menu must CONTEXT-FLIP like the fast-path
# button does (docking_control.gd) -- "Request docking." while free, "Request
# undock." once actually at this station's berth, never both. Regression:
# before this, the menu only ever offered "Request docking.", which for an
# already-docked player just replied "you are already berthed" with no way to
# ask to be released -- the player had to fall back to the DockingControl
# button instead. Bypasses real capture-physics convergence (already covered
# by test_docking/test_freighter_docking) by directly wiring the bay/ship
# docked state, keeping this a synchronous, focused check of the DIALOGUE's
# own branching.
# ---------------------------------------------------------------------------
func _run_dialogue_undock_check() -> void:
	print("--- Dialogue undock smoke check ('Request undock.' offered only once actually docked) ---")
	var station = _make_station("DialogueUndock", PortControl.STYLE_AUTOMATED, 12)
	var player = _make_shuttle("DialogueUndockPlayer", 205, Vector2(4000, 4000))
	var bay = _med_bay(station)

	if not Engine.has_singleton("DialogueManager"):
		_assert(false, "dialogue undock: DialogueManager singleton not available")
		_free_if_valid(player); _free_if_valid(station)
		return
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/port_control.dialogue")
	var states: Array = [{"station": station, "player": player}, DialogueScratch.scratch()]

	# get_next_dialogue_line() does NOT filter line.responses by a gated
	# choice's `[if .../]` condition -- every response ID always compiles
	# into the array, each carrying its own `is_allowed` bool (see
	# dialogue_manager.gd's _get_responses()/_check_condition() -- filtering
	# is left to the caller). comms_panel.gd already does this (see its own
	# comment there); mirror it here or this check would pass trivially
	# regardless of whether the condition actually worked.
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	var docking_resp = null
	var undock_resp = null
	for r in line.responses:
		if not r.is_allowed:
			continue
		if r.text == "Request docking.":
			docking_resp = r
		elif r.text == "Request undock.":
			undock_resp = r
	_assert(docking_resp != null, "dialogue undock: 'Request docking.' offered before docking")
	_assert(undock_resp == null, "dialogue undock: 'Request undock.' withheld before docking")

	bay.captured = player
	bay.state = DockingBay.State.DOCKED
	player.docking_bay = bay

	var line2 = await dm.get_next_dialogue_line(resource, "start", states)
	docking_resp = null
	undock_resp = null
	for r in line2.responses:
		if not r.is_allowed:
			continue
		if r.text == "Request docking.":
			docking_resp = r
		elif r.text == "Request undock.":
			undock_resp = r
	_assert(undock_resp != null, "dialogue undock: 'Request undock.' offered once docked")
	_assert(docking_resp == null, "dialogue undock: 'Request docking.' withheld once docked (previously the only option -- it just replied 'already berthed')")
	if undock_resp == null:
		_free_if_valid(player); _free_if_valid(station)
		return

	var reply = await dm.get_next_dialogue_line(resource, undock_resp.next_id, states)
	_assert(reply != null, "dialogue undock: selecting it returns a line")
	_assert(player.docking_bay == null, "dialogue undock: selecting 'Request undock.' actually releases the ship")
	_assert(bay.state == DockingBay.State.EMPTY, "dialogue undock: the bay returns to EMPTY")

	_free_if_valid(player); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario 1: the dialogue's "request docking" mutation path (via
# request_docking_via_control, the same wrapper dialogue/port_control.dialogue
# calls) issues a real grant, which then docks the ship through M32's gate.
# ---------------------------------------------------------------------------
var s1_station = null
var s1_shuttle = null
var s1_bay = null
var s1_t: float = 0.0
const S1_TIMEOUT := 12.0

func _run_scenario_1_grant_mutation() -> void:
	print("--- Scenario 1: grant mutation path -> DOCKED ---")
	s1_station = _make_station("Automated1", PortControl.STYLE_AUTOMATED, 1)
	s1_bay = _med_bay(s1_station)
	_assert(s1_bay != null, "scenario 1: station grows a DockingBay")

	var fwd: Vector2 = Vector2.RIGHT.rotated(s1_bay.global_rotation)
	s1_shuttle = _make_shuttle("S1Shuttle", 60, s1_bay.global_position + fwd * 200.0)
	s1_shuttle.dockable = true

	# THE mutation path: same call the .dialogue "do" line makes.
	var result: Dictionary = s1_station.request_docking_via_control(s1_shuttle)
	_assert(result.get("outcome", "") == "granted", "scenario 1: mutation path issues a granted outcome")
	_assert(s1_shuttle.docking_grant != null, "scenario 1: shuttle now holds a DockingGrant")
	if result.get("outcome", "") == "granted":
		# M40 -- MediumStation now authors TWO berths (dock_main/dock_aux), so
		# the pool may hand out either one; assert membership in the station's
		# own bay set rather than pinning to _med_bay()'s specific first bay.
		var granted_slip: String = result["grant"].get("slip_id", "")
		var station_slip_ids: Array = []
		for b in _all_bays(s1_station):
			station_slip_ids.append(b.slip_id)
		_assert(granted_slip in station_slip_ids, "scenario 1: granted slip is one of the station's own bays' slip_ids")

	s1_shuttle.wants_dock = true
	s1_t = 0.0

func _step_scenario_1(delta: float) -> void:
	s1_t += delta
	if s1_bay.state == DockingBay.State.DOCKED:
		_assert(true, "scenario 1: granted shuttle reaches DOCKED via M32's gate")
		_free_if_valid(s1_shuttle); _free_if_valid(s1_station)
		_run_scenario_2_slip_allocation()
	elif s1_t > S1_TIMEOUT:
		_assert(false, "scenario 1: granted shuttle never reached DOCKED (state=%d)" % s1_bay.state)
		_free_if_valid(s1_shuttle); _free_if_valid(s1_station)
		_run_scenario_2_slip_allocation()

# ---------------------------------------------------------------------------
# Scenario 2: slip allocation -- "two requesters get two DIFFERENT open
# slips; a station that is FULLY BOOKED denies the next request" (roadmap
# item 2). M40 -- MediumStation now authors TWO docking_port bays (dock_main/
# dock_aux, "second Ironhold berth"), so a single station alone can hold two
# simultaneous requesters; a single granted request no longer proves
# fullness the way it did when there was exactly one berth. This exercises
# both axes: two requesters AT THE SAME STATION get two distinct slip_ids
# (proving the pool doesn't double-book one slip), plus a third,
# independently-provisioned station proves grants across different stations
# carry distinct (station, slip) identity -- then fills BOTH of station A's
# berths before proving a further request there is denied.
# ---------------------------------------------------------------------------
func _run_scenario_2_slip_allocation() -> void:
	print("--- Scenario 2: slip allocation (two different slips; a FULL station = no berths) ---")
	var station_a = _make_station("SlipA", PortControl.STYLE_AUTOMATED, 1)
	var bays_a: Array = _all_bays(station_a)
	var station_b = _make_station("SlipB", PortControl.STYLE_AUTOMATED, 2)

	var req1 = _make_shuttle("Req1", 70, Vector2(4000, 4000))
	var req1b = _make_shuttle("Req1b", 73, Vector2(4000, 4000))
	var req2 = _make_shuttle("Req2", 71, Vector2(4000, 4000))
	var req3 = _make_shuttle("Req3", 72, Vector2(4000, 4000))

	var g1 = station_a.request_docking_via_control(req1)
	var g1b = station_a.request_docking_via_control(req1b)
	var g2 = station_b.request_docking_via_control(req2)
	_assert(g1.get("outcome") == "granted" and g1b.get("outcome") == "granted" and g2.get("outcome") == "granted",
		"scenario 2: two requesters at station A's two berths, plus one at station B, all get granted")

	if g1.get("outcome") == "granted" and g1b.get("outcome") == "granted":
		_assert(g1["grant"]["slip_id"] != g1b["grant"]["slip_id"],
			"scenario 2: two requesters at the SAME station are assigned two DIFFERENT slips, not double-booked into one")
		var station_a_slips: Array = []
		for b in bays_a:
			station_a_slips.append(b.slip_id)
		_assert(g1["grant"]["slip_id"] in station_a_slips and g1b["grant"]["slip_id"] in station_a_slips,
			"scenario 2: both station-A grants carry one of station A's own bays' slip_ids")

	if g1.get("outcome") == "granted" and g2.get("outcome") == "granted":
		_assert(g1["grant"]["slip_id"] != g2["grant"]["slip_id"] or station_a != station_b,
			"scenario 2: grants across two different stations carry distinct (station, slip) identity")

	# A third request at station A -- now with BOTH berths reserved by
	# req1/req1b -- must be denied. This is the genuine "station is full"
	# case; with two berths, a single prior grant no longer proves it.
	var g3 = station_a.request_docking_via_control(req3)
	_assert(g3.get("outcome") == "no_berths", "scenario 2: a request at a station with BOTH berths reserved gets no_berths")

	_free_if_valid(req1); _free_if_valid(req1b); _free_if_valid(req2); _free_if_valid(req3)
	_free_if_valid(station_a); _free_if_valid(station_b)
	_run_scenario_3_discovery()

# ---------------------------------------------------------------------------
# Scenario 3: discovery. The port-control NPC appears in the transponder
# broadcast (comms_panel's actual data source) only when the ship carrying it
# is in comms range, and disappears once out of range.
# ---------------------------------------------------------------------------
var s3_station = null
var s3_ship = null
var s3_t: float = 0.0
var s3_sub_phase: int = 0

func _run_scenario_3_discovery() -> void:
	print("--- Scenario 3: NPC discovery in/out of transponder range ---")
	s3_station = _make_station("Discover1", PortControl.STYLE_AUTOMATED, 1)
	# Comms range on MediumStation's comms components is 30000 (medium_station.gd).
	s3_ship = _make_shuttle("S3Ship", 80, Vector2(5000, 0))  # well within range
	s3_t = 0.0
	s3_sub_phase = 0

# A Ship is a RigidBody2D -- writing `.position` directly gets clobbered next
# physics tick when the physics server syncs its own transform back onto the
# node (same trap test_port_zone.gd documents). Teleport through
# PhysicsServer2D directly so the move actually sticks.
func _teleport(ship, pos: Vector2) -> void:
	var xform: Transform2D = ship.global_transform
	xform.origin = pos
	PhysicsServer2D.body_set_state(ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	ship.position = pos

func _npc_visible(receiver, name_substr: String) -> bool:
	for t_id in receiver.active_transponders.keys():
		var t_data = receiver.active_transponders[t_id]
		for npc in t_data.get("npcs", []):
			if name_substr in String(npc.get("name", "")):
				_assert(npc.get("dialogue_path", "") != "", "scenario 3: broadcast NPC carries a non-empty dialogue_path")
				_assert(npc.has("tier"), "scenario 3: broadcast NPC carries a tier field")
				return true
	return false

func _step_scenario_3(delta: float) -> void:
	s3_t += delta
	match s3_sub_phase:
		0:
			if s3_t > 0.3:
				_assert(_npc_visible(s3_ship, "Control"), "scenario 3: port-control NPC visible in range (5000u, range 30000u)")
				_teleport(s3_ship, Vector2(50000, 0))  # push well outside comms range
				s3_sub_phase = 1
				s3_t = 0.0
		1:
			if s3_t > 0.3:
				_assert(not _npc_visible(s3_ship, "Control"), "scenario 3: port-control NPC no longer visible once out of comms range")
				_free_if_valid(s3_ship); _free_if_valid(s3_station)
				_run_scenario_4_fast_path_parity()

# ---------------------------------------------------------------------------
# Scenario 4: fast-path/dialogue parity. Both routes call
# request_docking_via_control() (PortControl.request_docking() underneath) --
# prove they're the literal same call by driving BOTH the DockingControl
# button and a direct "dialogue-equivalent" call against twin stations set up
# identically, and comparing outcome shape.
# ---------------------------------------------------------------------------
func _run_scenario_4_fast_path_parity() -> void:
	print("--- Scenario 4: fast-path button vs dialogue-equivalent mutation parity ---")
	var station_fast = _make_station("Parity", PortControl.STYLE_AUTOMATED, 1)
	var ship_fast = _make_shuttle("FastShuttle", 90, Vector2(4000, 4000))

	var control := DockingControl.new()
	main_node.add_child(control)
	control.player_ship = ship_fast
	control.target_station = station_fast
	control.refresh()
	_assert(control.text == "REQUEST DOCKING", "scenario 4: control reads 'REQUEST DOCKING' before any grant")

	# Note: GDScript lambdas capture locals by VALUE at connect-time, not by
	# reference, so a `func(o): got_outcome = o` closure would silently never
	# update an outer local -- inspect the button press's real side effect on
	# the ship instead (ship_fast.docking_grant), which is unambiguous.
	control._on_pressed()

	_assert(ship_fast.docking_grant != null, "scenario 4: fast-path button issues a granted outcome (ship now holds a grant)")
	_assert(ship_fast.wants_dock == true, "scenario 4: fast-path button raises wants_dock (surfaces clearance / flies the capture)")

	# The dialogue mutation calls the exact same station method -- prove a
	# second station (twin setup) produces the SAME outcome SHAPE via the
	# literal method the .dialogue "do" line invokes.
	var station_dlg = _make_station("ParityDlg", PortControl.STYLE_AUTOMATED, 2)
	var ship_dlg = _make_shuttle("DlgShuttle", 91, Vector2(4000, 4000))
	var dlg_result: Dictionary = station_dlg.request_docking_via_control(ship_dlg)
	_assert(dlg_result.get("outcome", "") == "granted", "scenario 4: dialogue-path mutation issues a granted outcome")
	_assert(dlg_result["grant"].keys() == ship_fast.docking_grant.keys(),
		"scenario 4: both routes' grants carry the same field shape")

	_free_if_valid(control)
	_free_if_valid(ship_fast); _free_if_valid(station_fast)
	_free_if_valid(ship_dlg); _free_if_valid(station_dlg)
	_run_scenario_5_context_flip()

# ---------------------------------------------------------------------------
# Scenario 5: context flip. DockingControl reads "REQUEST DOCKING" when
# clear, flips to "UNDOCK" once actually captured (docking_bay != null,
# DOCKED), and pressing Undock drives M32's request_undock() to EMPTY.
# ---------------------------------------------------------------------------
var s5_station = null
var s5_shuttle = null
var s5_bay = null
var s5_control = null
var s5_t: float = 0.0
var s5_sub_phase: int = 0
const S5_TIMEOUT := 12.0

func _run_scenario_5_context_flip() -> void:
	print("--- Scenario 5: context-flip button text + undock behavior ---")
	s5_station = _make_station("Flip1", PortControl.STYLE_AUTOMATED, 1)
	s5_bay = _med_bay(s5_station)

	var fwd: Vector2 = Vector2.RIGHT.rotated(s5_bay.global_rotation)
	s5_shuttle = _make_shuttle("S5Shuttle", 95, s5_bay.global_position + fwd * 200.0)
	s5_shuttle.dockable = true
	s5_shuttle.manual_undock = true

	s5_control = DockingControl.new()
	main_node.add_child(s5_control)
	s5_control.player_ship = s5_shuttle
	s5_control.target_station = s5_station
	s5_control.refresh()
	_assert(s5_control.text == "REQUEST DOCKING", "scenario 5: reads 'REQUEST DOCKING' before docking")

	var result: Dictionary = s5_station.request_docking_via_control(s5_shuttle)
	_assert(result.get("outcome") == "granted", "scenario 5: setup grant issued")
	s5_shuttle.wants_dock = true
	s5_t = 0.0
	s5_sub_phase = 0

func _step_scenario_5(delta: float) -> void:
	s5_t += delta
	match s5_sub_phase:
		0:
			if s5_bay.state == DockingBay.State.DOCKED:
				s5_control.refresh()
				_assert(s5_control.text == "UNDOCK", "scenario 5: control flips to 'UNDOCK' once DOCKED")
				s5_control._on_pressed()  # press Undock
				s5_sub_phase = 1
				s5_t = 0.0
			elif s5_t > S5_TIMEOUT:
				_assert(false, "scenario 5: never reached DOCKED to test the flip")
				_finish_scenario_5()
		1:
			if s5_t > 1.5:
				_assert(s5_bay.state == DockingBay.State.EMPTY, "scenario 5: Undock press drives the bay to EMPTY")
				s5_control.refresh()
				_assert(s5_control.text == "REQUEST DOCKING", "scenario 5: control flips back to 'REQUEST DOCKING' after undock")
				_finish_scenario_5()

func _finish_scenario_5() -> void:
	_free_if_valid(s5_control)
	_free_if_valid(s5_shuttle); _free_if_valid(s5_station)
	_run_scenario_6_style_degradation()

# ---------------------------------------------------------------------------
# Scenario 6: per-style degradation.
#   AUTOMATED -- grants on the first request.
#   MINIMAL -- stalls (deterministic counter, not RNG) then a re-request
#              succeeds.
#   STAFFED -- surfaces a personal NPC name (not "...Control") and still
#              yields a valid grant.
# ---------------------------------------------------------------------------
func _run_scenario_6_style_degradation() -> void:
	print("--- Scenario 6: per-style degradation (AUTOMATED/MINIMAL/STAFFED) ---")

	# AUTOMATED: grants immediately.
	var auto_station = _make_station("Auto6", PortControl.STYLE_AUTOMATED, 1)
	var auto_ship = _make_shuttle("Auto6Ship", 100, Vector2(4000, 4000))
	var auto_result = auto_station.request_docking_via_control(auto_ship)
	_assert(auto_result.get("outcome") == "granted", "scenario 6: AUTOMATED grants on the first request")

	# MINIMAL: first request stalls (deterministic), second succeeds. Each test
	# station is a fresh instance (fresh instance_id), so PortControl's
	# per-station stall counter never leaks in from an earlier scenario.
	var min_station = _make_station("Minimal6", PortControl.STYLE_MINIMAL, 2)
	var min_ship = _make_shuttle("Min6Ship", 101, Vector2(4000, 4000))
	var min_result_1 = min_station.request_docking_via_control(min_ship)
	_assert(min_result_1.get("outcome") == "stalled", "scenario 6: MINIMAL stalls on the first request (deterministic, no grant issued)")
	_assert(min_ship.docking_grant == null, "scenario 6: a stalled MINIMAL request issues no grant")
	var min_result_2 = min_station.request_docking_via_control(min_ship)
	_assert(min_result_2.get("outcome") == "granted", "scenario 6: MINIMAL re-request after the stall succeeds")

	# STAFFED: personal name (not "...Control"), still grants.
	var staffed_station = _make_station("Staffed6", PortControl.STYLE_STAFFED, 3)
	var staffed_name: String = PortControl.get_controller_name(staffed_station)
	_assert(not staffed_name.ends_with("Control"), "scenario 6: STAFFED surfaces a personal name, not '...Control' (got '%s')" % staffed_name)
	_assert(not staffed_station.available_npcs.is_empty() and staffed_station.available_npcs[0].character_name == staffed_name,
		"scenario 6: STAFFED station's broadcast NPC name matches the personal dockmaster name")
	var staffed_ship = _make_shuttle("Staffed6Ship", 102, Vector2(4000, 4000))
	var staffed_result = staffed_station.request_docking_via_control(staffed_ship)
	_assert(staffed_result.get("outcome") == "granted", "scenario 6: STAFFED still yields a valid grant")

	_free_if_valid(auto_ship); _free_if_valid(auto_station)
	_free_if_valid(min_ship); _free_if_valid(min_station)
	_free_if_valid(staffed_ship); _free_if_valid(staffed_station)
	_finalize()

func _physics_process(delta: float) -> void:
	if finished:
		return
	if s1_station != null and s1_shuttle != null and is_instance_valid(s1_shuttle):
		_step_scenario_1(delta)
	elif s3_station != null and s3_ship != null and is_instance_valid(s3_ship):
		_step_scenario_3(delta)
	elif s5_station != null and s5_shuttle != null and is_instance_valid(s5_shuttle):
		_step_scenario_5(delta)

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_port_control_comms <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_port_control_comms <<<")
		get_tree().quit(1)

