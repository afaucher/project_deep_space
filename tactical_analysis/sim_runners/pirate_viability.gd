extends Node

# M52a -- pirate viability measurement (implementation_plans/m52a_pirate_
# viability.md). Drives the REAL home cluster (HomeCluster.build + the loader:
# stations, the 7-beacon road, both cargo lanes, patrols) plus the pirate
# guild, headless and manually ticked, then reports whether pirates actually
# take anything. The campaign showed takes_total=0; this is the rerunnable
# instrument the fixes are calibrated against.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim pirate_viability
# Writes tactical_analysis/data/pirate_viability.csv (periodic guild-state
# snapshots) and prints a final summary + a floor check (takes >= 1). The
# per-attempt abort causes / comply-run decisions are in the job_log lines
# also emitted to stdout (both pirate logs default ON, M52a).

const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")

# Accelerated CADENCE + CONCURRENCY only (not difficulty): shrink the arrival
# window/policy period and raise the cap so many hunts happen in a short run.
# Patience, ranges, hull speeds -- everything the fix is measuring -- stay at
# their real values.
const FAST_CONFIG := {
	"policy_period": 2.0,
	"arrival_window": [8.0, 16.0],
	"presumed_lost_delay": 45.0,
	"base_cap": 3,
	"max_cap": 3,
}

# Isolated open-space trade runs, each well clear of every station/beacon/
# wormhole (so the guild's hazard-avoidance PREFERS them) AND far from each
# OTHER (> witness range 6km apart) so each victim is genuinely ALONE on its
# own lane -- otherwise the shuttles witness each other and every robbery
# aborts on third_party before the victim can even decide. This supplies the
# "traffic to rob out in the dark" densely enough to MEASURE the take rate;
# the convergence of a lurking pirate onto a LONE complying victim is exactly
# the H1 question (does the take land once they're in the same place). Each
# center gets one shuttle back-and-forth on a short segment.
const TRADE_CENTERS := [
	Vector2(80000, -60000), Vector2(130000, -75000),
	Vector2(55000, -30000), Vector2(150000, -35000),
]
const TRADE_HALF := Vector2(9000, 0)  # short segment: frequent passes past a mid-lane lurk

# Long enough for the full loop to close: a take (8s hold) then a dark exfil
# back to the distant wormhole (~215k units at 1000 u/s ~= 3.5 min) plus the
# presumed_lost_delay before the guild scores it CASHED_OUT.
const SIM_MINUTES := 12.0
const DT := 1.0 / 60.0

var main_node: Node
var manager
var guild
var log_file: FileAccess
var frames: int = 0
var max_frames: int = int(SIM_MINUTES * 60.0 * 60.0)
var _snapshot_accum: float = 0.0

func setup(main) -> void:
	main_node = main
	print("Starting Tactical Sim: Pirate Viability (", SIM_MINUTES, " sim-min)")

	# Pirate logs on so the career (attempt aborts, comply/run) is in the log.
	DebugSettings.set_choice("pirate_guild_log", DebugSettings.PirateGuildLog.ON)
	DebugSettings.set_choice("job_log", DebugSettings.JobLog.ON)

	var def = HomeCluster.build()
	manager = ClusterManager.new()
	manager.name = "ClusterManager"
	main_node.add_child(manager)
	ClusterLoader.load_into(def, manager)  # no story overlay needed for the sim

	# Remove the home cluster's own two cargo lanes (Mule on the beacon road,
	# Ore Barge to Coldreach): they're sparse (one slow shuttle each on huge
	# hub lanes) and only DILUTE the guild's lane-point selection away from the
	# controlled traders below. The stations, the 7-beacon road, and the
	# patrols stay -- so pirates still hunt inside the real hostile environment;
	# only the cargo POOL is swapped for a measurable one.
	var kept: Array = []
	for r in manager.records:
		if r.id == 700 or r.id == 701:
			continue
		kept.append(r)
	manager.records = kept

	# One lone cargo shuttle per isolated trade lane (see TRADE_CENTERS).
	for i in range(TRADE_CENTERS.size()):
		var a: Vector2 = TRADE_CENTERS[i] - TRADE_HALF
		var b: Vector2 = TRADE_CENTERS[i] + TRADE_HALF
		var rec := ClusterEntity.new()
		rec.id = 800 + i
		rec.name = "Trader %d" % i
		rec.hull_script = CargoShuttle
		rec.kind = ClusterEntity.Kind.TRAFFIC
		rec.is_static = false
		rec.pos = TRADE_CENTERS[i]
		rec.iff_tags = ["TEAM_PLAYER"]
		rec.transponder_flag = Standing.FLAG_DRIFT
		rec.behavior = {"route": [a, b], "loop": true, "cargo": true}
		manager.records.append(rec)

	guild = PirateGuild.new(FAST_CONFIG)
	manager.directors.append(guild)

	log_file = FileAccess.open("res://tactical_analysis/data/pirate_viability.csv", FileAccess.WRITE)
	if log_file == null:
		printerr("Failed to open CSV for writing.")
		get_tree().quit(1)
		return
	log_file.store_line("sim_seconds,active,overdue,pending,cap,takes_total,losses,returned_empty,backoff")

func _physics_process(_delta: float) -> void:
	if manager == null:
		return
	manager.tick(DT)
	frames += 1

	_snapshot_accum += DT
	if _snapshot_accum >= 5.0:
		_snapshot_accum -= 5.0
		_snapshot()

	if frames >= max_frames:
		_finish()

func _snapshot() -> void:
	var active := 0
	var overdue := 0
	for rid in guild.members.keys():
		var st = guild.members[rid].get("state", -1)
		if st == PirateGuild.MemberState.ACTIVE:
			active += 1
		elif st == PirateGuild.MemberState.OVERDUE:
			overdue += 1
	log_file.store_line("%.0f,%d,%d,%d,%d,%d,%d,%d,%.1f" % [
		frames * DT, active, overdue, guild.arrivals.size(), guild.cap,
		guild.takes_total, guild.losses, guild.get("returned_empty"),
		guild.get("backoff_factor"),
	])

# Robberies LANDED = cashed-out takes + loot already aboard members still in
# transit (a take counts the moment the loot is aboard, not only after the
# long dark exfil closes) -- the direct answer to "do pirates succeed".
func _robberies() -> int:
	var n: int = guild.takes_total
	for rid in guild.members.keys():
		var m: Dictionary = guild.members[rid]
		var st = m.get("state", -1)
		if st == PirateGuild.MemberState.ACTIVE or st == PirateGuild.MemberState.OVERDUE:
			n += m.get("last_loot_takes", 0)
	return n

func _finish() -> void:
	log_file.flush()
	log_file.close()
	var robberies: int = _robberies()
	print("=== Pirate Viability Summary (", SIM_MINUTES, " sim-min) ===")
	print("  robberies_landed = ", robberies, "  (loot aboard + cashed)")
	print("  takes_total(cashed) = ", guild.takes_total)
	print("  losses           = ", guild.losses)
	print("  returned_empty   = ", guild.get("returned_empty"))
	print("  final cap        = ", guild.cap)
	if robberies >= 1:
		print(">>> [SIM PASSED] pirate_viability (robberies_landed=%d >= 1) <<<" % robberies)
		get_tree().quit(0)
	else:
		printerr(">>> [SIM FAILED] pirate_viability (0 robberies -- pirates still never succeed) <<<")
		get_tree().quit(1)
