extends RefCounted

# Shared scaffolding for the tactical/balance sims. These runners set the
# game's NUMBERS -- rates, catch rates, budgets, verdicts -- so a broken one
# does not fail loudly, it produces a plausible figure somebody then acts on.
# This file exists to make the ways they break structural rather than
# per-author.
#
# Extracted 2026-07-26 after pirate_effectiveness.gd copied ~80 lines of
# economy_traffic.gd's setup and silently omitted ONE of them (the clock, see
# advance() below). It ran 28 game-minutes and reported takes 0 / losses 0 /
# returned_empty 0, which reads exactly like "pirates are ineffective" and
# actually meant "no pirate was ever created". Nothing in the output said so.
#
# NOT a framework. Only the pieces that were already duplicated verbatim:
# world construction, the clock, the settle boundary, CSV append, and the
# liveness check that would have caught the above.
#
# Conventions these sims follow -- all four learned the hard way, see
# .agents/skills/sim-harness/SKILL.md for the full reasoning:
#   1. State budgets in TIME, never in ticks.
#   2. Give discrete-event rates a long enough horizon (30 vs 180 sim-minutes
#      moved a repair rate by 16x -- same code, same world).
#   3. Tally against AUTHORED rates, never measured ones: backpressure makes a
#      healthy producer read as a weak one.
#   4. Label harness-compressed config distinctly from campaign-real config.

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

const DT := 1.0 / 60.0

# Producers seeded above surplus_line (0.85) so EXPORT postings are already
# open; consumers at target. See economy_traffic.gd's own long note on why
# this is STATED rather than simulated toward -- with the current
# BUFFER_HOURS, producers need ~0.35x buffer to clear the surplus line while
# consumers empty in ~0.5x, so simulating forward kills every consumer before
# any producer can sell.
const SEED_PRODUCER_FRACTION := 0.92

# ---------------------------------------------------------------------------
# World construction
# ---------------------------------------------------------------------------

# Build the real home cluster, seed its economy to a running state with NOTHING
# promoted (pure bookkeeping, no physics), then switch to full-sim liveness and
# add it to the tree so docking and collisions are real.
#
# The seed phase runs against a bubble policy with the viewpoint far outside
# it, which guarantees _reconcile() promotes nothing -- that is what makes the
# single big economy tick free.
static func build_live_home_cluster(host: Node, directors: Array = []) -> Node:
	var def = HomeCluster.build()
	var manager = ClusterManager.new()
	manager.name = "ClusterManager"

	var warmup_pol := LivenessPolicy.new()
	warmup_pol.configure_bubble(1.0, 2.0)
	manager.policy = warmup_pol
	manager.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, manager)
	manager.directors.append(StationEconomy.new())
	seed_steady_state(manager)

	var live_pol := LivenessPolicy.new()
	live_pol.configure_full_sim()
	manager.policy = live_pol
	host.add_child(manager)

	for d in directors:
		manager.directors.append(d)
	return manager

# Every authored bin into the state a cluster that has been running a while
# would be in.
static func seed_steady_state(manager) -> void:
	for rec in manager.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		if rec.industry.is_empty():
			continue
		for c in Commodity.ALL:
			var bin: Dictionary = rec.stocks["self"][c]
			var capacity: float = bin.get("capacity", 0.0)
			if capacity <= 0.0:
				continue
			if can_produce(rec, c):
				bin["stock"] = capacity * SEED_PRODUCER_FRACTION
			elif has_demand(rec, c):
				bin["stock"] = bin.get("target", capacity * 0.5)

static func can_produce(rec, commodity: String) -> bool:
	var ind: Dictionary = rec.industry
	if ind.get("sources", {}).has(commodity):
		return true
	for conv in ind.get("converters", []):
		if conv.get("out", {}).has(commodity):
			return true
	return false

static func has_demand(rec, commodity: String) -> bool:
	var ind: Dictionary = rec.industry
	if ind.get("sinks", {}).has(commodity):
		return true
	for conv in ind.get("converters", []):
		if conv.get("in", {}).has(commodity):
			return true
	return false

# Stations with an authored economy, name-sorted for determinism.
static func economic_stations(manager) -> Array:
	var out: Array = []
	for rec in manager.records:
		if rec.kind == ClusterEntity.Kind.STATION and rec.stocks.has("self") and not rec.industry.is_empty():
			out.append(rec)
	out.sort_custom(func(a, b): return a.name < b.name)
	return out

# Planner-driven haulers ringed around the economic stations. Each inherits its
# home station's flag and IFF rather than a hardcoded home identity -- an
# all-one-flag fleet is categorically ineligible to lift eligibility-restricted
# commodities (Coldreach's VOLATILES), and a sim that cannot carry the goods
# cannot answer its own question.
static func spawn_planner_haulers(manager, count: int, first_id: int = 9500) -> Array:
	var stations: Array = economic_stations(manager)
	if stations.is_empty():
		return []
	var out: Array = []
	for i in range(count):
		var home = stations[i % stations.size()]
		var rec = ClusterEntity.new()
		rec.id = first_id + i
		rec.name = "Hauler %d" % i
		rec.hull_script = CargoShuttle
		rec.kind = ClusterEntity.Kind.TRAFFIC
		rec.is_static = false
		rec.pos = home.pos + Vector2(9000.0, 0.0).rotated((TAU / float(count)) * float(i))
		rec.iff_tags = home.iff_tags.duplicate(true)
		rec.transponder_flag = home.transponder_flag
		rec.behavior = {"cargo": true}   # no "route" -> RoutePlannerLeaf
		manager.records.append(rec)
		out.append(rec)
	return out

# ---------------------------------------------------------------------------
# The clock -- the thing that was silently missing
# ---------------------------------------------------------------------------

# ClusterManager._physics_process self-ticks ONLY when `viewpoint_node` is a
# live node ("in the live game the player ship is the viewpoint"). A headless
# sim sets a bare `viewpoint` Vector2 and no node, so a manager sitting in the
# tree ticks NOTHING: no directors, no economy, no guild, no traffic.
#
# Every sim must therefore drive the cluster itself. Routing that through the
# harness means no future runner can forget, which is exactly how
# pirate_effectiveness reported a confident, wrong zero.
class Clock:
	extends RefCounted
	# An inner class does not inherit the outer script's constants, so the
	# timestep lives here rather than reaching outward for it.
	const DT := 1.0 / 60.0
	var settle_frames: int
	var total_frames: int
	var frames: int = 0

	func _init(settle_minutes: float, measure_minutes: float) -> void:
		settle_frames = int(settle_minutes * 60.0 * 60.0)
		total_frames = settle_frames + int(measure_minutes * 60.0 * 60.0)

	# Advance one physics frame. Returns "settling" | "measure_start" | "measuring"
	# | "done". `measure_start` is the caller's cue to snapshot baselines and
	# zero counters -- promotion produces a burst of collision damage and early
	# churn that has nothing to do with what any of these sims measure.
	func advance(manager) -> String:
		manager.tick(DT)
		frames += 1
		if frames == settle_frames:
			return "measure_start"
		if frames >= total_frames:
			return "done"
		return "settling" if frames < settle_frames else "measuring"

# ---------------------------------------------------------------------------
# Liveness -- "did this sim actually simulate anything?"
# ---------------------------------------------------------------------------

# Every sim declares what must be NON-ZERO for its results to mean anything:
# members spawned, deliveries made, contacts acquired. A run that fails its
# own liveness check has produced NO DATA, and must say so instead of printing
# a 0% that reads like a finding.
#
# `checks` is {label: value}. Returns {"ok": bool, "dead": Array of labels}.
static func liveness(checks: Dictionary) -> Dictionary:
	var dead: Array = []
	for label in checks:
		if float(checks[label]) <= 0.0:
			dead.append(label)
	return {"ok": dead.is_empty(), "dead": dead}

static func print_liveness(result: Dictionary) -> void:
	if result["ok"]:
		return
	print("")
	print("  *** NO DATA -- this run did not simulate what it measures. ***")
	print("  Zero: %s" % str(result["dead"]))
	print("  Do NOT read the numbers below as a finding. Something upstream of")
	print("  the measurement did not run (a clock not driven, a director never")
	print("  ticked, a fleet that could not lift the goods).")

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Append one row, writing the header only when creating the file, so repeated
# invocations (a strategy sweep, a parameter sweep) build one table.
static func append_row(path: String, header: String, row: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var existed: bool = FileAccess.file_exists(path)
	var f = FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if f == null:
		printerr("[SIM] could not open ", path)
		return false
	if not existed:
		f.store_line(header)
	else:
		f.seek_end()
	f.store_line(row)
	f.close()   # store_line BUFFERS -- an unclosed file reads back as 0 lines
	return true
