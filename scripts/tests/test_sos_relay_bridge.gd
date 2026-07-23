extends Node

# M52 -- the key relay test (implementation_plans/m52_sos_as_contact.md's
# "The key test" section): a chain of beacons ("bridge"), each within
# comms-link range of its immediate neighbor, spanning a distance well
# beyond any single beacon's own SOS/comms range. set_sos_active(true, ...)
# fired from a ship near the MIDDLE of the chain. A patrol-equivalent ship
# at the FAR end (outside the sender's own direct SOS/comms range) ends up
# with a "DISTRESS CALL" entry in its own active_contacts for the sender via
# the EXISTING datalink relay alone -- NO relay-specific code was written to
# make this pass. SOS becoming a normal active_contacts entry is the whole
# point: it rides the relay for free the instant it's a normal dictionary
# in active_contacts (ship.gd's peer-scan loop already relays active_
# contacts wholesale, freshest-wins, multi-hop, LOS+IFF gated).
#
# Chain layout (all same IFF tag, straight line, clear LOS):
#   Sender (0,0) --20000-- Beacon1 (20000,0) --22000-- Beacon2 (42000,0)
#     --22000-- Patrol (64000,0)
# Sender-Beacon1 = 20000, within Hail.SOS_BATTERY_RANGE/comms range (30000)
# -- Beacon1 hears the SOS DIRECTLY. Beacon1-Beacon2 and Beacon2-Patrol are
# each 22000 (within comms range 30000, so each relay LINK holds), but
# Sender-Beacon2 (42000) and Sender-Patrol (64000) are both well beyond
# 30000 -- neither could ever hear the SOS directly. Every ship but the
# sender has its sensors stripped (test_comms_relay.gd's existing pattern),
# and Beacon2/Patrol sit beyond even a Frigate's 40000-unit active sensor
# range from the sender regardless -- so nothing observed here can be
# explained by real detection, only the SOS hail + the existing relay loop.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_sos_relay_bridge

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const SOSResponseLeaf = preload("res://scripts/ai/leaves/sos_response_leaf.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, pos: Vector2, strip_sensors: bool = true) -> Node:
	var s = Frigate.new()
	s.name = ship_name
	s.owner_id = spawned.size() + 1
	s.iff_tags = ["TEAM_BRIDGE"]
	s.position = pos
	if strip_sensors:
		s.ship_components = s.ship_components.filter(func(c): return c["type"] != "sensors")
	main_node.add_child(s)
	spawned.append(s)
	return s

func setup(main) -> void:
	main_node = main
	print("=== test_sos_relay_bridge: SOS reaches a far patrol via the existing datalink relay alone ===")

	var sender = _make_ship("Sender", Vector2(0, 0), false) # keeps its own sensors -- irrelevant, it's the emitter
	var beacon1 = _make_ship("Beacon1", Vector2(20000, 0))
	var beacon2 = _make_ship("Beacon2", Vector2(42000, 0))
	var patrol = _make_ship("Patrol", Vector2(64000, 0))

	var sender_trk: String = "TRK-%03d" % (abs(sender.get_instance_id()) % 1000)

	_assert(sender.position.distance_to(beacon2.position) > Hail.SOS_BATTERY_RANGE,
		"setup: sender-to-beacon2 distance exceeds the SOS battery floor -- direct hearing is impossible")
	_assert(sender.position.distance_to(patrol.position) > Hail.SOS_BATTERY_RANGE,
		"setup: sender-to-patrol distance exceeds the SOS battery floor -- direct hearing is impossible")

	sender.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)

	var frame := 0
	var beacon1_hop := -1
	var beacon2_hop := -1
	var patrol_hop := -1
	while frame < 600: # up to 10s -- generous margin for a 3-hop relay chain
		await main_node.get_tree().physics_frame
		frame += 1
		if beacon1_hop == -1 and beacon1.active_contacts.has(sender_trk):
			beacon1_hop = frame
		if beacon2_hop == -1 and beacon2.active_contacts.has(sender_trk):
			beacon2_hop = frame
		if patrol_hop == -1 and patrol.active_contacts.has(sender_trk):
			patrol_hop = frame
		if patrol_hop != -1:
			break

	_assert(beacon1_hop != -1, "Beacon1 (direct comms range of the sender) heard the SOS")
	_assert(beacon2_hop != -1, "Beacon2 (relay hop 1, beyond the sender's own direct range) received the DISTRESS CALL contact via relay")
	_assert(patrol_hop != -1, "Patrol (relay hop 2, far end of the bridge) received the DISTRESS CALL contact via relay")

	print("  hop timing (physics frames since SOS activation): Beacon1=%d, Beacon2=%d, Patrol=%d" % [beacon1_hop, beacon2_hop, patrol_hop])

	if beacon1_hop != -1:
		_assert(beacon1.active_contacts[sender_trk].get("classification", "") == "DISTRESS CALL",
			"Beacon1's entry is classified DISTRESS CALL")
	if beacon2_hop != -1:
		_assert(beacon2.active_contacts[sender_trk].get("classification", "") == "DISTRESS CALL",
			"Beacon2's relayed entry is classified DISTRESS CALL")
	if patrol_hop != -1:
		var pc: Dictionary = patrol.active_contacts[sender_trk]
		_assert(pc.get("classification", "") == "DISTRESS CALL", "Patrol's relayed entry is classified DISTRESS CALL")
		_assert(pc.get("sos", false), "Patrol's relayed entry carries the sos attribute")
		_assert(pc.get("pos", Vector2.ZERO).distance_to(sender.position) < 1000.0, "Patrol's relayed position is close to the sender's real position")
	if beacon1_hop != -1 and beacon2_hop != -1 and patrol_hop != -1:
		_assert(beacon2_hop >= beacon1_hop and patrol_hop >= beacon2_hop,
			"hop ordering is monotonic (Beacon1 no later than Beacon2 no later than Patrol) -- genuine multi-hop propagation, not a single lucky simultaneous broadcast")

	# Now prove SOSResponseLeaf actually breaks off and closes on it -- reusing
	# the SAME leaf real patrol ships use, no relay-specific test scaffolding.
	if patrol_hop != -1:
		var leaf := SOSResponseLeaf.new()
		var bb := Blackboard.new()
		bb.blackboard = {}
		var result: int = leaf.tick(patrol, bb)
		_assert(result == leaf.SUCCESS, "SOSResponseLeaf claims the tick and starts closing on the relayed DISTRESS CALL contact")
		_assert(bb.get_value("sos_responding_to", "") == sender_trk, "SOSResponseLeaf committed to the sender's track, learned purely via relay")

	_free_all()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_sos_relay_bridge <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_sos_relay_bridge <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
