extends Node

# M53c Phase A acceptance (implementation_plans/m53c_demand_routing.md
# "Phase A -- Station economy state"). Unit-level checks of the converter/
# sink/source mechanism, the (location, holder) keying, and the urgency read
# -- everything EXCEPT the home cluster's own authored reference-table
# numbers, which live in test_station_economy_reference.gd (kept separate
# since that one drives the full HomeCluster.build() and is a much bigger
# fixture). All sub-tests but F run synchronously against a bare
# ClusterManager used purely as a records container (director.tick() is
# called directly, bypassing ClusterManager.tick()'s own promote/demote pass
# -- not needed for these, and would require a live hull for no reason). F
# specifically drives ClusterManager.tick() under configure_bubble() with a
# far viewpoint, per the plan's explicit requirement that the economy must
# advance for a DORMANT station (see test_cluster_bubble.gd/
# test_registry_survives_demote.gd for the same pattern). Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_station_economy

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")

var main_node: Node = null
var failures: Array = []

const EPS := 0.0005

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _approx(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < EPS, "%s (expected %.4f, got %.4f)" % [msg, b, a])

func _mk_station(id: int, pos: Vector2 = Vector2.ZERO) -> ClusterEntity:
	var rec := ClusterEntity.new()
	rec.id = id
	rec.hull_script = SmallStation
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
	rec.pos = pos
	StationEconomy.ensure_holder(rec, "self")
	return rec

func _set_bin(rec, holder: String, commodity: String, stock: float, capacity: float, target: float = -1.0, surplus_line: float = -1.0) -> void:
	var bin: Dictionary = rec.stocks[holder][commodity]
	bin["stock"] = stock
	bin["capacity"] = capacity
	bin["target"] = target if target >= 0.0 else capacity * 0.5
	bin["surplus_line"] = surplus_line if surplus_line >= 0.0 else capacity * 0.85

func setup(main) -> void:
	main_node = main
	print("Starting Station Economy (M53c Phase A) Tests")

	_test_bins_fully_populated()
	_test_converter_starves()
	_test_converter_blocks_and_stops_input()
	_test_partial_running_and_floor()
	_test_stalled_converter_consumes_nothing_sink_still_drains()
	_test_dormant_station_ticks()
	_test_clamps_and_urgency()
	_test_party_holder_separate_bin()

	_finalize()

# ---------------------------------------------------------------------------
# A. Bins fully populated for all four commodity classes at load, zeros
# included -- both via ClusterLoader (the real authoring path) and via a
# partially-authored "economy" dict (Drift-Market-shaped: only 3 of 4
# commodities mentioned).
# ---------------------------------------------------------------------------

func _test_bins_fully_populated() -> void:
	var def := ClusterDef.new()
	def.bounds = Rect2(-500000, -500000, 1000000, 1000000)
	def.add_entity({
		"id": 900, "name": "No-Economy Station", "hull": SmallStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2.ZERO, "is_static": true,
	})
	def.add_entity({
		"id": 901, "name": "Partial Station", "hull": SmallStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(1000, 0), "is_static": true,
		"economy": {"bins": {Commodity.VOLATILES: {"stock": 5.0, "capacity": 40.0}}},
	})
	var m := ClusterManager.new()
	ClusterLoader.load_into(def, m)

	var rec_no_econ = m.records[0]
	_assert(rec_no_econ.stocks.has("self"), "A: a station with no 'economy' key still gets stocks['self']")
	for c in Commodity.ALL:
		var has_bin: bool = rec_no_econ.stocks.get("self", {}).has(c)
		_assert(has_bin, "A: no-economy station's 'self' bins include %s" % c)
		if has_bin:
			var bin: Dictionary = rec_no_econ.stocks["self"][c]
			_assert(bin.get("stock", -1.0) == 0.0 and bin.get("capacity", -1.0) == 0.0,
				"A: no-economy station's %s bin is zeroed, not missing fields" % c)

	var rec_partial = m.records[1]
	_assert(rec_partial.stocks["self"][Commodity.VOLATILES]["stock"] == 5.0,
		"A: partial economy's authored VOLATILES override applied")
	for c in [Commodity.ORE, Commodity.REFINED, Commodity.GOODS]:
		var bin2: Dictionary = rec_partial.stocks["self"][c]
		_assert(bin2.get("stock", -1.0) == 0.0 and bin2.get("capacity", -1.0) == 0.0,
			"A: partial economy's unmentioned %s bin still fully populated at zero (not missing)" % c)

# ---------------------------------------------------------------------------
# B. Converter STARVES when input is withheld -- output stops entirely, and
# the reported reason is STARVED (not BLOCKED).
# ---------------------------------------------------------------------------

func _test_converter_starves() -> void:
	var rec := _mk_station(910)
	_set_bin(rec, "self", Commodity.ORE, 0.0, 100.0)       # no ore at all
	_set_bin(rec, "self", Commodity.REFINED, 20.0, 100.0)  # plenty of headroom
	rec.industry["converters"] = [
		{"in": {Commodity.ORE: 10.0}, "out": {Commodity.REFINED: 5.0}, "rate": 1.0},
	]
	var cluster := ClusterManager.new()
	cluster.add_record(rec)
	var econ := StationEconomy.new({"policy_period": 3600.0})   # 1 tick = 1 hour, so rates == lots-per-pass
	econ.tick(3600.0, cluster)

	var conv: Dictionary = rec.industry["converters"][0]
	_assert(conv.get("state", -1) == StationEconomy.ConverterState.STARVED, "B: converter reports STARVED when ORE is withheld")
	_approx(conv.get("achieved", -1.0), 0.0, "B: achieved throughput is zero while STARVED")
	_approx(rec.stocks["self"][Commodity.REFINED]["stock"], 20.0, "B: REFINED output did not move -- STARVED stops production")

# ---------------------------------------------------------------------------
# C. Converter BLOCKS when the output bin is full -- and ORE consumption
# stops WITH it (backpressure reaching the input side, per the design doc).
# ---------------------------------------------------------------------------

func _test_converter_blocks_and_stops_input() -> void:
	var rec := _mk_station(911)
	_set_bin(rec, "self", Commodity.ORE, 100.0, 100.0)      # plenty of ore
	_set_bin(rec, "self", Commodity.REFINED, 100.0, 100.0)  # output bin already full
	rec.industry["converters"] = [
		{"in": {Commodity.ORE: 10.0}, "out": {Commodity.REFINED: 5.0}, "rate": 1.0},
	]
	var cluster := ClusterManager.new()
	cluster.add_record(rec)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	econ.tick(3600.0, cluster)

	var conv: Dictionary = rec.industry["converters"][0]
	_assert(conv.get("state", -1) == StationEconomy.ConverterState.BLOCKED, "C: converter reports BLOCKED when REFINED bin is full")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], 100.0, "C: ORE was NOT consumed -- BLOCKED stops input draw too (backpressure)")
	_approx(rec.stocks["self"][Commodity.REFINED]["stock"], 100.0, "C: REFINED stayed at capacity, no overflow")

# ---------------------------------------------------------------------------
# D. Partial running scales to the scarcest input; below the floor fraction
# it is zero (not a trickle).
# ---------------------------------------------------------------------------

func _test_partial_running_and_floor() -> void:
	# D1: 60% of the ore a full pass needs -> 60% achieved, scaled consumption/production.
	var rec := _mk_station(912)
	_set_bin(rec, "self", Commodity.ORE, 6.0, 100.0)     # needs 10.0 for a full pass -> 60%
	_set_bin(rec, "self", Commodity.REFINED, 0.0, 100.0) # ample headroom
	rec.industry["converters"] = [
		{"in": {Commodity.ORE: 10.0}, "out": {Commodity.REFINED: 5.0}, "rate": 1.0},
	]
	var cluster := ClusterManager.new()
	cluster.add_record(rec)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	econ.tick(3600.0, cluster)

	var conv: Dictionary = rec.industry["converters"][0]
	_assert(conv.get("state", -1) == StationEconomy.ConverterState.RUNNING, "D1: partial running still reports RUNNING")
	_approx(conv.get("achieved", -1.0), 0.6, "D1: achieved fraction scales to the scarcest input")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], 0.0, "D1: ORE drawn down proportionally to achieved (6.0 - 6.0)")
	_approx(rec.stocks["self"][Commodity.REFINED]["stock"], 3.0, "D1: REFINED produced proportionally to achieved (5.0 * 0.6)")

	# D2: 3% of a full pass's ore -- below the floor, must be zero, not a trickle.
	var rec2 := _mk_station(913)
	_set_bin(rec2, "self", Commodity.ORE, 0.3, 100.0)      # 0.3 / 10.0 = 3%
	_set_bin(rec2, "self", Commodity.REFINED, 0.0, 100.0)
	rec2.industry["converters"] = [
		{"in": {Commodity.ORE: 10.0}, "out": {Commodity.REFINED: 5.0}, "rate": 1.0},
	]
	var cluster2 := ClusterManager.new()
	cluster2.add_record(rec2)
	econ.tick(3600.0, cluster2)

	var conv2: Dictionary = rec2.industry["converters"][0]
	_approx(conv2.get("achieved", -1.0), 0.0, "D2: below-floor throughput snaps to zero, not a 3% trickle")
	_approx(rec2.stocks["self"][Commodity.ORE]["stock"], 0.3, "D2: below-floor -> NO ore consumed at all")
	_approx(rec2.stocks["self"][Commodity.REFINED]["stock"], 0.0, "D2: below-floor -> NO refined produced at all")

# ---------------------------------------------------------------------------
# E. A stalled converter consumes NOTHING, while the population sink keeps
# draining regardless (two independent mechanisms).
# ---------------------------------------------------------------------------

func _test_stalled_converter_consumes_nothing_sink_still_drains() -> void:
	var rec := _mk_station(914)
	_set_bin(rec, "self", Commodity.ORE, 0.0, 100.0)        # STARVED
	_set_bin(rec, "self", Commodity.REFINED, 0.0, 100.0)
	_set_bin(rec, "self", Commodity.VOLATILES, 10.0, 100.0)
	rec.industry["converters"] = [
		{"in": {Commodity.ORE: 10.0}, "out": {Commodity.REFINED: 5.0}, "rate": 1.0},
	]
	rec.industry["sinks"] = {Commodity.VOLATILES: 2.0}
	var cluster := ClusterManager.new()
	cluster.add_record(rec)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	econ.tick(3600.0, cluster)

	_approx(rec.stocks["self"][Commodity.ORE]["stock"], 0.0, "E: stalled converter's input untouched (still 0, no negative draw attempted)")
	_approx(rec.stocks["self"][Commodity.REFINED]["stock"], 0.0, "E: stalled converter's output untouched")
	_approx(rec.stocks["self"][Commodity.VOLATILES]["stock"], 8.0, "E: population sink drains VOLATILES regardless of the cold converter (10.0 - 2.0)")

# ---------------------------------------------------------------------------
# F. The economy advances for a DORMANT station -- driven under
# configure_bubble() with the viewpoint far away, exactly the case that would
# silently not work if the tick were hung off a live Ship node instead of the
# ClusterEntity record.
# ---------------------------------------------------------------------------

func _test_dormant_station_ticks() -> void:
	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(10000.0, 15000.0)
	m.policy = pol
	main_node.add_child(m)

	var rec := _mk_station(915, Vector2.ZERO)
	_set_bin(rec, "self", Commodity.ORE, 0.0, 100.0)
	rec.industry["sources"] = {Commodity.ORE: 4.0}
	m.add_record(rec)

	m.directors.append(StationEconomy.new({"policy_period": 3600.0}))

	m.viewpoint = Vector2(1e9, 0)   # far away -- station must stay dormant
	m.tick(3600.0)                  # one full policy_period

	_assert(not rec.is_live(), "F: station stayed DORMANT (viewpoint is far away)")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], 4.0, "F: dormant station's ORE source still delivered (economy ticks off the record, not a live node)")

	m.queue_free()

# ---------------------------------------------------------------------------
# G. Clamps hold at both ends; urgency is 0 at target, 1 at empty/full, and
# flips direction above surplus_line.
# ---------------------------------------------------------------------------

func _test_clamps_and_urgency() -> void:
	var rec := _mk_station(916)
	_set_bin(rec, "self", Commodity.GOODS, 0.0, 100.0, 50.0, 90.0)

	_approx(StationEconomy.urgency(rec, "self", Commodity.GOODS)["value"], 1.0, "G: urgency is 1.0 at empty")
	_assert(StationEconomy.urgency(rec, "self", Commodity.GOODS)["direction"] == "IMPORT", "G: direction is IMPORT below target")

	rec.stocks["self"][Commodity.GOODS]["stock"] = 50.0
	_approx(StationEconomy.urgency(rec, "self", Commodity.GOODS)["value"], 0.0, "G: urgency is 0 exactly at target")
	_assert(StationEconomy.urgency(rec, "self", Commodity.GOODS)["direction"] == "SATISFIED", "G: satisfied at target")

	rec.stocks["self"][Commodity.GOODS]["stock"] = 95.0
	var u := StationEconomy.urgency(rec, "self", Commodity.GOODS)
	_assert(u["direction"] == "EXPORT", "G: direction flips to EXPORT above surplus_line")
	_approx(u["value"], 0.5, "G: EXPORT urgency at the midpoint between surplus_line and capacity")

	rec.stocks["self"][Commodity.GOODS]["stock"] = 100.0
	_approx(StationEconomy.urgency(rec, "self", Commodity.GOODS)["value"], 1.0, "G: urgency is 1.0 at full capacity")

	# Clamp check -- a sink whose rate would drive stock deep negative in one
	# pass must clamp to exactly 0, never overshoot.
	rec.stocks["self"][Commodity.GOODS]["stock"] = 10.0
	rec.industry["sinks"] = {Commodity.GOODS: 1000.0}
	var cluster := ClusterManager.new()
	cluster.add_record(rec)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	econ.tick(3600.0, cluster)
	_approx(rec.stocks["self"][Commodity.GOODS]["stock"], 0.0, "G: an oversized sink clamps stock to 0, never negative")

	# Clamp check -- deliver() beyond capacity clamps to capacity, never overshoots.
	var rec2 := _mk_station(917)
	_set_bin(rec2, "self", Commodity.ORE, 0.0, 20.0)
	StationEconomy.deliver(rec2, "self", Commodity.ORE, 1000.0)
	_approx(rec2.stocks["self"][Commodity.ORE]["stock"], 20.0, "G: deliver() beyond capacity clamps to capacity, never overshoots")

# ---------------------------------------------------------------------------
# H. A party holder at the same location keeps its own separate bin -- the
# regression sentinel for (location, holder) keying (design doc's trap 5).
# ---------------------------------------------------------------------------

func _test_party_holder_separate_bin() -> void:
	var rec := _mk_station(918)
	_set_bin(rec, "self", Commodity.ORE, 20.0, 100.0)

	StationEconomy.ensure_holder(rec, "PartyX")
	rec.stocks["PartyX"][Commodity.ORE]["capacity"] = 50.0
	StationEconomy.deliver(rec, "PartyX", Commodity.ORE, 15.0)

	_approx(rec.stocks["PartyX"][Commodity.ORE]["stock"], 15.0, "H: PartyX's own ORE stockpile received the delivery")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], 20.0, "H: the station's OWN 'self' bin is untouched by PartyX's delivery -- separate holder, same location")

	for c in Commodity.ALL:
		_assert(rec.stocks["PartyX"].has(c), "H: PartyX's holder entry is ALSO fully populated across all four commodities (%s)" % c)

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_station_economy <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_station_economy <<<")
		get_tree().quit(1)
