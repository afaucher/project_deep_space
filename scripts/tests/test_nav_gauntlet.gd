extends Node

# M53c Phase D -- isolated nav gauntlet. One CargoShuttle, one asteroid field,
# one GO_TO+DOCK_AT job issued through the real M50 job-runner path (JobRunnerLeaf
# executing JobSteps.step_go_to/step_dock_at -- the SAME verbs RoutePlanner.
# route_itinerary() emits, see scripts/ai/route_planner.gd) -- reproduces the
# M53c Phase C traffic-sim finding (haulers bleeding stations dry via real
# collision damage while navigating INTO the outposts that sit on asteroid
# fields) in seconds instead of the 20-minute economy_traffic sim. Run this
# while tuning scripts/ai/steering.gd instead.
#
# Densities are the three real outpost fields authored in home_cluster.gd
# (rock count + field radius + RNG seed, copied verbatim so the layout matches
# the actual game). The shuttle's start distance from the station is FIXED and
# short across all three -- see START_DIST below -- so density, not transit
# distance, is the variable under test (CLAUDE.md: shrink distance, not
# density, if a full traverse would be too slow for the gate).
#
# Assertions are margin-based per CLAUDE.md ("Godot 2D physics is NOT
# bit-deterministic run-to-run") -- arrival + a max-HP-loss-fraction, never an
# exact number.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_nav_gauntlet
# Pass marker per CLAUDE.md.

const Asteroid = preload("res://scripts/asteroid.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

# name, rock count, field radius, RNG seed -- taken verbatim from
# home_cluster.gd's def.add_field(...) calls for Deepcut/Coldreach/Slag Bay.
# Ordered hardest (most rocks, widest field) last.
const DENSITIES := [
	{"name": "Deepcut",   "rocks": 15, "radius": 9000.0,  "seed": 3},
	{"name": "Coldreach", "rocks": 22, "radius": 12000.0, "seed": 2},
	{"name": "Slag Bay",  "rocks": 32, "radius": 16000.0, "seed": 1},
]

# Fixed, short traverse for EVERY density -- the shuttle starts already inside
# the field (same local rock density a real approach sees, since the loader
# scatters rocks uniform-in-area) rather than outside it, so wall-clock time
# doesn't scale with the field's radius.
const START_DIST := 5000.0
# 15% -- comfortably above the ~10% worst observed post-fix result (a rock
# landing almost exactly on the Deepcut approach corridor forces a slow, tight
# final squeeze past it) and well under the un-fixed baseline's 22%. Margin
# per CLAUDE.md's physics-noise note, not an exact-value assertion.
const MAX_HP_LOSS_FRACTION := 0.15
# Generous: the DOCK_AT approach itself (job_steps.gd's capture-radius/
# hemisphere gate, not this test's concern) can spiral for ~30s even with ZERO
# obstacles before the capture geometry lines up -- confirmed with a 0-rock
# control run. 90s covers that plus room for field-avoidance detours. Real
# wall-clock cost stays small: --fixed-fps never sleeps, so this runs in
# low single-digit seconds regardless of the sim-second budget.
const TIMEOUT := 90.0

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var d_index: int = 0
var shuttle = null
var station = null
var rocks: Array = []
var t: float = 0.0
var start_max_health: float = 0.0
var arrived: bool = false

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
	print("Starting Nav Gauntlet Tests")
	_start_density(0)

# Reproduces cluster_loader.gd's field expansion exactly (seeded RNG,
# uniform-in-disk via r = R*sqrt(u)) so the local rock density/layout matches
# the real game's fields, not an invented approximation.
func _spawn_field(center: Vector2, radius: float, count: int, field_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = field_seed
	var out: Array = []
	for i in range(count):
		var rr: float = radius * sqrt(rng.randf())
		var aa: float = rng.randf() * TAU
		var rock = Asteroid.new()
		rock.name = "Rock%d" % i
		rock.position = center + Vector2(cos(aa), sin(aa)) * rr
		main_node.add_child(rock)
		out.append(rock)
	return out

func _start_density(i: int) -> void:
	d_index = i
	t = 0.0
	arrived = false
	var d: Dictionary = DENSITIES[i]
	print("--- Density %d/%d: %s (%d rocks, field radius %.0f) ---" % [i + 1, DENSITIES.size(), d["name"], d["rocks"], d["radius"]])

	var center := Vector2.ZERO
	rocks = _spawn_field(center, d["radius"], d["rocks"], d["seed"])

	station = SmallStation.new()
	station.name = "Outpost_%s" % d["name"]
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = center
	main_node.add_child(station)

	shuttle = CargoShuttle.new()
	shuttle.name = "Gauntlet_%s" % d["name"]
	shuttle.owner_id = 60
	shuttle.iff_tags = ["TEAM_PLAYER"]
	shuttle.position = center + Vector2(START_DIST, 0)
	main_node.add_child(shuttle)
	shuttle.add_child(AITreeFactory.build_pirate())   # Disengage -> JobRunner -> Idle: bare M50 job-runner path
	shuttle.assign_job({
		"steps": [
			{"verb": "GO_TO", "pos": center},
			{"verb": "DOCK_AT", "station_pos": center},
		],
		"current": 0,
	})

	start_max_health = _max_health(shuttle)

var _dbg_ticks := 0
func _physics_process(delta: float) -> void:
	if finished or shuttle == null:
		return
	t += delta
	_dbg_ticks += 1
	if _dbg_ticks % 300 == 0:   # ~5s of sim time -- enough to follow progress without spamming the log
		print("  [dbg] t=%.1f pos=%s dist_ctr=%.0f hp=%.1f" % [t, str(shuttle.position), shuttle.position.length(), _total_health(shuttle)])

	if not arrived and shuttle.get("docking_bay") != null:
		arrived = true
		_finish_density()
		return

	if t > TIMEOUT:
		_finish_density()

func _finish_density() -> void:
	var d: Dictionary = DENSITIES[d_index]
	var lost: float = start_max_health - _total_health(shuttle)
	var frac: float = (lost / start_max_health) if start_max_health > 0.0 else 0.0
	print("[%s] arrived=%s  t=%.2fs  hp_lost=%.1f/%.1f (%.1f%%)" % [d["name"], str(arrived), t, lost, start_max_health, frac * 100.0])

	_assert(arrived, "%s: shuttle should arrive/dock within timeout (t=%.2f, pos=%s, dist_to_center=%.0f)" % [d["name"], t, str(shuttle.position), shuttle.position.length()])
	_assert(frac < MAX_HP_LOSS_FRACTION, "%s: shuttle should lose less than %.0f%% of max HP navigating the field (lost %.1f%%)" % [d["name"], MAX_HP_LOSS_FRACTION * 100.0, frac * 100.0])

	_free_if_valid(shuttle)
	_free_if_valid(station)
	for r in rocks:
		_free_if_valid(r)
	rocks = []

	if d_index + 1 < DENSITIES.size():
		_start_density(d_index + 1)
	else:
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_nav_gauntlet <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_nav_gauntlet <<<")
		get_tree().quit(1)
