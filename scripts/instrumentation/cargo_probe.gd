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
static func note(direction: String, requested: float, allowed: float, transferred: float) -> void:
	if not enabled:
		return
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

# Fraction of the PLANNED pickup volume that actually made it aboard. Returns
# -1.0 when nothing was attempted, so "no pickups" cannot be misread as "0%
# delivered" -- the same convention as EngagementProbe.stop_rate().
static func pickup_yield() -> float:
	return (pickup_transferred / pickup_requested) if pickup_requested > 0.0 else -1.0

static func drop_yield() -> float:
	return (drop_transferred / drop_requested) if drop_requested > 0.0 else -1.0
