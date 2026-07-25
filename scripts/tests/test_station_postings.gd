extends Node

# M53c Phase B acceptance (implementation_plans/m53c_demand_routing.md
# "Phase B -- Postings (stations publish)"). Covers the posting shape built on
# top of Phase A's bins/urgency (scripts/directors/station_economy.gd):
#   A. a posting appears when stock crosses the threshold and closes (returns
#      {}) once satisfied.
#   B. quantity depletes as served, via ordinary stock movement -- not a
#      separate exclusive-claim counter -- so several servers can work one
#      posting.
#   C. payout is FIXED at acceptance, not recomputed on arrival.
#   D. price varies by asker (own-flag vs foreign multiplier); urgency stays
#      IDENTICAL across both calls -- principle 9's regression sentinel.
#   E. eligibility -- the real Coldreach VOLATILES case (home_cluster.gd):
#      a foreign-flag hull cannot take the restricted posting, a Meridian
#      hull can.
#   F. port control composes for free: a ship that never reached DOCKED at a
#      host (the HOSTILE-denied-a-berth case, port control's existing
#      admission machinery) cannot serve that host's posting via
#      Ship.serve_posting() -- no new standing-specific code, same gate
#      begin_repairs() already uses.
#
# A-E run synchronously against bare ClusterEntity records (Phase A's own
# test style -- StationEconomy's postings are pure functions of record state,
# no live node needed). F needs a live docked/undocked Ship + DockingBay pair,
# so it uses test_repair_services.gd's bare-station fixture pattern plus a
# manually-attached weak record reference (mirrors ClusterManager._promote()'s
# own `node.cluster_record_ref = weakref(rec)` wiring -- see ship.gd). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_station_postings

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")

var main_node: Node = null
var failures: Array = []

const EPS := 0.001

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _approx(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < EPS, "%s (expected %.4f, got %.4f)" % [msg, b, a])

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _mk_station(id: int) -> ClusterEntity:
	var rec := ClusterEntity.new()
	rec.id = id
	rec.hull_script = SmallStation
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
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
	print("Starting Station Postings (M53c Phase B) Tests")

	_test_appears_and_closes()
	_test_quantity_depletes_several_servers()
	_test_payout_fixed_at_acceptance()
	_test_price_by_asker_urgency_identical()
	_test_eligibility_coldreach_volatiles()
	_test_hostile_denied_docking_cannot_serve()

	_finalize()

# ---------------------------------------------------------------------------
# A. A posting appears once stock crosses the import threshold, and closes
# (get_posting returns {}) once satisfied.
# ---------------------------------------------------------------------------
func _test_appears_and_closes() -> void:
	var rec := _mk_station(950)
	_set_bin(rec, "self", Commodity.REFINED, 50.0, 100.0)   # == target -> SATISFIED
	_assert(StationEconomy.get_posting(rec, "self", Commodity.REFINED).is_empty(),
		"A: no posting while satisfied (stock == target)")

	rec.stocks["self"][Commodity.REFINED]["stock"] = 10.0   # below target -> IMPORT urgency
	var posting: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.REFINED)
	_assert(not posting.is_empty(), "A: a posting appears once stock drops below target")
	_assert(posting.get("direction", "") == "IMPORT", "A: the posting direction is IMPORT")
	_approx(posting.get("quantity", -1.0), 40.0, "A: quantity is the raw deficit (target 50 - stock 10)")

	rec.stocks["self"][Commodity.REFINED]["stock"] = 50.0   # back to target -> closes
	_assert(StationEconomy.get_posting(rec, "self", Commodity.REFINED).is_empty(),
		"A: the posting closes once stock returns to target (satisfied)")

# ---------------------------------------------------------------------------
# B. Quantity depletes per delivery via ordinary stock movement -- several
# servers (repeated fulfill() calls) can work the SAME posting, no exclusive
# claim or reservation anywhere.
# ---------------------------------------------------------------------------
func _test_quantity_depletes_several_servers() -> void:
	var rec := _mk_station(951)
	# surplus_line pinned to capacity so an over-delivery below can never flip
	# this bin to EXPORT urgency (which would read as "still an open posting,
	# just now an export one") -- this sub-test is about IMPORT depleting to
	# SATISFIED, not the EXPORT flip, which Phase A's own urgency tests cover.
	_set_bin(rec, "self", Commodity.REFINED, 0.0, 100.0, 40.0, 100.0)   # 40-lot IMPORT deficit
	var posting0: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.REFINED)
	_approx(posting0.get("quantity", -1.0), 40.0, "B: initial posting quantity is the full 40-lot deficit")

	# Server 1 delivers 10.
	var accept1: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.REFINED, "")
	var result1: Dictionary = StationEconomy.fulfill(rec, accept1, 10.0)
	_approx(result1.get("transferred", -1.0), 10.0, "B: server 1 delivers 10")
	var posting1: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.REFINED)
	_approx(posting1.get("quantity", -1.0), 30.0, "B: quantity depleted to 30 after server 1's delivery")

	# Server 2 (a completely independent accept) delivers another 10 against
	# the SAME still-open posting -- no claim held by server 1 blocks it.
	var accept2: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.REFINED, "")
	var result2: Dictionary = StationEconomy.fulfill(rec, accept2, 10.0)
	_approx(result2.get("transferred", -1.0), 10.0, "B: server 2 also delivers 10 against the same posting")
	var posting2: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.REFINED)
	_approx(posting2.get("quantity", -1.0), 20.0, "B: quantity depleted further to 20 -- two independent servers, one posting")

	# Over-delivering the remainder clamps at the bin, and the posting closes.
	StationEconomy.fulfill(rec, StationEconomy.accept_posting(rec, "self", Commodity.REFINED, ""), 1000.0)
	_assert(StationEconomy.get_posting(rec, "self", Commodity.REFINED).is_empty(),
		"B: the posting closes once the deficit is fully served")

# ---------------------------------------------------------------------------
# C. Payout is fixed AT ACCEPTANCE, not recomputed on arrival -- delivering
# into a bin whose urgency (and therefore price) has since dropped must still
# pay the ORIGINAL price, not a re-derived lower one.
# ---------------------------------------------------------------------------
func _test_payout_fixed_at_acceptance() -> void:
	var rec := _mk_station(952)
	_set_bin(rec, "self", Commodity.GOODS, 0.0, 100.0, 50.0)   # empty -> urgency 1.0, high price
	var accept: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.GOODS, "")
	var locked_price: float = accept.get("price", -1.0)
	_assert(locked_price > 0.0, "C: acceptance locks a positive price while urgency is high")

	# Someone ELSE delivers most of the deficit before this server's own
	# delivery lands -- urgency (and the CURRENT price) drops a lot.
	StationEconomy.deliver(rec, "self", Commodity.GOODS, 45.0)
	var current_price: float = StationEconomy.price(rec, "self", Commodity.GOODS, "")
	_assert(current_price < locked_price, "C: the CURRENT price has dropped since acceptance (sanity check on the fixture)")

	# This server's delivery, using the OLD acceptance, must still pay the
	# ORIGINAL (higher) price, not the now-lower current one.
	var result: Dictionary = StationEconomy.fulfill(rec, accept, 5.0)
	_approx(result.get("transferred", -1.0), 5.0, "C: 5 units actually transferred")
	_approx(result.get("payout", -1.0), 5.0 * locked_price, "C: payout uses the LOCKED acceptance price, not a recomputed one")

# ---------------------------------------------------------------------------
# D. Price varies by asker (own-flag discount vs a foreign surcharge); the
# reported URGENCY must stay bit-for-bit identical regardless of asker --
# principle 9's explicit regression sentinel (politics never touches need).
# ---------------------------------------------------------------------------
func _test_price_by_asker_urgency_identical() -> void:
	var rec := _mk_station(953)
	rec.transponder_flag = Standing.FLAG_DRIFT
	rec.market["self"] = {
		Commodity.ORE: {
			"own_flag_multiplier": 0.5,   # zero-rate-ish discount for the station's own flag
			"foreign_multiplier": 2.0,    # surcharge for anyone else
		},
	}
	_set_bin(rec, "self", Commodity.ORE, 90.0, 100.0, 10.0, 50.0)   # well above surplus_line -> EXPORT urgency

	var posting_home: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.ORE, Standing.FLAG_DRIFT)
	var posting_foreign: Dictionary = StationEconomy.get_posting(rec, "self", Commodity.ORE, Standing.FLAG_MERIDIAN)

	_assert(not posting_home.is_empty() and not posting_foreign.is_empty(), "D: both askers see an open posting")
	_approx(posting_home.get("urgency", -1.0), posting_foreign.get("urgency", -2.0),
		"D: urgency is IDENTICAL regardless of asker flag (principle 9)")
	_assert(posting_home.get("price", -1.0) < posting_foreign.get("price", -1.0),
		"D: price DIFFERS by asker -- home flag pays less than a foreign one")
	_approx(posting_foreign.get("price", -1.0), posting_home.get("price", -1.0) * 4.0,
		"D: the price ratio matches the authored multipliers (2.0 / 0.5 = 4x)")

# ---------------------------------------------------------------------------
# E. Eligibility -- the real Coldreach VOLATILES case from home_cluster.gd:
# a foreign-flag hull cannot take the restricted posting; a Meridian
# (Coldreach's own flag) hull can. Built off the REAL authored cluster, not a
# hand-rolled station, so this is also a regression guard on the actual
# authoring in home_cluster.gd staying wired correctly.
# ---------------------------------------------------------------------------
func _test_eligibility_coldreach_volatiles() -> void:
	var def = HomeCluster.build()
	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)   # keep everything dormant -- postings are record-pure
	ClusterLoader.load_into(def, m)

	var coldreach = null
	for rec in m.records:
		if rec.name == "Coldreach":
			coldreach = rec
			break
	_assert(coldreach != null, "E: Coldreach exists in the authored home cluster")
	if coldreach == null:
		return

	_assert(not StationEconomy.is_eligible(coldreach, "self", Commodity.VOLATILES, Standing.FLAG_DRIFT),
		"E: a home-flagged (foreign to Coldreach) hull is NOT eligible for Coldreach's VOLATILES posting")
	_assert(StationEconomy.is_eligible(coldreach, "self", Commodity.VOLATILES, Standing.FLAG_MERIDIAN),
		"E: a Meridian-flagged (local) hull IS eligible")

	# Coldreach's other commodities carry no restriction -- eligibility must
	# not leak across commodities on the same holder.
	_assert(StationEconomy.is_eligible(coldreach, "self", Commodity.ORE, Standing.FLAG_DRIFT),
		"E: Coldreach's ORE is NOT restricted -- a home-flagged hull is eligible")

	# accept_posting() must itself refuse an ineligible asker (not just
	# is_eligible() in isolation).
	_set_bin(coldreach, "self", Commodity.VOLATILES, 0.0, coldreach.stocks["self"][Commodity.VOLATILES].get("capacity", 100.0))
	var accept_foreign: Dictionary = StationEconomy.accept_posting(coldreach, "self", Commodity.VOLATILES, Standing.FLAG_DRIFT)
	_assert(accept_foreign.is_empty(), "E: accept_posting() itself refuses an ineligible foreign asker")
	var accept_local: Dictionary = StationEconomy.accept_posting(coldreach, "self", Commodity.VOLATILES, Standing.FLAG_MERIDIAN)
	_assert(not accept_local.is_empty(), "E: accept_posting() succeeds for an eligible local asker")

	m.queue_free()

# ---------------------------------------------------------------------------
# F. Port control composes for free: a ship that never reached DOCKED at a
# host (standing in for a HOSTILE ship denied a berth -- see the port_control.gd
# reading in the report: there is no separate standing-check subsystem to add
# here, the EXISTING admission gate -- "is this ship actually captured at
# THIS host's own bay" -- is already what begin_repairs() uses, and
# Ship.serve_posting() reuses the identical check) cannot serve a posting.
# ---------------------------------------------------------------------------
var f_station = null
var f_shuttle = null
var f_rec: ClusterEntity = null
var f_accept: Dictionary = {}

func _test_hostile_denied_docking_cannot_serve() -> void:
	print("--- F: a ship never DOCKED (denied a berth) cannot serve a posting ---")
	f_station = MediumStation.new()
	f_station.name = "PostingHost"
	f_station.owner_id = 1
	f_station.iff_tags = ["TEAM_PLAYER"]
	f_station.position = Vector2.ZERO
	f_station.port_zone = {"radius": 8000.0, "authority": "PostingHost Control", "rules": {}}
	main_node.add_child(f_station)

	f_rec = _mk_station(954)
	_set_bin(f_rec, "self", Commodity.GOODS, 0.0, 100.0, 50.0)   # open IMPORT posting
	f_station.cluster_record_ref = weakref(f_rec)

	f_accept = StationEconomy.accept_posting(f_rec, "self", Commodity.GOODS, "")
	_assert(not f_accept.is_empty(), "F: a real posting exists to attempt against")

	# The "HOSTILE" ship: no grant requested, wants_dock left false, never
	# captured -- exactly what a real denial (port control refusing a berth)
	# leaves the ship in. docking_bay stays null throughout.
	f_shuttle = CargoShuttle.new()
	f_shuttle.name = "DeniedHostile"
	f_shuttle.owner_id = 999
	f_shuttle.position = Vector2(50000, 50000)   # nowhere near the berth
	main_node.add_child(f_shuttle)

	var result: Dictionary = f_station.serve_posting(f_shuttle, f_accept, 10.0)
	_assert(result.get("transferred", -1.0) == 0.0, "F: an undocked ship transfers NOTHING")
	_assert(result.get("payout", -1.0) == 0.0, "F: an undocked ship is paid NOTHING")
	_approx(f_rec.stocks["self"][Commodity.GOODS]["stock"], 0.0, "F: the station's stock is untouched by the denied attempt")

	_free_if_valid(f_shuttle)
	_free_if_valid(f_station)

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_station_postings <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_station_postings <<<")
		get_tree().quit(1)
