class_name Variants

# M24 -- delta variants: apply a small list of ops to a base ship's authored
# component array to produce a variant array, without hand-copying the whole
# base. See design_ideas/hull_shape_grammar.md §5/§7 and
# implementation_plans/m24_delta_variants_design.md.
#
# Variants.apply(base, ops) never mutates `base` -- it deep-copies first, then
# applies ops to the copy, and returns that. Callers (variant ship _init()s)
# pass a preloaded base ship's design() array; the base's own array is never
# touched.
#
# Ops v1 (each a Dictionary):
#   {"swap": id, "part": [family, tier, mark]} -- replace the named component
#     with a catalog part (Parts.make) built at the SAME rect position. The
#     new part's size MUST equal the old component's rect size EXACTLY -- a
#     size mismatch is a hard error: apply() push_errors and returns [] (an
#     empty array), the chosen "hard error" contract (see file-level test in
#     test_ship_variants.gd item 2). This is the geometry-safety contract that
#     keeps swap/tune classified STATS_ONLY trustworthy -- a swap can change
#     stats but never the silhouette.
#   {"tune": id, "field": f, "value": v} -- overwrite a single field on the
#     named component. No other field changes.
#   {"remove": id} -- drop the named component entirely.
#
# classify(ops) -> STATS_ONLY if every op is swap/tune; GEOMETRY if any op is
# remove (removal changes the silhouette/connectivity, so the result needs a
# full validator re-run, same as any hand-authored ship).

const Parts = preload("res://scripts/components/parts_catalog.gd")

enum DeltaClass { STATS_ONLY, GEOMETRY }

# Returns a NEW Array (deep copy of `base` with ops applied); never mutates
# `base`. On a size-mismatched swap, push_errors and returns [] (empty array)
# -- callers must treat an empty return as "apply failed", same convention as
# Parts.make's error contract.
static func apply(base: Array, ops: Array) -> Array:
	var result: Array = base.duplicate(true)

	for op in ops:
		if op.has("swap"):
			if not _apply_swap(result, op):
				push_error("Variants.apply: swap failed for op %s -- hard error, returning empty array" % str(op))
				return []
		elif op.has("tune"):
			_apply_tune(result, op)
		elif op.has("remove"):
			_apply_remove(result, op)
		else:
			push_error("Variants.apply: unrecognized op (must have one of swap/tune/remove keys): %s" % str(op))
			return []

	return result

# swap: replace the component whose id == op["swap"] with a freshly-built
# catalog part (op["part"] == [family, tier, mark]), placed at the OLD
# component's rect.position. The new part's rect.size must equal the old
# rect.size exactly, or this is a hard error (returns false, caller aborts the
# whole apply()). Preserves array position (in-place replacement) so ordering
# stays stable/deterministic.
static func _apply_swap(components: Array, op: Dictionary) -> bool:
	var target_id: String = op["swap"]
	var part_spec: Array = op["part"]
	var family: String = part_spec[0]
	var tier: int = part_spec[1]
	var mark: int = part_spec[2]

	for i in range(components.size()):
		var comp: Dictionary = components[i]
		if comp.get("id", "") != target_id:
			continue

		if not comp.has("rect"):
			push_error("Variants.apply: swap target '%s' has no rect" % target_id)
			return false
		var old_rect: Rect2 = comp["rect"]

		var new_comp: Dictionary = Parts.make(family, tier, mark, old_rect.position, {"id": target_id})
		if new_comp.is_empty():
			push_error("Variants.apply: Parts.make failed for swap target '%s' (family=%s tier=%d mark=%d)" % [target_id, family, tier, mark])
			return false

		var new_rect: Rect2 = new_comp["rect"]
		if new_rect.size != old_rect.size:
			push_error("Variants.apply: swap size mismatch for '%s' -- old rect size %s, new part size %s (same-rect swap requires an exact size match)" % [target_id, old_rect.size, new_rect.size])
			return false

		components[i] = new_comp
		return true

	push_error("Variants.apply: swap target id '%s' not found in base components" % target_id)
	return false

# tune: overwrite a single field on the named component. Every other field is
# left untouched.
static func _apply_tune(components: Array, op: Dictionary) -> void:
	var target_id: String = op["tune"]
	var field: String = op["field"]
	var value = op["value"]

	for comp in components:
		if comp.get("id", "") == target_id:
			comp[field] = value
			return

	push_error("Variants.apply: tune target id '%s' not found in base components" % target_id)

# remove: drop the component with the given id entirely.
static func _apply_remove(components: Array, op: Dictionary) -> void:
	var target_id: String = op["remove"]
	for i in range(components.size()):
		if components[i].get("id", "") == target_id:
			components.remove_at(i)
			return

	push_error("Variants.apply: remove target id '%s' not found in base components" % target_id)

# classify: STATS_ONLY if every op is swap/tune (geometry-safe by construction
# -- same rect, catalog-legal stats); GEOMETRY if any op is a remove (changes
# the silhouette/connectivity, needs a full validator re-run).
static func classify(ops: Array) -> int:
	for op in ops:
		if op.has("remove"):
			return DeltaClass.GEOMETRY
	return DeltaClass.STATS_ONLY
