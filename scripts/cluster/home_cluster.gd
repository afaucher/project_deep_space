extends RefCounted
class_name HomeCluster

# M15/M16 -- the authored home cluster: The Sovereign Drift. Three medium-station
# hubs spread across the cluster, three small-station mining outposts each sitting
# on an asteroid field, a seven-beacon road linking the two main hubs, and the
# Nexus wormhole out in dark space away from the road. All coordinates sit well
# inside the +/-500k float32 budget. See implementation_plans/m16_static_landmarks_design.md.

const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const MobileHome = preload("res://scripts/ships/mobile_home.gd")

# Home faction shares the player's tag so hubs read friendly and their station AI
# never targets the player. Faction modelling proper is a later concern.
const HOME_IFF := ["TEAM_PLAYER"]
const BEACON_RANGE := 50000.0   # matches Buoy's comms range

static func build() -> ClusterDef:
	var def = ClusterDef.new()
	def.name = "The Sovereign Drift (Home)"
	def.bounds = Rect2(-250000, -250000, 500000, 500000)
	def.player_start = Vector2(3000, 0)

	# --- Hubs (medium stations) ---
	# M42 -- sid is the story overlay's join key (story/home_cluster_overlay.gd,
	# story/characters.gd); only entities story content actually references
	# need one -- Ironhold (Aunt Stephanie) now, the five homes for M43's Todd
	# + residents.
	_station(def, 1, "Ironhold", MediumStation, Vector2(0, 0), "hub", "ironhold")
	_station(def, 2, "Drift Market", MediumStation, Vector2(200000, 40000), "hub", "drift_market")
	_station(def, 3, "Refinery Prime", MediumStation, Vector2(40000, -150000), "hub", "refinery_prime")

	# --- Mining outposts (small stations), each parked on a field ---
	_station(def, 10, "Slag Bay", SmallStation, Vector2(150000, 110000), "outpost")
	_station(def, 11, "Coldreach", SmallStation, Vector2(-70000, 90000), "outpost")
	_station(def, 12, "Deepcut", SmallStation, Vector2(90000, -170000), "outpost")

	# --- Asteroid fields on the outposts (loader expands into individual rocks) ---
	# Slag Bay's field is the M43 search field -- expanded (10k -> 16k, rocks
	# scaled to keep density) so all five Drift homes fit inside it with real
	# flying distance between them (the check_on_todd search is elimination
	# across the whole field, see the roadmap's M43 section).
	def.add_field({"center": Vector2(150000, 110000), "radius": 16000.0, "count": 32, "seed": 1})
	def.add_field({"center": Vector2(-70000, 90000), "radius": 12000.0, "count": 22, "seed": 2})
	def.add_field({"center": Vector2(90000, -170000), "radius": 9000.0, "count": 15, "seed": 3})

	# --- Mobile Homes (civilian habitats), all parked in the Slag Bay field ---
	# M43 -- one community, one search area ("ask the neighbors; those folks
	# see everything"): the residents are Todd's neighbors, so they live where
	# the mission looks. Spread across the expanded field so eliminating the
	# unnamed contacts takes real flying; Claim 42 (Todd) sits out on the far
	# spinward edge, furthest from the field's mouth (and where Wex's rambling
	# actually points, for a player who listens).
	_home(def, 200, "Hermit's Rest", Vector2(145000, 115000), "hermits_rest")
	_home(def, 201, "Claim 42", Vector2(159000, 99000), "claim_42")
	_home(def, 202, "The Deep Freeze", Vector2(140000, 103000), "deep_freeze")
	_home(def, 203, "Lucky Strike", Vector2(154000, 121000), "lucky_strike")
	_home(def, 204, "Rock Bottom", Vector2(162000, 114000), "rock_bottom")

	# --- Beacon road: Ironhold (0,0) -> Drift Market (200000,40000) ---
	# Seven interior beacons at ~25k spacing (well inside the 50k comms range, so
	# their lit zones overlap the whole way). Chained into one routing path.
	var a := Vector2(0, 0)
	var b := Vector2(200000, 40000)
	var beacon_count := 7
	for i in range(beacon_count):
		var f: float = float(i + 1) / float(beacon_count + 1)   # interior fractions
		_beacon(def, 100 + i, "Beacon " + str(i + 1), a.lerp(b, f))
	var edges: Array = []
	for i in range(beacon_count - 1):
		edges.append([100 + i, 100 + i + 1])
	def.beacon_edges = edges

	# --- Nexus wormhole, out in dark space (no beacons out here) ---
	def.add_entity({
		"id": 500, "name": "Nexus Wormhole", "hull": Wormhole,
		"kind": ClusterEntity.Kind.WORMHOLE, "pos": Vector2(-130000, -110000),
		"iff_tags": [], "is_static": true,
	})

	# --- Light-attack-craft patrols (loop a diamond around a hub) ---
	_patrol(def, 600, "Patrol Alpha", LightAttackCraft, Vector2(0, 0), 12000.0)         # Ironhold
	_patrol(def, 601, "Patrol Bravo", LightAttackCraft, Vector2(200000, 40000), 12000.0) # Drift Market

	# --- Cargo shuttles on fixed lanes (not a full mesh), starting at Ironhold ---
	_cargo(def, 700, "Mule", Vector2(0, 0), Vector2(200000, 40000))    # hub <-> hub, down the road
	_cargo(def, 701, "Ore Barge", Vector2(0, 0), Vector2(-70000, 90000)) # hub <-> Coldreach outpost

	return def

static func _station(def, id: int, name: String, hull: Script, pos: Vector2, role: String, sid: String = "") -> void:
	def.add_entity({
		"id": id, "sid": sid, "name": name, "hull": hull,
		"kind": ClusterEntity.Kind.STATION, "pos": pos, "role": role,
		"iff_tags": HOME_IFF, "is_static": true,
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
	})

# A cargo hauler shuttling between two stations (a fixed lane, looping). Starts at
# station a. The bubble dead-reckons it while dormant; the CargoRun leaf is wired
# from the behavior route+cargo flag on promote.
static func _cargo(def, id: int, name: String, a: Vector2, b: Vector2) -> void:
	# Start on the approach to a, NOT at a's center -- a is a station and spawning
	# inside its hull would eject the shuttle. The route targets are the station
	# centers; DOCK_REQUEST_RADIUS handles the approach.
	var start: Vector2 = a + (b - a).normalized() * 6000.0
	def.add_entity({
		"id": id, "name": name, "hull": CargoShuttle,
		"kind": ClusterEntity.Kind.TRAFFIC, "pos": start,
		"iff_tags": HOME_IFF, "is_static": false,
		"behavior": {"route": [a, b], "loop": true, "cargo": true},
	})

# A mobile home holding station in a specific location.
static func _home(def, id: int, name: String, pos: Vector2, sid: String = "") -> void:
	def.add_entity({
		"id": id, "sid": sid, "name": name, "hull": MobileHome,
		"kind": ClusterEntity.Kind.STATION, "pos": pos,
		"iff_tags": ["TEAM_CIVILIAN"], "is_static": true,
	})

