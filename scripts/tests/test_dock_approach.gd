extends Node

# Isolated DOCK-CYCLE harness (design_ideas/port_zones_and_channels.md "Two
# speed rules, not one"). Sibling to test_nav_gauntlet.gd -- but where the
# gauntlet asks "can a hull cross a rock field without shredding itself", this
# asks the question the gauntlet cannot: **does routine station traffic damage
# the station?**
#
# WHY THIS EXISTS SEPARATELY: the M53c economy_traffic sim found stations
# bleeding REFINED/GOODS to self-repair at a rate that tracked DOCKING COUNT
# (Refinery Prime, 9 dockings, -20.9 REFINED/hr; Slag Bay, 2 dockings, none).
# That is a 20-minute cluster-wide economic simulation answering a question
# about hulls and closing velocities. This runs in seconds.
#
# THIS IS A RATE MEASUREMENT, NOT AN EVENT TEST -- and that is the whole
# design. The first version of this file ran each scenario to first-dock and
# caught exactly ONE damaging collision in 120 seconds (513 u/s, 2490 damage,
# which was the entire 4.93% hull loss that run). Tuning against a sample of
# one is how you fix the wrong thing: the failure is stochastic -- it needs a
# particular convergence geometry to line up -- so the honest instrument runs
# many cycles and reports damaging contacts PER CYCLE. A fix is credible when
# it moves a rate, not when it makes one unlucky collision go away.
#
# NO ASTEROIDS ANYWHERE IN THIS FILE -- that is deliberate. The gauntlet
# already covers field navigation; rocks here would let a field-avoidance
# regression masquerade as a docking-discipline regression.
#
# TWO MECHANISMS, MEASURED SEPARATELY (they want different fixes):
#   - ARRIVAL. Steering.steer() takes `exclude_pos` -- the body being
#     approached is deliberately never dodged -- so converging hulls each fly
#     straight at the same point while dodging EACH OTHER in a shrinking cone.
#     The observed 513 u/s hit was exactly this: avoidance of one obstacle
#     shoving a hull into the one it had stopped watching.
#   - DEPARTURE. DockingBay._release() imparts a separation impulse while the
#     hull is still inside the station's footprint. A departure-side problem
#     reads as an approach-discipline failure unless you split them, and then
#     gets "fixed" in the wrong place.
#
# Both station kinds are covered on purpose: MediumStation publishes a
# `speed_advisory` port zone (200 u/s, medium_station.gd) and SmallStation
# publishes NOTHING -- no port control, and it could not enforce a limit if it
# wanted to. Approach discipline is self-imposed and must hold at BOTH, so the
# SmallStation rows prove rule 1 rather than rule 2.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_dock_approach
# Pass marker per CLAUDE.md.

const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Freighter = preload("res://scripts/ships/freighter.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")

const SCENARIOS := [
	{"name": "solo control / SmallStation", "medium": false, "ships": 1, "cycles": 4},
	{"name": "traffic / MediumStation (publishes 200 u/s)", "medium": true, "ships": 8, "cycles": 30},
	{"name": "traffic / SmallStation (publishes nothing)", "medium": false, "ships": 8, "cycles": 30},
	# The Nexus hauler: the cluster's export gate made physical (implementation_
	# plans/m53d_meridian_sovereignty.md). A HEAVY Freighter (mass ~300 vs the
	# shuttle's, accel 8-12, max_speed ~400) comes through the wormhole
	# periodically, docks at Ironhold, takes whatever Ironhold has posted for
	# export, and leaves. The open question this scenario exists to answer is
	# simply WHETHER A HULL THAT SIZE CAN BERTH AT ALL -- capture geometry is
	# sized around shuttles, and a 300-mass hull that misses its capture and
	# grazes the station instead would do far more damage than any shuttle
	# (collision damage scales with reduced mass).
	# 2 cycles, not 3: a Freighter tops out at ~400 u/s against the shuttle's
	# ~700 and is ponderous on the capture spiral, so one full out-and-back
	# cycle costs it ~300 sim-seconds. Two cycles is enough to show it berths
	# repeatably; a third would only buy TIMEOUT.
	{"name": "Nexus hauler (Freighter) solo / MediumStation", "medium": true, "ships": 1, "cycles": 2, "hull": "freighter"},
	# ...and the same hull arriving into live shuttle traffic, which is the
	# realistic case and the dangerous one.
	{"name": "Nexus hauler + shuttles / MediumStation", "medium": true, "ships": 5, "cycles": 10, "hull": "mixed"},
	# ROCK FIELD. Closes the coverage gap this file's own header creates: every
	# other scenario excludes asteroids so that a field-avoidance regression
	# cannot masquerade as a docking-discipline one. But economy_traffic keeps
	# reporting its heaviest station self-repair at exactly the two stations that
	# sit INSIDE fields (Coldreach, Halvorsen), and the combination -- converging
	# traffic AND rocks on the approach -- is the one case nothing tested.
	# Geometry is Coldreach's real field, copied from home_cluster.gd's
	# def.add_field() call (22 rocks, 12000 radius, seed 2) so this is the actual
	# game layout rather than an invented one.
	{"name": "traffic + rock field / SmallStation (Coldreach layout)", "medium": false, "ships": 8, "cycles": 20,
		"rocks": 22, "field_radius": 12000.0, "field_seed": 2},
]

# Ships fly out to this radius and come back, over and over. Long enough that a
# hull reaches real cruise speed before it has to shed it (an approach that
# never accelerates proves nothing), short enough to keep cycles cheap.
const START_DIST := 12000.0

# Inside this radius a hull is "on approach" and its speed is sampled.
const APPROACH_RADIUS := 6000.0

# Ship.COLLISION_DAMAGE_MIN_SPEED. Below this the engine treats contact as free
# (routine docking settle is ~25 u/s), which is why peak APPROACH speed and
# peak CONTACT speed are different measurements and this file reports both --
# the solo run peaks around 727 u/s on approach and does zero damage, because
# it sheds all of it before touching anything. Only contact speed predicts
# damage.
const DAMAGING_CONTACT_SPEED := 150.0

# A contact within this many seconds of leaving a berth is attributed to
# DEPARTURE rather than ARRIVAL.
const DEPARTURE_WINDOW := 6.0

# The only authored approach-speed number in the codebase (medium_station.gd's
# port zone). Reported for both station kinds: rule 2 makes it law at the
# MediumStation, rule 1 should produce something similar at the SmallStation
# for its own reasons.
const SANE_APPROACH_SPEED := 200.0

# Routine traffic must not damage the station. Not an exact zero -- CLAUDE.md
# warns against exact-value assertions under physics noise -- but a station
# losing >1% of its hull to being used as intended is the failure this file
# exists to catch.
const MAX_STATION_HP_LOSS_FRACTION := 0.01
const MAX_SHIP_HP_LOSS_FRACTION := 0.10
# A REGRESSION GUARD, not a perfection bar -- and deliberately not the primary
# criterion. Set from measured data after the fix landed, having first been
# guessed at 0.05 before any data existed.
#
# Why it is not the criterion: this counts contacts above
# DAMAGING_CONTACT_SPEED, but "damaging" there is the engine's free-contact
# threshold, not a statement about consequence. The MediumStation settles
# around 0.3 contacts/cycle while losing 0.44% of a 108,200 HP hull over 30
# cycles -- roughly 16 HP per dock, which is not damage in any sense the
# economy can feel. Failing on that number would mean tuning the game until an
# invented threshold went green.
#
# STATION HP LOSS is the real criterion (below), because it is the quantity
# that actually propagates: station self-repair draws REFINED/GOODS from its
# own bins, which is what made this a visible economy problem in the first
# place. This rate stays as a guard because the pre-fix baseline was 2.000
# contacts/cycle, so 0.50 still catches any meaningful backslide.
const MAX_DAMAGING_STATION_CONTACTS_PER_CYCLE := 0.50

# Per-scenario budget in sim-seconds. --fixed-fps never sleeps, so sim-seconds
# are cheap in wall-clock.
const TIMEOUT := 600.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var s_index: int = 0
var station = null
var ships: Array = []
var t: float = 0.0
var station_start_hp: float = 0.0
var ships_start_hp: float = 0.0
var peak_approach_speed: float = 0.0
var peak_contact_speed: float = 0.0
var cycles_done: int = 0

# Per-ship bookkeeping, keyed by instance id (NOT by node name -- see
# _start_scenario's naming note).
var _was_docked: Dictionary = {}      # id -> bool
var _undock_t: Dictionary = {}        # id -> sim time it last left a berth (-INF if never)

# Contact tally. `station_hits` counts contacts against the STATION above the
# damaging threshold; `ship_hits` counts hull-on-hull. Split arrival/departure.
var station_hits: int = 0
var ship_hits: int = 0
var arrival_hits: int = 0
var departure_hits: int = 0
var worst_hit: Dictionary = {}
var rocks: Array = []

# Reproduces cluster_loader.gd's field expansion exactly (seeded RNG,
# uniform-in-disk via r = R*sqrt(u)) so local rock density matches the real
# game's fields rather than an invented approximation. Same helper as
# test_nav_gauntlet.gd.
func _spawn_field(center: Vector2, radius: float, count: int, field_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = field_seed
	var out: Array = []
	for i in range(count):
		var rr: float = radius * sqrt(rng.randf())
		var aa: float = rng.randf() * TAU
		var rock_pos: Vector2 = center + Vector2(cos(aa), sin(aa)) * rr
		# Mirrors ClusterLoader's cleared-approach rule, reading its own constant
		# so the two can never drift. The station sits at `center` here, so this
		# is the same test the loader applies in the real world -- which is the
		# point: this scenario must reflect the field a hauler ACTUALLY meets, or
		# it guards a hazard the game no longer generates.
		if rock_pos.distance_to(center) < ClusterLoader.STATION_CLEAR_RADIUS:
			continue
		var rock = Asteroid.new()
		rock.name = "Rock_S%d_%d" % [s_index, i]
		rock.position = rock_pos
		main_node.add_child(rock)
		out.append(rock)
	return out

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _total_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += max(0.0, c.get("health", 0.0))
	return h

func _max_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += c.get("max_health", 0.0)
	return h

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func setup(main) -> void:
	main_node = main
	print("Starting Dock Cycle Tests")
	_start_scenario(0)

func _outer_point(k: int, n: int) -> Vector2:
	return Vector2(START_DIST, 0).rotated((TAU / float(n)) * float(k))

# GO_TO the ship's own outer waypoint, then DOCK_AT the station. Re-issued
# every time it completes, which is what produces repeated dock/undock cycles:
# DOCK_AT finishes on capture, the bay auto-releases after dock_duration, and
# the next GO_TO sends the hull back out.
func _issue_cycle(ship, k: int, n: int) -> void:
	ship.assign_job({
		"steps": [
			{"verb": "GO_TO", "pos": _outer_point(k, n)},
			{"verb": "DOCK_AT", "station_pos": Vector2.ZERO},
		],
		"current": 0,
	})

func _start_scenario(i: int) -> void:
	s_index = i
	t = 0.0
	peak_approach_speed = 0.0
	peak_contact_speed = 0.0
	cycles_done = 0
	station_hits = 0
	ship_hits = 0
	arrival_hits = 0
	departure_hits = 0
	worst_hit = {}
	_was_docked = {}
	_undock_t = {}
	ships = []
	var sc: Dictionary = SCENARIOS[i]
	print("--- Scenario %d/%d: %s (%d ships, target %d cycles) ---" % [
		i + 1, SCENARIOS.size(), sc["name"], int(sc["ships"]), int(sc["cycles"])])

	var center := Vector2.ZERO
	station = MediumStation.new() if sc["medium"] else SmallStation.new()
	# Names are scenario-tagged because queue_free() is DEFERRED: the previous
	# scenario's nodes are still in the tree when these are added, so a reused
	# name gets silently renamed to "@RigidBody2D@NNN" by Godot. That made the
	# first run's collision log unreadable (every participant was an anonymous
	# RigidBody) and cost real diagnosis time.
	station.name = "Station_S%d" % i
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = center
	main_node.add_child(station)
	station_start_hp = _max_health(station)

	rocks = []
	var rock_count: int = int(sc.get("rocks", 0))
	if rock_count > 0:
		rocks = _spawn_field(center, float(sc.get("field_radius", 12000.0)), rock_count, int(sc.get("field_seed", 1)))
		print("    (%d asteroids, field radius %.0f)" % [rock_count, sc.get("field_radius", 12000.0)])

	var n: int = int(sc["ships"])
	ships_start_hp = 0.0
	var hull_mode: String = sc.get("hull", "shuttle")
	for k in range(n):
		# "mixed" makes ship 0 the heavy and the rest shuttles -- one Nexus
		# hauler arriving into ordinary traffic, not a fleet of them.
		var heavy: bool = hull_mode == "freighter" or (hull_mode == "mixed" and k == 0)
		var ship = Freighter.new() if heavy else CargoShuttle.new()
		ship.name = "%s_S%d_%d" % ["Nexus" if heavy else "Hauler", i, k]
		ship.owner_id = 60 + k
		ship.iff_tags = ["TEAM_PLAYER"]
		ship.position = _outer_point(k, n)
		main_node.add_child(ship)
		# Bare M50 job-runner path (Disengage -> JobRunner -> Idle), same as
		# test_nav_gauntlet: this test is about the dock cycle, not about route
		# planning, so no RoutePlannerLeaf and no cluster wiring.
		ship.add_child(AITreeFactory.build_pirate())
		ship.body_entered.connect(_on_contact.bind(ship))
		_was_docked[ship.get_instance_id()] = false
		_undock_t[ship.get_instance_id()] = -1000.0
		_issue_cycle(ship, k, n)
		ships.append(ship)
		ships_start_hp += _max_health(ship)

# Mirrors Ship._on_body_entered's own closing-speed calculation (pre-solve
# velocities on both sides, so handler ordering doesn't matter) rather than
# reading post-bounce velocity, which would understate every impact.
func _on_contact(other: Node, ship) -> void:
	if not (other is RigidBody2D) or station == null:
		return
	var other_prev = other.get("_prev_linear_velocity")
	var other_vel: Vector2 = other_prev if other_prev != null else other.linear_velocity
	var self_prev = ship.get("_prev_linear_velocity")
	var self_vel: Vector2 = self_prev if self_prev != null else ship.linear_velocity
	var v_impact: float = (self_vel - other_vel).length()
	if v_impact > peak_contact_speed:
		peak_contact_speed = v_impact
	if v_impact <= DAMAGING_CONTACT_SPEED:
		return

	var hit_station: bool = other == station
	if hit_station:
		station_hits += 1
	else:
		ship_hits += 1
	var since_undock: float = t - float(_undock_t.get(ship.get_instance_id(), -1000.0))
	var phase: String = "DEPARTURE" if since_undock <= DEPARTURE_WINDOW else "ARRIVAL"
	if hit_station:
		if phase == "DEPARTURE":
			departure_hits += 1
		else:
			arrival_hits += 1
	if worst_hit.is_empty() or v_impact > float(worst_hit.get("v", 0.0)):
		worst_hit = {"v": v_impact, "who": ship.name, "target": other.name, "phase": phase, "t": t}
	print("  [contact] t=%.1f %s -> %s  v_impact=%.0f  %s%s" % [
		t, ship.name, other.name, v_impact, phase, "  (STATION)" if hit_station else ""])

var _dbg_ticks := 0
func _physics_process(delta: float) -> void:
	if finished or station == null:
		return
	t += delta
	_dbg_ticks += 1
	var sc: Dictionary = SCENARIOS[s_index]
	var n: int = int(sc["ships"])

	for k in range(ships.size()):
		var ship = ships[k]
		if not is_instance_valid(ship):
			continue
		var id: int = ship.get_instance_id()
		var docked: bool = ship.get("docking_bay") != null

		# Dock/undock edge detection drives both the cycle counter and the
		# arrival/departure attribution.
		if docked and not _was_docked[id]:
			cycles_done += 1
		elif not docked and _was_docked[id]:
			_undock_t[id] = t
			_issue_cycle(ship, k, n)   # released -- send it back out for another lap
		_was_docked[id] = docked

		if not docked:
			var dist: float = ship.position.distance_to(station.position)
			if dist <= APPROACH_RADIUS:
				var spd: float = ship.linear_velocity.length()
				if spd > peak_approach_speed:
					peak_approach_speed = spd

	if _dbg_ticks % 600 == 0:
		print("  [dbg] t=%.0f cycles=%d/%d station_hits=%d ship_hits=%d station_hp=%.0f/%.0f" % [
			t, cycles_done, int(sc["cycles"]), station_hits, ship_hits, _total_health(station), station_start_hp])

	if cycles_done >= int(sc["cycles"]) or t > TIMEOUT:
		_finish_scenario()

func _finish_scenario() -> void:
	var sc: Dictionary = SCENARIOS[s_index]
	var station_lost: float = station_start_hp - _total_health(station)
	var station_frac: float = (station_lost / station_start_hp) if station_start_hp > 0.0 else 0.0

	var ships_now: float = 0.0
	for ship in ships:
		if is_instance_valid(ship):
			ships_now += _total_health(ship)
	var ships_lost: float = ships_start_hp - ships_now
	var ships_frac: float = (ships_lost / ships_start_hp) if ships_start_hp > 0.0 else 0.0
	var per_cycle: float = (float(station_hits) / float(cycles_done)) if cycles_done > 0 else 0.0

	print("[%s] cycles=%d t=%.0fs  station_hp_lost=%.1f (%.2f%%)  ship_hp_lost=%.1f (%.2f%%)" % [
		sc["name"], cycles_done, t, station_lost, station_frac * 100.0, ships_lost, ships_frac * 100.0])
	print("    station_hits=%d (%.3f/cycle -- arrival %d, departure %d)  ship_hits=%d  peak_approach=%.0f  peak_contact=%.0f" % [
		station_hits, per_cycle, arrival_hits, departure_hits, ship_hits, peak_approach_speed, peak_contact_speed])
	if not worst_hit.is_empty():
		print("    worst: %s -> %s at %.0f u/s (%s, t=%.1f)" % [
			worst_hit["who"], worst_hit["target"], worst_hit["v"], worst_hit["phase"], worst_hit["t"]])

	_assert(cycles_done >= int(sc["cycles"]),
		"%s: should complete %d dock cycles within %.0fs (managed %d)" % [
			sc["name"], int(sc["cycles"]), TIMEOUT, cycles_done])
	_assert(per_cycle <= MAX_DAMAGING_STATION_CONTACTS_PER_CYCLE,
		"%s: damaging station contacts per dock cycle should stay at or under %.2f (measured %.3f over %d cycles)" % [
			sc["name"], MAX_DAMAGING_STATION_CONTACTS_PER_CYCLE, per_cycle, cycles_done])
	_assert(station_frac < MAX_STATION_HP_LOSS_FRACTION,
		"%s: station should lose under %.1f%% HP to routine traffic (lost %.2f%%)" % [
			sc["name"], MAX_STATION_HP_LOSS_FRACTION * 100.0, station_frac * 100.0])
	_assert(ships_frac < MAX_SHIP_HP_LOSS_FRACTION,
		"%s: hulls should lose under %.0f%% HP over the run (lost %.2f%%)" % [
			sc["name"], MAX_SHIP_HP_LOSS_FRACTION * 100.0, ships_frac * 100.0])

	for ship in ships:
		_free_if_valid(ship)
	ships = []
	for r in rocks:
		_free_if_valid(r)
	rocks = []
	_free_if_valid(station)
	station = null

	if s_index + 1 < SCENARIOS.size():
		_start_scenario(s_index + 1)
	else:
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_dock_approach <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_dock_approach <<<")
		get_tree().quit(1)
