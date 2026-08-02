extends Node

# PIRATE EFFECTIVENESS MATRIX -- scenario x victim speed.
#
# The standing mystery is takes=0 in every pirate sim, across every targeting
# strategy, for as long as anyone has measured. This harness exists to turn that
# single number into a matrix, so "pirates don't work" can be replaced with
# "pirates fail HERE, under THESE conditions".
#
# THREE SCENARIOS, the ones worth separating:
#   UNOPPOSED_SNEAK       dark_lurk tradecraft -- go dark, lurk the lane, ambush.
#   UNOPPOSED_FALSE_FLAG  arrive lit under a cover identity and close openly.
#   PATROL                sneak, but a patrol is on station near the lane.
#
# SWEPT AGAINST VICTIM SPEED, because that is the design relationship the
# fiction wants: a laden bulk hauler should be catchable and a fast courier
# should usually get away. The mechanism already exists -- ThreatResponseLeaf
# decides comply-or-run by comparing the victim's own max_speed against the
# threat's observed capability (RUN when mine > theirs x RUN_SPEED_RATIO) -- so
# this matrix is really asking whether that mechanism produces the intended
# curve or a flat line.
#
# MEASURES GROUND TRUTH, NOT THE LEDGER. Success is `pirate.loot_takes >= 1` and
# `victim.looted`, read off the hulls. Deliberately NOT the PirateGuild ledger:
# on 2026-07-31 the ledger was found to book a completed robbery as a LOSS
# (cash-out requires a 10s check-in to catch the pirate inside an 8000u ring it
# crosses in ~11s at exit speed), so a guild-based score would report zero even
# when the piracy itself worked. Fixing that is separate; measuring around it is
# how this harness stays honest about what the AI can actually do.
#
# THE JOB STOPS AT THE TAKE. Exfil, laundering and cash-out are a different
# question and add ~2 minutes of sim per trial. What is being rated here is
# whether a pirate can find, catch and rob a ship.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim pirate_scenarios

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const SCENARIOS := ["UNOPPOSED_SNEAK", "UNOPPOSED_FALSE_FLAG", "PATROL"]

# Victim max_speed as a fraction of the pirate's (ArmedPinnace = 2000).
# 0.30 laden bulk hauler, 0.50 standard shuttle, 0.80 fast trader,
# 1.10 courier that outruns the pirate outright.
const SPEED_RATIOS := [0.30, 0.50, 0.80, 1.10]
const PIRATE_SPEED := 2000.0

const TRIALS_PER_CELL := 3
const TRIAL_FRAME_BUDGET := 5400   # 90s of sim -- generous for lurk + intercept + 8s hold
const R_THIRD_PARTY := 3000.0

# Lane geometry: the victim transits A -> B, the pirate lurks at the midpoint.
const LANE_A := Vector2(-14000, 0)
const LANE_B := Vector2(14000, 0)
const LURK := Vector2(0, 0)
const PATROL_STATION := Vector2(0, 7000)

var main_node: Node = null
var spawned: Array = []
var results: Array = []

func setup(main) -> void:
	main_node = main
	seed(20260731)
	# The job log is the only narration of a hunt; without it a failed trial is
	# an unexplained zero. Patrol log likewise for the PATROL scenario.
	DebugSettings.set_choice("job_log", DebugSettings.JobLog.ON)
	DebugSettings.set_choice("patrol_log", DebugSettings.PatrolLog.ON)
	print("=== pirate_scenarios: effectiveness matrix (scenario x victim speed) ===")
	print("    pirate max_speed=%.0f; success = pirate.loot_takes >= 1 (ground truth, not the guild ledger)" % PIRATE_SPEED)
	await _run_matrix()
	_report()

func _make(script, n: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = n
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	Standing.reset()

func _settle(n: int) -> void:
	for i in range(n):
		await main_node.get_tree().physics_frame

# The canonical hunt, cut at the take. `sneak` prepends the dark_lurk
# tradecraft (AWAIT clear -> GO_DARK); false_flag_cruise skips both and arrives
# at SELECT_VICTIM still lit under its cover identity -- exactly the split
# pirate_guild.gd's _roll_posture makes.
func _hunt_job(sneak: bool) -> Dictionary:
	var steps: Array = []
	if sneak:
		steps.append({"verb": "AWAIT", "condition": "clear", "clear_range": 8000.0, "timeout": 20.0, "on_abort": "go_dark"})
		steps.append({"verb": "GO_DARK", "label": "go_dark"})
	steps.append_array([
		{"verb": "SELECT_VICTIM", "label": "hunt", "lane_pos": LURK, "lurk_radius": 2500.0,
			"witness_range": R_THIRD_PARTY, "max_attempts": 4, "max_hunt_seconds": 70.0, "on_abort": "give_up"},
		{"verb": "INTERCEPT", "on_abort": "hunt",
			"abort_when": [{"cond": "victim_lost", "on_abort": "hunt"}]},
		{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0, "on_abort": "hunt"},
		{"verb": "TAKE_ALONGSIDE", "hold_time": 8.0, "range": 600.0, "on_abort": "hunt"},
		{"verb": "AWAIT", "label": "give_up", "condition": "clear", "clear_range": 1.0, "timeout": 1.0, "on_abort": ""},
	])
	return {"steps": steps, "current": 0}

func _trial(scenario: String, ratio: float, trial_idx: int) -> Dictionary:
	_cleanup()
	await _settle(2)

	var pirate = _make(ArmedPinnace, "Pirate", 900, LURK + Vector2(0, -1200), ["TEAM_PIRATE"])
	pirate.max_speed = PIRATE_SPEED
	pirate.set_transponder_flag(Standing.FLAG_CIVILIAN)
	pirate.add_child(AITreeFactory.build_pirate())

	# The victim transits the lane under its own cargo AI, so DEMAND_STOP meets a
	# real comply-or-run decision rather than a parked target.
	var victim = _make(CargoShuttle, "Victim", 901, LANE_A, ["TEAM_VICTIM"])
	victim.max_speed = PIRATE_SPEED * ratio
	victim.set_transponder_flag(Standing.FLAG_CIVILIAN)
	victim.add_child(AITreeFactory.build_cargo())
	victim.assign_job({"steps": [{"verb": "GO_TO", "pos": LANE_B}], "current": 0})

	var patrol = null
	if scenario == "PATROL":
		patrol = _make(Frigate, "Patrol", 902, PATROL_STATION, ["TEAM_HOME"])
		patrol.set_transponder_flag(Standing.FLAG_DRIFT)
		patrol.authority_flags = [Standing.FLAG_DRIFT]
		patrol.warrant_authority = [Standing.FLAG_DRIFT]
		patrol.add_child(AITreeFactory.build_patrol())

	pirate.assign_job(_hunt_job(scenario != "UNOPPOSED_FALSE_FLAG"))

	var took := false
	var frames := 0
	while frames < TRIAL_FRAME_BUDGET:
		await main_node.get_tree().physics_frame
		frames += 1
		if not is_instance_valid(pirate) or pirate.is_dead:
			break
		if pirate.loot_takes >= 1:
			took = true
			break
		if not is_instance_valid(victim) or victim.is_dead:
			break

	var row := {
		"scenario": scenario, "ratio": ratio, "trial": trial_idx,
		"took": took, "frames": frames,
		"pirate_dead": not is_instance_valid(pirate) or pirate.is_dead,
		"victim_looted": is_instance_valid(victim) and victim.looted,
		"reached_demand": is_instance_valid(victim) and not victim.pending_demand.is_empty(),
	}
	results.append(row)
	print("  %-22s speed x%.2f  trial %d: %s (%.1fs%s)" % [
		scenario, ratio, trial_idx,
		"TOOK" if took else "no take", frames / 60.0,
		", pirate dead" if row["pirate_dead"] else ""])
	return row

func _run_matrix() -> void:
	for scenario in SCENARIOS:
		for ratio in SPEED_RATIOS:
			for t in range(TRIALS_PER_CELL):
				await _trial(scenario, ratio, t)

func _rate(scenario: String, ratio: float) -> float:
	var n := 0
	var hit := 0
	for r in results:
		if r["scenario"] == scenario and abs(float(r["ratio"]) - ratio) < 0.001:
			n += 1
			if r["took"]:
				hit += 1
	return (float(hit) / n) if n > 0 else 0.0

func _report() -> void:
	_cleanup()
	print("\n=== TAKE RATE (fraction of %d trials) ===" % TRIALS_PER_CELL)
	var hdr := "%-22s" % "scenario"
	for ratio in SPEED_RATIOS:
		hdr += "  x%.2f" % ratio
	print(hdr)
	for scenario in SCENARIOS:
		var line := "%-22s" % scenario
		for ratio in SPEED_RATIOS:
			line += "  %5.2f" % _rate(scenario, ratio)
		print(line)

	var total := 0
	var took := 0
	for r in results:
		total += 1
		if r["took"]:
			took += 1
	print("\n  overall: %d/%d trials landed a take" % [took, total])

	# The design relationship the fiction wants, stated as a check rather than
	# left to eyeballing: slow prey should be catchable, fast prey should mostly
	# escape. Reported for every scenario, since a patrol may legitimately
	# suppress both ends.
	print("\n=== speed relationship (want: slow catchable, fastest escapes) ===")
	for scenario in SCENARIOS:
		var slow: float = _rate(scenario, SPEED_RATIOS[0])
		var fast: float = _rate(scenario, SPEED_RATIOS[SPEED_RATIOS.size() - 1])
		var verdict: String
		if slow == 0.0 and fast == 0.0:
			verdict = "FLAT ZERO -- pirates never succeed, speed is not the variable"
		elif slow > fast:
			verdict = "as designed (slow %.2f > fast %.2f)" % [slow, fast]
		elif slow == fast:
			verdict = "FLAT -- speed makes no difference"
		else:
			verdict = "INVERTED -- fast prey is caught MORE often than slow"
		print("  %-22s %s" % [scenario, verdict])

	var path := "res://tactical_analysis/data/pirate_scenarios.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line("scenario,speed_ratio,trial,took,seconds,pirate_dead,victim_looted,reached_demand")
		for r in results:
			f.store_line("%s,%.2f,%d,%s,%.2f,%s,%s,%s" % [
				r["scenario"], r["ratio"], r["trial"], str(r["took"]), r["frames"] / 60.0,
				str(r["pirate_dead"]), str(r["victim_looted"]), str(r["reached_demand"])])
		f.flush()
		f.close()
		print("\n  wrote ", path)
	get_tree().quit(0)
