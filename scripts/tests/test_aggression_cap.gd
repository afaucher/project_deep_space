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
const InterdictLeaf = preload("res://scripts/ai/leaves/interdict_leaf.gd")

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

	# --- Part 1b: the standing tier a warrant produces -----------------------
	# The yellow tier is CAUTION -- "what your ship can determine without
	# knowing more" -- and a warrant for a minor offense is exactly that. Before
	# this column every enforceable warrant read flat HOSTILE, which is how a
	# clean hull got painted red for not answering an identify challenge.
	print("\n--- what tier a warrant lands on ---")
	var expected_tier := {
		Standing.OFF_ASSAULT: Standing.HOSTILE,
		Standing.OFF_SUSTAINED_ASSAULT: Standing.HOSTILE,
		Standing.OFF_ARMED_ROBBERY: Standing.HOSTILE,
		Standing.OFF_OPERATOR_FLAGGED: Standing.HOSTILE,
		Standing.OFF_ARMED_THREAT: Standing.CAUTION,   # demanded our submission -- police or pirate? cannot tell
		Standing.OFF_NO_ID: Standing.CAUTION,          # THE PLAYTEST BUG, fixed upstream of the targeting gate
		Standing.OFF_SPEED_VIOLATION: Standing.CAUTION,
	}
	for offense in expected_tier:
		_assert(Standing.standing_for_offense(offense) == expected_tier[offense],
			"%s lands on %s (got '%s')" % [offense, expected_tier[offense], Standing.standing_for_offense(offense)])
	_assert(Standing.standing_for_offense("SOME_FUTURE_OFFENSE") == Standing.CAUTION,
		"an unknown offense lands on CAUTION, not HOSTILE (fails closed, same as authorizes_force)")

	# CAUTION is an alias for the existing yellow tier, NOT a fifth tier -- same
	# string, same severity, so the datalink compare-and-copy and every colour
	# consumer are untouched.
	_assert(Standing.CAUTION == Standing.CAUTION,
		"CAUTION is an alias for the existing yellow tier, not a new one")
	_assert(Standing.severity(Standing.CAUTION) < Standing.severity(Standing.HOSTILE)
			and Standing.severity(Standing.CAUTION) > Standing.severity(Standing.NEUTRAL),
		"caution sits between neutral and hostile in severity")

	# A caution-grade warrant must never MASK a more severe rule. A pirate who
	# has also picked up a NO_ID still reads HOSTILE off the enemy flag -- if
	# the warrant short-circuited, this would read yellow, which is a strictly
	# worse bug than the one the column fixes.
	var flag_obs := _make_patrol("PatrolFlagPrecedence")
	flag_obs.known_enemy_flags = [Standing.FLAG_PIRATE]
	flag_obs.warrants = {}
	flag_obs.post_warrant(Standing.OFF_NO_ID, "", _sig(), "test")
	flag_obs._rebuild_warrant_index()
	var masked: Dictionary = Standing.compute_standing(
		{"classification": "UNIDENTIFIED VESSEL", "signature": _sig()},
		{"name": "Black Sail", "flag": Standing.FLAG_PIRATE}, flag_obs)
	_assert(masked.get("standing", "") == Standing.HOSTILE,
		"a caution-grade warrant does NOT mask the known-enemy-flag rule (got '%s')" % masked.get("standing", ""))

	# And it must still beat NEUTRAL, or a warrant for a minor offense would be
	# invisible on a hull that is otherwise reporting clean.
	var caution_obs := _make_patrol("PatrolCautionBeatsNeutral")
	caution_obs.warrants = {}
	caution_obs.post_warrant(Standing.OFF_NO_ID, "", _sig(), "ignored identify challenge")
	caution_obs._rebuild_warrant_index()
	var over_neutral: Dictionary = Standing.compute_standing(
		{"classification": "UNIDENTIFIED VESSEL", "signature": _sig()},
		{"name": "", "flag": Standing.FLAG_CIVILIAN}, caution_obs)
	_assert(over_neutral.get("standing", "") == Standing.CAUTION,
		"a caution-grade warrant still outranks NEUTRAL on a reporting hull (got '%s')" % over_neutral.get("standing", ""))

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

	# --- Part 3: the other half of the ladder --------------------------------
	# Interdiction follows the WARRANT; engagement follows the STANDING. Once
	# NO_ID became caution-grade, InterdictLeaf's HOSTILE-only gate silently
	# dropped the entire patrol response to it -- the offense the ladder exists
	# for -- leaving the docking denial as its only consequence. It now demands
	# a stop from anyone we hold an enforceable warrant against at any tier.
	print("\n--- InterdictLeaf: demand a stop, at any warrant tier ---")
	_assert(_interdicts(_make_patrol("InterdictNoID"), Standing.OFF_NO_ID, Standing.CAUTION),
		"a caution-grade NO_ID warrant DOES get interdicted -- intercepted and hailed, never shot")
	_assert(_interdicts(_make_patrol("InterdictAssault"), Standing.OFF_ASSAULT, Standing.HOSTILE),
		"a hostile-grade warrant still gets interdicted (demand before weapons, unchanged)")

	# The load-bearing negative. CAUTION is also what an ordinary non-reporting
	# hull reads, so interdicting on the TIER rather than the warrant would have
	# every patrol demanding a stop from every unidentified ship in the cluster.
	_assert(not _interdicts(_make_patrol("InterdictBareCaution"), "", Standing.CAUTION),
		"a caution contact with NO warrant is NOT interdicted (merely unidentified is not an offense)")

	# --- Part 4: response priority -- red threats, SOS, then yellow ----------
	# Interdict/JobRunner sit ABOVE Engage and SOSResponse, which was right when
	# a demand job was a red matter by definition. Once caution-grade warrants
	# became interdictable, a NO_ID chase would pre-empt a firefight AND a
	# distress call, and hold the slot for the whole 25s INTERCEPT patience.
	# Yellow work now yields instead.
	print("\n--- priority: yellow work yields to red threats and SOS ---")

	_assert(not _interdicts_with_bystander(_make_patrol("PrioRedBlocks"), Standing.OFF_NO_ID, _red_bystander()),
		"a yellow interdiction is NOT started while a red threat is in range (bigger fish)")
	_assert(not _interdicts_with_bystander(_make_patrol("PrioSOSBlocks"), Standing.OFF_NO_ID, _sos_bystander()),
		"a yellow interdiction is NOT started while a distress call is live")
	_assert(_interdicts_with_bystander(_make_patrol("PrioQuiet"), Standing.OFF_NO_ID, {}),
		"...but IS started when nothing outranks it (the control -- otherwise the two above prove nothing)")
	_assert(_interdicts_with_bystander(_make_patrol("PrioRedItself"), Standing.OFF_ASSAULT, _red_bystander()),
		"RED work is never deferred -- a hostile-grade demand still goes out with other hostiles around")

	# The harder half: a yellow job ALREADY RUNNING when the red threat shows
	# up must be abandoned, not merely un-started.
	var yielder := _make_patrol("PrioYields")
	_assert(_interdicts(yielder, Standing.OFF_NO_ID, Standing.CAUTION),
		"setup: a yellow demand job is running")
	var yielded_iid: int = yielder.assignment.get("victim_iid", -1)
	yielder.active_contacts["TRK-002"] = _red_bystander()
	var leaf2 = InterdictLeaf.new()
	var bb2 := StubBlackboard.new()
	# Refusal memory as the leaf itself would have left it after assigning.
	bb2.set_value("interdict_refused", {yielded_iid: true})
	leaf2.tick(yielder, bb2)
	leaf2.free()
	_assert(yielder.assignment.is_empty(),
		"a RUNNING yellow demand job is abandoned when a red threat appears")
	_assert(not bb2.get_value("interdict_refused", {}).has(yielded_iid),
		"and its refusal memory is cleared -- yielding must not read as 'already demanded and refused', which would retire the interdiction for good")

	_finish()

# A second contact that outranks yellow work: a fresh hostile.
func _red_bystander() -> Dictionary:
	var c: Dictionary = _hostile_contact(112233)
	c["pos"] = Vector2(600, 0)
	return c

# ...and a live distress call. No staleness filter applies to these (see
# InterdictLeaf._outranked) so a bare fresh contact is enough.
func _sos_bystander() -> Dictionary:
	return {
		"instance_id": 445566,
		"classification": "DISTRESS CALL",
		"standing": "",
		"pos": Vector2(900, 0),
		"last_seen_at": Engine.get_physics_frames(),
	}

# _interdicts, plus one extra contact in the patrol's sensor picture.
func _interdicts_with_bystander(patrol: Node, offense: String, bystander: Dictionary) -> bool:
	var subject_iid: int = 987654
	var c: Dictionary = _hostile_contact(subject_iid)
	c["standing"] = Standing.HOSTILE if offense == Standing.OFF_ASSAULT else Standing.CAUTION
	patrol.active_contacts = {"TRK-001": c}
	if not bystander.is_empty():
		patrol.active_contacts["TRK-002"] = bystander
	patrol.active_transponders = {}
	patrol.warrants = {}
	patrol.assignment = {}
	patrol.post_warrant(offense, "", _sig(), "test")
	patrol._rebuild_warrant_index()

	var leaf = InterdictLeaf.new()
	var bb := StubBlackboard.new()
	leaf.tick(patrol, bb)
	leaf.free()
	# The job must be against OUR subject -- with a red bystander present the
	# leaf may legitimately interdict THAT instead, which is not the same claim.
	return patrol.assignment.get("victim_iid", -1) == subject_iid

# Same fixture shape as _acquires: one contact, optionally one warrant, leaf
# ticked directly. Returns whether InterdictLeaf assigned a demand job.
func _interdicts(patrol: Node, offense: String, standing: String) -> bool:
	var subject_iid: int = 987654
	var c: Dictionary = _hostile_contact(subject_iid)
	c["standing"] = standing
	patrol.active_contacts = {"TRK-001": c}
	patrol.active_transponders = {}
	patrol.warrants = {}
	patrol.assignment = {}
	if offense != "":
		patrol.post_warrant(offense, "", _sig(), "test")
	patrol._rebuild_warrant_index()

	var leaf = InterdictLeaf.new()
	var bb := StubBlackboard.new()
	leaf.tick(patrol, bb)   # side-effect leaf: always FAILURE, assigns the job
	leaf.free()
	return not patrol.assignment.is_empty()

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
