extends RefCounted

# WHERE DOES THE CARGO GO? OFF by default; a sim turns it on.
#
# D67 measured a ~10x gap and could not explain it. With no haulers draining
# them, postings offer 3.96 lots against a 4.0 cap (economy_clock, seconds);
# campaigns realize 0.34-0.61. Something between "the posting exists" and "a
# hull is carrying it" loses 90% of the load.
#
# THREE HYPOTHESES DIED before this file existed, each to a measurement rather
# than an argument: fleet over-provisioning (a 3x fleet A/B moved the mean
# 0.22 -> 0.23), "it is not warm-up" (killed by reading sim_harness's seeding),
# and "the economy is the limit" (killed by economy_clock). So this is
# deliberately NOT a fourth hypothesis -- it is a direct count at the line that
# does the thing, which is the rule that finally worked on D50 (`386 FleeLeaf
# ticks stolen` against a 387-frame gap).
#
# `Ship.serve_posting` is that line. It receives the PLANNED amount -- the
# number route_itinerary() stamped on the DOCK_AT step when the route was
# chosen -- and returns what actually moved, with M55a's clamp in between:
#
#   requested   what the plan asked for, decided at ROUTE time
#     |  <- M55a: hull capacity (EXPORT) or possession (IMPORT)
#   allowed     what this hull could physically do
#     |  <- StationEconomy.fulfill: clamped to the live bin
#   transferred what actually moved
#
# The two gaps mean completely different things and want opposite fixes:
#
#   requested -> allowed    the HULL was the limit. On a pickup that means it
#                           arrived with cargo still aboard; on a delivery it
#                           means it is not carrying what it promised (robbed,
#                           or a short pickup upstream).
#   allowed -> transferred  the POSTING was the limit -- it held less than when
#                           the route was planned. That is CONTENTION: someone
#                           else got there first, or the station's own tick
#                           moved the bin. This is the number D67 needs.
#
# Split by direction because a pickup and a delivery are different questions:
# EXPORT is "how much did I manage to load", IMPORT is "how much did I manage to
# deliver". Folding them together is how "cargo is small" stayed unexplained for
# a day.

static var enabled: bool = false

# EXPORT -- the pickup leg. This is where load size is DECIDED.
static var pickup_requested: float = 0.0
static var pickup_allowed: float = 0.0
static var pickup_transferred: float = 0.0
static var pickup_events: int = 0
static var pickup_short: int = 0        # transferred < allowed: the posting had less than planned

# IMPORT -- the delivery leg.
static var drop_requested: float = 0.0
static var drop_allowed: float = 0.0
static var drop_transferred: float = 0.0
static var drop_events: int = 0
static var drop_short: int = 0

# --- PER-TRANSFER LEDGER ---------------------------------------------------
#
# The aggregates above sum, and a sum hides three things this file exists to
# find. Mean 0.128 across 54 pickups could be 54 loads of 0.13 or 50 of 0.02
# plus 4 of 1.5 -- completely different diagnoses. It has no time axis, so it
# cannot say whether load size is flat (warm-up dilution of a whole-run mean) or
# still climbing (a drifting equilibrium, i.e. the fleet under-serving). And it
# cannot attribute: most lanes healthy with two starving reads identically to
# every lane mediocre.
#
# ONE ROW PER TRANSFER, not per minute. A hull's manifest only changes AT a
# transfer, so per-minute sampling records the same value repeatedly AND can
# still miss a load-and-unload that happens between two samples. The event is
# the correct sampling unit: strictly more informative per row, and it cannot
# miss one.
#
# THEFT IS IN HERE TOO, and it has to be. Three events change a manifest and
# only two go through serve_posting -- LOAD and UNLOAD there, THEFT in
# JobSteps.transfer_loot. Logging only the dock leaves a hole exactly where the
# interesting thing happens, and makes the conservation identity
# (sum of bins + sum of manifests) unclosable.
#
# `local_qty` is the posting quantity at THIS end, read BEFORE the transfer
# depletes it. The far end's quantity is not reachable from a dock, but it does
# not need to be: `requested` already encodes min(LOT_SIZE, min(both)), so
# `requested < local_qty` proves the OTHER side (or the hold) was the binding
# constraint, and `requested == local_qty` proves this one was.
static var _log = null

static func _ensure_log() -> void:
	if _log != null:
		return
	DirAccess.make_dir_recursive_absolute("res://tmp")
	_log = FileAccess.open("res://tmp/cargo_transfers.csv", FileAccess.WRITE)
	if _log != null:
		_log.store_line("minute,event,ship,counterparty,commodity,requested,allowed,transferred,local_qty")

static func _row(event: String, ship_name: String, counterparty: String, commodity: String,
		requested: float, allowed: float, transferred: float, local_qty: float) -> void:
	_ensure_log()
	if _log == null:
		return
	_log.store_line("%.2f,%s,%s,%s,%s,%.4f,%.4f,%.4f,%.4f" % [
		Engine.get_physics_frames() / 3600.0, event, ship_name, counterparty, commodity,
		requested, allowed, transferred, local_qty])
	_log.flush()   # store_line BUFFERS -- a run killed mid-way must not lose the ledger

static func reset() -> void:
	pickup_requested = 0.0
	pickup_allowed = 0.0
	pickup_transferred = 0.0
	pickup_events = 0
	pickup_short = 0
	drop_requested = 0.0
	drop_allowed = 0.0
	drop_transferred = 0.0
	drop_events = 0
	drop_short = 0

# Called once per settled transaction, from Ship.serve_posting, with all three
# numbers in hand. Cheap: one static bool read on a path that runs at most once
# per dock, never per frame.
static func note(direction: String, requested: float, allowed: float, transferred: float,
		ship_name: String = "?", station_name: String = "?", commodity: String = "?",
		local_qty: float = -1.0) -> void:
	if not enabled:
		return
	# EXPORT is the station shipping out, i.e. the hull LOADING. Named from the
	# hull's point of view in the ledger, because that is who the row is about.
	_row("LOAD" if direction == "EXPORT" else "UNLOAD",
		ship_name, station_name, commodity, requested, allowed, transferred, local_qty)
	if direction == "EXPORT":
		pickup_requested += requested
		pickup_allowed += allowed
		pickup_transferred += transferred
		pickup_events += 1
		if transferred < allowed - 0.0001:
			pickup_short += 1
	elif direction == "IMPORT":
		drop_requested += requested
		drop_allowed += allowed
		drop_transferred += transferred
		drop_events += 1
		if transferred < allowed - 0.0001:
			drop_short += 1

# Theft -- the third manifest-changing event, and the only one not at a dock.
# `requested` is what the victim was carrying of this commodity (what a pirate
# with unlimited room would have taken) and `local_qty` carries the robber's
# free volume, so a partial take is legible as such rather than as a small
# victim.
static func note_theft(robber_name: String, victim_name: String, commodity: String,
		victim_had: float, taken: float, robber_free: float) -> void:
	if not enabled:
		return
	_row("THEFT", robber_name, victim_name, commodity, victim_had, taken, taken, robber_free)

# Fraction of the PLANNED pickup volume that actually made it aboard. Returns
# -1.0 when nothing was attempted, so "no pickups" cannot be misread as "0%
# delivered" -- the same convention as EngagementProbe.stop_rate().
static func pickup_yield() -> float:
	return (pickup_transferred / pickup_requested) if pickup_requested > 0.0 else -1.0

static func drop_yield() -> float:
	return (drop_transferred / drop_requested) if drop_requested > 0.0 else -1.0
