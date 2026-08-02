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
const RiskMap = preload("res://scripts/mail/risk_map.gd")

# One hauler-trip (design doc: "a lot must stay small relative to a need...
# several ships can work the same run"). Refinery Prime's ORE deficit alone
# runs into double digits of lots against this, matching the doc's own
# "16-lot deficit vs a 1-lot hull" illustration.
#
# 2026-07-26 -- 1.0 -> 4.0. This is a THROUGHPUT constant, and at 1.0 it was
# the binding constraint on the entire cluster economy, which is not what it
# was meant to express.
#
# Measured over 180 sim-minutes: Refinery Prime consumes 6.6 ORE/hr and
# received 2.56/hr across 9 deliveries, while its five ORE suppliers sat
# BACKED UP against their own bin capacities (Corvus authored at 1.8/hr,
# producing 0.475 with its bin pinned at 10.03 of 10.8; Slag Bay 3.2 authored,
# 1.53 produced, above its surplus line). A full bin blocks its source, so the
# cluster read as an ore SHORTAGE while ore was piling up unsold at every mine.
# The authored tally is healthy -- 8.9/hr supply against 7.4/hr demand, a 20%
# margin -- and the same shape held for VOLATILES (3.2 vs 2.6). Nothing was
# short; nothing could MOVE. Eight haulers lifting <=1 lot per round trip
# between stations 200-400k apart cannot feed a 6.6/hr converter at any
# authored rate.
#
# 4.0 clears that with headroom (~3x the measured shortfall on the binding
# ORE lane) without collapsing the design property this const exists for:
# Refinery Prime's ORE bin holds 39.6 lots, so a drawdown to empty is still
# ~5 hulls' worth and several ships still work the same run. The `min()`
# against posting quantity in _score_pair() means thin lanes never see the
# full 4.0 anyway -- the measured average was 0.85 against a 1.0 cap, so
# postings were already binding ~15% of the time.
#
# INTERIM, deliberately. A lot size that ignores the hull is wrong on its face
# -- a CargoShuttle and an Ore Barge carry identical loads today. The real
# model is per-hull capacity derived from `cargo_bay` components, which the
# codebase is already most of the way to: ComponentSpec.CARGO_AREA_PER_UNIT
# exists and ship_design_validator.gd:162 already computes
# `capacity = area / CARGO_AREA_PER_UNIT` -- for VALIDATION only, with nothing
# reading it at runtime. Two things block the swap, and both are real work:
# CargoShuttle authors no `cargo_bay` component at all (only Freighter and the
# stations do), and area-units need calibrating into lots. See
# design_ideas/station_economy.md's "Haul capacity" section for the plan,
# including the freight-hauler class that has to exist between the shuttle and
# the Freighter once capacity actually varies by hull.
const LOT_SIZE := 4.0

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
#
# 2026-07-26 -- this constant is PER LOT PER UNIT, and callers must multiply
# by the amount carried. They did not, and that made the LOT_SIZE bump change
# something it was never meant to touch.
#
# Payout is linear in amount; travel cost was flat. So raising LOT_SIZE alone
# multiplied every route's payout by 4 and left its cost untouched --
# quadrupling the distance a route can profitably cover. test_route_planner's
# section B caught it on the first run: a pair rejected from 2,000,000 units
# out became viable, and the arithmetic says nothing inside the cluster could
# be rejected on distance any more (the ~1.41M-unit diagonal costs 212 against
# an 800 payout). "Geography becomes economically real, for free" would have
# quietly stopped being true, and the next sim would have had two variables in
# it instead of one.
#
# Scaling cost by `amount` restores proportionality exactly: score becomes
# amount x [(p_pickup + p_dropoff) - cost_per_lot x distance]. The bracket is
# what decides viability, and it does not contain `amount` at all -- so which
# lanes are worth flying is IDENTICAL to LOT_SIZE 1.0, and only throughput
# moved. Comparisons across candidates now favour a bigger load over a smaller
# one at equal per-lot value, which is just the total value of the trip and is
# what you want.
#
# Cost-per-LOT is also the honest fiction for an interim. Nothing bigger than
# a CargoShuttle is authored, so "4 lots" today means four shuttle-loads, and
# four shuttle-loads genuinely do cost four shuttles' worth of travel. The
# moment capacity comes from `cargo_bay` components this linearity must BREAK
# in two ways: cost becomes per-TRIP (you fly the same distance with a half-
# empty hold, so a long haul for a quarter load should read as the bad
# business it is), and one large hull moving 4 lots should cost less than four
# small ones. That economy of scale is what makes a mid-tier freight hauler
# worth owning rather than merely bigger. Deferred deliberately -- per-trip
# cost only becomes meaningful once hulls actually differ. See
# design_ideas/station_economy.md's "Haul capacity is a property of the HULL".
const TRAVEL_COST_PER_UNIT := 0.00015

# Hysteresis margin (design doc: "a competing route must beat the current
# plan's remaining value by a margin, or haulers thrash between near-equal
# routes"). Absolute score units (same units as price(), 0..~100 per leg) --
# 15 PER LOT is a legible ~15% of one leg's max possible price, big enough to
# absorb ordinary urgency drift between two ordinary postings but small enough
# that a genuinely better route (a station gone newly desperate) still wins.
#
# 2026-07-26 -- derived from LOT_SIZE rather than hardcoded. Scores are
# amount-proportional (see TRAVEL_COST_PER_UNIT), so a flat 15 against 4-lot
# scores would be ~3.75% of a leg, not 15% -- the band would have silently
# narrowed to a quarter of its intended width and haulers would thrash on
# noise. This is the second constant the LOT_SIZE bump would have quietly
# mis-scaled; anything else expressed in absolute score units needs the same
# treatment.
const HYSTERESIS_MARGIN_PER_LOT := 15.0
const HYSTERESIS_MARGIN := HYSTERESIS_MARGIN_PER_LOT * LOT_SIZE

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

# A route must at least pay for itself. best_route() takes the ARGMAX, which
# happily returns the least-bad option when every candidate loses money -- and
# the traffic sim caught exactly that: "PLAN GOODS Ironhold->Coldreach (score
# -35.5)", "RE-PLAN REFINED ... (score -58.6 beat remaining -77.7 by margin)".
# A hauler was committing to runs costing more in travel than both ends pay,
# and the hysteresis was then picking between two losses.
#
# That is not just untidy, it is expensive: a hull on a loss-making run is
# capacity the cluster does not get back. Idling until something is worth
# flying is strictly better -- and it is what an independent operator would
# actually do.
#
# (This paragraph used to justify itself with "fleet capacity is only ~1.5x
# total haul demand". That figure was computed at LOT_SIZE 1.0 and the
# 2026-07-26 bump to 4.0 invalidates it. The floor does not depend on capacity
# being scarce -- flying a loss is wrong at any fleet size -- so the argument
# stands without the number, and a stale number is worse than none.)
#
# 0.0 is the honest floor ("don't fly a loss") rather than a tuned number. A
# ship already mid-route is NOT affected: this gates new plans only, so a hull
# that has already made its pickup still completes the drop rather than
# stranding the cargo.
const MIN_VIABLE_SCORE := 0.0

# `known_incidents` is the CALLER's heard news (RoutePlannerLeaf passes
# Mailbag.read_incidents(cluster, actor.get_mailbag())). Defaulting to empty
# keeps every existing caller and test on today's behaviour -- no knowledge,
# no risk -- so the fog is opt-in per reader rather than global truth.
static func best_route(cluster, from_pos: Vector2, ship_flag: String,
		known_incidents: Array = []) -> Dictionary:
	var best: Dictionary = {}
	# Sampled ONCE per search, not per pair: _score_pair runs stations^2 x
	# commodities times, and recency only needs to be consistent within a search.
	var now: int = Engine.get_physics_frames()
	var best_score: float = -INF
	var pairs_scored := 0
	for pickup_rec in cluster.records:
		if pickup_rec.kind != ClusterEntity.Kind.STATION:
			continue
		for dropoff_rec in cluster.records:
			if dropoff_rec == pickup_rec or dropoff_rec.kind != ClusterEntity.Kind.STATION:
				continue
			for commodity in Commodity.ALL:
				var route: Dictionary = _score_pair(pickup_rec, dropoff_rec, commodity, from_pos, ship_flag, known_incidents, now)
				if route.is_empty():
					continue
				pairs_scored += 1
				if route["score"] > best_score:
					best_score = route["score"]
					best = route
	if not best.is_empty() and best_score <= MIN_VIABLE_SCORE:
		best = {}   # nothing worth flying -- idle rather than burn a hull on a loss
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
static func _score_pair(pickup_rec, dropoff_rec, commodity: String, from_pos: Vector2, ship_flag: String,
		known_incidents: Array = [], now: int = 0) -> Dictionary:
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
	# Cost is per LOT per unit -- multiply by what we are actually carrying, or
	# payout scales with the load while cost does not. See the constant's own
	# comment for what that broke.
	var travel_cost: float = TRAVEL_COST_PER_UNIT * amount * (deadhead + haul)
	var risk: float = _risk_estimate(pickup_rec, dropoff_rec, known_incidents, now)
	var score: float = payout - travel_cost - risk

	return {
		"commodity": commodity,
		"pickup_id": pickup_rec.id, "pickup_pos": pickup_rec.pos, "pickup_name": pickup_rec.name,
		"dropoff_id": dropoff_rec.id, "dropoff_pos": dropoff_rec.pos, "dropoff_name": dropoff_rec.name,
		"pickup_accept": accept_pickup, "dropoff_accept": accept_dropoff,
		"amount": amount, "score": score,
	}

# ---------------------------------------------------------------------------
# M59 -- the risk term. The seam M53c left ("risk comes from HEARD news, which
# is what lets a hauler fly into an ambush the player already knows about")
# now has the substrate it was waiting on: M57 incidents, carried by M58
# mailbags. As promised, exactly one function changed.
#
# THE INPUT IS HEARD NEWS, NOT TRUTH. `known_incidents` is whatever the READER
# has been told -- Mailbag.read_incidents() clamped to its delivered version --
# so two haulers with different travel histories price the same lane
# differently, and a hull fresh out of a port that has heard nothing prices
# every lane at zero risk and flies straight into it. That is the feature.
#
# Three weights, each with a reason rather than a taste:
#
#   PER LOT. Scores are amount-proportional, and route_planner has already been
#   bitten by an absolute-units constant silently mis-scaling when LOT_SIZE
#   moved (see HYSTERESIS_MARGIN_PER_LOT's comment, which explicitly warns that
#   "anything else expressed in absolute score units needs the same
#   treatment"). This is that anything else.
#
#   CORRIDOR, not endpoints. Distance is measured to the pickup->dropoff
#   SEGMENT, because a robbery happens out on a lane, nowhere near either
#   station -- scoring against endpoints would miss precisely the incidents
#   that matter. RISK_CORRIDOR_RADIUS is the pirate detection radius from the
#   viability work: beyond it, an incident says nothing about this lane.
#
#   RECENCY. Halved every RISK_HALF_LIFE_FRAMES. This is the damping term for
#   the predator-prey oscillation the design doc predicts (cargo leaves,
#   pirates starve, patrols relax, cargo returns) -- its half-life is the main
#   dial for how fast that cycle runs, which is why it is a named constant and
#   not an inline 0.5.
#
# Deliberately NOT weighted by incident kind. An OVERDUE (a hull that stopped
# reporting, culprit unknown) counts the same as a witnessed ARMED_ROBBERY.
# Weighting them differently is a policy judgement, and the whole point of the
# verdict/evidence split is that a consumer owns its own policy -- so when
# there is a reason to separate them, it belongs here, visibly, rather than
# baked into the record.
# The weighting itself lives in scripts/mail/risk_map.gd, shared with the
# patrol side -- so "cargo avoids dangerous lanes and patrols prefer them" is
# one function consulted twice rather than two that happen to agree. Only the
# per-lot scaling is ours: scores here are amount-proportional, and this file
# has already been bitten by an absolute-units constant silently mis-scaling
# when LOT_SIZE moved (see HYSTERESIS_MARGIN_PER_LOT, which warns in as many
# words that "anything else expressed in absolute score units needs the same
# treatment"). This is that anything else.
const RISK_CORRIDOR_RADIUS := RiskMap.RISK_CORRIDOR_RADIUS
const RISK_HALF_LIFE_FRAMES := RiskMap.RISK_HALF_LIFE_FRAMES

static func _risk_estimate(pickup_rec, dropoff_rec, known_incidents: Array, now: int) -> float:
	return RiskMap.lane_risk(pickup_rec.pos, dropoff_rec.pos, known_incidents, now) * LOT_SIZE

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
		return pickup_payout + dropoff_payout - TRAVEL_COST_PER_UNIT * amount * dist
	var dist2: float = actor_pos.distance_to(dropoff_pos)
	return dropoff_payout - TRAVEL_COST_PER_UNIT * amount * dist2

# Hysteresis gate: a candidate only replaces the standing plan if it clears
# the remaining value by MARGIN, not merely exceeds it (design doc: "without a
# band, small posting updates cause thrash -- a hauler pirouetting between two
# nearly-equal routes"). A pure function (no ship/job coupling) so the thrash
# test can drive it directly with hand-picked numbers.
static func should_replan(current_remaining: float, candidate_score: float, margin: float = HYSTERESIS_MARGIN) -> bool:
	return candidate_score > current_remaining + margin
