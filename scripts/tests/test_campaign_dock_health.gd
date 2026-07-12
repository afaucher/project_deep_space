extends Node

# Regression for the campaign docking-wedge bug: "port control responds
# negative, but the indicator shows and you can't seem to dock."
#
# Chain that produced it: the M40 second berth (dock_aux) let a cargo shuttle
# be assigned the berth on the station's FAR side; its approach crossed the
# hull (cargo steering deliberately doesn't avoid the destination station),
# the collision set Ironhold spinning (~0.37 rad/s); nothing ever despun a
# station (StationKeepingLeaf held actor.rotation -- a target that spins with
# the hull); the berth poses orbited with the spin, so every capture became
# an endless chase; CAPTURING had no timeout, so both bays wedged shut
# forever ("no berths"), while the wedged player's grant countdown stayed
# frozen (fulfilled-pause), keeping stale docking indicators alive.
#
# Fixes under test (all four layers):
#   1. StationKeepingLeaf holds its INITIAL attitude -> live stations despin.
#   2. STRUCTURE-tier angular_damp = 0.5 -> AI-less stations shed spin too.
#   3. DockingBay CAPTURE_TIMEOUT -> an unwinnable capture frees the bay.
#   4. issue_docking_grant assigns the NEAREST free bay -> arrivals are never
#      routed to the far side through the station's own hull. (Also heals the
#      cargo AI: an aborted capture drops it back to TRANSIT to re-request.)
#
# This test runs the REAL campaign content (HomeCluster + overlay, real
# ClusterManager, real cargo traffic) and asserts the player can dock at
# Ironhold at the start AND again after the traffic window in which the
# wedge used to form, and that the station stays despun throughout.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_campaign_dock_health

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const HomeClusterOverlay = preload("res://scripts/story/home_cluster_overlay.gd")
const StoryCharacters = preload("res://scripts/story/characters.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

const TRAFFIC_WINDOW_END := 45.0   # the original wedge formed by t~16 and was permanent by t~26
const SECOND_DOCK_DEADLINE := 80.0
const MAX_RESIDUAL_SPIN := 0.05

var main_node: Node = null
var failures: Array = []
var player = null
var ironhold = null
var t: float = 0.0
var phase: int = 0
var docked_once := false
var undock_sent := false
var retry_at: float = 0.0
var max_spin_seen: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Campaign Dock Health Tests")
	var def = HomeCluster.build()
	var manager = ClusterManager.new()
	manager.live_parent = main
	main.add_child(manager)
	ClusterLoader.load_into(def, manager, HomeClusterOverlay, StoryCharacters)

	player = CargoShuttle.new()
	player.name = "Ship_1"
	player.owner_id = 1
	player.iff_tags = ["TEAM_PLAYER"]
	player.position = def.player_start
	player.dockable = true
	player.manual_undock = true
	main.add_child(player)

	manager.viewpoint = def.player_start
	manager.tick(0.0)

	for rec in manager.records:
		if rec.sid == "ironhold":
			ironhold = rec.live_node
	_assert(ironhold != null, "campaign Ironhold promotes")
	if ironhold == null:
		_finish()

func _try_dock() -> bool:
	var result: Dictionary = ironhold.request_docking_via_control(player)
	if result.get("outcome") != "granted":
		return false
	player.wants_dock = true
	for b in ironhold.get_berths():
		if b.slip_id == result["grant"].get("slip_id", ""):
			# 200u is comfortably inside the derived capture_radius (~396u
			# for Ironhold's ~264u hull -- see PortZone.derive_capture_radius,
			# a short-range docking arm, not the old flat 5000u default).
			var approach: Vector2 = b.global_position + Vector2.RIGHT.rotated(b.global_rotation) * 200.0
			var xform: Transform2D = player.global_transform
			xform.origin = approach
			PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
			player.position = approach
			player.linear_velocity = Vector2.ZERO
	return true

func _physics_process(delta: float) -> void:
	if ironhold == null or phase >= 99:
		return
	t += delta
	max_spin_seen = max(max_spin_seen, abs(ironhold.angular_velocity))

	match phase:
		0:
			# Phase 0: first docking, straight from spawn.
			if _try_dock():
				phase = 1
			elif t > 10.0:
				_assert(false, "first docking request should be granted within 10s of campaign start")
				phase = 90
		1:
			if player.docking_bay != null and player.docking_bay.state == DockingBay.State.DOCKED:
				_assert(true, "player docks at Ironhold at campaign start")
				docked_once = true
				phase = 2
			elif t > 20.0:
				_assert(false, "player failed to reach DOCKED on the first grant (t=%.1f)" % t)
				phase = 90
		2:
			# Phase 2: undock, move clear, let NPC traffic run through the
			# window where the wedge used to form.
			if not undock_sent:
				player.request_undock()
				undock_sent = true
			elif player.docking_bay == null:
				var xform: Transform2D = player.global_transform
				xform.origin = Vector2(3000, 0)
				PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
				player.position = Vector2(3000, 0)
				player.linear_velocity = Vector2.ZERO
				player.wants_dock = false
				phase = 3
		3:
			if t >= TRAFFIC_WINDOW_END:
				_assert(abs(ironhold.angular_velocity) < MAX_RESIDUAL_SPIN,
					"station spin stays despun through the traffic window (ang_vel=%.3f)" % ironhold.angular_velocity)
				retry_at = t
				phase = 4
		4:
			# Phase 4: dock AGAIN after traffic -- the pool must have recovered
			# even if a capture aborted or a shuttle bumped the hull meanwhile.
			if player.docking_bay != null and player.docking_bay.state == DockingBay.State.DOCKED:
				_assert(true, "player docks at Ironhold again after the traffic window")
				phase = 90
			elif t - retry_at > 3.0:
				retry_at = t
				_try_dock()   # keep retrying; transient shuttle occupancy is legal
			if t > SECOND_DOCK_DEADLINE:
				_assert(false, "player could not re-dock after the traffic window (bays wedged?)")
				for b in ironhold.get_berths():
					print("  bay ", b.slip_id, " state=", b.state)
				phase = 90
		90:
			_finish()

func _finish() -> void:
	phase = 99
	print("  (max station spin seen: %.3f rad/s)" % max_spin_seen)
	if failures.is_empty():
		print(">>> [TEST PASSED] test_campaign_dock_health <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_campaign_dock_health <<<")
		get_tree().quit(1)
