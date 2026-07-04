class_name ShipDesignValidator

# M9b -- validates an authored ship's components + handling stats against the
# spec chart in component_spec.gd. See
# implementation_plans/m9b_spec_chart_design.md for the full rule set.
#
# Scope: catalog ship classes only (Frigate, and the M9c ships). Does NOT
# validate missile.gd (ordnance, fast and weird on purpose) or
# buoy.gd/sensor_drone.gd. A ship opts in by declaring a real ship_tier;
# classes left at ComponentSpec.Tier.UNVALIDATED are skipped (ok=true, no
# violations -- an explicit opt-out, not a failure).

# Preload const (not the global `ComponentSpec` class_name) so this compiles
# regardless of the git-tracked global class cache, which the headless
# --run-test path doesn't regenerate. See ship.gd for the same rationale.
const ComponentSpec = preload("res://scripts/components/component_spec.gd")

const REQUIRED_KEYS := ["id", "type", "rect", "health", "max_health", "density"]

# Returns { "ok": bool, "tier": int, "violations": Array }
# Each violation: { "component_id": String, "field": String, "reason": String, "severity": String }
# "ok" is true iff there are no "error"-severity violations -- "warning"-severity
# violations (banded stat checks + handling checks, see M9c) don't block.
static func validate(ship) -> Dictionary:
	var tier: int = ship.ship_tier
	var violations: Array = []

	if tier == ComponentSpec.Tier.UNVALIDATED:
		return {"ok": true, "tier": tier, "violations": violations}

	var components: Array = ship.ship_components

	_check_structural(components, tier, violations)
	_check_banded_stats(components, tier, violations)
	_check_handling(ship, tier, violations)
	_check_overlaps(components, violations)
	_check_connectivity(components, violations)
	_check_pd_coherence(components, violations)
	_check_hull_coverage(components, violations)
	_check_active_surface(components, violations)

	var has_error := violations.any(func(v): return v["severity"] == "error")
	return {"ok": not has_error, "tier": tier, "violations": violations}

# ---------------------------------------------------------------------------
# 3a. Structural rules
# ---------------------------------------------------------------------------

static func _check_structural(components: Array, tier: int, violations: Array) -> void:
	var seen_ids := {}
	var has_hull := false
	var has_reactor := false
	var has_engines := false
	var has_rcs := false
	var has_sensors := false
	var has_powered_non_reactor := false
	var has_living_quarters := false
	var has_cargo_bay := false
	
	var total_living_area := 0.0
	var total_cargo_area := 0.0

	for comp in components:
		var comp_id: String = comp.get("id", "<missing id>")

		# Rule 1: schema -- every component dict has the required keys.
		var missing_keys: Array = []
		for key in REQUIRED_KEYS:
			if not comp.has(key):
				missing_keys.append(key)
		if not missing_keys.is_empty():
			violations.append({
				"component_id": comp_id,
				"field": "schema",
				"reason": "missing required key(s): " + str(missing_keys),
				"severity": "error",
			})
			# Skip further checks on this component if core fields are absent --
			# health-sanity checks below assume the keys exist.
			continue

		# Rule 2: unique ids.
		if seen_ids.has(comp_id):
			violations.append({
				"component_id": comp_id,
				"field": "id",
				"reason": "duplicate component id",
				"severity": "error",
			})
		else:
			seen_ids[comp_id] = true

		# Rule 3: health sanity.
		var health = comp["health"]
		var max_health = comp["max_health"]
		var density = comp["density"]
		if not (max_health > 0):
			violations.append({"component_id": comp_id, "field": "max_health", "reason": "max_health must be > 0, got " + str(max_health), "severity": "error"})
		if not (health > 0 and health <= max_health):
			violations.append({"component_id": comp_id, "field": "health", "reason": "health must satisfy 0 < health <= max_health, got health=" + str(health) + " max_health=" + str(max_health), "severity": "error"})
		if not (density > 0):
			violations.append({"component_id": comp_id, "field": "density", "reason": "density must be > 0, got " + str(density), "severity": "error"})

		var type: String = comp.get("type", "")

		if type == "hull":
			has_hull = true
		elif type == "reactor":
			has_reactor = true
			if not (comp.get("power_rating", 0.0) > 0):
				violations.append({"component_id": comp_id, "field": "power_rating", "reason": "reactor must have power_rating > 0, got " + str(comp.get("power_rating", 0.0)), "severity": "error"})
		elif type == "engines":
			has_engines = true
			if not (comp.get("thrust_rating", 0.0) > 0):
				violations.append({"component_id": comp_id, "field": "thrust_rating", "reason": "engine must have thrust_rating > 0, got " + str(comp.get("thrust_rating", 0.0)), "severity": "error"})
		elif type == "rcs":
			has_rcs = true
			if not (comp.get("thrust_rating", 0.0) > 0):
				violations.append({"component_id": comp_id, "field": "thrust_rating", "reason": "rcs must have thrust_rating > 0, got " + str(comp.get("thrust_rating", 0.0)), "severity": "error"})
			if not (comp.get("torque_rating", 0.0) > 0):
				violations.append({"component_id": comp_id, "field": "torque_rating", "reason": "rcs must have torque_rating > 0, got " + str(comp.get("torque_rating", 0.0)), "severity": "error"})
		elif type == "sensors":
			has_sensors = true
		elif type == "living_quarters":
			has_living_quarters = true
			if comp.has("rect"):
				var r: Rect2 = comp["rect"]
				total_living_area += r.size.x * r.size.y
		elif type == "cargo_bay":
			has_cargo_bay = true
			if comp.has("rect"):
				var r: Rect2 = comp["rect"]
				total_cargo_area += r.size.x * r.size.y

		# Rule 8 bookkeeping: any powered component type other than hull/reactor.
		if type != "hull" and type != "reactor":
			has_powered_non_reactor = true

	# Rule 4: has a hull.
	if not has_hull:
		violations.append({"component_id": "<ship>", "field": "hull", "reason": "ship has no component of type 'hull'", "severity": "error"})

	# Rule 5: has a reactor (with power_rating > 0, checked per-component above).
	if not has_reactor:
		violations.append({"component_id": "<ship>", "field": "reactor", "reason": "ship has no component of type 'reactor' with power_rating > 0", "severity": "error"})

	# Rule 6: mobility -- DRONE..HEAVY need engines; STRUCTURE is exempt (and
	# having engines at all is itself a violation for STRUCTURE). STRUCTURE also
	# requires capacity components (living quarters, cargo).
	if tier == ComponentSpec.Tier.STRUCTURE:
		if has_engines:
			violations.append({"component_id": "<ship>", "field": "engines", "reason": "STRUCTURE-tier ship must not have any 'engines' component (immobile by design)", "severity": "error"})
		if not has_rcs:
			violations.append({"component_id": "<ship>", "field": "rcs", "reason": "STRUCTURE-tier ship must have an 'rcs' component for station keeping", "severity": "error"})
		if not has_living_quarters:
			violations.append({"component_id": "<ship>", "field": "living_quarters", "reason": "STRUCTURE-tier ship must have a 'living_quarters' component", "severity": "error"})
		if not has_cargo_bay:
			violations.append({"component_id": "<ship>", "field": "cargo_bay", "reason": "STRUCTURE-tier ship must have a 'cargo_bay' component", "severity": "error"})
		
		# Log a warning if capacity is unusually small (e.g. 0)
		var human_capacity = total_living_area / ComponentSpec.AREA_PER_PERSON
		var cargo_capacity = total_cargo_area / ComponentSpec.CARGO_AREA_PER_UNIT
		if human_capacity < 1.0:
			violations.append({"component_id": "<ship>", "field": "capacity", "reason": "STRUCTURE-tier ship has less than 1 person capacity", "severity": "warning"})
	else:
		if not has_engines:
			violations.append({"component_id": "<ship>", "field": "engines", "reason": "ship has no component of type 'engines' with thrust_rating > 0", "severity": "error"})

	# Rule 7: not blind.
	if not has_sensors:
		violations.append({"component_id": "<ship>", "field": "sensors", "reason": "ship has no component of type 'sensors'", "severity": "error"})

	# Rule 8: reactor sufficiency (structural form -- gross case only).
	if has_powered_non_reactor and not has_reactor:
		violations.append({"component_id": "<ship>", "field": "reactor", "reason": "ship has powered systems but no reactor", "severity": "error"})

# ---------------------------------------------------------------------------
# 3b. Banded stat checks (chart-driven, §4.2)
# ---------------------------------------------------------------------------

static func _check_banded_stats(components: Array, tier: int, violations: Array) -> void:
	for comp in components:
		if not (comp.has("id") and comp.has("type")):
			continue # already flagged by the schema check above

		violations.append_array(check_component_bands(comp, tier))

# M21 -- extracted from the loop above so the parts catalog test (and any
# future caller) can band-check a single component dict without going through
# a whole ship. Behavior is unchanged from the inline version: same lookups,
# same skip rules, same violation dict shape. comp is assumed to already have
# "id"/"type" (callers that skip that check, e.g. the loop above, do so
# before calling this).
static func check_component_bands(comp: Dictionary, tier: int) -> Array:
	var violations: Array = []

	var spec_class: String = ComponentSpec.resolve_spec_class(comp)
	if spec_class == "":
		return violations # no banded spec class for this component

	var class_bands: Dictionary = ComponentSpec.COMPONENT_BANDS.get(spec_class, {})
	if not class_bands.has(tier):
		return violations # this spec class has no entry for this tier -- skip, not a violation

	var tier_bands: Dictionary = class_bands[tier]
	var comp_id: String = comp.get("id", "<missing id>")
	for field in tier_bands.keys():
		if not comp.has(field):
			continue
		var value = comp[field]
		var band: Array = tier_bands[field]
		var lo = band[0]
		var hi = band[1]
		if not (value >= lo and value <= hi):
			violations.append({
				"component_id": comp_id,
				"field": field,
				"reason": str(field) + "=" + str(value) + " outside " + spec_class + " band for tier " + str(tier) + " [" + str(lo) + ", " + str(hi) + "]",
				"severity": "warning",
			})

	return violations

# ---------------------------------------------------------------------------
# 3c. Handling check (§4.3)
# ---------------------------------------------------------------------------

static func _check_handling(ship, tier: int, violations: Array) -> void:
	var bands: Dictionary = ComponentSpec.HANDLING_BANDS.get(tier, {})
	if bands.is_empty():
		return

	if bands.has("max_speed"):
		var speed_band: Array = bands["max_speed"]
		var max_speed = ship.max_speed
		if not (max_speed >= speed_band[0] and max_speed <= speed_band[1]):
			violations.append({
				"component_id": "<ship>",
				"field": "max_speed",
				"reason": "max_speed=" + str(max_speed) + " outside handling band for tier " + str(tier) + " [" + str(speed_band[0]) + ", " + str(speed_band[1]) + "]",
				"severity": "warning",
			})

	if bands.has("max_omega"):
		var omega_band: Array = bands["max_omega"]
		var max_omega = ship.max_omega
		if not (max_omega >= omega_band[0] and max_omega <= omega_band[1]):
			violations.append({
				"component_id": "<ship>",
				"field": "max_omega",
				"reason": "max_omega=" + str(max_omega) + " outside handling band for tier " + str(tier) + " [" + str(omega_band[0]) + ", " + str(omega_band[1]) + "]",
				"severity": "warning",
			})

# ---------------------------------------------------------------------------
# 3d. Overlap check (§4.4) -- no two components may overlap each other.
# ---------------------------------------------------------------------------

static func _check_overlaps(components: Array, violations: Array) -> void:
	# Collect components that have valid rects.
	var with_rects := []
	for comp in components:
		if not comp.has("rect") or not comp.has("id"):
			continue
		with_rects.append(comp)

	for i in range(with_rects.size()):
		var a = with_rects[i]
		var rect_a: Rect2 = a["rect"]
		for j in range(i + 1, with_rects.size()):
			var b = with_rects[j]
			var rect_b: Rect2 = b["rect"]
			if rect_a.intersects(rect_b, false):  # false = exclude touching edges
				violations.append({
					"component_id": a["id"],
					"field": "rect",
					"reason": "component '" + a["id"] + "' overlaps '" + b["id"] + "'",
					"severity": "error",
				})

# ---------------------------------------------------------------------------
# 3e. Connectivity check (§4.5) -- every component must touch or overlap at
# least one other component. A component is "adjacent" if their Rect2s share
# an edge (touching) or overlap.
# ---------------------------------------------------------------------------

static func _rects_adjacent(a: Rect2, b: Rect2) -> bool:
	# true if the two rects overlap OR share an edge (touching).
	# Rect2.intersects(r, true) returns true for touching edges.
	return a.intersects(b, true)

static func _check_connectivity(components: Array, violations: Array) -> void:
	if components.size() <= 1:
		return

	# Filter to components that actually have rects.
	var with_rects := []
	for comp in components:
		if comp.has("rect") and comp.has("id"):
			with_rects.append(comp)

	if with_rects.size() <= 1:
		return

	# Build adjacency and flood-fill from component 0.
	var visited := {}
	var queue := [0]
	visited[0] = true

	while not queue.is_empty():
		var current = queue.pop_front()
		var rect_c: Rect2 = with_rects[current]["rect"]
		for k in range(with_rects.size()):
			if visited.has(k):
				continue
			if _rects_adjacent(rect_c, with_rects[k]["rect"]):
				visited[k] = true
				queue.append(k)

	# Any unvisited component is disconnected.
	for k in range(with_rects.size()):
		if not visited.has(k):
			violations.append({
				"component_id": with_rects[k]["id"],
				"field": "rect",
				"reason": "component '" + with_rects[k]["id"] + "' is not adjacent to any other component (disconnected)",
				"severity": "error",
			})

# ---------------------------------------------------------------------------
# 3f. PD coherence (warning) -- ship lasers auto-fire at ordnance, so any laser
# weapon is a point-defense mount, and those turrets are only as good as the
# sensor feeding their firing solution. Too slow a refresh and they aim at
# second-stale positions and miss fast ordnance; too coarse a bin count and the
# tracked bearing is too imprecise to hit. Flag a ship that carries lasers but
# has no active sensor quick and fine enough to track ordnance.
#
# Warning, not error: deliberate low-end designs are allowed (the light attack
# craft's single forward laser off a 0.5s dish passes at the threshold). This
# only catches "turrets with no eyes" -- the failure that had stations firing
# four PD turrets off a 1.0s strategic search dish. Arc-coverage geometry (does
# the sensor cone actually cover each turret's arc?) is a deliberate v1 scope
# cut; this just asks whether a PD-capable sensor exists at all.
# ---------------------------------------------------------------------------

const PD_SENSOR_MAX_REFRESH := 0.5   # seconds between sweeps; slower can't aim at ordnance
const PD_SENSOR_MIN_BINS := 36       # angular bins; coarser can't resolve a firing solution

static func _check_pd_coherence(components: Array, violations: Array) -> void:
	var has_laser := false
	for comp in components:
		if comp.get("type", "") == "weapons" and comp.get("weapon_type", "") == "laser":
			has_laser = true
			break
	if not has_laser:
		return

	var has_pd_sensor := false
	for comp in components:
		if comp.get("type", "") != "sensors":
			continue
		if comp.get("active", true) == false:
			continue
		# passive_em senses bearing/EM only, not the resolved position a firing
		# solution needs, so it never counts as a PD tracker.
		if comp.get("sensor_type", "active") == "passive_em":
			continue
		if comp.get("refresh_interval", 0.0) <= PD_SENSOR_MAX_REFRESH and comp.get("num_bins", 0) >= PD_SENSOR_MIN_BINS:
			has_pd_sensor = true
			break

	if not has_pd_sensor:
		violations.append({
			"component_id": "<ship>",
			"field": "pd_sensor",
			"reason": "ship has laser (point-defense) weapons but no active sensor fast/fine enough to aim them (need refresh_interval <= " + str(PD_SENSOR_MAX_REFRESH) + "s and num_bins >= " + str(PD_SENSOR_MIN_BINS) + ")",
			"severity": "warning",
		})

# ---------------------------------------------------------------------------
# 3g/3h. M23 -- mechanized layout checks (hull coverage + active surfaces).
# See implementation_plans/m23_layout_coverage_checks_design.md and
# design_ideas/hull_shape_grammar.md section 6. These mechanize the
# ship-design skill's two human-eyeball checklist items (SKILL.md 4a/4e) as
# validator WARNINGS -- ok stays true regardless, deliberate glass-cannon
# designs remain legal, the point is visibility not prohibition.
#
# Both checks operate purely on the components array (no Ship instance) and
# reuse the exact geometry semantics of ship.gd's damage raymarch
# (DAMAGE_RAYMARCH_STEP, Rect2.has_point containment, get_local_aabb's
# min/max-over-rects) so a check's verdict agrees with how damage actually
# propagates through the hull.
# ---------------------------------------------------------------------------

# Mirrors ship.gd's DAMAGE_RAYMARCH_STEP (2.0) -- kept as an independent const
# (this file must not depend on a Ship instance/autoload) but MUST be kept in
# sync with ship.gd if that constant ever changes.
const LAYOUT_RAYMARCH_STEP := 2.0
const LAYOUT_RAY_START_OFFSET := 0.5  # start the ray this far outside the face, per the plan

# Types the two layout checks apply to. Comms/reactor/hull (and rcs, cargo,
# living quarters, docking ports) are exempt from both -- only components with
# a directional purpose (weapon/sensor/engine) have an "active surface" or a
# coverage expectation in the skill's rules.
const LAYOUT_CHECKED_TYPES := ["weapons", "sensors", "engines"]

# Cardinal face directions, keyed by name for violation messages.
const _FACE_DIRS := {
	"+X": Vector2(1, 0),
	"-X": Vector2(-1, 0),
	"+Y": Vector2(0, 1),
	"-Y": Vector2(0, -1),
}

# Ship AABB from the components array alone -- same min/max-over-rects
# construction as ship.gd's get_local_aabb(), so face-exit tests agree with
# the real ship bounding box the damage raymarch clips rays against.
static func _components_aabb(components: Array) -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for comp in components:
		if not comp.has("rect"):
			continue
		var r: Rect2 = comp["rect"]
		min_x = min(min_x, r.position.x)
		max_x = max(max_x, r.position.x + r.size.x)
		min_y = min(min_y, r.position.y)
		max_y = max(max_y, r.position.y + r.size.y)
	if min_x == INF:
		return Rect2(-10, -10, 20, 20)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

# Nearest-cardinal mapping for a heading angle, per the plan: 0 -> +X,
# PI/-PI -> -X, -PI/2 -> -Y, +PI/2 -> +Y. Ties (exactly PI/4 etc.) fall to
# whichever quadrant wrapf lands closest to; component headings in this
# codebase are always authored at exact cardinal/intercardinal-safe angles.
static func _nearest_cardinal(heading: float) -> String:
	var h := wrapf(heading, -PI, PI)
	if abs(h) <= PI / 4.0:
		return "+X"
	if abs(h) >= 3.0 * PI / 4.0:
		return "-X"
	if h > 0.0:
		return "+Y"
	return "-Y"

# True if this component's arc is omnidirectional -- no active face concept
# applies (matches the ship.gd convention at line ~1472: arc_width < TAU-0.01
# means "not omni").
static func _is_omni(comp: Dictionary) -> bool:
	var arc: float = comp.get("arc_width", 0.0)
	return arc >= TAU - 0.01

# The center point of one cardinal face of a rect.
static func _face_center(rect: Rect2, dir_name: String) -> Vector2:
	match dir_name:
		"+X":
			return Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5)
		"-X":
			return Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)
		"+Y":
			return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
		"-Y":
			return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
		_:
			return rect.get_center()

# March outward from `start` in direction `dir_vec`, at the damage-raymarch
# step size, until either (a) leaving the ship AABB -- exposed, returns true --
# or (b) entering some OTHER component's rect -- covered, returns false.
# `self_id` is excluded from the "crossed a component" test (a component can't
# cover its own face).
static func _ray_exits_aabb_uncovered(start: Vector2, dir_vec: Vector2, aabb: Rect2, components: Array, self_id: String) -> bool:
	var pos := start
	# Bound the march so a pathological/empty AABB can't spin forever --
	# the ship's own diagonal is always a safe upper bound on how far a ray
	# inside (or just outside) the AABB needs to travel to exit it.
	var max_dist: float = aabb.size.length() + LAYOUT_RAY_START_OFFSET + LAYOUT_RAYMARCH_STEP * 2.0
	var max_steps: int = int(ceil(max_dist / LAYOUT_RAYMARCH_STEP)) + 2

	for i in range(max_steps):
		if not aabb.has_point(pos):
			return true # exited the ship's own bounding box -- exposed

		for comp in components:
			if comp.get("id", "") == self_id:
				continue
			if not comp.has("rect"):
				continue
			var r: Rect2 = comp["rect"]
			if r.has_point(pos):
				return false # covered -- another component's rect stops the ray

		pos += dir_vec * LAYOUT_RAYMARCH_STEP

	# Ran out of steps without leaving the AABB or hitting a component -- treat
	# as covered (shouldn't happen given the max_dist bound, but fail closed
	# rather than false-flagging a warning).
	return false

# _check_hull_coverage -- for each weapon/sensor/engine, cast an outward ray
# from the center of each NON-active face (omni components: all four faces,
# since they have no active face). If the ray exits the ship's
# component-union AABB without crossing any OTHER component's rect, the face
# is unarmored from that direction -- warn "exposed face <dir>".
static func _check_hull_coverage(components: Array, violations: Array) -> void:
	var aabb := _components_aabb(components)

	for comp in components:
		var type: String = comp.get("type", "")
		if not LAYOUT_CHECKED_TYPES.has(type):
			continue
		if not comp.has("rect") or not comp.has("id"):
			continue

		var comp_id: String = comp["id"]
		var rect: Rect2 = comp["rect"]
		var omni := _is_omni(comp)
		var active_face := "" if omni else _active_face_dir(comp, type)

		for dir_name in _FACE_DIRS.keys():
			if not omni and dir_name == active_face:
				continue # active face is the active-surface check's job, not coverage's

			var dir_vec: Vector2 = _FACE_DIRS[dir_name]
			var start: Vector2 = _face_center(rect, dir_name) + dir_vec * LAYOUT_RAY_START_OFFSET
			if _ray_exits_aabb_uncovered(start, dir_vec, aabb, components, comp_id):
				violations.append({
					"component_id": comp_id,
					"field": "hull_coverage",
					"reason": "component '" + comp_id + "' has an exposed face (" + dir_name + ") -- no hull or other component covers it from that direction",
					"severity": "warning",
				})

# The face in the component's heading direction, mapped to the nearest
# cardinal. Engines are a special case: their active face is ALWAYS -X
# (exhaust points aft) regardless of the authored heading field.
static func _active_face_dir(comp: Dictionary, type: String) -> String:
	if type == "engines":
		return "-X"
	return _nearest_cardinal(comp.get("heading", 0.0))

# _check_active_surface -- the face in the component's active direction must
# reach the ship AABB edge WITHOUT crossing another component's rect, else the
# component's functional surface (barrel/dish/exhaust) is masked -- warn
# "masked active face". Omni components are exempt (no active face concept).
static func _check_active_surface(components: Array, violations: Array) -> void:
	var aabb := _components_aabb(components)

	for comp in components:
		var type: String = comp.get("type", "")
		if not LAYOUT_CHECKED_TYPES.has(type):
			continue
		if not comp.has("rect") or not comp.has("id"):
			continue
		if _is_omni(comp):
			continue

		var comp_id: String = comp["id"]
		var rect: Rect2 = comp["rect"]
		var dir_name := _active_face_dir(comp, type)
		var dir_vec: Vector2 = _FACE_DIRS[dir_name]
		var start: Vector2 = _face_center(rect, dir_name) + dir_vec * LAYOUT_RAY_START_OFFSET

		if not _ray_exits_aabb_uncovered(start, dir_vec, aabb, components, comp_id):
			violations.append({
				"component_id": comp_id,
				"field": "active_surface",
				"reason": "component '" + comp_id + "' has a masked active face (" + dir_name + ") -- another component blocks its functional surface before reaching the hull edge",
				"severity": "warning",
			})

