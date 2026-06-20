extends Node

const Ship = preload("res://scripts/ship.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const Missile = preload("res://scripts/missile.gd")

var main_node: Node = null
var observer: Ship = null
var time_elapsed: float = 0.0
var test_phase: int = 0

var expected_contacts = {
	"FRIENDLY VESSEL": false,
	"UNIDENTIFIED VESSEL": false,
	"FRIENDLY ORDNANCE": false,
	"INCOMING ORDNANCE": false,
	"WRECKAGE": false,
	"ASTEROID": false
}

func setup(main) -> void:
	main_node = main
	print("Test test_classifiers_e2e initialized.")
	
	# 1. Observer Ship
	observer = Ship.new()
	observer.name = "Observer"
	observer.owner_id = 1
	observer.position = Vector2.ZERO
	main_node.add_child(observer)
	
	# 2. Friendly Vessel
	var friendly = Ship.new()
	friendly.name = "FriendlyShip"
	friendly.owner_id = 1
	friendly.position = Vector2(0, -1000)
	main_node.add_child(friendly)
	
	# 3. Enemy Vessel
	var enemy = Ship.new()
	enemy.name = "EnemyShip"
	enemy.owner_id = 2
	enemy.position = Vector2(1000, 0)
	main_node.add_child(enemy)
	
	# 4. Wreckage (Ship with no reactor / hulked)
	var wreck = Ship.new()
	wreck.name = "Wreckage"
	wreck.owner_id = 3
	wreck.position = Vector2(0, 1000)
	wreck.hulk() # Shuts down power, leaving it cold
	main_node.add_child(wreck)
	
	# 5. Asteroid
	var asteroid = Asteroid.new()
	asteroid.name = "TestAsteroid"
	asteroid.position = Vector2(-1000, 0)
	main_node.add_child(asteroid)
	
	# 6. Friendly Ordnance
	var f_missile = Missile.new()
	f_missile.name = "FriendlyMissile"
	f_missile.setup(1, Vector2(-1000, -1000), Vector2.ZERO, 0)
	main_node.add_child(f_missile)
	
	# 7. Incoming Ordnance
	var e_missile = Missile.new()
	e_missile.name = "EnemyMissile"
	e_missile.setup(2, Vector2(1000, 1000), Vector2.ZERO, 0)
	main_node.add_child(e_missile)

func _physics_process(delta: float) -> void:
	if not observer: return
	time_elapsed += delta
	
	if test_phase == 0:
		# Wait 2 seconds for sensors to sweep and classify everything
		if time_elapsed > 2.0:
			test_phase = 1
			print("Checking observer's active contacts...")
			
			for c_id in observer.active_contacts:
				var c = observer.active_contacts[c_id]
				var sig = c.get("signature", {})
				var c_class = c.get("classification", "UNKNOWN")
				print("Found contact: ", c_id, " classified as: ", c_class, " (Pos: ", c.get("pos"), " CS: ", sig.get("cross_section"), " Heat: ", sig.get("heat"), " EM: ", sig.get("em_noise"), " Owner: ", sig.get("owner_id"), " Density: ", sig.get("density"), ")")
				if expected_contacts.has(c_class):
					expected_contacts[c_class] = true
					
			var all_found = true
			var missing = []
			for k in expected_contacts:
				if not expected_contacts[k]:
					all_found = false
					missing.append(k)
					
			if all_found:
				print("[TEST PASSED] test_classifiers_e2e. All expected classifications found in simulation.")
				get_tree().quit(0)
			else:
				printerr("[TEST FAILED] Missing expected classifications: ", missing)
				get_tree().quit(1)
