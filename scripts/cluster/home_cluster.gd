extends RefCounted
class_name HomeCluster

# M15 -- the authored home cluster: The Sovereign Drift. Three medium-station
# hubs spread across tens of thousands of units, three small-station mining
# outposts, a four-beacon road linking two hubs, and a scatter of sample
# asteroids by an outpost. The wormhole and real (procedural) asteroid fields
# arrive in M16; this is the navigable skeleton. All coordinates sit well inside
# the +/-500k float32 budget. See implementation_plans/m15_cluster_loader_design.md.

const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

# Home faction shares the player's tag so hubs read friendly and their station AI
# never targets the player. Faction modelling proper is a later concern.
const HOME_IFF := ["TEAM_PLAYER"]

static func build() -> ClusterDef:
	var def = ClusterDef.new()
	def.name = "The Sovereign Drift (Home)"
	def.bounds = Rect2(-250000, -250000, 500000, 500000)
	def.player_start = Vector2(3000, 0)

	# --- Hubs (medium stations) ---
	_station(def, 1, "Ironhold", MediumStation, Vector2(0, 0))
	_station(def, 2, "Drift Market", MediumStation, Vector2(120000, 40000))
	_station(def, 3, "Refinery Prime", MediumStation, Vector2(60000, -110000))

	# --- Mining outposts (small stations) ---
	_station(def, 10, "Slag Bay", SmallStation, Vector2(150000, 95000))
	_station(def, 11, "Coldreach", SmallStation, Vector2(-40000, 70000))
	_station(def, 12, "Deepcut", SmallStation, Vector2(95000, -165000))

	# --- Beacon road: Ironhold (0,0) -> Drift Market (120000,40000) ---
	var a := Vector2(0, 0)
	var b := Vector2(120000, 40000)
	for i in range(4):
		var f: float = 0.2 + 0.2 * i        # f = 0.2, 0.4, 0.6, 0.8
		_beacon(def, 100 + i, "Beacon " + str(i + 1), a.lerp(b, f))
	def.beacon_edges = [[100, 101], [101, 102], [102, 103]]

	# --- Sample asteroids near Coldreach (M16 replaces these with a field) ---
	var field_center := Vector2(-40000, 70000)
	var offsets := [
		Vector2(2000, 1500), Vector2(-3000, 2500), Vector2(1000, -2000),
		Vector2(3500, 500), Vector2(-2500, -3000), Vector2(500, 3200),
	]
	for i in range(offsets.size()):
		_asteroid(def, 200 + i, field_center + offsets[i])

	return def

static func _station(def, id: int, name: String, hull: Script, pos: Vector2) -> void:
	def.add_entity({
		"id": id, "name": name, "hull": hull,
		"kind": ClusterEntity.Kind.STATION, "pos": pos,
		"iff_tags": HOME_IFF, "is_static": true,
	})

static func _beacon(def, id: int, name: String, pos: Vector2) -> void:
	def.add_entity({
		"id": id, "name": name, "hull": Buoy,
		"kind": ClusterEntity.Kind.BEACON, "pos": pos,
		"iff_tags": HOME_IFF, "is_static": true,
	})

static func _asteroid(def, id: int, pos: Vector2) -> void:
	def.add_entity({
		"id": id, "name": "Asteroid", "hull": Asteroid,
		"kind": ClusterEntity.Kind.ASTEROID, "pos": pos,
		"iff_tags": [], "is_static": true,
	})
