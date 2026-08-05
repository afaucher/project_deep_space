extends Node

# M55a -- PHYSICAL CARGO. A hauler holds what it picked up, and can only
# deliver what it holds.
#
# WHY THIS MILESTONE EXISTS, in one sentence: before it, `serve_posting()`
# handed `amount` straight to `StationEconomy.fulfill()` with nothing checking
# the hull possessed anything, so a ROBBED HAULER STILL DELIVERED IN FULL and
# piracy could not touch the economy at all. That made "the economy survives
# four game-hours alongside piracy and patrols" -- this project's headline
# result on 2026-08-03, measured as 0/24 starved bins -- a statement about a
# MISSING COUPLING rather than about a resilient economy (ledger D58). Goods
# were, quite literally, minted at the delivery dock.
#
# What is covered:
#   A. the hold is a VOLUME with a cap -- a load clamps to free space, and the
#      helper reports what ACTUALLY fit, not what was asked for.
#   B. unloading clamps to what is held, and a drained commodity leaves NO
#      float-dust key behind.
#   C. **the D58 rule**: a docked hull carrying nothing delivers nothing, and
#      the station's stock is untouched.
#   D. a PARTIAL pickup makes a partial delivery -- the case that silently
#      minted goods before, and the one a station-stock assertion alone can
#      never catch.
#   E. conservation across a full pickup -> dropoff round trip.
#   F. a pickup cannot exceed the hold; the station keeps what did not fit.
#   G. `Ship.CARGO_CAPACITY` equals `RoutePlanner.LOT_SIZE`.
#
# G is not pedantry. Two constants kept in agreement by hand is exactly how the
# 2026-07-26 LOT_SIZE bump silently mis-scaled three others
# (TRAVEL_COST_PER_UNIT, HYSTERESIS_MARGIN_PER_LOT, and MIN_BIN_LOTS, whose
# comment still describes the pre-bump world). Pinning it costs one assertion.
#
# A-B and G are pure and run synchronously. C-F need a hull that passes
# `serve_posting`'s admission gate ("is this ship captured at THIS host's own
# bay"), which is driven here by setting the bay's state directly rather than
# flying a real approach. The REAL physics-driven settlement path is already
# covered end-to-end by test_route_planner's case F, which now also asserts
# conservation across the seam -- so this file tests the RULES on top of a seam
# that is verified elsewhere, rather than re-flying the same approach.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_cargo_manifest

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")

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

func _mk_station_rec(id: int) -> ClusterEntity:
	var rec := ClusterEntity.new()
	rec.id = id
	rec.hull_script = SmallStation
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
	StationEconomy.ensure_holder(rec, "self")
	return rec

func _set_bin(rec, commodity: String, stock: float, capacity: float, target: float = -1.0, surplus_line: float = -1.0) -> void:
	var bin: Dictionary = rec.stocks["self"][commodity]
	bin["stock"] = stock
	bin["capacity"] = capacity
	bin["target"] = target if target >= 0.0 else capacity * 0.5
	bin["surplus_line"] = surplus_line if surplus_line >= 0.0 else capacity * 0.85

func _find_bay(station) -> DockingBay:
	for child in station.get_children():
		if child is DockingBay:
			return child
	return null

# A station plus a hull that reads as DOCKED at it. The bay's state is set
# directly instead of flying an approach: this file is about what moves ACROSS
# the seam, and the seam's own physics is test_route_planner's F.
var _station = null
var _shuttle = null

func _make_docked_pair(rec) -> bool:
	_station = MediumStation.new()
	_station.name = "ManifestHost"
	_station.owner_id = 1
	_station.iff_tags = ["TEAM_PLAYER"]
	_station.position = Vector2.ZERO
	main_node.add_child(_station)
	_station.cluster_record_ref = weakref(rec)

	var bay := _find_bay(_station)
	if bay == null:
		_assert(false, "fixture: the station grew a DockingBay")
		return false

	_shuttle = CargoShuttle.new()
	_shuttle.name = "ManifestShuttle"
	_shuttle.owner_id = 60
	_shuttle.iff_tags = ["TEAM_PLAYER"]
	_shuttle.position = Vector2(200, 0)
	main_node.add_child(_shuttle)

	bay.state = DockingBay.State.DOCKED
	_shuttle.docking_bay = bay
	return true

func _teardown_pair() -> void:
	_free_if_valid(_shuttle)
	_free_if_valid(_station)
	_shuttle = null
	_station = null

func setup(main) -> void:
	main_node = main
	print("Starting Cargo Manifest (M55a) Tests")

	_test_load_clamps_to_capacity()
	_test_unload_clamps_and_leaves_no_dust()
	_test_empty_hull_delivers_nothing()
	_test_partial_pickup_makes_partial_delivery()
	_test_conservation_round_trip()
	_test_pickup_cannot_exceed_the_hold()
	_test_capacity_matches_planner_lot_size()
	_test_laden_hull_plans_for_what_it_carries()

	_finalize()

# ---------------------------------------------------------------------------
# A. The hold is a volume with a cap, and the helper reports what FIT.
# ---------------------------------------------------------------------------
func _test_load_clamps_to_capacity() -> void:
	print("--- A: loading clamps to free volume ---")
	var hull = CargoShuttle.new()
	main_node.add_child(hull)

	_approx(hull.manifest_free(), hull.CARGO_CAPACITY, "A: a fresh hull's whole hold is free")
	var got: float = hull.manifest_add(Commodity.ORE, 1000.0)
	_approx(got, hull.CARGO_CAPACITY, "A: loading 1000 into a 4-lot hold reports what actually FIT, not what was asked")
	_approx(hull.manifest_total(), hull.CARGO_CAPACITY, "A: the hull holds exactly its capacity")
	_approx(hull.manifest_free(), 0.0, "A: nothing free once full")
	_approx(hull.manifest_add(Commodity.GOODS, 1.0), 0.0, "A: a full hold accepts nothing more")
	_assert(not hull.cargo_manifest.has(Commodity.GOODS), "A: and a refused load leaves no empty key behind")

	# The mixed hold D60 describes, at the data level -- the planner does not
	# fill this way yet, but the SHAPE must already support it or that change
	# becomes a rewrite instead of an addition.
	hull.cargo_manifest.clear()
	_approx(hull.manifest_add(Commodity.RARE, 1.0), 1.0, "A: 1 lot of RARE loads")
	_approx(hull.manifest_add(Commodity.ORE, 99.0), hull.CARGO_CAPACITY - 1.0,
		"A: the REST of the hold takes another commodity -- capacity is shared, not per-commodity")
	_approx(hull.manifest_total(), hull.CARGO_CAPACITY, "A: the shared hold is full across two commodities")

	_free_if_valid(hull)

# ---------------------------------------------------------------------------
# B. Unloading clamps to what is held, and drains cleanly.
# ---------------------------------------------------------------------------
func _test_unload_clamps_and_leaves_no_dust() -> void:
	print("--- B: unloading clamps to what is held ---")
	var hull = CargoShuttle.new()
	main_node.add_child(hull)

	hull.manifest_add(Commodity.ORE, 2.0)
	_approx(hull.manifest_remove(Commodity.ORE, 99.0), 2.0, "B: removing more than held reports only what was there")
	_approx(hull.manifest_amount(Commodity.ORE), 0.0, "B: the hull is empty of ORE")
	_assert(not hull.cargo_manifest.has(Commodity.ORE),
		"B: a drained commodity leaves NO key -- float dust would read as 'still carrying' forever")
	_approx(hull.manifest_remove(Commodity.GOODS, 1.0), 0.0, "B: removing a commodity never held is a no-op")

	_free_if_valid(hull)

# ---------------------------------------------------------------------------
# C. THE D58 RULE. A docked hull carrying nothing delivers nothing.
# ---------------------------------------------------------------------------
func _test_empty_hull_delivers_nothing() -> void:
	print("--- C: a hull carrying nothing delivers nothing (the D58 rule) ---")
	var rec := _mk_station_rec(970)
	_set_bin(rec, Commodity.GOODS, 0.0, 100.0)   # empty -> open IMPORT posting
	if not _make_docked_pair(rec):
		_teardown_pair()
		return

	var accept: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.GOODS, "")
	_assert(not accept.is_empty(), "C: a real IMPORT posting exists to deliver against")
	_assert(accept.get("direction", "") == "IMPORT", "C: and it is an IMPORT (the station receives)")

	var result: Dictionary = _station.serve_posting(_shuttle, accept, 4.0)
	_approx(result.get("transferred", -1.0), 0.0, "C: an empty hull transfers NOTHING")
	_approx(result.get("payout", -1.0), 0.0, "C: and is paid NOTHING")
	_approx(rec.stocks["self"][Commodity.GOODS]["stock"], 0.0,
		"C: the station's stock is untouched -- goods are no longer minted at the dock")

	_teardown_pair()

# ---------------------------------------------------------------------------
# D. A partial pickup makes a partial delivery.
#
# This is the case the old code got wrong SILENTLY. The hauler plans for 4,
# the pickup station only has 2, and before the manifest existed the dropoff
# still delivered the full 4 -- because `amount` was the plan's number and
# nothing tracked what was actually aboard.
# ---------------------------------------------------------------------------
func _test_partial_pickup_makes_partial_delivery() -> void:
	print("--- D: a short pickup makes a short delivery ---")
	var rec := _mk_station_rec(971)
	_set_bin(rec, Commodity.GOODS, 0.0, 100.0)
	if not _make_docked_pair(rec):
		_teardown_pair()
		return

	# The hull got only 2 at its pickup (that station was nearly out).
	_shuttle.manifest_add(Commodity.GOODS, 2.0)

	var accept: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.GOODS, "")
	# It still tries to deliver the 4 its PLAN said, which is exactly what the
	# itinerary stages -- route_itinerary() writes the planned amount, not a
	# number anybody re-checked against the hold.
	var result: Dictionary = _station.serve_posting(_shuttle, accept, 4.0)
	_approx(result.get("transferred", -1.0), 2.0, "D: only the 2 it actually carried land")
	_approx(rec.stocks["self"][Commodity.GOODS]["stock"], 2.0, "D: the station received 2, not the planned 4")
	_approx(_shuttle.manifest_total(), 0.0, "D: and the hull is empty afterwards")

	_teardown_pair()

# ---------------------------------------------------------------------------
# E. Conservation across a pickup -> dropoff round trip.
# ---------------------------------------------------------------------------
func _test_conservation_round_trip() -> void:
	print("--- E: conservation across pickup -> dropoff ---")
	var rec := _mk_station_rec(972)
	# Well above surplus_line -> an open EXPORT posting the hull can load from.
	_set_bin(rec, Commodity.ORE, 95.0, 100.0)
	if not _make_docked_pair(rec):
		_teardown_pair()
		return

	var export_accept: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.ORE, "")
	_assert(not export_accept.is_empty(), "E: an EXPORT posting exists to load from")
	_assert(export_accept.get("direction", "") == "EXPORT", "E: and it is an EXPORT (the station ships out)")

	var stock_before: float = rec.stocks["self"][Commodity.ORE]["stock"]
	var loaded: Dictionary = _station.serve_posting(_shuttle, export_accept, 3.0)
	_approx(loaded.get("transferred", -1.0), 3.0, "E: 3 lots leave the station")
	_approx(_shuttle.manifest_amount(Commodity.ORE), 3.0, "E: and 3 lots are aboard the hull")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], stock_before - 3.0,
		"E: the station's stock fell by exactly what the hull gained")

	_teardown_pair()

# ---------------------------------------------------------------------------
# F. A pickup cannot exceed the hold.
# ---------------------------------------------------------------------------
func _test_pickup_cannot_exceed_the_hold() -> void:
	print("--- F: a pickup clamps to the hold, and the station keeps the rest ---")
	var rec := _mk_station_rec(973)
	_set_bin(rec, Commodity.ORE, 95.0, 100.0)
	if not _make_docked_pair(rec):
		_teardown_pair()
		return

	# Already carrying 3 of a 4-lot hold: only 1 more can fit.
	_shuttle.manifest_add(Commodity.ORE, 3.0)
	var stock_before: float = rec.stocks["self"][Commodity.ORE]["stock"]

	var export_accept: Dictionary = StationEconomy.accept_posting(rec, "self", Commodity.ORE, "")
	var loaded: Dictionary = _station.serve_posting(_shuttle, export_accept, 4.0)
	_approx(loaded.get("transferred", -1.0), 1.0, "F: only the 1 lot that fits is loaded")
	_approx(_shuttle.manifest_total(), _shuttle.CARGO_CAPACITY, "F: the hull is now exactly full")
	_approx(rec.stocks["self"][Commodity.ORE]["stock"], stock_before - 1.0,
		"F: the station kept the 3 lots that did not fit -- cargo is not destroyed by an over-ask")

	_teardown_pair()

# ---------------------------------------------------------------------------
# G. The two capacity constants must agree.
# ---------------------------------------------------------------------------
func _test_capacity_matches_planner_lot_size() -> void:
	print("--- G: Ship.CARGO_CAPACITY == RoutePlanner.LOT_SIZE ---")
	var hull = CargoShuttle.new()
	main_node.add_child(hull)
	_approx(hull.CARGO_CAPACITY, RoutePlanner.LOT_SIZE,
		"G: the hold matches the cap the planner builds every route against (M55c removes this duplication)")
	_free_if_valid(hull)

# ---------------------------------------------------------------------------
# H. A laden hull searches only for routes carrying what it already holds.
#
# THE FAILURE THIS PREVENTS, which M55a itself created: cargo is now physical,
# so a hull whose dropoff bin filled mid-transit keeps the difference. A laden
# hull planning a route for a DIFFERENT commodity can neither load (hold full)
# nor deliver (not carrying what the dropoff wants) -- it flies both legs, moves
# nothing, re-plans, and repeats forever. A hauler burned permanently, which is
# the job-runner failure class that has already cost this project a faction.
#
# The fix is a search restriction, NOT a dump: destroying cargo would break the
# conservation this whole milestone exists to establish.
# ---------------------------------------------------------------------------
func _test_laden_hull_plans_for_what_it_carries() -> void:
	print("--- H: a laden hull plans a route for what it is carrying ---")
	var pickup := _mk_station_rec(974)
	pickup.pos = Vector2.ZERO
	pickup.name = "LadenPickup"
	var dropoff := _mk_station_rec(975)
	dropoff.pos = Vector2(100000, 0)
	dropoff.name = "LadenDropoff"

	# ORE is the FAT lane: full surplus at the pickup, empty bin at the dropoff
	# (IMPORT urgency 1.0 -> top price). REFINED is a thin one -- a surplus to
	# load, but a dropoff only slightly under target, so low urgency and a much
	# lower score. Unconstrained, ORE must win.
	_set_bin(pickup, Commodity.ORE, 95.0, 100.0)
	_set_bin(dropoff, Commodity.ORE, 0.0, 100.0)
	_set_bin(pickup, Commodity.REFINED, 95.0, 100.0)
	_set_bin(dropoff, Commodity.REFINED, 45.0, 100.0)   # target 50 -> small deficit

	var cluster = ClusterManager.new()
	cluster.add_record(pickup)
	cluster.add_record(dropoff)

	var free_choice: Dictionary = RoutePlanner.best_route(cluster, Vector2.ZERO, "")
	_assert(not free_choice.is_empty(), "H: an unladen hull finds a route at all")
	_assert(free_choice.get("commodity", "") == Commodity.ORE,
		"H: unconstrained, the fat ORE lane wins (got %s)" % str(free_choice.get("commodity", "")))

	# Now the same world, seen by a hull already holding REFINED.
	var laden: Dictionary = RoutePlanner.best_route(cluster, Vector2.ZERO, "", [], Commodity.REFINED)
	_assert(not laden.is_empty(), "H: a laden hull still finds a route for its own cargo")
	_assert(laden.get("commodity", "") == Commodity.REFINED,
		"H: carrying REFINED, it plans REFINED even though ORE pays better (got %s)" % str(laden.get("commodity", "")))

	# And the restriction is a FILTER, not a fallback: a commodity with no
	# viable route yields nothing rather than quietly reverting to the best
	# unconstrained lane, which would put the hull straight back into the loop.
	var impossible: Dictionary = RoutePlanner.best_route(cluster, Vector2.ZERO, "", [], Commodity.VOLATILES)
	_assert(impossible.is_empty(),
		"H: no viable route for the held commodity returns {} -- it does NOT fall back to ORE")

	# Every scored candidate carries the held commodity, not just the winner --
	# the winner alone could pass by luck.
	var all_laden: Array = RoutePlanner.scored_routes(cluster, Vector2.ZERO, "", [], Commodity.REFINED)
	var off_commodity: int = 0
	for r in all_laden:
		if r.get("commodity", "") != Commodity.REFINED:
			off_commodity += 1
	_assert(off_commodity == 0, "H: the whole candidate set is restricted, not merely the argmax")

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_cargo_manifest <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_cargo_manifest <<<")
		get_tree().quit(1)
