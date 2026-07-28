extends Node
class_name MissileController

const Standing = preload("res://scripts/combat/standing.gd")

# Guidance-law tuning. FUEL_LIFETIME bounds effective engagement range/time
# together with the missile's own max_speed; the lock-related thresholds
# trade lock stability against how easy a target is to break lock by breaking
# sensor contact.
const FUEL_LIFETIME := 15.0          # seconds before self-destruct ("ran out of fuel")
const COMBAT_DEBUG := false          # gate verbose [Missile] lifecycle traces
const LOCK_LOSS_STALENESS := 5.0     # seconds an existing lock's contact can go unrefreshed before it's dropped
const ACQUISITION_FRESHNESS := 1.0   # seconds a contact must have been refreshed within to be eligible for a *new* lock (stricter than keeping one)
const LEAD_TIME_CAP := 0.7           # seconds -- caps how far ahead proportional-nav aims so the missile doesn't cross the target's path
const VELOCITY_STEER_THRESHOLD := 10.0 # below this velocity error, steer directly at the intercept point instead of the desired-velocity vector
const SEEKER_EDGE_MARGIN := 10.0     # degrees of margin kept off the seeker's edge so the target doesn't fall out of FOV next frame
const SEEKER_FALLBACK_HALF_ARC := PI / 3.0 # used only if no seeker component is found (shouldn't happen in practice)
const PROXIMITY_FUSE_RANGE := 100.0  # distance at which the warhead detonates
const WARHEAD_DAMAGE := 250.0
const JINK_INTERVAL := 0.25          # seconds between evasive heading re-rolls (~4 Hz) -- DebugSettings.missile_jink
const JINK_MAX_ANGLE := deg_to_rad(10.0) # max evasive offset from the target bearing
# How long a DEAD missile (fuel-out dud, or gutted by PD without detonating)
# drifts as sensor-visible wreckage before despawning. Detonation already
# frees the node immediately; without this, every dud lingered FOREVER as a
# full Ship instance paying the entire per-ship physics tick -- the combat
# perf census measured dead hulks (mostly missiles) at ~19% of the "ships"
# group and climbing, an unbounded accumulation over a long fight. The linger
# keeps the "it went dark and drifted" sensor read (classifies WRECKAGE,
# EM-dark) for a while; the despawn then uses the same
# purge_despawned_contact path as detonation so observers' tracks clean up
# per the selected contact-cleanup mode instead of ghosting for the full
# CONTACT_TIMEOUT. 2 minutes: long enough that battlefield debris feels
# persistent to a player watching the aftermath, while still bounding the
# dead-ship population (steady-state dead weight = death rate x this).
const WRECKAGE_LINGER := 120.0

var ship: RigidBody2D
var target_id: String = ""
var age: float = 0.0
var _jink_timer: float = 0.0
var _jink_offset: float = 0.0
var _wreckage_age: float = 0.0

func _ready() -> void:
	ship = get_parent()
	if not ship or not ship.has_method("apply_control_input"):
		set_physics_process(false)
		push_error("MissileController must be a child of a Ship")

func _physics_process(delta: float) -> void:
	# Guidance body lives in _guidance_tick so its early returns can't skip
	# the PerfProbe end() -- this controller runs per missile per frame and
	# was previously invisible in the attribution table (untagged).
	PerfProbe.begin("missile_controller")
	if ship.is_dead:
		# Dead missile (dud/fuel-out/PD kill that didn't detonate): drift as
		# wreckage for WRECKAGE_LINGER, then despawn. Guidance's own is_dead
		# early-return means this clock must run out here, not in there.
		if multiplayer.is_server():
			_wreckage_age += delta
			if _wreckage_age > WRECKAGE_LINGER:
				set_physics_process(false) # queue_free defers -- don't re-run while dying
				Ship.purge_despawned_contact(ship.get_tree(), ship.get_instance_id(), ship.position)
				ship.queue_free()
	else:
		_guidance_tick(delta)
	PerfProbe.end("missile_controller")

func _guidance_tick(delta: float) -> void:
	if not multiplayer.is_server(): return
	if ship.is_dead: return

	age += delta

	# Evasive jink: periodically re-roll a small heading offset so the missile weaves,
	# keeping the PD firing solution (built on our tracked heading) stale. Off by default.
	if DebugSettings.get_choice("missile_jink") == DebugSettings.MissileJink.ON:
		_jink_timer -= delta
		if _jink_timer <= 0.0:
			_jink_offset = randf_range(-JINK_MAX_ANGLE, JINK_MAX_ANGLE)
			_jink_timer = JINK_INTERVAL
	else:
		_jink_offset = 0.0

	if age > FUEL_LIFETIME:
		# Run out of fuel, self-destruct or go inert
		if COMBAT_DEBUG: print("[Missile] Out of fuel looking for target")
		ship.hulk()
		return
		
	# Check if current target is valid
	var current_target_valid = false
	if target_id != "" and ship.active_contacts.has(target_id):
		var contact = ship.active_contacts[target_id]
		if contact.get("pos_timer", 0.0) <= LOCK_LOSS_STALENESS:
			current_target_valid = true
			
	if not current_target_valid:
		if target_id != "":
			if COMBAT_DEBUG: print("[Missile] Lost lock on target cid: ", target_id)
			target_id = ""
			
		# Find closest hostile target in own sensors
		var best_dist = 999999.0
		var new_target = ""
		
		for c_id in ship.active_contacts:
			var contact = ship.active_contacts[c_id]
			var classification = contact.get("classification", "")
			# M48 -- a missile is COMMITTED ORDNANCE, and the Missile hull has
			# no comms component: it can never receive a transponder flag, so
			# it can never independently compute Standing.HOSTILE (a re-sensed
			# target reads CAUTION to it). Its LAUNCHER already made the
			# hostile judgment at fire time -- the missile inherits that lock
			# at launch. So reacquisition keys on CLASSIFICATION (any
			# non-friendly vessel is a valid re-lock for a dumb weapon already
			# loosed at a hostile), NOT on a standing the missile physically
			# cannot earn. Gating reacquire on HOSTILE made the seeker
			# permanently drop its lock the moment the inherited contact went
			# stale (LOCK_LOSS_STALENESS), so every missile flew straight past
			# -- gutting the primary weapon of every missile-armed AI and
			# tripling time-to-kill. (This is the pre-M48 behavior; a missile
			# "remembering" its designated target's identity to avoid
			# re-locking a passing neutral is a future piracy refinement.)
			if classification != "UNIDENTIFIED VESSEL" and classification != "INCOMING ORDNANCE":
				continue
			if contact.get("pos_timer", 0.0) > ACQUISITION_FRESHNESS:
				continue # Need a fresh contact to acquire lock
				
			var dist_to = ship.position.distance_to(contact["pos"])
			if dist_to < best_dist:
				best_dist = dist_to
				new_target = c_id
				
		if new_target != "":
			target_id = new_target
			if COMBAT_DEBUG: print("[Missile] Acquired new target cid: ", target_id)
			
	if target_id == "":
		# No target and no fallback, fly straight
		ship.apply_control_input(1.0, 0.0, ship.rotation, 1, 0)
		return
		
	var target = ship.active_contacts[target_id]
	var target_pos = target["pos"]
	var target_vel = target["vel"]
	
	# Proportional Navigation (simplified lead pursuit)
	var rel_pos = target_pos - ship.position
	var rel_vel = target_vel - ship.linear_velocity
	var closing_vel = -rel_pos.normalized().dot(rel_vel)
	
	var time_to_impact = 0.0
	if closing_vel > 0.0:
		time_to_impact = rel_pos.length() / closing_vel
	else:
		time_to_impact = rel_pos.length() / max(1.0, ship.linear_velocity.length())
		
	# Cap the lead time so the missile doesn't aim too far ahead and cross the target's path
	time_to_impact = min(time_to_impact, LEAD_TIME_CAP)
		
	var intercept_pos = target_pos + (target_vel * time_to_impact)
	
	var desired_vel = (intercept_pos - ship.position).normalized() * ship.max_speed
	var vel_error = desired_vel - ship.linear_velocity
	var desired_heading = ship.rotation
	if vel_error.length() > VELOCITY_STEER_THRESHOLD:
		desired_heading = vel_error.angle()
	else:
		desired_heading = (intercept_pos - ship.position).angle()
	
	# Clamp heading to keep target within seeker cone
	var angle_to_target = rel_pos.angle()
	var seeker_half_arc = SEEKER_FALLBACK_HALF_ARC
	for s in ship.get_components_by_type("sensors"):
		if s["id"] == "seeker":
			seeker_half_arc = s["arc_width"] / 2.0
			break
	var max_lead = max(0.1, seeker_half_arc - deg_to_rad(SEEKER_EDGE_MARGIN))
	var lead_angle_diff = wrapf(desired_heading - angle_to_target, -PI, PI)
	# Add the evasive jink here (before the clamp) so the weave is bounded by the
	# seeker cone -- the target never falls out of FOV, so we keep lock while jinking.
	lead_angle_diff += _jink_offset
	lead_angle_diff = clampf(lead_angle_diff, -max_lead, max_lead)
	desired_heading = angle_to_target + lead_angle_diff
	
	# Full thrust, steer in the drift-compensated direction
	ship.apply_control_input(1.0, 0.0, desired_heading, 1, 0)
	
	# Warhead detonate logic
	if rel_pos.length() < PROXIMITY_FUSE_RANGE:
		detonate()

func detonate() -> void:
	if ship.is_dead: return

	# A missile is only lethal if its warhead survived. PD that guts the "warhead"
	# component duds the missile: it still expends itself on the proximity fuse
	# below, but deals no damage. (A reactor/hull kill stops it even earlier via
	# is_dead.) This makes the warhead a meaningful PD target instead of a decorative
	# HP box -- see design_ideas/warhead_laser_special_case.md.
	var warhead = ship.get_component("warhead")
	var warhead_live = not warhead.is_empty() and warhead.get("health", 0.0) > 0.0

	if warhead_live and target_id != "" and ship.active_contacts.has(target_id):
		var target_pos = ship.active_contacts[target_id]["pos"]
		var space_state = ship.get_world_2d().direct_space_state
		var dir = (target_pos - ship.position).normalized()
		var end_pos = ship.position + dir * 2000.0 # Extend ray well past the target
		var query = PhysicsRayQueryParameters2D.create(ship.position, end_pos)
		var result = space_state.intersect_ray(query)
		
		# Draw the laser beam (fire and forget visual)
		var main_node = ship.get_tree().current_scene
		if main_node and main_node.has_method("draw_laser"):
			main_node.draw_laser(ship.position, target_pos)
			
		if COMBAT_DEBUG: print("[Missile] Firing laser warhead at target: ", target_id, " from ", ship.position, " to ", target_pos)
			
		if result and result.collider.has_method("take_damage") and result.collider != ship:
			var hit_dir = (result.collider.position - ship.position).normalized()
			# Missiles are laser-heads, so they deal laser damage (which applies extreme heat)
			# M48 -- attribute to the LAUNCHER, not the missile itself (the missile is
			# about to be freed; the launcher is the one whose standing/wanted-name
			# should be affected).
			result.collider.take_damage(WARHEAD_DAMAGE, result.position, hit_dir, "laser", ship.launcher_instance_id)
			
	# Destroy missile. Before it's freed, clean up observers' tracks of it per the
	# selected debug cleanup mode -- otherwise every ship that saw it keeps a
	# dead-reckoned ghost gliding on for the full CONTACT_TIMEOUT.
	Ship.purge_despawned_contact(ship.get_tree(), ship.get_instance_id(), ship.position)
	ship.hulk()
	ship.queue_free()
