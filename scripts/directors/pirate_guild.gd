extends RefCounted
class_name PirateGuild

# M51 -- the pirate guild director (design_ideas/jobs_and_itineraries.md §3 is
# the director pattern -- a ledger plus a policy tick, the director honesty
# rule; implementation_plans/m51_pirate_guild_design.md is the pinned spec).
# The guild is an off-map organization: it never reads a non-member ship's
# state, only its own members' nodes (a check-in "radio report"), the
# records array's public geometry (the wormhole, cargo lanes -- things a
# guild watching the lanes plausibly knows), and its own config. Killing a
# member buys quiet MINUTES (presumed_lost_delay), never a same-frame
# replacement -- see the honesty rule in the design doc.
#
# A RefCounted (not a Node) living in ClusterManager.directors, ticked from
# ClusterManager.tick(dt) -- so tests drive it with the exact same
# deterministic manual tick as the cluster (viewpoint_node null).
#
# Reference via the preload-const convention (CLAUDE.md's headless
# class-cache caveat -- never the bare class_name):
#   const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const PirateOreShuttle = preload("res://scripts/ships/pirate_ore_shuttle.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")

# Ledger member states (jobs_and_itineraries.md §3 / the design doc's ledger
# shape). SCHEDULED is conceptual only -- a scheduled arrival has no record
# id yet (nothing to key `members` on), so it lives in `arrivals` instead;
# `members` entries only ever hold ACTIVE/OVERDUE/LOST/CASHED_OUT. Name-pool
# avoidance treats both the same way ("in use by ACTIVE/SCHEDULED members").
# RETURNED_EMPTY (M52a): a member that withdrew ALIVE with nothing taken --
# not a take (didn't rob anyone), not a loss (didn't lose a hull). "We'd be
# more profitable elsewhere"; it feeds the profitability backoff below and
# lets a scared-off pirate pop back up later on the normal schedule.
enum MemberState { SCHEDULED, ACTIVE, OVERDUE, LOST, CASHED_OUT, RETURNED_EMPTY }

# Base id for spawned pirate records -- clear of every authored home_cluster
# id (stations 1-12, homes 200-204, beacons 100-106, wormhole 500, patrols
# 600-601, cargo 700-701 -- see home_cluster.gd), so a guild member's record
# id can never collide with authored world furniture.
const BASE_RECORD_ID := 9000

const DEFAULT_CONFIG := {
	"policy_period": 10.0,
	"presumed_lost_delay": 45.0,
	"arrival_window": [120.0, 300.0],
	"base_cap": 1,
	"max_cap": 3,
	"takes_per_cap_raise": 2,
	"losses_per_cap_cut": 2,
	"cashin_radius": 8000.0,
	"hull_mix": [PirateOreShuttle, ArmedPinnace],
	# Identity generation (the back channels). Names are GENERATED (first x
	# second part), not drawn from a fixed pool, and a name once issued is
	# never issued again (issued_names below) -- a convincing false identity
	# takes illegal back channels to procure, so each member arrives with a
	# pre-provisioned KIT of identity_kit_size papers and can never fabricate
	# another on the spot. Burn the whole kit and you run dark and hope.
	"identity_kit_size": 3,
	"name_parts_first": [
		"Fair", "Slow", "Quiet", "Long", "Second", "Loose", "Dead", "Last",
		"Open", "Clean", "Distant", "Idle", "Pale", "Steady", "Broken", "Late",
	],
	"name_parts_second": [
		"Trader", "Light", "Return", "Odds", "Wind", "Change", "Reckoning",
		"Call", "Book", "Slate", "Signal", "Hands", "Harbor", "Crossing",
		"Promise", "Ledger",
	],
}

# --- The ledger (plain serializable state -- record ids and plain values
# only, no live-node refs held across ticks; see the design doc). ---------

var config: Dictionary = {}

# record_id -> {state, cover_name, relight_name, last_seen_pos,
# last_loot_takes, overdue_since, observed_dead}. Resolved members (LOST/
# CASHED_OUT) are kept for history; they hold no record refs.
var members: Dictionary = {}

# [{eta_remaining, cover_name, relight_name, hull_idx}] -- scheduled arrivals
# with no record yet (the record is minted when they actually spawn).
var arrivals: Array = []

# Every identity ever issued through the back channels, forever -- a burned
# name is never re-issued (it may be on wanted lists; re-flying it would be
# suicide, and the future ship-search mechanic cross-references exactly this
# kind of paper trail). Serializable set: name -> true.
var issued_names: Dictionary = {}

var takes_total: int = 0
var losses: int = 0
var returned_empty: int = 0
var take_streak: int = 0
var loss_streak: int = 0
# Profitability governor (M52a): consecutive PROFITLESS resolutions (LOST or
# RETURNED_EMPTY) stretch the next arrival delay (backoff_factor); any real
# take resets it. Distinct from cap (how MANY at once) -- backoff is how OFTEN.
# A lane that isn't paying gets fewer ships committed, and the guild recovers
# on its own clock (a scared-off predator population that ebbs and returns).
var profitless_streak: int = 0
var backoff_factor: float = 1.0
var cap: int = 1

var _elapsed: float = 0.0
var _next_record_id: int = BASE_RECORD_ID
var _hull_cursor: int = 0

func _init(cfg: Dictionary = {}) -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	for key in cfg:
		config[key] = cfg[key]
	cap = clampi(config.get("base_cap", 1), config.get("base_cap", 1), config.get("max_cap", 1))

# ---------------------------------------------------------------------------
# The policy tick. Called from ClusterManager.tick(dt) at the end of every
# cluster tick (dt-accumulated -- arrival scatter/eta rolls happen INSIDE the
# policy pass so the determinism test can reproduce them from a seed).
# ---------------------------------------------------------------------------

func tick(dt: float, cluster) -> void:
	_elapsed += dt
	var period: float = config.get("policy_period", 10.0)
	if period <= 0.0:
		return
	while _elapsed >= period:
		_elapsed -= period
		_policy_pass(cluster, period)

func _policy_pass(cluster, period: float) -> void:
	_check_ins(cluster)
	_resolve_overdue(cluster, period)
	_adjust_cap()
	_schedule_floor()
	_spawn_due_arrivals(cluster, period)
	_log(cluster)

# ---------------------------------------------------------------------------
# 1. Check-ins -- the honesty rule made mechanical: a member's own live node
# is read (the fiction of a radio report), nothing else. Live and not dead ->
# refresh last_seen_pos/last_loot_takes. Dead, record gone, or node gone ->
# OVERDUE, stamping overdue_since ONCE (never re-stamped).
# ---------------------------------------------------------------------------

func _check_ins(cluster) -> void:
	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		if m.get("state", -1) != MemberState.ACTIVE:
			continue
		var rec = _find_record(cluster, record_id)
		if rec != null and rec.is_live():
			var node = rec.live_node
			if node.is_dead:
				m["state"] = MemberState.OVERDUE
				m["overdue_since"] = 0.0
				m["observed_dead"] = true
				# M52a: capture the killer (developer instrumentation -- the node
				# stamped its last attributed attacker in take_damage) so the LOST
				# line can name it. Empty when the hull died to collision/anon.
				m["killed_by"] = node.last_damage_attacker_name
				var by: String = node.last_damage_attacker_name
				_event("'%s' (record %d) missed check-in (observed dead%s) -> OVERDUE" %
					[m.get("cover_name", "?"), record_id, " -- killed by '%s'" % by if by != "" else ""])
			else:
				m["last_seen_pos"] = node.position
				m["last_loot_takes"] = node.loot_takes
		else:
			m["state"] = MemberState.OVERDUE
			m["overdue_since"] = 0.0
			m["observed_dead"] = false
			_event("'%s' (record %d) missed check-in (vanished) -> OVERDUE" % [m.get("cover_name", "?"), record_id])

# ---------------------------------------------------------------------------
# 2. Resolve overdue past presumed_lost_delay. Vanished (not observed dead)
# within cashin_radius of the wormhole -> CASHED_OUT. Anything else
# (observed dead, or vanished elsewhere) -> LOST, and the member's
# ClusterEntity is erased from cluster.records -- the death-gap fix: the
# hulk node (if it's still sitting live in the world) is left exactly where
# it is as ordinary wreckage, but its RECORD must go or a later reconcile
# pass could resurrect a fresh, alive hull from it.
# ---------------------------------------------------------------------------

func _resolve_overdue(cluster, period: float) -> void:
	var delay: float = config.get("presumed_lost_delay", 45.0)
	var cashin_radius: float = config.get("cashin_radius", 8000.0)
	var wormhole_pos: Vector2 = _wormhole_pos(cluster)

	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		if m.get("state", -1) != MemberState.OVERDUE:
			continue
		m["overdue_since"] = m.get("overdue_since", 0.0) + period
		if m["overdue_since"] < delay:
			continue

		var vanished_near_wormhole: bool = (not m.get("observed_dead", false)) \
			and m.get("last_seen_pos", wormhole_pos).distance_to(wormhole_pos) <= cashin_radius
		var loot: int = m.get("last_loot_takes", 0)

		if vanished_near_wormhole and loot > 0:
			m["state"] = MemberState.CASHED_OUT
			takes_total += loot
			take_streak += 1
			loss_streak = 0
			profitless_streak = 0
			_recompute_backoff()
			_event("'%s' (record %d) CASHED OUT (takes +%d -> total %d, streak %d)" %
				[m.get("cover_name", "?"), record_id, loot, takes_total, take_streak])
		elif vanished_near_wormhole:
			# Left alive with an empty hold -- withdrew, not lost. Feeds backoff
			# but never counts as a loss (no hull thinned) or a take.
			m["state"] = MemberState.RETURNED_EMPTY
			returned_empty += 1
			take_streak = 0
			profitless_streak += 1
			_recompute_backoff()
			_event("'%s' (record %d) RETURNED EMPTY (no take, alive; profitless streak %d, backoff x%.1f)" %
				[m.get("cover_name", "?"), record_id, profitless_streak, backoff_factor])
		else:
			m["state"] = MemberState.LOST
			losses += 1
			loss_streak += 1
			take_streak = 0
			profitless_streak += 1
			_recompute_backoff()
			_erase_record(cluster, record_id)
			var kb: String = m.get("killed_by", "")
			_event("'%s' (record %d) presumed LOST (%s%s; losses %d, streak %d, backoff x%.1f)" %
				[m.get("cover_name", "?"), record_id,
					"observed dead" if m.get("observed_dead", false) else "vanished off-wormhole",
					" -- killed by '%s'" % kb if kb != "" else "",
					losses, loss_streak, backoff_factor])

# ---------------------------------------------------------------------------
# 3. Cap adjust -- streak-driven, clamped [base_cap, max_cap] both ways.
# ---------------------------------------------------------------------------

# Dev convenience (DebugSettings "pirate_overdrive"): bypasses the streak-
# gated ramp and the real-world arrival pacing so a playtester can see M52's
# demand/robbery/interdiction loop repeatedly without waiting out minutes of
# normal cap-ramp/spawn pacing. `DebugSettings and` guards direct
# instantiation (tests, headless script contexts) where the autoload may not
# be registered -- same pattern this file's _log() already uses.
const OVERDRIVE_CAP := 6
const OVERDRIVE_ARRIVAL_WINDOW := [8.0, 20.0]

func _overdrive() -> bool:
	return DebugSettings and DebugSettings.get_choice("pirate_overdrive") == DebugSettings.PirateOverdrive.ON

func _adjust_cap() -> void:
	if _overdrive():
		if cap != OVERDRIVE_CAP:
			_event("overdrive -- cap %d -> %d" % [cap, OVERDRIVE_CAP])
		cap = OVERDRIVE_CAP
		take_streak = 0
		loss_streak = 0
		return
	var base_cap: int = config.get("base_cap", 1)
	var max_cap: int = config.get("max_cap", 3)
	if take_streak >= config.get("takes_per_cap_raise", 2):
		var raised: int = clampi(cap + 1, base_cap, max_cap)
		if raised != cap:
			_event("success attracts recruits -- cap %d -> %d" % [cap, raised])
		cap = raised
		take_streak = 0
	if loss_streak >= config.get("losses_per_cap_cut", 2):
		var cut: int = clampi(cap - 1, base_cap, max_cap)
		if cut != cap:
			_event("losses thin the ranks -- cap %d -> %d" % [cap, cut])
		cap = cut
		loss_streak = 0

# ---------------------------------------------------------------------------
# 4. Floor -- schedule arrivals until active+overdue+pending == cap. Etas and
# names are rolled on the GLOBAL seeded RNG right here (not deferred), which
# is what makes the determinism test reproducible from a seed.
# ---------------------------------------------------------------------------

func _schedule_floor() -> void:
	var window: Array = OVERDRIVE_ARRIVAL_WINDOW if _overdrive() else config.get("arrival_window", [120.0, 300.0])
	var hull_mix: Array = config.get("hull_mix", [])
	if hull_mix.is_empty():
		return
	while _roster_pressure() < cap:
		# Profitability backoff: a lane that keeps costing the guild ships or
		# sending them home empty gets fewer arrivals, spaced further apart.
		var eta: float = randf_range(window[0], window[1]) * backoff_factor
		var kit: Array = _provision_kit()
		var hull_idx: int = _hull_cursor % hull_mix.size()
		_hull_cursor += 1
		arrivals.append({
			"eta_remaining": eta,
			"kit": kit,
			"hull_idx": hull_idx,
		})
		_event("arrival scheduled: '%s' in %.0fs (papers: %d)" % [kit[0], eta, kit.size()])

# active + overdue (still-carried members) + already-pending arrivals --
# what the floor check compares against cap.
func _roster_pressure() -> int:
	var n: int = arrivals.size()
	for record_id in members.keys():
		var st = members[record_id].get("state", -1)
		if st == MemberState.ACTIVE or st == MemberState.OVERDUE:
			n += 1
	return n

# ---------------------------------------------------------------------------
# 5. Spawn due arrivals -- eta_remaining -= policy_period; <= 0 spawns a
# ClusterEntity (TRAFFIC, cover identity, the assembled hunt job as
# behavior.job) at the wormhole and the member goes ACTIVE.
# ---------------------------------------------------------------------------

func _spawn_due_arrivals(cluster, period: float) -> void:
	var wormhole_pos: Vector2 = _wormhole_pos(cluster)
	var hull_mix: Array = config.get("hull_mix", [])
	var still_pending: Array = []
	for arrival in arrivals:
		arrival["eta_remaining"] = arrival.get("eta_remaining", 0.0) - period
		if arrival["eta_remaining"] > 0.0:
			still_pending.append(arrival)
			continue

		var record_id: int = _next_record_id
		_next_record_id += 1

		var scatter := Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))
		var spawn_pos: Vector2 = wormhole_pos + scatter

		var hull_idx: int = arrival.get("hull_idx", 0) % max(1, hull_mix.size())
		var hull_script: Script = hull_mix[hull_idx]
		var kit: Array = arrival.get("kit", [])
		var cover_name: String = kit[0] if not kit.is_empty() else ""

		var rec := ClusterEntity.new()
		rec.id = record_id
		rec.name = cover_name
		rec.hull_script = hull_script
		rec.kind = ClusterEntity.Kind.TRAFFIC
		rec.is_static = false
		rec.pos = spawn_pos
		# Shared guild tag FIRST (mutual FRIENDLY-crypto recognition: guild
		# members never rob or get spooked by their own -- the viability sim
		# showed pirates targeting each other as prey and tripping each other's
		# witness checks when the cap climbed above 1). The unique per-member
		# tag rides alongside for future per-member identity; nothing keys on it
		# today. Outsiders share neither, so a pirate still reads UNIDENTIFIED to
		# a patrol/the player.
		rec.iff_tags = ["PIRATE_GUILD", "PIRATE_GUILD_%d" % record_id]
		rec.transponder_flag = Standing.FLAG_CIVILIAN
		rec.behavior = {
			"pirate": true,
			"identity_kit": kit.duplicate(),
			"job": _build_hunt_job(cluster, wormhole_pos),
		}
		cluster.records.append(rec)

		members[record_id] = {
			"state": MemberState.ACTIVE,
			"cover_name": cover_name,
			"kit": kit.duplicate(),
			"last_seen_pos": spawn_pos,
			"last_loot_takes": 0,
			"overdue_since": 0.0,
			"observed_dead": false,
		}
		_event("'%s' arrived through the wormhole (%s, record %d)" %
			[cover_name, hull_script.resource_path.get_file(), record_id])

	arrivals = still_pending

# ---------------------------------------------------------------------------
# Hunt-job assembly -- the M50 canonical shape (implementation_plans/
# m50_pirate_tree_design.md), parameterized from records instead of authored
# by a test. Same abort topology + the As-built deviations that shape codifies:
# third_party_in_range NOT on SELECT_VICTIM (no victim exists yet -- it would
# always false-flag the intended prey), a second GO_DARK after TAKE_ALONGSIDE
# (show_colors re-lit the transponder; AWAIT{track_quiet} needs it off again).
#
# M53a Slice D -- posture: the guild rolls a `posture` per arrival ("dark_lurk"
# | "false_flag_cruise", see _roll_posture) and assembles a DIFFERENT pre-hunt
# step list per posture (jobs_and_itineraries.md's "missions are data" -- the
# posture lives entirely in which steps get assembled, no branching inside any
# step implementation). dark_lurk keeps today's AWAIT{clear}->GO_DARK before
# the hunt; false_flag_cruise skips both and goes straight from staging into
# SELECT_VICTIM/INTERCEPT with the transponder still lit under the cover
# identity -- "one more freighter" closing to demand range. Both postures
# share the identical hunt/take core and exfil tail: the post-TAKE_ALONGSIDE
# GO_DARK is the FIRST dark moment for a false_flag_cruise pirate (never went
# dark before) and the RE-achieved dark moment for a dark_lurk one (show_colors
# relit it) -- either way, laundering still depends on the track dying before
# RELIGHT, so the tail must and does stay identical.
# ---------------------------------------------------------------------------

const _R_THIRD_PARTY := 6000.0
# Tradecraft keep-away from stations (playtest: a pirate lurked, robbed, and
# went dark ON Drift Market's doorstep -- lane endpoints ARE stations, and
# nothing kept the rolled points away from them). Station positions are
# PUBLIC geometry (the same records the lanes come from), so avoiding them
# is honest guild knowledge, not omniscience.
const _R_STATION_AVOID := 25000.0
# M52a (H2): the beacon road is the WORST place to hunt -- beacons are EM-loud
# sensor+comms relays that see and report, the road carries the most traffic
# (more witnesses), and patrols work it. Beacons stay honest witnesses in the
# job's own sensor checks (no exemption anywhere); the intelligence is here in
# the guild's hunt GEOMETRY instead. Charted beacon positions are public
# knowledge (same records class as the stations the guild already reads), so
# rolling lurk/staging/exfil points away from them is honest guild tradecraft,
# not omniscience. The keep-away sits comfortably above the 6km witness range
# so the whole 25k-spaced road fails clearance and the guild self-selects the
# unbeaconed Coldreach lane / off-road stretches.
const _R_BEACON_AVOID := 15000.0

const POSTURE_DARK_LURK := "dark_lurk"
const POSTURE_FALSE_FLAG_CRUISE := "false_flag_cruise"
# Modestly favors dark_lurk: it's the proven, lower-risk tradecraft (today's
# only mode before this slice); false_flag_cruise is the newer, bolder play
# (closing to demand range still lit is a bigger gamble if the cover doesn't
# hold). Not a hard 50/50 -- tune this constant to rebalance the split later.
const FALSE_FLAG_CRUISE_CHANCE := 0.4

# Seeded per-arrival roll (CLAUDE.md determinism rule -- plain randf() on the
# global seeded RNG, no new RNG instance).
func _roll_posture() -> String:
	return POSTURE_FALSE_FLAG_CRUISE if randf() < FALSE_FLAG_CRUISE_CHANCE else POSTURE_DARK_LURK

func _build_hunt_job(cluster, wormhole_pos: Vector2) -> Dictionary:
	var stations: Array = _station_positions(cluster)
	var beacons: Array = _beacon_positions(cluster)
	var lane_info: Dictionary = _pick_lane_point(cluster, wormhole_pos, stations, beacons)
	var lane_pos: Vector2 = lane_info.get("pos", wormhole_pos)
	var seg_a: Vector2 = lane_info.get("seg_a", lane_pos)
	var seg_b: Vector2 = lane_info.get("seg_b", lane_pos)
	var staging_pos: Vector2 = _away_from_hazards(func(): return _staging_point(wormhole_pos, seg_a, seg_b), stations, beacons)
	var exfil_pos: Vector2 = _away_from_hazards(func(): return _exfil_point(wormhole_pos, lane_pos), stations, beacons)

	var posture: String = _roll_posture()

	# Pre-hunt tradecraft: dark_lurk waits for CLEAR then goes dark before
	# SELECT_VICTIM ever runs; false_flag_cruise skips both and arrives at
	# SELECT_VICTIM still lit under its cover identity (the "one more
	# freighter" posture -- see header).
	var pre_hunt: Array = []
	if posture == POSTURE_DARK_LURK:
		pre_hunt = [
			# Don't kill the transponder in front of witnesses -- a NEUTRAL
			# trader vanishing off the board while watched is a suspicion
			# gift. Wait until nobody's in plausible sensor range (own-sensor
			# heuristic); patience runs out -> go dark anyway (on_abort jumps
			# to the GO_DARK label -- an impatient pirate, not a broken job).
			{"verb": "AWAIT", "condition": "clear", "clear_range": 8000.0, "timeout": 45.0, "on_abort": "go_dark"},
			{"verb": "GO_DARK", "label": "go_dark"},
		]

	var hunt_and_take: Array = [
		# See header: third_party_in_range deliberately NOT attached here.
		# max_attempts (M52a): a bounded hunt budget -- after this many
		# victim-engagement cycles with nothing taken, SELECT_VICTIM aborts
		# to "exit" (withdraw alive via the wormhole -> RETURNED_EMPTY),
		# rather than thrashing the same lane until a patrol kills it.
		{"verb": "SELECT_VICTIM", "label": "hunt", "lane_pos": lane_pos, "lurk_radius": 2500.0, "witness_range": _R_THIRD_PARTY, "max_attempts": 4, "max_hunt_seconds": 150.0, "on_abort": "exit"},
		{"verb": "INTERCEPT", "on_abort": "hunt",
			"abort_when": [{"cond": "victim_lost", "on_abort": "hunt"}, {"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
		{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0, "on_abort": "hunt",
			"abort_when": [{"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
		{"verb": "TAKE_ALONGSIDE", "hold_time": 12.0, "range": 200.0, "on_abort": "hunt",
			"abort_when": [{"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
	]

	# Exfil tail -- IDENTICAL for both postures (see header): laundering
	# depends on the track dying before RELIGHT, so both a re-darkened
	# dark_lurk pirate and a first-time-dark false_flag_cruise pirate must
	# still go dark here before the launder wait.
	var exfil_tail: Array = [
		{"verb": "GO_DARK"}, # dark_lurk: re-achieve dark after DEMAND_STOP's show_colors relit us. false_flag_cruise: first time dark at all -- break the track before laundering.
		{"verb": "GO_TO", "label": "exfil", "pos": exfil_pos},
		# on_abort MATTERS HERE and its absence was catastrophic (found 2026-07-26
		# by tracing a member that stayed ACTIVE for three game-hours).
		# JobRunnerLeaf._abort_to("") sets current = steps.size(), which the
		# runner reads as JOB COMPLETE and clears the assignment -- so a
		# timeout on this step skipped RELIGHT and EXIT_AT entirely. The pirate
		# never flew to the wormhole, never despawned, and never resolved: it
		# sat dark and motionless in deep space forever while the guild's
		# ledger held it ACTIVE. At base_cap 1 that permanently stalls the
		# whole guild -- no further arrival is ever scheduled, silently.
		#
		# Worse, it selected against success. SELECT_VICTIM's own abort targets
		# "exit" and jumps straight to EXIT_AT, so a pirate that found NOBODY
		# went home cleanly, while a pirate that actually engaged someone
		# reached this step and got stranded. Every hull that got far enough to
		# attempt a robbery was removed from the population, which is why the
		# effectiveness sim measured zero takes across every targeting strategy.
		# 180s, raised from 60 (2026-07-27). The thermal self-throttle (Ship's
		# _thermal_throttle_cap) made a post-take exfil take ~113s where 60 used
		# to be ample: a pirate that has just run an intercept and a take is HOT,
		# so it eases off exactly when it wants to leave. Measured on
		# test_pirate_ambush -- the AWAIT completes NATURALLY at that budget
		# (RELIGHT fires, cover identity resumes); at 60 it timed out and aborted
		# to "exit", skipping RELIGHT, so pirates silently stopped resuming cover
		# identities altogether.
		#
		# Slower is the RIGHT behaviour here, not a cost to be bought back. The
		# exfil's defence is being unremarkable, not being quick -- and heat is a
		# sensor-visible signature (Ship.get_signature returns it), so burning
		# hard to escape would make a pirate a brighter contact at the exact
		# moment it is trying to disappear. Deliberately NOT granting exfil the
		# emergency thermal set point: nothing is shooting at it, and "emergency"
		# has to keep meaning danger or it means nothing.
		{"verb": "AWAIT", "condition": "track_quiet", "seconds": 3.0, "clear_range": 5000.0, "timeout": 180.0, "on_abort": "exit"},
		# The launder relight draws the next unused paper from the ship's
		# pre-provisioned identity kit (job_steps.gd RELIGHT from_kit) --
		# a convincing identity can't be fabricated on the spot. Kit
		# exhausted -> ABORT to "exit": run for the wormhole DARK and
		# hope nobody stops you (drawing patrol challenges in controlled
		# space is exactly the squeeze the design wants).
		{"verb": "RELIGHT", "from_kit": true, "flag": Standing.FLAG_CIVILIAN, "on_abort": "exit"},
		{"verb": "EXIT_AT", "label": "exit", "pos": wormhole_pos},
	]

	var steps: Array = [{"verb": "GO_TO", "pos": staging_pos}]
	steps.append_array(pre_hunt)
	steps.append_array(hunt_and_take)
	steps.append_array(exfil_tail)

	return {
		"steps": steps,
		"current": 0,
		"posture": posture,
	}

# ---------------------------------------------------------------------------
# HUNT-POINT TARGETING (2026-07-26)
#
# What these strategies use: PUBLIC GEOMETRY, and only that. Where the
# stations are, which ones are trade hubs, where the charted beacons and the
# wormhole sit.
#
# That is a scope statement, NOT a design constraint. The POSTING BOARD is a
# legitimate information source for a pirate -- knowing that Refinery Prime is
# desperate for ore tells you which lane is worth sitting on, and a guild that
# can read the market is exactly the kind of emergent behaviour worth having.
# What has not been worked out yet is the INFORMATION ECONOMY around it: who
# can see which postings, at what latency, at what cost, and how that visibility
# is earned or bought. That question belongs with the mail network
# (design_ideas/mail_network.md), which is already headed for "information
# rides couriers" rather than ambient global truth -- and settling it for
# pirates settles it for everyone.
#
# So: geometry-only is where these three START, because the map needs no new
# plumbing. A market-aware strategy is the expected successor, not a rejected
# option. Live hauler positions stay out regardless -- that is omniscience, not
# information anyone could have acquired.
#
# All three share the existing hazard keep-away and the {"pos", "seg_a",
# "seg_b"} return contract, so _staging_point's entry-point variance (re-roll
# an independent anchor along the SAME segment) keeps working unchanged.
enum HuntStrategy {
	LEGACY_LANE_ROUTES, # authored {"route": [...]} lanes -- DEAD, see _pick_lane_point
	STATION_CHORD,      # a point along a random trade-hub pair's straight line
	APPROACH_RING,      # a point on the funnel annulus around one trade hub
	CROSSROADS,         # a point where MANY hub-pair chords converge
}

# Static so a test/sim can sweep strategies without re-plumbing the director.
static var hunt_strategy: int = HuntStrategy.CROSSROADS

# APPROACH_RING: how far out the funnel band sits, as multiples of the station
# keep-away. Inside 1.0 would be under the hub's guns (and would fail the
# hazard check anyway); past ~2.5 the traffic has dispersed and it stops being
# a funnel.
const _APPROACH_RING_INNER := 1.15
const _APPROACH_RING_OUTER := 2.5

# CROSSROADS: how many chord points to sample, how near a chord counts as
# "carried by" it, and how many of the best-scoring candidates to pick among.
# The top-K pick (rather than a plain argmax) is what stops every pirate in
# the cluster converging on the single densest crossroads.
const _CROSSROADS_SAMPLES := 24
const _CROSSROADS_CHORD_R := 30000.0
const _CROSSROADS_TOP_K := 4

func _pick_hunt_point(cluster, wormhole_pos: Vector2, stations: Array, beacons: Array) -> Dictionary:
	var hubs: Array = _trade_station_positions(cluster)
	if hubs.size() < 2:
		return {"pos": wormhole_pos, "seg_a": wormhole_pos, "seg_b": wormhole_pos}
	match hunt_strategy:
		HuntStrategy.APPROACH_RING:
			return _hunt_approach_ring(hubs, stations, beacons)
		HuntStrategy.CROSSROADS:
			return _hunt_crossroads(hubs, stations, beacons)
		_:
			return _hunt_station_chord(hubs, stations, beacons)

# A random pair of trade hubs, a point along the straight line between them.
# The premise: cargo between two hubs has to cross the space between them, and
# absent a reason to detour it crosses roughly straight. Same [0.15, 0.85]
# bound the authored-lane roll used -- the endpoints are station doorsteps.
func _hunt_station_chord(hubs: Array, stations: Array, beacons: Array) -> Dictionary:
	return _away_from_hazards(func():
		var pair: Array = _random_hub_pair(hubs)
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		return {"pos": a.lerp(b, randf_range(0.15, 0.85)), "seg_a": a, "seg_b": b}
	, stations, beacons)

# A point on the annulus around ONE hub. The premise is different and in some
# ways stronger than the chord's: whatever route a hauler picks, it must
# arrive somewhere and leave somewhere, so traffic density is highest near a
# hub regardless of what the lanes look like. The cost is that hubs are also
# where the defences are -- patrol loops sit on Ironhold and Drift Market --
# so this trades catch rate against survival.
#
# seg_a/seg_b run RADIALLY outward from the hub through the point, so
# _staging_point's re-roll walks the approach line rather than sliding around
# the ring (staging should sit further out on the same approach, not on the
# far side of the station).
func _hunt_approach_ring(hubs: Array, stations: Array, beacons: Array) -> Dictionary:
	return _away_from_hazards(func():
		var hub: Vector2 = hubs[randi() % hubs.size()]
		var bearing: float = randf_range(0.0, TAU)
		var dir: Vector2 = Vector2.RIGHT.rotated(bearing)
		var r: float = _R_STATION_AVOID * randf_range(_APPROACH_RING_INNER, _APPROACH_RING_OUTER)
		var p: Vector2 = hub + dir * r
		return {"pos": p, "seg_a": p, "seg_b": hub + dir * (_R_STATION_AVOID * _APPROACH_RING_OUTER * 1.6)}
	, stations, beacons)

# Where many hub-pair chords pass close together -- the cluster's geometric
# chokepoints. The premise is the most defensible of the three: a guild does
# not need to know the ACTUAL routes if it can see that, whatever they are,
# traffic between one side of the cluster and the other has to funnel through
# here. It is also self-tuning -- move a station and the crossroads move.
#
# Deliberately picks randomly among the TOP_K scorers instead of the single
# best. A pure argmax is a map-wide constant: every pirate, forever, in one
# spot, which is worse than the bug this replaces.
func _hunt_crossroads(hubs: Array, stations: Array, beacons: Array) -> Dictionary:
	var scored: Array = []
	for _i in range(_CROSSROADS_SAMPLES):
		var pair: Array = _random_hub_pair(hubs)
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var p: Vector2 = a.lerp(b, randf_range(0.15, 0.85))
		scored.append({"pos": p, "seg_a": a, "seg_b": b, "score": _chord_carriers(p, hubs)})
	scored.sort_custom(func(x, y): return x["score"] > y["score"])
	var top: Array = scored.slice(0, mini(_CROSSROADS_TOP_K, scored.size()))
	return _away_from_hazards(func():
		return top[randi() % top.size()]
	, stations, beacons)

# How many distinct hub-pair chords pass within _CROSSROADS_CHORD_R of p.
# A crude betweenness measure, and crude is right: this is a pirate's guess at
# where traffic concentrates, not a routing solver.
func _chord_carriers(p: Vector2, hubs: Array) -> int:
	var n: int = 0
	for i in range(hubs.size()):
		for j in range(i + 1, hubs.size()):
			if _dist_to_segment(p, hubs[i], hubs[j]) <= _CROSSROADS_CHORD_R:
				n += 1
	return n

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _random_hub_pair(hubs: Array) -> Array:
	var i: int = randi() % hubs.size()
	var j: int = randi() % hubs.size()
	while j == i:
		j = randi() % hubs.size()
	return [hubs[i], hubs[j]]

func _station_positions(cluster) -> Array:
	var out: Array = []
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.STATION:
			out.append(rec.pos)
	return out

# TRADE stations only -- the subset a hunt point should be reasoned FROM,
# as opposed to _station_positions above which is every STATION-kind record
# and is what we AVOID (you keep clear of a parked mobile home too).
#
# The filter is `industry` non-empty, not `kind`, for the reason CLAUDE.md
# already records against this exact trap: mobile homes are STATION-kind, so
# keying on kind alone silently folds the five Slag Bay trailers into the
# "hubs traffic flows between" set and drags hunt geometry into a residential
# field nobody ships cargo to. Which stations are trade hubs is public
# knowledge in the strong sense -- you can see the freighters dock.
func _trade_station_positions(cluster) -> Array:
	var out: Array = []
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		if typeof(rec.industry) != TYPE_DICTIONARY or rec.industry.is_empty():
			continue
		out.append(rec.pos)
	return out

func _beacon_positions(cluster) -> Array:
	var out: Array = []
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.BEACON:
			out.append(rec.pos)
	return out

# Roll candidates until one clears BOTH keep-aways (stations at _R_STATION_
# AVOID, charted beacons at _R_BEACON_AVOID); otherwise keep the candidate
# with the greatest clearance (a cramped/all-hazard cluster degrades to
# "least bad", never to a crash or an infinite loop). Deterministic: pure
# seeded rolls, fixed retry count.
#
# `roll` may return a bare Vector2 (the staging/exfil point rolls) OR a
# Dictionary carrying {"pos": Vector2, ...extra} (the lane-point roll, whose
# EXTRA fields -- the winning segment's endpoints -- ride along so the caller
# can see which segment the WINNING candidate actually came from, not just
# whichever roll happened last; see _pick_lane_point). Hazard-checks only the
# "pos"/Vector2 half; returns the whole winning candidate unchanged.
func _away_from_hazards(roll: Callable, stations: Array, beacons: Array) -> Variant:
	var best = roll.call()
	var best_c: float = _hazard_clearance(_hazard_pos(best), stations, beacons)
	for _i in range(7):
		if best_c >= 0.0:
			return best
		var candidate = roll.call()
		var c: float = _hazard_clearance(_hazard_pos(candidate), stations, beacons)
		if c > best_c:
			best = candidate
			best_c = c
	return best

func _hazard_pos(candidate) -> Vector2:
	if candidate is Vector2:
		return candidate
	return candidate.get("pos", Vector2.ZERO)

# Signed clearance: how far INSIDE (negative) or OUTSIDE (positive) all
# keep-aways the point is. >= 0 means it clears every station and beacon.
# Empty hazard lists contribute INF (no constraint).
func _hazard_clearance(p: Vector2, stations: Array, beacons: Array) -> float:
	var c: float = INF
	for s_pos in stations:
		c = minf(c, p.distance_to(s_pos) - _R_STATION_AVOID)
	for b_pos in beacons:
		c = minf(c, p.distance_to(b_pos) - _R_BEACON_AVOID)
	return c

# A seeded point along a randomly-chosen cargo lane's route segment. Cargo
# lanes are public knowledge (a guild watching the lanes plausibly has it) --
# TRAFFIC records whose behavior carries {"route": [...], "cargo": true}
# (home_cluster.gd). The lerp fraction stays INSIDE [0.15, 0.85] and the
# point must clear the station keep-away -- lane ENDPOINTS are station
# doorsteps (the playtest bug), and no sane pirate lurks under a hub's guns.
# Falls back to the wormhole itself if the cluster somehow carries no cargo
# lane (keeps the job assemblable rather than crashing).
#
# Returns {"pos": Vector2, "seg_a": Vector2, "seg_b": Vector2} -- the winning
# segment's own endpoints ride along (M53a Slice D) so _staging_point can
# re-roll an INDEPENDENT anchor point further along that SAME segment
# (entry-point variance: two consecutive pirates on the same lane no longer
# surface at the same spot), rather than every staging point anchoring
# rigidly off lane_pos itself.
func _pick_lane_point(cluster, wormhole_pos: Vector2, stations: Array, beacons: Array) -> Dictionary:
	# M53d follow-up -- AUTHORED LANES NO LONGER EXIST. `_cargo()` stopped
	# emitting a "route" when haulers became planner-driven (they now decide
	# their own circuits from the posting board), so this scan returns an empty
	# set on the real home cluster and every hunt point collapsed onto the
	# wormhole fallback. test_pirate_circulation caught it: 200 assemblies, one
	# location. Pirates stopped distributing across the cluster entirely.
	#
	# The strategies below replace authored routes with MAP REASONING, which is
	# the honest premise anyway: a guild watching the cluster knows where the
	# hubs are and can infer where cargo must pass. It never gets to read the
	# posting board (that is private economic information) or live hauler
	# positions (that is omniscience) -- only public geometry.
	if hunt_strategy != HuntStrategy.LEGACY_LANE_ROUTES:
		return _pick_hunt_point(cluster, wormhole_pos, stations, beacons)

	var lanes: Array = []
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.TRAFFIC:
			continue
		var behavior = rec.behavior
		if typeof(behavior) != TYPE_DICTIONARY or not behavior.get("cargo", false):
			continue
		var route: Array = behavior.get("route", [])
		if route.size() >= 2:
			lanes.append(route)
	if lanes.is_empty():
		return {"pos": wormhole_pos, "seg_a": wormhole_pos, "seg_b": wormhole_pos}

	# Reroll across the WHOLE lane set (lane + segment + fraction) each attempt,
	# not just the fraction on one fixed lane -- so a lane that runs down the
	# beacon road (the "Mule" lane, every point within a beacon keep-away) loses
	# to the unbeaconed lane on clearance, and the guild self-selects the quiet
	# route instead of degrading to the least-bad point on the road.
	var picked: Variant = _away_from_hazards(func():
		var route: Array = lanes[randi() % lanes.size()]
		var seg: int = randi() % (route.size() - 1)
		var a: Vector2 = route[seg]
		var b: Vector2 = route[seg + 1]
		return {"pos": a.lerp(b, randf_range(0.15, 0.85)), "seg_a": a, "seg_b": b}
	, stations, beacons)
	return picked

# A dark staging spot near the HUNTING GROUND (the lane), not back at the
# entry wormhole. M52a: anchoring staging at the wormhole meant a pirate went
# dark by the wormhole and then had to cruise the whole way to a distant lane
# under its hunt-time budget -- a slow hull never arrived and withdrew empty
# every time (the viability sim's dead giveaway). Staging just short of and
# off to one side of the lane lets the pirate transit LIT to its hunting area
# (ordinary-looking traffic), go dark once AWAIT{clear} says nobody's near,
# and hunt right there. Off-lane + hazard keep-away (the _away_from_hazards
# wrapper) keep it out of witness/patrol sight.
#
# M53a Slice D -- entry-point variance: re-rolls its OWN anchor on the SAME
# lane segment (a fresh [0.15, 0.85] fraction between seg_a/seg_b, mirroring
# _pick_lane_point's own bound) instead of anchoring rigidly off the already-
# chosen lane_pos. Two consecutive pirates hunting the same lane therefore
# stage at genuinely different spots ALONG the lane's length, not just off to
# a randomized side of the same point -- the playtest's "shouldn't always
# enter the route in the same spot" ask. Off that fresh anchor, the same
# back-along-the-approach + perpendicular-offset shape as before.
func _staging_point(wormhole_pos: Vector2, seg_a: Vector2, seg_b: Vector2) -> Vector2:
	var anchor: Vector2 = seg_a.lerp(seg_b, randf_range(0.15, 0.85))
	var dir: Vector2 = (anchor - wormhole_pos)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var perp: Vector2 = dir.rotated(PI / 2.0)
	var side: float = 1.0 if randf() < 0.5 else -1.0
	return anchor - dir * randf_range(3000.0, 8000.0) + perp * side * randf_range(6000.0, 14000.0)

# Another off-road dark point, offset from the lane back toward/around the
# wormhole side -- distinct from staging_point's roll.
func _exfil_point(wormhole_pos: Vector2, lane_pos: Vector2) -> Vector2:
	var dir: Vector2 = (wormhole_pos - lane_pos)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.LEFT
	var perp: Vector2 = dir.rotated(PI / 2.0)
	var side: float = 1.0 if randf() < 0.5 else -1.0
	return lane_pos + dir * randf_range(3000.0, 9000.0) + perp * side * randf_range(8000.0, 20000.0)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_record(cluster, record_id: int):
	for rec in cluster.records:
		if rec.id == record_id:
			return rec
	return null

func _erase_record(cluster, record_id: int) -> void:
	for i in range(cluster.records.size()):
		if cluster.records[i].id == record_id:
			cluster.records.remove_at(i)
			return

# Profitability backoff factor from the profitless streak: 1x, 2x, 4x, capped
# at 8x. Any real take resets profitless_streak to 0 -> back to 1x.
func _recompute_backoff() -> void:
	backoff_factor = minf(pow(2.0, float(profitless_streak)), 8.0)

func _wormhole_pos(cluster) -> Vector2:
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.WORMHOLE:
			return rec.pos
	return Vector2.ZERO

# Generate one never-before-issued identity (seeded rolls -- deterministic
# under the test seed). The part-combination space is large (16x16 default);
# if a roll collides with an issued name, re-roll a bounded number of times,
# then fall back to a numbered variant (degenerate-but-unique, never crashes
# even with tiny test part lists).
func _generate_name() -> String:
	var firsts: Array = config.get("name_parts_first", ["Nameless"])
	var seconds: Array = config.get("name_parts_second", ["Hull"])
	for _attempt in range(24):
		var candidate: String = "%s %s" % [firsts[randi() % firsts.size()], seconds[randi() % seconds.size()]]
		if not issued_names.has(candidate):
			issued_names[candidate] = true
			return candidate
	var n: int = 2
	var base: String = "%s %s" % [firsts[randi() % firsts.size()], seconds[randi() % seconds.size()]]
	while issued_names.has("%s %d" % [base, n]):
		n += 1
	var fallback: String = "%s %d" % [base, n]
	issued_names[fallback] = true
	return fallback

# The back channels at work: provision a member's whole identity kit ahead
# of time. kit[0] is the arrival cover; the rest are the relight papers.
func _provision_kit() -> Array:
	var kit: Array = []
	for _i in range(maxi(1, config.get("identity_kit_size", 3))):
		kit.append(_generate_name())
	return kit

# Event line -- fires at ledger MILESTONES (arrival scheduled/spawned,
# OVERDUE, LOST, CASHED_OUT, cap moves), same toggle as the per-pass summary
# below. The pirate's whole career is deliberately invisible in-world (dark,
# off-lane); these lines are how a playtester watches it happen.
func _event(msg: String) -> void:
	if DebugSettings and DebugSettings.get_choice("pirate_guild_log") == DebugSettings.PirateGuildLog.ON:
		print("[PirateGuild] ", msg)

func _log(cluster) -> void:
	if not (DebugSettings and DebugSettings.get_choice("pirate_guild_log") == DebugSettings.PirateGuildLog.ON):
		return
	var active := 0
	var overdue := 0
	for record_id in members.keys():
		var st = members[record_id].get("state", -1)
		if st == MemberState.ACTIVE:
			active += 1
		elif st == MemberState.OVERDUE:
			overdue += 1
	var etas: Array = []
	for arrival in arrivals:
		etas.append(snappedf(arrival.get("eta_remaining", 0.0), 0.1))
	print("[PirateGuild] active=%d overdue=%d pending=%d cap=%d take_streak=%d loss_streak=%d takes_total=%d losses=%d returned_empty=%d backoff=x%.1f etas=%s" %
		[active, overdue, arrivals.size(), cap, take_streak, loss_streak, takes_total, losses, returned_empty, backoff_factor, str(etas)])
