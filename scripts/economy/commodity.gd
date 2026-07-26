class_name Commodity

# M53c Phase A -- the four commodity classes (design_ideas/station_economy.md
# "The commodity classes, and the cluster's economic shape"). Static string
# constants, same convention as Standing.FLAG_* (scripts/combat/standing.gd):
# a bare source of truth for a value that rides mail, postings, and bins, so
# nothing downstream compares against a hand-typed literal.
#
# Reference via the preload-const convention (CLAUDE.md's headless
# class-cache caveat -- never the bare class_name):
#   const Commodity = preload("res://scripts/economy/commodity.gd")
#
# Four, not three: GOODS is the cluster's only external dependency (imported
# via the Nexus wormhole), which is the whole point -- folding it into REFINED
# would erase the import chokepoint. See the design doc's "why four classes."

const ORE := "ORE"               # mining outposts -- feedstock for REFINED
const VOLATILES := "VOLATILES"   # Coldreach only -- life support, locally sourced
const REFINED := "REFINED"       # Refinery Prime, from ORE -- structure and parts, the main export
const GOODS := "GOODS"           # imported only, via Ironhold -- machinery, medicine, tech
# M53d -- exotics, mined only in Meridian space (Halvorsen Claim, Corvus
# Yards). The cluster's SECOND export and the reason Meridian is a peer
# sovereign rather than two mining camps: it is an INCOME, not a utility.
# Consumed by nobody here -- every lot exists to leave through Ironhold's
# wormhole gate, which is precisely what makes it weak leverage. Home does not
# need rare, so home can close the gate at no cost to itself while Meridian
# loses everything; Meridian's counter-lever (Coldreach's air) is existential
# and therefore an escalation, not an everyday move. That asymmetry is why the
# two coexist, and it falls out of this graph rather than a diplomacy system.
# See implementation_plans/m53d_meridian_sovereignty.md.
const RARE := "RARE"

# Iterated wherever a bin dict must be FULLY populated for all classes
# (CLAUDE.md's missing-Dictionary-key trap -- see cluster_entity.gd's stocks
# field). Order is not meaningful, just stable.
const ALL := [ORE, VOLATILES, REFINED, GOODS, RARE]

# ---------------------------------------------------------------------------
# Bin geometry (consumed by home_cluster.gd's _bin()).
#
# THE ECONOMY HAS A HIDDEN TIME-CONSTANT and this is where it is set. A
# producer starts at target (50% of capacity) and opens its first EXPORT
# posting at surplus_line (85%), a climb of 35% of capacity. When capacity is
# `rate x hours`, the time to make that climb is 0.35 x hours -- INDEPENDENT of
# the rate. So this table, not the rates, is what decides how fast the economy
# moves. (Corollary worth knowing: scaling every rate by K changes nothing,
# because capacity scales with it and the constant cancels.)
#
# It was a single global 24.0, which put the economy on a clock 30-60x slower
# than transport: 8.4h to open an export and 12h+ of buffer, against a hauler
# round trip of 12-24 game-MINUTES. A player sees 2-5 round trips in a session
# and therefore saw no economic movement at all, and the 30-minute traffic sim
# could not observe trade in half the commodities.
#
# Now per-class, because the right answer genuinely differs and the difference
# is good fiction:
#   VOLATILES  short  -- running out kills people; that should be a live threat
#                        you can watch closing in, not a 9-day abstraction.
#   ORE/REFINED/GOODS  medium -- industrial, tolerant of a late shipment.
#   RARE       long   -- nobody dies without exotics. Slow is CORRECT here: it
#                        accumulates quietly for the Nexus hauler to collect,
#                        which is the intended design rather than a defect.
const BUFFER_HOURS := {
	ORE: 6.0,
	VOLATILES: 3.0,
	REFINED: 6.0,
	GOODS: 6.0,
	RARE: 24.0,
}

# Floor on bin capacity, in LOTS (RoutePlanner.LOT_SIZE is 1.0, so lots and
# units coincide today -- the point is that this is denominated in hauler
# loads, not in an arbitrary absolute).
#
# The floor exists for a real reason: a bin must hold several hauler loads, or
# one delivery slams it from empty to overflowing and it behaves like a switch
# instead of a buffer. It was 50 -- which is FIFTY hauler loads, 5-14x more
# than that argument needs, and it wrecked the time-constant above for every
# low-rate bin (RARE took 44 hours to open an export instead of 8.4, because
# its climb was a fixed 17.5 lots rather than 35% of its own throughput).
const MIN_BIN_LOTS := 8.0
