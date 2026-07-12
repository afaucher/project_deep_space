extends "res://addons/beehave/nodes/leaves/action.gd"

# M20 -- cargo run: drive a shuttle around its lane (patrol_route = station
# positions), docking at each stop, then moving on. Two states per stop:
# TRANSIT (cruise to the station) and DOCKING (yield to the station's berth while
# it captures/holds/releases us). Returns FAILURE with no route so the selector
# falls through to Idle. See implementation_plans/m20_traffic_wiring_design.md.
#
# M32 -- controlled-station parity: at a CONTROLLED stop (station's
# get_port_zone() non-empty) the leaf runs the SAME lifecycle as the player --
# request a grant via the shared Station.issue_docking_grant() BEFORE raising
# wants_dock; no grant (full or otherwise ineligible) means the shuttle holds
# near the approach point and retries next tick rather than piling up at the
# capture radius with nothing to show for it. At an OPEN stop (no port_zone)
# the old permissionless wants_dock-only path is unchanged.
#
# Undock: cargo shuttles never set manual_undock (it defaults false), so
# DockingBay's original M19 auto-release-after-dock_duration timer still owns
# their release, at both open AND controlled stops -- the leaf doesn't call
# request_undock() itself. That command exists for the manual-hold path (a
# ship that DID set manual_undock=true); wiring the cargo AI onto it too is a
# judgment call left for when a controlled route actually needs a longer,
# business-gated hold rather than the fixed timer (out of scope here -- noted
# in the M32 report).

const Steering = preload("res://scripts/ai/steering.gd")

const DOCK_REQUEST_RADIUS := 4000.0   # raise the dock request within this of the station
const CARGO_CRUISE := 700.0           # transit speed
const STATION_SEARCH_RADIUS := 6000.0 # how close a "ships"-group node must be to count as "the station here"

func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return FAILURE
	var route: Array = actor.patrol_route
	if route.is_empty():
		return FAILURE
	var idx: int = actor.patrol_index
	if idx < 0 or idx >= route.size():
		idx = 0
	var target: Vector2 = route[idx]

	if not actor.cargo_docking:
		# TRANSIT to the current station.
		if actor.position.distance_to(target) < DOCK_REQUEST_RADIUS:
			var station = _find_station_at(actor, target)
			var zone: Dictionary = {}
			if station != null and station.has_method("get_port_zone"):
				zone = station.get_port_zone()
			if not zone.is_empty():
				# Controlled stop -- must hold a grant before wants_dock does anything
				# (DockingBay's gate rejects an ungranted ship at a controlled bay).
				if actor.get("docking_grant") == null:
					station.issue_docking_grant(actor)   # null (no berths) just means retry next tick
				if actor.get("docking_grant") != null:
					actor.cargo_docking = true
					actor.cargo_captured_seen = false
					actor.wants_dock = true
				# else: no grant yet (full or zone hiccup) -- hold and retry.
			else:
				actor.cargo_docking = true
				actor.cargo_captured_seen = false
				actor.wants_dock = true
		else:
			_cruise_to(actor, target)
		return SUCCESS

	# DOCKING at the current station.
	if actor.docking_bay != null:
		# Captured -> yield: coast so the berth spring owns the motion.
		actor.cargo_captured_seen = true
		actor.apply_control_input(0.0, 0.0, actor.rotation, 0, 0)
	elif actor.cargo_captured_seen and not actor.wants_dock:
		# The bay finished its load/unload cycle and released us -> next station.
		if actor.patrol_loop:
			idx = (idx + 1) % route.size()
		else:
			idx = min(idx + 1, route.size() - 1)
		actor.patrol_index = idx
		actor.cargo_docking = false
	elif not actor.cargo_captured_seen and not actor.wants_dock:
		# Released WITHOUT ever docking -- the bay aborted the capture
		# (CAPTURE_TIMEOUT on an unwinnable chase, or a clamp snap) and
		# _release() cleared wants_dock. Without this branch the shuttle
		# cruises the approach point forever with wants_dock down, never
		# capturable again. Drop back to TRANSIT: the arrival check re-runs,
		# re-requests a grant, and re-raises wants_dock cleanly.
		actor.cargo_docking = false
	else:
		var grant = actor.get("docking_grant")
		if grant != null and grant.get("slip_id", "") != "":
			var station = _find_station_at(actor, target)
			if station != null:
				for b in station.get_berths():
					if b.slip_id == grant.get("slip_id", ""):
						var approach_pt = b.global_position + Vector2.RIGHT.rotated(b.global_rotation) * 2000.0
						_cruise_to(actor, approach_pt)
						return RUNNING
		# Fallback if no slip is assigned yet (e.g. uncontrolled station).
		# Seek the first bay's approach point so we can enter its capture cone.
		var station = _find_station_at(actor, target)
		if station != null:
			var bays = station.get_berths()
			if bays.size() > 0:
				var b = bays[0]
				var approach_pt = b.global_position + Vector2.RIGHT.rotated(b.global_rotation) * 2000.0
				_cruise_to(actor, approach_pt)
				return RUNNING
				
		actor.apply_control_input(0.0, 0.0, (target - actor.position).angle(), 1, 1)
	return SUCCESS

# Resolve the actual station node standing at (near) this stop's waypoint, so
# the leaf can call its issue_docking_grant()/get_port_zone(). patrol_route is
# just Vector2 waypoints (no node reference), so this is a cheap proximity
# lookup in the same "ships" group _update_port_zone_membership() already
# scans -- bounded to a handful of stations in a sim bubble, not hundreds.
func _find_station_at(actor: Node, waypoint: Vector2):
	var tree = actor.get_tree()
	if tree == null:
		return null
	var best = null
	var best_d: float = STATION_SEARCH_RADIUS
	for s in tree.get_nodes_in_group("ships"):
		if s == actor: continue
		if not s.has_method("get_berths"): continue
		if s.get_berths().is_empty(): continue
		if s.get('ship_tier') != 4: continue # ComponentSpec.Tier.STRUCTURE
		var d: float = s.position.distance_to(waypoint)
		if d <= best_d:
			best = s
			best_d = d
	return best

func _cruise_to(actor: Node, target: Vector2) -> void:
	var desired: Vector2 = target - actor.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	# Avoid obstacles in transit, but not the destination station itself.
	var avoided: Vector2 = Steering.steer(actor, desired, target)
	var desired_vel: Vector2 = avoided.normalized() * CARGO_CRUISE
	var steer: Vector2 = desired_vel - actor.linear_velocity
	if steer.length() < 10.0:
		steer = desired_vel
	actor.apply_control_input(0.0, CARGO_CRUISE, steer.angle(), 1, 1)
