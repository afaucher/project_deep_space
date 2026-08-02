extends Node

# M58 acceptance -- two-tier transport, the fog, and notarization
# (implementation_plans/m57_m61_information_economy_roadmap.md "M58",
# design_ideas/mail_network.md).
#
# The four things that must be true, in rising order of how much they matter:
#
#   1. The mailbag merges as `max` on BOTH holder clocks, so holders converge
#      regardless of who syncs with whom or in what order -- and a merge can
#      only ever ADVANCE a holder. Docking at a quiet outpost must not make a
#      hauler forget what it witnessed.
#   2. `confirmed_at` moves independently of `version`. "I checked and nothing
#      had changed" has to be representable, or a courier's run only pays when
#      there happens to be news.
#   3. READS ARE CLAMPED TO THE DELIVERED VERSION. Content is global -- every
#      log sits on its own record, reachable in principle -- and the clamp is
#      the entire fog. A source never heard of is invisible; a source heard of
#      at v3 shows exactly three entries even though five exist.
#   4. Information has a POSITION AND A VELOCITY. Two stations disagree, and go
#      on disagreeing, until a hull physically carries news between them. That
#      is the headline behaviour of this milestone and section [5] is its test.
#
# Plus notarization, which is what finally makes piracy enforceable: a robbed
# civilian's warrant is sealed (origin_flag "", relay refuses it), so an
# authority must re-issue it under its own flag -- and only for its own flag.
#
# Section [6] docks a ship FOR REAL through DockingBay rather than calling the
# exchange directly, because the wiring is where this milestone actually broke
# once: a preload added to docking_bay.gd re-entered the ship.gd <->
# docking_bay.gd class cycle, which does not fail a test, it HANGS it.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_mail_network

const Mailbag = preload("res://scripts/mail/mailbag.gd")
const Incident = preload("res://scripts/mail/incident.gd")
const SourceLog = preload("res://scripts/mail/source_log.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

# Mailbag.read_incidents only needs `.records`, so a stand-in keeps these
# assertions away from ClusterManager's promote/demote machinery.
class FakeCluster extends RefCounted:
	var records: Array = []

var main_node: Node = null
var failures: Array = []
var finished: bool = false
var _next_rec_id: int = 5000

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# A Ship wired to a fresh cluster record, so it has a source_id, a record-backed
# mailbag, and a record-backed incident log -- the promoted-hull case.
#
# `pos` matters and is not cosmetic: every hull in this file shares one scene,
# and leaving them all at the origin buries section [6]'s DockingBay inside a
# pile of other stations, so nothing ever settles into DOCKED. Each section gets
# its own patch of empty space.
func _make_ship(script, nm: String, flag: String, authority: Array = [],
		pos: Vector2 = Vector2.ZERO) -> Array:
	var s = script.new()
	s.name = nm
	s.owner_id = 90
	s.position = pos
	main_node.add_child(s)
	s.set_transponder_flag(flag)
	s.warrant_authority = authority
	var rec = ClusterEntity.new()
	rec.id = _next_rec_id
	_next_rec_id += 1
	s.cluster_record_ref = weakref(rec)
	return [s, rec]

func setup(main) -> void:
	main_node = main
	print("Starting Mail Network (M58) Tests")
	_test_merge_algebra()
	_test_confirmed_at_moves_alone()
	_test_reads_are_clamped()
	_test_exchange_policy()
	_test_news_travels_at_hull_speed()
	await _test_real_dock_wiring()
	_test_notarization()
	_finalize()

# --- 1. Convergence, and the anti-erase property. ---------------------------
func _test_merge_algebra() -> void:
	print("[1] mailbag merges as max on both clocks")
	var a := {1: {"version": 5, "confirmed_at": 100}}
	var b := {1: {"version": 3, "confirmed_at": 400}, 2: {"version": 9, "confirmed_at": 50}}

	var ab: Dictionary = Mailbag.merge(a.duplicate(true), b)
	var ba: Dictionary = Mailbag.merge(b.duplicate(true), a)
	_assert(ab == ba, "merge is COMMUTATIVE (%s vs %s)" % [str(ab), str(ba)])
	_assert(Mailbag.version_of(ab, 1) == 5, "version takes the max (5, not 3)")
	_assert(Mailbag.confirmed_at_of(ab, 1) == 400, "confirmed_at takes the max independently (400)")
	_assert(Mailbag.version_of(ab, 2) == 9, "an unheard-of source is learned wholesale")

	var twice: Dictionary = Mailbag.merge(ab.duplicate(true), b)
	_assert(twice == ab, "merge is IDEMPOTENT -- re-syncing changes nothing")

	# The property that killed the snapshot design: a poorer view cannot erase.
	var rich := {1: {"version": 12, "confirmed_at": 900}}
	var poor := {1: {"version": 2, "confirmed_at": 3}}
	var after: Dictionary = Mailbag.merge(rich.duplicate(true), poor)
	_assert(Mailbag.version_of(after, 1) == 12 and Mailbag.confirmed_at_of(after, 1) == 900,
		"merging a POORER view is a no-op -- docking at a quiet port erases nothing")

	# sync_direct is clamped upward too: touching a source cannot walk a holder
	# back to it, even if it heard something newer third-hand.
	var bag := {7: {"version": 20, "confirmed_at": 500}}
	Mailbag.sync_direct(bag, 7, 4, 600)
	_assert(Mailbag.version_of(bag, 7) == 20,
		"sync_direct never lowers a version heard third-hand")
	_assert(Mailbag.confirmed_at_of(bag, 7) == 600, "but it does refresh confidence")

# --- 2. Version measures content; confirmed_at measures uncertainty. --------
func _test_confirmed_at_moves_alone() -> void:
	print("[2] 'I checked and nothing had changed' is representable")
	var bag := {}
	Mailbag.sync_direct(bag, 3, 12, 1000)
	var before_v: int = Mailbag.version_of(bag, 3)
	Mailbag.sync_direct(bag, 3, 12, 5000) # quiet source: same seq, later visit
	_assert(Mailbag.version_of(bag, 3) == before_v, "version did NOT move (nothing happened there)")
	_assert(Mailbag.confirmed_at_of(bag, 3) == 5000, "confirmed_at DID move -- uncertainty collapsed")
	_assert(Mailbag.has_news_for(bag, {3: {"version": 12, "confirmed_at": 1000}}),
		"and that counts as news for a holder with the same version but staler confidence")

# --- 3. THE FOG. ------------------------------------------------------------
func _test_reads_are_clamped() -> void:
	print("[3] reads are clamped to the delivered version")
	var cluster := FakeCluster.new()
	var src_a := ClusterEntity.new(); src_a.id = 11
	var src_b := ClusterEntity.new(); src_b.id = 22
	for i in range(5):
		src_a.incident_seq += 1
		SourceLog.append_entry(src_a.incident_log, src_a.incident_seq,
			Incident.make(Incident.KIND_ARMED_ROBBERY, "P%d" % i, "PIRATE", Vector2(i, 0), "A"), 100)
	src_b.incident_seq += 1
	SourceLog.append_entry(src_b.incident_log, src_b.incident_seq,
		Incident.make(Incident.KIND_OVERDUE, "Cluster_1", "DRIFT", Vector2(9, 9), "B"), 100)
	cluster.records = [src_a, src_b]

	var bag := {}
	_assert(Mailbag.read_incidents(cluster, bag).is_empty(),
		"a holder that has heard nothing reads NOTHING, even though every log is right there")

	Mailbag.sync_direct(bag, 11, 3, 1)
	var seen: Array = Mailbag.read_incidents(cluster, bag)
	_assert(seen.size() == 3, "delivered v3 of a 5-entry log reads exactly 3 (got %d)" % seen.size())
	_assert(not Mailbag.knows(bag, 22), "source B was never heard of...")
	var from_b := 0
	for e in seen:
		if e.get("source_id", -1) == 22:
			from_b += 1
	_assert(from_b == 0, "...so B contributes nothing, though its log exists and is reachable")
	_assert(seen[0].has("source_confirmed_at"),
		"reads carry how stale that source is, not just what it said")

	Mailbag.sync_direct(bag, 11, 5, 2)
	_assert(Mailbag.read_incidents(cluster, bag).size() == 5, "advancing the version reveals the rest")

# --- 4. Receive freely, give deliberately. ----------------------------------
func _test_exchange_policy() -> void:
	print("[4] the dock exchange is asymmetric")
	var st = _make_ship(MediumStation, "DriftPort", Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT], Vector2(0, 0))
	var kin = _make_ship(CargoShuttle, "DriftHauler", Standing.FLAG_DRIFT, [], Vector2(0, 4000))
	var foreign = _make_ship(CargoShuttle, "MeridianHauler", Standing.FLAG_MERIDIAN, [], Vector2(0, 8000))

	# Give each hull something only it knows.
	st[0].record_incident(Incident.KIND_OVERDUE, "Cluster_1", Standing.FLAG_DRIFT, Vector2(1, 1))
	kin[0].record_incident(Incident.KIND_ARMED_ROBBERY, "Raider", "PIRATE", Vector2(2, 2))
	foreign[0].record_incident(Incident.KIND_ARMED_ROBBERY, "Other", "PIRATE", Vector2(3, 3))

	st[0].exchange_mail_on_dock(foreign[0])
	_assert(Mailbag.version_of(foreign[0].get_mailbag(), st[1].id) >= 1,
		"a FOREIGN hull still RECEIVES -- a public board cannot be un-seen")
	_assert(Mailbag.version_of(st[0].get_mailbag(), foreign[1].id) == 0,
		"but the station learns nothing from it -- giving is deliberate")

	st[0].exchange_mail_on_dock(kin[0])
	_assert(Mailbag.version_of(kin[0].get_mailbag(), st[1].id) >= 1, "own-flag hull receives")
	_assert(Mailbag.version_of(st[0].get_mailbag(), kin[1].id) >= 1,
		"and GIVES, because it shares the port's flag")

# --- 5. Information has a position and a velocity. --------------------------
func _test_news_travels_at_hull_speed() -> void:
	print("[5] two ports disagree until a hull carries news between them")
	var port_a = _make_ship(MediumStation, "PortA", Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT], Vector2(200000, 0))
	var port_b = _make_ship(MediumStation, "PortB", Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT], Vector2(200000, 20000))
	var courier = _make_ship(CargoShuttle, "Courier", Standing.FLAG_DRIFT, [], Vector2(200000, 40000))

	port_a[0].record_incident(Incident.KIND_ARMED_ROBBERY, "Raider", "PIRATE", Vector2(500, 500))

	_assert(Mailbag.version_of(port_b[0].get_mailbag(), port_a[1].id) == 0,
		"PortB starts knowing nothing of PortA -- they are far apart and nobody has flown between")

	port_a[0].exchange_mail_on_dock(courier[0])
	_assert(Mailbag.version_of(courier[0].get_mailbag(), port_a[1].id) >= 1, "the courier loads up at A")
	_assert(Mailbag.version_of(port_b[0].get_mailbag(), port_a[1].id) == 0,
		"and B STILL knows nothing -- the news is in flight, not broadcast")

	port_b[0].exchange_mail_on_dock(courier[0])
	_assert(Mailbag.version_of(port_b[0].get_mailbag(), port_a[1].id) >= 1,
		"only on arrival does B learn what A knew -- carried, at hull speed")

# --- 6. The wiring, through a real dock. ------------------------------------
func _test_real_dock_wiring() -> void:
	print("[6] a REAL DockingBay dock runs the exchange")
	var st = _make_ship(MediumStation, "WiredPort", Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT], Vector2(400000, 0))
	st[0].record_incident(Incident.KIND_OVERDUE, "Cluster_7", Standing.FLAG_DRIFT, Vector2(4, 4))

	var bays: Array = []
	for c in st[0].get_children():
		if c is DockingBay:
			bays.append(c)
	if bays.is_empty():
		_assert(false, "station should grow at least one DockingBay")
		return
	var bay = bays[0]

	var hauler = _make_ship(CargoShuttle, "WiredHauler", Standing.FLAG_DRIFT, [], Vector2(400000, 5000))
	var fwd: Vector2 = Vector2.RIGHT.rotated(bay.global_rotation)
	hauler[0].position = bay.global_position + fwd * 200.0
	st[0].issue_docking_grant(hauler[0])
	hauler[0].wants_dock = true

	var frames := 0
	while frames < 1800 and bay.state != DockingBay.State.DOCKED:
		await main_node.get_tree().physics_frame
		frames += 1
	_assert(bay.state == DockingBay.State.DOCKED, "the hauler actually docked (%d frames)" % frames)
	_assert(Mailbag.version_of(hauler[0].get_mailbag(), st[1].id) >= 1,
		"and the DOCKED transition ran the mail exchange -- not just the direct-call path")

# --- 7. Notarization: the seal, and who may break it. -----------------------
func _test_notarization() -> void:
	print("[7] an authority co-signs a sealed civilian report -- own flag only")
	var port = _make_ship(MediumStation, "LawPort", Standing.FLAG_DRIFT, [Standing.FLAG_DRIFT], Vector2(600000, 0))
	var victim = _make_ship(CargoShuttle, "DriftVictim", Standing.FLAG_DRIFT, [], Vector2(600000, 4000)) # authority [] -- sealed
	var stranger = _make_ship(CargoShuttle, "MeridianVictim", Standing.FLAG_MERIDIAN, [], Vector2(600000, 8000))

	var sig := {"iff_tags": ["TEAM_PIRATE"], "hull": "pinnace"}
	victim[0].record_incident(Incident.KIND_ARMED_ROBBERY, "Second Return", "PIRATE",
		Vector2(8000, 0), "", sig)
	stranger[0].record_incident(Incident.KIND_ARMED_ROBBERY, "Other Raider", "PIRATE",
		Vector2(9000, 0), "", sig)

	# The victim's own warrant is sealed -- that is the problem being solved.
	victim[0].post_warrant(Standing.OFF_ARMED_ROBBERY, "Second Return", sig, "took cargo")
	var own_key: String = Standing.OFF_ARMED_ROBBERY + "|" + Standing.subject_key("Second Return", sig)
	_assert(victim[0].warrants.has(own_key), "the victim posted its own warrant")
	_assert(not Standing.warrant_enforceable_by(victim[0].warrants[own_key], [Standing.FLAG_DRIFT], 999),
		"which NOBODY else can act on -- personal origin, the seal M58 exists to break")

	# Foreign flag: incident travels, warrant does not get issued.
	port[0].exchange_mail_on_dock(stranger[0])
	_assert(port[0].warrants.is_empty(),
		"a MERIDIAN victim gets no Drift warrant -- Drift does not prosecute on Meridian's behalf")

	# Own flag: co-signed, and now enforceable by any Drift holder.
	port[0].exchange_mail_on_dock(victim[0])
	_assert(port[0].warrants.has(own_key), "the port issued its OWN warrant on the same subject key")
	if port[0].warrants.has(own_key):
		var w: Dictionary = port[0].warrants[own_key]
		_assert(w.get("origin_flag", "") == Standing.FLAG_DRIFT,
			"scoped to the port's flag (got '%s')" % w.get("origin_flag", ""))
		_assert(Standing.warrant_enforceable_by(w, [Standing.FLAG_DRIFT], 999),
			"and a patrol that never saw the robbery can now act on it -- the payoff")

	# A DARK attacker cannot be notarized. subject_key's signature fallback is
	# iff_tags + cross_section -- a band-shared crypto set plus a per-tick lerp
	# of an angle-dependent reading -- so issuing off it would mint a FLAG-WIDE
	# warrant against a whole crew, on a key that would not reliably match
	# anyway. The report is still filed; only the verdict is withheld.
	var dark_victim = _make_ship(CargoShuttle, "DarkVictim", Standing.FLAG_DRIFT, [], Vector2(600000, 12000))
	dark_victim[0].record_incident(Incident.KIND_ARMED_ROBBERY, "", "", Vector2(9500, 0), "", sig)
	var before_dark: int = port[0].warrants.size()
	port[0].exchange_mail_on_dock(dark_victim[0])
	_assert(port[0].warrants.size() == before_dark,
		"a robbery by an UNIDENTIFIED hull notarizes nothing -- going dark stays a real defence")
	_assert(Mailbag.version_of(port[0].get_mailbag(), dark_victim[1].id) >= 1,
		"but the port still RECEIVED the report -- evidence is filed, only the verdict is withheld")

	# NAME_WITHHELD is not a name. A hull broadcasting with share-name off
	# reports the literal "UNKNOWN", which is non-empty -- so an emptiness check
	# would notarize it under the SHARED key `name:UNKNOWN` and brand every
	# name-withholding hull in the cluster. This is the false positive that
	# prompted the 2026-08-01 subject_key fix; assert both halves of it.
	_assert(Standing.subject_key(Standing.NAME_WITHHELD, sig) == Standing.subject_key("", sig),
		"a NAME_WITHHELD subject keys the same as an unnamed one -- not to `name:UNKNOWN`")
	_assert(Standing.subject_key("Real Name", sig) != Standing.subject_key(Standing.NAME_WITHHELD, sig),
		"and a genuinely named subject still keys distinctly")

	var withheld_victim = _make_ship(CargoShuttle, "WithheldVictim", Standing.FLAG_DRIFT, [], Vector2(600000, 16000))
	withheld_victim[0].record_incident(Incident.KIND_ARMED_ROBBERY, Standing.NAME_WITHHELD, "PIRATE",
		Vector2(9900, 0), "", sig)
	var before_withheld: int = port[0].warrants.size()
	port[0].exchange_mail_on_dock(withheld_victim[0])
	_assert(port[0].warrants.size() == before_withheld,
		"a robbery by a NAME-WITHHOLDING hull notarizes nothing -- 'UNKNOWN' is not an identity")

	# Re-docking must not re-issue: the mailbag version is the dedupe.
	var count_before: int = port[0].warrants.size()
	var issued_again: int = port[0].notarize_from(victim[0], Mailbag.version_of(port[0].get_mailbag(), victim[1].id))
	_assert(issued_again == 0, "re-docking notarizes nothing a second time (issued %d)" % issued_again)
	_assert(port[0].warrants.size() == count_before, "and the warrant store did not grow")

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_mail_network <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_mail_network <<<")
		get_tree().quit(1)
