extends RefCounted
class_name ClusterValidator

# M15/M16 -- well-formedness check for an authored ClusterDef, in the mold of
# ship_design_validator.gd. Returns { ok, violations }; `ok` is false iff any
# error-severity violation exists (warnings are advisory, don't block), matching
# ShipDesignValidator's convention so test_static_landmarks can assert zero
# errors over the home cluster exactly as test_ship_designs does over the catalog.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

const STATION_MIN_SEPARATION := 3000.0   # min center distance between structures
const BEACON_DEFAULT_RANGE := 50000.0    # comms range assumed when a beacon omits it
const OUTPOST_FIELD_MARGIN := 3000.0     # slack when checking an outpost sits on a field

static func validate(def) -> Dictionary:
	var violations: Array = []

	# 1. Unique ids.
	var seen := {}
	for e in def.entities:
		var eid = e["id"]
		if seen.has(eid):
			violations.append(_v(eid, "id", "duplicate entity id", "error"))
		seen[eid] = true

	# 2. In bounds.
	for e in def.entities:
		if not def.bounds.has_point(e["pos"]):
			violations.append(_v(e["id"], "pos", "entity outside cluster bounds " + str(def.bounds), "error"))

	# 3. Structures must not sit on top of each other.
	var stations: Array = def.entities.filter(func(x): return x.get("kind") == ClusterEntity.Kind.STATION)
	for i in range(stations.size()):
		for j in range(i + 1, stations.size()):
			var d: float = stations[i]["pos"].distance_to(stations[j]["pos"])
			if d < STATION_MIN_SEPARATION:
				violations.append(_v(stations[i]["id"], "overlap",
					"station too close to " + str(stations[j]["id"]) + " (" + str(int(d)) + "u)", "error"))

	# 4. Beacon edges must reference real beacons.
	var beacon_pos := {}
	var beacon_range := {}
	for e in def.entities:
		if e.get("kind") == ClusterEntity.Kind.BEACON:
			beacon_pos[e["id"]] = e["pos"]
			beacon_range[e["id"]] = e.get("comms_range", BEACON_DEFAULT_RANGE)
	for edge in def.beacon_edges:
		if not beacon_pos.has(edge[0]) or not beacon_pos.has(edge[1]):
			violations.append(_v(edge[0], "beacon_edge",
				"edge references a non-beacon or missing id: " + str(edge), "error"))

	# 5. Beacon graph connectivity (advisory -- a single home road should be one
	#    connected component).
	if beacon_pos.size() > 1 and not _beacons_connected(beacon_pos, def.beacon_edges):
		violations.append(_v(-1, "beacon_graph", "beacon graph is not fully connected", "warning"))

	# 6. Road lit (advisory): adjacent beacons on an edge must be within comms
	#    range so their lit zones overlap -- no dark gap mid-road. Validates the
	#    spacing decision.
	for edge in def.beacon_edges:
		if beacon_pos.has(edge[0]) and beacon_pos.has(edge[1]):
			var gap: float = beacon_pos[edge[0]].distance_to(beacon_pos[edge[1]])
			var reach: float = min(beacon_range[edge[0]], beacon_range[edge[1]])
			if gap > reach:
				violations.append(_v(edge[0], "road_lit",
					"beacon gap %du exceeds lit range %du -- dark spot mid-road" % [int(gap), int(reach)], "warning"))

	# 7. Asteroid fields: non-empty and fully inside bounds.
	for fi in range(def.asteroid_fields.size()):
		var f = def.asteroid_fields[fi]
		if int(f.get("count", 0)) <= 0:
			violations.append(_v(-1, "field", "asteroid field %d has no asteroids" % fi, "error"))
		var c: Vector2 = f["center"]
		var r: float = f["radius"]
		var field_rect := Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		if not def.bounds.encloses(field_rect):
			violations.append(_v(-1, "field", "asteroid field %d extends outside cluster bounds" % fi, "error"))

	# 8. Mining outposts should sit on an asteroid field (advisory).
	var outposts: Array = def.entities.filter(func(x): return x.get("kind") == ClusterEntity.Kind.STATION and x.get("role", "") == "outpost")
	for op in outposts:
		var on_field := false
		for f in def.asteroid_fields:
			if op["pos"].distance_to(f["center"]) <= float(f["radius"]) + OUTPOST_FIELD_MARGIN:
				on_field = true
				break
		if not on_field:
			violations.append(_v(op["id"], "outpost_field", "mining outpost sits on no asteroid field", "warning"))

	var errors: Array = violations.filter(func(v): return v["severity"] == "error")
	return {"ok": errors.is_empty(), "violations": violations}

static func _v(entity_id, field: String, reason: String, severity: String) -> Dictionary:
	return {"entity_id": entity_id, "field": field, "reason": reason, "severity": severity}

static func _beacons_connected(beacon_pos: Dictionary, edges: Array) -> bool:
	# BFS from an arbitrary beacon; every beacon must be reachable.
	var adj := {}
	for bid in beacon_pos:
		adj[bid] = []
	for edge in edges:
		if adj.has(edge[0]) and adj.has(edge[1]):
			adj[edge[0]].append(edge[1])
			adj[edge[1]].append(edge[0])
	var start = beacon_pos.keys()[0]
	var visited := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur = queue.pop_back()
		for nb in adj[cur]:
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited.size() == beacon_pos.size()
