extends Node

# Regression for a real campaign bug: docking always read "no open berths" at
# every hub once cargo traffic was running. Root cause -- MediumStation._init()
# hardcodes port_zone["authority"] = "Ironhold Control" (and its one docking
# port's id, "dock_main") as class-level literals, true when only one medium
# station existed. home_cluster.gd reuses the SAME class for three hubs
# (Ironhold, Drift Market, Refinery Prime); without cluster_manager.gd's
# _rebrand_port_zone() (called from _promote(), keyed on the entity's real
# name), all three would report the identical authority + slip id, so
# Ship.issue_docking_grant()'s authority-string reservation scan (ship.gd)
# treats a grant held at ANY medium station as reserving a slip at EVERY
# medium station.
#
# This test promotes two MediumStation entities (mirroring how ClusterManager
# actually spawns campaign hubs, not a hand-built station) with distinct
# names and proves a live grant at one does not block a docking request at
# the other -- the exact multi-instance scenario no prior test covered (every
# existing docking test uses exactly one station).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_campaign_docking_isolation

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	print("Starting Campaign Docking Isolation Tests")

	var manager := ClusterManager.new()
	manager.policy.configure_full_sim()
	manager.live_parent = main
	main.add_child(manager)

	var rec_a := ClusterEntity.new()
	rec_a.id = 1
	rec_a.name = "Ironhold"
	rec_a.hull_script = MediumStation
	rec_a.kind = ClusterEntity.Kind.STATION
	rec_a.is_static = true
	rec_a.pos = Vector2(0, 0)
	manager.add_record(rec_a)

	var rec_b := ClusterEntity.new()
	rec_b.id = 2
	rec_b.name = "Drift Market"
	rec_b.hull_script = MediumStation
	rec_b.kind = ClusterEntity.Kind.STATION
	rec_b.is_static = true
	rec_b.pos = Vector2(300000, 0)
	manager.add_record(rec_b)

	manager.tick(0.0)   # promote both

	var station_a = rec_a.live_node
	var station_b = rec_b.live_node
	_assert(station_a != null and is_instance_valid(station_a), "Ironhold should be promoted live")
	_assert(station_b != null and is_instance_valid(station_b), "Drift Market should be promoted live")
	if station_a == null or station_b == null:
		_finish()
		return

	# 1. Rebranding actually happened -- authorities differ and match the
	# entity's own name, not the class-level "Ironhold Control" default for
	# BOTH (that literal default is fine for Ironhold specifically, but
	# Drift Market must NOT also read "Ironhold Control").
	var auth_a: String = station_a.get_port_zone().get("authority", "")
	var auth_b: String = station_b.get_port_zone().get("authority", "")
	_assert(auth_a == "Ironhold Control", "station A (named 'Ironhold') should rebrand to 'Ironhold Control', got '%s'" % auth_a)
	_assert(auth_b == "Drift Market Control", "station B (named 'Drift Market') should rebrand to its OWN authority, got '%s'" % auth_b)
	_assert(auth_a != auth_b, "two distinct hubs must not share an authority string")

	# 2. Two shuttles take BOTH of Drift Market's berths (M40 -- MediumStation
	# now authors two docking_port bays, dock_main/dock_aux -- filling just
	# one no longer makes the station full, so the regression check below
	# needs Drift Market genuinely fully booked).
	var shuttle_b := CargoShuttle.new()
	shuttle_b.name = "ShuttleAtDriftMarket"
	shuttle_b.owner_id = 50
	main.add_child(shuttle_b)
	var grant_b = station_b.issue_docking_grant(shuttle_b)
	_assert(grant_b != null, "Drift Market should grant its first free berth to shuttle_b")
	_assert(grant_b != null and grant_b.get("authority", "") == "Drift Market Control",
		"shuttle_b's grant should carry Drift Market's own authority")

	var shuttle_b2 := CargoShuttle.new()
	shuttle_b2.name = "ShuttleAtDriftMarket2"
	shuttle_b2.owner_id = 52
	main.add_child(shuttle_b2)
	var grant_b2 = station_b.issue_docking_grant(shuttle_b2)
	_assert(grant_b2 != null, "Drift Market should grant its SECOND free berth to shuttle_b2")
	_assert(grant_b2 != null and grant_b != null and grant_b2.get("slip_id", "") != grant_b.get("slip_id", ""),
		"shuttle_b and shuttle_b2 should hold two DIFFERENT Drift Market slips, not double-booked")

	# Drift Market is now genuinely full -- a third shuttle there gets no berths.
	var shuttle_b3 := CargoShuttle.new()
	shuttle_b3.name = "ShuttleAtDriftMarket3"
	shuttle_b3.owner_id = 53
	main.add_child(shuttle_b3)
	var grant_b3 = station_b.issue_docking_grant(shuttle_b3)
	_assert(grant_b3 == null, "Drift Market should deny a third shuttle once both its berths are reserved")

	# 3. THE regression check: Ironhold, a completely different station with
	# its own separate pair of berths, must still grant a DIFFERENT shuttle a
	# berth even while Drift Market is fully booked. Pre-fix, this failed --
	# Ironhold's reservation scan saw Drift Market's shuttles' grants (same
	# shared "Ironhold Control" authority + same slip ids under the old bug)
	# and believed its own berths were already taken.
	var shuttle_a := CargoShuttle.new()
	shuttle_a.name = "ShuttleAtIronhold"
	shuttle_a.owner_id = 51
	main.add_child(shuttle_a)
	var grant_a = station_a.issue_docking_grant(shuttle_a)
	_assert(grant_a != null, "Ironhold must still grant its own free berth even while Drift Market is fully booked (pre-fix regression: always returned null / 'no open berths')")

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_campaign_docking_isolation <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_campaign_docking_isolation <<<")
		get_tree().quit(1)
