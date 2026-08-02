extends RefCounted
class_name TrafficGuild

# M53b Pass 2 -- the traffic guild director (implementation_plans/
# m53bc_traffic_guild.md "Pass 2"; design_ideas/jobs_and_itineraries.md §3 is
# the director pattern this and pirate_guild.gd both implement -- a ledger
# plus a policy tick, the director honesty rule). A RefCounted (not a Node)
# living in ClusterManager.directors, ticked from ClusterManager.tick(dt) --
# tests drive it with the same deterministic manual tick as the cluster.
#
# DELIBERATE duplication with pirate_guild.gd (the sequencing insight in the
# plan doc): this is the SECOND director, built concretely so Pass 3 can
# extract a shared skeleton from two real examples instead of inventing hooks
# from one. Do not "clean this up" by importing from pirate_guild.gd.
#
# Two independent jobs live in one ledger:
#   1. Population floor PER FLAG -- adopt the authored cargo lanes
#      (home_cluster.gd ids 700-703) as members on first tick, then replenish
#      a LOST hauler on the SAME route it served, under the same flag. This is
#      the depletion fix: authored traffic + working piracy otherwise thin the
#      world permanently.
#   2. Transient wormhole freighters -- through-traffic that spawns at the
#      wormhole, docks at BOTH road termini (Ironhold, Drift Market), then
#      EXIT_AT the wormhole. Rebalances nothing; just makes the road busy and
#      witnessed. Reuses the M50 job runner via the new civilian job tree
#      (ai_tree_factory.gd's build_civilian_job(), cluster_manager.gd's
#      generalized _attach_ai).
#
# Reference via the preload-const convention (CLAUDE.md's headless
# class-cache caveat -- never the bare class_name):
#   const TrafficGuild = preload("res://scripts/directors/traffic_guild.gd")

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const SourceLog = preload("res://scripts/mail/source_log.gd")
const Incident = preload("res://scripts/mail/incident.gd")

# Base id for spawned traffic records -- clear of every authored home_cluster
# id (stations 1-14, homes 200-204, beacons 100-114, wormhole 500, patrols
# 600-601, cargo 700-703 -- see home_cluster.gd) AND clear of PirateGuild's
# own BASE_RECORD_ID (9000+), so neither director's spawns can ever collide.
const BASE_RECORD_ID := 8000

enum MemberState { ACTIVE, OVERDUE, LOST }
enum FreighterState { ACTIVE, OVERDUE, DEPARTED, DESTROYED }

const DEFAULT_CONFIG := {
	"policy_period": 10.0,
	"presumed_lost_delay": 45.0,
	# Population floor -- one target per flag. Defaults match the authored
	# baseline exactly (Mule + Ore Barge for FLAG_DRIFT, Meridian Runner +
	# Combine Hauler for FLAG_MERIDIAN, home_cluster.gd 700-703): adoption
	# alone satisfies the floor on a fresh campaign, so nothing spawns until
	# something is actually lost. Raising a target above the adopted count
	# grows that flag's traffic (the "not merely replace losses" design).
	"population_targets": {Standing.FLAG_DRIFT: 2, Standing.FLAG_MERIDIAN: 2},
	"hauler_arrival_window": [60.0, 150.0],
	"relief_name": "Relief Hauler",
	# Transient wormhole freighters -- through-traffic only, no route memory.
	"freighter_target": 2,
	"freighter_arrival_window": [45.0, 120.0],
	"freighter_hull": CargoShuttle,
	"freighter_flag": Standing.FLAG_CIVILIAN,
	"freighter_name": "Transient Freighter",
	# The beacon road's two termini, read by NAME off the live STATION
	# records each policy pass (never a hardcoded Vector2 -- CLAUDE.md's
	# duplicated-world-constants warning). Config, not code, so a test
	# fixture with differently-named stations can override it.
	"road_terminus_a": "Ironhold",
	"road_terminus_b": "Drift Market",
	# Perf ceiling (design doc's "Perf" watch item): total roster pressure
	# (pending arrivals + active/overdue haulers + active/overdue freighters,
	# across every flag) never exceeds this, regardless of how high the
	# per-flag targets/freighter_target are configured.
	"hard_cap": 10,
}

# --- The ledger (plain serializable state -- record ids and plain values
# only, no live-node refs held across ticks; see the design doc). ---------

var config: Dictionary = {}

# record_id -> {state, flag, route: [Vector2, Vector2], hull_script, iff_tags,
# last_seen_pos, overdue_since, observed_dead}. Population-floor haulers only
# (adopted authored lanes + their replenishments); LOST members are kept for
# history, same as PirateGuild.
var members: Dictionary = {}

# record_id -> {state, overdue_since, observed_dead}. Transient wormhole
# freighters -- through-traffic, no route memory, never replenished
# individually (the freighter_target floor tops the COUNT up instead).
var freighters: Dictionary = {}

# [{kind: "hauler"|"freighter", eta_remaining, <hauler: route/flag/hull_script/
# iff_tags>}] -- scheduled arrivals with no record yet (minted on spawn).
var arrivals: Array = []

var losses: int = 0
var replenishments: int = 0
var freighters_departed: int = 0
var freighters_destroyed: int = 0

# M57 -- the guild's OWN incident log. The guild is a source: OVERDUE is not
# something it was told, it is something it CONCLUDED from its own members
# going quiet, which is why this is honest with no transport layer built yet
# (the design doc's "one piece that needs no mail at all"). Haulers on authored
# lanes are the guild's own hulls, so reading their check-ins is a radio
# report, not omniscience -- the same trick PirateGuild already uses.
#
# It is also the only intelligence signal in the game that SURVIVES A PIRATE
# KILLING THE SOLE WITNESS: a robbery nobody lived to report still shows up
# here as a hull that stopped arriving.
#
# Lives on the director rather than a station record because the guild has no
# seat yet; M58 gives it one and this moves there. Storage mechanics are
# SourceLog's, same as every other log.
const INCIDENT_LOG_CAP := 100
var incident_log: Array = []
var incident_seq: int = 0

var _elapsed: float = 0.0
var _next_record_id: int = BASE_RECORD_ID
var _adopted: bool = false

func _init(cfg: Dictionary = {}) -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	for key in cfg:
		config[key] = cfg[key]

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
	_adopt_authored(cluster)
	_check_ins(cluster)
	_resolve_overdue(cluster, period)
	_schedule_floor(cluster)
	_spawn_due_arrivals(cluster, period)
	_log(cluster)

# ---------------------------------------------------------------------------
# 0. Adoption -- the depletion fix's other half. Folds every existing
# TRAFFIC/cargo record whose flag this director manages (population_targets'
# keys) into `members` as an ACTIVE member, ONCE (the _adopted guard makes a
# second/Nth policy pass a no-op -- idempotent by construction, not by
# re-checking membership). Without this, killing the authored "Mule" would
# never trigger replenishment -- the director would only ever know about ITS
# OWN spawns, which IS the depletion bug the plan calls out.
# ---------------------------------------------------------------------------

func _adopt_authored(cluster) -> void:
	if _adopted:
		return
	_adopted = true
	var targets: Dictionary = config.get("population_targets", {})
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.TRAFFIC:
			continue
		var behavior = rec.behavior
		if typeof(behavior) != TYPE_DICTIONARY or not behavior.get("cargo", false):
			continue
		if not targets.has(rec.transponder_flag):
			continue # not a flag this guild manages (e.g. a future third sovereign)
		var route: Array = behavior.get("route", [])
		members[rec.id] = {
			"state": MemberState.ACTIVE,
			"flag": rec.transponder_flag,
			"route": route.duplicate(true),
			"hull_script": rec.hull_script,
			"iff_tags": rec.iff_tags.duplicate(true),
			"last_seen_pos": rec.pos,
			"overdue_since": 0.0,
			"observed_dead": false,
		}
		_event("adopted authored lane '%s' (record %d, flag %s, route %s)" %
			[rec.name, rec.id, rec.transponder_flag, str(route)])

# ---------------------------------------------------------------------------
# 1. Check-ins -- the honesty rule made mechanical (director honesty rule,
# jobs_and_itineraries.md §3): a member's own live node is read, nothing
# else. Live and not dead -> refresh last_seen_pos. Dead, record gone, or
# node gone -> OVERDUE, stamping overdue_since ONCE. Haulers and freighters
# both follow this shape; kept as two small loops (not one generic helper)
# per the pass's deliberate-duplication note -- they diverge in resolution.
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
				_event("hauler on route %s (record %d) missed check-in (observed dead) -> OVERDUE" %
					[str(m.get("route", [])), record_id])
			else:
				m["last_seen_pos"] = node.position
		else:
			m["state"] = MemberState.OVERDUE
			m["overdue_since"] = 0.0
			m["observed_dead"] = false
			_event("hauler on route %s (record %d) missed check-in (vanished) -> OVERDUE" %
				[str(m.get("route", [])), record_id])

	for record_id in freighters.keys():
		var f: Dictionary = freighters[record_id]
		if f.get("state", -1) != FreighterState.ACTIVE:
			continue
		var rec = _find_record(cluster, record_id)
		if rec != null and rec.is_live():
			if rec.live_node.is_dead:
				f["state"] = FreighterState.OVERDUE
				f["overdue_since"] = 0.0
				f["observed_dead"] = true
				_event("freighter (record %d) missed check-in (observed dead) -> OVERDUE" % record_id)
		else:
			# Vanished -- almost always a successful EXIT_AT (ClusterManager's
			# own external-despawn reconcile already erased the record by the
			# time this runs, see _reconcile()'s ordering ahead of directors).
			f["state"] = FreighterState.OVERDUE
			f["overdue_since"] = 0.0
			f["observed_dead"] = false
			_event("freighter (record %d) missed check-in (vanished, likely departed) -> OVERDUE" % record_id)

# ---------------------------------------------------------------------------
# 2. Resolve overdue past presumed_lost_delay.
#   Haulers: always LOST (no cash-out concept here -- an idle lane has
#   nothing to "take"), record erased (M51's death-gap fix, same as
#   PirateGuild), and a replacement is scheduled on the EXACT SAME route,
#   flag, hull and iff_tags the lost member carried -- not a generic per-flag
#   respawn, so route continuity is exact.
#   Freighters: observed dead -> DESTROYED; vanished -> DEPARTED. Either way
#   the record is erased defensively (usually already gone via reconcile) and
#   NO individual replacement is scheduled -- the freighter_target floor
#   below tops the COUNT back up on its own schedule.
# ---------------------------------------------------------------------------

# Appends to the guild's own source log. Mirrors Ship.record_incident() (same
# SourceLog mechanics, same never-rewound seq, same cap) -- separate only
# because a director is not a Node and has no cluster record to resolve to.
func _record_incident(kind: String, subject_name: String, subject_flag: String, pos: Vector2) -> Dictionary:
	incident_seq += 1
	var fields: Dictionary = Incident.make(kind, subject_name, subject_flag, pos, "TrafficGuild")
	return SourceLog.append_entry(incident_log, incident_seq, fields, INCIDENT_LOG_CAP)

func _resolve_overdue(cluster, period: float) -> void:
	var delay: float = config.get("presumed_lost_delay", 45.0)
	var hard_cap: int = config.get("hard_cap", 999999)

	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		if m.get("state", -1) != MemberState.OVERDUE:
			continue
		m["overdue_since"] = m.get("overdue_since", 0.0) + period
		if m["overdue_since"] < delay:
			continue
		m["state"] = MemberState.LOST
		losses += 1
		# M57 -- `losses` is a scoreboard: it says HOW MANY, never WHERE, so no
		# router can act on it. The same event as a positioned incident is the
		# cheapest real intelligence in the system.
		#
		# Note what the subject is here: an OVERDUE incident names the LOST
		# HULL, not a perpetrator -- nobody saw who did it, and inventing an
		# attacker would be exactly the omniscience this model exists to remove.
		# Ambiguous evidence a director weighs for itself is the point.
		#
		# last_seen_pos is honestly "where we last heard from it" (refreshed
		# only by check-ins on a live node), NOT where it died -- so a hull
		# jumped further along its route reports the last place anyone knew it
		# was fine. That understatement is correct and should not be "fixed".
		_record_incident(Incident.KIND_OVERDUE,
			"Cluster_%d" % record_id, m.get("flag", ""),
			m.get("last_seen_pos", Vector2.ZERO))
		_erase_record(cluster, record_id)
		_event("hauler on route %s (record %d) presumed LOST (%s; losses %d)" %
			[str(m.get("route", [])), record_id,
				"observed dead" if m.get("observed_dead", false) else "vanished", losses])
		if _total_roster_pressure() < hard_cap:
			_schedule_specific_arrival(m.get("route", []), m.get("flag", ""),
				m.get("hull_script", null), m.get("iff_tags", []))
		else:
			_event("hard cap (%d) reached -- NOT replacing lost hauler on route %s" %
				[hard_cap, str(m.get("route", []))])

	for record_id in freighters.keys():
		var f: Dictionary = freighters[record_id]
		if f.get("state", -1) != FreighterState.OVERDUE:
			continue
		f["overdue_since"] = f.get("overdue_since", 0.0) + period
		if f["overdue_since"] < delay:
			continue
		_erase_record(cluster, record_id) # defensive -- reconcile usually already did this
		if f.get("observed_dead", false):
			f["state"] = FreighterState.DESTROYED
			freighters_destroyed += 1
			_event("freighter (record %d) DESTROYED en route" % record_id)
		else:
			f["state"] = FreighterState.DEPARTED
			freighters_departed += 1
			_event("freighter (record %d) DEPARTED via the wormhole" % record_id)

# ---------------------------------------------------------------------------
# 3. Floor -- backstop top-up toward the configured per-flag/freighter
# targets, beyond what event-driven replacement (above) already provides.
# On a fresh campaign with default config this never fires (adoption alone
# satisfies every target); it exists so raising a target later (story-phase
# growth) actually grows traffic, per the design doc's "not merely replace
# losses." Etas are rolled on the GLOBAL seeded RNG right here (not
# deferred) -- what makes the determinism test reproducible from a seed.
# ---------------------------------------------------------------------------

func _schedule_floor(cluster) -> void:
	var hard_cap: int = config.get("hard_cap", 999999)
	var targets: Dictionary = config.get("population_targets", {})
	for flag in targets.keys():
		while _flag_roster_pressure(flag) < int(targets[flag]) and _total_roster_pressure() < hard_cap:
			var tmpl: Dictionary = _flag_template(flag)
			if tmpl.is_empty():
				break # nothing to clone from yet (no adopted/spawned member of this flag) -- skip until one exists
			_schedule_specific_arrival(tmpl.get("route", []), flag, tmpl.get("hull_script", null), tmpl.get("iff_tags", []))

	while _freighter_roster_pressure() < int(config.get("freighter_target", 2)) and _total_roster_pressure() < hard_cap:
		_schedule_freighter_arrival()

# An existing (possibly LOST/history) member's route/hull/iff_tags, used as a
# template for a generic floor top-up of the SAME flag. Event-driven
# replacement (in _resolve_overdue) never uses this -- it already knows the
# exact member it's replacing.
func _flag_template(flag: String) -> Dictionary:
	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		if m.get("flag", "") == flag:
			return {"route": m.get("route", []), "hull_script": m.get("hull_script", null), "iff_tags": m.get("iff_tags", [])}
	return {}

func _schedule_specific_arrival(route: Array, flag: String, hull_script: Script, iff_tags: Array) -> void:
	var window: Array = config.get("hauler_arrival_window", [60.0, 150.0])
	var eta: float = randf_range(window[0], window[1])
	arrivals.append({
		"kind": "hauler",
		"eta_remaining": eta,
		"route": route.duplicate(true),
		"flag": flag,
		"hull_script": hull_script,
		"iff_tags": iff_tags.duplicate(true),
	})
	_event("replacement hauler scheduled for route %s (flag %s) in %.0fs" % [str(route), flag, eta])

func _schedule_freighter_arrival() -> void:
	var window: Array = config.get("freighter_arrival_window", [45.0, 120.0])
	var eta: float = randf_range(window[0], window[1])
	arrivals.append({"kind": "freighter", "eta_remaining": eta})
	_event("freighter arrival scheduled in %.0fs" % eta)

# ---------------------------------------------------------------------------
# 4. Spawn due arrivals -- eta_remaining -= policy_period; <= 0 spawns a
# ClusterEntity at the wormhole and the member/freighter goes ACTIVE.
# ---------------------------------------------------------------------------

func _spawn_due_arrivals(cluster, period: float) -> void:
	var wormhole_pos: Vector2 = _wormhole_pos(cluster)
	var still_pending: Array = []
	for arrival in arrivals:
		arrival["eta_remaining"] = arrival.get("eta_remaining", 0.0) - period
		if arrival["eta_remaining"] > 0.0:
			still_pending.append(arrival)
			continue
		if arrival.get("kind", "") == "hauler":
			_spawn_hauler(cluster, arrival, wormhole_pos)
		else:
			_spawn_freighter(cluster, arrival, wormhole_pos)
	arrivals = still_pending

func _spawn_hauler(cluster, arrival: Dictionary, wormhole_pos: Vector2) -> void:
	var route: Array = arrival.get("route", [])
	var hull_script: Script = arrival.get("hull_script", null)
	if hull_script == null or route.size() < 2:
		_event("hauler arrival skipped -- missing route/hull data")
		return

	var record_id: int = _next_record_id
	_next_record_id += 1
	var flag: String = arrival.get("flag", "")

	var rec := ClusterEntity.new()
	rec.id = record_id
	rec.name = "%s %d" % [config.get("relief_name", "Relief Hauler"), record_id]
	rec.hull_script = hull_script
	rec.kind = ClusterEntity.Kind.TRAFFIC
	rec.is_static = false
	rec.pos = wormhole_pos
	var iff_tags: Array = arrival.get("iff_tags", [])
	rec.iff_tags = iff_tags.duplicate(true)
	rec.transponder_flag = flag
	# Same behavior shape home_cluster.gd's authored lanes use -- the EXISTING
	# route/cargo branch in cluster_manager.gd's _attach_ai handles this
	# unchanged (build_cargo(), CargoRunLeaf); replenishment needs no new
	# machinery, just a fresh record.
	# Omit "route" entirely when there is none, rather than writing an empty
	# array. cluster_manager.gd's Phase C branch keys on `cargo AND NOT
	# has("route")`, so an empty-but-PRESENT key would fail that test, then fail
	# the patrol branch's `route.size() > 0` too, and the hull would fall through
	# to combat AI. A replenishment for a planner-driven lane must itself be
	# planner-driven.
	rec.behavior = {"loop": true, "cargo": true}
	if not route.is_empty():
		rec.behavior["route"] = route.duplicate(true)
	cluster.records.append(rec)

	members[record_id] = {
		"state": MemberState.ACTIVE,
		"flag": flag,
		"route": route.duplicate(true),
		"hull_script": hull_script,
		"iff_tags": iff_tags.duplicate(true),
		"last_seen_pos": wormhole_pos,
		"overdue_since": 0.0,
		"observed_dead": false,
	}
	replenishments += 1
	_event("'%s' (record %d) arrived through the wormhole -- resuming route %s (flag %s)" %
		[rec.name, record_id, str(route), flag])

func _spawn_freighter(cluster, arrival: Dictionary, wormhole_pos: Vector2) -> void:
	var hull_script: Script = config.get("freighter_hull", null)
	if hull_script == null:
		_event("freighter arrival skipped -- no freighter_hull configured")
		return
	var job: Dictionary = _build_freighter_job(cluster, wormhole_pos)
	if job.is_empty():
		_event("freighter arrival skipped -- road termini not found (check road_terminus_a/b)")
		return

	var record_id: int = _next_record_id
	_next_record_id += 1
	var scatter := Vector2(randf_range(-500.0, 500.0), randf_range(-500.0, 500.0))

	var rec := ClusterEntity.new()
	rec.id = record_id
	rec.name = "%s %d" % [config.get("freighter_name", "Transient Freighter"), record_id]
	rec.hull_script = hull_script
	rec.kind = ClusterEntity.Kind.TRAFFIC
	rec.is_static = false
	rec.pos = wormhole_pos + scatter
	rec.iff_tags = []
	rec.transponder_flag = config.get("freighter_flag", Standing.FLAG_CIVILIAN)
	# NEW behavior shape (M53b structural gap #1/#2): a bare {"job": ...} with
	# no "route"/"cargo" keys, so cluster_manager.gd's generalized _attach_ai
	# routes it to the new civilian job tree instead of the cargo/patrol branch.
	rec.behavior = {"job": job}
	cluster.records.append(rec)

	freighters[record_id] = {
		"state": FreighterState.ACTIVE,
		"overdue_since": 0.0,
		"observed_dead": false,
	}
	_event("'%s' (record %d) arrived through the wormhole -- running the road" % [rec.name, record_id])

# ---------------------------------------------------------------------------
# Freighter itinerary -- the M50 canonical shape from the plan doc: GO_TO ->
# DOCK_AT -> AWAIT{undocked} -> GO_TO -> DOCK_AT -> AWAIT{undocked} ->
# EXIT_AT (test_visitor_itinerary.gd's proven shape). No RNG at all -- the
# termini and the wormhole are all fixed public geometry, read fresh off the
# live records each call (never a hardcoded Vector2 -- see the
# road_terminus_a/b config comment). Orders the two dock stops by distance
# from the wormhole (nearer terminus first) so the itinerary reflects
# whichever terminus the freighter actually arrives closest to, rather than
# assuming which name is "near".
# ---------------------------------------------------------------------------

func _build_freighter_job(cluster, wormhole_pos: Vector2) -> Dictionary:
	var termini: Dictionary = _road_termini(cluster)
	var a = termini.get("a", null)
	var b = termini.get("b", null)
	if a == null or b == null:
		return {}

	var near: Vector2 = a if wormhole_pos.distance_to(a) <= wormhole_pos.distance_to(b) else b
	var far: Vector2 = b if near == a else a

	return {
		"steps": [
			{"verb": "GO_TO", "pos": near},
			{"verb": "DOCK_AT", "station_pos": near},
			{"verb": "AWAIT", "condition": "undocked"},
			{"verb": "GO_TO", "pos": far},
			{"verb": "DOCK_AT", "station_pos": far},
			{"verb": "AWAIT", "condition": "undocked"},
			{"verb": "EXIT_AT", "pos": wormhole_pos},
		],
		"current": 0,
	}

# The beacon road's two termini -- read by station NAME (config data, see
# road_terminus_a/b) off the live STATION records' own positions. Never a
# hardcoded Vector2 literal (CLAUDE.md's duplicated-world-constants warning);
# only the NAMES are config, same as main.gd's own nav-destination lookups.
func _road_termini(cluster) -> Dictionary:
	var a_name: String = config.get("road_terminus_a", "Ironhold")
	var b_name: String = config.get("road_terminus_b", "Drift Market")
	var a = null
	var b = null
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		if rec.name == a_name:
			a = rec.pos
		elif rec.name == b_name:
			b = rec.pos
	return {"a": a, "b": b}

# ---------------------------------------------------------------------------
# Roster-pressure helpers -- what the floor checks and the hard cap compare
# against: pending arrivals + active/overdue members (haulers or freighters,
# per flag or overall).
# ---------------------------------------------------------------------------

func _flag_roster_pressure(flag: String) -> int:
	var n: int = 0
	for arrival in arrivals:
		if arrival.get("kind", "") == "hauler" and arrival.get("flag", "") == flag:
			n += 1
	for record_id in members.keys():
		var m: Dictionary = members[record_id]
		if m.get("flag", "") != flag:
			continue
		var st = m.get("state", -1)
		if st == MemberState.ACTIVE or st == MemberState.OVERDUE:
			n += 1
	return n

func _freighter_roster_pressure() -> int:
	var n: int = 0
	for arrival in arrivals:
		if arrival.get("kind", "") == "freighter":
			n += 1
	for record_id in freighters.keys():
		var st = freighters[record_id].get("state", -1)
		if st == FreighterState.ACTIVE or st == FreighterState.OVERDUE:
			n += 1
	return n

func _total_roster_pressure() -> int:
	var n: int = arrivals.size()
	for record_id in members.keys():
		var st = members[record_id].get("state", -1)
		if st == MemberState.ACTIVE or st == MemberState.OVERDUE:
			n += 1
	for record_id in freighters.keys():
		var st = freighters[record_id].get("state", -1)
		if st == FreighterState.ACTIVE or st == FreighterState.OVERDUE:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Helpers -- identical shape to PirateGuild's own (deliberate duplication,
# see the file header).
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

# Event line -- fires at ledger MILESTONES (adoption, arrival scheduled/
# spawned, OVERDUE, LOST, DEPARTED/DESTROYED), same toggle as the per-pass
# summary below.
func _event(msg: String) -> void:
	if DebugSettings and DebugSettings.get_choice("traffic_guild_log") == DebugSettings.TrafficGuildLog.ON:
		print("[TrafficGuild] ", msg)

func _log(cluster) -> void:
	if not (DebugSettings and DebugSettings.get_choice("traffic_guild_log") == DebugSettings.TrafficGuildLog.ON):
		return
	var active_h := 0
	var overdue_h := 0
	for record_id in members.keys():
		var st = members[record_id].get("state", -1)
		if st == MemberState.ACTIVE:
			active_h += 1
		elif st == MemberState.OVERDUE:
			overdue_h += 1
	var active_f := 0
	var overdue_f := 0
	for record_id in freighters.keys():
		var st = freighters[record_id].get("state", -1)
		if st == FreighterState.ACTIVE:
			active_f += 1
		elif st == FreighterState.OVERDUE:
			overdue_f += 1
	print("[TrafficGuild] haulers active=%d overdue=%d freighters active=%d overdue=%d pending=%d losses=%d replenishments=%d departed=%d destroyed=%d roster_pressure=%d/%d" %
		[active_h, overdue_h, active_f, overdue_f, arrivals.size(), losses, replenishments,
			freighters_departed, freighters_destroyed, _total_roster_pressure(), config.get("hard_cap", 999999)])
