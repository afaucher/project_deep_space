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
# overshoot).
#
# Softened from the original K_SPRING=4/K_DAMP=4 (~0.5s time constant) after
# player feedback ("the docking clamp really yanks you") -- roughly half the
# stiffness, ~1s time constant, same critically-damped ratio so it still
# settles cleanly without overshoot/oscillation, just less violently. Paired
# with the capture_radius clamp above (docking_port loop, ship.gd) which
# stops capture from engaging so far out that the initial pos_err -- and
# therefore the initial jerk -- was large to begin with.
const K_SPRING := 2.0
const K_DAMP := 2.83   # ~2*sqrt(K_SPRING), critically damped
const K_ROT := 3.0
const K_ROT_DAMP := 3.46   # ~2*sqrt(K_ROT), critically damped

# Yield strength of the clamp (distance error before it snaps). Allows forceful breakaway.
const YIELD_STRENGTH := 200.0

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

# A capture that hasn't settled into DOCKED within this many seconds aborts
# and frees the bay. Without it, a chase that can never settle -- most
# concretely a berth pose orbiting on a spinning station (the campaign
# "port control says negative but the indicator shows" bug) -- wedges the
# bay in CAPTURING forever: the berth pool reads permanently full, and the
# captured ship's grant countdown stays frozen (see
# Ship._update_docking_grant's fulfilled pause), keeping stale docking
# indicators alive. Generous vs the spring's ~1s time constant: a healthy
# capture settles in a few seconds even from the capture radius' edge.
const CAPTURE_TIMEOUT := 20.0

var state: int = State.EMPTY
var captured = null
var _dock_timer := 0.0
var _capture_timer := 0.0

func _enter_tree() -> void:
	add_to_group("docking_bays")

func _exit_tree() -> void:
	remove_from_group("docking_bays")

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
				_capture_timer += delta
				if _capture_timer > CAPTURE_TIMEOUT:
					_release()   # unwinnable capture -- free the bay (see CAPTURE_TIMEOUT)
					return
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
					# Engineering-log entry on the DOCKED transition (the
					# moment the clamps actually have the ship) -- the
					# player-facing record that docking succeeded, alongside
					# the repair/damage entries M40 already logs.
					var host = get_parent()
					if captured.has_method("log_event"):
						var host_label: String = ""
						if host != null:
							host_label = str(host.get("ship_name")) if host.get("ship_name") != null else host.name
						captured.log_event("info", "Docked at %s berth %s" % [host_label, slip_id])
					# M53b Pass 1 -- record the arrival in the STATION's own
					# docking registry (Ship.record_docking_event). THIS
					# transition, not grant issuance, is the convergence
					# point both the player (port_control.request_docking)
					# and NPC (Ship.issue_docking_grant called directly by
					# AI) docking paths funnel through -- see docking_bay.gd
					# file header / Ship.docking_registry doc comment.
					if host != null and host.has_method("record_docking_event"):
						var subject: Dictionary = {}
						if captured.has_method("get_active_transponder_data"):
							subject = captured.get_active_transponder_data()
						host.record_docking_event(subject.get("name", ""), subject.get("flag", ""), "DOCKED")
					# M58 -- THE COURIER STEP. Mail rides hulls, and this dock is where a
					# visiting ship's mailbag and the station's meet -- the only way news
					# crosses a gap wider than radio range. No courier NPC is needed:
					# haulers already fly station to station as a side effect of the
					# economy, so the carrier network IS the trade network.
					#
					# The policy (receive freely, give deliberately, then notarize what we
					# have authority over) lives on Ship, NOT here. Two reasons: a bay is a
					# mechanism and should not hold faction policy, and preloading the mail
					# module here re-entered the ship.gd <-> docking_bay.gd class cycle
					# (ship.gd already preloads DockingBay), which surfaces as an
					# unresolvable `Ship` and HANGS the test rather than failing it.
					if host != null and host.has_method("exchange_mail_on_dock"):
						host.exchange_mail_on_dock(captured)
					# M53c Phase C -- the delivery seam: settle whatever cargo
					# transaction the ship staged for THIS stop (design doc:
					# "a delivery is an EVENT (a dock), not a cargo transfer").
					# Read-and-clear so a stale/mis-timed acceptance can never
					# settle twice against a later, unrelated dock. Reuses
					# Ship.serve_posting() -- the SAME admission-gated seam
					# Phase B built (DOCKED-at-this-host-bay is exactly what
					# just became true above), so there is no second gate to
					# get wrong. captured.get()/host.has_method() (not a direct
					# field read) because a non-Ship dockable or a host with no
					# serve_posting method must no-op cleanly rather than error.
					if host != null and host.has_method("serve_posting"):
						var pending = captured.get("pending_delivery")
						if pending is Dictionary and not pending.is_empty():
							captured.pending_delivery = {}
							host.serve_posting(captured, pending.get("acceptance", {}), pending.get("amount", 0.0))
		State.DOCKED:
			if not _valid(captured):
				_release()
			else:
				_servo(captured)          # keep it seated while loading
				
				# M19 -- Clamp Snapping / Forceful Breakaway.
				# The spring has a physical yield strength. If the ship fires its engines
				# hard enough to stretch the spring beyond this distance error, the clamp breaks.
				var port_offset = _get_captured_port_offset(captured)
				var port_global_offset = port_offset.rotated(captured.rotation)
				var pos_err: float = _berth_pos_for(captured).distance_to(captured.position + port_global_offset)
				
				if pos_err > YIELD_STRENGTH:
					_release()
					return # Clamp snapped!
				
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
		# Measured from the DOCKING POINT (the clearance-adjusted seat,
		# _berth_pos_for -- same reference the nav panel's capture-zone circle
		# draws around), not the raw authored bay position. Those two used to
		# diverge for any berth where the standoff pushes the seat well
		# outward (a big hull, or a berth mounted close to the hull) --
		# capture engaged from a circle centered well INSIDE the one actually
		# drawn on the map, so the clamp visibly grabbed ships long before
		# they crossed the visible ring ("the actual zone is about half as
		# wide"). The hemisphere check below still uses the raw bay position/
		# heading -- standoff moves the seat, not the port's own facing.
		var d: float = _berth_pos_for(s).distance_to(s.position)
		if d <= best_d:
			# M32: Only capture if the ship is in the approach HEMISPHERE (in
			# front of the port), so we never tractor a ship through the station
			# hull from the far side. `> 0.0` is the hemisphere (reject only what's
			# behind the port); the earlier `> 0.866` was a 30-degree cone that
			# contradicted this comment and rejected legitimate off-axis approaches
			# (a shuttle ~31 degrees off the port axis -- see test_docking). Any
			# tighter "fly down the lane" discipline belongs to the M34 lane aid,
			# not a hard capture gate.
			var dir_to_ship = (s.position - global_position).normalized()
			var bay_forward = Vector2.RIGHT.rotated(global_rotation)
			if dir_to_ship.dot(bay_forward) > 0.0:
				best = s
				best_d = d
	if best != null:
		captured = best
		captured.docking_bay = self   # claim it so no other bay double-captures
		state = State.CAPTURING
		_capture_timer = 0.0
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
	if ship == null or not ship.has_method("get_bounding_radius"):
		return global_position
	return berth_pos_for_bounding_radius(ship.get_bounding_radius())

# Public variant of the above that doesn't need a live ship node -- only its
# bounding radius. A UI draw call (navigation_panel.gd's docking nav aids) has
# no ship Node reference for a berth it's merely illustrating, just the
# player's own bounding_radius already carried on the state packet; before
# this existed, the nav panel drew the marker/lane at the raw authored pose
# (global_position) instead of this clearance-adjusted seat, which for a
# berth mounted close to a large hull (e.g. Ironhold's dock_main sits ~195u
# out while the required standoff is 264(hull) + ship + 25(margin) =~ 300u+)
# put the marker HALF INSIDE the station -- nowhere near where a ship (NPC or
# player) actually comes to rest.
func berth_pos_for_bounding_radius(other_bounding_radius: float) -> Vector2:
	var host = get_parent()
	if host == null or not host.has_method("get_bounding_radius"):
		return global_position
	var out_vec: Vector2 = global_position - host.global_position
	var berth_dist: float = out_vec.length()
	if berth_dist < 0.001:
		return global_position
	var required: float = host.get_bounding_radius() + other_bounding_radius + CLEARANCE_MARGIN
	if required <= berth_dist:
		return global_position
	return host.global_position + out_vec / berth_dist * required

func _release() -> void:
	if _valid(captured):
		# Log/record only a release FROM DOCKED (a completed stay) -- an
		# aborted capture never actually docked, and logging those would spam
		# the engineering log (and the station's docking registry) on every
		# timeout/retry cycle.
		if state == State.DOCKED:
			if captured.has_method("log_event"):
				captured.log_event("info", "Released from berth " + slip_id)
			# M53b Pass 1 -- symmetric departure record alongside the
			# DOCKED-transition arrival record above (Ship.docking_registry /
			# record_docking_event) -- same convergence point, same station.
			var release_host = get_parent()
			if release_host != null and release_host.has_method("record_docking_event"):
				var subject: Dictionary = {}
				if captured.has_method("get_active_transponder_data"):
					subject = captured.get_active_transponder_data()
				release_host.record_docking_event(subject.get("name", ""), subject.get("flag", ""), "DEPARTED")
		captured.wants_dock = false
		captured.docking_bay = null
		# The docking transaction with THIS station is over (completed hold,
		# manual undock, aborted capture, or clamp snap) -- consume the grant
		# so the slip returns to the pool IMMEDIATELY. Without this, a
		# departed ship's grant kept its slip reserved until the 120s
		# countdown or zone-exit, which with two cargo shuttles cycling could
		# hold BOTH of a station's physically-empty berths against the player
		# for long stretches ("Negative, we have no open berths" with an
		# empty dock -- found via the berth-check logging this fix shipped
		# with). Only clear a grant this bay's own host issued -- a grant
		# from some OTHER authority is none of this bay's business.
		var grant = captured.get("docking_grant")
		var host = get_parent()
		if grant != null and host != null and host.has_method("get_port_zone"):
			var host_authority: String = host.get_port_zone().get("authority", "")
			if grant.get("authority", "") == host_authority:
				captured.docking_grant = null
				# Departure corridor: keep the CHANNEL drawable (not the
				# slip reservation, already freed above) until the ship
				# actually clears the exclusion boundary -- see
				# departing_slip's own comment on ship.gd. Applies to any
				# release from a granted stay, not just a completed DOCKED
				# hold -- an aborted capture (CAPTURE_TIMEOUT) leaves the
				# ship just as deep inside the disc and just as in need of
				# an exit path.
				captured.departing_slip = {"authority": host_authority, "slip_id": slip_id}
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
	var grant = s.get("docking_grant")

	if zone.is_empty():
		# open/uncontrolled station -- old permissionless behavior, BUT we should NOT
		# kidnap a ship that explicitly holds a grant for a different controlled station.
		if grant != null and grant.get("authority", "") != "":
			return false
		return true

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
