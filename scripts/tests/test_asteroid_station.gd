extends Node

# M27 acceptance -- asteroid station (THE MARQUEE, per
# implementation_plans/m27_catalog_expansion_design.md test plan item 7). This
# is the archetype's acceptance criterion: cold-and-dark, the station reads as
# ASTEROID to an observing frigate's classify_contact; powered up, the SAME
# tracked contact re-reads as a powered vessel, all within the normal
# sensor-sweep/classification/decay window -- no special-cased test-only
# behavior, just the fleet's existing signature model (ship.gd's
# classify_contact) doing exactly what design_ideas/ship_parameter_table.md's
# signature-axis section says it should.
#
# Sequence:
#   1. Spawn the station cold-and-dark (its authored default posture -- see
#      asteroid_station.gd's WAKE_COMPONENT_IDS) + an observing Frigate within
#      the frigate's omni_main active-sensor range (40000, refresh 2.0s).
#   2. Run frames until the frigate's sweep + classification settles; assert
#      its contact for the station reads exactly "ASTEROID" (the literal
#      string classify_contact returns for the
#      em<=threshold/density>250/cs>50 branch -- see ship.gd).
#   3. Power the station up: flip powered_on=true on WAKE_COMPONENT_IDS (the
#      documented wake convention).
#   4. Run frames through another sweep+classification window; assert the
#      SAME contact id now reads as a powered contact -- classify_contact's
#      em>ACTIVE_EM_THRESHOLD branch returns "UNIDENTIFIED VESSEL" for a
#      non-friendly observer (the frigate and station share no IFF tags
#      here), so that's the exact string asserted -- NOT "ASTEROID".
#   5. Assert the station's position never moved (STRUCTURE tier, no
#      engines, rcs only arrests drift -- it was never given anything to
#      drift from since nothing pushes it, but the check is asserted anyway
#      per the plan's explicit "the station never moved" acceptance item).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_asteroid_station
# Pass marker per CLAUDE.md.

const AsteroidStation = preload("res://scripts/ships/asteroid_station.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")

const STATION_POS := Vector2.ZERO
const STATION_DRIFT_TOLERANCE := 1.0 # STRUCTURE, no engines, nothing pushes it -- should be exactly 0 drift

# Well inside the frigate's omni_main range (40000, TAU arc, 2.0s refresh) and
# its passive_em range (80000) -- close enough that even the frigate's
# shorter/narrower dir_high_res (40000, PI/6 arc) can find it if aimed, but
# omni_main alone is sufficient since it's omnidirectional.
const FRIGATE_POS := Vector2(8000.0, 0.0)

# omni_main refreshes every 2.0s; give several sweeps + fusion/correlation
# settling time before asserting either read. 300 frames = 5s at 60fps = 2+
# full omni_main sweep cycles.
const SETTLE_FRAMES := 300

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var station = null
var frigate = null
var phase: int = 0 # 0 = cold-and-dark settling, 1 = powered settling
var frame_in_phase: int = 0
var max_station_drift: float = 0.0

# The contact id the frigate assigns the station -- captured once seen in
# phase 0 and re-checked under the SAME id in phase 1 (proves it's the same
# tracked contact re-classifying, not a new detection).
var station_contact_id: String = ""

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Asteroid Station (M27) Tests")

	station = AsteroidStation.new()
	station.name = "AsteroidStation"
	station.owner_id = 700
	station.iff_tags = ["TEAM_ROCK"]
	station.position = STATION_POS
	main_node.add_child(station)

	frigate = Frigate.new()
	frigate.name = "ObserverFrigate"
	frigate.owner_id = 701
	frigate.iff_tags = ["TEAM_OBSERVER"] # deliberately NOT sharing the station's tag
	frigate.position = FRIGATE_POS
	main_node.add_child(frigate)

func _physics_process(_delta: float) -> void:
	if finished:
		return

	if is_instance_valid(station):
		var drift: float = station.position.distance_to(STATION_POS)
		max_station_drift = max(max_station_drift, drift)

	frame_in_phase += 1

	if phase == 0 and frame_in_phase >= SETTLE_FRAMES:
		_check_cold_and_dark()
		_wake_station()
		phase = 1
		frame_in_phase = 0
	elif phase == 1 and frame_in_phase >= SETTLE_FRAMES:
		_check_powered()
		_finish()

# Find the frigate's tracked contact for the station by instance_id (not by
# guessing a TRK-### string), so this doesn't depend on the id-formatting
# convention in ship.gd's correlate-tracks loop.
func _find_station_contact() -> String:
	if not is_instance_valid(frigate) or not is_instance_valid(station):
		return ""
	var target_iid: int = station.get_instance_id()
	for c_id in frigate.active_contacts:
		var c: Dictionary = frigate.active_contacts[c_id]
		if c.get("instance_id", -1) == target_iid:
			return c_id
	return ""

func _check_cold_and_dark() -> void:
	var c_id: String = _find_station_contact()
	_assert(c_id != "", "Phase 0: frigate should have a tracked contact for the cold-and-dark station after " + str(SETTLE_FRAMES) + " frames")
	if c_id == "":
		return
	station_contact_id = c_id
	var classification: String = frigate.active_contacts[c_id].get("classification", "")
	print("[test_asteroid_station] cold-and-dark classification: ", classification)
	_assert(classification == "ASTEROID", "Phase 0: cold-and-dark station should classify as exactly 'ASTEROID', got '" + classification + "'")

	# Sanity: em_signature should be at (or hover near) zero with reactor +
	# sensors + PD all powered off -- confirms the "cold and dark" posture is
	# actually cold and dark, not just coincidentally under threshold.
	_assert(station.em_signature <= 5.0, "Phase 0: cold-and-dark station's em_signature should be <= ACTIVE_EM_THRESHOLD (5.0), got " + str(station.em_signature))

func _wake_station() -> void:
	print("[test_asteroid_station] waking station: flipping powered_on on ", AsteroidStation.WAKE_COMPONENT_IDS)
	for c in station.ship_components:
		if AsteroidStation.WAKE_COMPONENT_IDS.has(c.get("id", "")):
			c["powered_on"] = true

func _check_powered() -> void:
	_assert(station_contact_id != "", "Phase 1: need a contact id captured from phase 0 to re-check")
	if station_contact_id == "":
		return
	if not frigate.active_contacts.has(station_contact_id):
		_assert(false, "Phase 1: the same tracked contact id (" + station_contact_id + ") should still exist after waking the station")
		return
	var classification: String = frigate.active_contacts[station_contact_id].get("classification", "")
	print("[test_asteroid_station] powered classification: ", classification)
	_assert(classification != "ASTEROID", "Phase 1: powered station's contact should no longer classify as ASTEROID, got '" + classification + "'")
	_assert(classification == "UNIDENTIFIED VESSEL", "Phase 1: powered station (no shared IFF with observer) should classify as exactly 'UNIDENTIFIED VESSEL', got '" + classification + "'")
	_assert(station.em_signature > 5.0, "Phase 1: powered station's em_signature should exceed ACTIVE_EM_THRESHOLD (5.0), got " + str(station.em_signature))

func _finish() -> void:
	if finished:
		return
	finished = true

	_assert(is_instance_valid(station), "station should still be alive/valid at the end of the run")
	if is_instance_valid(station):
		_assert(max_station_drift <= STATION_DRIFT_TOLERANCE,
			"station should never move (max drift %.4fu > tolerance %.1fu)" % [max_station_drift, STATION_DRIFT_TOLERANCE])

	if failures.is_empty():
		print(">>> [TEST PASSED] test_asteroid_station <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_asteroid_station <<<")
		get_tree().quit(1)
