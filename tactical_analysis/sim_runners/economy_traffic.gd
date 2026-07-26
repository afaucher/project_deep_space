extends Node

# M53c Phase C -- REAL acceptance evidence (implementation_plans/
# m53c_demand_routing.md "The soak sims" / "Phase C"). Where economy_soak.gd
# proves the bookkeeping and deliberately runs NOTHING that redistributes,
# this runner is the "after" picture: real hulls, real physics, real
# docking, driven by the M53c ship-side planner (RoutePlannerLeaf +
# RoutePlanner), against the REAL home cluster. Stations must be LIVE for
# docking to work at all, so this uses configure_full_sim() -- ClusterManager's
# own default policy, so no override is needed, just add the manager to the
# scene tree so real _physics_process ticks drive it (pirate_viability.gd's
# established pattern for a "real hulls flying" tactical sim).
#
# Three phases, in order (each solving a different problem -- see the consts):
#   1. SEED -- bins stated directly into a running-economy configuration
#      (producers holding sellable surplus, consumers at a working reserve),
#      because a flat world offers the planner no routes at all.
#   2. SETTLE_MINUTES -- real physics, fleet flying, results DISCARDED. Excludes
#      the promotion damage/self-repair transient from the measured rates.
#   3. SIM_MINUTES   -- the measurement window. Everything reported comes from
#      here.
#
# Fleet: NUM_HAULERS planner-driven civilian haulers (design doc's own "~8
# haulers" reference-capacity illustration), one starting near each of the
# cluster's 8 economically-active stations, EACH CARRYING ITS HOME STATION'S
# FLAG (3 Meridian, 5 home) so the fleet can actually lift flag-restricted
# cargo -- see the spawn loop's own comment. Each carries behavior =
# {"cargo": true} with NO "route" -- the M53c Phase C marker cluster_
# manager.gd's _attach_ai reads to attach build_civilian_job() +
# RoutePlannerLeaf with nothing pre-assigned, instead of a fixed authored
# lane. Deliberately does NOT add TrafficGuild (its own fixed-lane haulers
# still run the pre-Phase-C CargoRunLeaf, which the design doc itself notes
# "transfers nothing" -- they would fly and dock but move zero lots, adding
# sim cost with no economic effect) or PirateGuild (predation would confound
# a pure "do haulers keep every station fed" measurement, and isn't asked
# for here).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim economy_traffic
# Writes tactical_analysis/data/economy_traffic.csv (tracked summary) and
# tmp/economy_traffic_trace.csv (gitignored per-minute trace), following
# economy_soak.gd's own output convention exactly.

const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

# 30 game-minutes (a const so it can be raised, per the plan doc). A hauler
# round trip is 12-24 game-minutes, so this gives every hull 1-2 completed
# trips -- enough to read NET FLOW direction, the plan doc's explicit
# measurable (buffers are ~24h, so starvation itself would show nothing in a
# window this short).
const SIM_MINUTES := 30.0
const DT := 1.0 / 60.0
const NUM_HAULERS := 8
const SNAPSHOT_PERIOD := 30.0 # sim-seconds between min-stock/trace samples

# SEEDED STEADY STATE, replacing a 48-hour unattended warmup.
#
# The problem the warmup solved was real: a FRESH HomeCluster.build() starts
# every bin exactly AT target, which is SATISFIED -- no posting at all -- and an
# EXPORT only opens above surplus_line. A planner needing a matched
# EXPORT+IMPORT pair therefore finds literally zero routes on a flat world
# (confirmed via route_planner_log: "EXPORT open 0, IMPORT open 24" on every
# hauler, every check). The 30-minute measurement window is meant to observe
# hauler correction against STANDING imbalance, like a campaign a few hours old
# -- not to also wait for imbalance to accumulate.
#
# But simulating forward cannot produce that state once Commodity.BUFFER_HOURS
# shortened the buffers, because the two requirements now cross:
#   - a producer needs 0.35 x BUFFER_HOURS to clear surplus_line: ~2.1h for
#     ORE/REFINED/GOODS, ~8.4h for RARE
#   - a consumer starting at target empties in 0.5 x BUFFER_HOURS: 1.5h on
#     VOLATILES, 3h elsewhere
# So by the time producers can sell, consumers are dead. The 48h warmup made
# this vivid: it emptied EVERY consumer to zero, and because an empty bin's
# sinks consume nothing, net flow read 0.000 and the verdict scored those dead
# stations "ok" -- the run's failing-row count IMPROVED from 19 to 1 as the
# cluster collapsed.
#
# So state it directly instead of simulating toward it. Producers hold sellable
# surplus, consumers hold a normal reserve. Deterministic, instant, and immune
# to future BUFFER_HOURS changes -- which a tuned warmup duration would not be.
const SEED_PRODUCER_FRACTION := 0.92   # of capacity -- above surplus_line (0.85), so EXPORT is open
const SEED_CONSUMER_AT_TARGET := true  # a normal working reserve, neither desperate nor full

# SETTLE, distinct from the seed above and solving a different problem. The
# seed states the ECONOMY's starting configuration; this one runs REAL PHYSICS
# with the fleet already flying, and throws the results away.
#
# Why it has to exist: promoting the cluster produces a one-time burst of
# component damage (bodies resolving overlap at spawn), and stations
# self-repair by drawing REFINED (hull) and GOODS (systems) from their own
# bins -- ship.gd's _heal_components, which is stock-gated for stations. The
# first run to measure this read Deepcut GOODS at -35.6/hr and Ironhold GOODS
# at -74/hr against authored sink rates of 0.15 and a +1.50 SOURCE. The
# per-minute trace showed why: a steep drop for ~2 minutes, then dead flat at
# EXACTLY the authored rate (Deepcut -0.0013 per 30s = -0.15/hr; Ironhold
# rising +1.5/hr). The economy was correct the whole time -- a startup
# transient was being smeared across a 30-minute average by sampling
# initial_stock at frame zero.
#
# So: fly for SETTLE_MINUTES, then snapshot initial_stock and ZERO every
# counter (_begin_measurement below). Everything after that is steady state.
# 3.0 is ~1.5x the observed ~2-minute transient. This is deliberately NOT a
# fix to the economy or to repair -- both are behaving correctly; it is a fix
# to WHERE THE STOPWATCH STARTS.
const SETTLE_MINUTES := 3.0

var main_node: Node
var manager
var log_file: FileAccess
var frames: int = 0
var max_frames: int
var settle_frames: int
var _measuring: bool = false
var _snapshot_accum: float = 0.0

var stations: Array = [] # ClusterEntity records, the 8 economically-active stations
var hauler_recs: Array = []
var initial_stock: Dictionary = {} # station name -> commodity -> float
var min_stock: Dictionary = {} # station name -> commodity -> float
var delivery_counts: Dictionary = {} # station name -> commodity -> int
var _pending_watch: Dictionary = {} # hauler record id -> last-seen pending_delivery dict

# M53c Phase D -- attribution (design_ideas note: a repair spike must never
# again be mistaken for an economy failure, see the M53c Phase C traffic-sim
# finding that motivated this). net_flow alone conflates THREE independent
# stock movers: the economy proper (sinks/converters/sources, StationEconomy's
# own periodic tick), repair (Ship._heal_components drawing REFINED/GOODS to
# heal a docked hauler), and trade (a hauler's own cargo actually landing).
# Rather than hook StationEconomy/ship.gd internals, both are measured
# directly from signals this runner already has:
#   - repair_lots: reconstructed from each hauler's OWN per-component health
#     delta while docked, run back through StationEconomy's published
#     HULL_HP_PER_LOT/SYSTEM_HP_PER_LOT (exact inverse of _heal_components'
#     forward conversion -- see _track_repairs below).
#   - trade_lots: the SAME settle-detection delivery_counts already uses,
#     just summing the staged `amount` (signed by IMPORT/EXPORT direction)
#     instead of counting events.
# The economy-proper column is then the RESIDUAL: total net_flow minus trade
# minus repair -- exact given accurate trade/repair measurements, and it's
# this residual (not raw net_flow) that verdict/FAIL now keys on, so a
# station only fails when its ACTUAL economy is upside down, not when haulers
# are merely bleeding it via collision damage on approach.
var repair_lots: Dictionary = {}   # station name -> commodity -> non-negative lots consumed by repair
var trade_lots: Dictionary = {}    # station name -> commodity -> signed lots (+IMPORT into holder, -EXPORT out)
var _last_comp_health: Dictionary = {}   # hauler record id -> {component id -> health}

# M53c Phase C follow-up -- the FOURTH stock mover, and the one that poisoned
# the first run's economy column. ship.gd's _process_repairs heals a station's
# OWN components from its OWN bins, exactly like it heals a docked guest's --
# but the guest path was the only one being measured (repair_lots above tracks
# hauler components only), so every lot a station spent patching ITSELF landed
# in the economy residual and read as an economy failure. Measured the same
# honest way: per-component health deltas on the station's own hull, run back
# through StationEconomy's HP-per-lot constants. With this column present,
# net_flow = economy + repair + self_repair + trade is exact, and a station
# bleeding stock from collision damage says so in its own column instead of
# defaming its sinks.
var self_repair_lots: Dictionary = {}   # station name -> commodity -> non-negative lots consumed by self-repair
var _last_station_health: Dictionary = {}   # station name -> {component id -> health}

func setup(main) -> void:
	main_node = main
	print("=== M53c economy_traffic: %.0f game-minutes, %d planner-driven haulers, real docking ===" % [SIM_MINUTES, NUM_HAULERS])
	print("(bins seeded to a running-economy state -- see this file's SEED_* comment)")

	# Same reasoning as economy_soak.gd: this director prints one line per
	# STALLED converter per pass, which would dominate a run this long.
	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)

	var def = HomeCluster.build()
	manager = ClusterManager.new()
	manager.name = "ClusterManager"
	# SEED PHASE -- deliberately NOT added to the scene tree yet (economy_
	# soak.gd's exact technique): a bubble policy + a viewpoint far outside it
	# guarantees _reconcile() promotes NOTHING, so the single big tick() below
	# is pure bookkeeping, no physics, no live_parent needed at all.
	var warmup_pol := LivenessPolicy.new()
	warmup_pol.configure_bubble(1.0, 2.0)
	manager.policy = warmup_pol
	manager.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, manager)
	manager.directors.append(StationEconomy.new())
	_seed_steady_state(manager)

	# MEASUREMENT PHASE -- switch to the real full-sim policy (ClusterManager's
	# own default; a fresh LivenessPolicy set up explicitly here so the swap
	# is visible rather than relying on a constructor default) and only NOW
	# add the manager to the tree, so real _physics_process ticks + real
	# docking take over from here.
	var live_pol := LivenessPolicy.new()
	live_pol.configure_full_sim()
	manager.policy = live_pol
	main_node.add_child(manager) # stations must be LIVE for docking to work at all

	var station_recs: Array = []
	for rec in manager.records:
		if rec.kind == ClusterEntity.Kind.STATION and rec.stocks.has("self") and not rec.industry.is_empty():
			station_recs.append(rec)
	station_recs.sort_custom(func(a, b): return a.name < b.name)
	stations = station_recs
	print("Tracking %d stations with an authored economy; spawning %d haulers." % [stations.size(), NUM_HAULERS])

	var next_id := 9500
	for i in range(NUM_HAULERS):
		var home = stations[i % stations.size()]
		var angle: float = (TAU / float(NUM_HAULERS)) * float(i)
		var rec := ClusterEntity.new()
		rec.id = next_id
		next_id += 1
		rec.name = "Hauler %d" % i
		rec.hull_script = CargoShuttle
		rec.kind = ClusterEntity.Kind.TRAFFIC
		rec.is_static = false
		rec.pos = home.pos + Vector2(9000.0, 0.0).rotated(angle)
		# M53c Phase C follow-up -- each hauler carries ITS HOME STATION'S flag
		# and IFF rather than a hardcoded TEAM_DRIFT/FLAG_DRIFT for all eight.
		# The first run moved ZERO volatiles cluster-wide, and the reason was
		# not the planner: Coldreach is the only VOLATILES source and restricts
		# its EXPORT posting to Standing.FLAG_MERIDIAN (home_cluster.gd's
		# _economy_coldreach, the design doc's "natural first real case" for
		# export control). An all-Drift fleet is categorically ineligible to
		# lift the one commodity every station in the cluster consumes, so the
		# sim could not answer its own question. Deriving the flag from the
		# home station (3 of the 8 -- Coldreach, Halvorsen, Corvus -- are
		# Meridian) makes the fleet match the world instead of restating it,
		# and it stays correct on its own if a station ever changes hands.
		rec.iff_tags = home.iff_tags.duplicate(true)
		rec.transponder_flag = home.transponder_flag
		# M53c Phase C marker: cargo=true, NO "route" -- see this file's own
		# header and cluster_manager.gd's _attach_ai.
		rec.behavior = {"cargo": true}
		manager.records.append(rec)
		hauler_recs.append(rec)

	# Provisional -- every one of these is re-snapshotted/zeroed by
	# _begin_measurement() once the settle window closes. Populated here so the
	# settle window's own _snapshot()/_track_repairs() calls have somewhere to
	# write instead of erroring on a missing key.
	for rec in stations:
		initial_stock[rec.name] = {}
		min_stock[rec.name] = {}
		delivery_counts[rec.name] = {}
		repair_lots[rec.name] = {}
		trade_lots[rec.name] = {}
		self_repair_lots[rec.name] = {}
		for c in Commodity.ALL:
			var stock: float = rec.stocks["self"][c]["stock"]
			initial_stock[rec.name][c] = stock
			min_stock[rec.name][c] = stock
			delivery_counts[rec.name][c] = 0
			repair_lots[rec.name][c] = 0.0
			trade_lots[rec.name][c] = 0.0
			self_repair_lots[rec.name][c] = 0.0

	settle_frames = int(SETTLE_MINUTES * 60.0 * 60.0)
	max_frames = settle_frames + int(SIM_MINUTES * 60.0 * 60.0)

	DirAccess.make_dir_recursive_absolute("res://tactical_analysis/data")
	DirAccess.make_dir_recursive_absolute("res://tmp")
	log_file = FileAccess.open("res://tmp/economy_traffic_trace.csv", FileAccess.WRITE)
	if log_file == null:
		printerr("[SIM FAILED] could not open tmp/economy_traffic_trace.csv for writing")
		get_tree().quit(1)
		return
	log_file.store_line("sim_minutes,phase,station,flag,commodity,stock,capacity")

# Puts every authored bin into the state a cluster that has been running for a
# while would be in. Producers (a source, or a converter that outputs it) hold
# surplus above surplus_line so their EXPORT postings are open; anything merely
# consumed sits at target. A commodity the station has no mechanism for is left
# alone at its inert zero -- Drift Market has no ORE bin in any meaningful
# sense, and inventing stock for it would invent a market.
func _seed_steady_state(mgr) -> void:
	var seeded: int = 0
	for rec in mgr.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		if rec.industry.is_empty():
			continue
		for c in Commodity.ALL:
			var bin: Dictionary = rec.stocks["self"][c]
			var capacity: float = bin.get("capacity", 0.0)
			if capacity <= 0.0:
				continue
			if _can_produce(rec, c):
				bin["stock"] = capacity * SEED_PRODUCER_FRACTION
				seeded += 1
			elif _has_demand(rec, c) and SEED_CONSUMER_AT_TARGET:
				bin["stock"] = bin.get("target", capacity * 0.5)
				seeded += 1
	print("Seeded %d bins to a running-economy state." % seeded)

func _physics_process(_delta: float) -> void:
	if manager == null:
		return

	# Snapshot each live hauler's pending_delivery BEFORE the tick that may
	# settle it (docking_bay.gd's DOCKED-transition hook clears it the same
	# frame it fires serve_posting()) -- this is how delivery_counts is
	# measured: read-before/read-after across the tick that actually moves
	# the stock, attributed to whichever station the hauler is docked AT
	# right now (its docking_bay's host, resolved back to a station NAME via
	# that host's own cluster_record_ref -- the same weak-ref wiring Part 1's
	# delivery seam itself relies on).
	for rec in hauler_recs:
		if not rec.is_live():
			continue
		var node = rec.live_node
		var pd = node.get("pending_delivery")
		if pd is Dictionary and not pd.is_empty():
			_pending_watch[rec.id] = pd.duplicate(true)

	manager.tick(DT)
	frames += 1

	for rec in hauler_recs:
		if not rec.is_live() or not _pending_watch.has(rec.id):
			continue
		var node = rec.live_node
		var pd = node.get("pending_delivery")
		if pd is Dictionary and not pd.is_empty():
			continue # still pending (not yet DOCKED) -- keep watching
		var settled: Dictionary = _pending_watch[rec.id] # what we staged before the tick that just cleared it
		_pending_watch.erase(rec.id)
		var bay = node.get("docking_bay")
		if bay == null:
			continue # the docking attempt was abandoned before ever settling (shouldn't happen in steady flight, but stay defensive)
		var host = bay.get_parent()
		var host_rec = null
		var host_ref = host.get("cluster_record_ref") if host != null else null
		if host_ref != null:
			host_rec = host_ref.get_ref()
		if host_rec == null or not delivery_counts.has(host_rec.name):
			continue
		var acceptance: Dictionary = settled.get("acceptance", {})
		var commodity: String = acceptance.get("commodity", "")
		if delivery_counts[host_rec.name].has(commodity):
			delivery_counts[host_rec.name][commodity] += 1
			# Trade's own contribution to stock, signed like net_flow (+ into the
			# holder on IMPORT, - out of it on EXPORT). Uses the STAGED amount
			# (what the planner/route intended), the same value delivery_counts'
			# sibling column already keys off -- fulfill() itself clamps this
			# down only when the bin runs out of stock/capacity mid-transfer, a
			# rare edge this tactical attribution accepts as noise.
			var amount: float = settled.get("amount", 0.0)
			var signed_amount: float = amount if acceptance.get("direction", "") == "IMPORT" else -amount
			trade_lots[host_rec.name][commodity] += signed_amount

	_track_repairs()
	_track_self_repairs()

	# Settle window closes -- start the stopwatch (see SETTLE_MINUTES).
	if not _measuring and frames >= settle_frames:
		_begin_measurement()

	_snapshot_accum += DT
	if _snapshot_accum >= SNAPSHOT_PERIOD:
		_snapshot_accum -= SNAPSHOT_PERIOD
		_snapshot()

	if frames >= max_frames:
		_finish()

# The stopwatch. Re-baselines initial_stock to RIGHT NOW and zeroes every
# accumulator, so the spawn transient (component damage from bodies resolving
# overlap at promotion, and the station self-repair that pays for it) is
# excluded from the reported rates entirely rather than averaged into them.
# min_stock re-baselines too -- a settle-window trough is not a finding.
func _begin_measurement() -> void:
	_measuring = true
	for rec in stations:
		for c in Commodity.ALL:
			var stock: float = rec.stocks["self"][c]["stock"]
			initial_stock[rec.name][c] = stock
			min_stock[rec.name][c] = stock
			delivery_counts[rec.name][c] = 0
			repair_lots[rec.name][c] = 0.0
			trade_lots[rec.name][c] = 0.0
			self_repair_lots[rec.name][c] = 0.0
	print("--- settle window closed after %.0f game-min; measuring %.0f game-min from here ---" % [SETTLE_MINUTES, SIM_MINUTES])

# Reconstructs repair's stock draw from the HEALED side (each hauler's own
# per-component health), run back through StationEconomy's published
# HP-per-lot constants -- the exact inverse of Ship._heal_components' forward
# conversion (healed_hp = lots_taken * hp_per_lot), so this is not an
# approximation: whatever HP a component visibly gained this frame is exactly
# the lots StationEconomy.withdraw() pulled from the host's bin to pay for it.
# Attributed to whichever station the hauler's docking_bay currently belongs
# to (undocked/not-yet-captured haulers have no bay and are skipped) --
# self-repair (a station healing itself) never touches a hauler record, so it
# never shows up here, which is correct: this column is specifically "haulers
# draining an outpost via their own damage," the M53c Phase C finding.
func _track_repairs() -> void:
	for rec in hauler_recs:
		if not rec.is_live():
			continue
		var node = rec.live_node
		var prev: Dictionary = _last_comp_health.get(rec.id, {})
		var cur: Dictionary = {}
		var bay = node.get("docking_bay")
		var host_rec = null
		if bay != null:
			var host = bay.get_parent()
			var host_ref = host.get("cluster_record_ref") if host != null else null
			if host_ref != null:
				host_rec = host_ref.get_ref()
		for c in node.ship_components:
			var comp_id: String = c.get("id", "")
			var health: float = c.get("health", 0.0)
			cur[comp_id] = health
			if not prev.has(comp_id):
				continue # first frame we've seen this hauler/component -- nothing to diff yet
			var healed: float = health - prev[comp_id]
			if healed <= 0.0 or host_rec == null or not repair_lots.has(host_rec.name):
				continue # damage (or no change), or not docked anywhere trackable -- not a repair draw
			var commodity: String = Commodity.REFINED if c.get("type", "") == "hull" else Commodity.GOODS
			var hp_per_lot: float = StationEconomy.HULL_HP_PER_LOT if commodity == Commodity.REFINED else StationEconomy.SYSTEM_HP_PER_LOT
			if repair_lots[host_rec.name].has(commodity):
				repair_lots[host_rec.name][commodity] += healed / hp_per_lot
		_last_comp_health[rec.id] = cur

# The station-side twin of _track_repairs above -- same inverse-of-_heal_
# components arithmetic, but walking each STATION's own hull and attributing
# the draw to that station itself. Stations are only live during the physics
# phase (is_live() is false for anything the bubble hasn't promoted), so a
# dormant station simply contributes nothing, which is correct: ship.gd's
# _process_repairs is a live-node _physics_process, so a dormant station does
# not repair at all.
func _track_self_repairs() -> void:
	for rec in stations:
		if not rec.is_live():
			continue
		var node = rec.live_node
		var comps = node.get("ship_components")
		if not (comps is Array):
			continue # a non-Ship dockable -- no components to diff (defensive; every authored station is a Ship today)
		var prev: Dictionary = _last_station_health.get(rec.name, {})
		var cur: Dictionary = {}
		for c in comps:
			var comp_id: String = c.get("id", "")
			var health: float = c.get("health", 0.0)
			cur[comp_id] = health
			if not prev.has(comp_id):
				continue # first sighting -- nothing to diff yet
			var healed: float = health - prev[comp_id]
			if healed <= 0.0:
				continue # damage, or no change -- not a repair draw
			var commodity: String = Commodity.REFINED if c.get("type", "") == "hull" else Commodity.GOODS
			var hp_per_lot: float = StationEconomy.HULL_HP_PER_LOT if commodity == Commodity.REFINED else StationEconomy.SYSTEM_HP_PER_LOT
			if self_repair_lots[rec.name].has(commodity):
				self_repair_lots[rec.name][commodity] += healed / hp_per_lot
		_last_station_health[rec.name] = cur

func _snapshot() -> void:
	var minute: float = frames * DT / 60.0
	# `phase` marks which side of the settle boundary a row is on, so the trace
	# still SHOWS the spawn transient (it's the evidence that motivated the
	# settle window, and worth being able to re-read) without it being
	# mistakable for measured steady state.
	var phase: String = "measure" if _measuring else "settle"
	for rec in stations:
		for c in Commodity.ALL:
			var stock: float = rec.stocks["self"][c]["stock"]
			if _measuring:
				min_stock[rec.name][c] = min(min_stock[rec.name][c], stock)
			log_file.store_line("%.2f,%s,%s,%s,%s,%.3f,%.3f" % [minute, phase, rec.name, rec.transponder_flag, c, stock, rec.stocks["self"][c]["capacity"]])

func _can_produce(rec, commodity: String) -> bool:
	var sources: Dictionary = rec.industry.get("sources", {})
	if sources.get(commodity, 0.0) > 0.0:
		return true
	for conv in rec.industry.get("converters", []):
		if conv.get("out", {}).get(commodity, 0.0) > 0.0:
			return true
	return false

# Does this station WANT the commodity at all? A sink, or a converter that
# eats it. Distinguishes "starved" (wants it, has none) from "not applicable"
# (Drift Market has no ORE mechanism, so its zero stock is meaningless).
func _has_demand(rec, commodity: String) -> bool:
	if rec.industry.get("sinks", {}).get(commodity, 0.0) > 0.0:
		return true
	for conv in rec.industry.get("converters", []):
		if conv.get("in", {}).get(commodity, 0.0) > 0.0:
			return true
	return false

func _finish() -> void:
	log_file.flush()
	log_file.close()

	var sim_hours: float = SIM_MINUTES / 60.0
	var summary := FileAccess.open("res://tactical_analysis/data/economy_traffic.csv", FileAccess.WRITE)
	# cause -> Array of description strings. Grouping by CAUSE rather than
	# listing flat is the point of the split: each cause has a different owner
	# (routing, navigation, the planner), so the reader should be able to see
	# at a glance which system to go look at.
	var by_cause: Dictionary = {}
	if summary != null:
		summary.store_line("sim_minutes,settle_minutes,num_haulers,station,flag,commodity,net_flow_lots_per_hour,economy_lots_per_hour,repair_lots_per_hour,self_repair_lots_per_hour,trade_lots_per_hour,delivery_count,min_stock,can_produce_locally,verdict")

	print("\n=== Net flow (lots/hour, %d haulers over %.0f game-min, after a %.0f-min settle) ===" % [NUM_HAULERS, SIM_MINUTES, SETTLE_MINUTES])
	print("net_flow = economy (sinks/converters/sources) + repair (haulers healing while docked)")
	print("           + self_repair (the station patching its own hull) + trade (cargo actually moved)")
	print("station              flag         commodity    net/hr    economy/hr  repair/hr  self_rep/hr  trade/hr  deliveries  min_stock  verdict")
	for rec in stations:
		for c in Commodity.ALL:
			var final_stock: float = rec.stocks["self"][c]["stock"]
			var net_rate: float = (final_stock - initial_stock[rec.name][c]) / sim_hours
			# Both repair columns are non-negative magnitudes (lots CONSUMED);
			# their contribution to stock is always a drain, hence the minus.
			var repair_rate: float = -repair_lots[rec.name][c] / sim_hours
			var self_repair_rate: float = -self_repair_lots[rec.name][c] / sim_hours
			var trade_rate: float = trade_lots[rec.name][c] / sim_hours
			# Economy-proper is the RESIDUAL: whatever net_flow isn't already
			# explained by the two repair paths or trade. Exact given accurate
			# measurements (all three are measured directly, not estimated),
			# since net_flow = economy + repair + self_repair + trade by
			# construction -- those are the only four things that ever touch a
			# station's own stock.
			var economy_rate: float = net_rate - repair_rate - self_repair_rate - trade_rate
			var can_produce: bool = _can_produce(rec, c)
			var has_demand: bool = _has_demand(rec, c)
			# Same 2% -of-target convention economy_soak.gd uses: a bin at 2% of
			# target is functionally out, and an exact-zero test under-reports.
			var bin_target: float = rec.stocks["self"][c].get("target", 0.0)
			var starved: bool = bin_target > 0.0 and min_stock[rec.name][c] <= bin_target * 0.02
			var verdict: String = _verdict_for(net_rate, economy_rate, repair_rate + self_repair_rate, trade_rate, can_produce, starved, has_demand)
			if verdict != "ok":
				if not by_cause.has(verdict):
					by_cause[verdict] = []
				by_cause[verdict].append("%s/%s (net %.3f/hr; economy %.3f, repair %.3f, trade %.3f, %d deliveries)" % [
					rec.name, c, net_rate, economy_rate, repair_rate + self_repair_rate, trade_rate, delivery_counts[rec.name][c]])
			print("%-20s %-12s %-12s %-9.3f %-11.3f %-10.3f %-12.3f %-9.3f %-11d %-10.2f %s" % [
				rec.name, rec.transponder_flag, c, net_rate, economy_rate, repair_rate, self_repair_rate, trade_rate,
				delivery_counts[rec.name][c], min_stock[rec.name][c], verdict])
			if summary != null:
				summary.store_line("%d,%d,%d,%s,%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%.3f,%s,%s" % [
					int(SIM_MINUTES), int(SETTLE_MINUTES), NUM_HAULERS, rec.name, rec.transponder_flag, c,
					net_rate, economy_rate, repair_rate, self_repair_rate, trade_rate,
					delivery_counts[rec.name][c], min_stock[rec.name][c],
					"yes" if can_produce else "no", verdict])
	if summary != null:
		summary.flush()
		summary.close()

	var total_fails: int = 0
	for cause in by_cause.keys():
		total_fails += by_cause[cause].size()

	print("\n=== Verdict ===")
	if total_fails == 0:
		print("SERVED: no station is net-negative on a commodity it cannot produce itself.")
		print("\nSummary: tactical_analysis/data/economy_traffic.csv   Per-minute trace: tmp/economy_traffic_trace.csv")
		get_tree().quit(0)
	else:
		printerr(">>> [SIM FAILED] economy_traffic: %d station-commodity row(s) net-negative with no local production." % total_fails)
		for cause in by_cause.keys():
			printerr("  [%s] %s" % [cause, _CAUSE_HELP.get(cause, "")])
			for r in by_cause[cause]:
				printerr("    ", r)
		print("\nSummary: tactical_analysis/data/economy_traffic.csv   Per-minute trace: tmp/economy_traffic_trace.csv")
		get_tree().quit(1)

# One line per cause explaining WHO OWNS IT -- the reason the verdict names a
# cause at all instead of a flat FAIL.
const _CAUSE_HELP := {
	"UNSERVED": "nothing is hauling this at all -- routing/eligibility problem (is any ship eligible to lift it?)",
	"UNDERSUPPLIED": "haulers ARE delivering, just not fast enough -- fleet size or route economics",
	"OVER_EXPORTED": "the planner is hauling this AWAY faster than the station makes it -- pricing/urgency problem",
	"REPAIR_DRAIN": "repair is the dominant drain -- a NAVIGATION problem (hulls taking damage), not an economy one",
	"STARVED": "the bin hit EMPTY -- consumption has already stopped, so net flow reads 0.000 and means nothing",
}

# Keys on NET FLOW, not on the economy residual. The previous version keyed on
# economy_rate, which is negative BY DEFINITION for any station that consumes
# a commodity -- that is what a consumer IS -- so every consumer reported FAIL
# no matter how well it was being served. It flagged Ironhold/ORE and Refinery
# Prime/ORE as failures while both were running net POSITIVE (+2.289 and
# +2.520/hr) on healthy trade. Net flow is the honest measure of "is this
# station being kept alive"; the attribution columns then explain WHY it's
# negative, which is what the cause string below reports.
func _verdict_for(net_rate: float, economy_rate: float, repair_total: float, trade_rate: float, can_produce: bool, starved: bool, has_demand: bool) -> String:
	# STARVED is checked FIRST, ahead of every other branch including the
	# net_rate >= 0 early-out, because a flatlined station is the one case where
	# net flow reads HEALTHY while the station is dead. A bin at zero cannot be
	# drained further, so its sinks consume nothing, so net_rate is exactly
	# 0.000 -- and the old ordering returned "ok" for that. Observed when
	# Commodity.BUFFER_HOURS shortened the buffers: the sim's headline count
	# improved from 19 failing rows to 1 precisely BECAUSE most stations had
	# emptied completely and stopped registering. An instrument whose numbers
	# get better as the patient dies is worse than no instrument.
	if starved and has_demand and not can_produce:
		return "STARVED"
	if net_rate >= 0.0:
		return "ok"
	var repair_mag: float = absf(min(repair_total, 0.0))
	var economy_mag: float = absf(min(economy_rate, 0.0))
	var trade_mag: float = absf(min(trade_rate, 0.0))
	# REPAIR_DRAIN is checked BEFORE the can_produce exemption below: a station
	# bleeding stock to patch collision damage is a NAVIGATION finding, and it
	# is just as real on a station that makes the commodity itself. Letting the
	# exemption run first would silently mask exactly the failure the repair
	# columns were added to expose (e.g. Ironhold, which SOURCES goods, going
	# net-negative on goods because hulls keep hitting it).
	if repair_mag > economy_mag and repair_mag > trade_mag:
		return "REPAIR_DRAIN"
	if can_produce:
		return "ok" # drawing down its own production is the station's own business
	if trade_mag > economy_mag:
		return "OVER_EXPORTED"
	if trade_rate > 0.0:
		return "UNDERSUPPLIED"
	return "UNSERVED"
