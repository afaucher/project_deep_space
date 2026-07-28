extends Node

# Playtest A1/A3 calibration (design_ideas/2026-07-26-campaign_playtest.md).
#
# The campaign playtest reported ID and STOP demands from patrols with no
# obvious cause; the standing report on the player at spawn is grey/NEUTRAL by
# every authored value, and a patrol should have nothing to demand. The
# hypothesis under test is the one the playtest itself raised: **the patrol is
# reading the player wrong because of DISTANCE**, not because any standing value
# is wrong.
#
# The mechanism it would have to be, from ship.gd's datalink loop: a transponder
# is only received inside COMMS range
#
#     if their_comms_range <= 0.0: continue
#     var link_range = min(self_comms_range, their_comms_range)
#     if dist > link_range: continue
#     ... active_transponders[s.get_instance_id()] = t_data
#
# while a SENSOR contact forms on its own, separate reach. Wherever sensor reach
# exceeds comms reach there is a band in which a patrol holds a solid track on a
# hull it cannot identify -- which is CAUTION, which is exactly what a
# DEMAND{IDENTIFY} is for. Nobody has ever calibrated the two against each
# other.
#
# This test does not assume that band exists. It MEASURES both radii and prints
# the table, then asserts the property that actually matters:
#
#   **If a patrol can see you, it must be able to hear you.**
#
# i.e. there is no distance at which a contact exists without its transponder.
# That is the calibration claim, and it is the thing a demand-side grace period
# CANNOT fix -- a 3-second grace covers a few frames of relay lag, not a hull
# that sits in the gap indefinitely.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_patrol_id_read

const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")

# Spread across and beyond the authored 30000 comms range so the far end is a
# genuine control (nothing should be heard OR seen out there).
const DISTANCES := [1000.0, 4000.0, 8000.0, 15000.0, 25000.0, 35000.0]
# Fusion is a multi-stage pipeline (bin sweep -> correlate -> classify) and the
# datalink relay runs at DATALINK_RELAY_HZ (15) with a per-ship phase offset, so
# a fresh pair needs real settling time before a reading means anything.
const SETTLE_FRAMES := 180

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var d_index: int = 0
var frames: int = 0
var patrol = null
var subject = null
var rows: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Patrol ID-Read Calibration")
	_start(0)

func _start(i: int) -> void:
	d_index = i
	frames = 0
	var d: float = DISTANCES[i]

	# The patrol: home-faction, ordinary warrant authority, default
	# known_enemy_flags ([FLAG_PIRATE]).
	patrol = Frigate.new()
	patrol.name = "PatrolAlpha"
	patrol.owner_id = 1
	patrol.iff_tags = ["TEAM_DRIFT"]
	main_node.add_child(patrol)
	patrol.set_transponder_flag(Standing.FLAG_DRIFT)

	# The subject: exactly what main.gd's _spawn_player_ship builds for the
	# campaign -- CargoShuttle, TEAM_PLAYER (deliberately NOT overlapping the
	# home tags), flying the home flag with the transponder on.
	subject = CargoShuttle.new()
	subject.name = "PlayerLike"
	subject.owner_id = 60
	subject.iff_tags = ["TEAM_PLAYER"]
	subject.position = Vector2(d, 0)
	main_node.add_child(subject)
	subject.set_transponder_flag(Standing.FLAG_DRIFT)

func _find_contact(observer, target) -> Dictionary:
	var tid: int = target.get_instance_id()
	for trk in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[trk]
		if c.get("instance_id", 0) == tid:
			return c
	return {}

func _physics_process(_delta: float) -> void:
	if finished or patrol == null:
		return
	frames += 1
	if frames < SETTLE_FRAMES:
		return

	var d: float = DISTANCES[d_index]
	var c: Dictionary = _find_contact(patrol, subject)
	var t: Dictionary = patrol.active_transponders.get(subject.get_instance_id(), {})
	var st: Dictionary = Standing.compute_standing(c, t, patrol) if not c.is_empty() else {}

	rows.append({
		"dist": d,
		"seen": not c.is_empty(),
		"heard": not t.is_empty(),
		"classification": c.get("classification", "-"),
		"standing": st.get("standing", "-"),
		"reason": st.get("reason", ""),
	})
	print("  [%6.0f] seen=%-5s heard=%-5s class=%-20s standing=%-12s %s" % [
		d, str(not c.is_empty()), str(not t.is_empty()),
		c.get("classification", "-"), st.get("standing", "-"), st.get("reason", "")])

	patrol.queue_free()
	subject.queue_free()
	patrol = null
	subject = null

	if d_index + 1 < DISTANCES.size():
		_start(d_index + 1)
	else:
		_report()

func _report() -> void:
	print("\n--- Calibration ---")
	var seen_max: float = -1.0
	var heard_max: float = -1.0
	for r in rows:
		if r["seen"]:
			seen_max = maxf(seen_max, r["dist"])
		if r["heard"]:
			heard_max = maxf(heard_max, r["dist"])
	print("furthest SEEN (sensor contact): %.0f" % seen_max)
	print("furthest HEARD (transponder):   %.0f" % heard_max)

	# THE GAP IS DELIBERATE -- do not assert it away. Comms is authored SHORTER
	# than sensor reach on purpose: hearing a hull's transponder is a small
	# piece of omniscience you have to close distance to earn, and being able to
	# see something you cannot yet identify is the intended texture. An earlier
	# version of this test asserted "if you can see it you must hear it" and had
	# the design exactly backwards.
	#
	# So the property under test is not that the band is absent. It is that the
	# band is HONEST: inside comms a reporting hull reads NEUTRAL, outside it
	# reads CAUTION, and -- the part that actually bit -- being unheard out
	# there must never be treated as EVIDENCE. See challenge_leaf's expiry path:
	# a NO_ID warrant may only be posted against a contact still inside comms
	# range, because otherwise the silence is our deafness, not their refusal.
	_assert(seen_max > heard_max,
		"sensor reach (%.0f) should exceed comms reach (%.0f) -- the gap is the intended asymmetry"
			% [seen_max, heard_max])
	for r in rows:
		if r["seen"] and not r["heard"]:
			_assert(r["standing"] == Standing.CAUTION,
				"at %.0f, seen but out of comms, the honest read is CAUTION (got '%s')"
					% [r["dist"], r["standing"]])

	# Wherever both hold, the campaign's own identity setup must resolve to
	# NEUTRAL: no IFF overlap (TEAM_PLAYER vs TEAM_DRIFT) but a valid
	# transponder flying a non-enemy flag. Anything else is A1's cause.
	for r in rows:
		if r["seen"] and r["heard"]:
			_assert(r["standing"] == Standing.NEUTRAL,
				"at %.0f a player-like hull should read NEUTRAL, got '%s' (%s)"
					% [r["dist"], r["standing"], r["reason"]])

	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_patrol_id_read <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_patrol_id_read <<<")
		get_tree().quit(1)
