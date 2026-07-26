class_name RoutePlanner

# M53c Phase C -- the ship-side planner (design_ideas/station_economy.md
# "Routing: EVERY ship plans for itself"; implementation_plans/
# m53c_demand_routing.md "Phase C"). ONE planner, on the ship -- no operator
# dispatch pass (an operator scoring a hull 400k away would need instantaneous
# command and control, which contradicts information travelling at hull
# speed). Static executor library, same convention as job_steps.gd: stateless
# functions, all state (the plan itself) lives on the job dict the caller
# hands back to Ship.set_default_job()/assign_job().
#
# score(posting) = offered_price(posting, THIS ship)
#                - travel_cost(from where I am now)
#                - risk_estimate(route, as I understand it)
#
# Deliberately NO flag_affinity term (design doc, verbatim) -- price
# discrimination already lives station-side (StationEconomy._policy_
# multiplier, Phase B); willingness/duty is owner-side (Phase D, not built
# here). Eligibility (export control) is folded in for free via
# StationEconomy.get_posting()/accept_posting()'s own `eligible` field -- a
# ship simply never sees a route through a posting it isn't eligible for,
# which is also how "two ships with different flags make different choices
# from identical world state" falls out with no separate mechanism (Coldreach
# restricts VOLATILES to Standing.FLAG_MERIDIAN, home_cluster.gd).
#
# A ROUTE here is the minimum end of the design doc's "2-3 legs" range: a
# PICKUP leg (dock at a station with an open EXPORT posting for commodity C,
# withdraw -- the design doc's "both ends pay": the exporter pays for
# removal) and a DROPOFF leg (dock at a station with an open IMPORT posting
# for the SAME commodity, deliver -- the importer pays for receipt). Cargo
# stays abstract (design doc principle 5, "a delivery is an EVENT, not a
# cargo transfer") -- nothing is held in between; the pickup fulfill() and
# dropoff fulfill() are two independent stock movements linked only by the
# ship's own itinerary. Route search stays SHALLOW on purpose (design doc:
# "deeper lookahead against information this stale is false precision and
# reads as less legible behavior") -- one pickup/dropoff pair, not a chained
# multi-hop search.
#
# The board is GLOBALLY READABLE for now (Phase B decision -- fog/latency
# gating is Mail phase 3, explicitly out of scope here), so best_route() below
# reads every station record directly off `cluster.records`, live or dormant,
# the same "walk the record, not the live node" discipline StationEconomy's
# own tick uses.
#
# Reference via the preload-const convention (CLAUDE.md's headless
# class-cache caveat -- never the bare class_name):
#   const RoutePlanner = preload("res://scripts/ai/route_planner.gd")

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

# One hauler-trip (design doc: "a lot must stay small relative to a need...
# several ships can work the same run"). Refinery Prime's ORE deficit alone
# runs into double digits of lots against this, matching the doc's own
# "16-lot deficit vs a 1-lot hull" illustration.
const LOT_SIZE := 1.0

# Cost per world-unit of travel, calibrated against design_ideas/
# station_economy.md's own worked "Geography becomes economically real, for
# free" table: solving cost = payout - net for its Ironhold/Deepcut vantage
# points on "Deepcut ore -> Refinery Prime" (74 over 492k units, 16 over 108k)
# and the Corvus Yards viability solve (136 over 906k) all land within a few
# percent of 0.00015/unit -- so this is a transcribed constant, not a tuned
# one. NOTE: the design doc's own worked table used a deliberately LINEAR
# illustrative price curve (100 x urgency), while StationEconomy.price() is
# mildly CONVEX (PRICE_CONVEX_EXP=1.5) -- see that file's own comment on the
# same discrepancy -- so exact payout figures are not bit-reproducible against
# the doc's table; the distance-to-cost ratio is what carries over.
const TRAVEL_COST_PER_UNIT := 0.00015

# Hysteresis margin (design doc: "a competing route must beat the current
# plan's remaining value by a margin, or haulers thrash between near-equal
# routes"). Absolute score units (same units as price(), 0..~100 per leg) --
# 15 is a legible ~15% of one leg's max possible price, big enough to absorb
# ordinary urgency drift between two ordinary postings but small enough that a
# genuinely better route (a station gone newly desperate) still wins.
const HYSTERESIS_MARGIN := 15.0

# Itinerary step index at which the pickup leg is behind us (see
# route_itinerary() below for the 6-step shape): 0=GO_TO pickup, 1=DOCK_AT
# pickup, 2=AWAIT undocked, 3=GO_TO dropoff, 4=DOCK_AT dropoff, 5=AWAIT
# undocked. current >= 3 means the pickup's DOCK_AT already ran (and, since
# JobRunnerLeaf only advances `current` on DONE, that DOCK_AT's staged
# delivery already fired inside DockingBay) -- remaining_value() below uses
# this to stop counting the pickup's payout/travel once it's sunk cost.
const DROPOFF_LEG_START := 3

# ---------------------------------------------------------------------------
# best_route() -- the search. O(stations^2 x commodities), trivially cheap
# (at most a few hundred dictionary reads) and called only at re-plan time,
# never per-physics-tick. Returns {} if nothing viable exists (no open
# posting pair this ship is eligible for) -- the caller's job is to leave
# whatever plan (or lack of one) already stands.
# ---------------------------------------------------------------------------

static func best_route(cluster, from_pos: Vector2, ship_flag: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	var pairs_scored := 0
	for pickup_rec in cluster.records:
		if pickup_rec.kind != ClusterEntity.Kind.STATION:
			continue
		for dropoff_rec in cluster.records:
			if dropoff_rec == pickup_rec or dropoff_rec.kind != ClusterEntity.Kind.STATION:
				continue
			for commodity in Commodity.ALL:
				var route: Dictionary = _score_pair(pickup_rec, dropoff_rec, commodity, from_pos, ship_flag)
				if route.is_empty():
					continue
				pairs_scored += 1
				if route["score"] > best_score:
					best_score = route["score"]
					best = route
	if _diag_enabled():
		_diag_report(cluster, from_pos, ship_flag, pairs_scored, best)
	return best

# ---------------------------------------------------------------------------
# Diagnostic (DebugSettings "route_planner_log", default OFF -- see that
# file's own comment). Answers, in one line per best_route() call: how many
# EXPORT/IMPORT postings exist AT ALL (open, regardless of eligibility), how
# many of those THIS ship is eligible for, how many pickup/dropoff pairs
# actually scored (both legs open+eligible+nonzero quantity), and the winning
# candidate or NONE. A cheap re-scan of the board -- only paid when the
# toggle is ON, never in the hot (default) path.
# ---------------------------------------------------------------------------
static func _diag_enabled() -> bool:
	return DebugSettings and DebugSettings.get_choice("route_planner_log") == DebugSettings.RoutePlannerLog.ON

static func _diag_report(cluster, from_pos: Vector2, ship_flag: String, pairs_scored: int, best: Dictionary) -> void:
	var export_total := 0
	var export_eligible := 0
	var import_total := 0
	var import_eligible := 0
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		for commodity in Commodity.ALL:
			var posting: Dictionary = StationEconomy.get_posting(rec, "self", commodity, ship_flag)
			if posting.is_empty():
				continue
			if posting["direction"] == "EXPORT":
				export_total += 1
				if posting["eligible"]:
					export_eligible += 1
			elif posting["direction"] == "IMPORT":
				import_total += 1
				if posting["eligible"]:
					import_eligible += 1
	var best_desc: String = "NONE"
	if not best.is_empty():
		best_desc = "%.1f (%s %s->%s, amount %.2f)" % [best["score"], best["commodity"], best["pickup_name"], best["dropoff_name"], best["amount"]]
	print("[RoutePlanner] search from %s flag '%s': EXPORT open %d (eligible %d), IMPORT open %d (eligible %d), pairs scored %d, best=%s" % [
		from_pos, ship_flag, export_total, export_eligible, import_total, import_eligible, pairs_scored, best_desc])

# One candidate pickup/dropoff pair for one commodity, or {} if either side
# has no open posting this ship is eligible for (StationEconomy.get_posting's
# own `eligible` field folds in export-control restrictions -- e.g. Coldreach
# VOLATILES, home_cluster.gd -- with no separate check needed here).
static func _score_pair(pickup_rec, dropoff_rec, commodity: String, from_pos: Vector2, ship_flag: String) -> Dictionary:
	var pickup_posting: Dictionary = StationEconomy.get_posting(pickup_rec, "self", commodity, ship_flag)
	if pickup_posting.is_empty() or pickup_posting["direction"] != "EXPORT" or not pickup_posting["eligible"]:
		return {}
	var dropoff_posting: Dictionary = StationEconomy.get_posting(dropoff_rec, "self", commodity, ship_flag)
	if dropoff_posting.is_empty() or dropoff_posting["direction"] != "IMPORT" or not dropoff_posting["eligible"]:
		return {}

	var amount: float = min(LOT_SIZE, min(pickup_posting["quantity"], dropoff_posting["quantity"]))
	if amount <= 0.0:
		return {}

	var accept_pickup: Dictionary = StationEconomy.accept_posting(pickup_rec, "self", commodity, ship_flag)
	var accept_dropoff: Dictionary = StationEconomy.accept_posting(dropoff_rec, "self", commodity, ship_flag)
	if accept_pickup.is_empty() or accept_dropoff.is_empty():
		return {} # posting closed between the read above and accept (shouldn't happen synchronously, but stay defensive)

	var payout: float = accept_pickup["price"] * amount + accept_dropoff["price"] * amount
	# The deadhead leg is a REAL cost (design doc, verbatim): score the WHOLE
	# round -- deadhead to the pickup, THEN the paying haul -- not just the
	# paying half. This is what makes the same posting worth different
	# amounts depending on where the ship already is.
	var deadhead: float = from_pos.distance_to(pickup_rec.pos)
	var haul: float = pickup_rec.pos.distance_to(dropoff_rec.pos)
	var travel_cost: float = TRAVEL_COST_PER_UNIT * (deadhead + haul)
	var risk: float = _risk_estimate(pickup_rec, dropoff_rec)
	var score: float = payout - travel_cost - risk

	return {
		"commodity": commodity,
		"pickup_id": pickup_rec.id, "pickup_pos": pickup_rec.pos, "pickup_name": pickup_rec.name,
		"dropoff_id": dropoff_rec.id, "dropoff_pos": dropoff_rec.pos, "dropoff_name": dropoff_rec.name,
		"pickup_accept": accept_pickup, "dropoff_accept": accept_dropoff,
		"amount": amount, "score": score,
	}

# Risk term hook -- design doc: "risk comes from HEARD news, which is what
# lets a hauler fly into an ambush the player already knows about." That
# requires the fog/heard-news substrate (Mail phase 2-3, Phase E) which is
# explicitly out of scope for M53c Phase C. Zero for now, kept as its own
# named function (not inlined into _score_pair's score line) so the seam is
# obvious and a later phase changes exactly one function, not every call site.
static func _risk_estimate(_pickup_rec, _dropoff_rec) -> float:
	return 0.0

# ---------------------------------------------------------------------------
# route_itinerary() -- turns a best_route() result into a job dict for
# Ship.set_default_job()/assign_job() (JobRunnerLeaf's two-slot model). Just a
# longer itinerary on the EXISTING M50 job runner (design doc, verbatim): six
# GO_TO/DOCK_AT/AWAIT steps job_steps.gd already implements, no new verbs.
# DOCK_AT's optional "delivery" param (job_steps.gd's step_dock_at) is what
# actually stages the transaction Part 1's docking_bay.gd hook settles.
#
# The route-search fields (route_commodity, route_score, pickup_pos, ...) ride
# ALONGSIDE the steps on the same dict -- not itinerary state, but this dict
# IS "the ship's own plan" (design doc: "the plan lives in the ship's own
# behavior dict"), and remaining_value()/should_replan() below need them back
# without re-deriving from the (possibly since-changed) live posting.
# ---------------------------------------------------------------------------

static func route_itinerary(route: Dictionary) -> Dictionary:
	return {
		"steps": [
			{"verb": "GO_TO", "pos": route["pickup_pos"]},
			{"verb": "DOCK_AT", "station_pos": route["pickup_pos"],
				"delivery": {"acceptance": route["pickup_accept"], "amount": route["amount"]}},
			{"verb": "AWAIT", "condition": "undocked"},
			{"verb": "GO_TO", "pos": route["dropoff_pos"]},
			{"verb": "DOCK_AT", "station_pos": route["dropoff_pos"],
				"delivery": {"acceptance": route["dropoff_accept"], "amount": route["amount"]}},
			{"verb": "AWAIT", "condition": "undocked"},
		],
		"current": 0,
		"route_commodity": route["commodity"],
		"route_score": route["score"],
		"pickup_pos": route["pickup_pos"],
		"dropoff_pos": route["dropoff_pos"],
		"pickup_accept": route["pickup_accept"],
		"dropoff_accept": route["dropoff_accept"],
		"amount": route["amount"],
	}

# ---------------------------------------------------------------------------
# remaining_value() -- the "current plan's remaining value" hysteresis reads
# (design doc, verbatim: "a competing route must beat the current plan's
# REMAINING value"). Sunk legs don't count against continuing: once the
# pickup is behind us (current >= DROPOFF_LEG_START), only the dropoff's
# payout minus the remaining travel to it is left to weigh -- the deadhead we
# already flew is gone either way, so re-scoring it against a fresh candidate
# would double-penalize the plan we're already committed to.
#
# Returns -INF for an empty/non-route job (nothing currently held -- anything
# viable beats it) so should_replan() below never needs a separate "do we
# even have a plan" branch.
# ---------------------------------------------------------------------------

static func remaining_value(actor_pos: Vector2, job: Dictionary) -> float:
	if job.is_empty() or not job.has("pickup_accept"):
		return -INF
	var amount: float = job.get("amount", 0.0)
	var dropoff_pos: Vector2 = job.get("dropoff_pos", actor_pos)
	var dropoff_payout: float = job.get("dropoff_accept", {}).get("price", 0.0) * amount
	var current: int = job.get("current", 0)
	if current < DROPOFF_LEG_START:
		var pickup_pos: Vector2 = job.get("pickup_pos", actor_pos)
		var pickup_payout: float = job.get("pickup_accept", {}).get("price", 0.0) * amount
		var dist: float = actor_pos.distance_to(pickup_pos) + pickup_pos.distance_to(dropoff_pos)
		return pickup_payout + dropoff_payout - TRAVEL_COST_PER_UNIT * dist
	var dist2: float = actor_pos.distance_to(dropoff_pos)
	return dropoff_payout - TRAVEL_COST_PER_UNIT * dist2

# Hysteresis gate: a candidate only replaces the standing plan if it clears
# the remaining value by MARGIN, not merely exceeds it (design doc: "without a
# band, small posting updates cause thrash -- a hauler pirouetting between two
# nearly-equal routes"). A pure function (no ship/job coupling) so the thrash
# test can drive it directly with hand-picked numbers.
static func should_replan(current_remaining: float, candidate_score: float, margin: float = HYSTERESIS_MARGIN) -> bool:
	return candidate_score > current_remaining + margin
