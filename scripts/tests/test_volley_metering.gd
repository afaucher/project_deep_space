extends Node

# M12a: massed-fire TIMING (Ship.is_group_volley_ready). Encodes the rule:
#   - hold the volley while any tube that could still fire (alive, powered, has ammo) is
#     on cooldown -- wait so the battery launches together and saturates PD;
#   - never wait on a tube that is damaged, out of ammo, or disabled.
const Frigate = preload("res://scripts/ships/frigate.gd")

var ship
var tubes: Array = []

func setup(main) -> void:
	print("Test test_volley_metering initialized.")
	var failures: Array = []

	ship = Frigate.new()
	ship.name = "VolleyShip"
	ship.owner_id = 1
	ship.position = Vector2.ZERO
	main.add_child(ship)

	for w in ship.get_components_by_type("weapons"):
		if ship.get_weapon_group_id(w) == "port" and w["weapon_type"] == "missile":
			tubes.append(w["id"])
	if tubes.size() != 3:
		failures.append("expected 3 port missile tubes, got %d (%s)" % [tubes.size(), tubes])

	# A) all tubes fresh -> volley ready
	_reset()
	if not _volley_ready():
		failures.append("A: all tubes fresh -> expected volley READY")

	# B) one live tube actively getting ready (on cooldown) -> HOLD
	_reset()
	ship.get_component(tubes[0])["cooldown"] = 3.0
	if _volley_ready():
		failures.append("B: a live tube on cooldown -> expected HOLD (wait for it)")

	# C) that cooling tube is also OUT OF AMMO -> excluded, do not wait -> READY
	_reset()
	ship.get_component(tubes[0])["cooldown"] = 3.0
	ship.get_component(tubes[0])["ammo"] = 0
	if not _volley_ready():
		failures.append("C: empty tube must not block the volley -> expected READY")

	# D) that cooling tube is also DAMAGED -> excluded -> READY
	_reset()
	ship.get_component(tubes[0])["cooldown"] = 3.0
	ship.get_component(tubes[0])["health"] = 0.0
	if not _volley_ready():
		failures.append("D: damaged tube must not block the volley -> expected READY")

	# E) that cooling tube is also DISABLED (powered off) -> excluded -> READY
	_reset()
	ship.get_component(tubes[0])["cooldown"] = 3.0
	ship.get_component(tubes[0])["powered_on"] = false
	if not _volley_ready():
		failures.append("E: disabled tube must not block the volley -> expected READY")

	# F) the whole battery just fired (all on cooldown) -> HOLD until they recover together
	_reset()
	for tid in tubes:
		ship.get_component(tid)["cooldown"] = 5.0
	if _volley_ready():
		failures.append("F: entire battery cooling -> expected HOLD")

	# G) no live tubes at all (all empty) -> nothing to volley -> not ready
	_reset()
	for tid in tubes:
		ship.get_component(tid)["ammo"] = 0
	if _volley_ready():
		failures.append("G: no live tubes -> expected NOT ready (nothing to volley)")

	ship.queue_free()

	if failures.is_empty():
		print("Volley metering OK: holds for cooling tubes, ignores damaged/empty/disabled.")
		print(">>> [TEST PASSED] test_volley_metering <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_volley_metering <<<")
		get_tree().quit(1)

func _volley_ready() -> bool:
	return ship.is_group_volley_ready("port", "missile")

func _reset() -> void:
	for tid in tubes:
		var w = ship.get_component(tid)
		w["cooldown"] = 0.0
		w["ammo"] = 5
		w["health"] = w["max_health"]
		w["powered_on"] = true
