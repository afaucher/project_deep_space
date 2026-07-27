extends Node

# The AGGRESSION CAP (campaign playtest 2026-07-26, item A3 --
# design_ideas/2026-07-26-campaign_playtest.md).
#
# The playtest's player was flying clean, answered nobody's challenge in time,
# and got shot by the home station for it. The mechanism was that HOSTILE was
# treated as a firing authorization by everything that read it: an ignored
# IDENTIFY challenge posts a NO_ID warrant, compute_standing reads any
# enforceable warrant as HOSTILE, and AcquireTargetLeaf engaged anything
# HOSTILE. Nothing anywhere asked "is THIS offense worth shooting over?"
#
# Standing.authorizes_force is that question, and this test pins both halves of
# the answer:
#
#   1. The table itself -- which offenses put weapons on the table. This is a
#      DESIGN claim, not an implementation detail, so it is asserted offense by
#      offense rather than by re-deriving it from response_class (the whole
#      point is that response_class does NOT determine it: ASSAULT is
#      INTERCEPT-class and authorizes force, NO_ID is INTERCEPT-class and does
#      not).
#
#   2. AcquireTargetLeaf actually consuming it -- with a real Ship as the actor
#      and the leaf ticked DIRECTLY, so a pass means the gate works rather than
#      meaning two hulls failed to drift into weapons range. Every case below
#      differs ONLY in which warrant the patrol holds; the contact, the
#      geometry and the standing are identical, so nothing but the cap can
#      explain a different verdict.
#
# The negative controls matter as much as the positives. A cap that also
# stopped a ship shooting back at someone shooting it, or stopped a patrol
# engaging a declared pirate, would be a worse bug than the one it fixes.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_aggression_cap

const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const AcquireTargetLeaf = preload("res://scripts/ai/leaves/acquire_target_leaf.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

# Beehave's blackboard is a Node with its own tree plumbing; this leaf only
# ever calls set_value on it, so a two-method stand-in keeps the test to the
# thing under test.
class StubBlackboard:
	var values: Dictionary = {}
	func set_value(key, value, _id = null) -> void:
		values[key] = value
	func get_value(key, default = null, _id = null):
		return values.get(key, default)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _sig() -> Dictionary:
	return {"iff_tags": ["TEAM_SUBJECT"], "cross_section": 42.0}

# A live HOSTILE contact sitting well inside weapons range, fresh enough to
# clear the fire-discipline staleness gate. Everything the leaf checks BESIDE
# the cap is deliberately made to pass, so the cap is the only variable.
func _hostile_contact(subject_iid: int) -> Dictionary:
	return {
		"instance_id": subject_iid,
		"classification": "UNIDENTIFIED VESSEL",
		"standing": Standing.HOSTILE,
		"signature": _sig(),
		"pos": Vector2(300, 0),
		"last_seen_at": Engine.get_physics_frames(),
	}

func _make_patrol(patrol_name: String) -> Node:
	var p = Frigate.new()
	p.name = patrol_name
	p.owner_id = 1
	p.iff_tags = ["TEAM_DRIFT"]
	p.position = Vector2.ZERO
	main_node.add_child(p)
	spawned.append(p)
	return p

# Give `patrol` one contact and (optionally) one warrant against it, rebuild
# the warrant index the way the fusion tick does, then tick the leaf once and
# report whether it acquired.
func _acquires(patrol: Node, offense: String) -> bool:
	var subject_iid: int = 987654
	patrol.active_contacts = {"TRK-001": _hostile_contact(subject_iid)}
	patrol.active_transponders = {}
	patrol.warrants = {}
	if offense != "":
		patrol.post_warrant(offense, "", _sig(), "test")
	patrol._rebuild_warrant_index()

	var leaf = AcquireTargetLeaf.new()
	var bb := StubBlackboard.new()
	var success: int = leaf.SUCCESS
	var result: int = leaf.tick(patrol, bb)
	leaf.free()
	return result == success

func setup(main) -> void:
	main_node = main
	print("Starting Aggression Cap (playtest A3) Tests")

	# --- Part 1: the table ---------------------------------------------------
	print("\n--- which offenses authorize force ---")
	var expected := {
		Standing.OFF_ASSAULT: true,             # they fired on us -- self-defense
		Standing.OFF_SUSTAINED_ASSAULT: true,   # repeat violence, MAX class
		Standing.OFF_ARMED_ROBBERY: true,       # took cargo under guns, MAX class
		Standing.OFF_OPERATOR_FLAGGED: true,    # the player MARKed them; that is the order
		Standing.OFF_ARMED_THREAT: false,       # threatened, has not fired -- interdict, don't shoot
		Standing.OFF_NO_ID: false,              # THE PLAYTEST BUG
		Standing.OFF_SPEED_VIOLATION: false,    # administrative
	}
	for offense in expected:
		var want: bool = expected[offense]
		_assert(Standing.authorizes_force(offense) == want,
			"%s %s authorize force" % [offense, "should" if want else "must NOT"])

	# The point of the flag existing at all: it cuts ACROSS response class, so
	# it could not have been derived from the one we already had.
	_assert(Standing.response_class(Standing.OFF_ASSAULT) == Standing.response_class(Standing.OFF_NO_ID),
		"ASSAULT and NO_ID share a response class (both INTERCEPT) ...")
	_assert(Standing.authorizes_force(Standing.OFF_ASSAULT) != Standing.authorizes_force(Standing.OFF_NO_ID),
		"... but differ on force -- which is why authorizes_force is its own column, not a response_class lookup")

	# Fail closed. An offense nobody has classified must not inherit permission
	# to shoot; see the _OFFENSE_TABLE note on why this default and not the
	# other one.
	_assert(not Standing.authorizes_force("SOME_FUTURE_OFFENSE"),
		"an unknown offense does not authorize force (the cap fails closed)")

	# --- Part 2: the targeting gate consumes it ------------------------------
	print("\n--- AcquireTargetLeaf against an identical HOSTILE contact ---")

	# The bug, guarded. Same contact, same standing, same range as the cases
	# below -- only the offense differs.
	_assert(not _acquires(_make_patrol("PatrolNoID"), Standing.OFF_NO_ID),
		"a NO_ID warrant does NOT make the contact a weapons target (the playtest bug)")
	_assert(not _acquires(_make_patrol("PatrolThreat"), Standing.OFF_ARMED_THREAT),
		"an ARMED_THREAT warrant does not either -- demand a stop, don't open fire")

	# Self-defense. If the cap broke this it would be a worse bug than A3: a
	# ship that cannot return fire at someone shooting it.
	_assert(_acquires(_make_patrol("PatrolAssault"), Standing.OFF_ASSAULT),
		"an ASSAULT warrant DOES -- being shot at authorizes shooting back")
	_assert(_acquires(_make_patrol("PatrolRobbery"), Standing.OFF_ARMED_ROBBERY),
		"an ARMED_ROBBERY warrant does -- MAX-class offenses are uncapped")
	_assert(_acquires(_make_patrol("PatrolFlagged"), Standing.OFF_OPERATOR_FLAGGED),
		"an OPERATOR_FLAGGED warrant does -- MARK HOSTILE is an explicit operator order")

	# HOSTILE with no warrant behind it at all: a declared enemy flag
	# (compute_standing rule 3, e.g. a Jolly Roger) or the one-tick eager cache
	# stamp before the index rebuild catches up. Neither is capped.
	_assert(_acquires(_make_patrol("PatrolFlagEnemy"), ""),
		"a HOSTILE contact with NO matching warrant stays engageable (declared enemy / eager stamp)")

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_aggression_cap <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_aggression_cap <<<")
		get_tree().quit(1)
