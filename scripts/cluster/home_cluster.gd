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
	_station(def, 1, "Ironhold", MediumStation, Vector2(0, 0), "hub")
	_station(def, 2, "Drift Market", MediumStation, Vector2(200000, 40000), "hub")
	_station(def, 3, "Refinery Prime", MediumStation, Vector2(40000, -150000), "hub")

	# --- Mining outposts (small stations), each parked on a field ---
	_station(def, 10, "Slag Bay", SmallStation, Vector2(150000, 110000), "outpost")
	_station(def, 11, "Coldreach", SmallStation, Vector2(-70000, 90000), "outpost")
	_station(def, 12, "Deepcut", SmallStation, Vector2(90000, -170000), "outpost")

	# --- Asteroid fields on the outposts (loader expands into individual rocks) ---
	def.add_field({"center": Vector2(150000, 110000), "radius": 10000.0, "count": 18, "seed": 1})
	def.add_field({"center": Vector2(-70000, 90000), "radius": 12000.0, "count": 22, "seed": 2})
	def.add_field({"center": Vector2(90000, -170000), "radius": 9000.0, "count": 15, "seed": 3})

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

	return def

static func _station(def, id: int, name: String, hull: Script, pos: Vector2, role: String) -> void:
	def.add_entity({
		"id": id, "name": name, "hull": hull,
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
