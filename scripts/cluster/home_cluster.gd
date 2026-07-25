extends RefCounted
class_name HomeCluster

# M15/M16 -- the authored home cluster: The Sovereign Drift. Three medium-station
# hubs spread across the cluster, three small-station mining outposts each sitting
# on an asteroid field, a beacon road linking the two main hubs, and the Nexus
# wormhole near the central hub. All coordinates sit well inside the +/-500k
# float32 budget. See implementation_plans/m16_static_landmarks_design.md.
#
# M53a -- Pass 1/Slice A: the cluster doubled in radius (more room for traffic
# to be lonely in) and the Nexus wormhole moved from the periphery to near
# Ironhold (now the cluster's front door). SCALE is applied to every authored
# position below (stations/outposts/patrol centers/patrol radii/field centers);
# comms/sensor ranges, asteroid-field radii, and the beacon road's ~25k spacing
# stay ABSOLUTE on purpose -- the world gets bigger relative to your senses,
# not your sensors. See implementation_plans/m53a_economic_expansion.md.
const SCALE := 2.0

const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")
const MobileHome = preload("res://scripts/ships/mobile_home.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

# M53c Phase A -- the home cluster's economy (design_ideas/station_economy.md
# "Worked reference case"). Rock counts are the SAME numbers driving
# def.add_field's `count` below -- named here so the ore-extraction sources
# authored per outpost DERIVE from them (design doc: "ore extraction is not
# invented... home_cluster.gd already authors 32/22/18/18/15 rocks per
# asteroid field") instead of duplicating the number as a second hardcoded
# constant (CLAUDE.md's "duplicated world constants" warning).
const SLAG_BAY_ROCKS := 32
const COLDREACH_ROCKS := 22
const DEEPCUT_ROCKS := 15
const HALVORSEN_ROCKS := 18
const CORVUS_ROCKS := 18
# lots/hour of ORE extracted per rock -- reproduces the reference table's
# Slag Bay/Halvorsen/Corvus/Deepcut ORE sources exactly (32/18/18/15 * 0.1 =
# 3.2/1.8/1.8/1.5). Deliberately NOT applied to Coldreach's rock count: its
# field is ice-rich (mostly VOLATILES), so its small ORE byproduct (0.6) and
# its VOLATILES source (2.60) are both authored directly below rather than
# derived -- the plan doc calls for deriving ORE extraction specifically, and
# Coldreach's ore yield isn't the same mechanism as a dedicated mining
# outpost's.
const ORE_RATE_PER_ROCK := 0.1

# M53a -- home carries its OWN crypto tag; the player is NOT crypto-kin of
# home (keeps TEAM_PLAYER, see main.gd's _spawn_player_ship). Flying
# FLAG_DRIFT with the transponder on, the player reads NEUTRAL to home
# (compute_standing's "reporting clean" tier): left alone (station/patrol AI
# engages HOSTILE only) and still gets dock grants (NEUTRAL qualifies), but
# is flippable to HOSTILE on aggression like anyone else -- the M52
# warrant/interdiction contract now applies to the player symmetrically
# instead of the old crypto handshake making them immune.
const HOME_IFF := ["TEAM_DRIFT"]

# M53d -- the peer sovereign's crypto tag. A module-level const (not the local
# it used to be) because Coldreach is authored ~100 lines above the Meridian
# colony block and needs it too. See the M53d note on Coldreach below.
const MERIDIAN_IFF := ["TEAM_MERIDIAN"]

const BEACON_RANGE := 50000.0   # matches Buoy's comms range

static func build() -> ClusterDef:
	var def = ClusterDef.new()
	def.name = "The Sovereign Drift (Home)"
	def.bounds = Rect2(-500000, -500000, 1000000, 1000000)
	def.player_start = Vector2(3000, 0)   # stays put -- Ironhold itself is still at (0,0)

	# --- Hubs (medium stations) ---
	# M42 -- sid is the story overlay's join key (story/home_cluster_overlay.gd,
	# story/characters.gd); only entities story content actually references
	# need one -- Ironhold (Aunt Stephanie) now, the five homes for M43's Todd
	# + residents.
	_station(def, 1, "Ironhold", MediumStation, Vector2(0, 0), "hub", "ironhold", HOME_IFF, Standing.FLAG_DRIFT, _economy_ironhold())
	_station(def, 2, "Drift Market", MediumStation, Vector2(200000, 40000) * SCALE, "hub", "drift_market", HOME_IFF, Standing.FLAG_DRIFT, _economy_drift_market())
	_station(def, 3, "Refinery Prime", MediumStation, Vector2(40000, -150000) * SCALE, "hub", "refinery_prime", HOME_IFF, Standing.FLAG_DRIFT, _economy_refinery_prime())

	# --- Mining outposts (small stations), each parked on a field ---
	var slag_bay_pos: Vector2 = Vector2(150000, 110000) * SCALE
	var coldreach_pos: Vector2 = Vector2(-70000, 90000) * SCALE
	var deepcut_pos: Vector2 = Vector2(90000, -170000) * SCALE
	_station(def, 10, "Slag Bay", SmallStation, slag_bay_pos, "outpost", "", HOME_IFF, Standing.FLAG_DRIFT, _economy_slag_bay())
	# M53d -- Coldreach flies the MERIDIAN flag, not home's. It holds the
	# cluster's only VOLATILES source (its field reads ice-rich -- see
	# _economy_coldreach below), so this single flag is what stops Meridian
	# being a client state: home breathes Meridian's air (existential, fast)
	# while Meridian depends on home for REFINED, GOODS import and all export
	# access (economic, slow). Mutual assured disruption -- which is what
	# explains why they coexist despite the jurisdiction seam instead of one
	# absorbing the other. See implementation_plans/m53d_meridian_sovereignty.md.
	#
	# It also makes the border CONTIGUOUS rather than scattered: every Meridian
	# station now sits at x < 0 (Coldreach -140k, Halvorsen -280k, Corvus -300k)
	# and every home station at x >= 0, with Ironhold a capital on the line. And
	# Coldreach is Ironhold's NEAREST neighbour (228k, vs 310k to Refinery
	# Prime), so the shortest, highest-volume lane in the cluster -- already
	# authored as record 701 "Ore Barge" -- becomes the interstate artery.
	#
	# 701 deliberately stays a HOME hauler: home reaching across the border to
	# fetch its own air is the dependency made visible, and it puts a home hull
	# in foreign, UNPATROLLED space (no patrol loop reaches Coldreach -- Alpha
	# and Bravo sit on Ironhold and Drift Market with 24k radii). That is the
	# escort market's natural origin: overwhelming interest, zero jurisdiction.
	_station(def, 11, "Coldreach", SmallStation, coldreach_pos, "outpost", "", MERIDIAN_IFF, Standing.FLAG_MERIDIAN, _economy_coldreach())
	_station(def, 12, "Deepcut", SmallStation, deepcut_pos, "outpost", "", HOME_IFF, Standing.FLAG_DRIFT, _economy_deepcut())

	# --- Asteroid fields on the outposts (loader expands into individual rocks) ---
	# Centers scale with their stations; RADII stay absolute (sized for
	# mining/sensor scale, which doesn't change). Slag Bay's field is the M43
	# search field -- its radius (16k) is unchanged so the check_on_todd search
	# geometry (elimination across the whole field) is preserved; only its
	# center moves with the station.
	def.add_field({"center": slag_bay_pos, "radius": 16000.0, "count": SLAG_BAY_ROCKS, "seed": 1})
	def.add_field({"center": coldreach_pos, "radius": 12000.0, "count": COLDREACH_ROCKS, "seed": 2})
	def.add_field({"center": deepcut_pos, "radius": 9000.0, "count": DEEPCUT_ROCKS, "seed": 3})

	# --- Mobile Homes (civilian habitats), all parked in the Slag Bay field ---
	# M43 -- one community, one search area ("ask the neighbors; those folks
	# see everything"): the residents are Todd's neighbors, so they live where
	# the mission looks. Spread across the expanded field so eliminating the
	# unnamed contacts takes real flying; Claim 42 (Todd) sits out on the far
	# spinward edge, furthest from the field's mouth (and where Wex's rambling
	# actually points, for a player who listens).
	#
	# M53a -- the field CENTER scaled 2x with its station, but the five homes'
	# positions RELATIVE to the center must stay unchanged (scaling them too
	# would spread them across a 2x-wider span and break the M43 elimination
	# search). So translate each home by the same delta the center moved,
	# rather than scaling its absolute coordinate.
	var slag_bay_delta: Vector2 = slag_bay_pos - Vector2(150000, 110000)
	_home(def, 200, "Hermit's Rest", Vector2(145000, 115000) + slag_bay_delta, "hermits_rest")
	_home(def, 201, "Claim 42", Vector2(159000, 99000) + slag_bay_delta, "claim_42")
	_home(def, 202, "The Deep Freeze", Vector2(140000, 103000) + slag_bay_delta, "deep_freeze")
	_home(def, 203, "Lucky Strike", Vector2(154000, 121000) + slag_bay_delta, "lucky_strike")
	_home(def, 204, "Rock Bottom", Vector2(162000, 114000) + slag_bay_delta, "rock_bottom")

	# --- Beacon road: Ironhold (0,0) -> Drift Market (400000,80000) ---
	# M53a -- the road is now 2x longer (~408k vs ~204k), so it needs more
	# interior beacons to hold the SAME ~25k absolute spacing (a surveilled
	# corridor's spacing is its identity, not something that scales with the
	# cluster). 15 interior beacons over 16 segments reproduces the original
	# ~25.5k spacing exactly (same math, twice the road).
	var a := Vector2(0, 0)
	var b := Vector2(200000, 40000) * SCALE
	var beacon_count := 15
	for i in range(beacon_count):
		var f: float = float(i + 1) / float(beacon_count + 1)   # interior fractions
		_beacon(def, 100 + i, "Beacon " + str(i + 1), a.lerp(b, f))
	var edges: Array = []
	for i in range(beacon_count - 1):
		edges.append([100 + i, 100 + i + 1])
	def.beacon_edges = edges

	# --- Nexus wormhole, the cluster's front door near Ironhold ---
	# M53a -- relocated from the periphery to near the central hub: transient
	# traffic (Pass 3's wormhole freighters) now flows past Ironhold naturally,
	# and pirate arrivals/exfils have to transit real space instead of
	# skulking on the edge. Placed opposite the beacon road's heading (the road
	# runs +x/+y toward Drift Market, so the wormhole sits -x) at 35k out --
	# clear of the 25k station keep-away and outside Ironhold's 24k patrol
	# loop, confirmed by ClusterValidator.
	def.add_entity({
		"id": 500, "name": "Nexus Wormhole", "hull": Wormhole,
		"kind": ClusterEntity.Kind.WORMHOLE, "pos": Vector2(-35000, 0),
		"iff_tags": [], "is_static": true,
	})

	# --- Light-attack-craft patrols (loop a diamond around a hub) ---
	_patrol(def, 600, "Patrol Alpha", LightAttackCraft, Vector2(0, 0), 12000.0 * SCALE)         # Ironhold
	_patrol(def, 601, "Patrol Bravo", LightAttackCraft, Vector2(200000, 40000) * SCALE, 12000.0 * SCALE) # Drift Market

	# --- Cargo shuttles on fixed lanes (not a full mesh), starting at Ironhold ---
	_cargo(def, 700, "Mule", Vector2(0, 0), Vector2(200000, 40000) * SCALE)    # hub <-> hub, down the road
	_cargo(def, 701, "Ore Barge", Vector2(0, 0), coldreach_pos) # hub <-> Coldreach outpost

	# --- M53a Pass 2 -- peer sovereign: the Meridian Combine ---
	# A second, unrelated flag/crypto-tag sharing the cluster (NOT HOME_IFF,
	# NOT FLAG_DRIFT): two mining colonies of their own, each with a cargo
	# lane back to Ironhold. _station()/_cargo() default to the home identity
	# above, so passing the Meridian iff_tags/flag explicitly is the only
	# thing that makes these different from an ordinary outpost/hauler --
	# which in turn means their warrant_authority defaults to FLAG_MERIDIAN
	# (M52b's "stations default warrant_authority to their own flag"), the
	# jurisdiction seam a home patrol's warrants can't reach and vice versa
	# (test_jurisdiction_seam.gd pins this as the slice's payoff assertion).
	# "Meridian Combine" is a placeholder name -- see the FLAG_MERIDIAN
	# comment in standing.gd.
	#
	# Coordinates: Slice A's 2x geometry left the (-,-) and (-,+) quadrants
	# empty (home stations cluster in +x and the wormhole sits just -x of
	# Ironhold at (-35000,0)) -- both colonies sit there, each 200k+ from
	# every existing station/field/patrol-loop/beacon-road point and inside
	# the +/-450k margin the plan calls for.
	var meridian_iff := MERIDIAN_IFF
	var halvorsen_pos: Vector2 = Vector2(-280000, -260000)   # (-,-) quadrant, empty
	var corvus_pos: Vector2 = Vector2(-300000, 340000)        # (-,+) quadrant, clear of Coldreach
	_station(def, 13, "Halvorsen Claim", SmallStation, halvorsen_pos, "outpost", "", meridian_iff, Standing.FLAG_MERIDIAN, _economy_halvorsen())
	_station(def, 14, "Corvus Yards", SmallStation, corvus_pos, "outpost", "", meridian_iff, Standing.FLAG_MERIDIAN, _economy_corvus())
	def.add_field({"center": halvorsen_pos, "radius": 10000.0, "count": HALVORSEN_ROCKS, "seed": 4})
	def.add_field({"center": corvus_pos, "radius": 10000.0, "count": CORVUS_ROCKS, "seed": 5})
	_cargo(def, 702, "Meridian Runner", Vector2(0, 0), halvorsen_pos, OreShuttle, meridian_iff, Standing.FLAG_MERIDIAN)
	_cargo(def, 703, "Combine Hauler", Vector2(0, 0), corvus_pos, OreShuttle, meridian_iff, Standing.FLAG_MERIDIAN)

	return def

## M53a -- iff_tags/flag are optional, defaulting to home's own identity so
## every pre-Pass-2 call site (positional, 6 args) is behaviorally unchanged.
## A peer-sovereign call site (e.g. the Meridian colonies below) passes its
## own iff_tags + flag; warrant_authority always derives from `flag`, so a
## peer station gets the jurisdiction-seam default for free (M52b).
## M53c Phase A -- `economy` is optional and defaults to {} (no industry, inert
## zero bins via ClusterLoader's _init_economy) so every pre-Phase-A call site
## stays behaviorally unchanged. See the design doc's "Worked reference case"
## and the _economy_*() authoring functions below for the home cluster's own
## values.
static func _station(def, id: int, name: String, hull: Script, pos: Vector2, role: String, sid: String = "", iff_tags: Array = HOME_IFF, flag: String = Standing.FLAG_DRIFT, economy: Dictionary = {}) -> void:
	def.add_entity({
		"id": id, "sid": sid, "name": name, "hull": hull,
		"kind": ClusterEntity.Kind.STATION, "pos": pos, "role": role,
		"iff_tags": iff_tags, "is_static": true,
		"transponder_flag": flag,
		# M52b -- stations ARE the authority: default warrant_authority to
		# their own flag (design doc's "Stations and patrol/military ships
		# default warrant_authority to their own flag" -- everyone else,
		# including the player, stays empty).
		"warrant_authority": [flag],
		"economy": economy,
	})

static func _beacon(def, id: int, name: String, pos: Vector2) -> void:
	def.add_entity({
		"id": id, "name": name, "hull": Buoy,
		"kind": ClusterEntity.Kind.BEACON, "pos": pos, "comms_range": BEACON_RANGE,
		"iff_tags": HOME_IFF, "is_static": true,
	})

# A patrol hull that loops a diamond of `radius` around `center`. Mobile traffic
# (is_static false) so the bubble dead-reckons it while dormant; the FollowRoute
# leaf is wired from the behavior route on promote.
static func _patrol(def, id: int, name: String, hull: Script, center: Vector2, radius: float) -> void:
	var route := [
		center + Vector2(radius, 0), center + Vector2(0, radius),
		center + Vector2(-radius, 0), center + Vector2(0, -radius),
	]
	def.add_entity({
		"id": id, "name": name, "hull": hull,
		"kind": ClusterEntity.Kind.TRAFFIC, "pos": route[0],
		"iff_tags": HOME_IFF, "is_static": false,
		"behavior": {"route": route, "loop": true},
		"transponder_flag": Standing.FLAG_DRIFT,
		# M49 -- consumed by the not-yet-built DEMAND_SURRENDER rules; fielded
		# now so patrols don't need reshaping later.
		"authority_flags": [Standing.FLAG_DRIFT],
		# M52b -- patrols are the other archetype the design doc calls out by
		# name; same default-to-own-flag rule as stations above.
		"warrant_authority": [Standing.FLAG_DRIFT],
	})

# A cargo hauler shuttling between two stations (a fixed lane, looping). Starts at
# station a. The bubble dead-reckons it while dormant; the CargoRun leaf is wired
# from the behavior route+cargo flag on promote.
#
## M53a -- hull/iff_tags/flag are optional, defaulting to home's own identity
## (CargoShuttle/HOME_IFF/FLAG_DRIFT) so both pre-Pass-2 call sites (positional,
## 4 args) are behaviorally unchanged. A peer lane (the Meridian runs below)
## passes its own hull (OreShuttle) + iff_tags + flag.
static func _cargo(def, id: int, name: String, a: Vector2, b: Vector2, hull: Script = CargoShuttle, iff_tags: Array = HOME_IFF, flag: String = Standing.FLAG_DRIFT) -> void:
	# Start on the approach to a, NOT at a's center -- a is a station and spawning
	# inside its hull would eject the shuttle. The route targets are the station
	# centers; DOCK_REQUEST_RADIUS handles the approach.
	var start: Vector2 = a + (b - a).normalized() * 6000.0
	def.add_entity({
		"id": id, "name": name, "hull": hull,
		"kind": ClusterEntity.Kind.TRAFFIC, "pos": start,
		"iff_tags": iff_tags, "is_static": false,
		"behavior": {"route": [a, b], "loop": true, "cargo": true},
		"transponder_flag": flag,
	})

# A mobile home holding station in a specific location.
static func _home(def, id: int, name: String, pos: Vector2, sid: String = "") -> void:
	def.add_entity({
		"id": id, "sid": sid, "name": name, "hull": MobileHome,
		"kind": ClusterEntity.Kind.STATION, "pos": pos,
		"iff_tags": ["TEAM_CIVILIAN"], "is_static": true,
		"transponder_flag": Standing.FLAG_CIVILIAN,
	})

# ---------------------------------------------------------------------------
# M53c Phase A -- the home cluster's economy (design_ideas/station_economy.md
# "Worked reference case", the reference table oracle test_station_economy_
# reference.gd asserts against). Explicitly authored PER STATION, never
# defaulted from `role` (the plan doc's "role has only hub/outpost, which
# cannot distinguish Refinery Prime from Ironhold" -- eight distinct profiles
# would override a role-default in all eight cases). Rates are lots/hour, the
# same unit the reference table uses; StationEconomy converts using dt_hours.
# ---------------------------------------------------------------------------

# Generic bin auto-sizing from a station's own throughput magnitude (the
# absolute rate of whatever mechanism touches this commodity there). Neither
# the design doc nor the reference table specifies bin sizes -- only RATES --
# so one formula, driven by the rate itself, keeps every station's bin
# consistently proportioned: ~24h of buffer at target, comfortable headroom
# both directions, starting stock AT target (so nothing starts pre-urgent).
# That is generous enough that a modest test window never spuriously STARVES
# or BLOCKS an authored converter/sink/source pair, which is what lets the
# reference-table test read the tick's OUTPUT as the authored rate.
static func _bin(rate_hint: float) -> Dictionary:
	var capacity: float = maxf(50.0, absf(rate_hint) * 24.0)
	var target: float = capacity * 0.5
	return {"stock": target, "capacity": capacity, "target": target, "surplus_line": capacity * 0.85}

# Ironhold -- port of export/import (design doc: "why every authored lane
# terminates there"). ORE is a pure SINK (5.6/hr leaving through the
# wormhole -- an export, not a converter, since nothing is transformed);
# GOODS is a pure SOURCE (1.5/hr landing -- the cluster's only external
# supply). VOLATILES/REFINED sinks are ordinary population upkeep.
static func _economy_ironhold() -> Dictionary:
	return {
		"bins": {
			Commodity.ORE: _bin(5.6), Commodity.VOLATILES: _bin(0.60),
			Commodity.REFINED: _bin(0.50), Commodity.GOODS: _bin(1.50),
		},
		"sinks": {Commodity.ORE: 5.6, Commodity.VOLATILES: 0.60, Commodity.REFINED: 0.50},
		"sources": {Commodity.GOODS: 1.50},
	}

# Drift Market -- eastern depot. No ORE mechanism at all (the reference
# table's "--"), so its ORE bin stays the inert zero default from
# ClusterLoader's ensure_holder -- omitted from "bins" on purpose.
static func _economy_drift_market() -> Dictionary:
	return {
		"bins": {
			Commodity.VOLATILES: _bin(0.50), Commodity.REFINED: _bin(0.50), Commodity.GOODS: _bin(0.30),
		},
		"sinks": {Commodity.VOLATILES: 0.50, Commodity.REFINED: 0.50, Commodity.GOODS: 0.30},
	}

# Refinery Prime -- the cluster's only REFINED source, via a converter (NOT a
# rate): the ORE -3.3/hr the reference table shows is the converter's own
# input consumption, not a separate sink. REFINED nets exactly the
# converter's +2.2/hr output (no additional population sink on REFINED here --
# the refinery's own people draw VOLATILES/GOODS like everyone else, not the
# thing it makes).
static func _economy_refinery_prime() -> Dictionary:
	return {
		"bins": {
			Commodity.ORE: _bin(3.3), Commodity.REFINED: _bin(2.20),
			Commodity.VOLATILES: _bin(0.45), Commodity.GOODS: _bin(0.40),
		},
		"converters": [
			{"in": {Commodity.ORE: 3.3}, "out": {Commodity.REFINED: 2.2}, "rate": 1.0},
		],
		"sinks": {Commodity.VOLATILES: 0.45, Commodity.GOODS: 0.40},
	}

# Slag Bay -- 32-rock field, ORE source DERIVED from the rock count (see
# ORE_RATE_PER_ROCK above), not a second hardcoded number.
static func _economy_slag_bay() -> Dictionary:
	var ore_rate: float = SLAG_BAY_ROCKS * ORE_RATE_PER_ROCK
	return {
		"bins": {
			Commodity.ORE: _bin(ore_rate), Commodity.VOLATILES: _bin(0.40),
			Commodity.REFINED: _bin(0.25), Commodity.GOODS: _bin(0.20),
		},
		"sources": {Commodity.ORE: ore_rate},
		"sinks": {Commodity.VOLATILES: 0.40, Commodity.REFINED: 0.25, Commodity.GOODS: 0.20},
	}

# Coldreach -- 22-rock field, ice-rich: the cluster's ONLY VOLATILES source,
# authored directly (not derived -- it isn't a mining-outpost ORE yield, it's
# a byproduct of an ice field, a different mechanism than Slag Bay/Halvorsen/
# Corvus/Deepcut's dedicated ore mining). Its small ORE trickle (0.6) is
# likewise authored directly for the same reason -- the plan doc's "derive
# ONLY ore extraction from rock counts" targets the four dedicated ore
# outposts below, not Coldreach's incidental byproduct.
static func _economy_coldreach() -> Dictionary:
	return {
		"bins": {
			Commodity.ORE: _bin(0.6), Commodity.VOLATILES: _bin(2.60),
			Commodity.REFINED: _bin(0.25), Commodity.GOODS: _bin(0.20),
		},
		"sources": {Commodity.ORE: 0.6, Commodity.VOLATILES: 2.60},
		"sinks": {Commodity.REFINED: 0.25, Commodity.GOODS: 0.20},
	}

# Deepcut -- 15-rock field, derived ORE source.
static func _economy_deepcut() -> Dictionary:
	var ore_rate: float = DEEPCUT_ROCKS * ORE_RATE_PER_ROCK
	return {
		"bins": {
			Commodity.ORE: _bin(ore_rate), Commodity.VOLATILES: _bin(0.22),
			Commodity.REFINED: _bin(0.25), Commodity.GOODS: _bin(0.15),
		},
		"sources": {Commodity.ORE: ore_rate},
		"sinks": {Commodity.VOLATILES: 0.22, Commodity.REFINED: 0.25, Commodity.GOODS: 0.15},
	}

# Halvorsen Claim (Meridian) -- 18-rock field, derived ORE source.
static func _economy_halvorsen() -> Dictionary:
	var ore_rate: float = HALVORSEN_ROCKS * ORE_RATE_PER_ROCK
	return {
		"bins": {
			Commodity.ORE: _bin(ore_rate), Commodity.VOLATILES: _bin(0.22),
			Commodity.REFINED: _bin(0.25), Commodity.GOODS: _bin(0.15),
		},
		"sources": {Commodity.ORE: ore_rate},
		"sinks": {Commodity.VOLATILES: 0.22, Commodity.REFINED: 0.25, Commodity.GOODS: 0.15},
	}

# Corvus Yards (Meridian) -- 18-rock field, derived ORE source.
static func _economy_corvus() -> Dictionary:
	var ore_rate: float = CORVUS_ROCKS * ORE_RATE_PER_ROCK
	return {
		"bins": {
			Commodity.ORE: _bin(ore_rate), Commodity.VOLATILES: _bin(0.21),
			Commodity.REFINED: _bin(0.20), Commodity.GOODS: _bin(0.10),
		},
		"sources": {Commodity.ORE: ore_rate},
		"sinks": {Commodity.VOLATILES: 0.21, Commodity.REFINED: 0.20, Commodity.GOODS: 0.10},
	}

