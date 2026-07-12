extends Node

# M40 acceptance -- Repair mechanism + engineering log
# (implementation_plans/m39_m44_homefront_roadmap.md, M40 section). Covers:
#   a. Docked damaged ship + begin_repairs -> component health climbs over
#      sim frames -> reaches max -> "Repairs complete" + "<id> repaired"
#      entries land in eng_log.
#   b. begin_repairs while NOT docked -> false, no healing.
#   c. Undock mid-repair -> healing stops.
#   d. begin_repairs on a hulk -> false.
#   e. Eng-log edge triggering: repeated take_damage() hits past the 50%
#      "damaged" threshold and down to 0 ("destroyed") log exactly ONE entry
#      per crossing, not one per hit; current_heat pegged at max_heat logs
#      "Thermal overload" exactly once despite staying pegged for several
#      frames.
# Phase-machine style copied from test_port_control_comms.gd (setup(main),
# _assert collecting failures, _physics_process driving phases forward on
# sim time). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_repair_services

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

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

# Every scenario gets its OWN authority string (not medium_station.gd's
# shared "Ironhold Control" default). Multiple MediumStation instances
# sharing an authority is exactly the cross-station reservation bug
# test_campaign_docking_isolation guards against -- with several stations
# alive across this file's scenarios (queue_free() is deferred, so a freed
# station/shuttle from an earlier scenario can still be group-visible for
# the rest of the same frame), a shared default authority risks one
# scenario's grant/slip bleeding into the next. Mirrors
# test_port_control_comms.gd's own _make_station() helper.
func _make_station(station_name: String, owner: int) -> Node:
	var st = MediumStation.new()
	st.name = station_name
	st.owner_id = owner
	st.iff_tags = ["TEAM_PLAYER"]
	st.position = Vector2.ZERO
	st.port_zone = {
		"radius": 8000.0,
		"authority": station_name + " Control",
		"rules": {},
	}
	main_node.add_child(st)
	return st

func _make_shuttle(shuttle_name: String, owner: int, pos: Vector2) -> Node:
	var s = CargoShuttle.new()
	s.name = shuttle_name
	s.owner_id = owner
	s.iff_tags = ["TEAM_PLAYER"]
	s.position = pos
	s.dockable = true
	main_node.add_child(s)
	return s

func setup(main) -> void:
	main_node = main
	print("Starting Repair Services (M40) Tests")
	_run_scenario_b_not_docked()
	_run_scenario_d_hulk()
	_run_scenario_a_docked_repair()

# ---------------------------------------------------------------------------
# Scenario b: begin_repairs while NOT docked -> false, no healing.
# ---------------------------------------------------------------------------
func _run_scenario_b_not_docked() -> void:
	print("--- Scenario b: begin_repairs on an undocked ship ---")
	var station = _make_station("NotDocked", 1)
	var shuttle = _make_shuttle("NotDockedShuttle", 50, Vector2(9999, 9999))

	var comp: Dictionary = shuttle.get_component("comms_array")
	comp["health"] = 5.0

	var result: bool = station.begin_repairs(shuttle)
	_assert(result == false, "scenario b: begin_repairs on an undocked ship returns false")
	_assert(not station.active_repairs.has(shuttle.get_instance_id()), "scenario b: undocked ship is never registered for repair")
	_assert(comp["health"] == 5.0, "scenario b: an undocked ship's damaged component does not heal")

	_free_if_valid(shuttle); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario d: begin_repairs on a hulk -> false.
# ---------------------------------------------------------------------------
func _run_scenario_d_hulk() -> void:
	print("--- Scenario d: begin_repairs on a hulk ---")
	var station = _make_station("HulkHost", 1)
	var shuttle = _make_shuttle("HulkShuttle", 51, Vector2(9999, 9999))

	shuttle.hulk()
	var result: bool = station.begin_repairs(shuttle)
	_assert(result == false, "scenario d: begin_repairs on a hulk returns false")
	_assert(not station.active_repairs.has(shuttle.get_instance_id()), "scenario d: a hulk is never registered for repair")

	_free_if_valid(shuttle); _free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario a: docked damaged ship + begin_repairs -> health climbs to max ->
# "Repairs complete" + "<id> repaired" eng_log entries.
# ---------------------------------------------------------------------------
var a_station = null
var a_bay = null
var a_shuttle = null
var a_comp: Dictionary = {}
var a_t: float = 0.0
var a_sub_phase: int = 0
var a_health_mid: float = -1.0
const A_DOCK_TIMEOUT := 15.0
const A_REPAIR_TIMEOUT := 15.0

func _run_scenario_a_docked_repair() -> void:
	print("--- Scenario a: docked + begin_repairs heals to max, logs completion ---")
	a_station = _make_station("RepairA", 1)
	a_bay = _med_bay(a_station)
	_assert(a_bay != null, "scenario a: station grows a DockingBay")
	if a_bay == null:
		_run_scenario_c_undock_stops_repair()
		return

	var fwd: Vector2 = Vector2.RIGHT.rotated(a_bay.global_rotation)
	a_shuttle = _make_shuttle("RepairShuttleA", 60, a_bay.global_position + fwd * 200.0)

	a_comp = a_shuttle.get_component("comms_array")
	a_comp["health"] = 5.0

	var result: Dictionary = a_station.request_docking_via_control(a_shuttle)
	_assert(result.get("outcome", "") == "granted", "scenario a: docking request granted")
	a_shuttle.wants_dock = true
	a_health_mid = -1.0
	a_t = 0.0
	a_sub_phase = 0

func _step_scenario_a(delta: float) -> void:
	a_t += delta
	match a_sub_phase:
		0:
			if a_bay.state == DockingBay.State.DOCKED:
				var began: bool = a_station.begin_repairs(a_shuttle)
				_assert(began, "scenario a: begin_repairs on a freshly-docked ship returns true")
				a_sub_phase = 1
				a_t = 0.0
			elif a_t > A_DOCK_TIMEOUT:
				_assert(false, "scenario a: shuttle never reached DOCKED (state=%d)" % a_bay.state)
				_finish_scenario_a()
		1:
			if a_t > 0.3 and a_health_mid < 0.0:
				a_health_mid = a_comp["health"]
				_assert(a_health_mid > 5.0, "scenario a: component health climbs while under repair (started 5.0, now %.1f)" % a_health_mid)
			if a_comp["health"] >= a_comp.get("max_health", 30.0):
				a_sub_phase = 2
				a_t = 0.0
			elif a_t > A_REPAIR_TIMEOUT:
				_assert(false, "scenario a: component never reached max health (health=%.1f)" % a_comp["health"])
				_finish_scenario_a()
		2:
			# Give the ship's own crossing check + the station's repair tick a
			# moment to both land their log entries.
			if a_t > 0.3:
				var has_repaired_entry := false
				var has_complete_entry := false
				for e in a_shuttle.eng_log:
					if e.get("text", "") == "comms_array repaired":
						has_repaired_entry = true
					if e.get("text", "") == "Repairs complete":
						has_complete_entry = true
				_assert(has_repaired_entry, "scenario a: eng_log has a 'comms_array repaired' entry")
				_assert(has_complete_entry, "scenario a: eng_log has a 'Repairs complete' entry")
				_assert(not a_station.active_repairs.has(a_shuttle.get_instance_id()), "scenario a: ship is unregistered from active_repairs once fully healed")
				_finish_scenario_a()

func _finish_scenario_a() -> void:
	_free_if_valid(a_shuttle); _free_if_valid(a_station)
	_run_scenario_c_undock_stops_repair()

# ---------------------------------------------------------------------------
# Scenario c: undock mid-repair stops healing.
# ---------------------------------------------------------------------------
var c_station = null
var c_bay = null
var c_shuttle = null
var c_comp: Dictionary = {}
var c_t: float = 0.0
var c_sub_phase: int = 0
var c_health_at_undock: float = -1.0
const C_DOCK_TIMEOUT := 15.0

func _run_scenario_c_undock_stops_repair() -> void:
	print("--- Scenario c: undock mid-repair stops healing ---")
	c_station = _make_station("RepairC", 2)
	c_bay = _med_bay(c_station)
	_assert(c_bay != null, "scenario c: station grows a DockingBay")
	if c_bay == null:
		_run_scenario_e_eng_log_crossings()
		return

	var fwd: Vector2 = Vector2.RIGHT.rotated(c_bay.global_rotation)
	c_shuttle = _make_shuttle("RepairShuttleC", 61, c_bay.global_position + fwd * 200.0)
	c_shuttle.manual_undock = true   # hold DOCKED until we explicitly undock

	c_comp = c_shuttle.get_component("comms_array")
	c_comp["health"] = 5.0

	var result: Dictionary = c_station.request_docking_via_control(c_shuttle)
	_assert(result.get("outcome", "") == "granted", "scenario c: docking request granted")
	c_shuttle.wants_dock = true
	c_health_at_undock = -1.0
	c_t = 0.0
	c_sub_phase = 0

func _step_scenario_c(delta: float) -> void:
	c_t += delta
	match c_sub_phase:
		0:
			if c_bay.state == DockingBay.State.DOCKED:
				var began: bool = c_station.begin_repairs(c_shuttle)
				_assert(began, "scenario c: begin_repairs on a freshly-docked ship returns true")
				c_sub_phase = 1
				c_t = 0.0
			elif c_t > C_DOCK_TIMEOUT:
				_assert(false, "scenario c: shuttle never reached DOCKED (state=%d)" % c_bay.state)
				_finish_scenario_c()
		1:
			# Let it heal partway (not to completion) before undocking.
			if c_t > 0.3:
				_assert(c_comp["health"] > 5.0, "scenario c: component healed partway before undock (health=%.1f)" % c_comp["health"])
				_assert(c_comp["health"] < c_comp.get("max_health", 30.0), "scenario c: component not yet at full health before undock")
				c_health_at_undock = c_comp["health"]
				c_shuttle.request_undock()   # DockingBay.release_with_push() is synchronous
				_assert(c_bay.state == DockingBay.State.EMPTY, "scenario c: request_undock releases the bay immediately (-> EMPTY)")
				c_sub_phase = 2
				c_t = 0.0
		2:
			if c_t > 0.5:
				_assert(not c_station.active_repairs.has(c_shuttle.get_instance_id()), "scenario c: ship is unregistered from active_repairs after undock")
				_assert(c_comp["health"] == c_health_at_undock, "scenario c: component health stopped climbing after undock (was %.1f, now %.1f)" % [c_health_at_undock, c_comp["health"]])
				_finish_scenario_c()

func _finish_scenario_c() -> void:
	_free_if_valid(c_shuttle); _free_if_valid(c_station)
	_run_scenario_e_eng_log_crossings()

# ---------------------------------------------------------------------------
# Scenario e: eng-log edge-triggered crossings.
#   - Repeated take_damage() hits that push a component below the 50%
#     "damaged" threshold, and then to 0 ("destroyed"), log exactly ONE entry
#     per crossing, not one per hit.
#   - current_heat pegged at/above max_heat logs "Thermal overload" exactly
#     once despite staying pegged across several frames.
# Uses two standalone (undocked) CargoShuttles -- no station/dock plumbing
# needed for this scenario.
# ---------------------------------------------------------------------------
var e_comp_ship = null
var e_heat_ship = null
var e_hull_comp: Dictionary = {}
var e_t: float = 0.0
var e_sub_phase: int = 0
var e_heat_frames: int = 0

func _run_scenario_e_eng_log_crossings() -> void:
	print("--- Scenario e: eng-log edge-triggered crossings (damaged/destroyed/thermal) ---")
	e_comp_ship = _make_shuttle("CrossingShip", 70, Vector2(20000, 20000))
	e_heat_ship = _make_shuttle("HeatCrossingShip", 71, Vector2(-20000, -20000))

	# CargoShuttle's FIRST component is "hull_port" (max_health 180.0) --
	# take_damage() with no pos/dir always falls back to the first hull
	# component (see Ship.take_damage()'s fallback branch), giving a
	# deterministic, repeatable target across multiple hits. Damaging only
	# this one hull plate (of five) never destroys is_sys_destroyed("hull")
	# ship-wide, so the ship never dies mid-scenario.
	e_hull_comp = e_comp_ship.get_component("hull_port")

	e_comp_ship.take_damage(95.0)   # 180 -> 85: below the 90 (50%) threshold, still alive
	e_heat_frames = 0
	e_t = 0.0
	e_sub_phase = 0

func _count_log(ship, text: String) -> int:
	var n := 0
	for e in ship.eng_log:
		if e.get("text", "") == text:
			n += 1
	return n

func _step_scenario_e(delta: float) -> void:
	e_t += delta
	# Force the heat ship pegged at max_heat every frame throughout this
	# scenario -- robust to node processing order relative to the ship's own
	# _physics_process (the heat sim would otherwise dissipate it back down).
	e_heat_ship.current_heat = e_heat_ship.max_heat
	e_heat_frames += 1

	match e_sub_phase:
		0:
			if e_t > 0.2:
				_assert(_count_log(e_comp_ship, "hull_port damaged") == 1,
					"scenario e: exactly one 'hull_port damaged' entry after crossing below 50%%")
				# Repeated hits that stay within the damaged band (still alive) must not re-log.
				e_comp_ship.take_damage(5.0)
				e_comp_ship.take_damage(5.0)
				e_sub_phase = 1
				e_t = 0.0
		1:
			if e_t > 0.2:
				_assert(_count_log(e_comp_ship, "hull_port damaged") == 1,
					"scenario e: repeated hits within the damaged band do not re-log 'damaged'")
				e_comp_ship.take_damage(200.0)   # push well past 0 -> destroyed
				e_sub_phase = 2
				e_t = 0.0
		2:
			if e_t > 0.2:
				_assert(_count_log(e_comp_ship, "hull_port destroyed") == 1,
					"scenario e: exactly one 'hull_port destroyed' entry after crossing to 0")
				e_comp_ship.take_damage(50.0)
				e_comp_ship.take_damage(50.0)
				e_sub_phase = 3
				e_t = 0.0
		3:
			if e_t > 0.2:
				_assert(_count_log(e_comp_ship, "hull_port destroyed") == 1,
					"scenario e: repeated hits after destruction do not re-log 'destroyed'")
				_assert(_count_log(e_comp_ship, "hull_port damaged") == 1,
					"scenario e: 'damaged' does not re-fire once already destroyed")
				e_sub_phase = 4
				e_t = 0.0
		4:
			if e_heat_frames > 10 and e_t > 0.2:
				_assert(_count_log(e_heat_ship, "Thermal overload -- reactor taking damage") == 1,
					"scenario e: exactly one 'Thermal overload' entry despite staying pegged at max_heat for multiple frames")
				_finish_scenario_e()

func _finish_scenario_e() -> void:
	_free_if_valid(e_comp_ship); _free_if_valid(e_heat_ship)
	_finalize()

func _physics_process(delta: float) -> void:
	if finished:
		return
	if a_station != null and a_shuttle != null and is_instance_valid(a_shuttle):
		_step_scenario_a(delta)
	elif c_station != null and c_shuttle != null and is_instance_valid(c_shuttle):
		_step_scenario_c(delta)
	elif e_comp_ship != null and e_heat_ship != null and is_instance_valid(e_comp_ship) and is_instance_valid(e_heat_ship):
		_step_scenario_e(delta)

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_repair_services <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_repair_services <<<")
		get_tree().quit(1)
