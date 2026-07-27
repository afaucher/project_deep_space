extends Node

# What happens to a warrant when the OBSERVER's knowledge of the subject's
# identity changes between posting and lookup.
#
# Standing.subject_key() files a warrant under "name:<claimed>" when a
# transponder name is known and "sig:<tags>|<cross_section>" when it is not,
# and nothing forces those two moments to agree. warrants.md anticipated the
# ambiguity ("needs care for claimed-name vs signature identity... accept
# occasional duplicates over false merges") but budgeted for DUPLICATE
# records. The real failure mode is worse and the opposite shape: the SAME
# record becomes unreachable, because the lookup asks for a key nobody filed
# it under.
#
# Two cases pull in opposite directions and both are gameplay-visible:
#
#   1. Fire while dark, then light your transponder. The ASSAULT warrant was
#      filed under `sig:`; every later lookup asks for `name:`. Without the
#      signature fallback in compute_standing the warrant is still in the
#      index and permanently unenforceable -- turning a transponder ON
#      launders an assault.
#
#   2. Get a NO_ID warrant, then light your transponder. Here the SAME
#      mechanism is the intended resolution: warrants.md's taxonomy says
#      NO_ID "resolves itself the moment the subject reports a transponder"
#      with "no separate revocation path to build for it". The fallback must
#      NOT apply, or the cluster's most forgivable offense becomes a
#      permanent brand nothing can clear.
#
# Found while decimating the datalink relay (Ship.DATALINK_RELAY_HZ): at 60Hz
# case 1's race window was a single frame and no test ever landed in it.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_warrant_identity_change

const Standing = preload("res://scripts/combat/standing.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# A minimal stand-in for the observer Ship: compute_standing only reads
# iff_tags, known_enemy_flags and warrant_index off it.
class FakeObserver:
	var iff_tags: Array = ["TEAM_OBS"]
	var known_enemy_flags: Array = []
	var warrant_index: Dictionary = {}

func _sig() -> Dictionary:
	return {"iff_tags": ["TEAM_SUBJECT"], "cross_section": 42.0}

func _contact() -> Dictionary:
	return {"classification": "UNIDENTIFIED VESSEL", "signature": _sig()}

# Build the index the way Ship._rebuild_warrant_index does, so key derivation
# is never duplicated in the test.
func _observer_holding(offense: String, claimed_name: String) -> FakeObserver:
	var obs := FakeObserver.new()
	var subject: Dictionary = {"claimed_name": claimed_name, "signature": _sig()}
	var issuer: Dictionary = {"iid": 1, "name": "Observer"}
	var event_key: String = offense + "|" + Standing.subject_key(claimed_name, _sig())
	var w: Dictionary = Standing.make_warrant(offense, subject, issuer, "", event_key, "test")
	obs.warrant_index = Standing.build_warrant_index({event_key: w}, [], 1)
	return obs

func setup(_main) -> void:
	print("Starting warrant identity-change tests")

	# --- Case 1: dark ASSAULT, then the subject squawks ---------------------
	print("\n--- ASSAULT posted while the subject was dark, then it lights its transponder ---")
	var obs_assault := _observer_holding(Standing.OFF_ASSAULT, "")
	# Derive the key rather than spelling it out -- the literal form is
	# Standing's business, and hardcoding it here just tests float formatting.
	_assert(obs_assault.warrant_index.has(Standing.subject_key("", _sig())),
		"setup: an ASSAULT posted with no claimed name is filed under a signature key")
	_assert(not obs_assault.warrant_index.has(Standing.subject_key("Second Return", _sig())),
		"setup: and NOT under the name it will later be looked up by -- this is the whole trap")

	var dark: Dictionary = Standing.compute_standing(_contact(), {}, obs_assault)
	_assert(dark.get("standing", "") == Standing.HOSTILE,
		"while still dark, the signature-keyed ASSAULT reads HOSTILE (got '%s')" % dark.get("standing", ""))

	var squawking: Dictionary = Standing.compute_standing(
		_contact(), {"name": "Second Return", "flag": Standing.FLAG_CIVILIAN}, obs_assault)
	_assert(squawking.get("standing", "") == Standing.HOSTILE,
		"lighting a transponder does NOT launder the assault -- still HOSTILE (got '%s')" % squawking.get("standing", ""))

	# --- Case 2: NO_ID, then the subject squawks ----------------------------
	print("\n--- NO_ID posted (necessarily nameless), then the subject lights its transponder ---")
	var obs_noid := _observer_holding(Standing.OFF_NO_ID, "")
	_assert(Standing.self_resolves_on_id(Standing.OFF_NO_ID),
		"NO_ID is marked self-resolving in the offense table")
	_assert(not Standing.self_resolves_on_id(Standing.OFF_ASSAULT),
		"ASSAULT is NOT self-resolving -- squawking must never clear it")

	# CAUTION, not HOSTILE. NO_ID is caution-grade (Standing's offense table):
	# "wanted for not identifying itself" is something you cannot resolve from
	# here, not a determination that the hull is an enemy. What this case is
	# really about is the KEYING -- that the warrant is reachable at all while
	# the subject is dark -- so the tier is incidental to it, but asserting the
	# right one keeps the file honest.
	var noid_dark: Dictionary = Standing.compute_standing(_contact(), {}, obs_noid)
	_assert(noid_dark.get("standing", "") == Standing.CAUTION,
		"while still dark, the NO_ID warrant is reachable and reads CAUTION (got '%s')" % noid_dark.get("standing", ""))

	var noid_squawking: Dictionary = Standing.compute_standing(
		_contact(), {"name": "Now Reporting", "flag": Standing.FLAG_CIVILIAN}, obs_noid)
	_assert(noid_squawking.get("standing", "") == Standing.NEUTRAL,
		"reporting a transponder SELF-RESOLVES NO_ID -- back to NEUTRAL, no revocation record needed (got '%s')" % noid_squawking.get("standing", ""))

	# --- Case 3: the reverse direction stays closed -------------------------
	# A name-keyed warrant must NOT be reachable by signature. Broadening that
	# way would let a warrant against one hull apply to every ship sharing its
	# tags and cross-section, and it is also the designed UNREPORTED rule: you
	# cannot enforce a name warrant on a hull you have not identified.
	print("\n--- a NAME-keyed warrant is not reachable by signature (going dark still works) ---")
	var obs_named := _observer_holding(Standing.OFF_ASSAULT, "Known Offender")
	var gone_dark: Dictionary = Standing.compute_standing(_contact(), {}, obs_named)
	_assert(gone_dark.get("standing", "") == Standing.UNREPORTED,
		"a hull that goes dark is UNREPORTED, not HOSTILE-by-signature (got '%s')" % gone_dark.get("standing", ""))

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_warrant_identity_change <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_warrant_identity_change <<<")
		get_tree().quit(1)
