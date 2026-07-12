extends Node

# Regression for "I still can't successfully get docking permission" (the
# grant-lifecycle half -- the berth-check log shipped alongside):
#
#   1. A grant is CONSUMED on bay release (docked -> auto-release, undock, or
#      aborted capture). Before this fix a departed cargo shuttle's grant kept
#      its slip reserved until the 120s countdown or zone-exit, so a station
#      could read "no open berths" with BOTH bays physically EMPTY (observed
#      live: dock_main:EMPTY + dock_aux:EMPTY yet grants held by two shuttles
#      already flying away).
#   2. Re-requesting while already holding a live grant is IDEMPOTENT: same
#      slip back, countdown refreshed -- never a double-book or a self-deny.
#   3. Requesting while physically docked at this station returns
#      "already_docked" (not a second grant, not "no berths").
#   4. Requesting from outside the control zone returns "out_of_zone" instead
#      of a grant that _update_docking_grant silently kills next tick.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_docking_grant_lifecycle

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const PortControl = preload("res://scripts/port/port_control.gd")

var main_node: Node = null
var failures: Array = []
var t: float = 0.0
var phase: int = 0

var station = null
var docker = null      # the shuttle that flies the full dock -> release cycle
var bystander = null   # requests the released slip immediately after
var docked_slip: String = ""

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Docking Grant Lifecycle Tests")

	station = MediumStation.new()
	station.name = "LifecycleStation"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	main.add_child(station)

	docker = CargoShuttle.new()
	docker.name = "LifecycleDocker"
	docker.owner_id = 2
	docker.iff_tags = ["TEAM_PLAYER"]
	docker.dockable = true
	docker.position = Vector2(3000, 0)
	main.add_child(docker)

	bystander = CargoShuttle.new()
	bystander.name = "LifecycleBystander"
	bystander.owner_id = 3
	bystander.iff_tags = ["TEAM_PLAYER"]
	bystander.dockable = true
	bystander.position = Vector2(3000, 500)
	main.add_child(bystander)

	# --- Scenario 4 (synchronous): out-of-zone request is denied up front.
	var far = CargoShuttle.new()
	far.name = "LifecycleFar"
	far.owner_id = 4
	far.iff_tags = ["TEAM_PLAYER"]
	far.position = Vector2(20000, 0)   # zone radius is 8000
	main.add_child(far)
	var far_result: Dictionary = PortControl.request_docking(station, far)
	_assert(far_result.get("outcome") == "out_of_zone",
		"scenario 4: request from 20000u (zone 8000u) -> out_of_zone (got %s)" % str(far_result.get("outcome")))
	_assert(far.docking_grant == null, "scenario 4: no grant was issued to the out-of-zone ship")
	far.queue_free()

	# --- Scenario 2 (synchronous): idempotent re-request.
	var first: Dictionary = PortControl.request_docking(station, docker)
	_assert(first.get("outcome") == "granted", "scenario 2: first in-zone request granted")
	var first_slip: String = first.get("grant", {}).get("slip_id", "")
	docker.docking_grant["time_left"] = 5.0   # age it, then re-request
	var again: Dictionary = PortControl.request_docking(station, docker)
	_assert(again.get("outcome") == "granted", "scenario 2: re-request while holding a grant still reads granted")
	_assert(again.get("grant", {}).get("slip_id", "") == first_slip,
		"scenario 2: re-request returns the SAME slip (no double-book)")
	_assert(docker.docking_grant.get("time_left", 0.0) > 100.0,
		"scenario 2: re-request refreshed the countdown (%.0f)" % docker.docking_grant.get("time_left", 0.0))
	docked_slip = first_slip

	# Park the docker in its assigned bay's capture cone; the berth servo
	# (Ironhold-style has_servo bays) pulls it to DOCKED from here.
	for b in station.get_berths():
		if b.slip_id == first_slip:
			var approach: Vector2 = b.global_position + Vector2.RIGHT.rotated(b.global_rotation) * 600.0
			var xform: Transform2D = docker.global_transform
			xform.origin = approach
			PhysicsServer2D.body_set_state(docker.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
			docker.position = approach
			docker.linear_velocity = Vector2.ZERO
	docker.wants_dock = true

func _physics_process(delta: float) -> void:
	if phase >= 99:
		return
	t += delta

	match phase:
		0:
			# Wait for DOCKED (servo capture from 600u takes a few seconds).
			if docker.docking_bay != null and docker.docking_bay.state == DockingBay.State.DOCKED:
				_assert(true, "docker reached DOCKED at slip %s (t=%.1f)" % [docked_slip, t])
				# --- Scenario 3: request while physically docked here.
				var res: Dictionary = PortControl.request_docking(station, docker)
				_assert(res.get("outcome") == "already_docked",
					"scenario 3: request while DOCKED -> already_docked (got %s)" % str(res.get("outcome")))
				_assert(res.get("slip_id", "") == docked_slip,
					"scenario 3: already_docked names the occupied slip")
				phase = 1
			elif t > 20.0:
				_assert(false, "docker never reached DOCKED (t=%.1f)" % t)
				phase = 90
		1:
			# manual_undock defaults false -> the bay auto-releases after its
			# dock_duration. The grant must be consumed by that release.
			if docker.docking_bay == null:
				_assert(docker.docking_grant == null,
					"scenario 1: auto-release consumed the docker's grant")
				# --- Scenario 5: departure corridor. The grant is gone, but
				# departing_slip must be stamped with the SAME slip so the nav
				# panel keeps the exit channel open (see ship.gd's own
				# comment) -- regression for "once you are released, the path
				# turns back into a hatch, you can't get out of the zone
				# before it closes".
				_assert(not docker.departing_slip.is_empty(),
					"scenario 5: release stamps departing_slip (channel stays drawable)")
				_assert(docker.departing_slip.get("authority", "") == station.get_port_zone().get("authority", ""),
					"scenario 5: departing_slip names this station's authority")
				_assert(docker.departing_slip.get("slip_id", "") == docked_slip,
					"scenario 5: departing_slip names the just-released slip")
				# The freed slip must be grantable to someone else IMMEDIATELY
				# -- not after a 120s countdown or a zone exit.
				var res: Dictionary = PortControl.request_docking(station, bystander)
				_assert(res.get("outcome") == "granted",
					"scenario 1: bystander granted immediately after the release (got %s)" % str(res.get("outcome")))
				phase = 2
			elif t > 40.0:
				_assert(false, "bay never auto-released the docker (t=%.1f)" % t)
				phase = 90
		2:
			# Still deep inside the exclusion disc (just released, hasn't
			# moved) -- departing_slip must NOT have cleared yet.
			_assert(not docker.departing_slip.is_empty(),
				"scenario 5: departing_slip survives while still inside the exclusion disc")
			# Teleport clear of the exclusion boundary (station.get_port_zone()
			# derives exclusion_radius for a controlled MediumStation; well
			# outside it regardless of the exact derived value) and tick once
			# -- _update_departing_slip (ship.gd) must clear it.
			var far: Vector2 = station.global_position + Vector2(1000000.0, 0.0)
			var xf: Transform2D = docker.global_transform
			xf.origin = far
			PhysicsServer2D.body_set_state(docker.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xf)
			docker.position = far
			phase = 3
		3:
			_assert(docker.departing_slip.is_empty(),
				"scenario 5: departing_slip clears once the ship exits the exclusion boundary")
			phase = 90
		90:
			_finish()

func _finish() -> void:
	phase = 99
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_grant_lifecycle <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_grant_lifecycle <<<")
		get_tree().quit(1)
