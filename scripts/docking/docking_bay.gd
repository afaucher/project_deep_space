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

# M32 -- stable identity for this bay within its host's berth list, set once at
# creation time in Ship._ready(). Used
# by the permission gate to match a specific-slip DockingGrant to exactly one
# bay (see _dockable_seeking()). "" means "not yet assigned".
var slip_id: String = ""

# M32 -- claimed by an any-open (slip_id == "") grant holder at capture time so
# a second any-open holder can't also land in this same bay while it's
# occupied. Reset to false on release. Meaningless for host stations with no
# port_zone (permissionless path never reads this).
var slip_claimed: bool = false

# Whether this bay actively pulls ships in during CAPTURING (tractor beam).
# If false, ships must manually fly into the tolerance zone before clamps (DOCKED) engage.
var has_servo: bool = false

# M32 -- separation-impulse strength imparted on request_undock(), applied to
# the ship's linear_velocity along the berth's outward (host->berth) heading.
# Tuned to be a gentle nudge clear of the capture radius, not a launch --
# roughly a few seconds to coast clear at typical shuttle scale.
const UNDOCK_PUSH_SPEED := 80.0

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
				var port_offset = _get_captured_port_offset(captured)
				var port_global_offset = port_offset.rotated(captured.rotation)
				var pos_err: float = _berth_pos_for(captured).distance_to(captured.position + port_global_offset)
				
				var port_heading = _get_captured_port_heading(captured)
				var target_rot = global_rotation + PI - port_heading
				var ang_err: float = abs(wrapf(target_rot - captured.rotation, -PI, PI))
				
				if pos_err < pos_tolerance and captured.linear_velocity.length() < settle_speed and ang_err < 0.2:
					state = State.DOCKED
					_dock_timer = dock_duration
		State.DOCKED:
			if not _valid(captured):
				_release()
			else:
				_servo(captured)          # keep it seated while loading
				# M32 -- manual_undock=false keeps the original M19 behavior
				# (auto-release after dock_duration) unchanged, which is why the
				# existing NPC/production docking tests stay green untouched.
				# manual_undock=true holds indefinitely (dock_duration becomes a
				# minimum hold, enforced by request_undock() below) until the
				# ship issues an explicit undock command.
				if captured.get("manual_undock") != true:
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
		# M32 -- any-open grant (slip_id == ""): claim THIS bay's slip at the
		# moment of capture so a second any-open holder flown at the same bay
		# can't also land here (see _dockable_seeking()'s any-open branch).
		# Specific-slip grants don't need this -- the reservation already lives
		# in the grant itself, held by issue_docking_grant().
		var grant = best.get("docking_grant")
		if grant != null and grant.get("slip_id", "INVALID") == "":
			slip_claimed = true

func _get_captured_port_offset(ship) -> Vector2:
	if ship.has_method("get_components_by_type"):
		var ports = ship.get_components_by_type("docking_port")
		if not ports.is_empty():
			var p = ports[0]
			return p["rect"].position + p["rect"].size / 2.0
	return Vector2.ZERO

func _get_captured_port_heading(ship) -> float:
	if ship.has_method("get_components_by_type"):
		var ports = ship.get_components_by_type("docking_port")
		if not ports.is_empty():
			return ports[0].get("heading", 0.0)
	return 0.0

func _servo(ship) -> void:
	if not has_servo and state != State.DOCKED:
		return # passive collar, no tractor beam until docked
		
	var port_offset = _get_captured_port_offset(ship)
	var port_global_offset = port_offset.rotated(ship.rotation)
	var target_pos = _berth_pos_for(ship)
	
	var pos_err: Vector2 = target_pos - (ship.position + port_global_offset)
	var accel: Vector2 = K_SPRING * pos_err - K_DAMP * ship.linear_velocity
	ship.apply_central_force(accel * ship.mass)
	
	var port_heading = _get_captured_port_heading(ship)
	var target_rot = global_rotation + PI - port_heading
	var ang_err: float = wrapf(target_rot - ship.rotation, -PI, PI)
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
	slip_claimed = false
	state = State.EMPTY

# M32 -- player/AI-initiated undock: drop the servo spring FIRST (so the pilot
# isn't fighting the clamp on separation), then impart a gentle separation
# impulse along the berth's outward heading (host->berth direction) so the
# ship actually clears the berth instead of drifting/re-triggering capture,
# then release to EMPTY. Called by Ship.request_undock() via the captured
# ship's docking_bay. No-op if nothing is actually docked.
func release_with_push() -> void:
	if not _valid(captured):
		_release()
		return
	var ship = captured
	var host = get_parent()
	var out_dir: Vector2 = Vector2.UP.rotated(global_rotation)
	if host != null:
		var out_vec: Vector2 = global_position - host.global_position
		if out_vec.length() > 0.001:
			out_dir = out_vec.normalized()
	ship.linear_velocity += out_dir * UNDOCK_PUSH_SPEED
	_release()

# Eligible = dockable, actively requesting, and not already claimed by another bay.
# M32 -- when the host station declares a port_zone (controlled), eligibility
# additionally requires a valid grant issued BY THIS STATION, branching on the
# grant's slip_id: >= 0 (assigned) means only the bay whose slip_id matches may
# capture; == -1 (any-open) means any FREE bay may capture (the claim itself
# happens in _try_capture() once this bay wins). A station with NO port_zone
# (get_port_zone() empty) is untouched -- the pre-M32 permissionless check.
func _dockable_seeking(s) -> bool:
	if not _valid(s) or s.get("dockable") != true or s.get("wants_dock") != true:
		return false
	var claim = s.get("docking_bay")
	if not (claim == null or claim == self):
		return false

	var host = get_parent()
	var zone: Dictionary = {}
	if host != null and host.has_method("get_port_zone"):
		zone = host.get_port_zone()
	if zone.is_empty():
		return true   # open/uncontrolled station -- old permissionless behavior

	var grant = s.get("docking_grant")
	if grant == null:
		return false
	var authority: String = zone.get("authority", "")
	if grant.get("authority", "") != authority:
		return false

	var slip: String = grant.get("slip_id", "INVALID")
	if slip != "" and slip != "INVALID":
		return slip == slip_id
	# Any-open (slip == ""): any bay not already claimed by another any-open
	# holder and not otherwise occupied may accept.
	return not slip_claimed

func _valid(n) -> bool:
	return n != null and is_instance_valid(n)
