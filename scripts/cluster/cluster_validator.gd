extends RefCounted
class_name ClusterValidator

# M15 -- well-formedness check for an authored ClusterDef, in the mold of
# ship_design_validator.gd. Returns { ok, violations }; `ok` is false iff any
# error-severity violation exists (warnings are advisory, don't block), matching
# ShipDesignValidator's convention so test_cluster_loader can assert zero errors
# over the home cluster exactly as test_ship_designs does over the catalog.
#
# M16 will extend this with asteroid-field and road-lit-coverage checks.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

const STATION_MIN_SEPARATION := 3000.0  # min center distance between structures

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
	var beacon_ids := {}
	for e in def.entities:
		if e.get("kind") == ClusterEntity.Kind.BEACON:
			beacon_ids[e["id"]] = true
	for edge in def.beacon_edges:
		if not beacon_ids.has(edge[0]) or not beacon_ids.has(edge[1]):
			violations.append(_v(edge[0], "beacon_edge",
				"edge references a non-beacon or missing id: " + str(edge), "error"))

	# 5. Beacon graph connectivity (advisory -- a cluster may hold separate road
	#    segments, but a single home road should be one connected component).
	if beacon_ids.size() > 1 and not _beacons_connected(beacon_ids, def.beacon_edges):
		violations.append(_v(-1, "beacon_graph", "beacon graph is not fully connected", "warning"))

	var errors: Array = violations.filter(func(v): return v["severity"] == "error")
	return {"ok": errors.is_empty(), "violations": violations}

static func _v(entity_id, field: String, reason: String, severity: String) -> Dictionary:
	return {"entity_id": entity_id, "field": field, "reason": reason, "severity": severity}

static func _beacons_connected(beacon_ids: Dictionary, edges: Array) -> bool:
	# BFS from an arbitrary beacon; every beacon must be reachable.
	var adj := {}
	for bid in beacon_ids:
		adj[bid] = []
	for edge in edges:
		if adj.has(edge[0]) and adj.has(edge[1]):
			adj[edge[0]].append(edge[1])
			adj[edge[1]].append(edge[0])
	var start = beacon_ids.keys()[0]
	var visited := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur = queue.pop_back()
		for nb in adj[cur]:
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited.size() == beacon_ids.size()
