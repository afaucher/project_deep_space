extends Node

# M50 -- the abort-edge proof (implementation_plans/m50_pirate_tree_design.md
# "Tests"): same hunt-job setup as test_pirate_ambush.gd, but a third armed
# ship closes to within the pirate's third_party_in_range radius mid-hunt
# (during INTERCEPT, before DEMAND_STOP ever sends anything). Asserts the
# runner's abort_when mechanism does its job: the job jumps straight to the
# "exfil" label (skipping DEMAND_STOP/TAKE_ALONGSIDE entirely), the victim is
# never looted, and the pirate never fires a shot -- structurally guaranteed
# by build_pirate() having no Engage branch at all (a pirate attacks only via
# the job's DEMAND/TAKE, never acquire_target), confirmed here by watching
# its laser's cooldown stay at zero throughout.
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames (CLAUDE.md).

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const R_THIRD_PARTY := 6000.0

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(script, ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

# Same shape as test_pirate_ambush.gd's _build_hunt_job (the canonical hunt
# job) -- duplicated deliberately (self-contained test files, this codebase's
# convention) rather than shared, so each test's job is fully legible on its
# own.
func _build_hunt_job(staging_pos: Vector2, lane_pos: Vector2, exfil_pos: Vector2, exit_pos: Vector2, relight_name: String) -> Dictionary:
	return {
		"steps": [
			{"verb": "GO_TO", "pos": staging_pos},
			{"verb": "GO_DARK"},
			# See test_pirate_ambush.gd's header note: third_party_in_range is
			# deliberately NOT attached to SELECT_VICTIM (circular before a
			# victim exists -- job["victim_iid"] is -1, so the intended prey
			# itself would always misread as a third party). It applies
			# cleanly from INTERCEPT onward, where job["victim_iid"] is set.
			{"verb": "SELECT_VICTIM", "label": "hunt", "lane_pos": lane_pos, "lurk_radius": 2500.0, "witness_range": 3000.0},
			{"verb": "INTERCEPT", "on_abort": "hunt",
				"abort_when": [{"cond": "victim_lost", "on_abort": "hunt"}, {"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "TAKE_ALONGSIDE", "hold_time": 8.0, "range": 600.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "GO_DARK"}, # re-dark after DEMAND_STOP's show_colors -- see the ambush test's header
			{"verb": "GO_TO", "label": "exfil", "pos": exfil_pos},
			{"verb": "AWAIT", "condition": "track_quiet", "seconds": 3.0, "clear_range": 5000.0, "timeout": 60.0},
			{"verb": "RELIGHT", "name": relight_name, "flag": Standing.FLAG_CIVILIAN},
			{"verb": "EXIT_AT", "pos": exit_pos},
		],
		"current": 0,
	}

func setup(main) -> void:
	main_node = main
	print("Starting Pirate Abort (M50) Tests")

	var staging_pos := Vector2(5000, 0)
	var lane_pos := staging_pos
	var exfil_pos := Vector2(5000, -12000)
	var exit_pos := Vector2(5000, -15000)

	var pirate = _make_ship(ArmedPinnace, "AbortPirate", 800, Vector2.ZERO, ["PIRATE_800"])
	pirate.set_transponder_custom_name("Fair Trader II")
	pirate.set_transponder_flag(Standing.FLAG_CIVILIAN)
	pirate.set_transponder_active(true)
	pirate.add_child(AITreeFactory.build_pirate())

	var victim = _make_ship(CargoShuttle, "AbortVictim", 802, Vector2(5000, -3000), ["TEAM_ABORT_VICTIM"])
	victim.add_child(AITreeFactory.build_cargo())

	var job := _build_hunt_job(staging_pos, lane_pos, exfil_pos, exit_pos, "Nobody Here")
	pirate.assign_job(job)

	var idx_intercept := 3
	var idx_exfil := 7 # the "exfil"-labeled GO_TO step's index

	var laser_id := ""
	for w in pirate.get_components_by_type("weapons"):
		if w.get("weapon_type", "") == "laser":
			laser_id = w["id"]
			break
	_assert(laser_id != "", "setup sanity: armed_pinnace has a laser weapon")
	var cooldown_before: float = pirate.get_component(laser_id).get("cooldown", 0.0)

	# --- Phase 1: let the pirate get as far as SELECT_VICTIM -> INTERCEPT. ---
	print("\n--- Phase 1: hunt begins, victim selected, INTERCEPT starts ---")
	var reached_intercept := false
	for i in range(1800): # up to 30s
		await main_node.get_tree().physics_frame
		if job.get("current", -1) >= idx_intercept:
			reached_intercept = true
			break
	_assert(reached_intercept, "job reached INTERCEPT (current=%d)" % job.get("current", -1))
	_assert(job.get("victim_iid", -1) == victim.get_instance_id(), "SELECT_VICTIM picked the cargo shuttle")

	# --- Phase 2: a third armed ship closes to within third_party_in_range
	# of the pirate. Assert the runner aborts the hunt straight to "exfil". ---
	print("\n--- Phase 2: a third armed ship closes -- assert abort to 'exfil' ---")
	var interloper = _make_ship(Frigate, "Interloper", 801, pirate.position + Vector2(500, 500), ["TEAM_INTERLOPER"])

	var aborted_to_exfil := false
	for i in range(1800): # up to 30s -- sensor correlation + a couple abort-check ticks
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate):
			break
		if job.get("current", -1) == idx_exfil:
			aborted_to_exfil = true
			break
		# Never let it get far enough to actually take -- fail fast/loud
		# rather than silently timing out if the abort didn't fire.
		if pirate.loot_takes >= 1:
			break
	_assert(aborted_to_exfil, "the runner aborted the hunt to the 'exfil' label once the interloper closed (current=%d)" % job.get("current", -1))

	# --- Phase 3: the heist never happened. -------------------------------
	print("\n--- Phase 3: the victim was never looted, the pirate never fired ---")
	_assert(is_instance_valid(victim) and not victim.looted, "the victim was NOT looted")
	_assert(pirate.loot_takes == 0, "loot_takes stayed 0 -- no take occurred")
	var cooldown_after: float = pirate.get_component(laser_id).get("cooldown", 0.0) if is_instance_valid(pirate) else -1.0
	_assert(cooldown_after == cooldown_before, "the pirate's laser cooldown never moved -- no shots fired (before=%.2f after=%.2f)" % [cooldown_before, cooldown_after])

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_pirate_abort <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_pirate_abort <<<")
		get_tree().quit(1)
