extends Node

# M27 acceptance -- a freighter (HEAVY, large bounding radius) approaches a
# MediumStation berth, gets captured, settles, and releases. Adapted from
# test_docking.gd's harness (M19). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_freighter_docking
#
# MediumStation's bounding radius (~264) plus the freighter's (~95.5) exceeds
# the station's authored berth distance (340, sized for a shuttle) -- so a
# naive capture would overlap the two hulls' circle collision shapes. The
# PRODUCTION fix (M27, user-requested: "medium stations dock whole
# freighters") lives in DockingBay._berth_pos_for(): the effective berth pose
# for a captured ship stands off outward along the station->berth direction
# to station_radius + ship_radius + CLEARANCE_MARGIN whenever the authored
# distance is too close. This test therefore uses the station's OWN
# auto-grown default bay -- no test-side workaround -- and asserts the
# settled seat lands in the standoff band, proving the real docking path
# handles big hulls out of the box (shuttles are unaffected: their required
# distance sits inside the authored berth distance, see test_docking).

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
# Comfortably inside MediumStation's derived capture_radius (~396u for its
# ~264u hull -- see PortZone.derive_capture_radius, a short-range docking
# arm, not the old flat 5000u default) while still meaningfully off the
# berth (>150u -- see the start_dist assertion below). The freighter never
# flies under its own power in this test; capture-then-spring-pull IS the
# approach, so the start position must already be within reach.
const START_OFFSET := Vector2(150, 260)

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
	freighter.set("docking_grant", {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "", "time_left": 300.0})

	main_node.add_child(station)   # _ready grows the station's own (default) bay

	# Use the station's OWN auto-grown default bay -- the production path.
	# The bounding-radius-aware standoff is DockingBay's job now, not the
	# test's (see file header).
	for c in station.get_children():
		if c is DockingBay:
			bay = c
			break
	_assert(bay != null, "station should auto-grow a DockingBay from get_berths()")
	if bay == null:
		_finalize()
		return

	print("[M27] station_radius=", station.get_bounding_radius(), " freighter_radius=", freighter.get_bounding_radius(), " authored_berth=", bay.position)

	freighter.position = bay.global_position + START_OFFSET
	main_node.add_child(freighter)

	start_dist = freighter.position.distance_to(bay.global_position)
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
			var spd: float = freighter.linear_velocity.length()
			_assert(start_dist > 150.0, "freighter should start well off the berth (was %.0f)" % start_dist)
			_assert(spd < bay.settle_speed, "docked freighter should be settled/slow (spd=%.1f)" % spd)
			_assert(is_finite(freighter.position.x) and is_finite(freighter.position.y), "docked position must be finite")
			# The production standoff must seat the freighter in the band
			# [no-overlap floor, standoff seat + tolerance]: collision circles
			# never overlap, AND the ship actually sits at the pushed-out seat
			# rather than drifting somewhere merely non-overlapping.
			var center_dist: float = station.global_position.distance_to(freighter.position)
			var radius_sum: float = station.get_bounding_radius() + freighter.get_bounding_radius()
			var required: float = radius_sum + DockingBay.CLEARANCE_MARGIN
			_assert(center_dist >= radius_sum, "docked freighter's collision circle should not overlap the station's (center_dist=%.1f, radius_sum=%.1f)" % [center_dist, radius_sum])
			_assert(center_dist <= required + bay.pos_tolerance, "docked freighter should sit AT the standoff seat (center_dist=%.1f, seat=%.1f, tol=%.1f)" % [center_dist, required, bay.pos_tolerance])
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
