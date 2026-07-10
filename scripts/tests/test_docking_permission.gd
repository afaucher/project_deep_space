extends Node

# M32 acceptance -- docking permission model
# (implementation_plans/m31_m36_port_authority_roadmap.md, M32 section).
# setup() runs the synchronous ISSUANCE checks (grant/deny/slip/pool); the
# physics-stepped phases below cover the behavioral lifecycle the plan called
# for: grant -> capture -> DOCKED, player-initiated undock round-trip, grant
# expiry (timeout AND zone-exit), the specific-slip gate, and the any-open gate.
# Phase-driven synchronous machine (same style as test_docking / test_collision_damage).

const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var phase: String = ""
var t: float = 0.0

# Per-phase scratch
var station = null
var bay = null
var shuttle = null
var docked_seen: bool = false
var dock_time: float = -1.0
var undock_fired: bool = false
var undock_speed_at_fire: float = 0.0

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

func setup(main) -> void:
	main_node = main
	print("Starting Docking Permission (M32) Tests")

	# --- Issuance (synchronous) ---
	# Open station: no port_zone -> issuance returns null (permissionless).
	var small = SmallStation.new()
	small.name = "IssueSmall"
	main_node.add_child(small)
	var s1 = CargoShuttle.new(); s1.owner_id = 50; main_node.add_child(s1)
	_assert(small.issue_docking_grant(s1) == null, "open station returns null grant (permissionless)")
	_free_if_valid(s1); _free_if_valid(small)

	# Controlled station: issues a valid assigned grant per free berth
	# (MediumStation authors TWO docking_port bays, M40 "second Ironhold
	# berth" -- see medium_station.gd's dock_main/dock_aux). A request is only
	# denied once BOTH berths' slips are reserved (shared-pool, no
	# double-book).
	var med = MediumStation.new()
	med.name = "IssueMed"
	main_node.add_child(med)
	var s2 = CargoShuttle.new(); s2.owner_id = 51; main_node.add_child(s2)
	var g2 = med.issue_docking_grant(s2)
	_assert(g2 != null, "controlled station issues a valid grant")
	if g2 != null:
		_assert(g2.get("holder") == 51, "grant holder matches ship owner_id")
		_assert(g2.get("slip_id") != "" and typeof(g2.get("slip_id")) == TYPE_STRING, "assigned policy stamps a non-empty string slip_id")
	var s3 = CargoShuttle.new(); s3.owner_id = 52; main_node.add_child(s3)
	var g3 = med.issue_docking_grant(s3)
	_assert(g3 != null, "second grant issued -- the station's other berth is still free")
	if g2 != null and g3 != null:
		_assert(g2.get("slip_id") != g3.get("slip_id"), "the two requesters are assigned two DIFFERENT slips, not double-booked into one")
	var s4 = CargoShuttle.new(); s4.owner_id = 53; main_node.add_child(s4)
	_assert(med.issue_docking_grant(s4) == null, "third grant denied -- both berths' slips already reserved (pool, no double-book)")
	_free_if_valid(s2); _free_if_valid(s3); _free_if_valid(s4); _free_if_valid(med)

	_start_dock_undock()

# ---------------------------------------------------------------------------
# Phase 1: grant -> capture -> DOCKED, then player-initiated undock round-trip.
# A shuttle with a valid grant + wants_dock docks at Ironhold; manual_undock
# keeps it clamped PAST dock_duration (no auto-release); request_undock() then
# drops the clamp and pushes it clear (bay -> EMPTY).
# ---------------------------------------------------------------------------
const DOCK_TIMEOUT := 18.0

func _start_dock_undock() -> void:
	phase = "dock_undock"
	t = 0.0
	docked_seen = false
	dock_time = -1.0
	undock_fired = false
	print("--- Phase 1: grant -> DOCKED -> hold -> undock ---")
	station = MediumStation.new()
	station.name = "Ironhold"
	station.owner_id = 1
	station.position = Vector2.ZERO
	main_node.add_child(station)
	bay = _med_bay(station)
	_assert(bay != null, "phase 1: MediumStation grows a DockingBay")
	if bay == null:
		_start_timeout_expiry(); return

	shuttle = CargoShuttle.new()
	shuttle.name = "Docker"
	shuttle.owner_id = 60
	shuttle.iff_tags = ["TEAM_PLAYER"]
	# In the bay's approach hemisphere (+Y of the port), within capture_radius.
	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	shuttle.position = bay.global_position + fwd * 400.0
	shuttle.dockable = true
	shuttle.wants_dock = true
	shuttle.manual_undock = true   # hold until we say undock
	main_node.add_child(shuttle)
	# A valid assigned grant for this station's slip.
	shuttle.docking_grant = {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": bay.slip_id, "time_left": 300.0}

func _phase_dock_undock(delta: float) -> void:
	t += delta
	if not is_instance_valid(bay) or not is_instance_valid(shuttle):
		_assert(false, "phase 1: bay/shuttle freed unexpectedly"); _start_timeout_expiry(); return

	if not docked_seen:
		if bay.state == DockingBay.State.DOCKED:
			docked_seen = true
			dock_time = t
			_assert(true, "phase 1: shuttle reached DOCKED with a valid grant")
		elif t > DOCK_TIMEOUT:
			_assert(false, "phase 1: never reached DOCKED (state=%d)" % bay.state)
			_free_if_valid(shuttle); _free_if_valid(station); _start_timeout_expiry()
		return

	# Docked. Confirm it HOLDS past dock_duration (manual_undock), then undock.
	if not undock_fired:
		if t > dock_time + bay.dock_duration + 1.0:
			_assert(bay.state == DockingBay.State.DOCKED, "phase 1: manual_undock holds DOCKED past dock_duration (no auto-release)")
			undock_speed_at_fire = shuttle.linear_velocity.length()
			shuttle.request_undock()
			undock_fired = true
		return

	# Give the release + push a couple frames to register.
	if t > dock_time + bay.dock_duration + 1.3:
		_assert(bay.state == DockingBay.State.EMPTY, "phase 1: request_undock releases the bay (-> EMPTY)")
		_assert(shuttle.docking_bay == null, "phase 1: undock clears the ship's docking_bay claim")
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_timeout_expiry()

# ---------------------------------------------------------------------------
# Phase 2: timeout expiry. A grant holder sitting INSIDE the zone (so the
# zone-exit path doesn't fire) but not docking counts its grant down; when
# time_left hits zero the grant clears.
# ---------------------------------------------------------------------------
func _start_timeout_expiry() -> void:
	phase = "timeout"
	t = 0.0
	print("--- Phase 2: grant timeout expiry ---")
	station = MediumStation.new()
	station.owner_id = 1
	station.position = Vector2.ZERO
	main_node.add_child(station)
	shuttle = CargoShuttle.new()
	shuttle.owner_id = 61
	shuttle.position = Vector2(6000, 0)   # inside the 8000u zone, outside capture_radius
	shuttle.wants_dock = false            # don't dock -- we want the unfulfilled countdown
	main_node.add_child(shuttle)
	shuttle.docking_grant = {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "", "time_left": 0.2}

func _phase_timeout(delta: float) -> void:
	t += delta
	if shuttle.docking_grant == null:
		_assert(t <= 1.0, "phase 2: grant timed out promptly (t=%.2f)" % t)
		_assert(true, "phase 2: grant cleared on time_left timeout")
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_zone_exit()
	elif t > 2.0:
		_assert(false, "phase 2: grant never timed out (time_left=%.2f)" % shuttle.docking_grant.get("time_left", -1.0))
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_zone_exit()

# ---------------------------------------------------------------------------
# Phase 3: zone-exit expiry. A grant holder OUTSIDE the zone loses the grant
# even with time_left to spare.
# ---------------------------------------------------------------------------
func _start_zone_exit() -> void:
	phase = "zone_exit"
	t = 0.0
	print("--- Phase 3: grant zone-exit expiry ---")
	station = MediumStation.new()
	station.owner_id = 1
	station.position = Vector2.ZERO
	main_node.add_child(station)
	shuttle = CargoShuttle.new()
	shuttle.owner_id = 62
	shuttle.position = Vector2(12000, 0)   # OUTSIDE the 8000u zone
	main_node.add_child(shuttle)
	shuttle.docking_grant = {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "", "time_left": 300.0}

func _phase_zone_exit(delta: float) -> void:
	t += delta
	if shuttle.docking_grant == null:
		_assert(true, "phase 3: grant cleared on leaving the zone (time_left was 300)")
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_specific_slip()
	elif t > 1.0:
		_assert(false, "phase 3: grant survived outside the zone (should have zone-expired)")
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_specific_slip()

# ---------------------------------------------------------------------------
# Phase 4: specific-slip gate. A grant assigned to a DIFFERENT slip than the
# bay carries must NOT be captured (the assigned-slip branch of the gate).
# ---------------------------------------------------------------------------
func _start_specific_slip() -> void:
	phase = "specific_slip"
	t = 0.0
	print("--- Phase 4: specific-slip gate (wrong slip -> no capture) ---")
	station = MediumStation.new()
	station.owner_id = 1
	station.position = Vector2.ZERO
	main_node.add_child(station)
	bay = _med_bay(station)
	shuttle = CargoShuttle.new()
	shuttle.owner_id = 63
	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	shuttle.position = bay.global_position + fwd * 400.0
	shuttle.dockable = true
	shuttle.wants_dock = true
	main_node.add_child(shuttle)
	# Grant assigned to a slip that does NOT match this bay -> gate must reject.
	shuttle.docking_grant = {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "not_a_real_slip", "time_left": 300.0}

func _phase_specific_slip(delta: float) -> void:
	t += delta
	if t > 3.0:
		_assert(bay.state == DockingBay.State.EMPTY, "phase 4: bay ignores a grant assigned to a different slip (state=%d)" % bay.state)
		_free_if_valid(shuttle); _free_if_valid(station)
		_start_any_open()

# ---------------------------------------------------------------------------
# Phase 5: any-open gate. With slip_policy=any_open the grant carries slip_id=""
# and ANY free bay captures the holder.
# ---------------------------------------------------------------------------
func _start_any_open() -> void:
	phase = "any_open"
	t = 0.0
	print("--- Phase 5: any-open gate (slip_id='' -> any free bay) ---")
	station = MediumStation.new()
	station.owner_id = 1
	station.position = Vector2.ZERO
	station.slip_policy = "any_open"
	main_node.add_child(station)
	bay = _med_bay(station)
	shuttle = CargoShuttle.new()
	shuttle.owner_id = 64
	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	shuttle.position = bay.global_position + fwd * 400.0
	shuttle.dockable = true
	shuttle.wants_dock = true
	main_node.add_child(shuttle)
	shuttle.docking_grant = {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "", "time_left": 300.0}

func _phase_any_open(delta: float) -> void:
	t += delta
	if bay.state == DockingBay.State.CAPTURING or bay.state == DockingBay.State.DOCKED:
		_assert(true, "phase 5: any-open grant captured by a free bay (state=%d)" % bay.state)
		_free_if_valid(shuttle); _free_if_valid(station)
		_finalize()
	elif t > 6.0:
		_assert(false, "phase 5: any-open grant never captured (state=%d)" % bay.state)
		_free_if_valid(shuttle); _free_if_valid(station)
		_finalize()

func _physics_process(delta: float) -> void:
	if finished:
		return
	match phase:
		"dock_undock": _phase_dock_undock(delta)
		"timeout": _phase_timeout(delta)
		"zone_exit": _phase_zone_exit(delta)
		"specific_slip": _phase_specific_slip(delta)
		"any_open": _phase_any_open(delta)

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_permission <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_permission <<<")
		get_tree().quit(1)
