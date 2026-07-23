extends Node

# M52 playtest fix -- thermal governor regression (job_steps.gd's
# _thermal_derate, calling session 2026-07-22). Root cause: two pirates
# converging on the SAME victim never exclude EACH OTHER from Steering.
# steer's avoidance (only the victim is excluded), so their pacing math and
# their mutual anti-overlap push fight indefinitely -- neither ever settles,
# both hold near-max commanded throttle forever. _engine_heat_contribution
# scales with abs(throttle), so sustained near-max throttle generates real
# heat; once current_heat pegs at max_heat, ship.gd's OWN periodic check
# (separate from take_damage() entirely -- no [Damage] print, no collision,
# no last_damage_attacker_name) drains the reactor's health directly. A
# pirate could die mid-encounter with ZERO visible cause in any log.
#
# Confirmed empirically before the fix: 2 pirates vs. 1 complying victim,
# heat climbed 0 -> 140/140 in ~35s at throttle 0.7-1.0, one pirate's
# reactor cooked to 0 HP by ~48s, the other survived (asymmetric outcome --
# whichever pirate loses the avoidance fight worse cooks faster). This test
# pins the fix: heat may still climb high under the same fight, but must
# never sustain long enough to actually kill either pirate.
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames (CLAUDE.md -- physics isn't bit-deterministic).

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Hail = preload("res://scripts/comms/hail.gd")

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

func setup(main) -> void:
	main_node = main
	print("=== test_multi_pirate_thermal: two pirates, one shared victim, neither cooks its own reactor ===")

	var victim = _make_ship(Frigate, "Victim", 900, Vector2.ZERO, ["TEAM_VICTIM"])
	# No AI -- compliance driven directly the instant a demand arrives, the
	# same engage_dead_stop() pattern M52c/M52-base tests already use.

	var pirates: Array = []
	for i in range(2):
		var p = _make_ship(ArmedPinnace, "Pirate%d" % i, 910 + i, Vector2(6000, 0).rotated(TAU * float(i) / 2.0), ["PIRATE_%d" % (910 + i)])
		p.add_child(AITreeFactory.build_pirate())
		# Hand-built job, same shape test_robbery_mechanics.gd/test_patrol_
		# interdiction.gd use -- BOTH pirates target the SAME victim_iid, the
		# exact convergence the playtest hit under pirate_overdrive.
		p.assignment = {
			"steps": [
				{"verb": "INTERCEPT"},
				{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0},
				{"verb": "TAKE_ALONGSIDE", "hold_time": 12.0, "range": 200.0},
			],
			"current": 0,
			"victim_iid": victim.get_instance_id(),
		}
		pirates.append(p)

	var complied := false
	var max_heat_ratio_seen := 0.0
	for i in range(9000): # up to 150s -- long enough to have killed a pirate pre-fix (~48s)
		await main_node.get_tree().physics_frame
		if not complied and victim.pending_demand.get("rung", "") == Hail.RUNG_STOP:
			victim.engage_dead_stop()
			complied = true
		for p in pirates:
			if is_instance_valid(p) and p.max_heat > 0.0:
				max_heat_ratio_seen = max(max_heat_ratio_seen, p.current_heat / p.max_heat)
		if not (is_instance_valid(pirates[0]) and is_instance_valid(pirates[1])):
			break

	_assert(complied, "the shared victim received and acted on a DEMAND(STOP)")
	_assert(is_instance_valid(pirates[0]) and not pirates[0].is_dead, "Pirate0 survived the whole encounter (was NOT is_dead)")
	_assert(is_instance_valid(pirates[1]) and not pirates[1].is_dead, "Pirate1 survived the whole encounter (was NOT is_dead)")
	print("[test] peak heat ratio observed across both pirates: %.2f (pre-fix, this scenario reliably reached 1.0 and killed one pirate by t=~48s)" % max_heat_ratio_seen)

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_multi_pirate_thermal <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_multi_pirate_thermal <<<")
		get_tree().quit(1)
