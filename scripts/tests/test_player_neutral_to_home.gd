extends Node

# M53a foundation -- the player is a NEUTRAL independent, NOT crypto-kin of the
# home faction. Pure-rules unit pass over Standing.compute_standing using the
# WIRED HomeCluster.HOME_IFF constant (not a hand-typed tag), so this is a real
# regression sentinel: if HOME_IFF ever goes back to sharing the player's
# TEAM_PLAYER crypto tag, the crypto handshake makes the player FRIENDLY again
# and the M52 interdiction contract silently stops applying to them -- exactly
# the bug this milestone fixed, and the one nothing else in the suite covers
# (the change decoupled a constant no existing test read).
#
# Model: test_standing_rules.gd -- bare Ship instances as observers (never
# added to the tree / _ready()'d; compute_standing only reads .iff_tags /
# .warrant_index / .known_enemy_flags).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_player_neutral_to_home

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")

# The player's own crypto tag (main.gd's _spawn_player_ship) and public flag
# (set_transponder_flag(FLAG_DRIFT)) -- the actual wired campaign identity.
const PLAYER_CRYPTO := "TEAM_PLAYER"

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_observer(tags: Array) -> Ship:
	var o = Ship.new()
	o.iff_tags = tags
	o.known_enemy_flags = [Standing.FLAG_PIRATE]
	o.warrant_index = {}
	return o

func setup(_main) -> void:
	print("=== test_player_neutral_to_home: campaign player reads NEUTRAL (not FRIENDLY) to home ===")
	Standing.reset()

	# The decoupling sentinel: home must NOT carry the player's crypto tag.
	_assert(not HomeCluster.HOME_IFF.has(PLAYER_CRYPTO),
		"HOME_IFF (%s) does not contain the player's crypto tag '%s' -- the decoupling is intact" % [str(HomeCluster.HOME_IFF), PLAYER_CRYPTO])

	var home_observer := _make_observer(HomeCluster.HOME_IFF)

	# The player as a contact seen by a home patrol/station: reporting (name +
	# FLAG_DRIFT), crypto TEAM_PLAYER (which home no longer shares).
	var player_contact := {"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": [PLAYER_CRYPTO]}}
	var player_transponder := {"name": "Player", "flag": Standing.FLAG_DRIFT}

	# 1. THE guarantee: player reads NEUTRAL "reporting clean", not FRIENDLY.
	var s1: Dictionary = Standing.compute_standing(player_contact, player_transponder, home_observer)
	_assert(s1.get("standing", "") == Standing.NEUTRAL,
		"player reads NEUTRAL to home (got '%s' -- reason '%s')" % [s1.get("standing", ""), s1.get("reason", "")])

	# 2. Home cohesion preserved: a home-tagged ship still reads FRIENDLY to home
	# (crypto overlap within HOME_IFF), so decoupling the player didn't break the
	# faction's own internal recognition.
	var home_contact := {"classification": "FRIENDLY VESSEL", "signature": {"iff_tags": HomeCluster.HOME_IFF}}
	var s2: Dictionary = Standing.compute_standing(home_contact, {"name": "Patrol Bravo", "flag": Standing.FLAG_DRIFT}, home_observer)
	_assert(s2.get("standing", "") == Standing.FRIENDLY,
		"a home-tagged ship still reads FRIENDLY to home (got '%s')" % s2.get("standing", ""))

	# 3. Proof the OLD wiring caused the immunity: the SAME player contact against
	# an observer that DOES share TEAM_PLAYER computes FRIENDLY -- documents
	# exactly what sharing the tag did (crypto beats flag -> uninterdictable),
	# and why HOME_IFF had to stop carrying it.
	var old_style_observer := _make_observer([PLAYER_CRYPTO])
	var s3: Dictionary = Standing.compute_standing(player_contact, player_transponder, old_style_observer)
	_assert(s3.get("standing", "") == Standing.FRIENDLY,
		"an observer sharing TEAM_PLAYER WOULD read the player FRIENDLY (the old bug -- proves the tag share was the cause)")

	# 4. A DARK player (transponder off) reads UNREPORTED to home, not FRIENDLY --
	# going dark in controlled space is what draws patrol challenges; it must
	# never fall back to friendly just because the hull used to be crypto-kin.
	var s4: Dictionary = Standing.compute_standing(player_contact, {}, home_observer)
	_assert(s4.get("standing", "") == Standing.UNREPORTED,
		"a dark (no-transponder) player reads UNREPORTED to home, not FRIENDLY (got '%s')" % s4.get("standing", ""))

	if failures.is_empty():
		print(">>> [TEST PASSED] test_player_neutral_to_home <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_player_neutral_to_home <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)
