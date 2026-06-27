extends Node

# M12c disengage trigger: a healthy ship engages a hostile; the same ship, once
# critically damaged, breaks off and flees (nose pointed AWAY from the threat) instead of
# trading blows. Drives the real tree deterministically (MANUAL thread) and reads the
# resulting helm heading.
const Frigate = preload("res://scripts/ships/frigate.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const BeehaveTreeScript = preload("res://addons/beehave/nodes/beehave_tree.gd")

func setup(main) -> void:
	print("Test test_ai_disengage initialized.")
	var failures: Array = []

	var ship = Frigate.new()
	ship.name = "DisengageShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	ship.rotation = 0.0
	main.add_child(ship)

	var tree = AITreeFactory.build_default()
	tree.process_thread = BeehaveTreeScript.ProcessThread.MANUAL
	ship.add_child(tree)

	# Hostile contact dead ahead (+X), 5 km.
	ship.active_contacts["TGT"] = {"pos": Vector2(5000, 0), "vel": Vector2.ZERO, "classification": "UNIDENTIFIED VESSEL"}

	# 1) Healthy: should NOT disengage -> engages, nose toward the +X threat (heading ~0).
	if ship.get_health_fraction() < 0.99:
		failures.append("pristine ship health fraction %.2f, expected ~1.0" % ship.get_health_fraction())
	tree.tick()
	if abs(wrapf(ship.target_heading - 0.0, -PI, PI)) > 0.4:
		failures.append("healthy ship heading %.2f, expected ~0 (engaging the +X threat)" % ship.target_heading)

	# 2) Cripple the ship below the disengage threshold.
	for c in ship.ship_components:
		c["health"] = c["max_health"] * 0.1
	if ship.get_health_fraction() >= 0.3:
		failures.append("crippled ship health fraction %.2f, expected < 0.3" % ship.get_health_fraction())
	tree.tick()
	# Fleeing a +X threat means nose to -X, heading ~ PI (== -PI after wrap).
	if abs(wrapf(ship.target_heading - PI, -PI, PI)) > 0.4:
		failures.append("crippled ship heading %.2f, expected ~PI (fleeing away from +X threat)" % ship.target_heading)

	ship.queue_free()

	if failures.is_empty():
		print("Disengage OK: healthy ship engages, crippled ship flees away from the threat.")
		print(">>> [TEST PASSED] test_ai_disengage <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_ai_disengage <<<")
		get_tree().quit(1)
