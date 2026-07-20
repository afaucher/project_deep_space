extends Node

# M52b -- PortControl.request_warrant_list unit coverage (implementation_
# plans/m52b_warrants.md's "Station pull merges, doesn't subscribe" test
# item; design_ideas/warrants.md's "On-request pull" section). Pure-function
# style, no scene tree/physics needed -- request_warrant_list only touches
# station.warrants/ship.warrants dicts directly, same model as
# test_standing_rules.gd's pure-rules pass.

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const PortControl = preload("res://scripts/port/port_control.gd")

func setup(_main) -> void:
	print("Test test_warrant_pull initialized.")

	var passed = 0
	var failed = 0

	var station := Ship.new()
	var asker := Ship.new()

	var flagged_key: String = Standing.OFF_ARMED_ROBBERY + "|" + Standing.subject_key("Wanted One", {})
	var personal_key: String = Standing.OFF_OPERATOR_FLAGGED + "|" + Standing.subject_key("Someone Else", {})
	station.warrants = {
		flagged_key: Standing.make_warrant(Standing.OFF_ARMED_ROBBERY, {"claimed_name": "Wanted One"}, {"iid": station.get_instance_id(), "name": "Station"}, "SOVEREIGN_DRIFT", flagged_key, "took cargo"),
		# A personal-origin record somehow present on the station's own store
		# (its own witnessed-but-undeputized read) -- must NOT propagate even
		# on an explicit pull, same rule the live relay enforces.
		personal_key: Standing.make_warrant(Standing.OFF_OPERATOR_FLAGGED, {"claimed_name": "Someone Else"}, {"iid": station.get_instance_id(), "name": "Station"}, "", personal_key, "personal test"),
	}

	var result: Dictionary = PortControl.request_warrant_list(station, asker)

	if result.get("outcome", "") == "granted" and result.get("count", -1) == 1:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] request_warrant_list should report 1 merged record (the flagged one only), got ", result)

	if asker.warrants.has(flagged_key):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] the flagged station warrant should land in the asking ship's own store")

	if asker.warrants.get(flagged_key, {}).get("origin_flag", "") == "SOVEREIGN_DRIFT":
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] the pulled warrant should preserve the STATION's origin_flag, got ", asker.warrants.get(flagged_key, {}))

	if not asker.warrants.has(personal_key):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a personal-origin station record must not propagate even on an explicit pull")

	# One-shot, not a subscription: a warrant added to the station AFTER the
	# pull must NOT silently appear on the asker without a SECOND explicit
	# pull -- proves this doesn't quietly become a live link.
	var later_key: String = Standing.OFF_ARMED_THREAT + "|" + Standing.subject_key("Late Arrival", {})
	station.warrants[later_key] = Standing.make_warrant(Standing.OFF_ARMED_THREAT, {"claimed_name": "Late Arrival"}, {"iid": station.get_instance_id(), "name": "Station"}, "SOVEREIGN_DRIFT", later_key, "late test")
	if not asker.warrants.has(later_key):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a warrant added to the station AFTER the pull must not silently appear -- this should be one-shot, not a live subscription")

	var second_result: Dictionary = PortControl.request_warrant_list(station, asker)
	if asker.warrants.has(later_key) and second_result.get("count", -1) == 1:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a SECOND explicit pull should pick up the late-added record, got ", second_result, " asker.warrants=", asker.warrants)

	# A third pull with nothing new should report 0 merged (no-op, not an
	# error) -- confirms merge_warrant's tie-break keeps re-pulling cheap.
	var third_result: Dictionary = PortControl.request_warrant_list(station, asker)
	if third_result.get("outcome", "") == "granted" and third_result.get("count", -1) == 0:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a re-pull with nothing new should report 0 merged, got ", third_result)

	station.free()
	asker.free()

	if failed == 0:
		print(">>> [TEST PASSED] test_warrant_pull <<<")
		print("[TEST PASSED] test_warrant_pull. Passed ", passed, "/", passed + failed, " cases.")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_warrant_pull <<<")
		printerr("[TEST SUITE FAILED] ", failed, " of ", passed + failed, " checks failed.")
		get_tree().quit(1)
