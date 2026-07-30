extends Node

# Pins the rows of design_ideas/2026-07-28-authority_scenarios.md that NOTHING
# else pinned. That table was built by reading code, and the point of this file
# is to stop it being a description and make it a contract -- so a future change
# that alters one of these behaviours fails here instead of quietly making the
# design doc wrong.
#
# DELIBERATELY NOT DUPLICATED. Most of the table is already covered, better than
# the doc originally credited:
#   test_hail_protocol      overheard STOP flips the issuer CAUTION (D); the
#                           police-stop exemption on both the addressed (C) and
#                           overheard (E) branches; assistance exemption (F);
#                           comms-range gating (A)
#   test_standing_e2e       the stray-fire ladder 1/2/3 hits -> SUSTAINED_ASSAULT
#                           (C); assistance exemption on the GUNFIRE path (D)
#   test_patrol_challenge   IDENTIFY never changes standing; NO_ID on refusal;
#                           ask-once; challenge voided out of comms range
#   test_standing_rules     withheld name reads caution-tier
#   test_weapons_safety     the console refuses to fire on a non-HOSTILE track
#
# What is left, and lives here:
#   A  an overheard IDENTIFY is inert (the rung gate) -- the STOP case is
#      pinned, its counterpart never was
#   B  authority_flags does NOT protect on the gunfire path -- the structural
#      finding behind the playtest's pirate-in-port report
#   C  refusing a STOP never escalates the refuser to HOSTILE
#   D  witnessing a second stop refreshes the SAME warrant rather than adding one
#   E  the authored home cluster grants authority_flags to patrols ONLY
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_authority_scenarios

const Frigate = preload("res://scripts/ships/frigate.gd")
const ShipBase = preload("res://scripts/ships/ship.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = Frigate.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	Standing.reset()
	Hail.reset()

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func _has_fresh_track(observer, target: Node) -> bool:
	var c: Dictionary = _find_contact(observer, target)
	return not c.is_empty() and ShipBase.contact_age(c) <= observer.FIRE_STALENESS_MAX

# Warrants of `offense` this observer holds, by event_key. Keyed rather than
# counted so scenario D can prove a re-post OVERWROTE instead of accumulating.
func _warrants_of(observer, offense: String) -> Dictionary:
	var out: Dictionary = {}
	for key in observer.warrants:
		var w: Dictionary = observer.warrants[key]
		if w.get("offense", "") == offense and w.get("status", "") == Standing.WARRANT_OPEN:
			out[key] = w
	return out

func _settle(frames: int) -> void:
	for i in range(frames):
		await main_node.get_tree().physics_frame

# Wait until `observer` holds a fresh track on `target`, or give up. Every
# scenario needs this first: the witness rules all require a live track on the
# ship being judged, so without it a "nothing happened" assertion passes for the
# wrong reason.
func _await_track(observer, target: Node, limit: int = 600) -> bool:
	for i in range(limit):
		await main_node.get_tree().physics_frame
		if _has_fresh_track(observer, target):
			return true
	return false

func setup(main) -> void:
	main_node = main
	print("=== test_authority_scenarios: pinning the authority table (design_ideas/2026-07-28-authority_scenarios.md) ===")

	await _scenario_a_overheard_identify_is_inert()
	await _scenario_b_authority_does_not_cover_gunfire()
	await _scenario_c_refusal_never_escalates()
	await _scenario_d_repeat_stop_refreshes_one_warrant()
	_scenario_e_authored_authority_flags()

	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_authority_scenarios <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_authority_scenarios <<<")
		get_tree().quit(1)

# --- A: an overheard IDENTIFY is inert ---------------------------------------
# Table row: "In port. The station demands ID of another ship." -> one engineering
# log line, nothing else. test_hail_protocol pins the STOP counterpart (a
# bystander flips the issuer CAUTION); the IDENTIFY case was never pinned, and it
# is the load-bearing half of comms_verbs.md's "demanding INFORMATION is never
# coercion". If the rung gate ever widens, every patrol doing its job would start
# painting itself yellow to every civilian in earshot.
func _scenario_a_overheard_identify_is_inert() -> void:
	print("\n--- A: overhearing a DEMAND(IDENTIFY) judges nobody ---")
	var issuer = _make_ship("A_Issuer", 700, Vector2(0, 0), ["TEAM_A_ISS"])
	var target = _make_ship("A_Target", 701, Vector2(2000, 0), ["TEAM_A_TGT"])
	var witness = _make_ship("A_Witness", 702, Vector2(1000, 500), ["TEAM_A_WIT"])

	var tracked: bool = await _await_track(witness, issuer)
	_assert(tracked, "A setup: the witness holds a fresh track on the issuer (else 'nothing happened' proves nothing)")

	issuer.send_demand(target.get_instance_id(), Hail.RUNG_IDENTIFY)
	await _settle(30)

	var heard := false
	for h in witness.last_hails:
		if h.get("sender_iid", -1) == issuer.get_instance_id() and h.get("rung", "") == Hail.RUNG_IDENTIFY:
			heard = true
	_assert(heard, "A setup: the witness DID overhear the demand (it is in range and recorded it)")

	_assert(_warrants_of(witness, Standing.OFF_ARMED_THREAT).is_empty(),
		"A: overhearing an IDENTIFY posts NO ARMED_THREAT against the issuer")
	var issuer_view: Dictionary = _find_contact(witness, issuer)
	_assert(issuer_view.get("standing_reason", "").find("demanding") == -1,
		"A: ...and the issuer's standing_reason says nothing about demanding (got '%s')" % issuer_view.get("standing_reason", ""))

	_free_all()

# --- B: authority_flags does NOT cover gunfire ------------------------------
# THE STRUCTURAL FINDING behind the playtest's "a ship arrives flying the pirate
# flag, the station opens fire, and my ship issued a warrant against IT".
#
# authority_flags is read in exactly two places, both on DEMAND(STOP) branches.
# The aggression-witness loop never consults it. So "that is my own militia doing
# its job" is not expressible when the enforcement is gunfire rather than a hail
# -- the only protection is the assistance exemption, which requires having
# ALREADY resolved the victim as HOSTILE, i.e. winning a race against the
# datalink relay.
#
# This test grants the observer the shooter's flag as a trusted authority and
# shows it changes nothing. If someone later adds an authority check to that
# loop, this test fails and the design doc needs updating -- which is the point.
func _scenario_b_authority_does_not_cover_gunfire() -> void:
	print("\n--- B: trusting the shooter's flag does NOT stop a witnessed-assault warrant ---")
	var shooter = _make_ship("B_Shooter", 710, Vector2(0, 0), ["TEAM_B_SHOOT"])
	var victim = _make_ship("B_Victim", 711, Vector2(1200, 0), ["TEAM_B_VIC"])
	var observer = _make_ship("B_Observer", 712, Vector2(600, 600), ["TEAM_B_OBS"])

	# The observer trusts the shooter's flag as an interdiction authority -- the
	# strongest form of "this is my own police" the model can express.
	shooter.set_transponder_flag(Standing.FLAG_DRIFT)
	observer.authority_flags = [Standing.FLAG_DRIFT]

	var t1: bool = await _await_track(observer, shooter)
	_assert(t1, "B setup: the observer holds a fresh track on the shooter")
	# The victim must NOT read HOSTILE to the observer, or the assistance
	# exemption fires and we would be re-testing test_standing_e2e's scenario D.
	var v_view: Dictionary = _find_contact(observer, victim)
	_assert(v_view.get("standing", "") != Standing.HOSTILE,
		"B setup: the observer does NOT read the victim as HOSTILE (assistance exemption must not apply)")

	for i in range(Standing.STRAY_HITS_TO_HOSTILE):
		victim.take_damage(10.0, victim.position + Vector2(-32, 0), Vector2(1, 0), "laser", shooter.get_instance_id())
		await _settle(4)

	var s_view: Dictionary = _find_contact(observer, shooter)
	_assert(s_view.get("standing", "") == Standing.HOSTILE,
		"B: the observer flips its OWN trusted authority to HOSTILE after %d stray hits (got '%s')"
			% [Standing.STRAY_HITS_TO_HOSTILE, s_view.get("standing", "")])
	_assert(not _warrants_of(observer, Standing.OFF_SUSTAINED_ASSAULT).is_empty(),
		"B: ...and posts SUSTAINED_ASSAULT against it -- authority_flags is never consulted on this path")

	# The consequence that makes it unrecoverable rather than merely wrong.
	_assert(Standing.default_expiry_seconds(Standing.OFF_SUSTAINED_ASSAULT) < 0.0,
		"B: SUSTAINED_ASSAULT never expires, so this verdict is permanent once reached")
	_assert(Standing.authorizes_force(Standing.OFF_SUSTAINED_ASSAULT),
		"B: ...and it authorizes force against the station that was defending the port")

	_free_all()

# --- C: refusing a STOP never escalates the refuser -------------------------
# Table row: "You keep running." -> not much. Worth pinning because it is the
# reason the escalation ladder is currently toothless: a hull that simply ignores
# every demand stays caution-tier, and a patrol needs HOSTILE to fire. If a
# future rung DOES escalate on refusal, that is a deliberate design change and
# this assertion is where it announces itself.
func _scenario_c_refusal_never_escalates() -> void:
	print("\n--- C: ignoring a STOP demand does not make the refuser HOSTILE ---")
	var issuer = _make_ship("C_Issuer", 720, Vector2(0, 0), ["TEAM_C_ISS"])
	var refuser = _make_ship("C_Refuser", 721, Vector2(1500, 0), ["TEAM_C_REF"])

	var tracked: bool = await _await_track(issuer, refuser)
	_assert(tracked, "C setup: the issuer holds a fresh track on the refuser")

	var seq: int = issuer.send_demand(refuser.get_instance_id(), Hail.RUNG_STOP)
	var landed := false
	for i in range(180):
		await main_node.get_tree().physics_frame
		if refuser.pending_demand.get("seq", -1) == seq:
			landed = true
			break
	_assert(landed, "C setup: the demand landed on the refuser")

	# Refuse by doing nothing at all -- never acknowledge, never stop.
	await _settle(240)

	var view: Dictionary = _find_contact(issuer, refuser)
	_assert(view.get("standing", "") != Standing.HOSTILE,
		"C: the issuer does NOT read a non-complying target as HOSTILE (got '%s')" % view.get("standing", ""))
	_assert(_warrants_of(issuer, Standing.OFF_ASSAULT).is_empty()
			and _warrants_of(issuer, Standing.OFF_SUSTAINED_ASSAULT).is_empty(),
		"C: ...and posts no assault-grade warrant for the refusal alone")

	_free_all()

# --- D: a second witnessed stop refreshes ONE warrant -----------------------
# Table row: "You watch several stops over half an hour." -> the authority is
# effectively permanently yellow. The mechanism is that post_warrant keys on
# (offense, subject), so a re-post overwrites in place with a fresh timestamp
# rather than accumulating -- which is why the 1800s ARMED_THREAT window restarts
# on every stop you happen to see.
func _scenario_d_repeat_stop_refreshes_one_warrant() -> void:
	print("\n--- D: witnessing a second stop refreshes the same warrant, does not add one ---")
	var issuer = _make_ship("D_Issuer", 730, Vector2(0, 0), ["TEAM_D_ISS"])
	var target = _make_ship("D_Target", 731, Vector2(2000, 0), ["TEAM_D_TGT"])
	var witness = _make_ship("D_Witness", 732, Vector2(1000, 500), ["TEAM_D_WIT"])

	var tracked: bool = await _await_track(witness, issuer)
	_assert(tracked, "D setup: the witness holds a fresh track on the issuer")

	issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
	await _settle(30)

	var first: Dictionary = _warrants_of(witness, Standing.OFF_ARMED_THREAT)
	_assert(first.size() == 1, "D setup: witnessing one stop posted exactly one ARMED_THREAT (got %d)" % first.size())
	if first.size() != 1:
		_free_all()
		return
	var key: String = first.keys()[0]
	var ts1: int = first[key].get("timestamp", -1)

	# A genuinely NEW stop demand (fresh seq), witnessed again a moment later.
	await _settle(60)
	issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
	await _settle(30)

	var second: Dictionary = _warrants_of(witness, Standing.OFF_ARMED_THREAT)
	_assert(second.size() == 1,
		"D: still exactly ONE ARMED_THREAT warrant after a second witnessed stop (got %d) -- keyed by (offense, subject)" % second.size())
	_assert(second.has(key), "D: ...under the same event_key")
	_assert(second.get(key, {}).get("timestamp", -1) > ts1,
		"D: ...with a REFRESHED timestamp, which is what restarts the expiry window (%d -> %d)"
			% [ts1, second.get(key, {}).get("timestamp", -1)])

	_free_all()

# --- E: who actually carries authority_flags in the shipped cluster ---------
# Table row: "A hauler witnesses the same police stop." -> same as you; the whole
# civilian population reads its own police as caution-tier.
#
# This is a DATA claim, not a logic one: the exemption mechanism works (pinned by
# test_hail_protocol E), it is simply authored on one entity type. Asserted
# against HomeCluster.build() directly -- no ships, no frames -- so it stays true
# of the cluster that actually ships rather than of a synthetic fixture.
func _scenario_e_authored_authority_flags() -> void:
	print("\n--- E: the authored home cluster grants authority_flags to patrols only ---")
	var def = HomeCluster.build()
	var with_flags: Array = []
	var without_flags: Array = []
	for e in def.entities:
		var af: Array = e.get("authority_flags", [])
		if af.is_empty():
			without_flags.append(e.get("name", "?"))
		else:
			with_flags.append(e.get("name", "?"))

	_assert(not with_flags.is_empty(), "E setup: at least one authored entity carries authority_flags")
	_assert(not without_flags.is_empty(), "E setup: ...and at least one does not")

	# Every holder is a patrol. Identified by carrying a patrol behaviour route
	# AND the flag, rather than by name matching, so renaming a patrol does not
	# silently pass this.
	var non_patrol_holders: Array = []
	for e in def.entities:
		if e.get("authority_flags", []).is_empty():
			continue
		if not e.get("behavior", {}).has("route"):
			non_patrol_holders.append(e.get("name", "?"))
	_assert(non_patrol_holders.is_empty(),
		"E: only route-flying patrols hold authority_flags (unexpected holders: %s)" % str(non_patrol_holders))

	# And the ones that do NOT hold it include the things the table calls out:
	# stations and haulers. They are the population that reads its own police as
	# caution-tier after witnessing a lawful stop.
	_assert(without_flags.size() > with_flags.size(),
		"E: the population WITHOUT the exemption (%d) outnumbers the patrols with it (%d)"
			% [without_flags.size(), with_flags.size()])
	print("     holders: %s" % str(with_flags))
	print("     %d authored entities have no authority_flags" % without_flags.size())
