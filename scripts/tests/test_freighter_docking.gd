extends Node

# M27 acceptance -- a freighter (HEAVY, large bounding radius) approaches a
# MediumStation berth, gets captured, settles, and releases. Adapted from
# test_docking.gd's harness (M19). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_freighter_docking
#
# CRITICAL WATCH (per the M27 plan): MediumStation's own bounding radius
# (~264) plus the freighter's (~95.5) exceeds the station's default berth
# distance (340, authored for a much smaller shuttle) -- 264+95.5 = 359.5 >
# 340, so the two hulls' CIRCLE collision shapes (ship.gd uses
# get_bounding_radius() for the physics CollisionShape2D, not the true
# rotated AABB) would overlap at the default berth pose. The fix here is a
# bounding-radius-aware berth STANDOFF: a second, custom-positioned
# DockingBay added as a child of the station (same mechanism
# test_docking_multi.gd uses for its extra berths), placed further out along
# the SAME heading/direction as the station's default berth, at distance
# station_radius + freighter_radius + a safety margin. This is a per-ship
# offset, not a pos_tolerance/settle_speed tweak -- the station's own
# get_berths() (medium_station.gd) is untouched.
#
# The station's own AUTO-GROWN default berth (grown in Ship._ready() from
# get_berths(), at the un-adjusted distance) is freed immediately after the
# station enters the tree -- left in place, it would race the custom berth to
# capture the freighter at the too-close pose. Test-side cleanup only;
# medium_station.gd is untouched.

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Freighter = preload("res://scripts/ships/freighter.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var station = null
var bay = null
var freighter = null
var start_dist: float = 0.0
var t: float = 0.0
var phase: int = 0          # 0 = approach, 1 = hold-then-release
var dock_time: float = -1.0

# Collision-impulse watch: a real hull collision shows up as a sudden,
# discontinuous jump in linear_velocity between consecutive physics frames --
# the servo's own spring-damper pull is smooth and bounded by comparison
# (K_SPRING/K_DAMP produce a continuous deceleration curve, not a step). Track
# frame-to-frame delta rather than an absolute speed bound, since the
# freighter's own free-flight approach speed can legitimately run up near (or
# slightly past, via the physics integrator) its max_speed before capture
# ever engages.
const VELOCITY_DELTA_SPIKE_BOUND := 300.0  # px/s change in ONE physics step
var prev_velocity: Vector2 = Vector2.ZERO
var max_velocity_delta: float = 0.0

const APPROACH_TIMEOUT := 20.0
const START_OFFSET := Vector2(400, 700)
const STANDOFF_MARGIN := 25.0  # extra clearance beyond the sum of both bounding radii

var max_observed_speed: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Freighter Docking (M27) Tests")

	station = MediumStation.new()
	station.name = "Station"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO

	# Freighter instantiated BEFORE add_child so get_bounding_radius() is
	# available (pure function of ship_components, no tree dependency) to
	# compute the standoff below.
	freighter = Freighter.new()
	freighter.name = "Freighter"
	freighter.owner_id = 50
	freighter.iff_tags = ["TEAM_PLAYER"]   # friendly so station PD ignores it
	freighter.wants_dock = true

	# Bounding-radius-aware berth standoff (see file header). Reuse the
	# station's default berth's direction/heading (get_berths()[0]) but push
	# the distance out to station_radius + freighter_radius + margin so the
	# two hulls' collision circles never overlap at the docked pose.
	var default_berth: Dictionary = station.get_berths()[0]
	var berth_dir: Vector2 = default_berth["pos"].normalized()
	var standoff_dist: float = station.get_bounding_radius() + freighter.get_bounding_radius() + STANDOFF_MARGIN
	var berth_pos: Vector2 = berth_dir * standoff_dist

	main_node.add_child(station)   # _ready grows the station's own (default) bay

	# Free the auto-grown default bay -- see file header. It would otherwise
	# claim the freighter into the too-close default pose in a race against
	# the custom berth below.
	for c in station.get_children():
		if c is DockingBay:
			station.remove_child(c)
			c.queue_free()

	bay = DockingBay.new()
	bay.position = berth_pos
	bay.rotation = default_berth["heading"]
	station.add_child(bay)

	print("[M27] station_radius=", station.get_bounding_radius(), " freighter_radius=", freighter.get_bounding_radius(), " standoff_berth_pos=", berth_pos)

	freighter.position = berth_pos + START_OFFSET
	main_node.add_child(freighter)

	start_dist = freighter.position.distance_to(berth_pos)
	prev_velocity = freighter.linear_velocity

func _physics_process(delta: float) -> void:
	if finished or bay == null or freighter == null:
		return
	t += delta

	max_observed_speed = max(max_observed_speed, freighter.linear_velocity.length())

	var velocity_delta: float = (freighter.linear_velocity - prev_velocity).length()
	max_velocity_delta = max(max_velocity_delta, velocity_delta)
	prev_velocity = freighter.linear_velocity

	if phase == 0:
		if bay.state == DockingBay.State.CAPTURING or bay.state == DockingBay.State.DOCKED:
			# Once capture begins, watch for a collision-impulse spike -- a
			# real hull collision would show up as a sudden single-frame
			# velocity jump well beyond the servo's own smooth pull.
			_assert(velocity_delta < VELOCITY_DELTA_SPIKE_BOUND, "no collision-impulse velocity-delta spike during capture (d_spd=%.1f)" % velocity_delta)

		if bay.state == DockingBay.State.DOCKED:
			dock_time = t
			var err: float = bay.global_position.distance_to(freighter.position)
			var spd: float = freighter.linear_velocity.length()
			_assert(start_dist > 500.0, "freighter should start well off the berth (was %.0f)" % start_dist)
			_assert(err < bay.pos_tolerance, "docked pose should be within tolerance (err=%.1f)" % err)
			_assert(spd < bay.settle_speed, "docked freighter should be settled/slow (spd=%.1f)" % spd)
			_assert(is_finite(freighter.position.x) and is_finite(freighter.position.y), "docked position must be finite")
			# Bounding-radius-aware standoff: the two hulls' collision circles
			# must not overlap at the settled pose.
			var center_dist: float = station.global_position.distance_to(freighter.position)
			var radius_sum: float = station.get_bounding_radius() + freighter.get_bounding_radius()
			_assert(center_dist >= radius_sum, "docked freighter's collision circle should not overlap the station's (center_dist=%.1f, radius_sum=%.1f)" % [center_dist, radius_sum])
			phase = 1
		elif t > APPROACH_TIMEOUT:
			var d: float = bay.global_position.distance_to(freighter.position)
			_assert(false, "APPROACH timeout -- never docked (state=%d, dist=%.0f)" % [bay.state, d])
			_finalize()
	elif phase == 1:
		_assert(velocity_delta < VELOCITY_DELTA_SPIKE_BOUND, "no collision-impulse velocity-delta spike while held (d_spd=%.1f)" % velocity_delta)
		if bay.state == DockingBay.State.EMPTY:
			_assert(freighter.wants_dock == false, "release should clear the freighter's dock request")
			_assert(is_finite(freighter.position.x) and is_finite(freighter.position.y), "released position must be finite")
			_finalize()
		elif t > dock_time + bay.dock_duration + 3.0:
			_assert(false, "HOLD timeout -- bay never released (state=%d)" % bay.state)
			_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	print("[M27] max observed freighter speed during whole run: ", max_observed_speed, "  max single-frame velocity delta: ", max_velocity_delta)
	if failures.is_empty():
		print(">>> [TEST PASSED] test_freighter_docking <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_freighter_docking <<<")
		get_tree().quit(1)
