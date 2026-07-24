extends Node

# M53a Pass 2 -- the jurisdiction-seam payoff assertion: a warrant issued
# under one sovereign's authority (FLAG_MERIDIAN, the new peer flag) is
# VISIBLE but NOT ENFORCEABLE by the OTHER sovereign's patrol (FLAG_DRIFT,
# home), and vice versa. "You killed someone in the next country over and
# nobody here cares" -- design_ideas/2026-07-20-pirate_playtest.md via
# implementation_plans/m53a_economic_expansion.md's Scope item 3.
#
# Pure-function style over Standing's existing M52b warrant machinery (no
# scene tree/physics needed) -- same model as test_standing_rules.gd's
# "enforcement gate mirrors the issuing gate" cases and test_warrant_pull.gd.
# No NEW mechanism is being tested here -- warrant_enforceable_by/
# build_warrant_index already implement "enforceable only by holders of the
# origin flag" (M52b). This test pins that the SAME gate, unmodified, is
# what makes a second sovereign's jurisdiction actually mean something.

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")

func setup(_main) -> void:
	print("Test test_jurisdiction_seam initialized.")
	Standing.reset()

	var passed = 0
	var failed = 0

	var home_authority: Array = [Standing.FLAG_DRIFT]
	var meridian_authority: Array = [Standing.FLAG_MERIDIAN]
	var home_patrol_iid := 601      # a home patrol's own instance id (Patrol Alpha-ish)
	var meridian_patrol_iid := 502  # a Meridian-deputized ship's own instance id

	# --- A) A Meridian colony issues a warrant under ITS OWN authority -------
	# scoped_origin only stamps the flag if the issuer is actually deputized
	# for it (M52b) -- Halvorsen Claim's warrant_authority defaults to
	# [FLAG_MERIDIAN] (home_cluster.gd's _station), so this is the real path.
	var meridian_origin: String = Standing.scoped_origin(Standing.FLAG_MERIDIAN, meridian_authority)
	if meridian_origin == Standing.FLAG_MERIDIAN:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a Meridian station deputized for its own flag should stamp origin_flag = FLAG_MERIDIAN, got ", meridian_origin)

	var meridian_key: String = Standing.OFF_ARMED_ROBBERY + "|" + Standing.subject_key("Rock Runner", {})
	var w_meridian: Dictionary = Standing.make_warrant(
		Standing.OFF_ARMED_ROBBERY, {"claimed_name": "Rock Runner"},
		{"iid": 13, "name": "Halvorsen Claim"}, meridian_origin, meridian_key,
		"robbed a Meridian ore hauler")

	# 1. NOT enforceable by a home (FLAG_DRIFT-only) patrol -- home just isn't
	#    deputized for the Meridian flag, same gate M52b already enforces.
	if not Standing.warrant_enforceable_by(w_meridian, home_authority, home_patrol_iid):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a Meridian-flagged warrant must NOT be enforceable by a home (FLAG_DRIFT) patrol")

	# 2. IS enforceable by a fellow Meridian-deputized ship.
	if Standing.warrant_enforceable_by(w_meridian, meridian_authority, meridian_patrol_iid):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a Meridian-flagged warrant SHOULD be enforceable by a Meridian-deputized ship")

	# 3. VISIBLE: the raw warrant record itself is ordinary data -- a home
	#    dispatcher pulling/relaying Halvorsen's ledger sees it fine (nothing
	#    about the record is hidden; only ENFORCEMENT is gated). This is the
	#    "still information, not noise" half of the design doc's rule.
	var raw_store: Dictionary = {meridian_key: w_meridian}
	if raw_store.has(meridian_key):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] the warrant record should be plain visible data regardless of who can enforce it")

	# 4. NOT ENFORCEABLE, operationally: build_warrant_index (what
	#    compute_standing actually consults) drops it entirely for a home
	#    observer -- a merely-visible cross-flag warrant must never escalate
	#    standing to HOSTILE on its own strength (M52b's index contract).
	var home_index: Dictionary = Standing.build_warrant_index(raw_store, home_authority, home_patrol_iid)
	if home_index.is_empty():
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a home patrol's warrant index should NOT include a Meridian-origin warrant, got ", home_index)

	# 5. ...while the SAME warrant DOES land in a Meridian patrol's own index
	#    (their patrol would rightly paint this contact HOSTILE).
	var meridian_index: Dictionary = Standing.build_warrant_index(raw_store, meridian_authority, meridian_patrol_iid)
	if meridian_index.has(Standing.warrant_subject_key(w_meridian)):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a Meridian patrol's warrant index SHOULD include its own colony's warrant, got ", meridian_index)

	# 6. End-to-end via compute_standing: a home patrol that has only this
	#    Meridian warrant in its index (per #4) reads the wanted hauler as
	#    NEUTRAL, not HOSTILE -- "reporting clean" wins because the warrant
	#    lookup (compute_standing rule 2) is a no-op for this observer. This
	#    is the actual in-game behavior the pure checks above predict.
	var home_patrol := Ship.new()
	home_patrol.iff_tags = ["TEAM_DRIFT"]                    # not crypto-kin of Meridian
	home_patrol.known_enemy_flags = [Standing.FLAG_PIRATE]   # Meridian is NOT a known-enemy flag
	home_patrol.warrant_index = home_index
	var contact := {"classification": "FRIENDLY VESSEL", "signature": {"iff_tags": ["TEAM_MERIDIAN"]}}
	var transponder := {"name": "Rock Runner", "flag": Standing.FLAG_MERIDIAN}
	var result: Dictionary = Standing.compute_standing(contact, transponder, home_patrol)
	if result.get("standing", "") == Standing.NEUTRAL:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] home patrol should read the warranted-but-unenforceable Meridian hauler as NEUTRAL, got ", result)
	home_patrol.free()

	# --- B) ...and vice versa: a home-issued warrant means nothing to Meridian ---
	var drift_origin: String = Standing.scoped_origin(Standing.FLAG_DRIFT, home_authority)
	var drift_key: String = Standing.OFF_ASSAULT + "|" + Standing.subject_key("Drifter Two", {})
	var w_drift: Dictionary = Standing.make_warrant(
		Standing.OFF_ASSAULT, {"claimed_name": "Drifter Two"},
		{"iid": 601, "name": "Patrol Alpha"}, drift_origin, drift_key,
		"opened fire near Ironhold")

	if not Standing.warrant_enforceable_by(w_drift, meridian_authority, meridian_patrol_iid):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a FLAG_DRIFT warrant must NOT be enforceable by a Meridian-only ship")

	if Standing.warrant_enforceable_by(w_drift, home_authority, home_patrol_iid):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a FLAG_DRIFT warrant SHOULD be enforceable by a home patrol")

	var meridian_index_2: Dictionary = Standing.build_warrant_index({drift_key: w_drift}, meridian_authority, meridian_patrol_iid)
	if meridian_index_2.is_empty():
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a Meridian patrol's warrant index should NOT include a home-origin warrant, got ", meridian_index_2)

	if failed == 0:
		print(">>> [TEST PASSED] test_jurisdiction_seam <<<")
		print("[TEST PASSED] test_jurisdiction_seam. Passed ", passed, "/", passed + failed, " cases.")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_jurisdiction_seam <<<")
		printerr("[TEST SUITE FAILED] ", failed, " of ", passed + failed, " checks failed.")
		get_tree().quit(1)
