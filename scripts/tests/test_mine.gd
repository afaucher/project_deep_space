extends Node

# M27 acceptance -- mine (per implementation_plans/m27_catalog_expansion_design.md
# test plan item 5). Three things at once, using the build_station() AI tree
# (Engage: acquire nearest hostile VESSEL contact -> hold heading/fire ->
# StationKeepingIdle fallback -- no Disengage/Flee branch, so the mine never
# pursues or breaks off, matching "the mine never pursues" from the plan):
#
#   1. A hostile-IFF LAC drifts (constant linear_velocity, no AI/autopilot) on
#      a straight line through the mine's laser range -> the mine's laser
#      fires and the LAC takes damage (assert a hull-integrity/health drop).
#   2. A friendly-IFF ship (same LAC hull, TEAM_PLAYER tags shared with the
#      mine) crosses the same range and is NOT fired on -- passes unharmed.
#   3. The mine never PURSUES, but it may DODGE: once the hostile dies, the
#      wreck gate (acquire_target_leaf) correctly ends the engagement and the
#      tree falls through to StationKeepingIdle -- whose collision avoidance
#      then rightly sidesteps the dead hulk still coasting past ~100u away
#      (well inside Steering.MARGIN=400). So the drift assertion is
#      bounded-excursion + return-to-station, not never-moves. (The old
#      never-moves-30u assertion silently depended on the pre-fix bug: sticky
#      HOSTILE standing kept Engage latched on the wreck, which suppressed
#      StationKeeping -- and its avoidance -- entirely.)
#   4. Regression for that same wreck-gate fix: after the hostile dies, the
#      mine STOPS firing -- its laser cooldown never resets again.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_mine
# Pass marker per CLAUDE.md.

const Mine = preload("res://scripts/ships/mine.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
# M48 -- the Mine hull carries no comms component (see mine.gd's
# ship_components), so it can never RECEIVE a transponder flag (Ship's
# datalink relay gates the whole transponder-receive loop on
# self_comms_range > 0) -- a declared flag on the hostile LAC would be
# broadcast into the void. mark_contact_hostile is the legitimate lever for
# a comms-less hull (design doc: "a hull with no comms can't declare a
# flag, so there's no other legal way to mark it"). The friendly LAC stays
# FRIENDLY via the shared-tag crypto rule, which needs no transponder at all.
const Standing = preload("res://scripts/combat/standing.gd")

const MINE_POS := Vector2.ZERO
# A collision-avoidance dodge of the drifting hulk peaks around ~300-400u
# (observed ~320u); actual PURSUIT of a 300 u/s target would run to
# thousands. The excursion cap separates the two, and the end-of-run check
# proves the mine comes home (station keeping's return velocity is
# dist*0.1 -> exponential with a ~10s time constant, hence the long run).
const MINE_MAX_EXCURSION := 1200.0
const MINE_RETURN_TOLERANCE := 150.0

# Both LACs drift on a straight line near y=0, crossing well inside the mine's
# laser range (2200) at closest approach, starting and ending well outside it
# so each run has a clean "before/during/after" pass through weapons range.
const DRIFT_SPEED := 300.0
const HOSTILE_START := Vector2(-3000.0, 100.0)
const FRIENDLY_START := Vector2(-3000.0, -100.0)
const RUN_DURATION := 45.0 # both LACs cross and clear, then the post-dodge return converges (see MINE_RETURN_TOLERANCE)

var main_node: Node = null
var failures: Array = []
var finished: bool = false

var mine = null
var hostile = null
var friendly = null
var t: float = 0.0
var max_mine_drift: float = 0.0

# Wreck-gate regression tracking: after the hostile dies AND the death
# transient settles, a laser cooldown that INCREASES frame-to-frame means the
# mine fired again -- at a wreck. The grace covers the honest-sensors
# transient: the dying reactor's EM whiteout (REACTOR_WHITEOUT_DURATION=1.5s
# at 5x power_rating) keeps the hulk reading as an ACTIVE vessel to the
# mine's own sensors for ~2s (whiteout + sweep refresh + track lerp), so a
# double-tap during the flare is legitimate target-still-hot behavior, not
# the bug. The bug this guards against is INDEFINITE firing (sticky HOSTILE
# with no wreck gate), which only shows after the transient.
const POST_KILL_GRACE := 4.0
var _death_time: float = -1.0
var _prev_laser_cd: float = 0.0
var fired_after_kill: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func _total_health(ship) -> float:
	var h: float = 0.0
	for c in ship.ship_components:
		h += max(0.0, c.get("health", 0.0))
	return h

func setup(main) -> void:
	main_node = main
	print("Starting Mine (M27) Tests")

	mine = Mine.new()
	mine.name = "Mine"
	mine.owner_id = 500
	mine.iff_tags = ["TEAM_MINE"]
	mine.position = MINE_POS
	main_node.add_child(mine)
	mine.add_child(AITreeFactory.build_station())

	hostile = LightAttackCraft.new()
	hostile.name = "HostileLAC"
	hostile.owner_id = 501
	hostile.iff_tags = ["TEAM_HOSTILE"]
	hostile.position = HOSTILE_START
	hostile.linear_velocity = Vector2(DRIFT_SPEED, 0.0)
	main_node.add_child(hostile)

	friendly = LightAttackCraft.new()
	friendly.name = "FriendlyLAC"
	friendly.owner_id = 502
	friendly.iff_tags = ["TEAM_MINE"]   # shares the mine's own tag -> classified FRIENDLY
	friendly.position = FRIENDLY_START
	friendly.linear_velocity = Vector2(DRIFT_SPEED, 0.0)
	main_node.add_child(friendly)

# M48 -- the mine has no comms, so find its own sensor track on the hostile
# LAC (once its own sweep has correlated one) and flag it hostile directly.
# Cheap to call every frame -- a no-op once the contact is already HOSTILE.
func _mark_hostile_once_tracked() -> void:
	if not is_instance_valid(mine) or not is_instance_valid(hostile):
		return
	var tid: int = hostile.get_instance_id()
	for c_id in mine.active_contacts:
		var c: Dictionary = mine.active_contacts[c_id]
		if c.get("instance_id", -1) == tid and c.get("standing", "") != Standing.HOSTILE:
			mine.mark_contact_hostile(c_id, "test hostile")
			return

func _physics_process(delta: float) -> void:
	if finished or mine == null:
		return
	t += delta
	_mark_hostile_once_tracked()

	if is_instance_valid(mine):
		var drift: float = mine.position.distance_to(MINE_POS)
		max_mine_drift = max(max_mine_drift, drift)

	# Wreck-gate regression: once the hostile is dead and POST_KILL_GRACE has
	# passed (see the comment on that const), any frame-to-frame INCREASE of
	# the mine's laser cooldown is a fresh shot -- necessarily at the wreck,
	# the only thing it ever engaged. _prev_laser_cd tracks every post-death
	# frame (not just post-grace) so the first post-grace comparison can't
	# false-positive against a stale pre-grace snapshot.
	if is_instance_valid(mine) and is_instance_valid(hostile) and hostile.is_dead:
		var cd: float = mine.get_component("laser_main").get("cooldown", 0.0)
		if _death_time < 0.0:
			_death_time = t
		elif t - _death_time > POST_KILL_GRACE and cd > _prev_laser_cd + 0.01:
			fired_after_kill = true
		_prev_laser_cd = cd

	if t > RUN_DURATION:
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true

	if not is_instance_valid(mine):
		_assert(false, "mine should still be alive/valid at the end of the run")
	else:
		_assert(max_mine_drift <= MINE_MAX_EXCURSION,
			"mine may dodge but never pursues (max excursion %.1fu > cap %.1fu)" % [max_mine_drift, MINE_MAX_EXCURSION])
		var final_drift: float = mine.position.distance_to(MINE_POS)
		_assert(final_drift <= MINE_RETURN_TOLERANCE,
			"mine returns to station after any dodge (final drift %.1fu > tolerance %.1fu)" % [final_drift, MINE_RETURN_TOLERANCE])
	_assert(not fired_after_kill, "mine must stop firing once its target is a wreck (wreck-gate regression)")

	var hostile_health: float = _total_health(hostile) if is_instance_valid(hostile) else 0.0
	var hostile_max_health: float = 0.0
	if is_instance_valid(hostile):
		for c in hostile.ship_components:
			hostile_max_health += c.get("max_health", 0.0)
	var hostile_took_damage: bool = (not is_instance_valid(hostile)) or hostile.is_dead or (hostile_max_health > 0.0 and hostile_health < hostile_max_health - 0.01)
	_assert(hostile_took_damage, "hostile LAC should take damage from the mine's laser (health %.1f / max %.1f, is_dead=%s)" % [hostile_health, hostile_max_health, str(is_instance_valid(hostile) and hostile.is_dead)])

	if is_instance_valid(friendly):
		var friendly_health: float = _total_health(friendly)
		var friendly_max_health: float = 0.0
		for c in friendly.ship_components:
			friendly_max_health += c.get("max_health", 0.0)
		_assert(not friendly.is_dead, "friendly LAC should not have been destroyed")
		_assert(friendly_max_health > 0.0 and friendly_health >= friendly_max_health - 0.01,
			"friendly LAC should pass unharmed (health %.1f / max %.1f)" % [friendly_health, friendly_max_health])
	else:
		_assert(false, "friendly LAC should still be alive/valid at the end of the run")

	if failures.is_empty():
		print(">>> [TEST PASSED] test_mine <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_mine <<<")
		get_tree().quit(1)
