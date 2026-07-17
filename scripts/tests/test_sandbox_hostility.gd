extends Node

# M48 regression: the SANDBOX spawn path (main._spawn_ship) must flag AI combat
# ships so they actually fight under the standing model. This path is pure
# runtime wiring -- no headless test covered it, and it was shipped broken once
# (enemies spawned mutually NEUTRAL, so nothing engaged). This test drives the
# REAL main._spawn_ship and asserts the resulting standings:
#   - an ENEMY-team ship reads HOSTILE to a home-flagged player (and vice versa)
#   - a FRIENDLY-team ship reads FRIENDLY to the player (shared crypto tags)
#     and HOSTILE to the enemy
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sandbox_hostility

const Frigate = preload("res://scripts/ships/frigate.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const SETTLE_FRAMES := 240   # a few seconds for sensor sweeps + datalink to establish standing

var main_node: Node
var player: Node
var enemy: Node
var friendly: Node
var frame := 0
var failures: Array = []

func setup(main) -> void:
	main_node = main
	print("=== test_sandbox_hostility: main._spawn_ship must flag AI ships so combat starts ===")

	# A player ship the way the sandbox has one: home flag, registered as
	# players[1] so _spawn_ship reads its tags/position for placement.
	player = Frigate.new()
	player.name = "PlayerShip"
	player.owner_id = 1
	player.iff_tags = ["TEAM_PLAYER"]
	player.position = Vector2.ZERO
	main_node.add_child(player)
	player.set_transponder_flag(Standing.FLAG_DRIFT)
	main_node.players[1] = player

	# Drive the REAL spawn path under test.
	enemy = main_node._spawn_ship(Frigate, ShipCatalog.Team.ENEMY)
	friendly = main_node._spawn_ship(Frigate, ShipCatalog.Team.FRIENDLY)

	# Pull them into a tight, mutually-sensing cluster (the random 15k scatter
	# can otherwise straddle a sweep's first-acquisition timing); comms range
	# is 30k so all three link.
	enemy.position = Vector2(6000, 0)
	friendly.position = Vector2(0, 6000)

func _standing_of(observer: Node, target: Node) -> String:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		if observer.active_contacts[c_id].get("instance_id", -1) == tid:
			return observer.active_contacts[c_id].get("standing", "<no-track>")
	return "<no-track>"

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
	print(("  ok: " if cond else "  FAIL: "), msg)

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame < SETTLE_FRAMES:
		return
	set_physics_process(false)

	# The flag it was actually given (the thing the agent's claim got wrong).
	_check(enemy.get_active_transponder_data().get("flag", "") == Standing.FLAG_PIRATE,
		"ENEMY-team ship flies the black flag")
	_check(friendly.get_active_transponder_data().get("flag", "") == Standing.FLAG_DRIFT,
		"FRIENDLY-team ship flies the home flag")

	# The standings that make combat actually happen.
	_check(_standing_of(player, enemy) == Standing.HOSTILE,
		"player reads ENEMY as HOSTILE (got %s)" % _standing_of(player, enemy))
	_check(_standing_of(enemy, player) == Standing.HOSTILE,
		"ENEMY reads player as HOSTILE (got %s)" % _standing_of(enemy, player))
	_check(_standing_of(friendly, enemy) == Standing.HOSTILE,
		"FRIENDLY reads ENEMY as HOSTILE (got %s)" % _standing_of(friendly, enemy))
	_check(_standing_of(player, friendly) == Standing.FRIENDLY,
		"player reads FRIENDLY-team ship as FRIENDLY via crypto (got %s)" % _standing_of(player, friendly))

	if failures.is_empty():
		print(">>> [TEST PASSED] test_sandbox_hostility <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		printerr(">>> [TEST FAILED] test_sandbox_hostility <<<")
		get_tree().quit(1)
