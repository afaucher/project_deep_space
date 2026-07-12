extends Node

# M19 acceptance -- multiple ships dock at once without slamming into each other.
# A station with four berths (N/S/E/W) and four shuttles, each approaching from
# its own side. Asserts: each berth captures a DISTINCT shuttle (the claim stops
# double-capture), all settle, and the closest any two shuttles ever come stays
# well above their collision diameter (no slamming). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_docking_multi
# Pass marker per CLAUDE.md.

const SmallStation = preload("res://scripts/ships/small_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

# Two 50u-radius hulls overlap under 100u apart; require a comfortable margin.
const NO_SLAM_MIN := 150.0
const APPROACH_TIMEOUT := 14.0
const EXTRA_BERTHS := [Vector2(0, -300), Vector2(300, 0), Vector2(-300, 0)]
# Each berth faces OUTWARD (away from the station center, per the "M32
# controlled-station parity"/hemisphere-capture convention -- _try_capture()
# only grabs a ship in front of the port, dir_to_ship.dot(bay_forward) > 0),
# so a shuttle must sit FURTHER from center than its target berth, not
# between the berth and the center. The default bay (SmallStation's own
# authored docking_port, at (0,135), heading +Y) additionally has a SMALL
# derived capture_radius now (~275u for its ~184u hull -- see
# PortZone.derive_capture_radius, a short-range docking arm, not the old
# flat 5000u default) since it goes through Ship._ready()'s derivation loop,
# unlike the three EXTRA_BERTHS bays (hand-built via DockingBay.new(),
# bypassing that loop -- they keep DockingBay's own unmodified default and
# have generous reach regardless of distance). Each start below sits ~150u
# beyond its corresponding berth along the correct outward axis -- inside
# the default bay's shrunk capture_radius where that applies, comfortably
# inside the other three's much larger one either way, and short enough to
# settle within APPROACH_TIMEOUT under the softened servo spring (K_SPRING
# halved for a gentler pull-in -- see docking_bay.gd).
const SHUTTLE_STARTS := [Vector2(0, 300), Vector2(0, -450), Vector2(450, 0), Vector2(-450, 0)]

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var station = null
var bays: Array = []
var shuttles: Array = []
var min_pair_dist: float = INF
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Multi-Ship Docking (M19) Tests")

	station = SmallStation.new()
	station.name = "Station"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	main_node.add_child(station)   # grows the default berth

	for c in station.get_children():
		if c is DockingBay:
			bays.append(c)
	for off in EXTRA_BERTHS:
		var b = DockingBay.new()
		b.position = off
		# Universal Docking Refactor: bays are now directional passive collars.
		# Face each berth OUTWARD (toward the quadrant its shuttle approaches
		# from) so the shuttle sits in the approach hemisphere, and enable the
		# tractor servo (real station bays get has_servo=true from their
		# docking_port component; these hand-made test bays must set it too).
		b.rotation = off.angle()
		b.has_servo = true
		station.add_child(b)
		bays.append(b)

	for i in range(SHUTTLE_STARTS.size()):
		var sh = CargoShuttle.new()
		sh.name = "Shuttle_%d" % i
		sh.owner_id = 50 + i
		sh.iff_tags = ["TEAM_PLAYER"]
		sh.position = SHUTTLE_STARTS[i]
		sh.wants_dock = true
		main_node.add_child(sh)
		shuttles.append(sh)

	_assert(bays.size() == 4, "setup: expected 4 berths, got %d" % bays.size())

func _physics_process(_delta: float) -> void:
	if finished or shuttles.size() < 4:
		return
	t += _delta

	# Track the closest any two shuttles ever get (the anti-slam invariant).
	for i in range(shuttles.size()):
		for j in range(i + 1, shuttles.size()):
			var d: float = shuttles[i].position.distance_to(shuttles[j].position)
			if d < min_pair_dist:
				min_pair_dist = d

	var docked: int = 0
	for b in bays:
		if b.state == DockingBay.State.DOCKED:
			docked += 1

	if docked == bays.size():
		# Distinct capture: every bay holds a different shuttle.
		var caught := {}
		for b in bays:
			caught[b.captured.get_instance_id()] = true
		_assert(caught.size() == bays.size(), "each berth must hold a distinct shuttle (double-capture!) got %d" % caught.size())

		# Each captured shuttle settled at its berth. Measure against the
		# effective berth pose (_berth_pos_for applies the M27 radius standoff),
		# NOT the raw bay position -- that's where the servo actually seats the
		# ship, and it's the same reference test_docking (single) checks against.
		var all_settled := true
		for b in bays:
			if b._berth_pos_for(b.captured).distance_to(b.captured.position) >= b.pos_tolerance:
				all_settled = false
		_assert(all_settled, "every docked shuttle should be settled within tolerance")

		# The headline: nobody slammed into anybody on the way in.
		_assert(min_pair_dist > NO_SLAM_MIN,
			"shuttles came within %.0fu of each other (< %.0f safe) -- they slammed" % [min_pair_dist, NO_SLAM_MIN])

		for sh in shuttles:
			_assert(is_finite(sh.position.x) and is_finite(sh.position.y), "shuttle position must be finite")
		_finalize()
	elif t > APPROACH_TIMEOUT:
		_assert(false, "APPROACH timeout -- only %d/%d berths docked" % [docked, bays.size()])
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_multi <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_multi <<<")
		get_tree().quit(1)
