extends Node2D
class_name DockingBay

# M19 -- force-capture soft-dock. The bay's own global transform IS the berth
# pose. A dockable ship that has requested docking and enters the capture radius
# is drawn in by a mass-normalized spring-damper (so behaviour is
# ship-mass-independent) and held; once settled, a load/unload timer runs, then
# the ship is released. No rigid joint. See implementation_plans/m19_docking_design.md.

enum State { EMPTY, CAPTURING, DOCKED }

# Servo tuning, accel-space (mass-normalized): a = K_SPRING*pos_err - K_DAMP*vel;
# force = mass*a. K_DAMP ~ 2*sqrt(K_SPRING) is ~critical damping (draw in, no
# overshoot). K_SPRING=4 -> ~0.5s time constant, settles in a few seconds.
const K_SPRING := 4.0
const K_DAMP := 4.0
const K_ROT := 6.0
const K_ROT_DAMP := 5.0

var capture_radius := 5000.0
var pos_tolerance := 60.0     # settled when within this of the berth...
var settle_speed := 25.0      # ...and slower than this
var dock_duration := 1.5      # seconds held at berth before release

# M27 -- whole-freighter docking: the authored berth pose is fixed (e.g. 340u
# below a medium station, sized for shuttles), but capture must never pull a
# big hull into the station's own bounding circle. The effective berth pose
# for the captured ship stands the authored pose off outward (along the
# station->berth direction) until station_radius + ship_radius + margin fits.
# Small hulls are unaffected -- their required distance already sits inside
# the authored berth distance.
const CLEARANCE_MARGIN := 25.0

var state: int = State.EMPTY
var captured = null
var _dock_timer := 0.0

func configure(radius: float, duration: float) -> void:
	capture_radius = radius
	dock_duration = duration

func _physics_process(delta: float) -> void:
	match state:
		State.EMPTY:
			_try_capture()
		State.CAPTURING:
			if not _valid(captured):
				_release()
			else:
				_servo(captured)
				var pos_err: float = _berth_pos_for(captured).distance_to(captured.position)
				if pos_err < pos_tolerance and captured.linear_velocity.length() < settle_speed:
					state = State.DOCKED
					_dock_timer = dock_duration
		State.DOCKED:
			if not _valid(captured):
				_release()
			else:
				_servo(captured)          # keep it seated while loading
				_dock_timer -= delta
				if _dock_timer <= 0.0:
					_release()

func _try_capture() -> void:
	var best = null
	var best_d: float = capture_radius
	for s in get_tree().get_nodes_in_group("ships"):
		if not _dockable_seeking(s):
			continue
		var d: float = global_position.distance_to(s.position)
		if d <= best_d:
			best = s
			best_d = d
	if best != null:
		captured = best
		captured.docking_bay = self   # claim it so no other bay double-captures
		state = State.CAPTURING

func _servo(ship) -> void:
	var pos_err: Vector2 = _berth_pos_for(ship) - ship.position
	var accel: Vector2 = K_SPRING * pos_err - K_DAMP * ship.linear_velocity
	ship.apply_central_force(accel * ship.mass)
	var ang_err: float = wrapf(global_rotation - ship.rotation, -PI, PI)
	var alpha: float = K_ROT * ang_err - K_ROT_DAMP * ship.angular_velocity
	ship.apply_torque(alpha * ship.inertia)

# The effective berth position for THIS ship (see CLEARANCE_MARGIN comment):
# the authored pose, pushed outward along the station->berth direction when the
# ship's bounding radius wouldn't clear the station's. Recomputed per call so
# it tracks a (slowly) rotating/drifting station. Heading is unchanged -- the
# standoff moves the seat, not the facing.
func _berth_pos_for(ship) -> Vector2:
	var host = get_parent()
	if host == null or not host.has_method("get_bounding_radius") or not ship.has_method("get_bounding_radius"):
		return global_position
	var out_vec: Vector2 = global_position - host.global_position
	var berth_dist: float = out_vec.length()
	if berth_dist < 0.001:
		return global_position
	var required: float = host.get_bounding_radius() + ship.get_bounding_radius() + CLEARANCE_MARGIN
	if required <= berth_dist:
		return global_position
	return host.global_position + out_vec / berth_dist * required

func _release() -> void:
	if _valid(captured):
		captured.wants_dock = false
		captured.docking_bay = null
	captured = null
	state = State.EMPTY

# Eligible = dockable, actively requesting, and not already claimed by another bay.
func _dockable_seeking(s) -> bool:
	if not _valid(s) or s.get("dockable") != true or s.get("wants_dock") != true:
		return false
	var claim = s.get("docking_bay")
	return claim == null or claim == self

func _valid(n) -> bool:
	return n != null and is_instance_valid(n)
