extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const Missile = preload("res://scripts/ships/missile.gd")

var main_node: Node = null
var observer: Ship = null
var enemy: Ship = null
var time_elapsed: float = 0.0
var test_phase: int = 0
var phase_start_time: float = 0.0
var heat_before_hit: float = 0.0
var heat_after_hit: float = 0.0

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
	observer.iff_tags = ["TEAM_A"]
	observer.position = Vector2.ZERO
	main_node.add_child(observer)
	
	# 2. Friendly Vessel
	var friendly = Ship.new()
	friendly.name = "FriendlyShip"
	friendly.owner_id = 1
	friendly.iff_tags = ["TEAM_A"]
	friendly.position = Vector2(0, -1000)
	main_node.add_child(friendly)
	
	# 3. Enemy Vessel
	enemy = Ship.new()
	enemy.name = "EnemyShip"
	enemy.owner_id = 2
	enemy.iff_tags = ["TEAM_B"]
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
	f_missile.iff_tags = ["TEAM_A"]
	main_node.add_child(f_missile)
	
	# 7. Incoming Ordnance
	var e_missile = Missile.new()
	e_missile.name = "EnemyMissile"
	e_missile.setup(2, Vector2(1000, 1000), Vector2.ZERO, 0)
	e_missile.iff_tags = ["TEAM_B"]
	main_node.add_child(e_missile)

func _physics_process(delta: float) -> void:
	if not observer: return
	time_elapsed += delta
	
	if test_phase == 0:
		# Accumulate classifications ACROSS frames rather than snapshotting once.
		# INCOMING ORDNANCE is short-lived: the observer's PD cooks the enemy missile
		# within ~1-2s, and once its reactor is gone the hot corpse reads (correctly)
		# as WRECKAGE, not ordnance. A single 2s snapshot races that kill. OR-in every
		# class we ever see and pass as soon as all six have appeared at least once.
		for c_id in observer.active_contacts:
			var c = observer.active_contacts[c_id]
			var c_class = c.get("classification", "UNKNOWN")
			if expected_contacts.has(c_class):
				expected_contacts[c_class] = true

		var all_found = true
		for k in expected_contacts:
			if not expected_contacts[k]:
				all_found = false
				break

		# Give sensors a few seconds of sweeps; only fail if a class never appeared.
		if not all_found and time_elapsed < 4.0:
			return

		if not all_found:
			var missing = []
			for k in expected_contacts:
				if not expected_contacts[k]:
					missing.append(k)
			print("Checking observer's active contacts...")
			for c_id in observer.active_contacts:
				var c = observer.active_contacts[c_id]
				var sig = c.get("signature", {})
				print("Found contact: ", c_id, " classified as: ", c.get("classification", "UNKNOWN"), " (CS: ", sig.get("cross_section"), " Heat: ", sig.get("heat"), " EM: ", sig.get("em_noise"), " Owner: ", sig.get("owner_id"), " Density: ", sig.get("density"), ")")
			printerr("[TEST FAILED] Missing expected classifications: ", missing)
			get_tree().quit(1)
			return

		print("Classifications OK. Firing a laser hit at the enemy ship...")
		# heat is the ship-wide value get_signature() exposes externally as
		# "heat" -- the same value that feeds the sensed contact signature
		# and the targeting computer's history graph. A hit should spike it
		# immediately, then ordinary dissipation should bring it back down
		# over the next few seconds, matching M4's "visible, time-extended
		# signal change" bar without depending on sensor-fusion lag/timing.
		heat_before_hit = enemy.current_heat
		# Same known-good hit coordinates test_component_states.gd uses --
		# (-32, 0) relative to the ship lands inside engine_main's rect
		# (Rect2(-35,-10,5,20)), guaranteeing a non-zero damage_heat burst.
		enemy.take_damage(50.0, enemy.position + Vector2(-32, 0), Vector2(1, 0), "laser")
		heat_after_hit = enemy.current_heat

		if heat_after_hit <= heat_before_hit:
			printerr("[TEST FAILED] Hit didn't raise the enemy's heat signature. before=", heat_before_hit, " after=", heat_after_hit)
			get_tree().quit(1)
			return

		test_phase = 1
		phase_start_time = time_elapsed
		return

	if test_phase == 1:
		# Give dissipation (heat_dissipation_rate, gated by reactor power
		# ratio) several seconds to work the burst back down.
		if time_elapsed - phase_start_time > 5.0:
			var heat_after_decay = enemy.current_heat
			print("Heat before hit: ", heat_before_hit, " after hit: ", heat_after_hit, " after decay: ", heat_after_decay)
			if heat_after_decay < heat_after_hit:
				print("[TEST PASSED] test_classifiers_e2e. Weapon hit produced a visible, time-extended heat signature change.")
				get_tree().quit(0)
			else:
				printerr("[TEST FAILED] Heat signature did not decay after the hit. after_hit=", heat_after_hit, " after_decay=", heat_after_decay)
				get_tree().quit(1)
		return
