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

const ORE := "ORE"               # mining outposts -- the export product
const VOLATILES := "VOLATILES"   # Coldreach only -- life support, locally sourced
const REFINED := "REFINED"       # Refinery Prime, from ORE -- structure and parts
const GOODS := "GOODS"           # imported only, via Ironhold -- machinery, medicine, tech

# Iterated wherever a bin dict must be FULLY populated for all four classes
# (CLAUDE.md's missing-Dictionary-key trap -- see cluster_entity.gd's stocks
# field). Order is not meaningful, just stable.
const ALL := [ORE, VOLATILES, REFINED, GOODS]
