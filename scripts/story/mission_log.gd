extends Node
class_name MissionLog

# M39 -- Mission log: missions with ordered objectives, attached to a ship
# node exactly like CommsLedger (see ship.gd's _ready(),
# `comms_ledger = CommsLedger.new(); add_child(comms_ledger)` -- mission_log
# mirrors that). See implementation_plans/m39_m44_homefront_roadmap.md,
# "M39 -- Story state & mission log" and "Story data architecture".
#
# Missions are PLAIN Dictionaries (save-system readiness, challenge #4 in the
# roadmap): {id, title, giver, objectives: Array, state, indicators_visible}.
# Objectives are PLAIN Dictionaries: {id, kind, text, target, state}. Vector2
# inside `target` is fine (plain-serializable); no Object/Node references
# ever land in a mission dict.
#
# Objectives complete IN ORDER -- the first non-COMPLETE objective in a
# mission's objectives array is "the active one" for that mission. Kinds:
#   GO_TO_AREA  target = {center: Vector2, radius: float}
#   TALK_TO     target = {npc: String}
#   DELIVER     target = {item: String, npc: String}
#
# GO_TO_AREA proximity is checked in THIS node's own _physics_process, never
# added to ship.gd's already-hot per-frame path (roadmap explicitly calls
# this out). Checked on an accumulated ~0.5s tick, not every frame.

# M42 -- preloaded so start_mission_by_id() can look up catalog definitions by
# id (dialogue mutations pass a plain String, never an inline Dictionary
# literal -- see mission_catalog.gd's header). Preload const, not bare
# class_name, per the headless class-cache caveat (CLAUDE.md).
const MissionCatalog = preload("res://scripts/story/mission_catalog.gd")

signal mission_started(id: String)
signal objective_completed(mission_id: String, objective_id: String)
signal mission_completed(id: String)

const OBJ_STATE_ACTIVE := "ACTIVE"
const OBJ_STATE_COMPLETE := "COMPLETE"
const MISSION_STATE_ACTIVE := "ACTIVE"
const MISSION_STATE_COMPLETE := "COMPLETE"

const GO_TO_AREA_CHECK_INTERVAL := 0.5

var missions: Dictionary = {}   # id -> mission dict

var _proximity_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_proximity_accum += delta
	if _proximity_accum < GO_TO_AREA_CHECK_INTERVAL:
		return
	_proximity_accum = 0.0
	_check_go_to_area_objectives()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_mission(def: Dictionary) -> bool:
	var id: String = def.get("id", "")
	if id == "" or missions.has(id):
		return false

	var objectives: Array = []
	for obj_def in def.get("objectives", []):
		objectives.append({
			"id": obj_def.get("id", ""),
			"kind": obj_def.get("kind", ""),
			"text": obj_def.get("text", ""),
			"target": obj_def.get("target", {}),
			"state": OBJ_STATE_ACTIVE,
		})

	var mission: Dictionary = {
		"id": id,
		"title": def.get("title", ""),
		"giver": def.get("giver", ""),
		"objectives": objectives,
		"state": MISSION_STATE_ACTIVE,
		"indicators_visible": def.get("indicators_visible", true),
	}
	missions[id] = mission
	mission_started.emit(id)
	return true

# M42 -- catalog lookup + start, so .dialogue mutations write
# `do missions.start_mission_by_id("check_on_todd")` with no dictionary
# literals. Returns false (no-op) for an unknown id, same failure mode as
# start_mission() with a bad/empty def.
func start_mission_by_id(id: String) -> bool:
	var def: Dictionary = MissionCatalog.get_mission(id)
	if def.is_empty():
		return false
	return start_mission(def)

func active_missions() -> Array:
	var out: Array = []
	for m in missions.values():
		if m.get("state", "") == MISSION_STATE_ACTIVE:
			out.append(m)
	return out

func get_mission(id: String):
	return missions.get(id, null)

# Returns the first non-COMPLETE objective dict for a mission, or an empty
# Dictionary if the mission doesn't exist, has no objectives, or all
# objectives are complete. (Returns {} rather than null so callers can use
# the Dictionary subscript/`.get()` API uniformly without a type-inference
# trap -- see the GDScript traps note in CLAUDE.md re: untyped Variant vars.)
func get_active_objective(mission_id: String) -> Dictionary:
	var mission = missions.get(mission_id, null)
	if mission == null:
		return {}
	for obj in mission["objectives"]:
		if obj.get("state", "") != OBJ_STATE_COMPLETE:
			return obj
	return {}

func complete_objective(mission_id: String, objective_id: String) -> bool:
	var mission = missions.get(mission_id, null)
	if mission == null or mission.get("state", "") != MISSION_STATE_ACTIVE:
		return false

	# Only the current active (first non-COMPLETE) objective may be completed
	# -- objectives complete in order.
	var active_obj: Dictionary = get_active_objective(mission_id)
	if active_obj.is_empty() or active_obj.get("id", "") != objective_id:
		return false

	active_obj["state"] = OBJ_STATE_COMPLETE
	objective_completed.emit(mission_id, objective_id)

	if get_active_objective(mission_id).is_empty():
		mission["state"] = MISSION_STATE_COMPLETE
		mission_completed.emit(mission_id)

	return true

# Completes a matching active TALK_TO objective (any active mission whose
# current objective is TALK_TO this npc). Returns true if one was completed.
func notify_talked_to(npc_name: String) -> bool:
	var completed_any := false
	for mission_id in missions.keys():
		var mission = missions[mission_id]
		if mission.get("state", "") != MISSION_STATE_ACTIVE:
			continue
		var obj: Dictionary = get_active_objective(mission_id)
		if obj.is_empty():
			continue
		if obj.get("kind", "") != "TALK_TO":
			continue
		var target: Dictionary = obj.get("target", {})
		if target.get("npc", "") == npc_name:
			if complete_objective(mission_id, obj.get("id", "")):
				completed_any = true
	return completed_any

# Completes a matching active DELIVER objective ONLY if StoryState carries the
# required item; consumes the item on success. Returns true iff a delivery
# actually happened.
func notify_delivered(npc_name: String) -> bool:
	var completed_any := false
	for mission_id in missions.keys():
		var mission = missions[mission_id]
		if mission.get("state", "") != MISSION_STATE_ACTIVE:
			continue
		var obj: Dictionary = get_active_objective(mission_id)
		if obj.is_empty():
			continue
		if obj.get("kind", "") != "DELIVER":
			continue
		var target: Dictionary = obj.get("target", {})
		if target.get("npc", "") != npc_name:
			continue
		var item_id: String = target.get("item", "")
		if not StoryState.has_item(item_id):
			continue
		StoryState.remove_item(item_id)
		if complete_objective(mission_id, obj.get("id", "")):
			completed_any = true
	return completed_any

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _check_go_to_area_objectives() -> void:
	var ship = get_parent()
	if ship == null or not is_instance_valid(ship):
		return
	if not ("position" in ship):
		return
	var ship_pos: Vector2 = ship.position

	for mission_id in missions.keys():
		var mission = missions[mission_id]
		if mission.get("state", "") != MISSION_STATE_ACTIVE:
			continue
		var obj: Dictionary = get_active_objective(mission_id)
		if obj.is_empty():
			continue
		if obj.get("kind", "") != "GO_TO_AREA":
			continue
		var target: Dictionary = obj.get("target", {})
		var center: Vector2 = target.get("center", Vector2.ZERO)
		var radius: float = target.get("radius", 0.0)
		if ship_pos.distance_to(center) <= radius:
			complete_objective(mission_id, obj.get("id", ""))
