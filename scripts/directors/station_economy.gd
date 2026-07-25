extends RefCounted
class_name StationEconomy

# M53c Phase A -- the station economy director (design_ideas/station_economy.md;
# implementation_plans/m53c_demand_routing.md "Phase A"). A RefCounted living in
# ClusterManager.directors, ticked from ClusterManager.tick(dt) -- same director
# pattern as PirateGuild/TrafficGuild (design_ideas/jobs_and_itineraries.md §3),
# but simpler: no ledger of spawned entities, just a periodic pass over every
# STATION record's own stocks["self"] bins.
#
# PURE SUBSTRATE. Nothing outside this file reads stocks/market yet -- that is
# Phase B (postings) and later. This tick only makes the numbers move
# correctly: converters derive their own throughput from bin state (no
# authored `rate` on a bin -- see design doc "Converters: throughput is
# derived, not authored"), sinks drain unconditionally, sources deliver
# (scaffolding for mining traffic, Phase A only).
#
# Walks cluster.records DIRECTLY (not cluster.live_count()/live nodes) so a
# dormant station's economy advances exactly like a live one's -- the whole
# point of keeping this state on the ClusterEntity record rather than a live
# Ship field (see cluster_entity.gd's stocks doc comment). ClusterManager.tick()
# already calls every director's tick() unconditionally, after reconcile, so
# this needs no special wiring beyond being appended to `directors` (see
# main.gd's _bootstrap_campaign, alongside PirateGuild/TrafficGuild).
#
# Reference via the preload-const convention (CLAUDE.md's headless
# class-cache caveat -- never the bare class_name):
#   const StationEconomy = preload("res://scripts/directors/station_economy.gd")

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

# Per-converter stall state, exposed as readable data on the converter dict
# itself (conv["state"]) -- Phase B turns this into postable news; Phase A
# just needs it observable and correct. STARVED and BLOCKED are deliberately
# distinct (design doc "The two stall states are two different pieces of
# news"): STARVED = an input bin is empty, BLOCKED = an output bin is full.
enum ConverterState { RUNNING, STARVED, BLOCKED }

const DEFAULT_CONFIG := {
	"policy_period": 10.0,
	# "never trickles at 3%" -- below this achieved fraction, a converter
	# reports zero throughput instead of a token dribble. Not specified by the
	# design doc as an exact number; 5% is a reasonable floor that is clearly
	# distinguishable from "meaningfully running" without being so high it
	# eats ordinary partial-running behavior.
	"floor_fraction": 0.05,
}

var config: Dictionary = {}
var _elapsed: float = 0.0

func _init(cfg: Dictionary = {}) -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	for key in cfg:
		config[key] = cfg[key]

# ---------------------------------------------------------------------------
# The tick. dt-accumulated exactly like TrafficGuild's policy_period, so
# period accumulation "comes free" per the plan doc -- no new plumbing beyond
# appending this to ClusterManager.directors.
# ---------------------------------------------------------------------------

func tick(dt: float, cluster) -> void:
	_elapsed += dt
	var period: float = config.get("policy_period", 10.0)
	if period <= 0.0:
		return
	while _elapsed >= period:
		_elapsed -= period
		_economy_pass(cluster, period)

func _economy_pass(cluster, period: float) -> void:
	var dt_hours: float = period / 3600.0
	# Deliberately cluster.records, NOT a live-only iteration -- walks every
	# station regardless of liveness (the plan doc's explicit requirement;
	# ClusterManager.tick()'s OWN dormant-mover loop skips is_static records,
	# but directors are ticked separately and see the full record list).
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		_tick_station(rec, dt_hours)
	_log(cluster)

func _tick_station(rec, dt_hours: float) -> void:
	if not rec.stocks.has("self"):
		return   # no authored economy on this station (e.g. a mobile home) -- nothing to tick
	var self_bins: Dictionary = rec.stocks["self"]
	# BLOCKED must stop input consumption too (backpressure), so converters run
	# BEFORE sinks/sources -- not that ordering matters for correctness here
	# (each mechanism only touches its own declared commodities and clamps),
	# but converters are the interesting case and sinks/sources are simple
	# background rates.
	_run_converters(rec, self_bins, dt_hours)
	_run_sinks(rec, self_bins, dt_hours)
	_run_sources(rec, self_bins, dt_hours)

# ---------------------------------------------------------------------------
# Converters -- throughput derived from bin state, not an authored rate.
# achieved = min(rate, input_availability, output_headroom), scaled to the
# scarcest input/output as a FRACTION of the converter's declared in/out
# amounts (which are themselves lots/hour at rate=1.0). Below floor_fraction,
# achieved snaps to zero -- "a stalled converter consumes NOTHING" (no idle
# draw at all, not even a reduced one).
# ---------------------------------------------------------------------------

func _run_converters(rec, self_bins: Dictionary, dt_hours: float) -> void:
	var converters: Array = rec.industry.get("converters", [])
	if converters.is_empty():
		return
	var floor_fraction: float = config.get("floor_fraction", 0.05)
	for conv in converters:
		var ins: Dictionary = conv.get("in", {})
		var outs: Dictionary = conv.get("out", {})
		var rate: float = conv.get("rate", 1.0)

		var input_fraction: float = _sustainable_fraction(self_bins, ins, dt_hours, true)
		var output_fraction: float = _sustainable_fraction(self_bins, outs, dt_hours, false)

		var achieved: float = min(rate, min(input_fraction, output_fraction))
		var state: int = ConverterState.RUNNING
		if achieved < floor_fraction:
			achieved = 0.0
			# Whichever side was tighter is the reported reason. Ties resolve
			# to STARVED -- an empty input bin is the more common/legible
			# story, and in practice this codebase's authored converters never
			# tie (see home_cluster.gd).
			state = ConverterState.STARVED if input_fraction <= output_fraction else ConverterState.BLOCKED

		if achieved > 0.0:
			for c in ins.keys():
				var amt: float = ins[c]
				if amt > 0.0:
					_withdraw(self_bins, c, amt * achieved * dt_hours)
			for c in outs.keys():
				var amt: float = outs[c]
				if amt > 0.0:
					deliver(rec, "self", c, amt * achieved * dt_hours)

		conv["state"] = state
		conv["achieved"] = achieved

# The max fraction (0..1) of a converter's declared in/out amounts that the
# current bin state can sustain for one tick of dt_hours -- for inputs, how
# much stock is available to draw; for outputs, how much headroom is left
# before the bin fills. Starts at 1.0 (no commodities named -> unconstrained)
# and only ever gets pulled DOWN by min(), so the result is always in [0, 1].
func _sustainable_fraction(self_bins: Dictionary, amounts: Dictionary, dt_hours: float, is_input: bool) -> float:
	var fraction: float = 1.0
	if dt_hours <= 0.0:
		return fraction
	for c in amounts.keys():
		var amt: float = amounts[c]
		if amt <= 0.0:
			continue
		var bin: Dictionary = self_bins.get(c, {})
		var available: float
		if is_input:
			available = bin.get("stock", 0.0)
		else:
			available = bin.get("capacity", 0.0) - bin.get("stock", 0.0)
		var max_frac: float = available / (amt * dt_hours)
		fraction = min(fraction, max(0.0, max_frac))
	return fraction

# ---------------------------------------------------------------------------
# Sinks -- population upkeep and the like. A SEPARATE mechanism from
# converters that NEVER stops: it always attempts its full declared rate every
# tick regardless of whether any converter ran (design doc: "a cold refinery
# still drains volatiles -- because its people do, not because it does"). The
# clamp at _withdraw's bin floor is what keeps this from going negative; that
# clamp, not a stall check, is the only thing that ever slows a sink down.
# ---------------------------------------------------------------------------

func _run_sinks(rec, self_bins: Dictionary, dt_hours: float) -> void:
	var sinks: Dictionary = rec.industry.get("sinks", {})
	for c in sinks.keys():
		var rate: float = sinks[c]
		if rate > 0.0:
			_withdraw(self_bins, c, rate * dt_hours)

# ---------------------------------------------------------------------------
# Sources -- SCAFFOLDING standing in for mining traffic (design doc: "sources
# is scaffolding -- build the seam now"). Deliberately routes through
# deliver(), the same seam a real mining ship will call from docking_bay.gd's
# DOCKED hook later -- deleting this loop is then a one-line change, not a
# restructure.
# ---------------------------------------------------------------------------

func _run_sources(rec, self_bins: Dictionary, dt_hours: float) -> void:
	var sources: Dictionary = rec.industry.get("sources", {})
	for c in sources.keys():
		var rate: float = sources[c]
		if rate > 0.0:
			deliver(rec, "self", c, rate * dt_hours)

func _withdraw(self_bins: Dictionary, commodity: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if not self_bins.has(commodity):
		return
	var bin: Dictionary = self_bins[commodity]
	bin["stock"] = clampf(bin.get("stock", 0.0) - amount, 0.0, bin.get("capacity", 0.0))

# ---------------------------------------------------------------------------
# deliver() -- the ONE way stock increases (design doc, verbatim). Static so
# it's callable with no director instance -- the tick above calls it on
# itself, ClusterLoader calls it (via ensure_holder) at authoring time, and a
# future docking_bay.gd DOCKED hook will call it directly the same way.
# Clamps to the bin's capacity -- overflow simply stops accumulating (no
# failure state, per the design doc's depth-2-with-clamps decision).
# ---------------------------------------------------------------------------

static func deliver(rec, holder: String, commodity: String, amount: float) -> void:
	if amount <= 0.0:
		return
	ensure_holder(rec, holder)
	var bin: Dictionary = rec.stocks[holder][commodity]
	bin["stock"] = clampf(bin.get("stock", 0.0) + amount, 0.0, bin.get("capacity", 0.0))

# Guarantees rec.stocks[holder] exists and carries a FULLY POPULATED bin for
# every Commodity.ALL class (zeros where not already set) -- CLAUDE.md's
# missing-Dictionary-key trap, doubled by the two-level nesting here. Callers
# (ClusterLoader authoring "self", a party stockpile being created for the
# first time, deliver() above) only ever need a .get() guard on the HOLDER
# lookup; the commodity level is guaranteed by this function. Idempotent --
# never overwrites a bin that already exists, so calling it again (e.g.
# deliver() on an already-authored station) is always safe.
static func ensure_holder(rec, holder: String) -> void:
	if not rec.stocks.has(holder):
		rec.stocks[holder] = {}
	var bins: Dictionary = rec.stocks[holder]
	for c in Commodity.ALL:
		if not bins.has(c):
			bins[c] = default_bin()

static func default_bin() -> Dictionary:
	return {"stock": 0.0, "capacity": 0.0, "target": 0.0, "surplus_line": 0.0}

# ---------------------------------------------------------------------------
# urgency() -- the single derived read (design doc, verbatim). NEVER stored --
# always computed fresh from stock/target/surplus_line/capacity. Direction
# keys off STOCK (corrected twice in the design doc), which is what lets a
# holder flip from importer to exporter once over-served.
#
# Returns {"direction": "IMPORT"|"EXPORT"|"SATISFIED", "value": 0.0..1.0}.
# "SATISFIED" always carries value 0.0 (no posting, per the design doc).
# ---------------------------------------------------------------------------

static func urgency(rec, holder: String, commodity: String) -> Dictionary:
	var holder_bins: Dictionary = rec.stocks.get(holder, {})
	var bin: Dictionary = holder_bins.get(commodity, {})
	if bin.is_empty():
		return {"direction": "SATISFIED", "value": 0.0}

	var stock: float = bin.get("stock", 0.0)
	var target: float = bin.get("target", 0.0)
	var surplus_line: float = bin.get("surplus_line", 0.0)
	var capacity: float = bin.get("capacity", 0.0)

	if stock < target:
		var denom: float = target
		var v: float = 1.0 if denom <= 0.0 else clampf((target - stock) / denom, 0.0, 1.0)
		return {"direction": "IMPORT", "value": v}
	if stock > surplus_line:
		var denom2: float = capacity - surplus_line
		var v2: float = 1.0 if denom2 <= 0.0 else clampf((stock - surplus_line) / denom2, 0.0, 1.0)
		return {"direction": "EXPORT", "value": v2}
	return {"direction": "SATISFIED", "value": 0.0}

# ---------------------------------------------------------------------------
# withdraw() -- the general counterpart to deliver() (design doc's "the ONE
# way stock increases" gets its mirror here: the one way it decreases other
# than the tick's own sinks/converters). Any HOLDER, not just "self" -- an
# EXPORT posting is served by a ship picking cargo UP from a holder's bin,
# and Phase B2 repair draws down a station's own "self" bins the same way.
# Returns the amount ACTUALLY withdrawn (<= amount, less if the bin doesn't
# have enough), never negative, never below 0 stock -- a caller scales
# whatever it was about to do down to what stock allows, exactly deliver()'s
# clamp-not-fail discipline mirrored on the other side.
# ---------------------------------------------------------------------------

static func withdraw(rec, holder: String, commodity: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var holder_bins: Dictionary = rec.stocks.get(holder, {})
	var bin: Dictionary = holder_bins.get(commodity, {})
	if bin.is_empty():
		return 0.0
	var stock: float = bin.get("stock", 0.0)
	var taken: float = min(amount, stock)
	if taken <= 0.0:
		return 0.0
	bin["stock"] = clampf(stock - taken, 0.0, bin.get("capacity", 0.0))
	return taken

# ---------------------------------------------------------------------------
# M53c Phase B -- postings (design_ideas/station_economy.md "Postings are the
# universal coupling", "Pricing: urgency IS price discovery", principle 9).
#
# A posting is NOT a stored object -- it is DERIVED fresh from bin state every
# time it's asked for, same discipline as urgency() above (principle 4: one
# source of truth). That includes `quantity`: serving a posting moves STOCK
# via deliver()/withdraw(), and quantity is simply read back off that same
# stock, so "quantity depletes as served" needs no separate counter to drift
# out of sync with it.
#
# The one piece of REAL, independently-authored state is the market POLICY --
# eligibility (export control) and price multipliers (the political dial) --
# in rec.market[holder][commodity]:
#   { "eligible_flags": Array[String],   # [] = unrestricted (default)
#     "home_flag": String,               # who counts as "own flag" for pricing;
#                                         #   defaults to rec.transponder_flag
#                                         #   when holder == "self", else ""
#     "own_flag_multiplier": float,      # applied when asker == home_flag (default 1.0)
#     "foreign_multiplier": float }      # applied otherwise (default 1.0)
# Absent/empty market entry -> unrestricted eligibility, uniform (1.0) pricing
# regardless of asker -- the sane default when a station authors no policy.
# ---------------------------------------------------------------------------

# Mildly convex price curve base (design doc "Pricing: urgency IS price
# discovery" -- "Mildly convex in urgency": linear makes everything lukewarm,
# strongly convex makes the world oscillate between neglect and stampede).
# PRICE_BASE=100.0 matches the design doc's own worked "payout = 100 x
# urgency" illustration; PRICE_CONVEX_EXP is this section's own explicit
# correction on top of that (deliberately linear) illustration.
const PRICE_BASE := 100.0
const PRICE_CONVEX_EXP := 1.5

# M53c Phase B2 -- repair's HP-per-lot conversion (design doc "Repair closes
# the loop"): hull draws REFINED at 1 lot ~= 500 HP; every OTHER component
# type draws GOODS at 1 lot ~= 150 HP (~3.3x dearer per HP -- GOODS is the
# scarce import, so systems damage hurts more than structure). Lives here,
# not on Ship, so the economy's own conversion table stays in ONE place.
const HULL_HP_PER_LOT := 500.0
const SYSTEM_HP_PER_LOT := 150.0

static func _market_policy(rec, holder: String, commodity: String) -> Dictionary:
	return rec.market.get(holder, {}).get(commodity, {})

# Eligibility -- export control (design doc: "Coldreach restricting VOLATILES
# to locally-flagged hulls... the restriction stops AT THE SOURCE"). Anyone
# eligible when no policy is authored (or the list is empty).
static func is_eligible(rec, holder: String, commodity: String, flag: String) -> bool:
	var eligible_flags: Array = _market_policy(rec, holder, commodity).get("eligible_flags", [])
	if eligible_flags.is_empty():
		return true
	return eligible_flags.has(flag)

# Principle 9 -- EVERY political decision lives HERE, never in urgency() or
# _price_curve() below. This is the ONLY function price() consults for "who's
# asking"; calling it with two different asker_flag values must move price
# and nothing else (see _price_curve, which never sees a flag at all).
static func _policy_multiplier(rec, holder: String, commodity: String, asker_flag: String) -> float:
	var policy: Dictionary = _market_policy(rec, holder, commodity)
	var home_flag: String = policy.get("home_flag", rec.transponder_flag if holder == "self" else "")
	if asker_flag != "" and home_flag != "" and asker_flag == home_flag:
		return policy.get("own_flag_multiplier", 1.0)
	return policy.get("foreign_multiplier", 1.0)

# f(urgency) -- flag-BLIND by construction (no asker parameter at all, so it
# is structurally impossible for politics to leak in here). Mildly convex.
static func _price_curve(urgency_value: float) -> float:
	return PRICE_BASE * pow(clampf(urgency_value, 0.0, 1.0), PRICE_CONVEX_EXP)

# price() = f(urgency) x policy_multiplier(asker) (design doc, verbatim).
# asker_flag == "" reads the board's own posted number with no per-flag
# discount/surcharge applied -- the "globally readable" board Phase B builds,
# no fog yet.
static func price(rec, holder: String, commodity: String, asker_flag: String = "") -> float:
	var u: Dictionary = urgency(rec, holder, commodity)
	if u["direction"] == "SATISFIED":
		return 0.0
	return _price_curve(u["value"]) * _policy_multiplier(rec, holder, commodity, asker_flag)

# The posting itself. {} when the holder is SATISFIED -- "a posting appears
# when stock crosses the threshold and closes when satisfied" falls straight
# out of urgency() flipping to SATISFIED, no separate open/close bookkeeping.
# `eligible` reflects `asker_flag` (pass "" to read the board with no asker in
# mind -- always eligible, since eligibility restricts a PARTY, not the
# board). `urgency` is reported so callers/tests can assert it stays IDENTICAL
# across two different asker_flag calls even as `price` moves (principle 9's
# regression sentinel).
static func get_posting(rec, holder: String, commodity: String, asker_flag: String = "") -> Dictionary:
	var u: Dictionary = urgency(rec, holder, commodity)
	if u["direction"] == "SATISFIED":
		return {}
	var bin: Dictionary = rec.stocks.get(holder, {}).get(commodity, {})
	var quantity: float
	if u["direction"] == "IMPORT":
		quantity = max(0.0, bin.get("target", 0.0) - bin.get("stock", 0.0))
	else:
		quantity = max(0.0, bin.get("stock", 0.0) - bin.get("surplus_line", 0.0))
	return {
		"holder": holder,
		"commodity": commodity,
		"direction": u["direction"],
		"urgency": u["value"],
		"quantity": quantity,
		"eligible_flags": _market_policy(rec, holder, commodity).get("eligible_flags", []),
		"eligible": true if asker_flag == "" else is_eligible(rec, holder, commodity, asker_flag),
		"price": price(rec, holder, commodity, asker_flag),
	}

# "Payout is fixed at acceptance, not recomputed on arrival" (explicit test
# requirement) -- snapshots price/direction the MOMENT a server commits, so a
# delivery landing after the bin state has since moved (someone else got
# there first, or the station's own tick ran) is never a rules argument: the
# server is paid what it was promised, for whatever actually transfers.
# Returns {} for an ineligible asker or a posting that's already closed --
# nothing to accept.
static func accept_posting(rec, holder: String, commodity: String, asker_flag: String) -> Dictionary:
	var posting: Dictionary = get_posting(rec, holder, commodity, asker_flag)
	if posting.is_empty() or not posting["eligible"]:
		return {}
	return {
		"holder": holder,
		"commodity": commodity,
		"direction": posting["direction"],
		"price": posting["price"],
		"asker_flag": asker_flag,
	}

# Spends an acceptance snapshot: moves up to `amount` of stock -- IMPORT means
# the server delivers TO the holder (deliver()); EXPORT means the server picks
# UP from the holder (withdraw()) -- clamped by whichever of those two clamps
# to the live bin, so the actual transfer can land under `amount` (bin
# filled/emptied since accept). Payout is `acceptance.price * transferred`,
# the ACTUAL amount, never the requested one -- no free money for a delivery
# that didn't fully land. Several servers spending acceptances against the
# same (holder, commodity) is exactly "quantity depletes as served, not an
# exclusive claim" -- each call reads/writes the live bin, no reservation
# anywhere.
static func fulfill(rec, acceptance: Dictionary, amount: float) -> Dictionary:
	if acceptance.is_empty() or amount <= 0.0:
		return {"transferred": 0.0, "payout": 0.0}
	var holder: String = acceptance["holder"]
	var commodity: String = acceptance["commodity"]
	var before: float = rec.stocks.get(holder, {}).get(commodity, {}).get("stock", 0.0)
	if acceptance["direction"] == "IMPORT":
		deliver(rec, holder, commodity, amount)
	else:
		withdraw(rec, holder, commodity, amount)
	var after: float = rec.stocks.get(holder, {}).get(commodity, {}).get("stock", 0.0)
	var transferred: float = abs(after - before)
	return {"transferred": transferred, "payout": transferred * float(acceptance["price"])}

# Dev visibility only (same "console is omniscient by declaration" convention
# as PirateGuild/TrafficGuild's own _event()/_log()) -- one line per station
# whose converters aren't all RUNNING. Silent when nothing is stalled, which
# is the common case with the reference-table rates and generous auto-sized
# bins.
func _log(cluster) -> void:
	if not (DebugSettings and DebugSettings.get_choice("station_economy_log") == DebugSettings.StationEconomyLog.ON):
		return
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		var converters: Array = rec.industry.get("converters", [])
		for conv in converters:
			var state: int = conv.get("state", ConverterState.RUNNING)
			if state == ConverterState.RUNNING:
				continue
			var reason: String = "STARVED" if state == ConverterState.STARVED else "BLOCKED"
			print("[StationEconomy] %s converter %s -> %s is %s" %
				[rec.name, str(conv.get("in", {})), str(conv.get("out", {})), reason])
