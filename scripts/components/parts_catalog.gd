class_name Parts

# M21 -- parts catalog: a data-driven table of named component variants
# ("marks") per spec class per tier, so ships stop hand-tuning stats and
# per-ship stat auditing collapses into one catalog test. See
# design_ideas/hull_shape_grammar.md §3 and
# implementation_plans/m21_parts_catalog_design.md.
#
# Runtime doesn't change at all: Parts.make() returns the exact same plain
# component-dict shape ships have always authored by hand. No ship files
# change in this milestone (M21 scope) -- this file only adds a factory that
# *could* replace hand-authored dicts in a future milestone (M22+).
#
# ---------------------------------------------------------------------------
# Encoding notes
# ---------------------------------------------------------------------------
# Families v1: "laser", "missile", "engine", "rcs", "reactor", "sensor",
# "comms", "hull".
#
# `sensor` is one family with FIVE sub-kinds, selected via opts["sensor_kind"]
# (default "omni_search" if omitted). This mirrors the fleet's existing
# component dicts, which all set "type": "sensors" and distinguish role only
# via id/fields -- e.g. frigate.gd's dir_high_res (dir_search), omni_main
# (omni_search), omni_short_hi_res (omni_pd), passive_em (passive_em),
# omni_collision (collision). Sub-kinds:
#   - "omni_search"  -- TAU arc, moderate bins/refresh, general contact awareness
#   - "omni_pd"      -- TAU arc, fast refresh + fine bins, feeds PD firing solutions
#   - "dir_search"   -- narrow arc, longer range, forward-facing search/fire-control
#   - "passive_em"   -- TAU arc, EM-only bearing, no active emission
#   - "collision"    -- TAU arc, very short range, very fast refresh (helm/avoidance)
#
# `hull` marks are DENSITY grades, not stat points: civilian d=15 / standard
# d=20 / armored d=35 (mass and damage-soak scale together -- see
# hull_shape_grammar.md §3). Since hull rects are layout-driven (a hull is
# however big the silhouette needs it to be, not a fixed footprint), hull is
# the one family where `opts` MUST carry an explicit "size" (Vector2) --
# there's no default rect size to grow with the mark. Health scales with
# rect area * density so bigger/denser hull pieces are also tougher, matching
# every hand-authored hull component in the fleet.
#
# `opts: Dictionary` (all families) carries:
#   - "id": String            -- explicit component id (default: auto-generated, unique)
#   - "heading": float        -- forward-facing direction in radians (default 0.0);
#                                 applies to weapons/sensors (fields they already carry)
#   - "sensor_kind": String   -- sensor family only, one of the five kinds above
#   - "size": Vector2         -- hull family only, required (rect size)
#   - any other key           -- a raw field override, applied last, verbatim,
#                                 after the mark's stat block is built. This lets
#                                 a caller override e.g. "range" without inventing
#                                 a new mark.
#
# `Mark.COMPACT/STANDARD/HEAVY` sit near band floor / band mid / band ceiling
# per component_spec.gd, footprint growing with mark (small rect at COMPACT,
# larger at HEAVY) -- see hull_shape_grammar.md §3's laser example. STANDARD
# marks are calibrated to reproduce the fleet's existing authored numbers
# (LAC's laser, the frigate's engine -- see test item 8) so existing designs
# are expressible in the catalog unchanged.

const ComponentSpec = preload("res://scripts/components/component_spec.gd")

enum Mark { COMPACT, STANDARD, HEAVY }

# Monotonically-increasing counter backing auto-generated ids when opts has no
# explicit "id" -- guarantees two calls without an id yield distinct ids
# (test item 5) without relying on randomness.
static var _auto_id_counter: int = 0

static func _next_auto_id(family: String) -> String:
	_auto_id_counter += 1
	return "auto_%s_%d" % [family, _auto_id_counter]

# v1 family list (test item 1 -- enumeration completeness).
static func families() -> Array:
	return ["laser", "missile", "engine", "rcs", "reactor", "sensor", "comms", "hull"]

# Which tiers each family supports. A family/tier hole here (e.g. STRUCTURE
# has no "engine" entry) is an explicit, intentional absence -- ships of that
# tier don't carry that part type at all (see ship_design_validator.gd rule 6:
# STRUCTURE-tier ships must NOT have engines). Mirrors the holes already in
# ComponentSpec.COMPONENT_BANDS.
static func supported_tiers(family: String) -> Array:
	match family:
		"engine":
			return [ComponentSpec.Tier.DRONE, ComponentSpec.Tier.LIGHT, ComponentSpec.Tier.MEDIUM, ComponentSpec.Tier.HEAVY]
		"laser", "missile":
			return [ComponentSpec.Tier.DRONE, ComponentSpec.Tier.LIGHT, ComponentSpec.Tier.MEDIUM, ComponentSpec.Tier.HEAVY, ComponentSpec.Tier.STRUCTURE]
		"rcs", "comms", "sensor", "hull":
			return [ComponentSpec.Tier.DRONE, ComponentSpec.Tier.LIGHT, ComponentSpec.Tier.MEDIUM, ComponentSpec.Tier.HEAVY, ComponentSpec.Tier.STRUCTURE]
		"reactor":
			return [ComponentSpec.Tier.DRONE, ComponentSpec.Tier.LIGHT, ComponentSpec.Tier.MEDIUM, ComponentSpec.Tier.HEAVY, ComponentSpec.Tier.STRUCTURE]
		_:
			return []

# ---------------------------------------------------------------------------
# PARTS table -- one row per (family, tier, mark), each row a dict of the
# stat fields for that part (footprint stats are looked up separately in
# _rect_size_for so the two concerns -- "how good" and "how big" -- stay
# readable side by side). Values are hand-placed inside the component_spec.gd
# band for that tier: COMPACT near the floor, STANDARD at fleet-authored mid,
# HEAVY near the ceiling, primary stat strictly increasing mark-over-mark.
# ---------------------------------------------------------------------------

const PARTS := {
	"laser": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"damage": 60.0,  "range": 1200.0, "cooldown_max": 1.0, "size": Vector2(3, 3)},
			Mark.STANDARD: {"damage": 150.0, "range": 2200.0, "cooldown_max": 0.7, "size": Vector2(4, 4)},
			Mark.HEAVY:    {"damage": 280.0, "range": 3600.0, "cooldown_max": 0.4, "size": Vector2(5, 6)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"damage": 120.0, "range": 2200.0, "cooldown_max": 1.0, "size": Vector2(4, 4)},
			Mark.STANDARD: {"damage": 250.0, "range": 3000.0, "cooldown_max": 0.8, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"damage": 480.0, "range": 4400.0, "cooldown_max": 0.5, "size": Vector2(5, 8)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"damage": 340.0, "range": 3200.0, "cooldown_max": 1.2, "size": Vector2(4, 5)},
			Mark.STANDARD: {"damage": 500.0, "range": 4000.0, "cooldown_max": 1.0, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"damage": 900.0, "range": 6000.0, "cooldown_max": 0.7, "size": Vector2(6, 9)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"damage": 900.0,  "range": 4400.0, "cooldown_max": 1.2, "size": Vector2(5, 6)},
			Mark.STANDARD: {"damage": 1600.0, "range": 6000.0, "cooldown_max": 0.9, "size": Vector2(6, 8)},
			Mark.HEAVY:    {"damage": 3200.0, "range": 9000.0, "cooldown_max": 0.6, "size": Vector2(8, 12)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"damage": 350.0,  "range": 2200.0, "cooldown_max": 1.2, "size": Vector2(5, 5)},
			Mark.STANDARD: {"damage": 1000.0, "range": 4000.0, "cooldown_max": 0.9, "size": Vector2(6, 8)},
			Mark.HEAVY:    {"damage": 3200.0, "range": 7000.0, "cooldown_max": 0.6, "size": Vector2(8, 12)},
		},
	},
	"missile": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"range": 6000.0,  "cooldown_max": 24.0, "ammo": 2, "size": Vector2(3, 3)},
			Mark.STANDARD: {"range": 10000.0, "cooldown_max": 15.0, "ammo": 4, "size": Vector2(4, 4)},
			Mark.HEAVY:    {"range": 16000.0, "cooldown_max": 9.0, "ammo": 6, "size": Vector2(5, 6)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"range": 11000.0, "cooldown_max": 24.0, "ammo": 3, "size": Vector2(4, 4)},
			Mark.STANDARD: {"range": 12000.0, "cooldown_max": 18.0, "ammo": 4, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"range": 22000.0, "cooldown_max": 10.5, "ammo": 6, "size": Vector2(5, 8)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"range": 21000.0, "cooldown_max": 21.0, "ammo": 4,  "size": Vector2(5, 6)},
			Mark.STANDARD: {"range": 28000.0, "cooldown_max": 15.0, "ammo": 5,  "size": Vector2(5, 15)},
			Mark.HEAVY:    {"range": 38000.0, "cooldown_max": 9.0, "ammo": 8,  "size": Vector2(8, 18)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"range": 29000.0, "cooldown_max": 21.0, "ammo": 6,  "size": Vector2(5, 12)},
			Mark.STANDARD: {"range": 40000.0, "cooldown_max": 15.0, "ammo": 8,  "size": Vector2(8, 18)},
			Mark.HEAVY:    {"range": 58000.0, "cooldown_max": 7.5, "ammo": 12, "size": Vector2(10, 24)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"range": 21000.0, "cooldown_max": 21.0, "ammo": 6,  "size": Vector2(5, 12)},
			Mark.STANDARD: {"range": 35000.0, "cooldown_max": 15.0, "ammo": 10, "size": Vector2(8, 18)},
			Mark.HEAVY:    {"range": 58000.0, "cooldown_max": 7.5, "ammo": 16, "size": Vector2(10, 24)},
		},
	},
	"engine": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"thrust_rating": 500.0,  "torque_rating": 900.0,  "power_rating": 15.0, "size": Vector2(5, 5)},
			Mark.STANDARD: {"thrust_rating": 1400.0, "torque_rating": 2800.0, "power_rating": 25.0, "size": Vector2(7, 7)},
			Mark.HEAVY:    {"thrust_rating": 2700.0, "torque_rating": 5400.0, "power_rating": 40.0, "size": Vector2(9, 9)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"thrust_rating": 2300.0, "torque_rating": 4400.0,  "power_rating": 35.0, "size": Vector2(8, 8)},
			Mark.STANDARD: {"thrust_rating": 2500.0, "torque_rating": 5000.0,  "power_rating": 50.0, "size": Vector2(10, 10)},
			Mark.HEAVY:    {"thrust_rating": 6500.0, "torque_rating": 13000.0, "power_rating": 75.0, "size": Vector2(12, 14)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"thrust_rating": 4200.0,  "torque_rating": 8400.0,  "power_rating": 60.0,  "size": Vector2(5, 15)},
			Mark.STANDARD: {"thrust_rating": 5000.0,  "torque_rating": 10000.0, "power_rating": 100.0, "size": Vector2(5, 20)},
			Mark.HEAVY:    {"thrust_rating": 11500.0, "torque_rating": 23000.0, "power_rating": 150.0, "size": Vector2(8, 26)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"thrust_rating": 10500.0, "torque_rating": 21000.0, "power_rating": 120.0, "size": Vector2(8, 20)},
			Mark.STANDARD: {"thrust_rating": 16000.0, "torque_rating": 32000.0, "power_rating": 180.0, "size": Vector2(10, 26)},
			Mark.HEAVY:    {"thrust_rating": 31000.0, "torque_rating": 62000.0, "power_rating": 260.0, "size": Vector2(14, 32)},
		},
	},
	"rcs": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"thrust_rating": 60.0,  "torque_rating": 60.0,  "size": Vector2(2, 2)},
			Mark.STANDARD: {"thrust_rating": 220.0, "torque_rating": 220.0, "size": Vector2(3, 3)},
			Mark.HEAVY:    {"thrust_rating": 450.0, "torque_rating": 450.0, "size": Vector2(4, 4)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"thrust_rating": 250.0,  "torque_rating": 250.0,  "size": Vector2(3, 3)},
			Mark.STANDARD: {"thrust_rating": 900.0,  "torque_rating": 900.0,  "size": Vector2(4, 4)},
			Mark.HEAVY:    {"thrust_rating": 1800.0, "torque_rating": 1800.0, "size": Vector2(5, 5)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"thrust_rating": 600.0,  "torque_rating": 600.0,  "size": Vector2(4, 4)},
			Mark.STANDARD: {"thrust_rating": 2200.0, "torque_rating": 2200.0, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"thrust_rating": 4500.0, "torque_rating": 4500.0, "size": Vector2(6, 6)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"thrust_rating": 1200.0, "torque_rating": 1200.0, "size": Vector2(5, 5)},
			Mark.STANDARD: {"thrust_rating": 4500.0, "torque_rating": 4500.0, "size": Vector2(6, 6)},
			Mark.HEAVY:    {"thrust_rating": 9000.0, "torque_rating": 9000.0, "size": Vector2(8, 8)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"thrust_rating": 6000.0,  "torque_rating": 6000.0,  "size": Vector2(6, 6)},
			Mark.STANDARD: {"thrust_rating": 22000.0, "torque_rating": 22000.0, "size": Vector2(8, 8)},
			Mark.HEAVY:    {"thrust_rating": 45000.0, "torque_rating": 45000.0, "size": Vector2(10, 10)},
		},
	},
	"reactor": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"power_rating": 15.0,  "size": Vector2(3, 3)},
			Mark.STANDARD: {"power_rating": 40.0,  "size": Vector2(4, 4)},
			Mark.HEAVY:    {"power_rating": 70.0,  "size": Vector2(5, 5)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"power_rating": 50.0,  "size": Vector2(6, 6)},
			Mark.STANDARD: {"power_rating": 55.0,  "size": Vector2(10, 10)},
			Mark.HEAVY:    {"power_rating": 140.0, "size": Vector2(12, 12)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"power_rating": 90.0,  "size": Vector2(8, 8)},
			Mark.STANDARD: {"power_rating": 100.0, "size": Vector2(10, 10)},
			Mark.HEAVY:    {"power_rating": 270.0, "size": Vector2(14, 14)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"power_rating": 270.0, "size": Vector2(10, 12)},
			Mark.STANDARD: {"power_rating": 400.0, "size": Vector2(10, 12)},
			Mark.HEAVY:    {"power_rating": 850.0, "size": Vector2(14, 16)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"power_rating": 550.0,  "size": Vector2(12, 12)},
			Mark.STANDARD: {"power_rating": 1500.0, "size": Vector2(16, 16)},
			Mark.HEAVY:    {"power_rating": 5500.0, "size": Vector2(22, 22)},
		},
	},
	"comms": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"range": 2000.0,  "size": Vector2(2, 2)},
			Mark.STANDARD: {"range": 12000.0, "size": Vector2(3, 3)},
			Mark.HEAVY:    {"range": 22000.0, "size": Vector2(4, 4)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"range": 12000.0, "size": Vector2(3, 3)},
			Mark.STANDARD: {"range": 20000.0, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"range": 42000.0, "size": Vector2(6, 6)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"range": 22000.0, "size": Vector2(4, 4)},
			Mark.STANDARD: {"range": 30000.0, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"range": 55000.0, "size": Vector2(7, 7)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"range": 42000.0,  "size": Vector2(5, 5)},
			Mark.STANDARD: {"range": 65000.0,  "size": Vector2(7, 7)},
			Mark.HEAVY:    {"range": 115000.0, "size": Vector2(9, 9)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"range": 42000.0,  "size": Vector2(6, 6)},
			Mark.STANDARD: {"range": 90000.0,  "size": Vector2(8, 8)},
			Mark.HEAVY:    {"range": 240000.0, "size": Vector2(12, 12)},
		},
	},
	# Sensor stat bands in component_spec.gd are keyed on "health", not a
	# sensing-quality stat -- the actual sensing fields (range/arc_width/
	# num_bins/refresh_interval) are unbanded per component_spec.gd. Marks
	# still grow footprint + health together (bigger dish, tougher mount);
	# per test item 4, the monotonic PRIMARY stat for sensors is
	# num_bins/refresh quality, which we grow mark-over-mark even though
	# it's not band-checked, so the physical-grounding invariant holds.
	"sensor": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"health": 8.0,  "size": Vector2(2, 2)},
			Mark.STANDARD: {"health": 20.0, "size": Vector2(3, 3)},
			Mark.HEAVY:    {"health": 45.0, "size": Vector2(4, 4)},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"health": 14.0, "size": Vector2(3, 3)},
			Mark.STANDARD: {"health": 25.0, "size": Vector2(5, 5)},
			Mark.HEAVY:    {"health": 60.0, "size": Vector2(6, 6)},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"health": 20.0,  "size": Vector2(4, 4)},
			Mark.STANDARD: {"health": 40.0,  "size": Vector2(5, 5)},
			Mark.HEAVY:    {"health": 100.0, "size": Vector2(7, 7)},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"health": 40.0,  "size": Vector2(5, 5)},
			Mark.STANDARD: {"health": 90.0,  "size": Vector2(7, 7)},
			Mark.HEAVY:    {"health": 220.0, "size": Vector2(9, 9)},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"health": 40.0,  "size": Vector2(6, 6)},
			Mark.STANDARD: {"health": 120.0, "size": Vector2(9, 9)},
			Mark.HEAVY:    {"health": 420.0, "size": Vector2(13, 13)},
		},
	},
	# health_per_area values are calibrated against HULL_REFERENCE_AREA (below)
	# -- the rect size a hull chunk of that tier is expected to typically be
	# laid out at -- so COMPACT/STANDARD/HEAVY land near band floor/fleet-mid/
	# ceiling AT THAT REFERENCE AREA specifically (hull rects are otherwise
	# layout-driven per file header, so band conformance is inherently
	# size-dependent; the reference area is what test_parts_catalog uses).
	"hull": {
		ComponentSpec.Tier.DRONE: {
			Mark.COMPACT:  {"health_per_area": 0.375},
			Mark.STANDARD: {"health_per_area": 1.5},
			Mark.HEAVY:    {"health_per_area": 3.75},
		},
		ComponentSpec.Tier.LIGHT: {
			Mark.COMPACT:  {"health_per_area": 0.72},
			Mark.STANDARD: {"health_per_area": 1.28},
			Mark.HEAVY:    {"health_per_area": 3.2},
		},
		ComponentSpec.Tier.MEDIUM: {
			Mark.COMPACT:  {"health_per_area": 1.4},
			Mark.STANDARD: {"health_per_area": 2.33},
			Mark.HEAVY:    {"health_per_area": 4.0},
		},
		ComponentSpec.Tier.HEAVY: {
			Mark.COMPACT:  {"health_per_area": 1.83},
			Mark.STANDARD: {"health_per_area": 3.33},
			Mark.HEAVY:    {"health_per_area": 7.0},
		},
		ComponentSpec.Tier.STRUCTURE: {
			Mark.COMPACT:  {"health_per_area": 1.6},
			Mark.STANDARD: {"health_per_area": 4.0},
			Mark.HEAVY:    {"health_per_area": 20.0},
		},
	},
}

# Reference hull rect area (rect.size.x * rect.size.y) per tier -- see the
# "hull" PARTS comment above. Exposed so test_parts_catalog can build its
# band-conformance/monotonic-marks hull fixtures at a size the marks were
# actually calibrated against.
const HULL_REFERENCE_AREA := {
	ComponentSpec.Tier.DRONE: 40.0,
	ComponentSpec.Tier.LIGHT: 125.0,
	ComponentSpec.Tier.MEDIUM: 300.0,
	ComponentSpec.Tier.HEAVY: 600.0,
	ComponentSpec.Tier.STRUCTURE: 2000.0,
}

# Hull density grades keyed by mark -- see file header. Fixed across tiers
# (a civilian hull plate is d=15 whether it's on a shuttle or a destroyer);
# only the health-per-area (and therefore total health/mass) scales by tier.
const HULL_DENSITY := {
	Mark.COMPACT: 15.0,   # civilian
	Mark.STANDARD: 20.0,  # standard -- matches every hand-authored hull component today
	Mark.HEAVY: 35.0,     # armored
}

# ---------------------------------------------------------------------------
# Sensor sub-kind shape table -- arc_width/num_bins/refresh_interval/active/
# sensor_type per sub-kind. num_bins and refresh_interval get a per-mark
# multiplier (finer bins, faster refresh at higher marks) applied in make().
# ---------------------------------------------------------------------------

const SENSOR_KIND_SHAPE := {
	"omni_search": {"sensor_type": "active", "active": true, "arc_width": TAU, "base_num_bins": 36, "base_refresh": 1.5, "range_mult": 1.0},
	"omni_pd":     {"sensor_type": "active", "active": true, "arc_width": TAU, "base_num_bins": 900, "base_refresh": 0.15, "range_mult": 0.2},
	"dir_search":  {"sensor_type": "active", "active": true, "arc_width": PI / 6.0, "base_num_bins": 30, "base_refresh": 0.5, "range_mult": 1.6},
	"passive_em":  {"sensor_type": "passive_em", "active": true, "arc_width": TAU, "base_num_bins": 360, "base_refresh": 1.0, "range_mult": 3.2},
	"collision":   {"sensor_type": "active", "active": true, "arc_width": TAU, "base_num_bins": 8, "base_refresh": 0.1, "range_mult": 0.06},
}

# Per-mark quality multiplier applied to a sensor sub-kind's base bins/refresh:
# higher mark = more bins (finer), lower refresh (faster). Kept as a single
# small table so the "sensor quality" primary stat (test item 4) is legible.
const SENSOR_MARK_QUALITY := {
	Mark.COMPACT:  {"bins_mult": 0.6, "refresh_mult": 1.6},
	Mark.STANDARD: {"bins_mult": 1.0, "refresh_mult": 1.0},
	Mark.HEAVY:    {"bins_mult": 1.8, "refresh_mult": 0.6},
}

# A sensor's "primary stat" for the monotonic-marks invariant (test item 4) is
# a single scalar quality score combining finer bins + faster refresh (lower
# refresh_interval is better, so we invert it). Exposed as a helper so the
# test and any future caller compute it identically.
static func sensor_quality_score(comp: Dictionary) -> float:
	var num_bins: float = comp.get("num_bins", 1.0)
	var refresh: float = max(0.001, comp.get("refresh_interval", 1.0))
	return num_bins / refresh

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

# Builds a plain component dict for `family` at `tier`/`mark`, placed at `pos`
# (top-left of its rect, i.e. rect.position == pos). `opts` overrides -- see
# file header for the recognized keys ("id", "heading", "sensor_kind",
# "size", plus raw field overrides applied last).
static func make(family: String, tier: int, mark: int, pos: Vector2, opts: Dictionary = {}) -> Dictionary:
	var family_table: Dictionary = PARTS.get(family, {})
	if not family_table.has(tier):
		push_error("Parts.make: family '%s' has no entry for tier %d" % [family, tier])
		return {}
	var mark_row: Dictionary = family_table[tier].get(mark, {})
	if mark_row.is_empty():
		push_error("Parts.make: family '%s' tier %d has no entry for mark %d" % [family, tier, mark])
		return {}

	var comp_id: String = opts.get("id", _next_auto_id(family))
	var heading: float = opts.get("heading", 0.0)
	var density: float = 20.0

	var comp: Dictionary = {}

	match family:
		"hull":
			comp = _make_hull(tier, mark, mark_row, pos, opts)
		"laser", "missile":
			comp = _make_weapon(family, tier, mark, mark_row, pos, comp_id, heading, density)
		"engine":
			comp = _make_engine(mark_row, pos, comp_id, density)
		"rcs":
			comp = _make_rcs(mark_row, pos, comp_id, density)
		"reactor":
			comp = _make_reactor(mark_row, pos, comp_id, density)
		"comms":
			comp = _make_comms(mark_row, pos, comp_id, density)
		"sensor":
			comp = _make_sensor(tier, mark, mark_row, pos, comp_id, heading, density, opts)
		_:
			push_error("Parts.make: unknown family '%s'" % family)
			return {}

	# Apply raw field overrides last (everything in opts that isn't one of the
	# recognized structural keys). This lets a caller tune a single stat
	# without inventing a new mark row.
	var structural_keys := ["id", "heading", "sensor_kind", "size"]
	for key in opts.keys():
		if not structural_keys.has(key):
			comp[key] = opts[key]

	return comp

# ---------------------------------------------------------------------------
# Per-family builders
# ---------------------------------------------------------------------------

static func _base_dict(comp_id: String, type: String, rect: Rect2, health: float, density: float) -> Dictionary:
	return {
		"id": comp_id,
		"type": type,
		"rect": rect,
		"health": health,
		"max_health": health,
		"density": density,
		"heat": 0.0,
		"em_emission": 0.0,
		"switchable": true,
	}

static func _make_hull(tier: int, mark: int, mark_row: Dictionary, pos: Vector2, opts: Dictionary) -> Dictionary:
	if not opts.has("size"):
		push_error("Parts.make: hull family requires opts.size (Vector2) -- hull rects are layout-driven")
		return {}
	var size: Vector2 = opts["size"]
	var rect := Rect2(pos, size)
	var area: float = size.x * size.y
	var health_per_area: float = mark_row.get("health_per_area", 1.0)
	var health: float = max(1.0, area * health_per_area)
	var density: float = HULL_DENSITY.get(mark, 20.0)
	var comp_id: String = opts.get("id", _next_auto_id("hull"))
	var comp := _base_dict(comp_id, "hull", rect, health, density)
	comp["switchable"] = false
	return comp

static func _make_weapon(family: String, tier: int, mark: int, mark_row: Dictionary, pos: Vector2, comp_id: String, heading: float, density: float) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(5, 5))
	var rect := Rect2(pos, size)
	# Weapon hardpoint health/max_health tracks fleet convention (e.g. LAC's
	# laser is health 55 on a 5x5; frigate's is 150 on a 5x5) -- scale with
	# rect area so bigger mounts are tougher, same idea as hull.
	var area: float = size.x * size.y
	var health: float = max(10.0, area * 2.2)
	var comp := _base_dict(comp_id, "weapons", rect, health, density)
	comp["base_em_emission"] = 0.0
	comp["weapon_type"] = family
	comp["heading"] = heading
	comp["arc_width"] = PI / 3.0
	comp["range"] = mark_row["range"]
	comp["cooldown_max"] = mark_row["cooldown_max"]
	if family == "laser":
		comp["damage"] = mark_row["damage"]
	else: # missile
		comp["ammo"] = mark_row.get("ammo", 4)
	return comp

static func _make_engine(mark_row: Dictionary, pos: Vector2, comp_id: String, density: float) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(10, 10))
	var rect := Rect2(pos, size)
	var area: float = size.x * size.y
	var health: float = max(10.0, area * 0.6)
	var comp := _base_dict(comp_id, "engines", rect, health, density)
	comp["powered_on"] = true
	comp["power_rating"] = mark_row["power_rating"]
	comp["thrust_rating"] = mark_row["thrust_rating"]
	comp["torque_rating"] = mark_row["torque_rating"]
	return comp

static func _make_rcs(mark_row: Dictionary, pos: Vector2, comp_id: String, density: float) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(4, 4))
	var rect := Rect2(pos, size)
	var area: float = size.x * size.y
	var health: float = max(10.0, area * 2.0)
	var comp := _base_dict(comp_id, "rcs", rect, health, density)
	comp["thrust_rating"] = mark_row["thrust_rating"]
	comp["torque_rating"] = mark_row["torque_rating"]
	return comp

static func _make_reactor(mark_row: Dictionary, pos: Vector2, comp_id: String, density: float) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(10, 10))
	var rect := Rect2(pos, size)
	var area: float = size.x * size.y
	var health: float = max(10.0, area * 0.5)
	var comp := _base_dict(comp_id, "reactor", rect, health, density)
	comp["power_rating"] = mark_row["power_rating"]
	return comp

static func _make_comms(mark_row: Dictionary, pos: Vector2, comp_id: String, density: float) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(5, 5))
	var rect := Rect2(pos, size)
	var area: float = size.x * size.y
	var health: float = max(10.0, area * 1.2)
	var comp := _base_dict(comp_id, "comms", rect, health, density)
	comp["powered_on"] = true
	comp["range"] = mark_row["range"]
	return comp

static func _make_sensor(tier: int, mark: int, mark_row: Dictionary, pos: Vector2, comp_id: String, heading: float, density: float, opts: Dictionary) -> Dictionary:
	var size: Vector2 = mark_row.get("size", Vector2(5, 5))
	var rect := Rect2(pos, size)
	var health: float = mark_row["health"]
	var comp := _base_dict(comp_id, "sensors", rect, health, density)

	var sensor_kind: String = opts.get("sensor_kind", "omni_search")
	var kind_shape: Dictionary = SENSOR_KIND_SHAPE.get(sensor_kind, SENSOR_KIND_SHAPE["omni_search"])
	var quality: Dictionary = SENSOR_MARK_QUALITY.get(mark, SENSOR_MARK_QUALITY[Mark.STANDARD])

	comp["powered_on"] = true
	comp["sensor_type"] = kind_shape["sensor_type"]
	comp["active"] = kind_shape["active"]
	comp["arc_width"] = kind_shape["arc_width"]
	comp["heading"] = heading
	# "timer" is deliberately NOT set here -- it's runtime scratch (the
	# per-sweep countdown), normalized by Ship._ready() same as every
	# hand-authored ship's sensors. See file header / test item 3.

	var base_range: float = 20000.0 * kind_shape["range_mult"] * (1.0 + 0.3 * float(mark))
	comp["range"] = base_range

	var num_bins: int = int(round(kind_shape["base_num_bins"] * quality["bins_mult"]))
	comp["num_bins"] = max(1, num_bins)
	var refresh: float = kind_shape["base_refresh"] * quality["refresh_mult"]
	comp["refresh_interval"] = max(0.01, refresh)

	if sensor_kind == "passive_em":
		comp["base_em_emission"] = 0.0
		comp["em_emission"] = 0.0
	else:
		var em: float = 6.0 + 3.0 * float(mark)
		comp["base_em_emission"] = em
		comp["em_emission"] = em

	return comp
