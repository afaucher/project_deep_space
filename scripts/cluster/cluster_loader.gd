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

# M42 -- `overlay`/`characters` are optional story-data hooks (default null,
# so every pre-M42 call site -- test_cluster_loader, test_campaign_bootstrap --
# keeps working unchanged). When supplied they must expose the same static
# interface as scripts/story/home_cluster_overlay.gd (`get_entry(sid) ->
# Dictionary`) and scripts/story/characters.gd (`get_character(id) ->
# Dictionary`); main.gd's _bootstrap_campaign supplies the real home overlay +
# registry, tests may supply synthetic stand-ins with the same two static
# methods. ClusterLoader stays story-AGNOSTIC in mechanism: it merges
# whatever overlay dict it's handed onto the record's plain generic fields
# (cast/port_patch/component_overrides) and never interprets their content --
# see cluster_manager.gd's _promote(), which applies them without knowing who
# Stephanie is.
static func load_into(def, manager, overlay = null, characters = null) -> void:
	for e in def.entities:
		var rec = ClusterEntity.new()
		rec.id = e["id"]
		rec.name = e.get("name", "")
		rec.sid = e.get("sid", "")
		rec.hull_script = e["hull"]
		rec.kind = e.get("kind", ClusterEntity.Kind.TRAFFIC)
		rec.pos = e["pos"]
		var tags: Array = e.get("iff_tags", [])
		rec.iff_tags = tags.duplicate(true)
		rec.is_static = e.get("is_static", false)
		rec.behavior = e.get("behavior", null)
		# M48 -- optional declared-allegiance fields (see cluster_entity.gd);
		# absent for entities that carry no flag (asteroids, the wormhole,
		# beacons).
		rec.transponder_flag = e.get("transponder_flag", "")
		var auth_flags: Array = e.get("authority_flags", [])
		rec.authority_flags = auth_flags.duplicate(true)
		var warr_authority: Array = e.get("warrant_authority", [])
		rec.warrant_authority = warr_authority.duplicate(true)
		_merge_overlay(rec, overlay, characters)
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

# M42 -- folds one overlay entry (keyed by rec.sid) onto the record's plain
# generic fields. No-ops when overlay is null or the record has no sid or the
# overlay has no entry for it -- the vast majority of entities (asteroids,
# patrols, beacons, unreferenced stations) take this fast path untouched.
# Cast resolution happens HERE (load time), not at promote: characters.gd's
# {name, role, dialogue} becomes a plain {name, role, dialogue_path}
# descriptor on the record, so ClusterManager (story-blind by design) only
# ever touches plain data it already knows how to build an NPCProfile from.
# faction is deliberately NOT resolved here -- it depends on the node's
# port_zone authority, which _rebrand_port_zone() only knows at promote time.
static func _merge_overlay(rec, overlay, characters) -> void:
	if overlay == null or rec.sid == "":
		return
	var entry: Dictionary = overlay.get_entry(rec.sid)
	if entry.is_empty():
		return

	var cast_ids: Array = entry.get("cast", [])
	if characters != null:
		for cid in cast_ids:
			var cdata: Dictionary = characters.get_character(cid)
			if cdata.is_empty():
				continue
			rec.cast.append({
				"name": cdata.get("name", cid),
				"role": cdata.get("role", ""),
				"dialogue_path": cdata.get("dialogue", ""),
			})

	rec.port_patch = entry.get("port", {}).duplicate(true)
	rec.component_overrides = entry.get("component_overrides", {}).duplicate(true)
