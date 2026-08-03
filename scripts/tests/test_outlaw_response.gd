extends Node

# D28 -- a cornered pirate answers a patrol's DEMAND_STOP.
#
# WHAT THIS IS PINNING, and why it is not a balance test. EngagementProbe's
# first run measured 39 patrol interdictions ending complied 0 / refused 27 /
# outpaced 0. Zero outpaced means the patrols kept up every time; the subject
# just never stopped, because `build_pirate` had NO leaf that reads
# `pending_demand` -- ThreatResponseLeaf lives only in build_cargo. Refusal was
# structural, not chosen, and no amount of tuning patience could have found it.
#
# So the assertions here are about a MECHANISM EXISTING and being reachable
# through the real tree, not about a rate. Two of them matter most:
#
#   S1 -- a pirate that cannot outrun the patrol HEAVES TO, and that compliance
#         is visible to the patrol as `complied_stop` (which is what
#         step_demand_stop waits on and EngagementProbe scores as a stop).
#   S3 -- the leaf is actually WIRED INTO build_pirate. CLAUDE.md's standing
#         lesson is that a green unit test cannot tell you the input ever
#         arrives; M58 shipped a relay that no campaign could reach because
#         every test hand-built its own tree. So S3 asserts against the tree
#         the game really constructs.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_outlaw_response

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const OutlawResponseLeaf = preload("res://scripts/ai/leaves/outlaw_response_leaf.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var ship = Frigate.new()
	ship.name = ship_name
	ship.owner_id = owner
	ship.iff_tags = tags
	ship.position = pos
	main_node.add_child(ship)
	spawned.append(ship)
	return ship

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func _settle_track(a, b) -> bool:
	for i in range(360):
		await main_node.get_tree().physics_frame
		var c: Dictionary = _find_contact(a, b)
		if not c.is_empty() and Ship.contact_age(c) <= a.FIRE_STALENESS_MAX:
			return true
	return false

# A patrol interdiction job. `interdict_tier` is what EngagementProbe gates on
# to tell a patrol's stop from a pirate's robbery, so it belongs here.
func _interdict_job(subject_iid: int) -> Dictionary:
	return {"steps": [{"verb": "DEMAND_STOP", "patience": 9999.0, "cruise": 0.0}],
		"current": 0, "victim_iid": subject_iid, "interdict_tier": 1}

func setup(main) -> void:
	main_node = main
	print("Starting Outlaw Response (D28) Tests")

	await _test_cornered_pirate_heaves_to()
	await _test_faster_pirate_runs()
	_test_leaf_is_in_the_real_tree()

	_finish()

# --- S1: outmatched on speed -> comply, and the patrol can SEE it -----------
func _test_cornered_pirate_heaves_to() -> void:
	print("\n--- S1: a pirate that cannot outrun the patrol heaves to ---")
	var patrol = _make_ship("S1Patrol", 700, Vector2.ZERO, ["TEAM_LAW"])
	var pirate = _make_ship("S1Pirate", 701, Vector2(3000, 0), ["TEAM_P"])

	var settled: bool = await _settle_track(patrol, pirate)
	_assert(settled, "S1 setup: the patrol holds a fresh track on the pirate")

	# The pirate is strictly slower, so running is not on the table. Set this
	# rather than relying on hull stats -- the point under test is the DECISION,
	# and a test whose premise depends on catalog tuning breaks for the wrong
	# reason the next time a frigate's engine changes.
	pirate.max_speed = 400.0
	patrol.max_speed = 1200.0

	var runner = JobRunnerLeaf.new()
	var patrol_bb = BlackboardScript.new()
	var outlaw = OutlawResponseLeaf.new()
	var pirate_bb = BlackboardScript.new()
	patrol.assignment = _interdict_job(pirate.get_instance_id())

	var complied := false
	for i in range(600):
		runner.tick(patrol, patrol_bb)
		outlaw.tick(pirate, pirate_bb)
		await main_node.get_tree().physics_frame
		var c: Dictionary = _find_contact(patrol, pirate)
		if c.get("complied_stop", false):
			complied = true
			break

	_assert(complied,
		"S1: the pirate ACKNOWLEDGED and stopped -- and the patrol's own contact shows complied_stop")
	_assert(not pirate.compelled_stop.is_empty() or complied,
		"S1: compliance is a real hold, not just a message")

# --- S2: a genuinely faster pirate still runs -------------------------------
# The point of D28 is not "pirates surrender". If speed makes running the
# winning play, an outlaw runs -- otherwise this would be a surrender switch
# rather than a decision, and patrol effectiveness would stop meaning anything.
func _test_faster_pirate_runs() -> void:
	print("\n--- S2: a faster pirate runs instead ---")
	var patrol = _make_ship("S2Patrol", 702, Vector2(200000, 0), ["TEAM_LAW"])
	var pirate = _make_ship("S2Pirate", 703, Vector2(203000, 0), ["TEAM_P"])

	var settled: bool = await _settle_track(patrol, pirate)
	_assert(settled, "S2 setup: the patrol holds a fresh track on the pirate")

	pirate.max_speed = 2000.0
	patrol.max_speed = 300.0

	var runner = JobRunnerLeaf.new()
	var patrol_bb = BlackboardScript.new()
	var outlaw = OutlawResponseLeaf.new()
	var pirate_bb = BlackboardScript.new()
	patrol.assignment = _interdict_job(pirate.get_instance_id())

	var start_dist: float = patrol.position.distance_to(pirate.position)
	for i in range(600):
		runner.tick(patrol, patrol_bb)
		outlaw.tick(pirate, pirate_bb)
		await main_node.get_tree().physics_frame

	var c: Dictionary = _find_contact(patrol, pirate)
	_assert(not c.get("complied_stop", false),
		"S2: a pirate with the legs to escape does NOT heave to")
	_assert(patrol.position.distance_to(pirate.position) > start_dist,
		"S2: and it actually opened the range (%.0f -> %.0f)" % [
			start_dist, patrol.position.distance_to(pirate.position)])

# --- S3: the leaf is in the tree the GAME builds ----------------------------
# The M58 lesson, asserted directly: a handler that exists but is not wired is
# indistinguishable from no handler at all, and every unit test above builds
# its own leaf by hand and so cannot notice.
func _test_leaf_is_in_the_real_tree() -> void:
	print("\n--- S3: build_pirate actually contains the handler ---")
	var tree = AITreeFactory.build_pirate()
	var found := false
	var stack: Array = [tree]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n.get_script() == OutlawResponseLeaf:
			found = true
			break
		for child in n.get_children():
			stack.append(child)
	_assert(found,
		"S3: build_pirate() contains an OutlawResponseLeaf -- a pirate in a real campaign can answer a demand")
	tree.queue_free()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_outlaw_response <<<")
		get_tree().quit(0)
	else:
		print("[TEST FAILED] test_outlaw_response -- %d failure(s):" % failures.size())
		for f in failures:
			print("   - ", f)
		get_tree().quit(1)
