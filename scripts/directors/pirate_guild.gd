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
enum MemberState { SCHEDULED, ACTIVE, OVERDUE, LOST, CASHED_OUT }

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
	"name_pool": [
		"Fair Trader", "Slow Light", "Quiet Return", "Long Odds", "Second Wind",
		"Loose Change", "Dead Reckoning", "Last Call", "Open Book", "Clean Slate",
		"Distant Signal", "Idle Hands",
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

var takes_total: int = 0
var losses: int = 0
var take_streak: int = 0
var loss_streak: int = 0
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
			else:
				m["last_seen_pos"] = node.position
				m["last_loot_takes"] = node.loot_takes
		else:
			m["state"] = MemberState.OVERDUE
			m["overdue_since"] = 0.0
			m["observed_dead"] = false

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

		if vanished_near_wormhole:
			m["state"] = MemberState.CASHED_OUT
			takes_total += m.get("last_loot_takes", 0)
			take_streak += 1
			loss_streak = 0
		else:
			m["state"] = MemberState.LOST
			losses += 1
			loss_streak += 1
			take_streak = 0
			_erase_record(cluster, record_id)

# ---------------------------------------------------------------------------
# 3. Cap adjust -- streak-driven, clamped [base_cap, max_cap] both ways.
# ---------------------------------------------------------------------------

func _adjust_cap() -> void:
	var base_cap: int = config.get("base_cap", 1)
	var max_cap: int = config.get("max_cap", 3)
	if take_streak >= config.get("takes_per_cap_raise", 2):
		cap = clampi(cap + 1, base_cap, max_cap)
		take_streak = 0
	if loss_streak >= config.get("losses_per_cap_cut", 2):
		cap = clampi(cap - 1, base_cap, max_cap)
		loss_streak = 0

# ---------------------------------------------------------------------------
# 4. Floor -- schedule arrivals until active+overdue+pending == cap. Etas and
# names are rolled on the GLOBAL seeded RNG right here (not deferred), which
# is what makes the determinism test reproducible from a seed.
# ---------------------------------------------------------------------------

func _schedule_floor() -> void:
	var window: Array = config.get("arrival_window", [120.0, 300.0])
	var hull_mix: Array = config.get("hull_mix", [])
	if hull_mix.is_empty():
		return
	while _roster_pressure() < cap:
		var eta: float = randf_range(window[0], window[1])
		var names: Array = _draw_two_names()
		var hull_idx: int = _hull_cursor % hull_mix.size()
		_hull_cursor += 1
		arrivals.append({
			"eta_remaining": eta,
			"cover_name": names[0],
			"relight_name": names[1],
			"hull_idx": hull_idx,
		})

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
		var relight_name: String = arrival.get("relight_name", "")

		var rec := ClusterEntity.new()
		rec.id = record_id
		rec.name = arrival.get("cover_name", "")
		rec.hull_script = hull_script
		rec.kind = ClusterEntity.Kind.TRAFFIC
		rec.is_static = false
		rec.pos = spawn_pos
		rec.iff_tags = ["PIRATE_GUILD_%d" % record_id]
		rec.transponder_flag = Standing.FLAG_CIVILIAN
		rec.behavior = {
			"pirate": true,
			"job": _build_hunt_job(cluster, wormhole_pos, relight_name),
		}
		cluster.records.append(rec)

		members[record_id] = {
			"state": MemberState.ACTIVE,
			"cover_name": arrival.get("cover_name", ""),
			"relight_name": relight_name,
			"last_seen_pos": spawn_pos,
			"last_loot_takes": 0,
			"overdue_since": 0.0,
			"observed_dead": false,
		}

	arrivals = still_pending

# ---------------------------------------------------------------------------
# Hunt-job assembly -- the M50 canonical shape (implementation_plans/
# m50_pirate_tree_design.md), parameterized from records instead of authored
# by a test. Same abort topology + the As-built deviations that shape codifies:
# third_party_in_range NOT on SELECT_VICTIM (no victim exists yet -- it would
# always false-flag the intended prey), a second GO_DARK after TAKE_ALONGSIDE
# (show_colors re-lit the transponder; AWAIT{track_quiet} needs it off again).
# ---------------------------------------------------------------------------

const _R_THIRD_PARTY := 3000.0

func _build_hunt_job(cluster, wormhole_pos: Vector2, relight_name: String) -> Dictionary:
	var lane_pos: Vector2 = _pick_lane_point(cluster, wormhole_pos)
	var staging_pos: Vector2 = _staging_point(wormhole_pos, lane_pos)
	var exfil_pos: Vector2 = _exfil_point(wormhole_pos, lane_pos)

	return {
		"steps": [
			{"verb": "GO_TO", "pos": staging_pos},
			{"verb": "GO_DARK"},
			# See header: third_party_in_range deliberately NOT attached here.
			{"verb": "SELECT_VICTIM", "label": "hunt", "lane_pos": lane_pos, "lurk_radius": 2500.0, "witness_range": _R_THIRD_PARTY},
			{"verb": "INTERCEPT", "on_abort": "hunt",
				"abort_when": [{"cond": "victim_lost", "on_abort": "hunt"}, {"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "DEMAND_STOP", "show_colors": true, "patience": 25.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "TAKE_ALONGSIDE", "hold_time": 8.0, "range": 600.0, "on_abort": "hunt",
				"abort_when": [{"cond": "third_party_in_range", "r": _R_THIRD_PARTY, "on_abort": "exfil"}]},
			{"verb": "GO_DARK"}, # re-achieve dark after DEMAND_STOP's show_colors relit us
			{"verb": "GO_TO", "label": "exfil", "pos": exfil_pos},
			{"verb": "AWAIT", "condition": "track_quiet", "seconds": 3.0, "clear_range": 5000.0, "timeout": 60.0},
			{"verb": "RELIGHT", "name": relight_name, "flag": Standing.FLAG_CIVILIAN},
			{"verb": "EXIT_AT", "pos": wormhole_pos},
		],
		"current": 0,
	}

# A seeded point along a randomly-chosen cargo lane's route segment. Cargo
# lanes are public knowledge (a guild watching the lanes plausibly has it) --
# TRAFFIC records whose behavior carries {"route": [...], "cargo": true}
# (home_cluster.gd). Falls back to the wormhole itself if the cluster somehow
# carries no cargo lane (keeps the job assemblable rather than crashing).
func _pick_lane_point(cluster, wormhole_pos: Vector2) -> Vector2:
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
		return wormhole_pos

	var route: Array = lanes[randi() % lanes.size()]
	var seg: int = randi() % (route.size() - 1)
	var a: Vector2 = route[seg]
	var b: Vector2 = route[seg + 1]
	return a.lerp(b, randf())

# A seeded point off the beacon road: offset perpendicular from the
# wormhole->lane direction, well outside comms range of stations.
func _staging_point(wormhole_pos: Vector2, lane_pos: Vector2) -> Vector2:
	var dir: Vector2 = (lane_pos - wormhole_pos)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var perp: Vector2 = dir.rotated(PI / 2.0)
	var side: float = 1.0 if randf() < 0.5 else -1.0
	return wormhole_pos + dir * randf_range(5000.0, 15000.0) + perp * side * randf_range(8000.0, 20000.0)

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

func _wormhole_pos(cluster) -> Vector2:
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.WORMHOLE:
			return rec.pos
	return Vector2.ZERO

# Names in use by ACTIVE/OVERDUE members and already-pending arrivals --
# resolved (LOST/CASHED_OUT) members free their names back to the pool.
func _names_in_use() -> Dictionary:
	var in_use: Dictionary = {}
	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		var st = m.get("state", -1)
		if st == MemberState.ACTIVE or st == MemberState.OVERDUE:
			in_use[m.get("cover_name", "")] = true
			in_use[m.get("relight_name", "")] = true
	for arrival in arrivals:
		in_use[arrival.get("cover_name", "")] = true
		in_use[arrival.get("relight_name", "")] = true
	return in_use

func _draw_two_names() -> Array:
	var pool: Array = config.get("name_pool", [])
	var in_use: Dictionary = _names_in_use()
	var available: Array = []
	for n in pool:
		if not in_use.has(n):
			available.append(n)
	if available.size() < 2:
		available = pool.duplicate() # pool exhausted -- reuse rather than crash

	var idx1: int = randi() % available.size()
	var cover: String = available[idx1]
	available.remove_at(idx1)
	if available.is_empty():
		available = pool.duplicate()
		available.erase(cover)
		if available.is_empty():
			available = [cover] # single-name pool -- degenerate but non-crashing
	var idx2: int = randi() % available.size()
	var relight: String = available[idx2]
	return [cover, relight]

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
	print("[PirateGuild] active=%d overdue=%d pending=%d cap=%d take_streak=%d loss_streak=%d takes_total=%d losses=%d etas=%s" %
		[active, overdue, arrivals.size(), cap, take_streak, loss_streak, takes_total, losses, str(etas)])
