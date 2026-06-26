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
	var has_sensors := false
	var has_powered_non_reactor := false

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
		elif type == "sensors":
			has_sensors = true

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
	# having engines at all is itself a violation for STRUCTURE).
	if tier == ComponentSpec.Tier.STRUCTURE:
		if has_engines:
			violations.append({"component_id": "<ship>", "field": "engines", "reason": "STRUCTURE-tier ship must not have any 'engines' component (immobile by design)", "severity": "error"})
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

		var spec_class: String = ComponentSpec.resolve_spec_class(comp)
		if spec_class == "":
			continue # no banded spec class for this component

		var class_bands: Dictionary = ComponentSpec.COMPONENT_BANDS.get(spec_class, {})
		if not class_bands.has(tier):
			continue # this spec class has no entry for this tier -- skip, not a violation

		var tier_bands: Dictionary = class_bands[tier]
		var comp_id: String = comp["id"]
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
