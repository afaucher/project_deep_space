extends Node

# M48 -- live-ship scenarios for Standing (implementation_plans/
# m48_standings_flags_design.md's "New tests" list). Modeled on test_comms_
# chat.gd's / test_classifiers_e2e.gd's multi-scenario, frame-driven style:
# each scenario spawns a small cast of real ships, polls active_contacts
# until the condition under test settles (or a per-scenario timeout fires),
# then tears down and moves to the next. Godot 2D physics/timing isn't
# bit-deterministic run-to-run (CLAUDE.md) so every assertion here is a
# settle-and-check against a generous timeout, never an exact-frame check.

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")

var main_node: Node = null
var spawned: Array[Node] = []
var ships: Dictionary = {} # role name (String) -> Ship

var scenario_idx: int = -1
const NUM_SCENARIOS = 6
const SCENARIO_TIMEOUT := 8.0 # seconds of sim time before a scenario is declared hung
var scenario_timer: float = 0.0

# Small per-scenario state machines share one phase/step counter -- only one
# scenario is ever active at a time, and both are reset on every phase
# transition and at scenario start.
var phase: int = 0
var step_frame: int = 0

func setup(main) -> void:
	main_node = main
	print("Test test_standing_e2e initialized.")
	_start_scenario(0)

func _spawn(role: String, tags: Array, pos: Vector2) -> Ship:
	var s = Ship.new()
	s.name = role
	s.owner_id = spawned.size() + 1
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	ships[role] = s
	return s

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	ships.clear()

func _find_contact(observer: Ship, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func _contact_id_for(observer: Ship, target: Node) -> String:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c_id
	return ""

func _has_fresh_track(observer: Ship, target: Node) -> bool:
	var c: Dictionary = _find_contact(observer, target)
	if c.is_empty():
		return false
	return c.get("last_seen_timer", 999.0) <= observer.FIRE_STALENESS_MAX

func _start_scenario(idx: int) -> void:
	scenario_idx = idx
	scenario_timer = 0.0
	phase = 0
	step_frame = 0
	_cleanup()
	Standing.reset() # static registries (wanted_names, aggression bus) -- no cross-scenario bleed

	match idx:
		0:
			print("\n--- Scenario A: a dark (non-reporting) stranger is tracked but NOT engaged ---")
			_spawn("observer", ["TEAM_A"], Vector2.ZERO)
			var stranger = _spawn("stranger", ["TEAM_B"], Vector2(2500, 0))
			stranger.set_transponder_active(false) # go dark
		1:
			print("\n--- Scenario B: a pirate-flagged ship IS engaged ---")
			_spawn("observer", ["TEAM_A2"], Vector2.ZERO)
			var pirate = _spawn("pirate", ["TEAM_P"], Vector2(2500, 0))
			pirate.set_transponder_flag(Standing.FLAG_PIRATE)
		2:
			print("\n--- Scenario C: attacker fires on victim -- first-hit flip + stray-fire dampening on a witness ---")
			_spawn("attacker", ["TEAM_X"], Vector2(0, 0))
			_spawn("victim", ["TEAM_Y"], Vector2(2500, 0))
			_spawn("witness", ["TEAM_Z"], Vector2(1250, 2000))
		3:
			print("\n--- Scenario D: assistance exemption -- witness does NOT flip on a ship engaging an already-HOSTILE target ---")
			_spawn("observer", ["TEAM_W"], Vector2.ZERO)
			_spawn("enforcer", ["TEAM_E"], Vector2(2500, 0))
			var pirate_q = _spawn("pirate", ["TEAM_Q"], Vector2(2500, 1500))
			pirate_q.set_transponder_flag(Standing.FLAG_PIRATE) # already HOSTILE to observer via known-enemy flag
		4:
			print("\n--- Scenario E: datalink share propagates HOSTILE to a linked friendly ---")
			_spawn("m1", ["TEAM_M"], Vector2.ZERO)
			# m2 off the m1<->pirate line (not (200,0)) -- collinear placement
			# means m1's own LOS raycast to the pirate hits m2's hull first
			# and reads as blocked, which would silently defeat the "m1
			# detects the pirate directly" half of this scenario.
			var m2 = _spawn("m2", ["TEAM_M"], Vector2(0, 300))
			var pirate_r = _spawn("pirate", ["TEAM_R"], Vector2(3000, 0))
			pirate_r.set_transponder_flag(Standing.FLAG_PIRATE)
			# m2 must learn about the pirate ONLY via the datalink from m1 --
			# power down its own sensors so it cannot directly detect it.
			for comp in m2.get_components_by_type("sensors"):
				comp["powered_on"] = false
		5:
			print("\n--- Scenario F: mark_contact_hostile works ---")
			_spawn("observer", ["TEAM_F"], Vector2.ZERO)
			_spawn("target", ["TEAM_G"], Vector2(2500, 0))
		_:
			print("\nAll standing e2e scenarios passed!")
			print(">>> [TEST PASSED] test_standing_e2e <<<")
			get_tree().quit(0)

func _physics_process(delta: float) -> void:
	if scenario_idx < 0 or scenario_idx >= NUM_SCENARIOS:
		return
	scenario_timer += delta

	var result: int = -1 # -1 keep waiting, 0 fail, 1 pass
	match scenario_idx:
		0: result = _tick_scenario_a()
		1: result = _tick_scenario_b()
		2: result = _tick_scenario_c()
		3: result = _tick_scenario_d()
		4: result = _tick_scenario_e()
		5: result = _tick_scenario_f()

	if result == 1:
		_start_scenario(scenario_idx + 1)
	elif result == 0:
		print(">>> [TEST FAILED] test_standing_e2e <<<")
		get_tree().quit(1)
	elif scenario_timer > SCENARIO_TIMEOUT:
		printerr("  ASSERT FAILED: scenario ", scenario_idx, " timed out in phase ", phase)
		print(">>> [TEST FAILED] test_standing_e2e <<<")
		get_tree().quit(1)

# --- Scenario A: dark stranger tracked, not engaged -------------------------
func _tick_scenario_a() -> int:
	var observer: Ship = ships["observer"]
	var stranger: Ship = ships["stranger"]
	var c: Dictionary = _find_contact(observer, stranger)
	if c.is_empty():
		return -1
	if c.get("standing", "") == Standing.HOSTILE:
		printerr("  ASSERT FAILED: a dark, non-reporting stranger should never read HOSTILE, got standing=", c.get("standing", ""))
		return 0
	if c.get("standing", "") != Standing.UNREPORTED:
		return -1 # let a couple more ticks settle it
	print("  [PASS] dark stranger tracked as UNREPORTED (not engaged): reason='", c.get("standing_reason", ""), "'")
	return 1

# --- Scenario B: pirate-flagged ship engaged --------------------------------
func _tick_scenario_b() -> int:
	var observer: Ship = ships["observer"]
	var pirate: Ship = ships["pirate"]
	var c: Dictionary = _find_contact(observer, pirate)
	if c.is_empty() or c.get("standing", "") != Standing.HOSTILE:
		return -1
	print("  [PASS] pirate-flagged ship IS engaged: reason='", c.get("standing_reason", ""), "'")
	return 1

# --- Scenario C: first-hit victim flip + witness stray-fire dampening ------
func _tick_scenario_c() -> int:
	var attacker: Ship = ships["attacker"]
	var victim: Ship = ships["victim"]
	var witness: Ship = ships["witness"]

	match phase:
		0:
			# Both the victim and the witness need their OWN fresh track on
			# the attacker: the victim's own marking requires a track on the
			# attacker to flip (take_damage's "no track -> no marking" rule),
			# and the witness needs a live track to "see" the aggression event.
			if _has_fresh_track(victim, attacker) and _has_fresh_track(witness, attacker):
				phase = 1
				step_frame = 0
			return -1
		1:
			victim.take_damage(10.0, victim.position + Vector2(-32, 0), Vector2(1, 0), "laser", attacker.get_instance_id())
			phase = 2
			step_frame = 0
			return -1
		2:
			step_frame += 1
			if step_frame < 3:
				return -1 # give the witness's own fusion tick a few frames to consume the aggression event
			var v_c: Dictionary = _find_contact(victim, attacker)
			if v_c.get("standing", "") != Standing.HOSTILE or not ("fired on us" in v_c.get("standing_reason", "")):
				printerr("  ASSERT FAILED: victim should flip HOSTILE on the first hit ('fired on us'), got standing=", v_c.get("standing", ""), " reason='", v_c.get("standing_reason", ""), "'")
				return 0
			var w_c: Dictionary = _find_contact(witness, attacker)
			if w_c.get("standing", "") != Standing.SUSPICIOUS or w_c.get("aggro_hits", 0) != 1:
				printerr("  ASSERT FAILED: witness should be dampened to SUSPICIOUS (aggro_hits=1) after 1 stray hit, got standing=", w_c.get("standing", ""), " aggro_hits=", w_c.get("aggro_hits", 0))
				return 0
			print("  [PASS] first hit: victim flipped HOSTILE ('fired on us'), witness dampened to SUSPICIOUS (aggro_hits=1, reason='", w_c.get("standing_reason", ""), "')")
			phase = 3
			step_frame = 0
			return -1
		3:
			victim.take_damage(10.0, victim.position + Vector2(-32, 0), Vector2(1, 0), "laser", attacker.get_instance_id())
			phase = 4
			step_frame = 0
			return -1
		4:
			step_frame += 1
			if step_frame < 3:
				return -1
			var w_c2: Dictionary = _find_contact(witness, attacker)
			if w_c2.get("standing", "") != Standing.SUSPICIOUS or w_c2.get("aggro_hits", 0) != 2:
				printerr("  ASSERT FAILED: witness should still be dampened (aggro_hits=2, below STRAY_HITS_TO_HOSTILE) after 2 stray hits, got standing=", w_c2.get("standing", ""), " aggro_hits=", w_c2.get("aggro_hits", 0))
				return 0
			print("  [PASS] second hit: witness still dampened (aggro_hits=2)")
			phase = 5
			step_frame = 0
			return -1
		5:
			victim.take_damage(10.0, victim.position + Vector2(-32, 0), Vector2(1, 0), "laser", attacker.get_instance_id())
			phase = 6
			step_frame = 0
			return -1
		6:
			step_frame += 1
			if step_frame < 3:
				return -1
			var w_c3: Dictionary = _find_contact(witness, attacker)
			if w_c3.get("standing", "") != Standing.HOSTILE or not ("sustained attack" in w_c3.get("standing_reason", "")):
				printerr("  ASSERT FAILED: witness should escalate to HOSTILE ('sustained attack') on the 3rd stray hit (STRAY_HITS_TO_HOSTILE=", Standing.STRAY_HITS_TO_HOSTILE, "), got standing=", w_c3.get("standing", ""), " reason='", w_c3.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] third hit: witness escalated to HOSTILE (reason='", w_c3.get("standing_reason", ""), "')")
			return 1
	return -1

# --- Scenario D: assistance exemption ---------------------------------------
func _tick_scenario_d() -> int:
	var observer: Ship = ships["observer"]
	var enforcer: Ship = ships["enforcer"]
	var pirate_q: Ship = ships["pirate"]

	match phase:
		0:
			# Wait until the observer already judges pirate_q HOSTILE (via the
			# known-enemy flag) AND holds a fresh track on the enforcer, so the
			# exemption branch is actually exercised (not just a "no track" bypass).
			var q_c: Dictionary = _find_contact(observer, pirate_q)
			if q_c.get("standing", "") == Standing.HOSTILE and _has_fresh_track(observer, enforcer):
				phase = 1
				step_frame = 0
			return -1
		1:
			# The enforcer engages the already-HOSTILE pirate -- assistance, not aggression.
			pirate_q.take_damage(10.0, pirate_q.position + Vector2(-32, 0), Vector2(1, 0), "laser", enforcer.get_instance_id())
			phase = 2
			step_frame = 0
			return -1
		2:
			step_frame += 1
			if step_frame < 3:
				return -1
			var e_c: Dictionary = _find_contact(observer, enforcer)
			var std: String = e_c.get("standing", "")
			if std == Standing.HOSTILE or std == Standing.SUSPICIOUS or e_c.get("aggro_hits", 0) != 0:
				printerr("  ASSERT FAILED: assistance exemption should NOT flip/dampen the enforcer's standing, got standing='", std, "' aggro_hits=", e_c.get("aggro_hits", 0))
				return 0
			print("  [PASS] assistance exemption held: engaging an already-HOSTILE target did not flip the witness's judgment of the enforcer (standing stays '", std, "')")
			return 1
	return -1

# --- Scenario E: datalink standing share ------------------------------------
func _tick_scenario_e() -> int:
	var m1: Ship = ships["m1"]
	var m2: Ship = ships["m2"]
	var pirate_r: Ship = ships["pirate"]

	var m1_c: Dictionary = _find_contact(m1, pirate_r)
	if m1_c.get("standing", "") != Standing.HOSTILE:
		return -1 # m1 hasn't judged it directly yet

	var m2_c: Dictionary = _find_contact(m2, pirate_r)
	if m2_c.is_empty() or m2_c.get("standing", "") != Standing.HOSTILE:
		return -1 # datalink import/adoption hasn't propagated yet

	var reason: String = m2_c.get("standing_reason", "")
	if not reason.begins_with("datalink "):
		printerr("  ASSERT FAILED: m2's adopted HOSTILE standing should read as relayed (\"datalink <peer>: ...\"), got reason='", reason, "'")
		return 0
	print("  [PASS] datalink share propagated HOSTILE to the linked friendly (m2's own sensors are off): reason='", reason, "'")
	return 1

# --- Scenario F: mark_contact_hostile ---------------------------------------
func _tick_scenario_f() -> int:
	var observer: Ship = ships["observer"]
	var target: Ship = ships["target"]

	match phase:
		0:
			if _has_fresh_track(observer, target):
				var c_id: String = _contact_id_for(observer, target)
				observer.mark_contact_hostile(c_id, "test reason")
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 2:
				return -1
			var c: Dictionary = _find_contact(observer, target)
			if c.get("standing", "") != Standing.HOSTILE or c.get("standing_reason", "") != "test reason":
				printerr("  ASSERT FAILED: mark_contact_hostile should set HOSTILE with the given reason, got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] mark_contact_hostile: standing=HOSTILE reason='", c.get("standing_reason", ""), "'")
			return 1
	return -1
