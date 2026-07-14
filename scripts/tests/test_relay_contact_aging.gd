extends Node

# Regression -- the datalink relay's mutual-echo lock ("missiles and things
# never disappear, they just get stuck at what looks like sensor range").
#
# Two comms-linked friendlies each hold a copy of the same contact. Each
# tick a ship ages its own copy (+delta), then the relay's freshest-wins
# merge reads the TEAMMATE's copy -- which hasn't been aged yet this tick
# (or was itself just reset by reading OUR last-tick copy). The relayed
# timestamp always reads one tick "fresher", so both sides keep taking each
# other's frozen (age, pos) forever: last_seen_timer never reaches
# CONTACT_TIMEOUT (the ghost never expires) and the merge keeps overwriting
# the dead-reckoned position with the frozen echoed one (the blip visibly
# sticks where the target was last really seen). Leaving comms range broke
# the echo, which is why everything "started moving again" -- the exact
# playtest report.
#
# The fix (ship.gd, datalink relay): a relayed track is ONE HOP OLD -- its
# age is external + delta on receipt, compared strictly. A round-trip echo
# then costs 2 ticks while the local copy aged only 1, so the echo can
# never win; genuinely fresher data (a real detection, age 0 at the sensing
# ship) still propagates at the documented one-tick-per-hop latency.
#
# Scenario: A and D (both full-sensor frigates, comms-linked the whole
# time) both directly track hostile X. X then teleports far outside every
# sensor's range (wake-safe: body_set_state + sleeping=false -- see
# CLAUDE.md's sleeping-RigidBody2D gotcha). From that moment neither ship
# ever really detects X again; both copies must AGE honestly (not sit
# pinned at ~0 in the echo lock) and expire at CONTACT_TIMEOUT even though
# the ships stay comms-linked throughout.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_relay_contact_aging

const Ship = preload("res://scripts/ships/frigate.gd")

var main_node: Node = null
var failures: Array = []

var a = null
var d = null
var x = null
var t: float = 0.0
var teleported: bool = false
var checked_aging: bool = false
var finished: bool = false

const TELEPORT_AT := 1.0
const AGING_CHECK_AT := 9.0     # 8s after teleport -- pre-fix both copies sat pinned < 1s here
const EXPIRY_CHECK_AT := 25.0   # CONTACT_TIMEOUT (20s) + margin

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Relay Contact Aging (echo-lock regression) Tests")

	a = Ship.new(); a.name = "A"; a.owner_id = 1; a.iff_tags = ["TEAM_A"]; a.position = Vector2(0, 0)
	main_node.add_child(a)
	# Off the A-X axis so X never blocks the A-D relay link's LOS ray.
	d = Ship.new(); d.name = "D"; d.owner_id = 2; d.iff_tags = ["TEAM_A"]; d.position = Vector2(0, 6000)
	main_node.add_child(d)
	x = Ship.new(); x.name = "X"; x.owner_id = 3; x.iff_tags = ["TEAM_B"]; x.position = Vector2(2000, 0)
	main_node.add_child(x)

func _contact_for(ship: Node, target: Node) -> Dictionary:
	var target_id = "TRK-%03d" % (abs(target.get_instance_id()) % 1000)
	return ship.active_contacts.get(target_id, {})

func _physics_process(_delta: float) -> void:
	if finished:
		return
	t += _delta

	if t > TELEPORT_AT and not teleported:
		teleported = true
		# Both observers must actually have the track before it goes stale,
		# or the aging assertions below would pass vacuously.
		_assert(not _contact_for(a, x).is_empty(), "setup: A directly tracks X before it leaves")
		_assert(not _contact_for(d, x).is_empty(), "setup: D tracks X before it leaves")
		var xform: Transform2D = x.global_transform
		xform.origin = Vector2(500000, 500000)
		PhysicsServer2D.body_set_state(x.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
		x.position = Vector2(500000, 500000)
		x.sleeping = false   # a sleeping body's collision shape stays at the OLD spot (CLAUDE.md)

	if t > AGING_CHECK_AT and not checked_aging:
		checked_aging = true
		var ac: Dictionary = _contact_for(a, x)
		var dc: Dictionary = _contact_for(d, x)
		var a_age: float = ac.get("last_seen_timer", -1.0)
		var d_age: float = dc.get("last_seen_timer", -1.0)
		# ~8s since the last possible real detection. Pre-fix the echo lock
		# pinned both near 0 forever; post-fix both age honestly. Generous
		# floor (5s) so sweep cadence / hop latency can never flake it.
		_assert(a_age > 5.0, "A's stale track ages while comms-linked (age=%.2f, echo lock would pin it near 0)" % a_age)
		_assert(d_age > 5.0, "D's stale track ages while comms-linked (age=%.2f)" % d_age)

	if t > EXPIRY_CHECK_AT:
		var ac2: Dictionary = _contact_for(a, x)
		var dc2: Dictionary = _contact_for(d, x)
		_assert(ac2.is_empty(), "A's stale track expires at CONTACT_TIMEOUT despite the standing comms link (got %s)" % str(ac2.get("last_seen_timer", "gone")))
		_assert(dc2.is_empty(), "D's stale track expires at CONTACT_TIMEOUT despite the standing comms link")

		# The link itself must still be healthy -- the fix must starve the
		# ECHO, not the relay: A and D are friendlies in range, so each still
		# carries the other's live self-report at hop-latency freshness.
		var a_sees_d: Dictionary = _contact_for(a, d)
		_assert(not a_sees_d.is_empty(), "the relay link itself is still alive (A carries D's self-report)")
		if not a_sees_d.is_empty():
			_assert(a_sees_d.get("last_seen_timer", 99.0) < 1.0,
				"live self-reports stay fresh (age=%.3f -- hop latency, not echo-frozen staleness)" % a_sees_d.get("last_seen_timer", 99.0))

		finished = true
		if failures.is_empty():
			print(">>> [TEST PASSED] test_relay_contact_aging <<<")
			get_tree().quit(0)
		else:
			for f in failures:
				printerr("  FAIL: ", f)
			printerr(">>> [TEST FAILED] test_relay_contact_aging <<<")
			get_tree().quit(1)
