extends RefCounted

# DO PIRATES SIT WHERE CARGO ACTUALLY FLIES? OFF by default; a sim turns it on.
#
# WHY THIS EXISTS, and why it does not need a long run.
#
# The encounter arithmetic does not survive contact with the measurement. Random
# search over the authored cluster predicts a pirate should see prey in most
# hunts:
#
#   bounds 1,000,000 x 1,000,000            = 1e12 u^2
#   pirate passive_em radius                = 45,000
#   hauler cruise                           = ~700 u/s
#   14 haulers, 900s hunt
#   rate = 2*r*v*N / A = 8.8e-4 /s  ->  P(sighting per hunt) ~ 0.79
#
# Measured across the LANE_RUN A/B: 163 hunts ended "found nobody" against 3
# that found prey. Under 2% where the model says 79% -- overestimating by ~40x.
# An error that size is not a tuning gap, it is a wrong assumption, and the
# suspect assumption is UNIFORMITY: cargo does not fill the box, it flies the
# few lanes that pay, while `PirateGuild._random_hub_pair` samples station pairs
# uniformly. With 8 stations there are 28 possible lanes; if cargo concentrates
# on 3-4 of them, a uniform pick sits on a used road ~12% of the time.
#
# THAT IS A HYPOTHESIS, and this probe exists to test it rather than assume it.
# Three earlier confident causes this session were wrong from exactly this kind
# of reasoning-off-the-code (the pursuit `cruise` cap most expensively), so the
# rule now is measure first.
#
# WHY IT IS CHEAP -- the point of the design. Robberies are rare (0-3 per four
# game-hours) so anything measured in TAKES needs enormous runs. But lane CHOICE
# is sampled constantly: every hauler replan (~1 per 10s per hull) and every
# pirate arrival. A 30-60 game-minute run yields thousands of cargo samples and
# dozens of pirate ones, which is plenty to compare two distributions. We are
# measuring where the two populations GO, not how often they collide.
#
# THE SAMPLING IS TIME-WEIGHTED BY CONSTRUCTION, which is what makes the overlap
# number mean something. Encounter probability is proportional to hauler-seconds
# and pirate-seconds spent on the same lane. Replan checks fire on a fixed
# per-hull interval, so cargo counts are proportional to hauler-seconds; a pirate
# commits to one lane for a whole hunt, so pirate counts are proportional to
# pirate-hunts. Neither is a headcount.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

static var enabled: bool = false

# lane_key -> count. Keys are human-readable and DIRECTIONLESS ("Deepcut <-> Ironhold"),
# built by sorting the two endpoint names, since a lane is the same road whichever
# way you drive it and a pirate sitting on it does not care.
static var cargo_picks: Dictionary = {}
static var pirate_picks: Dictionary = {}

# Endpoints that did not resolve to a station, kept separately rather than
# silently bucketed. APPROACH_RING and the wormhole-anchored fallbacks in
# _pick_hunt_point produce segments whose ends are NOT two stations, and folding
# those into a station-pair histogram would invent lanes that do not exist.
static var pirate_unresolved: int = 0

# ARE CARGO SHIPS SIMPLY AVOIDING THE PIRATES? (2026-08-03)
#
# The aggregate shares above cannot answer this, because they average over the
# whole run: a lane that carried heavy traffic until a robbery and none
# afterwards looks identical to a lane with steady medium traffic. The question
# is TEMPORAL, so it needs a timeline.
#
# It matters because it could invert the diagnosis. If cargo diverts away from
# lanes where incidents happened, then a pirate that lands a take POISONS ITS
# OWN LANE -- and the pirate's hunt job commits to one lane for the whole hunt,
# so it cannot follow the traffic it just scared off. "Pirates find no prey"
# would then be partly the risk system WORKING, not a targeting failure.
#
# THE PRECONDITION, which decides what a null result means: cargo can only avoid
# what it has HEARD. Risk comes from incidents, an incident needs a completed
# robbery, and the news then has to reach the hauler by courier. So a pirate that
# has robbed nobody generates nothing to avoid, and "no drop" on such a lane is
# EXPECTED rather than evidence of anything. The two populations are reported
# separately below for exactly that reason.
static var cargo_timeline: Array = []   # {frame, lane}
static var pirate_hunts: Array = []     # {frame, lane}

static func reset() -> void:
	cargo_picks.clear()
	pirate_picks.clear()
	cargo_timeline.clear()
	pirate_hunts.clear()
	pirate_unresolved = 0

# Nearest station record to a point, or null. `max_dist` guards against naming a
# lane after a station that merely happens to be the closest thing to a point in
# deep space -- an APPROACH_RING segment ending 60,000u off a hub is about that
# hub, a chord midpoint 200,000u from anything is not.
static func _station_at(cluster, p: Vector2, max_dist: float):
	var best = null
	var best_d: float = max_dist
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		var d: float = p.distance_to(rec.pos)
		if d < best_d:
			best_d = d
			best = rec
	return best

static func _key(a_name: String, b_name: String) -> String:
	# Sorted, so A->B and B->A are one lane.
	return ("%s <-> %s" % [a_name, b_name]) if a_name <= b_name else ("%s <-> %s" % [b_name, a_name])

# A pirate has committed to a lane for the length of a hunt. Called from
# PirateGuild._build_hunt_job, which already holds `cluster`.
#
# `tolerance` is generous (one station keep-away radius) because the endpoints
# recorded here are the SEGMENT the pirate patrols, and several hunt strategies
# deliberately stand off from the hub rather than sitting on it.
static func note_pirate(cluster, seg_a: Vector2, seg_b: Vector2, tolerance: float = 60000.0) -> void:
	if not enabled or cluster == null or not is_instance_valid(cluster):
		return
	var a = _station_at(cluster, seg_a, tolerance)
	var b = _station_at(cluster, seg_b, tolerance)
	if a == null or b == null or a == b:
		pirate_unresolved += 1
		return
	var k: String = _key(a.name, b.name)
	pirate_picks[k] = int(pirate_picks.get(k, 0)) + 1
	pirate_hunts.append({"frame": Engine.get_physics_frames(), "lane": k})

# A hauler has chosen (or re-affirmed) a route. Called from RoutePlannerLeaf
# alongside the DecisionProbe hook, which already has the cluster and the route.
static func note_cargo(cluster, pickup_id: int, dropoff_id: int) -> void:
	if not enabled or cluster == null or not is_instance_valid(cluster):
		return
	var a_name: String = ""
	var b_name: String = ""
	for rec in cluster.records:
		if rec.id == pickup_id:
			a_name = rec.name
		elif rec.id == dropoff_id:
			b_name = rec.name
	if a_name == "" or b_name == "":
		return
	var k: String = _key(a_name, b_name)
	cargo_picks[k] = int(cargo_picks.get(k, 0)) + 1
	cargo_timeline.append({"frame": Engine.get_physics_frames(), "lane": k})

static func _shares(counts: Dictionary) -> Dictionary:
	var total: float = 0.0
	for k in counts:
		total += float(counts[k])
	var out: Dictionary = {}
	if total <= 0.0:
		return out
	for k in counts:
		out[k] = float(counts[k]) / total
	return out

# THE NUMBER THE HYPOTHESIS LIVES OR DIES ON.
#
#   overlap  = sum over lanes of  cargo_share(L) * pirate_share(L)
#              -- the probability that a random pirate-second and a random
#                 cargo-second are on the SAME lane.
#   best     = sum over lanes of  cargo_share(L)^2
#              -- the same quantity if pirates distributed themselves EXACTLY
#                 like cargo. The ceiling any targeting rule could reach.
#   efficiency = overlap / best, so 1.0 means "pirates are already where cargo
#              is" and 0.1 means "they are choosing roads cargo does not use".
#
# Reporting the ceiling alongside the value matters: `overlap` alone is
# uninterpretable, because a cluster where cargo itself is spread thin has a low
# ceiling no targeting rule can beat. That is the same failure the funnel's
# "RISK WAS ALWAYS ZERO" banner had -- a number that means opposite things
# depending on a second number nobody printed.
static func overlap_summary() -> Dictionary:
	var c: Dictionary = _shares(cargo_picks)
	var p: Dictionary = _shares(pirate_picks)
	if c.is_empty() or p.is_empty():
		return {}
	var overlap: float = 0.0
	for k in c:
		overlap += float(c[k]) * float(p.get(k, 0.0))
	var best: float = 0.0
	for k in c:
		best += float(c[k]) * float(c[k])
	return {
		"overlap": overlap,
		"best": best,
		"efficiency": (overlap / best) if best > 0.0 else 0.0,
		"cargo_lanes": c.size(),
		"pirate_lanes": p.size(),
	}

# Lanes sorted by cargo share, with the pirate share beside each -- the table a
# human reads to see WHICH roads are busy and whether anyone is watching them.
static func table() -> Array:
	var c: Dictionary = _shares(cargo_picks)
	var p: Dictionary = _shares(pirate_picks)
	var keys: Array = []
	for k in c:
		keys.append(k)
	for k in p:
		if not c.has(k):
			keys.append(k)
	keys.sort_custom(func(x, y):
		return float(c.get(x, 0.0)) > float(c.get(y, 0.0)))
	var out: Array = []
	for k in keys:
		out.append({
			"lane": k,
			"cargo": float(c.get(k, 0.0)),
			"pirate": float(p.get(k, 0.0)),
			"cargo_n": int(cargo_picks.get(k, 0)),
			"pirate_n": int(pirate_picks.get(k, 0)),
		})
	return out

# Cargo presence on a lane BEFORE a pirate committed to it vs DURING the hunt.
#
# `window_frames` defaults to 22 GAME-MINUTES either side (79,200 frames), set
# against MEASURED courier latency rather than picked for tidiness. The first
# version used 3 game-minutes and could not have detected the effect it exists
# to test: cargo only avoids what it has HEARD, a robbery takes ~22 game-minutes
# to reach a station by hull, so a 3-minute window closes long before any news
# could arrive. It duly reported `ratio 1.00` and I read that as "cargo does not
# avoid pirates", which the measurement could not support.
#
# This is D22 repeating inside an instrument: a time constant set without
# checking it against delivery latency. The ledger already records that exact
# error for RISK_HALF_LIFE_FRAMES (5 min half-life against 22 min latency, so
# news was stale before it landed). Same mistake, one level up.
#
# Counts are cargo samples (i.e. hauler-seconds, see the header) on that lane.
#
# Returns per-hunt rows plus totals. A hunt whose lane never carried cargo in
# EITHER window is dropped from the ratio -- it says nothing about avoidance, and
# including it would drag the mean toward zero and manufacture the very finding
# this is meant to test.
static func avoidance_summary(window_frames: int = 79200) -> Dictionary:
	if pirate_hunts.is_empty() or cargo_timeline.is_empty():
		return {}
	var before_total: int = 0
	var during_total: int = 0
	var scored: int = 0
	var rows: Array = []
	for h in pirate_hunts:
		var f: int = int(h["frame"])
		var lane: String = h["lane"]
		var before: int = 0
		var during: int = 0
		for c in cargo_timeline:
			if c["lane"] != lane:
				continue
			var cf: int = int(c["frame"])
			if cf >= f - window_frames and cf < f:
				before += 1
			elif cf >= f and cf < f + window_frames:
				during += 1
		if before == 0 and during == 0:
			continue
		scored += 1
		before_total += before
		during_total += during
		rows.append({"lane": lane, "frame": f, "before": before, "during": during})
	if scored == 0:
		return {}
	return {
		"hunts_scored": scored,
		"hunts_total": pirate_hunts.size(),
		"before": before_total,
		"during": during_total,
		"ratio": (float(during_total) / float(before_total)) if before_total > 0 else -1.0,
		"rows": rows,
	}
