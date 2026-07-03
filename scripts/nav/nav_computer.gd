extends RefCounted
class_name NavComputer

# M17 -- the routing brain. Turns a named destination into a beacon-graph route
# over a ClusterDef. On the road: BFS the beacon chain from the beacon nearest the
# start to the one nearest the destination. In the dark (no beacons, a disconnected
# graph from a sabotaged edge, or a short hop): a direct [dest]. See
# implementation_plans/m17_nav_routing_design.md. Referenced via preload const.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

# Named nav targets the player can pick: stations, beacons, the wormhole.
static func destinations(def) -> Array:
	var out: Array = []
	for e in def.entities:
		var k = e.get("kind")
		if k == ClusterEntity.Kind.STATION or k == ClusterEntity.Kind.BEACON or k == ClusterEntity.Kind.WORMHOLE:
			out.append({"name": e.get("name", "?"), "pos": e["pos"], "kind": k})
	return out

# Ordered world-space waypoints from `start` to `dest`, routed over the lit beacon
# graph where possible, direct where not.
static func route(def, start: Vector2, dest: Vector2) -> Array:
	var beacons: Array = []
	for e in def.entities:
		if e.get("kind") == ClusterEntity.Kind.BEACON:
			beacons.append({"id": e["id"], "pos": e["pos"]})
	if beacons.is_empty():
		return [dest]

	var entry = _nearest(beacons, start)
	var exit = _nearest(beacons, dest)

	# Short hop: the destination is nearer than the road entrance -> go direct.
	if start.distance_to(dest) <= start.distance_to(entry["pos"]):
		return [dest]

	var path_ids: Array = _bfs(entry["id"], exit["id"], def.beacon_edges)
	if path_ids.is_empty():
		return [dest]   # disconnected graph (e.g. sabotaged beacon) -> direct/dark

	var by_id := {}
	for b in beacons:
		by_id[b["id"]] = b["pos"]
	var result: Array = []
	for bid in path_ids:
		result.append(by_id[bid])
	# Final leg to the destination, unless it coincides with the exit beacon.
	if result.is_empty() or result[result.size() - 1].distance_to(dest) > 1.0:
		result.append(dest)
	return result

static func _nearest(beacons: Array, p: Vector2):
	var best = null
	var best_d: float = INF
	for b in beacons:
		var d: float = b["pos"].distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best

# Beacon-id path from from_id to to_id inclusive, or [] if unreachable.
static func _bfs(from_id, to_id, edges: Array) -> Array:
	if from_id == to_id:
		return [from_id]
	var adj := {}
	for edge in edges:
		if not adj.has(edge[0]): adj[edge[0]] = []
		if not adj.has(edge[1]): adj[edge[1]] = []
		adj[edge[0]].append(edge[1])
		adj[edge[1]].append(edge[0])
	if not adj.has(from_id) or not adj.has(to_id):
		return []
	var prev := {from_id: from_id}
	var queue: Array = [from_id]
	while not queue.is_empty():
		var cur = queue.pop_front()
		if cur == to_id:
			break
		for nb in adj[cur]:
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to_id):
		return []
	var path: Array = []
	var node = to_id
	while node != from_id:
		path.push_front(node)
		node = prev[node]
	path.push_front(from_id)
	return path
