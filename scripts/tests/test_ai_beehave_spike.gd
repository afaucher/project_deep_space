extends Node

# M12b-spike: Beehave headless GO/NO-GO gate.
#
# Proves the vendored Beehave addon (a) compiles under the headless --run-test path --
# i.e. the global class cache resolves Beehave's cross-referenced class_names -- and
# (b) a BeehaveTree _ready()s and tick()s with no editor and no rendering, driving a
# real Ship through an ActionLeaf. If this passes, Beehave is viable for M12. If it
# cannot be made to pass, the fallback is a pure-GDScript selector behind the same leaf
# interface (the Ship capability layer from M12a is framework-agnostic either way).
#
# Scripts are referenced via preload const (not bare global names) per the project's
# class-cache convention -- but the addon's OWN internal class_name refs still require a
# regenerated cache, which is exactly what part (a) verifies.
const Frigate = preload("res://scripts/ships/frigate.gd")
const BeehaveTreeScript = preload("res://addons/beehave/nodes/beehave_tree.gd")
const SpikeLeaf = preload("res://scripts/ai/leaves/spike_set_heading_leaf.gd")

func setup(main) -> void:
	print("Test test_ai_beehave_spike initialized.")
	var failures: Array = []

	# A real ship in the scene tree, same as in-game.
	var ship = Frigate.new()
	ship.name = "SpikeShip"
	ship.owner_id = 1
	main.add_child(ship)
	var before = ship.target_heading

	# Build a minimal tree IN CODE: BeehaveTree -> SpikeLeaf. MANUAL process thread so
	# the tree never auto-ticks -- the test drives tick() deterministically.
	var tree = BeehaveTreeScript.new()
	tree.name = "SpikeTree"
	tree.process_thread = BeehaveTreeScript.ProcessThread.MANUAL
	tree.actor = ship

	var leaf = SpikeLeaf.new()
	leaf.name = "SpikeLeaf"
	tree.add_child(leaf)

	# Adding the tree to the scene runs BeehaveTree._ready(), which reaches the
	# BeehaveGlobalDebugger / BeehaveGlobalMetrics autoloads and BeehaveDebuggerMessages.
	# This is the real headless risk -- if that machinery is unhappy under --headless,
	# _ready() blows up right here.
	main.add_child(tree)

	var status = tree.tick()

	if status != BeehaveTreeScript.SUCCESS:
		failures.append("tree.tick() returned %s, expected SUCCESS (%d)" % [status, BeehaveTreeScript.SUCCESS])

	if not is_equal_approx(ship.target_heading, SpikeLeaf.TEST_HEADING):
		failures.append("leaf did not drive ship: target_heading=%s, expected %s (was %s before tick)" % [ship.target_heading, SpikeLeaf.TEST_HEADING, before])

	tree.queue_free()
	ship.queue_free()

	if failures.is_empty():
		print("Beehave headless spike OK: tree ticked and the leaf drove the ship via apply_control_input.")
		print(">>> [TEST PASSED] test_ai_beehave_spike <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_ai_beehave_spike <<<")
		get_tree().quit(1)
