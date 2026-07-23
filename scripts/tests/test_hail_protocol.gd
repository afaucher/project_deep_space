extends Node

# M49 -- live-ship scenarios for the hail protocol (design_ideas/comms_verbs.md
# is THE SPEC). Modeled on test_standing_e2e.gd's multi-scenario, frame-driven
# style: each scenario spawns a small cast of real ships, polls state until the
# condition under test settles (or a per-scenario timeout fires), then tears
# down and moves to the next. Godot 2D physics/timing isn't bit-deterministic
# run-to-run (CLAUDE.md), so every assertion here is a settle-and-check
# against a generous timeout, never an exact-frame check.
#
# Covers comms_verbs.md's scenario list items relevant to the wire protocol +
# standing rules: (a) directed delivery + comms-range gating, (b) the
# addressed target's own STOP standing rule (+ police-stop exemption),
# (c) the overheard witness rule (+ authority-flag and assistance
# exemptions), (d) ACKNOWLEDGE's in_reply_to disambiguation (M52d renamed
# the verb from COMPLY), (e) SOS delivery + nature/name + TTL decay.
# Honored-stop mechanics (comply-or-run, the fire guard, the hold's
# heartbeat lapse, auto-resume) live in test_honored_stop.gd; the patrol
# IDENTIFY challenge flow lives in test_patrol_challenge.gd; the M52d demand
# heartbeat/expiry lives in test_demand_lifecycle.gd. (M52d removed the
# RELEASE verb entirely -- see hail.gd/ship.gd.)

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")

var main_node: Node = null
var spawned: Array[Node] = []
var ships: Dictionary = {}

var scenario_idx: int = -1
const NUM_SCENARIOS = 8
# Per-scenario timeout (sim seconds) -- most scenarios settle in a couple of
# sensor-fusion ticks, but SOS decay (scenario 7) needs to tick past its own
# ~90s TTL, so it gets a much longer budget.
const SCENARIO_TIMEOUTS := [8.0, 10.0, 10.0, 10.0, 10.0, 10.0, 8.0, 110.0]
var scenario_timer: float = 0.0

var phase: int = 0
var step_frame: int = 0
var _seq_a_captured: int = -1

func setup(main) -> void:
	main_node = main
	print("Test test_hail_protocol initialized.")
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

func _has_fresh_track(observer: Ship, target: Node) -> bool:
	var c: Dictionary = _find_contact(observer, target)
	if c.is_empty():
		return false
	return c.get("last_seen_timer", 999.0) <= observer.FIRE_STALENESS_MAX

func _heard_demand_from(ship: Ship, sender: Node) -> bool:
	for h in ship.last_hails:
		if h.get("verb", "") == Hail.VERB_DEMAND and h.get("sender_iid", -1) == sender.get_instance_id():
			return true
	return false

func _start_scenario(idx: int) -> void:
	scenario_idx = idx
	scenario_timer = 0.0
	phase = 0
	step_frame = 0
	_cleanup()
	Standing.reset()
	Hail.reset()

	match idx:
		0:
			print("\n--- Scenario A: directed DEMAND(STOP) delivery -- addressed + overheard + range gating ---")
			_spawn("issuer", ["TEAM_I"], Vector2.ZERO)
			_spawn("target", ["TEAM_T"], Vector2(5000, 0))
			_spawn("bystander", ["TEAM_BY"], Vector2(-3000, 4000)) # 5000 from issuer -- in range
			_spawn("far_ship", ["TEAM_FAR"], Vector2(100000, 0))   # far beyond the 30000 comms range
		1:
			print("\n--- Scenario B: addressed target's STOP standing rule -- issuer flips HOSTILE (no authority flag) ---")
			_spawn("issuer", ["TEAM_I2"], Vector2.ZERO)
			_spawn("target", ["TEAM_T2"], Vector2(3000, 0))
		2:
			print("\n--- Scenario C: addressed target's police-stop exemption (issuer's flag is a trusted authority) ---")
			var target_c = _spawn("target", ["TEAM_T3"], Vector2(3000, 0))
			target_c.authority_flags = ["MILITIA"]
			var issuer_c = _spawn("issuer", ["TEAM_I3"], Vector2.ZERO)
			issuer_c.set_transponder_flag("MILITIA")
		3:
			print("\n--- Scenario D: overheard witness rule -- bystander flips HOSTILE on the issuer (no exemptions apply) ---")
			_spawn("issuer", ["TEAM_I4"], Vector2.ZERO)
			_spawn("target", ["TEAM_T4"], Vector2(20000, 500)) # elsewhere -- bystander need not see it
			_spawn("bystander", ["TEAM_BY4"], Vector2(2500, 0))
		4:
			print("\n--- Scenario E: overheard witness -- authority-flag exemption (no flip) ---")
			var bystander_e = _spawn("bystander", ["TEAM_BY5"], Vector2(2500, 0))
			bystander_e.authority_flags = ["MILITIA"]
			_spawn("target", ["TEAM_T5"], Vector2(20000, 500))
			var issuer_e = _spawn("issuer", ["TEAM_I5"], Vector2.ZERO)
			issuer_e.set_transponder_flag("MILITIA")
		5:
			print("\n--- Scenario F: overheard witness -- assistance exemption (target already HOSTILE to the witness) ---")
			_spawn("issuer", ["TEAM_I6"], Vector2.ZERO)
			var target_f = _spawn("target", ["TEAM_T6"], Vector2(2500, 2500))
			target_f.set_transponder_flag(Standing.FLAG_PIRATE) # auto-HOSTILE to any observer via known_enemy_flags
			_spawn("bystander", ["TEAM_BY6"], Vector2(2500, -2500))
		6:
			print("\n--- Scenario G: COMPLY's in_reply_to disambiguates simultaneous demands ---")
			_spawn("target", ["TEAM_T7"], Vector2.ZERO)
			_spawn("issuer_a", ["TEAM_A7"], Vector2(3000, 0))
			_spawn("issuer_b", ["TEAM_B7"], Vector2(-3000, 0))
		7:
			print("\n--- Scenario H: SOS delivery (nature+name) and TTL decay ---")
			_spawn("caller", ["TEAM_C8"], Vector2.ZERO)
			_spawn("listener", ["TEAM_L8"], Vector2(2000, 0))
		_:
			print("\nAll hail protocol scenarios passed!")
			print(">>> [TEST PASSED] test_hail_protocol <<<")
			get_tree().quit(0)

func _physics_process(delta: float) -> void:
	if scenario_idx < 0 or scenario_idx >= NUM_SCENARIOS:
		return
	scenario_timer += delta

	var result: int = -1
	match scenario_idx:
		0: result = _tick_scenario_a()
		1: result = _tick_scenario_b()
		2: result = _tick_scenario_c()
		3: result = _tick_scenario_d()
		4: result = _tick_scenario_e()
		5: result = _tick_scenario_f()
		6: result = _tick_scenario_g()
		7: result = _tick_scenario_h()

	if result == 1:
		_start_scenario(scenario_idx + 1)
	elif result == 0:
		print(">>> [TEST FAILED] test_hail_protocol <<<")
		get_tree().quit(1)
	elif scenario_timer > SCENARIO_TIMEOUTS[scenario_idx]:
		printerr("  ASSERT FAILED: scenario ", scenario_idx, " timed out in phase ", phase)
		print(">>> [TEST FAILED] test_hail_protocol <<<")
		get_tree().quit(1)

# --- Scenario A: directed delivery + range gating ---------------------------
func _tick_scenario_a() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]
	var bystander: Ship = ships["bystander"]
	var far_ship: Ship = ships["far_ship"]

	match phase:
		0:
			step_frame += 1
			if step_frame < 3:
				return -1 # let _ready()'s scratch normalization settle
			issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
			phase = 1
			step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1 # give comms_inbox processing a couple of ticks
			if target.pending_demand.get("rung", "") != Hail.RUNG_STOP or target.pending_demand.get("sender_iid", -1) != issuer.get_instance_id():
				printerr("  ASSERT FAILED: target should hold a pending STOP demand from issuer, got pending_demand=", target.pending_demand)
				return 0
			if not _heard_demand_from(bystander, issuer):
				printerr("  ASSERT FAILED: in-range bystander should have overheard the directed DEMAND, last_hails=", bystander.last_hails)
				return 0
			if not far_ship.last_hails.is_empty():
				printerr("  ASSERT FAILED: out-of-range far_ship should hear nothing, got last_hails=", far_ship.last_hails)
				return 0
			print("  [PASS] directed DEMAND(STOP): target.pending_demand set; in-range bystander overheard; out-of-range far_ship heard nothing")
			return 1
	return -1

# --- Scenario B: addressed target's STOP standing rule -----------------------
func _tick_scenario_b() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]

	match phase:
		0:
			if _has_fresh_track(target, issuer):
				issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var c: Dictionary = _find_contact(target, issuer)
			if c.get("standing", "") != Standing.HOSTILE or not ("demanding we stop" in c.get("standing_reason", "")):
				printerr("  ASSERT FAILED: target should mark the issuer HOSTILE ('demanding we stop'), got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] addressed target flips the issuer HOSTILE on a STOP demand (reason='", c.get("standing_reason", ""), "')")
			return 1
	return -1

# --- Scenario C: addressed target's police-stop exemption --------------------
func _tick_scenario_c() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]

	match phase:
		0:
			if _has_fresh_track(target, issuer):
				issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var c: Dictionary = _find_contact(target, issuer)
			if c.get("standing", "") == Standing.HOSTILE:
				printerr("  ASSERT FAILED: a STOP demand from a trusted authority flag must NOT flip the issuer HOSTILE, got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] police-stop exemption held: trusted-flag STOP demand did not flip the issuer (standing='", c.get("standing", ""), "')")
			return 1
	return -1

# --- Scenario D: overheard witness rule (no exemptions) ---------------------
func _tick_scenario_d() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]
	var bystander: Ship = ships["bystander"]

	match phase:
		0:
			if _has_fresh_track(bystander, issuer):
				issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var c: Dictionary = _find_contact(bystander, issuer)
			if c.get("standing", "") != Standing.HOSTILE or not ("demanding a stop" in c.get("standing_reason", "")):
				printerr("  ASSERT FAILED: witness should flip the issuer HOSTILE ('demanding a stop of ...'), got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] witness rule: bystander flipped the issuer HOSTILE on an overheard STOP demand (reason='", c.get("standing_reason", ""), "')")
			return 1
	return -1

# --- Scenario E: overheard witness -- authority-flag exemption ---------------
func _tick_scenario_e() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]
	var bystander: Ship = ships["bystander"]

	match phase:
		0:
			if _has_fresh_track(bystander, issuer):
				issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var c: Dictionary = _find_contact(bystander, issuer)
			if c.get("standing", "") == Standing.HOSTILE:
				printerr("  ASSERT FAILED: a witness holding the issuer's flag as an authority must NOT flip it HOSTILE, got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] witness authority-flag exemption held: standing='", c.get("standing", ""), "'")
			return 1
	return -1

# --- Scenario F: overheard witness -- assistance exemption -------------------
func _tick_scenario_f() -> int:
	var issuer: Ship = ships["issuer"]
	var target: Ship = ships["target"]
	var bystander: Ship = ships["bystander"]

	match phase:
		0:
			# Need the bystander to hold BOTH a fresh track on the issuer AND
			# an already-HOSTILE track on the demand's target (the pirate).
			var target_c: Dictionary = _find_contact(bystander, target)
			if _has_fresh_track(bystander, issuer) and target_c.get("standing", "") == Standing.HOSTILE:
				issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
				phase = 1
				step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var c: Dictionary = _find_contact(bystander, issuer)
			if c.get("standing", "") == Standing.HOSTILE:
				printerr("  ASSERT FAILED: assistance exemption should NOT flip the issuer (demand's target already HOSTILE to the witness), got standing=", c.get("standing", ""), " reason='", c.get("standing_reason", ""), "'")
				return 0
			print("  [PASS] assistance exemption held: lawful interdiction of an already-HOSTILE target did not flip the issuer (standing='", c.get("standing", ""), "')")
			return 1
	return -1

# --- Scenario G: ACKNOWLEDGE in_reply_to disambiguation ----------------------
func _tick_scenario_g() -> int:
	var target: Ship = ships["target"]
	var issuer_a: Ship = ships["issuer_a"]
	var issuer_b: Ship = ships["issuer_b"]

	match phase:
		0:
			step_frame += 1
			if step_frame < 3:
				return -1
			issuer_a.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
			phase = 1
			step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			if target.pending_demand.get("sender_iid", -1) != issuer_a.get_instance_id():
				return -1 # not landed yet
			var seq_a: int = target.pending_demand.get("seq", -1)
			target.engage_dead_stop()
			if target.compelled_stop.get("issuer_iid", -1) != issuer_a.get_instance_id() or target.compelled_stop.get("demand_seq", -1) != seq_a:
				printerr("  ASSERT FAILED: compelled_stop should reference issuer_a's demand (seq=", seq_a, "), got compelled_stop=", target.compelled_stop)
				return 0
			# A second, later demand from a DIFFERENT issuer must not retroactively
			# change what we already complied with.
			issuer_b.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
			_seq_a_captured = seq_a
			phase = 2
			step_frame = 0
			return -1
		2:
			step_frame += 1
			if step_frame < 3:
				return -1
			if target.compelled_stop.get("demand_seq", -1) != _seq_a_captured or target.compelled_stop.get("issuer_iid", -1) != issuer_a.get_instance_id():
				printerr("  ASSERT FAILED: compelled_stop.demand_seq must still reference issuer_a's demand (seq=", _seq_a_captured, ") after issuer_b's later demand landed, got compelled_stop=", target.compelled_stop)
				return 0
			print("  [PASS] ACKNOWLEDGE's in_reply_to disambiguated: compelled_stop.demand_seq=", _seq_a_captured, " (issuer_a) survives a later demand from issuer_b")
			return 1
	return -1

# --- Scenario H: SOS delivery + nature/name + TTL decay ---------------------
func _tick_scenario_h() -> int:
	var caller: Ship = ships["caller"]
	var listener: Ship = ships["listener"]

	match phase:
		0:
			step_frame += 1
			if step_frame < 3:
				return -1
			caller.send_sos(Hail.NATURE_DISABLED)
			phase = 1
			step_frame = 0
			return -1
		1:
			step_frame += 1
			if step_frame < 3:
				return -1
			var caller_iid: int = caller.get_instance_id()
			if not listener.heard_sos.has(caller_iid):
				printerr("  ASSERT FAILED: listener should hold an SOS entry from the caller, heard_sos=", listener.heard_sos)
				return 0
			var sos: Dictionary = listener.heard_sos[caller_iid]
			if sos.get("nature", "") != Hail.NATURE_DISABLED or sos.get("name", "") != caller.ship_name:
				printerr("  ASSERT FAILED: SOS should carry nature=DISABLED and the caller's name, got sos=", sos)
				return 0
			print("  [PASS] SOS reached listener.heard_sos (nature='", sos.get("nature", ""), "', name='", sos.get("name", ""), "') -- now ticking past the TTL for decay")
			phase = 2
			return -1
		2:
			# Tick past HEARD_SOS_TTL (delta-accumulated, same convention as
			# Standing's aggression-event TTL) -- runs fast under --fixed-fps
			# (no real-time throttling), just many physics frames.
			var caller_iid2: int = caller.get_instance_id()
			if not listener.heard_sos.has(caller_iid2):
				print("  [PASS] SOS entry decayed and was pruned after its TTL")
				return 1
			return -1
	return -1
