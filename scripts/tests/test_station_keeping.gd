extends Node

# Station Keeping acceptance. We spawn a MobileHome (Tier.LIGHT) and a SmallStation (Tier.STRUCTURE),
# and fire an asteroid at each. The MobileHome must dodge it and then return to its start position.
# The SmallStation must hold its position (not dodge), get hit, and then arrest its drift to return to its start position.
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_station_keeping

const MobileHome = preload("res://scripts/ships/mobile_home.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const MH_POS = Vector2(0, 0)
const SS_POS = Vector2(0, 15000)

var main_node: Node = null
var failures: Array = []
var finished: bool = false
var t: float = 0.0

var mh = null
var ss = null
var rock1 = null
var rock2 = null

var mh_min_rock_dist: float = INF
var ss_min_rock_dist: float = INF

const TIMEOUT = 120.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Station Keeping Tests")

	# Mobile Home (Tier.LIGHT, will dodge)
	mh = MobileHome.new()
	mh.name = "Hermit"
	mh.position = MH_POS
	main_node.add_child(mh)
	mh.add_child(AITreeFactory.build_station())

	# Small Station (Tier.STRUCTURE, will NOT dodge)
	ss = SmallStation.new()
	ss.name = "Outpost"
	ss.position = SS_POS
	for c in ss.ship_components:
		c["density"] = 5000.0
	main_node.add_child(ss)
	ss.add_child(AITreeFactory.build_station())

	# Fire rock at Mobile Home
	rock1 = Asteroid.new()
	rock1.name = "Rock1"
	rock1.position = MH_POS + Vector2(6000, 0) # 6km out
	main_node.add_child(rock1)
	rock1.linear_velocity = Vector2(-500, 0) # Direct hit

	# Fire rock at Small Station
	rock2 = Asteroid.new()
	rock2.name = "Rock2"
	rock2.position = SS_POS + Vector2(6000, 0) # 6km out
	main_node.add_child(rock2)
	rock2.linear_velocity = Vector2(-500, 0) # Direct hit

func _physics_process(delta: float) -> void:
	if finished or mh == null or ss == null:
		return
		
	t += delta
	
	var d1 = mh.position.distance_to(rock1.position)
	if d1 < mh_min_rock_dist:
		mh_min_rock_dist = d1
		
	var d2 = ss.position.distance_to(rock2.position)
	if d2 < ss_min_rock_dist:
		ss_min_rock_dist = d2

	# Evaluate when time runs out, or when ships have successfully returned after rocks pass
	if rock1.position.x < -3000 and rock2.position.x < -3000:
		if mh.position.distance_to(MH_POS) < 100.0 and ss.position.distance_to(SS_POS) < 300.0:
			_evaluate()
	if t > TIMEOUT:
		_evaluate()

func _evaluate() -> void:
	if finished:
		return
	finished = true
	
	var collide_mh = mh.get_bounding_radius() + rock1.get_bounding_radius()
	var collide_ss = ss.get_bounding_radius() + rock2.get_bounding_radius()
	
	# Mobile Home should dodge and then return to origin
	_assert(mh_min_rock_dist > collide_mh + 10.0, "MobileHome should have dodged the asteroid (min dist %.0f, contact %.0f)" % [mh_min_rock_dist, collide_mh])
	_assert(mh.position.distance_to(MH_POS) < 100.0, "MobileHome should have returned to station (dist %.0f)" % mh.position.distance_to(MH_POS))
	
	# Small Station should take the hit, but return to origin
	_assert(ss_min_rock_dist <= collide_ss + 1.0, "SmallStation should NOT dodge and must take the hit (min dist %.0f, contact %.0f)" % [ss_min_rock_dist, collide_ss])
	_assert(ss.position.distance_to(SS_POS) < 300.0, "SmallStation should have returned to station (dist %.0f)" % ss.position.distance_to(SS_POS))

	if failures.is_empty():
		print("Station Keeping: MobileHome dodged (cleared by %.0f), SmallStation held ground (contact at %.0f). Both returned to station." % [mh_min_rock_dist, ss_min_rock_dist])
		print(">>> [TEST PASSED] test_station_keeping <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_station_keeping <<<")
		get_tree().quit(1)
