extends Node

# YOU CAN SHARE IFF WITHOUT SHARING AUTHORITY.
#
# Two ships on the same crypto handshake datalink freely -- they trade
# contacts and warrant records. But a warrant is only ENFORCEABLE by a ship
# deputized under its origin flag (Standing.warrant_enforceable_by /
# build_warrant_index). So a fleetmate can SEE that you hold a warrant and
# still, correctly, read the subject as NEUTRAL: the record travelled, the
# authority did not.
#
# WHY THIS NEEDS A LIVE TEST. test_jurisdiction_seam already pins the same
# rule -- but deliberately in pure-function style, "no scene tree/physics
# needed". That is exactly the gap this fills: the gate was correct in
# ISOLATION while the live datalink walked straight around it. Until
# 2026-07-27 the relay carried a "standing share" that copied any more-severe
# peer standing onto our own track, so a fleetmate simply ADOPTED the
# HOSTILE verdict without ever consulting enforceability. The pure-function
# test could not see it, because it never ran the relay.
#
# That share is now deleted (standing is derived locally from relayed
# EVIDENCE -- warrants and transponders -- not copied as a VERDICT), which is
# what makes this mechanic real rather than merely specified.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_shared_iff_unshared_authority

const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const FLAG_A := "SOVEREIGN_A"

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make(n: String, owner: int, tags: Array, pos: Vector2) -> Node:
	var s = Frigate.new()
	s.name = n
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _contact_on(observer: Node, subject: Node) -> Dictionary:
	var sid: int = subject.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == sid:
			return c
	return {}

func setup(main) -> void:
	main_node = main
	print("=== shared IFF, unshared authority ===")
	Standing.reset()

	# deputy and fleetmate share a crypto handshake, so they datalink.
	# ONLY deputy is deputized under FLAG_A.
	var deputy := _make("Deputy", 800, ["TEAM_SHARED"], Vector2.ZERO)
	deputy.warrant_authority = [FLAG_A]
	deputy.set_transponder_flag(FLAG_A)

	var fleetmate := _make("Fleetmate", 801, ["TEAM_SHARED"], Vector2(1500, 0))
	fleetmate.warrant_authority = []          # same fleet, no commission
	fleetmate.set_transponder_flag(FLAG_A)

	# The subject: a plain reporting hull both can see. Nothing about it is
	# inherently hostile -- the ONLY thing against it is the deputy's warrant.
	var subject := _make("Subject", 802, ["TEAM_OTHER"], Vector2(3000, 1200))
	subject.set_transponder_flag(Standing.FLAG_CIVILIAN)

	for i in range(240):
		await main_node.get_tree().physics_frame

	var d_c: Dictionary = _contact_on(deputy, subject)
	var f_c: Dictionary = _contact_on(fleetmate, subject)
	_assert(not d_c.is_empty(), "setup: the deputy holds a track on the subject")
	_assert(not f_c.is_empty(), "setup: the fleetmate holds a track on the subject too")
	_assert(f_c.get("standing", "") != Standing.HOSTILE,
		"setup: the fleetmate reads the subject as harmless BEFORE any warrant (got '%s')" % f_c.get("standing", ""))

	# The deputy posts a MAX-class warrant under its own authority.
	var claimed: String = deputy.active_transponders.get(subject.get_instance_id(), {}).get("name", "")
	deputy.post_warrant(Standing.OFF_ARMED_ROBBERY, claimed, d_c.get("signature", {}), "took cargo")
	deputy._rebuild_warrant_index()

	for i in range(240):
		await main_node.get_tree().physics_frame

	d_c = _contact_on(deputy, subject)
	f_c = _contact_on(fleetmate, subject)

	# --- The deputy enforces it. Control: without this the rest is vacuous. --
	_assert(d_c.get("standing", "") == Standing.HOSTILE,
		"the DEPUTIZED ship enforces its own warrant -- subject reads HOSTILE (got '%s')" % d_c.get("standing", ""))

	# --- The record travels... -----------------------------------------------
	var relayed := false
	for k in fleetmate.warrants:
		if fleetmate.warrants[k].get("offense", "") == Standing.OFF_ARMED_ROBBERY:
			relayed = true
			break
	_assert(relayed,
		"the WARRANT RECORD relayed to the fleetmate -- shared IFF means shared information")

	# --- ...but the authority does not. --------------------------------------
	# The heart of it. The fleetmate can read the record off its own store and
	# show it in a UI; it simply may not act on it.
	var in_index := false
	for k in fleetmate.warrant_index:
		if fleetmate.warrant_index[k].get("offense", "") == Standing.OFF_ARMED_ROBBERY:
			in_index = true
			break
	_assert(not in_index,
		"...but it never enters the fleetmate's ENFORCEABLE index (no commission under %s)" % FLAG_A)
	_assert(f_c.get("standing", "") != Standing.HOSTILE,
		"...so the fleetmate still reads the subject as NOT hostile (got '%s' -- this is the assertion the deleted standing share used to break)"
			% f_c.get("standing", ""))

	# --- Commission the fleetmate and the same record becomes enforceable ----
	# Proves the fleetmate's refusal was about AUTHORITY, not about the record
	# being missing or malformed.
	fleetmate.warrant_authority = [FLAG_A]
	fleetmate._rebuild_warrant_index()
	for i in range(180):
		await main_node.get_tree().physics_frame

	f_c = _contact_on(fleetmate, subject)
	_assert(f_c.get("standing", "") == Standing.HOSTILE,
		"once COMMISSIONED under %s, the fleetmate enforces the very same record (got '%s')"
			% [FLAG_A, f_c.get("standing", "")])

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_shared_iff_unshared_authority <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_shared_iff_unshared_authority <<<")
		get_tree().quit(1)
