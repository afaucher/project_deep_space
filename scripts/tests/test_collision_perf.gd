extends Node

# Perf regression guard for the close-range physics cliff.
# A frigate rammed into a medium station used to spike TIME_PHYSICS_PROCESS from
# ~1ms to 120+ms/frame and stall the sim -- NOT the collision solver, but the
# M26 outline-dot sampler: at close range a target subtends a wide angle, so a
# fine sensor (the frigate's 3600-bin short-range collision sensor) drove
# _sample_outline_dots to sample hundreds/thousands of bins -- ray-vs-AABB over
# every target component, per sensor, per ship, every frame. Fixed by capping
# bins-per-sample (MAX_DOT_BINS_PER_SAMPLE). This test rams a station and holds
# sustained contact, asserting the worst-frame physics time stays well under the
# old blow-up. The bound is generous (headless timing is machine-dependent); it
# only needs to separate "fixed" (~20ms here) from "broken" (120ms+).
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_collision_perf

const Frigate = preload("res://scripts/ships/frigate.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")

const RAM_SPEED := 500.0
const MAX_FRAMES := 300
const WARMUP_FRAMES := 30          # ignore the first frames (import/JIT warmup, pre-contact)
const PHYS_MS_CEILING := 60.0      # worst contact-frame budget; broken was 120ms+, fixed ~20ms

var main_node: Node = null
var station = null
var frigate = null
var frame: int = 0
var max_phys_ms: float = 0.0
var max_phys_frame: int = 0
var contact_seen: bool = false
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("=== collision perf: frigate -> medium station @ %.0f u/s ===" % RAM_SPEED)
	station = MediumStation.new()
	station.name = "PerfStation"
	station.owner_id = 1
	station.position = Vector2.ZERO
	main_node.add_child(station)

	frigate = Frigate.new()
	frigate.name = "PerfRam"
	frigate.owner_id = 900
	frigate.position = Vector2(-(station.get_bounding_radius() + 400.0), 0)
	main_node.add_child(frigate)
	frigate.linear_velocity = Vector2(RAM_SPEED, 0)
	frigate.body_entered.connect(func(_b): contact_seen = true)

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame > WARMUP_FRAMES:
		var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if phys_ms > max_phys_ms:
			max_phys_ms = phys_ms
			max_phys_frame = frame
	if frame >= MAX_FRAMES:
		print("=== max phys=%.2fms at frame %d | contact_seen=%s | ceiling=%.0fms ===" % [
			max_phys_ms, max_phys_frame, str(contact_seen), PHYS_MS_CEILING])
		_assert(contact_seen, "the frigate should actually make contact with the station (else the probe is meaningless)")
		_assert(max_phys_ms < PHYS_MS_CEILING,
			"worst-frame physics during sustained contact (%.1fms) should stay under %.0fms -- a regression here means the close-range outline-dot sampler (or similar per-frame work) is unbounded again" % [max_phys_ms, PHYS_MS_CEILING])
		if failures.is_empty():
			print(">>> [TEST PASSED] test_collision_perf <<<")
			get_tree().quit(0)
		else:
			for f in failures:
				printerr("  FAIL: ", f)
			printerr(">>> [TEST FAILED] test_collision_perf <<<")
			get_tree().quit(1)
