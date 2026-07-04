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

