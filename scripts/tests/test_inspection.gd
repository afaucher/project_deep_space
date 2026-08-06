extends Node

# M55e MVP -- a patrol reads what is in a stopped hull's COMPUTERS, not what it
# is broadcasting, and seizes it if it is a pirate.
#
# WHY THIS EXISTS. `colors_chance` is 0.5, so at any moment HALF of all pirates
# are flying a clean cover identity. A cover-flying pirate has no warrant against
# the name it is claiming, so `Standing.force_authorized_by()` -- the seizure
# gate -- returns false and the hull sails away clean no matter how thoroughly it
# was caught. Interdiction could stop it and then had no grounds to do anything.
#
# `iff_tags` is ground truth; the transponder is the only thing that can lie.
# Reading the former instead of the latter is what an inspection IS, and it needs
# no new state anywhere.
#
# Covered:
#   A. a COVER-flying pirate is unmasked, and the unmasked flag is set
#   B. a COLOURS-flying pirate reads PIRATE but is NOT counted as unmasked --
#      it was never hidden, and crediting inspection with that catch would
#      inflate what inspection is worth
#   C. an honest civilian reads CLEAN and is RELEASED, not hulked -- the common
#      case, and the one that decides whether patrols read as police or as
#      harassment
#   D. seizure grounds are the UNION of warrant and inspection: a warranted hull
#      is still hulked even when inspection finds nothing (behaviour is a strict
#      superset of pre-M55e), and a clean hull with no warrant is released
#   E. a subject that bolts between the stop and the inspection ABORTS rather
#      than being inspected in absentia
#
# Steps are driven directly rather than flown, with a hand-built contact
# carrying `complied_stop` -- the same state DEMAND_STOP leaves behind. What is
# under test is the VERDICT and the seizure gate; InterdictLeaf's own job
# assembly is exercised by test_patrol_interdiction.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_inspection

const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const EngagementProbe = preload("res://scripts/instrumentation/engagement_probe.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Ship = preload("res://scripts/ships/ship.gd")

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

# A patrol that can see `victim` and reads it as complied. `complied_stop` is
# what DEMAND_STOP leaves on the issuer's own fused contact, and both INSPECT and
# HULK_PRIZE gate on it.
func _make_patrol_seeing(victim, complied: bool) -> Node:
	var patrol = Frigate.new()
	patrol.name = "InspectPatrol"
	patrol.owner_id = 1
	patrol.iff_tags = ["TEAM_PLAYER"]
	main_node.add_child(patrol)
	patrol.active_contacts[Ship.track_id(victim.get_instance_id())] = {
		"instance_id": victim.get_instance_id(),
		"pos": victim.position,
		"vel": Vector2.ZERO,
		"complied_stop": complied,
	}
	return patrol

# `broadcast_flag` is what the hull's transponder DECLARES, which is the only
# thing that can lie. FLAG_PIRATE = flying colours (hiding nothing); anything
# else = a cover identity.
func _make_hull(script, nm: String, tags: Array, broadcast_flag: String) -> Node:
	var s = script.new()
	s.name = nm
	s.owner_id = 900
	s.iff_tags = tags
	s.position = Vector2(1000, 0)
	main_node.add_child(s)
	for c in s.get_components_by_type("comms"):
		c["transponder_flag"] = broadcast_flag
	return s

func _job(force_authorized: bool, victim) -> Dictionary:
	return {
		"steps": [{"verb": "INSPECT", "on_abort": ""}, {"verb": "HULK_PRIZE", "on_abort": ""}],
		"current": 0,
		"victim_iid": victim.get_instance_id(),
		"force_authorized": force_authorized,
		"interdict_tier": Standing.HOSTILE,
	}

func setup(main) -> void:
	main_node = main
	print("Starting Inspection (M55e MVP) Tests")
	EngagementProbe.enabled = true
	EngagementProbe.reset()

	_test_cover_flying_pirate_is_unmasked()
	_test_colours_flying_pirate_is_not_credited_as_unmasked()
	_test_clean_civilian_is_released()
	_test_warrant_alone_still_seizes()
	_test_bolted_subject_aborts()
	_test_probe_counts()

	EngagementProbe.enabled = false
	_finalize()

# ---------------------------------------------------------------------------
# A. The whole point: a pirate hiding behind a clean name is found and seized.
# ---------------------------------------------------------------------------
func _test_cover_flying_pirate_is_unmasked() -> void:
	print("--- A: a cover-flying pirate is unmasked and seized ---")
	var pirate = _make_hull(ArmedPinnace, "CoverPirate", [Standing.TAG_PIRATE_GUILD], Standing.FLAG_DRIFT)
	var patrol = _make_patrol_seeing(pirate, true)
	# NO warrant -- that is the case that used to sail away clean.
	var job: Dictionary = _job(false, pirate)

	_assert(JobSteps.execute("INSPECT", patrol, job["steps"][0], job) == JobSteps.DONE, "A: INSPECT completes")
	_assert(job.get("inspect_verdict", "") == "PIRATE", "A: verdict is PIRATE -- read from iff_tags, not the transponder")
	_assert(JobSteps.execute("HULK_PRIZE", patrol, job["steps"][1], job) == JobSteps.DONE, "A: HULK_PRIZE completes")
	_assert(pirate.is_dead, "A: and the hull is SEIZED on inspection grounds alone, with no warrant")

	_free_if_valid(pirate)
	_free_if_valid(patrol)

# ---------------------------------------------------------------------------
# B. A pirate flying its colours was never hidden. It still reads PIRATE, but
# inspection did not DISCOVER anything -- it was already seizable on sight under
# an empty warrant (D37). Counting it as unmasked would inflate what inspection
# is worth, which is exactly how an instrument starts lying.
# ---------------------------------------------------------------------------
func _test_colours_flying_pirate_is_not_credited_as_unmasked() -> void:
	print("--- B: a colours-flying pirate is PIRATE but not 'unmasked' ---")
	var pirate = _make_hull(ArmedPinnace, "OpenPirate", [Standing.TAG_PIRATE_GUILD], Standing.FLAG_PIRATE)
	var patrol = _make_patrol_seeing(pirate, true)
	var job: Dictionary = _job(false, pirate)

	JobSteps.execute("INSPECT", patrol, job["steps"][0], job)
	_assert(job.get("inspect_verdict", "") == "PIRATE", "B: verdict is still PIRATE")
	_assert(job.get("inspect_unmasked", true) == false, "B: but NOT counted as unmasked -- nothing was hidden")

	_free_if_valid(pirate)
	_free_if_valid(patrol)

# ---------------------------------------------------------------------------
# C. THE COMMON CASE. Most hulls a patrol stops are innocent -- the 2026-08-05
# baseline had 12 of 32 interdictions at CAUTION tier, hulls that merely failed
# an ID challenge. A clean read must cost them nothing.
# ---------------------------------------------------------------------------
func _test_clean_civilian_is_released() -> void:
	print("--- C: an honest civilian is inspected and RELEASED ---")
	var civ = _make_hull(CargoShuttle, "HonestHauler", ["TEAM_CIV"], Standing.FLAG_DRIFT)
	var patrol = _make_patrol_seeing(civ, true)
	var job: Dictionary = _job(false, civ)

	JobSteps.execute("INSPECT", patrol, job["steps"][0], job)
	_assert(job.get("inspect_verdict", "") == "CLEAN", "C: verdict is CLEAN")
	_assert(JobSteps.execute("HULK_PRIZE", patrol, job["steps"][1], job) == JobSteps.DONE, "C: HULK_PRIZE completes without seizing")
	_assert(not civ.is_dead, "C: and the civilian is RELEASED, not hulked")

	_free_if_valid(civ)
	_free_if_valid(patrol)

# ---------------------------------------------------------------------------
# D. Grounds are the UNION. Behaviour must be a strict superset of pre-M55e:
# anything a warrant used to seize is still seized, even if inspection is silent.
# ---------------------------------------------------------------------------
func _test_warrant_alone_still_seizes() -> void:
	print("--- D: a warrant alone still seizes, with no pirate tag ---")
	var subject = _make_hull(CargoShuttle, "WarrantedHull", ["TEAM_CIV"], Standing.FLAG_DRIFT)
	var patrol = _make_patrol_seeing(subject, true)
	var job: Dictionary = _job(true, subject)   # force_authorized, as InterdictLeaf stamps it

	JobSteps.execute("INSPECT", patrol, job["steps"][0], job)
	_assert(job.get("inspect_verdict", "") == "CLEAN", "D: inspection finds nothing")
	JobSteps.execute("HULK_PRIZE", patrol, job["steps"][1], job)
	_assert(subject.is_dead, "D: seized anyway -- the warrant is independent grounds")

	_free_if_valid(subject)
	_free_if_valid(patrol)

# ---------------------------------------------------------------------------
# E. You cannot inspect the computers of a hull that is no longer alongside.
# ---------------------------------------------------------------------------
func _test_bolted_subject_aborts() -> void:
	print("--- E: a subject that bolted cannot be inspected ---")
	var pirate = _make_hull(ArmedPinnace, "BoltedPirate", [Standing.TAG_PIRATE_GUILD], Standing.FLAG_DRIFT)
	var patrol = _make_patrol_seeing(pirate, false)   # complied_stop cleared
	var job: Dictionary = _job(false, pirate)

	_assert(JobSteps.execute("INSPECT", patrol, job["steps"][0], job) == JobSteps.ABORT, "E: INSPECT aborts")
	_assert(not job.has("inspect_verdict"), "E: and stamps no verdict -- it was never read")
	_assert(not pirate.is_dead, "E: the hull is not seized in absentia")

	_free_if_valid(pirate)
	_free_if_valid(patrol)

# ---------------------------------------------------------------------------
# F. The probe separates clean from dirty. A single "inspection rate" would make
# a run of administrative stops read identically to enforcement.
# ---------------------------------------------------------------------------
func _test_probe_counts() -> void:
	print("--- F: the probe keeps clean and dirty separate ---")
	_assert(EngagementProbe.inspections == 4, "F: 4 inspections counted (A, B, C, D -- E aborted before reading)")
	_assert(EngagementProbe.inspect_pirate == 2, "F: 2 read PIRATE")
	_assert(EngagementProbe.inspect_clean == 2, "F: 2 read CLEAN")
	_assert(EngagementProbe.inspect_unmasked == 1, "F: exactly 1 was UNMASKED -- the cover-flyer, not the colours-flyer")
	_assert(abs(EngagementProbe.inspect_hit_rate() - 0.5) < 0.001, "F: hit rate 50%")

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_inspection <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_inspection <<<")
		get_tree().quit(1)
