extends Node

# M53c Phase B2 acceptance (implementation_plans/m53c_demand_routing.md
# "Phase B2 -- Repair consumes stock"). Covers Ship._process_repairs gated on
# the host's own station economy (design_ideas/station_economy.md "Repair
# closes the loop: damage becomes demand"):
#   A. hull damage draws REFINED, systems damage draws GOODS (~3.3x dearer
#      per HP), at the design doc's worked ratio (1 lot ~= 500 HP hull,
#      ~= 150 HP systems).
#   B. repair stops at zero stock -- "no stock means no repair" -- and
#      resumes once stock is replenished.
#   C. a docked player's (ordinary docked ship's) repair moves the STATION's
#      own stock down -- the loop actually reaching the ledger.
#   D. station SELF-repair uses the identical path (same withdraw calls,
#      same stock) -- "stations ARE Ships... one mechanism, one ledger".
#   E. a host with NO economy record attached (every pre-Phase-B2 fixture,
#      bare Ship sandbox play) repairs UNGATED -- unchanged pre-Phase-B2
#      behavior, the regression guard for test_repair_services and friends.
#
# Phase-machine style, same as test_repair_services.gd (this file's direct
# sibling -- deliberately kept separate since Phase A/B fixtures wire a
# ClusterEntity record onto a bare station via a manually-set
# cluster_record_ref, which test_repair_services.gd's pre-Phase-B2 fixtures
# never do). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_station_repair_economy

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []

const EPS := 0.01

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _approx(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < EPS, "%s (expected %.4f, got %.4f)" % [msg, b, a])

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _med_bay(st) -> Node:
	for c in st.get_children():
		if c is DockingBay:
			return c
	return null

# A bare MediumStation.new() (test_repair_services.gd's own pattern) with a
# manually-attached ClusterEntity record -- mirrors ClusterManager._promote()'s
# `node.cluster_record_ref = weakref(rec)` exactly, without needing a full
# ClusterManager/promotion pass just to wire one field.
func _make_economy_station(station_name: String, owner: int, rec_id: int) -> Dictionary:
	var st = MediumStation.new()
	st.name = station_name
	st.owner_id = owner
	st.iff_tags = ["TEAM_PLAYER"]
	st.position = Vector2.ZERO
	st.port_zone = {"radius": 8000.0, "authority": station_name + " Control", "rules": {}}
	main_node.add_child(st)

	var rec := ClusterEntity.new()
	rec.id = rec_id
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
	StationEconomy.ensure_holder(rec, "self")
	st.cluster_record_ref = weakref(rec)

	return {"station": st, "rec": rec}

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
	print("Starting Station Repair Economy (M53c Phase B2) Tests")
	_run_scenario_e_ungated_bare_host()

# ---------------------------------------------------------------------------
# E. A host with no economy record attached repairs UNGATED -- the exact
# pre-Phase-B2 behavior, run FIRST and synchronously since it's a direct
# regression check (test_repair_services.gd already covers this at length;
# this is a cheap confirmation the new gating logic didn't change the
# no-record path).
# ---------------------------------------------------------------------------
func _run_scenario_e_ungated_bare_host() -> void:
	print("--- E: a host with no cluster record repairs ungated (unchanged pre-Phase-B2 behavior) ---")
	var st = MediumStation.new()
	st.name = "BareHost"
	st.owner_id = 1
	st.position = Vector2.ZERO
	st.port_zone = {"radius": 8000.0, "authority": "BareHost Control", "rules": {}}
	main_node.add_child(st)
	# cluster_record_ref left null -- exactly test_repair_services.gd's fixtures.

	var comp: Dictionary = st.get_component("comms_fwd") if st.has_method("get_component") else {}
	if comp.is_empty():
		_assert(false, "E: station has a comms_fwd component to damage")
		_free_if_valid(st)
		_run_scenario_a_hull_draws_refined()
		return
	comp["health"] = 1.0
	# Directly exercise the tick's healing helper without needing a live
	# docked guest -- _process_repairs's self-repair branch requires
	# stock_gated (false here), so nothing should move.
	st._process_repairs(1.0)
	_approx(comp["health"], 1.0, "E: with no record attached, self-repair does not even attempt to run (ungated path is docked-guest-only pre-Phase-B2 parity)")

	_free_if_valid(st)
	_run_scenario_a_hull_draws_refined()

# ---------------------------------------------------------------------------
# A. hull damage draws REFINED, systems damage draws GOODS, at the design
# doc's worked ratio (500 HP/lot hull, 150 HP/lot systems).
# ---------------------------------------------------------------------------
var a_station = null
var a_rec: ClusterEntity = null
var a_bay = null
var a_shuttle = null
var a_hull_comp: Dictionary = {}
var a_sys_comp: Dictionary = {}
var a_t: float = 0.0
var a_sub_phase: int = 0
const A_DOCK_TIMEOUT := 15.0

func _run_scenario_a_hull_draws_refined() -> void:
	print("--- A: docked repair draws REFINED for hull, GOODS for systems, at the 500/150 HP-per-lot ratio ---")
	var made := _make_economy_station("RepairA", 1, 960)
	a_station = made["station"]
	a_rec = made["rec"]
	# Ample stock -- this sub-test is about which BIN moves and by how much,
	# not about running out.
	a_rec.stocks["self"][Commodity.REFINED]["stock"] = 100.0
	a_rec.stocks["self"][Commodity.REFINED]["capacity"] = 100.0
	a_rec.stocks["self"][Commodity.GOODS]["stock"] = 100.0
	a_rec.stocks["self"][Commodity.GOODS]["capacity"] = 100.0

	a_bay = _med_bay(a_station)
	_assert(a_bay != null, "A: station grows a DockingBay")
	if a_bay == null:
		_finish_scenario_a(); return

	var fwd: Vector2 = Vector2.RIGHT.rotated(a_bay.global_rotation)
	a_shuttle = _make_shuttle("RepairShuttleA", 60, a_bay.global_position + fwd * 200.0)

	# hull_port is CargoShuttle's first component (type "hull"); comms_array
	# is a "comms"-type system component -- see test_repair_services.gd's own
	# use of comms_array for the systems side.
	a_shuttle.manual_undock = true   # hold DOCKED past the default dock_duration -- this scenario needs a real dwell
	a_hull_comp = a_shuttle.get_component("hull_port")
	a_sys_comp = a_shuttle.get_component("comms_array")
	a_hull_comp["health"] = 0.0
	a_sys_comp["health"] = 0.0

	var result: Dictionary = a_station.request_docking_via_control(a_shuttle)
	_assert(result.get("outcome", "") == "granted", "A: docking request granted")
	a_shuttle.wants_dock = true
	a_t = 0.0
	a_sub_phase = 0

func _step_scenario_a(delta: float) -> void:
	a_t += delta
	match a_sub_phase:
		0:
			if a_bay.state == DockingBay.State.DOCKED:
				var began: bool = a_station.begin_repairs(a_shuttle)
				_assert(began, "A: begin_repairs on a freshly-docked ship returns true")
				a_sub_phase = 1
				a_t = 0.0
			elif a_t > A_DOCK_TIMEOUT:
				_assert(false, "A: shuttle never reached DOCKED (state=%d)" % a_bay.state)
				_finish_scenario_a()
		1:
			if a_t > 0.5:
				_assert(a_hull_comp["health"] > 0.0, "A: hull component healed while docked")
				_assert(a_sys_comp["health"] > 0.0, "A: systems component healed while docked")

				var refined_drawn: float = 100.0 - a_rec.stocks["self"][Commodity.REFINED]["stock"]
				var goods_drawn: float = 100.0 - a_rec.stocks["self"][Commodity.GOODS]["stock"]
				_assert(refined_drawn > 0.0, "A: REFINED stock was drawn down by the hull repair")
				_assert(goods_drawn > 0.0, "A: GOODS stock was drawn down by the systems repair")

				# HP healed should equal lots drawn * HP-per-lot for each class.
				var expected_hull_health: float = refined_drawn * StationEconomy.HULL_HP_PER_LOT
				var expected_sys_health: float = goods_drawn * StationEconomy.SYSTEM_HP_PER_LOT
				_approx(a_hull_comp["health"], expected_hull_health, "A: hull HP healed matches REFINED lots drawn * 500 HP/lot")
				_approx(a_sys_comp["health"], expected_sys_health, "A: systems HP healed matches GOODS lots drawn * 150 HP/lot")

				# Same HP healed on both (same REPAIR_RATE*delta budget per
				# component) should draw ~3.3x more GOODS lots than REFINED
				# lots, per the design doc's stated ratio.
				if refined_drawn > 0.0:
					var ratio: float = goods_drawn / refined_drawn
					_assert(abs(ratio - (StationEconomy.HULL_HP_PER_LOT / StationEconomy.SYSTEM_HP_PER_LOT)) < 0.05,
						"A: GOODS is drawn down ~3.3x faster than REFINED for equal HP healed (ratio=%.3f)" % ratio)

				_finish_scenario_a()

func _finish_scenario_a() -> void:
	_free_if_valid(a_shuttle); _free_if_valid(a_station)
	_run_scenario_b_stops_at_zero_stock()

# ---------------------------------------------------------------------------
# B. Repair stops at zero stock (no idle draw, no free healing), then
# resumes once stock is replenished via deliver().
# ---------------------------------------------------------------------------
var b_station = null
var b_rec: ClusterEntity = null
var b_bay = null
var b_shuttle = null
var b_comp: Dictionary = {}
var b_t: float = 0.0
var b_sub_phase: int = 0
var b_health_at_stall: float = -1.0
const B_DOCK_TIMEOUT := 15.0

func _run_scenario_b_stops_at_zero_stock() -> void:
	print("--- B: repair stops at zero REFINED stock, resumes once replenished ---")
	var made := _make_economy_station("RepairB", 2, 961)
	b_station = made["station"]
	b_rec = made["rec"]
	# Enough REFINED for a little healing, then it runs out.
	b_rec.stocks["self"][Commodity.REFINED]["stock"] = 0.02   # a sliver -- a few HP worth
	b_rec.stocks["self"][Commodity.REFINED]["capacity"] = 100.0

	b_bay = _med_bay(b_station)
	_assert(b_bay != null, "B: station grows a DockingBay")
	if b_bay == null:
		_finish_scenario_b(); return

	var fwd: Vector2 = Vector2.RIGHT.rotated(b_bay.global_rotation)
	b_shuttle = _make_shuttle("RepairShuttleB", 61, b_bay.global_position + fwd * 200.0)
	b_shuttle.manual_undock = true   # hold DOCKED -- this scenario deliberately runs past the default dock_duration
	b_comp = b_shuttle.get_component("hull_port")   # hull -> REFINED
	b_comp["health"] = 0.0

	var result: Dictionary = b_station.request_docking_via_control(b_shuttle)
	_assert(result.get("outcome", "") == "granted", "B: docking request granted")
	b_shuttle.wants_dock = true
	b_t = 0.0
	b_sub_phase = 0

func _step_scenario_b(delta: float) -> void:
	b_t += delta
	match b_sub_phase:
		0:
			if b_bay.state == DockingBay.State.DOCKED:
				var began: bool = b_station.begin_repairs(b_shuttle)
				_assert(began, "B: begin_repairs on a freshly-docked ship returns true")
				b_sub_phase = 1
				b_t = 0.0
			elif b_t > B_DOCK_TIMEOUT:
				_assert(false, "B: shuttle never reached DOCKED (state=%d)" % b_bay.state)
				_finish_scenario_b()
		1:
			# Let a couple seconds pass -- the sliver of stock should exhaust
			# almost immediately (0.02 lots * 500 HP/lot = 10 HP ceiling).
			if b_t > 1.0:
				_approx(b_rec.stocks["self"][Commodity.REFINED]["stock"], 0.0, "B: REFINED stock is drained to zero, not negative")
				b_health_at_stall = b_comp["health"]
				_assert(b_health_at_stall > 0.0 and b_health_at_stall < b_comp.get("max_health", 180.0),
					"B: some healing happened before the stock ran out (health=%.2f)" % b_health_at_stall)
				b_sub_phase = 2
				b_t = 0.0
		2:
			# Stalled: no further healing with zero stock, across another beat.
			if b_t > 0.5:
				_approx(b_comp["health"], b_health_at_stall, "B: health stays PUT once stock hits zero -- no free healing")
				# Replenish -- healing must resume.
				StationEconomy.deliver(b_rec, "self", Commodity.REFINED, 10.0)
				b_sub_phase = 3
				b_t = 0.0
		3:
			if b_t > 0.5:
				_assert(b_comp["health"] > b_health_at_stall, "B: healing RESUMES once REFINED stock is replenished")
				_finish_scenario_b()

func _finish_scenario_b() -> void:
	_free_if_valid(b_shuttle); _free_if_valid(b_station)
	_run_scenario_c_docked_repair_moves_station_stock()

# ---------------------------------------------------------------------------
# C. A docked ship's repair moves the STATION's own stock down (the loop
# actually reaching the ledger -- not just component health climbing).
# ---------------------------------------------------------------------------
var c_station = null
var c_rec: ClusterEntity = null
var c_bay = null
var c_shuttle = null
var c_comp: Dictionary = {}
var c_t: float = 0.0
var c_sub_phase: int = 0
var c_initial_refined: float = -1.0

func _run_scenario_c_docked_repair_moves_station_stock() -> void:
	print("--- C: a docked ship's repair moves the station's OWN REFINED stock ---")
	var made := _make_economy_station("RepairC", 3, 962)
	c_station = made["station"]
	c_rec = made["rec"]
	c_rec.stocks["self"][Commodity.REFINED]["stock"] = 50.0
	c_rec.stocks["self"][Commodity.REFINED]["capacity"] = 100.0
	c_initial_refined = 50.0

	c_bay = _med_bay(c_station)
	_assert(c_bay != null, "C: station grows a DockingBay")
	if c_bay == null:
		_finish_scenario_c(); return

	var fwd: Vector2 = Vector2.RIGHT.rotated(c_bay.global_rotation)
	c_shuttle = _make_shuttle("RepairShuttleC", 62, c_bay.global_position + fwd * 200.0)
	c_shuttle.manual_undock = true
	c_comp = c_shuttle.get_component("hull_port")
	c_comp["health"] = 0.0

	var result: Dictionary = c_station.request_docking_via_control(c_shuttle)
	_assert(result.get("outcome", "") == "granted", "C: docking request granted")
	c_shuttle.wants_dock = true
	c_t = 0.0
	c_sub_phase = 0

func _step_scenario_c(delta: float) -> void:
	c_t += delta
	match c_sub_phase:
		0:
			if c_bay.state == DockingBay.State.DOCKED:
				var began: bool = c_station.begin_repairs(c_shuttle)
				_assert(began, "C: begin_repairs on a freshly-docked ship returns true")
				c_sub_phase = 1
				c_t = 0.0
			elif c_t > 15.0:
				_assert(false, "C: shuttle never reached DOCKED (state=%d)" % c_bay.state)
				_finish_scenario_c()
		1:
			if c_t > 0.5:
				_assert(c_rec.stocks["self"][Commodity.REFINED]["stock"] < c_initial_refined,
					"C: the station's own REFINED stock dropped as a result of the docked player's repair")
				_finish_scenario_c()

func _finish_scenario_c() -> void:
	_free_if_valid(c_shuttle); _free_if_valid(c_station)
	_run_scenario_d_self_repair()

# ---------------------------------------------------------------------------
# D. Station self-repair uses the SAME path -- a station with a damaged OWN
# component heals itself, drawing its OWN stock, with no docked guest at all.
# ---------------------------------------------------------------------------
var d_station = null
var d_rec: ClusterEntity = null
var d_comp: Dictionary = {}
var d_t: float = 0.0

func _run_scenario_d_self_repair() -> void:
	print("--- D: station self-repair uses the same path (draws its own stock, no docked guest) ---")
	var made := _make_economy_station("RepairD", 4, 963)
	d_station = made["station"]
	d_rec = made["rec"]
	d_rec.stocks["self"][Commodity.REFINED]["stock"] = 50.0
	d_rec.stocks["self"][Commodity.REFINED]["capacity"] = 100.0

	# Damage one of the STATION's own HULL components (medium_station.gd
	# authors several "hull_*_cap"/"hull_*_flank" parts, type "hull" -- must
	# be a hull-typed part so this draws REFINED, the only class this fixture
	# stocks; picking any other component type would need GOODS instead,
	# which this fixture deliberately leaves at zero).
	d_comp = d_station.get_component("hull_fwd_cap")
	_assert(not d_comp.is_empty(), "D: station has a damageable hull component")
	if d_comp.is_empty():
		_finish_scenario_d(); return
	d_comp["health"] = 0.0
	d_t = 0.0

func _step_scenario_d(delta: float) -> void:
	d_t += delta
	if d_t > 0.5:
		_assert(d_comp["health"] > 0.0, "D: the station's OWN component healed with no docked guest at all")
		_assert(d_rec.stocks["self"][Commodity.REFINED]["stock"] < 50.0, "D: self-repair drew down the station's OWN REFINED stock")
		_finish_scenario_d()

func _finish_scenario_d() -> void:
	_free_if_valid(d_station)
	_finalize()

func _physics_process(delta: float) -> void:
	if a_station != null and a_shuttle != null and is_instance_valid(a_shuttle):
		_step_scenario_a(delta)
	elif b_station != null and b_shuttle != null and is_instance_valid(b_shuttle):
		_step_scenario_b(delta)
	elif c_station != null and c_shuttle != null and is_instance_valid(c_shuttle):
		_step_scenario_c(delta)
	elif d_station != null and is_instance_valid(d_station):
		_step_scenario_d(delta)

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_station_repair_economy <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_station_repair_economy <<<")
		get_tree().quit(1)
