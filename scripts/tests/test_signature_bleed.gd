extends Node

# Signature-bleed regression.
#
# When a hot enemy and a cold asteroid sit at the same bearing from an observer
# they fall into the same angular sensor bin. Under the BLEND merge the bin takes
# max heat/EM and sums cross-section, and the largest object owns the track id --
# so the enemy's hot signature bleeds onto the asteroid's track and it gets
# mislabelled as a vessel (and stays that way after they separate).
#
# This test forces DebugSettings.SignatureMerge.NEAREST, where only the nearest
# object's clean signature survives the bin and farther objects are shadowed. It
# asserts the (nearer) asteroid keeps its ASTEROID classification despite a hot
# enemy just behind it on nearly the same bearing.
#
# Geometry matters: the pair must sit BEYOND the frigate's fine sensors
# (omni_short_hi_res, range 5000) on a bearing the forward dir_high_res cone
# (+X +/- 15deg) does NOT cover, so the only sensor resolving them is the coarse
# omni_main (TAU / 36 bins = 10deg). Otherwise a fine sensor resolves them
# separately and cleans the asteroid before any bleed can be observed. We place
# the pair down the -Y bearing (~-85deg), well outside the forward cone, at
# ~7-8.5k range -- inside omni_main but outside omni_short_hi_res. The ~3deg
# angular offset keeps them in the same omni_main bin while leaving the enemy's
# line-of-sight clear of the asteroid (no occlusion drop).

const Ship = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var main_node: Node = null
var observer: Ship = null
var asteroid = null
var time_elapsed: float = 0.0
var done := false

func setup(main) -> void:
	main_node = main
	print("Test test_signature_bleed initialized.")

	# Force NEAREST-wins co-bearing merge for this scenario.
	DebugSettings.set_choice("signature_merge", DebugSettings.SignatureMerge.NEAREST)

	# Observer at origin, default heading (forward = +X).
	observer = Ship.new()
	observer.name = "Observer"
	observer.owner_id = 1
	observer.iff_tags = ["TEAM_A"]
	observer.position = Vector2.ZERO
	main_node.add_child(observer)

	# Asteroid NEARER, bearing ~-85deg (down -Y), beyond the fine sensors -> it
	# wins the shared coarse bin under NEAREST.
	asteroid = Asteroid.new()
	asteroid.name = "TestAsteroid"
	asteroid.position = Vector2.RIGHT.rotated(deg_to_rad(-85.0)) * 7000.0
	main_node.add_child(asteroid)

	# Hot enemy FARTHER, bearing ~-82deg -> shares the observer's coarse omni_main
	# bin with the asteroid, but offset enough that the asteroid doesn't occlude
	# its line of sight. Under BLEND its heat/EM bleeds onto the asteroid; under
	# NEAREST the asteroid (closer) wins and the enemy is shadowed.
	var enemy = Ship.new()
	enemy.name = "EnemyShip"
	enemy.owner_id = 2
	enemy.iff_tags = ["TEAM_B"]
	enemy.position = Vector2.RIGHT.rotated(deg_to_rad(-82.0)) * 8500.0
	main_node.add_child(enemy)

func _physics_process(delta: float) -> void:
	if not observer or done: return
	time_elapsed += delta
	# omni_main refreshes every 2.0s; give it a couple of sweeps.
	if time_elapsed <= 3.0:
		return
	done = true

	# The asteroid wins the bin under NEAREST, so its track is keyed off the
	# asteroid's own instance id.
	var trk = "TRK-%03d" % (abs(asteroid.get_instance_id()) % 1000)
	print("Scanning observer contacts for asteroid track ", trk, " ...")

	var found_asteroid := false
	for c_id in observer.active_contacts:
		var c = observer.active_contacts[c_id]
		var c_class = c.get("classification", "UNKNOWN")
		var sig = c.get("signature", {})
		print("  ", c_id, " -> ", c_class, " (CS ", sig.get("cross_section"), " Heat ", sig.get("heat"), " EM ", sig.get("em_noise"), ")")
		if c_id == trk:
			found_asteroid = true
			if c_class != "ASTEROID":
				printerr("[TEST FAILED] Asteroid track classified as ", c_class, " -- signature bleed leaked the enemy's signature onto the asteroid.")
				get_tree().quit(1)
				return

	if not found_asteroid:
		printerr("[TEST FAILED] Never sensed the asteroid (no ", trk, " contact). Check sensor coverage of the test bearing.")
		get_tree().quit(1)
		return

	print("[TEST PASSED] test_signature_bleed. Co-bearing hot enemy did not bleed onto the asteroid under NEAREST merge.")
	get_tree().quit(0)
