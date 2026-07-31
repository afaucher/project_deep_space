extends Node

# HOW OFTEN DOES A BYSTANDER MIS-JUDGE ITS OWN STATION?
#
# design_ideas/2026-07-28-authority_scenarios.md section 5 -- the playtest's
# "a ship arrives flying the pirate flag, the station opens fire, and my ship
# issued a warrant against IT for sustained assault". Section 9 lists this as
# one of two things the doc still cannot claim: the MECHANISM is pinned
# (test_authority_scenarios B proves authority_flags does not protect on the
# gunfire path), but the FREQUENCY is not. How often does a real observer lose
# the race between "the station resolves JOLLY_ROGER and fires" and "my own
# datalink delivers me that transponder"? A unit test cannot answer that; it is
# a question about timing under realistic conditions.
#
# METHOD. The shooting is SCRIPTED, not left to station AI or weapon arcs. The
# question is about the WITNESS's judgment, so everything else is held still:
# the station delivers exactly STRAY_HITS_TO_HOSTILE hits at a controlled delay
# after the pirate appears, and we sweep that delay. Leaving it to a real
# station's AI would make every trial a measurement of turret cooldowns and
# firing arcs instead.
#
# WHAT IS SWEPT. Frames between the pirate spawning (transponder ON, flying
# JOLLY_ROGER) and the first shot. That is the window a bystander has to receive
# the pirate's transponder and resolve it HOSTILE -- which is the only thing
# that arms the assistance exemption and saves the station from being marked.
#
# WHAT IS REPORTED, per delay: how many bystanders had resolved the pirate by
# the time shooting started, and how many ended up holding an assault-grade
# warrant against their own station. Those two should be complements; where they
# are not, something other than the race is at work and that is worth knowing.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim port_defence

const Frigate = preload("res://scripts/ships/frigate.gd")
const ShipBase = preload("res://scripts/ships/ship.gd")
const Standing = preload("res://scripts/combat/standing.gd")

# Delay in physics frames between the pirate existing and the station opening
# fire. 0 = the station fires the instant it can; 240 = four seconds of grace.
const DELAYS := [0, 15, 30, 60, 120, 240]

# Bystanders per trial, parked at increasing range from the action. Range
# matters: a further bystander acquires the pirate later, so it should lose the
# race more often. If it does not, the race is not the mechanism.
const BYSTANDER_RANGES := [2000.0, 6000.0, 12000.0, 20000.0]

const PIRATE_POS := Vector2(3000, 0)
const STATION_POS := Vector2(0, 0)
const SETTLE_AFTER_SHOTS := 90   # frames for the witness fusion tick to land the verdict
const ACQUIRE_LIMIT := 900       # give the pirate's track time to exist at all

var main_node: Node = null
var spawned: Array = []
var rows: Array = []

func setup(main) -> void:
	main_node = main
	seed(20260730)  # reproducible: this sim's conclusion is a rate, not one run
	print("=== port_defence: how often a bystander marks its own station (authority_scenarios section 5) ===")
	print("    shooting is scripted; the swept variable is the grace period before the first shot")
	await _run_all()
	_report()

func _make_ship(n: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = Frigate.new()
	s.name = n
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	# Every hull here is parked and never accelerates, so Godot puts them to
	# sleep almost immediately. CLAUDE.md documents sleeping bodies going stale
	# in the physics broad phase; keep them awake so "nobody detected anybody"
	# cannot be an artifact of the harness.
	s.sleeping = false
	s.can_sleep = false
	spawned.append(s)
	return s

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	Standing.reset()

func _settle(frames: int) -> void:
	for i in range(frames):
		await main_node.get_tree().physics_frame

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

# Does `observer` hold an assault-grade (force-authorizing) warrant against
# `subject`? That is the failure we are counting -- not merely "went yellow".
func _holds_assault_against(observer, subject: Node) -> bool:
	var trk: String = ShipBase.track_id(subject.get_instance_id())
	var c: Dictionary = observer.active_contacts.get(trk, {})
	var claimed: String = observer.active_transponders.get(subject.get_instance_id(), {}).get("name", "")
	var want: String = Standing.subject_key(claimed, c.get("signature", {}))
	for key in observer.warrants:
		var w: Dictionary = observer.warrants[key]
		if w.get("status", "") != Standing.WARRANT_OPEN:
			continue
		if not Standing.authorizes_force(w.get("offense", "")):
			continue
		if Standing.warrant_subject_key(w) == want:
			return true
	return false

func _run_all() -> void:
	for delay in DELAYS:
		await _trial(delay)

func _trial(delay_frames: int) -> void:
	_cleanup()

	# The authority: flies the home flag, and is the hull that will shoot.
	var station = _make_ship("Station", 800, STATION_POS, ["TEAM_HOME"])
	station.set_transponder_flag(Standing.FLAG_DRIFT)
	station.warrant_authority = [Standing.FLAG_DRIFT]

	# Bystanders: ordinary civilians. They carry NO authority_flags, matching the
	# authored cluster (test_authority_scenarios E: 33 of 35 entities have none),
	# and they trust the pirate flag as an enemy by default like everyone else.
	# Scattered on DIFFERENT BEARINGS, not stacked along one axis. The first
	# version of this sim put them all at x=0 and only the nearest could see
	# anything: each hull's line-of-sight ray to the station passed straight
	# through the ships in front of it and was correctly rejected as blocked.
	# Sensor occlusion working as designed, ruining the experiment -- the
	# "nobody mis-filed" result it produced was pure vacuity.
	var bystanders: Array = []
	for i in range(BYSTANDER_RANGES.size()):
		var ang: float = deg_to_rad(40.0 + i * 75.0)
		var pos: Vector2 = STATION_POS + Vector2(BYSTANDER_RANGES[i], 0).rotated(ang)
		var b = _make_ship("Bystander%d" % i, 810 + i, pos, ["TEAM_CIV%d" % i])
		b.set_transponder_flag(Standing.FLAG_CIVILIAN)
		bystanders.append(b)

	# Let the scene settle so everyone holds tracks on the station BEFORE the
	# pirate exists -- otherwise a bystander that simply never saw the shooter
	# would count as "did not mis-file", which is the wrong reason to pass.
	await _settle(240)
	var saw_station: int = 0
	for i in range(bystanders.size()):
		var b = bystanders[i]
		var seen: bool = not _find_contact(b, station).is_empty()
		if seen:
			saw_station += 1


	# The pirate arrives, transponding, flying the black flag.
	var pirate = _make_ship("Pirate", 899, PIRATE_POS, ["TEAM_PIRATE"])
	pirate.set_transponder_flag(Standing.FLAG_PIRATE)

	# Wait until the pirate is at least TRACKED by someone, so delay 0 means
	# "fires as soon as there is anything to fire at" rather than "fires into an
	# empty scene before the body is even registered".
	var acquired := false
	for i in range(ACQUIRE_LIMIT):
		await main_node.get_tree().physics_frame
		if not _find_contact(station, pirate).is_empty():
			acquired = true
			break
	if not acquired:
		push_warning("[port_defence] delay=%d: station never acquired the pirate; trial skipped" % delay_frames)
		return

	await _settle(delay_frames)

	# Snapshot who had ALREADY resolved the pirate as HOSTILE at the moment the
	# first shot lands. This is the quantity the race is about.
	var resolved_at_shot: int = 0
	for b in bystanders:
		if _find_contact(b, pirate).get("standing", "") == Standing.HOSTILE:
			resolved_at_shot += 1

	# The station defends the port. Scripted, attributed to the station.
	for i in range(Standing.STRAY_HITS_TO_HOSTILE):
		pirate.take_damage(10.0, pirate.position + Vector2(-32, 0), Vector2(1, 0), "laser", station.get_instance_id())
		await _settle(4)

	await _settle(SETTLE_AFTER_SHOTS)

	var misfiled: int = 0
	var detail: Array = []
	for i in range(bystanders.size()):
		var bad: bool = _holds_assault_against(bystanders[i], station)
		if bad:
			misfiled += 1
		# Pair the verdict with whether this hull had RESOLVED the pirate, so the
		# result says WHY rather than just who. If mis-filing tracks "never
		# resolved", the relay race is the mechanism; if it does not, section 5's
		# explanation is wrong and needs replacing.
		var res: bool = _find_contact(bystanders[i], pirate).get("standing", "") == Standing.HOSTILE
		detail.append("%.0fu:%s/%s" % [BYSTANDER_RANGES[i], "MARKED" if bad else "ok",
			"resolved" if res else "UNRESOLVED"])

	rows.append({
		"delay": delay_frames,
		"delay_s": delay_frames / 60.0,
		"bystanders": bystanders.size(),
		"saw_station": saw_station,
		"resolved_at_shot": resolved_at_shot,
		"misfiled": misfiled,
		"detail": " ".join(detail),
	})
	print("  delay=%3d frames (%.2fs): resolved_at_shot=%d/%d  MARKED_OWN_STATION=%d/%d   [%s]" % [
		delay_frames, delay_frames / 60.0, resolved_at_shot, bystanders.size(),
		misfiled, bystanders.size(), " ".join(detail)])

func _report() -> void:
	_cleanup()
	print("\n=== port_defence results ===")
	print("%-8s %-8s %-18s %-22s %s" % ["delay", "secs", "resolved_at_shot", "marked_own_station", "by range"])
	for r in rows:
		print("%-8d %-8.2f %-18s %-22s %s" % [
			r["delay"], r["delay_s"],
			"%d/%d" % [r["resolved_at_shot"], r["bystanders"]],
			"%d/%d" % [r["misfiled"], r["bystanders"]],
			r["detail"]])

	var worst: int = 0
	var best: int = 99
	for r in rows:
		worst = max(worst, int(r["misfiled"]))
		best = min(best, int(r["misfiled"]))

	# res:// is writable from the editor build (and, as of 2026-07-29, from the
	# exported one too). Guarded anyway -- FileAccess returns null rather than
	# throwing, and a missing CSV must not look like a clean run.
	var path := "res://tactical_analysis/data/port_defence.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line("delay_frames,delay_seconds,bystanders,saw_station,resolved_at_shot,marked_own_station")
		for r in rows:
			f.store_line("%d,%.3f,%d,%d,%d,%d" % [
				r["delay"], r["delay_s"], r["bystanders"], r["saw_station"],
				r["resolved_at_shot"], r["misfiled"]])
		f.flush()
		f.close()
		print("\n  wrote ", path)
	else:
		printerr("  could not write ", path)

	print("\n  worst case: %d bystanders marked their own station; best case: %d" % [worst, best])
	if worst == 0:
		print("  VERDICT: the race was never lost at any delay tested -- section 5's frequency claim is NOT reproduced here.")
	elif best == 0:
		print("  VERDICT: the race is real and grace-dependent -- there is a delay above which it stops happening.")
	else:
		print("  VERDICT: bystanders mis-filed at EVERY delay tested, including the longest -- grace alone does not fix it.")
	get_tree().quit(0)
