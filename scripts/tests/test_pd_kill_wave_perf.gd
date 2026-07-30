extends Node

# M45c -- PD kill-wave perf regression guard.
#
# `tactical_analysis/sim_runners/perf_combat.gd` (a 3v3 frigate duel, NOT part
# of the regular gate -- see its own header comment for why) measured a real
# 278ms single-physics-frame spike in `pd_assign` (ship.gd's laser
# point-defense target-assignment loop) during a missile kill-wave. Root
# cause (confirmed by bisection this session, see
# implementation_plans/m45c_pd_kill_wave_perf.md's Findings): `ship.gd`'s
# `COMBAT_DEBUG` const had silently drifted from `false` to `true` (an
# unrelated commit, 2026-07-07) -- with it on, every successful PD shot's
# damage cascade (take_damage -> [Damage]/[Collision]/reactor-overheat/[PD]
# prints) runs INSIDE pd_assign's PerfProbe window, and during a kill-wave's
# many-simultaneous-kills moment the console/stdout I/O from dozens of prints
# in one frame -- not the assignment loop's own algorithm -- dominated the
# measured cost by roughly two orders of magnitude. The fix was restoring
# `const COMBAT_DEBUG := false`; `execute_fire()`'s intersect_shape query
# (hypothesis 1) and the assignment loop's own multi-pass shape (hypothesis
# 2) were bisected out as negligible contributors at this scenario's scale.
#
# This is a BOUNDED version of that scenario (10s, not perf_combat.gd's 25s)
# so it's cheap enough to live in the regular scripts/tests/ gate. It:
#   1. Asserts `ship.gd`'s COMBAT_DEBUG stays false -- the precise, cheap
#      guard against the EXACT regression that happened (silently flipping
#      this one flag back on).
#   2. Asserts pd_assign/weapons_pd PerfProbe max_frame_us stay under a wide
#      ceiling -- a broader guard against ANY future cost spike in this path
#      shaped the same way, not just this one flag.
# Budgets calibrated against this session's standalone measurements (see the
# Findings section of the plan doc): post-fix pd_assign max_frame_us
# 496-2536us / weapons_pd max_frame_us 1643-2816us across 5 seeds; pre-fix
# (COMBAT_DEBUG=true, same seeds) pd_assign 17441-26152us / weapons_pd
# 21594-26364us. Budgets set at roughly 3x the post-fix ceiling (same "~3x
# the fixed value" margin test_collision_perf.gd uses), which still leaves
# more than 2x headroom below the pre-fix floor -- a real regression fails
# loudly, normal physics-timing jitter (CLAUDE.md: 2D physics isn't
# bit-deterministic run-to-run) and build.ps1's parallel-run CPU contention
# (see test_perf_baseline.gd's own note on why ITS budget had to widen
# in-gate) should not.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_pd_kill_wave_perf
# (main.gd's _run_test seeds the RNG at 20260708 for every --run-test invocation.)

const Frigate = preload("res://scripts/ships/frigate.gd")
const ShipScript = preload("res://scripts/ships/ship.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const SHIPS_PER_SIDE := 3
const START_RANGE := 8000.0
const MEASURE_SECONDS := 10.0
const MEASURE_FRAMES := int(MEASURE_SECONDS * 60.0)

const PD_ASSIGN_MAX_US := 8000
const WEAPONS_PD_MAX_US := 10000

var main_node: Node = null
var frame: int = 0
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("=== M45c PD kill-wave perf guard (%d v %d frigates, %.0fs) ===" % [SHIPS_PER_SIDE, SHIPS_PER_SIDE, MEASURE_SECONDS])

	# The precise regression guard: this is the actual line that caused the
	# spike (see header comment). Check it directly, independent of the
	# timing assertions below, so a future regression fails with an
	# unambiguous message instead of "some perf number went up."
	_assert(ShipScript.COMBAT_DEBUG == false,
		"Ship.COMBAT_DEBUG must stay false -- flipping it true floods pd_assign's PerfProbe window with per-shot/per-hit console prints during a kill-wave (see this file's header comment)")

	for i in range(SHIPS_PER_SIDE):
		var a = Frigate.new()
		a.name = "TeamA_%d" % i
		a.owner_id = 100 + i
		a.iff_tags = ["TEAM_A"]
		a.position = Vector2(0, i * 300.0)
		a.rotation = 0.0
		main_node.add_child(a)
		a.set_transponder_flag(Standing.FLAG_PIRATE)
		a.add_child(AITreeFactory.build_default())

		var b = Frigate.new()
		b.name = "TeamB_%d" % i
		b.owner_id = 200 + i
		b.iff_tags = ["TEAM_B"]
		b.position = Vector2(START_RANGE, i * 300.0)
		b.rotation = PI
		main_node.add_child(b)
		b.set_transponder_flag(Standing.FLAG_PIRATE)
		b.add_child(AITreeFactory.build_default())

	PerfProbe.enabled = true

func _physics_process(_delta: float) -> void:
	if frame >= MEASURE_FRAMES + 1:
		return
	frame += 1
	if frame >= MEASURE_FRAMES:
		_finish()

func _finish() -> void:
	frame = MEASURE_FRAMES + 1  # stop _physics_process from doing more work

	var rep: Dictionary = PerfProbe.report(MEASURE_FRAMES)
	var pd_assign_max: int = int(rep.get("pd_assign", {}).get("max_frame_us", 0))
	var weapons_pd_max: int = int(rep.get("weapons_pd", {}).get("max_frame_us", 0))

	print("\n=== PerfProbe: pd_assign / weapons_pd max_frame_us ===")
	print("  pd_assign max_frame_us=%d (budget <%d)" % [pd_assign_max, PD_ASSIGN_MAX_US])
	print("  weapons_pd max_frame_us=%d (budget <%d)" % [weapons_pd_max, WEAPONS_PD_MAX_US])

	PerfProbe.print_counters(MEASURE_FRAMES)

	var csv_path := "res://tactical_analysis/data/pd_kill_wave_perf.csv"
	PerfProbe.report_csv(csv_path, MEASURE_FRAMES)
	print("  wrote ", csv_path)

	PerfProbe.enabled = false

	_assert(pd_assign_max < PD_ASSIGN_MAX_US,
		"pd_assign max_frame_us (%d) stays under the %dus budget" % [pd_assign_max, PD_ASSIGN_MAX_US])
	_assert(weapons_pd_max < WEAPONS_PD_MAX_US,
		"weapons_pd max_frame_us (%d) stays under the %dus budget" % [weapons_pd_max, WEAPONS_PD_MAX_US])

	if failures.is_empty():
		print(">>> [TEST PASSED] test_pd_kill_wave_perf <<<")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("  FAIL: ", msg)
		printerr(">>> [TEST FAILED] test_pd_kill_wave_perf <<<")
		get_tree().quit(1)
