extends Node

# M28 acceptance -- kinetic collision damage
# (implementation_plans/m28_m30_collision_roadmap.md, M28 section). Physical
# impacts above COLLISION_DAMAGE_MIN_SPEED (150 u/s) hurt; below it they are
# free. No blanket exemptions -- docking and missiles are NOT special-cased,
# they are protected (or not) purely by the speed gate, which is exactly what
# items 4 and 5 below prove.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_collision_damage
# Pass marker per CLAUDE.md.
#
# Structure: a sequence of self-contained PHASES, each spawning its own bodies
# fresh (freeing the previous phase's) so contact state never leaks between
# scenarios. _physics_process dispatches on `phase` and each phase's own timer.

const Frigate = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Freighter = preload("res://scripts/ships/freighter.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const DebugSettingsScript = preload("res://scripts/debug_settings.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var phase: String = ""
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _total_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += max(0.0, c.get("health", 0.0))
	return h

func _max_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += c.get("max_health", 0.0)
	return h

func _comp_health(ship, comp_id: String) -> float:
	for c in ship.ship_components:
		if c["id"] == comp_id:
			return c["health"]
	return -1.0

# Sum of (max_health - health) for every component whose rect lies at local-x
# >= x_min (nose-side components: hull_fwd, dir_high_res, hp_fwd_* -- all the
# forward hardpoints) -- used to check "impact-side took the hit" without
# depending on the raymarch happening to land on one specific named plate
# (a nose-mounted sensor sitting further out on the same axis can legitimately
# absorb a hit before it reaches hull_fwd behind it -- that's still "impact
# side took it", just distributed across whichever forward components the ray
# actually passed through).
func _region_damage(ship, x_min: float) -> float:
	var dmg: float = 0.0
	for c in ship.ship_components:
		var rect: Rect2 = c["rect"]
		if rect.position.x >= x_min:
			dmg += max(0.0, c["max_health"] - c["health"])
	return dmg

# Unclamped damage-absorbed total (sum of max_health - health across every
# component, allowing a component's raw health to go negative under the sum
# rather than flooring each one at 0 first). This is the true measure of how
# much damage the raymarch actually dealt, independent of which single
# component happened to absorb it -- _total_health()'s per-component floor
# means a hit that overkills a low-max_health component (e.g. a 50 HP sensor
# eating a 1400-point hit) reports only that component's own max as "visible"
# health lost, understating the real damage dealt. Symmetry (item 6) compares
# the underlying damage formula's output, so it needs the unclamped total.
func _raw_damage_absorbed(ship) -> float:
	var dmg: float = 0.0
	for c in ship.ship_components:
		dmg += c["max_health"] - c["health"]
	return dmg

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func setup(main) -> void:
	main_node = main
	print("Starting Collision Damage (M28) Tests")
	_start_phase_1()

# ---------------------------------------------------------------------------
# Phase 1: head-on above threshold. Two frigates closing at ~400 u/s combined
# (200 each, opposite directions) along +X, aligned so the impact face is the
# nose (hull_fwd) on one and the aft/stbd side on the other -- assert BOTH take
# damage, and on each, the impact-side plate's health drops below the far-side
# plate's (proves the raymarch entered from the contact face).
# ---------------------------------------------------------------------------
var f1 = null
var f2 = null
var p1_frigate_dmg: float = 0.0  # raw damage a like-speed frigate-vs-frigate hit deals; phase 5 compares the missile hit against it
const PHASE1_APPROACH := 600.0
const PHASE1_SPEED := 200.0
const PHASE1_TIMEOUT := 10.0

func _start_phase_1() -> void:
	phase = "phase_1"
	t = 0.0
	print("--- Phase 1: head-on above threshold (~400 u/s combined) ---")
	f1 = Frigate.new()
	f1.name = "F1_Nose"
	f1.owner_id = 601
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(-PHASE1_APPROACH, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE1_SPEED, 0)

	f2 = Frigate.new()
	f2.name = "F2_Facing"
	f2.owner_id = 602
	f2.iff_tags = ["TEAM_B"]
	f2.position = Vector2(PHASE1_APPROACH, 0)
	f2.rotation = PI  # nose points back at f1 -- symmetric head-on nose-to-nose
	main_node.add_child(f2)
	f2.linear_velocity = Vector2(-PHASE1_SPEED, 0)

func _phase_1_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(f2.position) <= (f1.get_bounding_radius() + f2.get_bounding_radius() + 5.0)
	var f1_damaged: bool = _total_health(f1) < _max_health(f1) - 0.01
	var f2_damaged: bool = _total_health(f2) < _max_health(f2) - 0.01

	if (contact and f1_damaged and f2_damaged) or t > PHASE1_TIMEOUT:
		# f1 faces +X (nose = forward hardpoints at local x>=15: hull_fwd,
		# dir_high_res, hp_fwd_laser, hp_fwd_missile); f2 is nose-to-nose with it
		# (rotation=PI), so f1 is hit on its nose. Compare damage absorbed by the
		# nose-region components vs the aft-region ones (hull_aft, engine_main at
		# local x<=-15) -- proves the raymarch entered from the contact face
		# without depending on the hit landing on one specific named plate (a
		# nose sensor mounted further out than hull_fwd on the same axis can
		# legitimately absorb the hit first).
		var nose_dmg: float = _region_damage(f1, 15.0)
		var aft_dmg: float = 0.0
		for c in f1.ship_components:
			var rect: Rect2 = c["rect"]
			if rect.position.x <= -15.0:
				aft_dmg += max(0.0, c["max_health"] - c["health"])
		print("[P1] f1 health %.1f/%.1f  f2 health %.1f/%.1f  f1 nose_dmg=%.1f aft_dmg=%.1f  contact=%s" % [
			_total_health(f1), _max_health(f1), _total_health(f2), _max_health(f2), nose_dmg, aft_dmg, str(contact)])
		_assert(t <= PHASE1_TIMEOUT, "phase 1: ships should collide within timeout")
		_assert(f1_damaged, "phase 1: f1 should take collision damage")
		_assert(f2_damaged, "phase 1: f2 should take collision damage")
		_assert(nose_dmg > aft_dmg, "phase 1: impact-side (nose) damage (%.1f) should exceed far-side (aft) damage (%.1f)" % [nose_dmg, aft_dmg])
		# Baseline for phase 5 mildness check: raw damage a 400 u/s frigate ram deals.
		p1_frigate_dmg = _raw_damage_absorbed(f1)
		_free_if_valid(f1)
		_free_if_valid(f2)
		_start_phase_2()

# ---------------------------------------------------------------------------
# Phase 2: gentle bump. Closing at 60 u/s (well under 150 threshold) -> zero
# damage on both sides once they've made contact and separated/settled.
# ---------------------------------------------------------------------------
const PHASE2_APPROACH := 200.0
const PHASE2_SPEED := 30.0
const PHASE2_TIMEOUT := 12.0
var p2_contacted: bool = false
var p2_contact_time: float = 0.0

func _start_phase_2() -> void:
	phase = "phase_2"
	t = 0.0
	p2_contacted = false
	print("--- Phase 2: gentle bump (60 u/s combined, under threshold) ---")
	f1 = Frigate.new()
	f1.name = "F1_Gentle"
	f1.owner_id = 611
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(-PHASE2_APPROACH, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE2_SPEED, 0)

	f2 = Frigate.new()
	f2.name = "F2_Gentle"
	f2.owner_id = 612
	f2.iff_tags = ["TEAM_B"]
	f2.position = Vector2(PHASE2_APPROACH, 0)
	f2.rotation = PI
	main_node.add_child(f2)
	f2.linear_velocity = Vector2(-PHASE2_SPEED, 0)

func _phase_2_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(f2.position) <= (f1.get_bounding_radius() + f2.get_bounding_radius() + 5.0)
	if contact and not p2_contacted:
		p2_contacted = true
		p2_contact_time = t

	# Give it 2s past contact for any (incorrect) damage to land, then check.
	if (p2_contacted and t > p2_contact_time + 2.0) or t > PHASE2_TIMEOUT:
		print("[P2] contacted=%s f1 health %.1f/%.1f  f2 health %.1f/%.1f" % [
			str(p2_contacted), _total_health(f1), _max_health(f1), _total_health(f2), _max_health(f2)])
		_assert(p2_contacted, "phase 2: ships should have made contact")
		_assert(_total_health(f1) >= _max_health(f1) - 0.01, "phase 2: f1 should take zero damage from gentle bump")
		_assert(_total_health(f2) >= _max_health(f2) - 0.01, "phase 2: f2 should take zero damage from gentle bump")
		_free_if_valid(f1)
		_free_if_valid(f2)
		_start_phase_3()

# ---------------------------------------------------------------------------
# Phase 3: rock ram. Ship rams an asteroid well above threshold -> ship takes
# damage, asteroid unaffected (no take_damage method), zero script errors
# (the has_method guard on the asteroid side; the asteroid's own handler
# doesn't exist since it's not a Ship, so only the ship's own contact fires).
# ---------------------------------------------------------------------------
const PHASE3_SPEED := 400.0
const PHASE3_TIMEOUT := 8.0
var rock = null

func _start_phase_3() -> void:
	phase = "phase_3"
	t = 0.0
	print("--- Phase 3: rock ram (400 u/s, well above threshold) ---")
	rock = Asteroid.new()
	rock.name = "Rock"
	rock.position = Vector2(1000, 0)
	main_node.add_child(rock)

	f1 = Frigate.new()
	f1.name = "F1_Rammer"
	f1.owner_id = 621
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(0, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE3_SPEED, 0)

func _phase_3_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(rock.position) <= (f1.get_bounding_radius() + rock.get_bounding_radius() + 5.0)
	var f1_damaged: bool = _total_health(f1) < _max_health(f1) - 0.01

	if (contact and f1_damaged) or t > PHASE3_TIMEOUT:
		print("[P3] f1 health %.1f/%.1f  rock still valid=%s" % [_total_health(f1), _max_health(f1), str(is_instance_valid(rock))])
		_assert(t <= PHASE3_TIMEOUT, "phase 3: ship should ram the asteroid within timeout")
		_assert(f1_damaged, "phase 3: ship should take damage from ramming the asteroid")
		_assert(is_instance_valid(rock), "phase 3: asteroid should be unaffected (still valid, no take_damage to call)")
		_free_if_valid(f1)
		_free_if_valid(rock)
		_start_phase_4()

# ---------------------------------------------------------------------------
# Phase 4: routine docking stays sub-threshold (NOT an exemption). Reuses the
# freighter-capture harness end to end -- ship at full/near-full health after
# capture+settle+release BECAUSE observed peak contact speed stays under
# COLLISION_DAMAGE_MIN_SPEED, not because docking is exempt. Companion: a
# deliberate high-speed ram into the station host DOES deal damage.
# ---------------------------------------------------------------------------
var station = null
var bay = null
var freighter = null
# Comfortably inside MediumStation's derived capture_radius (~396u for its
# ~264u hull -- see PortZone.derive_capture_radius, a short-range docking
# arm, not the old flat 5000u default). The freighter never flies under its
# own power here -- capture-then-spring-pull IS the approach.
const PHASE4_START_OFFSET := Vector2(150, 260)
const PHASE4_APPROACH_TIMEOUT := 20.0
var dock_time: float = -1.0
var docking_subphase: int = 0 # 0 = approach/capture, 1 = hold-then-release
var max_docking_speed: float = 0.0    # peak speed anytime during the whole approach (informational)
var max_contact_speed: float = 0.0    # peak speed while the collision CIRCLES are actually within touching distance -- the number the gate cares about
var ever_touched: bool = false

func _start_phase_4() -> void:
	phase = "phase_4"
	t = 0.0
	docking_subphase = 0
	dock_time = -1.0
	max_docking_speed = 0.0
	max_contact_speed = 0.0
	ever_touched = false
	print("--- Phase 4a: routine docking stays sub-threshold ---")

	station = MediumStation.new()
	station.name = "Station4"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO

	freighter = Freighter.new()
	freighter.name = "Freighter4"
	freighter.owner_id = 650
	freighter.iff_tags = ["TEAM_PLAYER"]
	freighter.wants_dock = true
	# M32: MediumStation is a controlled zone ("Ironhold Control"), so the bay
	# gate now requires a valid grant. Hand the freighter an any-open grant so
	# it can dock (same shortcut test_freighter_docking uses). This is a routine
	# dock -- exercising the collision-damage docking-exemption path, not the
	# permission system, so a pre-issued grant keeps the phase focused.
	freighter.set("docking_grant", {"authority": "Ironhold Control", "zone_authority": "Ironhold Control", "slip_id": "", "time_left": 300.0})

	main_node.add_child(station)
	for c in station.get_children():
		if c is DockingBay:
			bay = c
			break
	_assert(bay != null, "phase 4: station should auto-grow a DockingBay")
	if bay == null:
		_free_if_valid(station)
		_free_if_valid(freighter)
		_start_phase_4b()
		return

	freighter.position = bay.global_position + PHASE4_START_OFFSET
	main_node.add_child(freighter)

func _phase_4_process(delta: float) -> void:
	t += delta
	max_docking_speed = max(max_docking_speed, freighter.linear_velocity.length())

	# "Contact speed" specifically -- the roadmap's gate cares about the speed
	# AT the moment the two collision circles are close enough to touch, not
	# the peak speed reached anytime during free-flight approach (which can
	# legitimately run well past the threshold far from the station -- M27's
	# own docking test measures ~420 u/s there). The M27 standoff (berth pose
	# pushed out to station_radius + ship_radius + CLEARANCE_MARGIN) means a
	# routine dock should never actually bring the circles into contact at all.
	var circle_dist: float = station.global_position.distance_to(freighter.position)
	var radius_sum: float = station.get_bounding_radius() + freighter.get_bounding_radius()
	if circle_dist <= radius_sum + 5.0:
		ever_touched = true
		max_contact_speed = max(max_contact_speed, freighter.linear_velocity.length())

	if docking_subphase == 0:
		if bay.state == DockingBay.State.DOCKED:
			dock_time = t
			docking_subphase = 1
		elif t > PHASE4_APPROACH_TIMEOUT:
			_assert(false, "phase 4: freighter never docked (approach timeout)")
			_finish_phase_4()
	else:
		if bay.state == DockingBay.State.EMPTY:
			_finish_phase_4()
		elif t > dock_time + bay.dock_duration + 3.0:
			_assert(false, "phase 4: bay never released (hold timeout)")
			_finish_phase_4()

func _finish_phase_4() -> void:
	print("[P4a] whole-flight max speed=%.1f  peak CONTACT speed=%.1f (threshold=%.1f, ever_touched=%s)  freighter health %.1f/%.1f  station health %.1f/%.1f" % [
		max_docking_speed, max_contact_speed, ShipRef.COLLISION_DAMAGE_MIN_SPEED, str(ever_touched), _total_health(freighter), _max_health(freighter), _total_health(station), _max_health(station)])
	# The gate cares about speed AT contact, not peak speed anytime during
	# free-flight approach (that number legitimately runs past the threshold
	# far from the station -- see M27's own docking test). If the M27 standoff
	# is working, the circles should never even touch during a routine dock;
	# if they do touch, that contact speed must still be sub-threshold.
	_assert(not ever_touched or max_contact_speed < ShipRef.COLLISION_DAMAGE_MIN_SPEED,
		"phase 4: routine docking peak CONTACT speed (%.1f) should stay under the collision-damage threshold (%.1f)" % [max_contact_speed, ShipRef.COLLISION_DAMAGE_MIN_SPEED])
	_assert(_total_health(freighter) >= _max_health(freighter) - 0.01,
		"phase 4: freighter should be at full health after routine capture+settle+release (%.1f/%.1f)" % [_total_health(freighter), _max_health(freighter)])
	_assert(_total_health(station) >= _max_health(station) - 0.01,
		"phase 4: station should be at full health after routine docking (%.1f/%.1f)" % [_total_health(station), _max_health(station)])
	_free_if_valid(freighter)
	_free_if_valid(station)
	_start_phase_4b()

# Companion: a deliberate high-speed ram into the station host DOES deal
# damage -- proves the host isn't specially protected, only the speed gate.
const PHASE4B_RAM_SPEED := 500.0
const PHASE4B_TIMEOUT := 10.0

func _start_phase_4b() -> void:
	phase = "phase_4b"
	t = 0.0
	print("--- Phase 4b: deliberate high-speed ram into station DOES damage ---")
	station = MediumStation.new()
	station.name = "Station4b"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	station.position = Vector2.ZERO
	main_node.add_child(station)

	f1 = Frigate.new()
	f1.name = "F1_StationRammer"
	f1.owner_id = 651
	f1.iff_tags = ["TEAM_HOSTILE"]
	f1.position = Vector2(-(station.get_bounding_radius() + f1_radius_placeholder()), 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE4B_RAM_SPEED, 0)

func f1_radius_placeholder() -> float:
	return 700.0 # generous standoff so the ship is definitely clear of the station at spawn

func _phase_4b_process(delta: float) -> void:
	t += delta
	var station_damaged: bool = _total_health(station) < _max_health(station) - 0.01
	if station_damaged or t > PHASE4B_TIMEOUT:
		print("[P4b] station health %.1f/%.1f  (t=%.2f)" % [_total_health(station), _max_health(station), t])
		_assert(station_damaged, "phase 4b: a high-speed ram into the station SHOULD deal damage (no host exemption)")
		_free_if_valid(station)
		_free_if_valid(f1)
		_start_phase_5()

# ---------------------------------------------------------------------------
# Phase 5: missile contact = mild kinetic. A missile physically colliding with
# a ship deals NON-zero contact damage via the shared path, but small (low
# reduced mass) -- assert positive AND well under a like-speed frigate ram.
# The warhead/ranged-laser system is separate and out of scope here.
# ---------------------------------------------------------------------------
const PHASE5_SPEED := 400.0
const PHASE5_TIMEOUT := 8.0
var missile = null
var target = null
var missile_dmg_frigate_target: float = 0.0

func _start_phase_5() -> void:
	phase = "phase_5"
	t = 0.0
	print("--- Phase 5: missile contact = mild kinetic damage ---")
	target = Frigate.new()
	target.name = "MissileTarget"
	target.owner_id = 660
	target.iff_tags = ["TEAM_A"]
	target.position = Vector2(1000, 0)
	main_node.add_child(target)

	missile = Missile.new()
	missile.setup(661, Vector2(0, 0), Vector2(PHASE5_SPEED, 0), 0.0)
	missile.iff_tags = ["TEAM_HOSTILE"]
	main_node.add_child(missile)
	missile.linear_velocity = Vector2(PHASE5_SPEED, 0) # re-assert post add_child (see phase 1-4 fix note)

func _phase_5_process(delta: float) -> void:
	t += delta
	var target_damaged: bool = _total_health(target) < _max_health(target) - 0.01
	if target_damaged or t > PHASE5_TIMEOUT:
		missile_dmg_frigate_target = _raw_damage_absorbed(target)
		print("[P5] target damage from missile contact = %.2f  (t=%.2f)" % [missile_dmg_frigate_target, t])
		_assert(target_damaged, "phase 5: missile contact should deal non-zero damage to the target frigate")
		# Mild: a light missile vs a frigate must deal far less than a like-speed frigate ram.
		_assert(p1_frigate_dmg > 0.0 and missile_dmg_frigate_target < 0.5 * p1_frigate_dmg, "phase 5: missile contact (%.1f) should be well under a like-speed frigate ram (%.1f)" % [missile_dmg_frigate_target, p1_frigate_dmg])
		_free_if_valid(target)
		_free_if_valid(missile)
		_start_phase_6()

# ---------------------------------------------------------------------------
# Phase 6: symmetry. Identical ships, mirrored approach -> damage totals equal
# within 10%. Reuses the same setup as phase 1 (nose-to-nose, symmetric).
# ---------------------------------------------------------------------------
const PHASE6_APPROACH := 600.0
const PHASE6_SPEED := 200.0
const PHASE6_TIMEOUT := 10.0

func _start_phase_6() -> void:
	phase = "phase_6"
	t = 0.0
	p6_contacted = false
	p6_contact_time = 0.0
	print("--- Phase 6: symmetry (identical ships, mirrored approach) ---")
	f1 = Frigate.new()
	f1.name = "F1_Sym"
	f1.owner_id = 671
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(-PHASE6_APPROACH, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE6_SPEED, 0)

	f2 = Frigate.new()
	f2.name = "F2_Sym"
	f2.owner_id = 672
	f2.iff_tags = ["TEAM_B"]
	f2.position = Vector2(PHASE6_APPROACH, 0)
	f2.rotation = PI
	main_node.add_child(f2)
	f2.linear_velocity = Vector2(-PHASE6_SPEED, 0)

var p6_contacted: bool = false
var p6_contact_time: float = 0.0

func _phase_6_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(f2.position) <= (f1.get_bounding_radius() + f2.get_bounding_radius() + 5.0)
	if contact and not p6_contacted:
		p6_contacted = true
		p6_contact_time = t

	if (p6_contacted and t > p6_contact_time + 1.0) or t > PHASE6_TIMEOUT:
		# Use the UNCLAMPED damage-absorbed total (see _raw_damage_absorbed):
		# _total_health()'s per-component floor at 0 means whichever component
		# happens to intercept the ray first can overkill and cap the "visible"
		# loss at its own max_health, making otherwise-identical impacts look
		# asymmetric even though the underlying damage formula (same v_impact,
		# same reduced_mass for two identical ships) produced the same number
		# on both sides.
		var d1: float = _raw_damage_absorbed(f1)
		var d2: float = _raw_damage_absorbed(f2)
		var ratio: float = (min(d1, d2) / max(d1, d2)) if max(d1, d2) > 0.0 else 0.0
		var f1_damaged: bool = d1 > 0.01
		var f2_damaged: bool = d2 > 0.01
		print("[P6] f1 raw_dmg=%.2f  f2 raw_dmg=%.2f  ratio=%.3f  (contacted=%s)" % [d1, d2, ratio, str(p6_contacted)])
		_assert(f1_damaged and f2_damaged, "phase 6: both ships should take damage")
		_assert(ratio >= 0.9, "phase 6: damage totals should be equal within 10%% (f1=%.2f f2=%.2f ratio=%.3f)" % [d1, d2, ratio])
		_free_if_valid(f1)
		_free_if_valid(f2)
		_start_phase_7()

# ---------------------------------------------------------------------------
# Phase 7: monotonicity. Three impact speeds (200/300/400 combined) -> strictly
# increasing damage; threshold+epsilon -> near-zero. Run as three sequential
# sub-runs (200, 300, 400) plus a threshold+epsilon sub-run (151), each a
# fresh pair of frigates.
# ---------------------------------------------------------------------------
const PHASE7_SPEEDS := [151.0, 200.0, 300.0, 400.0, 1200.0] # combined closing speed; first is threshold+epsilon, last is far past the damage cap
const PHASE7_APPROACH := 600.0
const PHASE7_TIMEOUT := 12.0
const PHASE7_SETTLE_AFTER_CONTACT := 1.0 # seconds to wait after first contact before sampling damage -- body_entered fires on the physics tick AFTER two shapes are found overlapping, not the instant "contact" (a proximity check with slack) goes true
var p7_index: int = 0
var p7_damages: Array = []
var p7_contacted: bool = false
var p7_contact_time: float = 0.0

func _start_phase_7() -> void:
	phase = "phase_7"
	t = 0.0
	p7_index = 0
	p7_damages = []
	print("--- Phase 7: monotonicity across impact speeds ", PHASE7_SPEEDS, " ---")
	_start_phase_7_run()

func _start_phase_7_run() -> void:
	t = 0.0
	p7_contacted = false
	p7_contact_time = 0.0
	var combined_speed: float = PHASE7_SPEEDS[p7_index]
	var each_speed: float = combined_speed / 2.0
	print("[P7] sub-run %d: combined closing speed = %.1f" % [p7_index, combined_speed])
	f1 = Frigate.new()
	f1.name = "F1_Mono%d" % p7_index
	f1.owner_id = 700 + p7_index * 2
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(-PHASE7_APPROACH, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(each_speed, 0)

	f2 = Frigate.new()
	f2.name = "F2_Mono%d" % p7_index
	f2.owner_id = 700 + p7_index * 2 + 1
	f2.iff_tags = ["TEAM_B"]
	f2.position = Vector2(PHASE7_APPROACH, 0)
	f2.rotation = PI
	main_node.add_child(f2)
	f2.linear_velocity = Vector2(-each_speed, 0)

func _phase_7_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(f2.position) <= (f1.get_bounding_radius() + f2.get_bounding_radius() + 5.0)
	if contact and not p7_contacted:
		p7_contacted = true
		p7_contact_time = t

	if (p7_contacted and t > p7_contact_time + PHASE7_SETTLE_AFTER_CONTACT) or t > PHASE7_TIMEOUT:
		# Unclamped total (see _raw_damage_absorbed) -- same reasoning as phase 6:
		# a low-max_health component overkilled by a big hit would otherwise cap
		# the "visible" damage at its own max, breaking monotonicity once damage
		# is big enough to always one-shot whatever component the ray lands on.
		var dmg: float = _raw_damage_absorbed(f1)
		p7_damages.append(dmg)
		print("[P7] sub-run %d damage = %.3f (contacted=%s)" % [p7_index, dmg, str(p7_contacted)])
		_free_if_valid(f1)
		_free_if_valid(f2)
		p7_index += 1
		if p7_index < PHASE7_SPEEDS.size():
			_start_phase_7_run()
		else:
			_finish_phase_7()

func _finish_phase_7() -> void:
	print("[P7] all damages: ", p7_damages)
	_assert(p7_damages[0] < 5.0, "phase 7: threshold+epsilon (151 u/s) should be near-zero damage (got %.3f)" % p7_damages[0])
	_assert(p7_damages[1] < p7_damages[2], "phase 7: damage should strictly increase 200->300 (%.3f !< %.3f)" % [p7_damages[1], p7_damages[2]])
	_assert(p7_damages[2] < p7_damages[3], "phase 7: damage should strictly increase 300->400 (%.3f !< %.3f)" % [p7_damages[2], p7_damages[3]])
	# The 1200 u/s sub-run would deal ~24800 uncapped; COLLISION_DAMAGE_MAX
	# clamps it. Raw absorbed should sit at ~the cap (the whole capped lump
	# lands in the ~2 components the ray crosses), far below the uncapped value.
	_assert(p7_damages[4] < p7_damages[3] * 3.0, "phase 7: the 1200 u/s hit should be clamped, not the ~24800 uncapped value (got %.1f)" % p7_damages[4])
	_assert(abs(p7_damages[4] - ShipRef.COLLISION_DAMAGE_MAX) <= ShipRef.COLLISION_DAMAGE_MAX * 0.15, "phase 7: capped hit raw-absorbed (%.1f) should sit near COLLISION_DAMAGE_MAX (%.1f)" % [p7_damages[4], ShipRef.COLLISION_DAMAGE_MAX])
	_start_phase_8()

# ---------------------------------------------------------------------------
# Phase 8: negative control. With the DebugSettings knob OFF, the head-on case
# (same as phase 1) deals zero damage -- proves the gate is the gate.
# ---------------------------------------------------------------------------
const PHASE8_APPROACH := 600.0
const PHASE8_SPEED := 200.0
const PHASE8_TIMEOUT := 10.0
var p8_contacted: bool = false
var p8_contact_time: float = 0.0

func _start_phase_8() -> void:
	phase = "phase_8"
	t = 0.0
	p8_contacted = false
	print("--- Phase 8: negative control (collision_damage OFF) ---")
	DebugSettings.set_choice("collision_damage", DebugSettingsScript.CollisionDamage.OFF)

	f1 = Frigate.new()
	f1.name = "F1_NegControl"
	f1.owner_id = 800
	f1.iff_tags = ["TEAM_A"]
	f1.position = Vector2(-PHASE8_APPROACH, 0)
	main_node.add_child(f1)
	f1.linear_velocity = Vector2(PHASE8_SPEED, 0)

	f2 = Frigate.new()
	f2.name = "F2_NegControl"
	f2.owner_id = 801
	f2.iff_tags = ["TEAM_B"]
	f2.position = Vector2(PHASE8_APPROACH, 0)
	f2.rotation = PI
	main_node.add_child(f2)
	f2.linear_velocity = Vector2(-PHASE8_SPEED, 0)

func _phase_8_process(delta: float) -> void:
	t += delta
	var contact: bool = f1.position.distance_to(f2.position) <= (f1.get_bounding_radius() + f2.get_bounding_radius() + 5.0)
	if contact and not p8_contacted:
		p8_contacted = true
		p8_contact_time = t

	if (p8_contacted and t > p8_contact_time + 2.0) or t > PHASE8_TIMEOUT:
		print("[P8] contacted=%s f1 health %.1f/%.1f  f2 health %.1f/%.1f" % [
			str(p8_contacted), _total_health(f1), _max_health(f1), _total_health(f2), _max_health(f2)])
		_assert(p8_contacted, "phase 8: ships should still make contact (physics collision unaffected by the knob)")
		_assert(_total_health(f1) >= _max_health(f1) - 0.01, "phase 8: f1 should take zero damage with collision_damage OFF")
		_assert(_total_health(f2) >= _max_health(f2) - 0.01, "phase 8: f2 should take zero damage with collision_damage OFF")
		DebugSettings.set_choice("collision_damage", DebugSettingsScript.CollisionDamage.ON) # restore default
		_free_if_valid(f1)
		_free_if_valid(f2)
		_finish()

# ShipRef gives test code access to Ship's constants (COLLISION_DAMAGE_MIN_SPEED)
# without needing a live instance.
const ShipRef = preload("res://scripts/ships/ship.gd")

func _physics_process(delta: float) -> void:
	if finished:
		return
	match phase:
		"phase_1": _phase_1_process(delta)
		"phase_2": _phase_2_process(delta)
		"phase_3": _phase_3_process(delta)
		"phase_4": _phase_4_process(delta)
		"phase_4b": _phase_4b_process(delta)
		"phase_5": _phase_5_process(delta)
		"phase_6": _phase_6_process(delta)
		"phase_7": _phase_7_process(delta)
		"phase_8": _phase_8_process(delta)

func _finish() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_collision_damage <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_collision_damage <<<")
		get_tree().quit(1)
