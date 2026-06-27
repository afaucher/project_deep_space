extends Node

# Does the classifier actually handle the M9c ship types? test_classifiers only feeds
# hand-crafted signatures; this spawns every real catalog ship, lets its heat/EM settle,
# and asserts it classifies as a vessel (cross_section >= the ordnance threshold AND it
# reads as UNIDENTIFIED VESSEL to a non-friendly observer). A small hull whose AABB
# min-dimension falls under 10 would otherwise be misread as INCOMING ORDNANCE.
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const Ship = preload("res://scripts/ships/ship.gd")

var entries: Array = []
var frames := 0

func setup(main) -> void:
	print("Test test_classify_ships initialized.")
	var i := 0
	for entry in ShipCatalog.SPAWNABLE:
		var s = entry["script"].new()
		s.name = "CS_" + str(i)
		s.owner_id = 100 + i
		s.iff_tags = ["TEAM_ENEMY"]
		s.position = Vector2(i * 6000, 0)
		main.add_child(s)
		entries.append({"name": entry["name"], "ship": s})
		i += 1

func _physics_process(_delta: float) -> void:
	frames += 1
	if frames < 40:   # let the heat/EM loop settle
		return

	var failures: Array = []
	for e in entries:
		var s = e["ship"]
		var sig = s.get_signature()
		var cs = sig.get("cross_section", 0.0)
		var cls = Ship.classify_contact(sig, ["TEAM_PLAYER"])
		print("%-20s cs=%6.1f heat=%6.1f em=%6.1f den=%6.1f -> %s" % [
			e["name"], cs, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("density", 0.0), cls])
		if cs < Ship.ORDNANCE_CS_THRESHOLD:
			failures.append("%s cross_section %.1f < %.1f -- would read as ordnance, not a vessel" % [e["name"], cs, Ship.ORDNANCE_CS_THRESHOLD])
		if cls != "UNIDENTIFIED VESSEL":
			failures.append("%s classified '%s', expected UNIDENTIFIED VESSEL" % [e["name"], cls])

	if failures.is_empty():
		print(">>> [TEST PASSED] test_classify_ships <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_classify_ships <<<")
		get_tree().quit(1)
