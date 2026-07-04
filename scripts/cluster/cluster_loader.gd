extends RefCounted
class_name ClusterLoader

# M15 -- turn a ClusterDef's authored entity dicts into ClusterEntity records and
# hand them to a ClusterManager. No physics happens here: the manager's liveness
# policy decides what actually goes live around the player. Referenced via
# preload const per the headless class-cache caveat.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const _Asteroid = preload("res://scripts/asteroid.gd")

# Field-asteroid ids live in a high range so they never collide with authored
# entity ids: base = FIELD_ID_BASE + field_index*FIELD_ID_STRIDE + i.
const FIELD_ID_BASE := 1000000
const FIELD_ID_STRIDE := 10000

static func load_into(def, manager) -> void:
	for e in def.entities:
		var rec = ClusterEntity.new()
		rec.id = e["id"]
		rec.name = e.get("name", "")
		rec.hull_script = e["hull"]
		rec.kind = e.get("kind", ClusterEntity.Kind.TRAFFIC)
		rec.pos = e["pos"]
		var tags: Array = e.get("iff_tags", [])
		rec.iff_tags = tags.duplicate(true)
		rec.is_static = e.get("is_static", false)
		rec.behavior = e.get("behavior", null)
		manager.add_record(rec)

	# Expand asteroid fields into individual records. Seeded RNG -> deterministic
	# layout (testable). Uniform-in-disk: r = R*sqrt(u) so rocks don't clump at
	# the center. The bubble LODs them: a field only goes live when the player is
	# inside it.
	for fi in range(def.asteroid_fields.size()):
		var f = def.asteroid_fields[fi]
		var rng = RandomNumberGenerator.new()
		rng.seed = int(f.get("seed", fi + 1))
		var center: Vector2 = f["center"]
		var radius: float = f["radius"]
		var count: int = f["count"]
		var base_id: int = FIELD_ID_BASE + fi * FIELD_ID_STRIDE
		for i in range(count):
			var rr: float = radius * sqrt(rng.randf())
			var aa: float = rng.randf() * TAU
			var rec = ClusterEntity.new()
			rec.id = base_id + i
			rec.hull_script = _Asteroid
			rec.kind = ClusterEntity.Kind.ASTEROID
			rec.pos = center + Vector2(cos(aa), sin(aa)) * rr
			rec.is_static = true
			manager.add_record(rec)
