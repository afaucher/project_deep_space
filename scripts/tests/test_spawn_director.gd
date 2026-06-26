extends Node

# M10: unit tests for the pure ShipCatalog.iff_for() team-mapping helper.
# Referenced via preload const, never the bare global name -- see the
# class-cache note in m10_sandbox_spawn_design.md / ship_catalog.gd.
const ShipCatalog = preload("res://scripts/ship_catalog.gd")

func setup(_main) -> void:
	print("Test test_spawn_director initialized.")
	var failures: Array = []

	# FRIENDLY returns (a duplicate of) the player's own tags.
	var player_tags = ["TEAM_PLAYER", "SOME_OTHER_TAG"]
	var friendly_tags = ShipCatalog.iff_for(ShipCatalog.Team.FRIENDLY, 901, player_tags)
	if friendly_tags != player_tags:
		failures.append("FRIENDLY tags %s != player tags %s" % [friendly_tags, player_tags])
	# Must be a duplicate, not the same Array instance -- mutating one must not
	# mutate the other.
	if friendly_tags == player_tags:
		friendly_tags.append("MUTATED")
		if player_tags.has("MUTATED"):
			failures.append("FRIENDLY iff_for() returned a reference to player_tags instead of a duplicate")
		player_tags.erase("MUTATED")

	# ENEMY returns a shared, fixed tag regardless of owner_id.
	var enemy_tags_a = ShipCatalog.iff_for(ShipCatalog.Team.ENEMY, 902, player_tags)
	var enemy_tags_b = ShipCatalog.iff_for(ShipCatalog.Team.ENEMY, 903, player_tags)
	if enemy_tags_a != ["TEAM_ENEMY"]:
		failures.append("ENEMY tags %s != [\"TEAM_ENEMY\"]" % [enemy_tags_a])
	if enemy_tags_a != enemy_tags_b:
		failures.append("ENEMY tags differ between two owner_ids (%s vs %s) -- enemies must share a team tag" % [enemy_tags_a, enemy_tags_b])

	# PIRATE returns a tag unique per owner_id.
	var pirate_tags_904 = ShipCatalog.iff_for(ShipCatalog.Team.PIRATE, 904, player_tags)
	var pirate_tags_905 = ShipCatalog.iff_for(ShipCatalog.Team.PIRATE, 905, player_tags)
	if pirate_tags_904 == pirate_tags_905:
		failures.append("PIRATE tags identical for two different owner_ids (904: %s, 905: %s) -- pirates must NOT share a tag" % [pirate_tags_904, pirate_tags_905])

	# A pirate tag must not be shared with the player or with enemies (true FFA).
	for t in pirate_tags_904:
		if t in player_tags:
			failures.append("PIRATE tag %s overlaps player tags %s" % [t, player_tags])
		if t in enemy_tags_a:
			failures.append("PIRATE tag %s overlaps ENEMY tags %s" % [t, enemy_tags_a])

	# Re-spawning the same owner_id deterministically reproduces the same tag
	# (sanity on the formula itself, not a uniqueness claim).
	var pirate_tags_904_again = ShipCatalog.iff_for(ShipCatalog.Team.PIRATE, 904, player_tags)
	if pirate_tags_904 != pirate_tags_904_again:
		failures.append("PIRATE tag not deterministic for the same owner_id (%s vs %s)" % [pirate_tags_904, pirate_tags_904_again])

	if failures.is_empty():
		print("All ShipCatalog.iff_for() assertions passed!")
		print(">>> [TEST PASSED] test_spawn_director <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_spawn_director <<<")
		get_tree().quit(1)
