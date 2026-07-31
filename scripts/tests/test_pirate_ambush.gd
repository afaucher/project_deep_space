extends Node

# M50 -- e2e mini cluster: the full piracy loop against live traffic
# (implementation_plans/m50_pirate_tree_design.md "Tests"). A pirate
# (ArmedPinnace) arrives under a cover identity reading NEUTRAL to a watcher,
# goes dark, lurks, selects a lone cargo shuttle crossing the lane, demands a
# stop (colors shown), the victim complies (M49), the pirate takes it
# (loot_takes==1, victim.looted, hold lapses once the pirate stops refreshing
# -- M52d's heartbeat model, no RELEASE verb), exfils dark, relights under a
# NEW name, and reads NEUTRAL again to a fresh observer. Full arc,
# built entirely from the canonical hunt job assembled here (the guild
# director assembles this same shape in M51 -- test-issued in M50 per the
# plan).
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames (Godot 2D physics/timing isn't bit-deterministic
# run-to-run, CLAUDE.md). RNG is seeded by the test runner (main.gd), so this
# is repeatable run to run despite the sensor-noise jitter every tick adds.

const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

# Note: the watcher (planted 6000 out from the lane specifically so it can
# read the pirate's cover identity early, per Phase 1) is NOT a legitimate
# witness to the actual robbery -- it never gets close to the intercept/
# demand/take area (>=6000 away throughout). Keep this comfortably under
# that separation so the watcher's own presence never falsely trips the
# abort during the hunt.
const R_THIRD_PARTY := 3000.0
# Mirrors the canonical hunt's AWAIT{track_quiet} clear_range (pirate_guild.gd).
# The exfil geometry below has to keep the victim outside this, or the pirate
# can never go quiet and RELIGHT is skipped.
const TRACK_QUIET_CLEAR_RANGE := 5000.0

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(script, ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _find_contact(observer, target: Node) -> Dictionary:
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return {}
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func _build_hunt_job(staging_pos: Vector2, lane_pos: Vector2, exfil_pos: Vector2, exit_pos: Vector2, relight_name: String) -> Dictionary:
	return {
		"steps": [
			{"verb": "GO_TO", "pos": staging_pos},
			{"verb": "GO_DARK"},
			# NOTE (deviation from the doc's literal per-step table): third_
			# party_in_range is NOT attached here. Before a victim is chosen,
			# job["victim_iid"] is -1, so the check's own "neither the victim
			# nor FRIENDLY" exclusion can never match the very candidate
			# SELECT_VICTIM is about to pick -- the first fresh UNIDENTIFIED
			# VESSEL contact (the intended prey itself) would always read as
			# a false "third party" and abort the hunt before it ever
			# selects anyone. SELECT_VICTIM's own ALONE check already covers
			# "is there a witness near this candidate"; the shared abort_
			# when conditions apply cleanly once a victim actually exists
			# (INTERCEPT onward, below).
			{"verb": "SELECT_VICTIM", "label": "hunt", "lane_pos": lane_pos, "lurk_radius": 2500.0, "witness_range": 3000.0},
			{"verb": "INTERCEPT", "on_abort": "hunt",
				"abort_when": [{"cond": "victim_lost", "on_abort": "hunt"}, {"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "TAKE_ALONGSIDE", "hold_time": 8.0, "range": 600.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": R_THIRD_PARTY, "on_abort": "exfil"}]},
			# DEMAND_STOP's show_colors re-lit the transponder to hoist pirate
			# colors -- the canonical job's "GO_TO exfil point (DARK)" implies
			# darkness, but re-achieving it after showing colors needs its own
			# GO_DARK; the doc's shorthand table doesn't spell out this second
			# GO_DARK explicitly, but it's required for AWAIT{track_quiet}'s
			# dark-transponder precondition to ever hold.
			{"verb": "GO_DARK"},
			{"verb": "GO_TO", "label": "exfil", "pos": exfil_pos},
			# on_abort MATTERS -- see pirate_guild.gd's copy of this step and
			# CLAUDE.md's "job step that ABORTs with no on_abort label reports
			# SUCCESS". Production was fixed for this in July; this test's own
			# copy of the job was not, and it silently drifted apart. It cost a
			# confusing failure on 2026-07-27: the timeout finally became
			# reachable, the unlabelled abort set current = steps.size(), and the
			# runner logged "job complete" for a job that had skipped RELIGHT and
			# EXIT_AT entirely.
			#
			# 180s to match production, raised from 60 for the same reason: a
			# post-take pirate is hot, the thermal self-throttle eases it off, and
			# the exfil now measures ~113s. The AWAIT completes NATURALLY at this
			# budget rather than aborting.
			{"verb": "AWAIT", "condition": "track_quiet", "seconds": 3.0, "clear_range": 5000.0, "timeout": 180.0, "on_abort": "exit"},
			{"verb": "RELIGHT", "name": relight_name, "flag": Standing.FLAG_CIVILIAN},
			{"verb": "EXIT_AT", "pos": exit_pos},
		],
		"current": 0,
	}

func setup(main) -> void:
	main_node = main
	print("Starting Pirate Ambush (M50) Tests")

	# Narrate the otherwise-invisible hunt in this test's log (the job_log
	# lines double as living documentation of the ambush arc -- and as
	# coverage that the logging paths themselves don't crash).
	DebugSettings.set_choice("job_log", DebugSettings.JobLog.ON)

	var staging_pos := Vector2(5000, 0)
	var lane_pos := staging_pos
	# EXFIL OFF THE LANE, NOT ALONG IT. AWAIT{track_quiet} (job_steps.gd
	# _track_quiet_holds) requires no fresh contact within clear_range (5000) --
	# and it does NOT filter by classification, so the pirate's own victim
	# counts. These used to sit at x=5000, i.e. on the lane the victim flees
	# down: the victim spawns at y=-3000, ran to ~(5650, -9730) before the
	# robbery, and the old exfil at (5000, -12000) was ~2270 away from it.
	# track_quiet then could never clear, the AWAIT burned its full 180s timeout
	# and aborted to "exit", skipping RELIGHT entirely -- which surfaced two
	# phases later as "the observer reads CAUTION" and looked like a
	# classification bug.
	#
	# Whether that happened came down to how far the victim got before being
	# stopped, which is exactly the kind of margin that lands differently on
	# different machines (it reportedly passed reliably on Windows). Offsetting
	# LATERALLY makes the separation independent of how far down the lane the
	# chase ran: the victim tracks the lane at x~5000, so ~9000 of lateral
	# clearance holds wherever on it the robbery ends up.
	var exfil_pos := Vector2(14000, -12000)
	var exit_pos := Vector2(17000, -12000)

	var pirate = _make_ship(ArmedPinnace, "Pirate", 700, Vector2.ZERO, ["PIRATE_700"])
	# Cover identity on spawn (the spawner's job in M50; the guild director's
	# job in M51) -- a claimed civilian name + flag, reading NEUTRAL to
	# anyone whose sensors correlate it before it goes dark.
	pirate.set_transponder_custom_name("Fair Trader")
	pirate.set_transponder_flag(Standing.FLAG_CIVILIAN)
	pirate.set_transponder_active(true)
	pirate.add_child(AITreeFactory.build_pirate())

	var watcher = _make_ship(Frigate, "Watcher", 701, Vector2(5000, 6000), ["TEAM_WATCHER"])
	var victim = _make_ship(CargoShuttle, "Victim", 702, Vector2(5000, -3000), ["TEAM_VICTIM"])
	victim.add_child(AITreeFactory.build_cargo())

	var job := _build_hunt_job(staging_pos, lane_pos, exfil_pos, exit_pos, "Silent Drifter")
	pirate.assign_job(job)

	var idx_hunt := 2  # SELECT_VICTIM's index in the steps array above
	var idx_exit := 10 # EXIT_AT's index

	# --- Phase 1: cover-flag NEUTRAL read, then dark, then the hunt begins. ---
	print("\n--- Phase 1: cover-flag NEUTRAL read -> GO_DARK -> hunt begins ---")
	var saw_cover_neutral := false
	var hunt_started := false
	for i in range(1800): # up to 30s
		await main_node.get_tree().physics_frame
		if not saw_cover_neutral:
			var c: Dictionary = _find_contact(watcher, pirate)
			if c.get("standing", "") == Standing.NEUTRAL:
				saw_cover_neutral = true
		if job.get("current", -1) >= idx_hunt:
			hunt_started = true
			break
	_assert(saw_cover_neutral, "watcher read the pirate's cover identity as NEUTRAL before it went dark")
	_assert(hunt_started, "job reached the SELECT_VICTIM ('hunt') step (current=%d)" % job.get("current", -1))

	# --- Phase 2: select -> intercept -> demand -> victim complies. ---
	print("\n--- Phase 2: select victim -> intercept -> demand -> victim complies ---")
	var complied := false
	for i in range(1800): # up to 30s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate) or not is_instance_valid(victim):
			break
		if victim.compelled_stop.get("issuer_iid", -1) == pirate.get_instance_id():
			complied = true
			break
	_assert(job.get("victim_iid", -1) == victim.get_instance_id(), "SELECT_VICTIM picked the (only) cargo shuttle in the lane")
	_assert(complied, "the victim complied with the pirate's DEMAND(STOP) (compelled_stop=%s)" % str(victim.compelled_stop))

	# --- Phase 3: the take -- loot_takes, looted, hold lapses. ---
	print("\n--- Phase 3: TAKE_ALONGSIDE -- loot_takes, victim.looted, hold lapses ---")
	var taken := false
	for i in range(3600): # up to 60s -- TAKE_ALONGSIDE closes at a deliberately gentle pace, then holds 8s
		await main_node.get_tree().physics_frame
		if not is_instance_valid(pirate):
			break
		if pirate.loot_takes >= 1:
			taken = true
			break
	_assert(taken, "pirate.loot_takes incremented (loot_takes=%d)" % (pirate.loot_takes if is_instance_valid(pirate) else -1))
	_assert(is_instance_valid(victim) and victim.looted, "victim.looted was stamped by the take")

	# M52d -- no RELEASE verb: the pirate's TAKE_ALONGSIDE step (which was
	# refreshing the hold) is done and the job moves on to exfil, so the
	# refreshes simply stop. The victim's compelled_stop clears once its own
	# heartbeat timeout (Ship.HAIL_HEARTBEAT_TIMEOUT, 6s) elapses -- generous
	# margin past that, not "promptly".
	var released := false
	for i in range(600): # up to 10s -- comfortably past the 6s heartbeat timeout
		await main_node.get_tree().physics_frame
		if not is_instance_valid(victim):
			break
		if victim.compelled_stop.is_empty():
			released = true
			break
	_assert(released, "victim's hold lapsed once the pirate stopped refreshing it (heartbeat timeout, no RELEASE)")

	# --- Phase 4: exfil dark, launder wait, relight under a NEW name. -------
	print("\n--- Phase 4: exfil dark -> AWAIT track_quiet -> RELIGHT (new name) ---")

	# Guard the geometry invariant the rest of this phase depends on, at the
	# point where the chase has actually finished and the victim's final
	# position is known. If the exfil is not clear of the victim, track_quiet
	# can never go true, the AWAIT burns its whole timeout and skips RELIGHT --
	# and every downstream symptom shows up somewhere else entirely. Assert it
	# here so the test says so directly instead of leaving it to be inferred.
	var victim_to_exfil: float = exfil_pos.distance_to(victim.position) if is_instance_valid(victim) else INF
	_assert(victim_to_exfil > TRACK_QUIET_CLEAR_RANGE,
		"the exfil point is clear of the robbed victim (%.0f u, needs > %.0f) -- otherwise AWAIT{track_quiet} can never succeed" % [
			victim_to_exfil, TRACK_QUIET_CLEAR_RANGE])
	var relit := false
	# 200s, raised from 60. Measured, not guessed: the exfil completes at ~113s
	# now that a post-take pirate is thermally throttled (it just ran an
	# intercept and a take, so it is hot exactly when it wants to leave). Margin
	# per CLAUDE.md -- physics is not bit-deterministic run to run, so this is a
	# budget with headroom, not a figure fitted to one observation.
	var exfil_frames := 0
	for i in range(12000): # up to 200s -- exfil leg + the 3s track_quiet wait
		await main_node.get_tree().physics_frame
		exfil_frames = i + 1
		if not is_instance_valid(pirate):
			break
		# Record what is actually blocking track_quiet, so a future failure of
		# this leg names the ship responsible instead of leaving it to be
		# reconstructed from an aborted job two phases later.
		if i % 1800 == 0:
			var _blockers: Array = []
			for c_id in pirate.active_contacts:
				var _c: Dictionary = pirate.active_contacts[c_id]
				var _d: float = pirate.position.distance_to(_c.get("pos", pirate.position))
				if Ship.contact_age(_c) <= pirate.FIRE_STALENESS_MAX and _d <= TRACK_QUIET_CLEAR_RANGE:
					var _iid: int = _c.get("instance_id", -1)
					var _who = instance_from_id(_iid) if _iid != -1 else null
					_blockers.append("%s (d=%.0f)" % [
						str(_who.name) if is_instance_valid(_who) else c_id, _d])
			if not _blockers.is_empty():
				print("  [dbg] phase4 t=%.0fs: track_quiet blocked by %s" % [
					exfil_frames / 60.0, ", ".join(_blockers)])
		if job.get("current", -1) >= idx_exit:
			relit = true
			break
	# The AWAIT's own timeout is 180s. Printing when this leg ended separates
	# "the exfil got slower again" from "track_quiet never clears" -- the two
	# have the same symptom (abort -> RELIGHT skipped) and different fixes.
	print("  [dbg] phase4: exfil+await leg ended at %.1fs (AWAIT timeout is 180s)" % (exfil_frames / 60.0))
	_assert(relit, "job reached EXIT_AT (current=%d)" % job.get("current", -1))
	_assert(is_instance_valid(pirate), "pirate is still alive/valid right after relighting (hasn't despawned yet)")

	# "current >= idx_exit" does NOT mean RELIGHT ran. The AWAIT before it
	# carries on_abort:"exit", so a timeout JUMPS to the EXIT_AT label and
	# satisfies the index check having skipped RELIGHT entirely -- the exact
	# regression pirate_guild.gd:495-501 documents (it was why raising the AWAIT
	# timeout 60 -> 180 was needed). Asserting the index alone made that a silent
	# pass, and pushed the damage into Phase 5 where it surfaced as two
	# unrelated-looking read failures against a pirate that had never relit.
	#
	# Assert RELIGHT's own postcondition on the SHIP instead. Not job
	# ["_abort_reason"]: job_runner_leaf._abort_reason() erases the key as it
	# logs it, so it is always gone by the time a test could read it.
	var comms_active := false
	var comms_name := ""
	if is_instance_valid(pirate):
		for c in pirate.ship_components:
			if c.get("type", "") == "comms":
				comms_active = c.get("transponder_active", false)
				comms_name = str(c.get("transponder_custom_name", ""))
				break
	_assert(comms_active and comms_name == "Silent Drifter",
		"RELIGHT actually ran -- pirate is broadcasting its new papers (active=%s, name='%s')" % [
			comms_active, comms_name])

	# --- Phase 5: a FRESH observer, placed near the exit point, reads the
	# relit pirate as NEUTRAL again (new claimed name, civilian flag). -------
	print("\n--- Phase 5: a fresh observer reads the relit pirate as NEUTRAL ---")
	var fresh_observer = _make_ship(Frigate, "FreshObserver", 703, exit_pos, ["TEAM_FRESH"])
	var contact_seen := false
	var reads_neutral_again := false
	var saw_new_name := false
	var despawned := false
	var despawned_mid_read := false
	var closest_approach := INF
	var frames_waited := 0
	# What the observer ACTUALLY read, for the failure message. Knowing the
	# contact exists but reads HOSTILE is a different bug from it not existing.
	var last_standing: Variant = null
	var last_claimed_name := ""

	# BOTH reads are downstream of one physical precondition: the pirate has to
	# get close enough for this observer to sense it at all. When that does not
	# happen, asserting the reads directly produces two failures that both point
	# at classification/transponder logic and neither of which is the cause --
	# observed 2026-07-31, where all of Phase 5 failed and the actual state was
	# that the pirate had not arrived. So: track whether ANY contact ever
	# appeared, and report that first.
	#
	# The cap is a CAP, not a budget fitted to an observation -- the loop leaves
	# the moment both reads land, so raising it costs nothing on a passing run
	# and only buys headroom on a slow one (CLAUDE.md: physics is not
	# bit-deterministic run to run, so exact-frame expectations are wrong here).
	for i in range(6000): # up to 100s -- EXIT_AT still has to close the final leg
		await main_node.get_tree().physics_frame
		frames_waited = i + 1
		# The despawn is a RACE against the reads, not an ordering guarantee:
		# EXIT_AT can free the pirate while this loop is still waiting. Breaking
		# here without recording why would fail the two read assertions for a
		# reason that has nothing to do with what they test.
		if not is_instance_valid(pirate):
			despawned = true
			despawned_mid_read = not (reads_neutral_again and saw_new_name)
			break
		closest_approach = min(closest_approach,
			fresh_observer.global_position.distance_to(pirate.global_position))
		var c: Dictionary = _find_contact(fresh_observer, pirate)
		if not c.is_empty():
			contact_seen = true
			last_standing = c.get("standing", null)
		if c.get("standing", "") == Standing.NEUTRAL:
			reads_neutral_again = true
		var t: Dictionary = fresh_observer.active_transponders.get(pirate.get_instance_id(), {})
		if not t.is_empty():
			last_claimed_name = str(t.get("name", ""))
		if t.get("name", "") == "Silent Drifter":
			saw_new_name = true
		if reads_neutral_again and saw_new_name:
			break

	print("  [dbg] phase5: waited %.1fs  closest_approach=%s  contact_seen=%s  despawned=%s  last_standing=%s  last_claimed_name='%s'" % [
		frames_waited / 60.0,
		("%.0f u" % closest_approach) if closest_approach < INF else "n/a",
		contact_seen, despawned, last_standing, last_claimed_name])

	# Precondition first, and the reads only if it held -- one accurate failure
	# beats three misleading ones.
	if not contact_seen:
		_assert(false, "the fresh observer never got ANY contact for the pirate (closest approach %s over %.1fs) -- the reads below cannot be evaluated" % [
			("%.0f u" % closest_approach) if closest_approach < INF else "n/a",
			frames_waited / 60.0])
	elif despawned_mid_read:
		_assert(false, "the pirate despawned after %.1fs, before the observer finished reading it (neutral=%s, new_name=%s)" % [
			frames_waited / 60.0, reads_neutral_again, saw_new_name])
	else:
		_assert(reads_neutral_again, "the fresh observer read the relit pirate as NEUTRAL (read %s instead)" % last_standing)
		_assert(saw_new_name, "the fresh observer received the pirate's NEW claimed name ('Silent Drifter'), not the cover name (received '%s')" % last_claimed_name)

	# --- Phase 6: EXIT_AT despawns the pirate. ---
	if not despawned:
		for i in range(600): # up to 10s more
			await main_node.get_tree().physics_frame
			if not is_instance_valid(pirate):
				despawned = true
				break
	_assert(despawned, "EXIT_AT eventually despawned the pirate")
	spawned.erase(pirate) # already freed -- don't touch it again in cleanup

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_pirate_ambush <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_pirate_ambush <<<")
		get_tree().quit(1)
