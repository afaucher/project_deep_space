class_name ComponentSpec

# M9b -- single source of truth for "what does a legal component look like for
# a given ship tier." See implementation_plans/m9b_spec_chart_design.md.
#
# MEDIUM is ground truth -- derived from the frigate's real authored numbers.
# DRONE/LIGHT/HEAVY/STRUCTURE bands are provisional first-cut scaffolding,
# to be tuned in M9c when shuttle / light-attack-craft / destroyer are
# tuning those tiers is a one-file edit here.

const AREA_PER_PERSON := 40.0
const CARGO_AREA_PER_UNIT := 10.0

enum Tier { UNVALIDATED = -1, DRONE = 0, LIGHT = 1, MEDIUM = 2, HEAVY = 3, STRUCTURE = 4 }

# ---------------------------------------------------------------------------
# 4.1 Spec-class resolution
# ---------------------------------------------------------------------------

# Returns the spec class (a key into COMPONENT_BANDS) for a component dict,
# or "" if the component has no banded spec class (e.g. weapons of an
# unrecognized weapon_type).
static func resolve_spec_class(comp: Dictionary) -> String:
	var type: String = comp.get("type", "")
	match type:
		"hull":
			return "hull"
		"reactor":
			return "reactor"
		"engines":
			return "engine"
		"rcs":
			return "rcs"
		"comms":
			return "comms"
		"sensors":
			return "sensor"
		"weapons":
			var weapon_type: String = comp.get("weapon_type", "")
			if weapon_type == "laser":
				return "laser"
			elif weapon_type == "missile":
				return "missile"
			return ""
		"living_quarters":
			return "living_quarters"
		"cargo_bay":
			return "cargo_bay"
		"life_support":
			return "life_support"
		"docking_port":
			return "docking_port"
		_:
			return ""

# ---------------------------------------------------------------------------
# 4.2 Component bands -- [min, max] per spec class per tier.
# Stats checked per class are the dictionary keys nested under each tier.
# A spec class with no entry for a given tier is skipped (not a violation) --
# e.g. STRUCTURE has no "engine" entry (§3a rule 6 covers that case instead).
# ---------------------------------------------------------------------------

const COMPONENT_BANDS := {
	"hull": {
		Tier.DRONE: {"health": [10.0, 300.0]},
		Tier.LIGHT: {"health": [80.0, 600.0]},
		Tier.MEDIUM: {"health": [400.0, 1500.0]},
		Tier.HEAVY: {"health": [1000.0, 5000.0]},
		Tier.STRUCTURE: {"health": [3000.0, 60000.0]},
	},
	"reactor": {
		Tier.DRONE: {"power_rating": [10.0, 80.0]},
		Tier.LIGHT: {"power_rating": [40.0, 160.0]},
		Tier.MEDIUM: {"power_rating": [80.0, 300.0]},
		Tier.HEAVY: {"power_rating": [250.0, 900.0]},
		Tier.STRUCTURE: {"power_rating": [500.0, 6000.0]},
	},
	"engine": {
		Tier.DRONE: {"thrust_rating": [300.0, 3000.0], "torque_rating": [600.0, 6000.0]},
		Tier.LIGHT: {"thrust_rating": [2000.0, 7000.0], "torque_rating": [4000.0, 14000.0]},
		Tier.MEDIUM: {"thrust_rating": [4000.0, 12000.0], "torque_rating": [8000.0, 24000.0]},
		Tier.HEAVY: {"thrust_rating": [10000.0, 32000.0], "torque_rating": [20000.0, 64000.0]},
		# STRUCTURE: no entry -- STRUCTURE has no engines (§3a rule 6).
	},
	"rcs": {
		Tier.DRONE: {"thrust_rating": [50.0, 500.0], "torque_rating": [50.0, 500.0]},
		Tier.LIGHT: {"thrust_rating": [200.0, 2000.0], "torque_rating": [200.0, 2000.0]},
		Tier.MEDIUM: {"thrust_rating": [500.0, 5000.0], "torque_rating": [500.0, 5000.0]},
		Tier.HEAVY: {"thrust_rating": [1000.0, 10000.0], "torque_rating": [1000.0, 10000.0]},
		Tier.STRUCTURE: {"thrust_rating": [5000.0, 50000.0], "torque_rating": [5000.0, 50000.0]},
	},
	"comms": {
		Tier.DRONE: {"range": [0.0, 25000.0]},
		Tier.LIGHT: {"range": [10000.0, 45000.0]},
		Tier.MEDIUM: {"range": [20000.0, 60000.0]},
		Tier.HEAVY: {"range": [40000.0, 120000.0]},
		Tier.STRUCTURE: {"range": [40000.0, 250000.0]},
	},
	"sensor": {
		Tier.DRONE: {"health": [5.0, 60.0]},
		Tier.LIGHT: {"health": [10.0, 80.0]},
		Tier.MEDIUM: {"health": [15.0, 120.0]},
		Tier.HEAVY: {"health": [30.0, 250.0]},
		Tier.STRUCTURE: {"health": [30.0, 500.0]},
	},
	"laser": {
		Tier.DRONE: {"damage": [50.0, 300.0], "range": [1000.0, 4000.0], "cooldown_max": [0.2, 3.0]},
		Tier.LIGHT: {"damage": [100.0, 600.0], "range": [2000.0, 6000.0], "cooldown_max": [0.2, 3.0]},
		Tier.MEDIUM: {"damage": [300.0, 1200.0], "range": [3000.0, 8000.0], "cooldown_max": [0.2, 3.0]},
		Tier.HEAVY: {"damage": [800.0, 4000.0], "range": [4000.0, 12000.0], "cooldown_max": [0.2, 3.0]},
		Tier.STRUCTURE: {"damage": [300.0, 4000.0], "range": [2000.0, 8000.0], "cooldown_max": [0.2, 3.0]},
	},
	"missile": {
		Tier.DRONE: {"range": [5000.0, 20000.0], "cooldown_max": [5.0, 30.0]},
		Tier.LIGHT: {"range": [10000.0, 30000.0], "cooldown_max": [5.0, 30.0]},
		Tier.MEDIUM: {"range": [20000.0, 40000.0], "cooldown_max": [5.0, 30.0]},
		Tier.HEAVY: {"range": [28000.0, 60000.0], "cooldown_max": [5.0, 30.0]},
		Tier.STRUCTURE: {"range": [20000.0, 60000.0], "cooldown_max": [5.0, 30.0]},
	},
	"living_quarters": {
		# M27 -- LIGHT (pinnace passenger cabin) + HEAVY (freighter crew quarters)
		# rows added so these components are banded, not band-skipped, at those
		# tiers (see design_ideas/ship_parameter_table.md M27 pre-step and
		# implementation_plans/m27_catalog_expansion_design.md). Sized off the
		# same health-per-area discipline as the existing STRUCTURE row (small
		# station: 4000 area / 4000 health = 1.0 hpa; medium station: 16000/12000
		# = 0.75 hpa) applied at each tier's own expected compartment area, kept
		# strictly narrower than STRUCTURE's ceiling (stations are the largest
		# hulls in the fleet) while wide enough not to fight authoring.
		Tier.LIGHT: {"health": [50.0, 3000.0]},
		Tier.HEAVY: {"health": [300.0, 9000.0]},
		Tier.STRUCTURE: {"health": [100.0, 10000.0]},
	},
	"cargo_bay": {
		# M27 -- same rationale/derivation as living_quarters above.
		Tier.LIGHT: {"health": [50.0, 3000.0]},
		Tier.HEAVY: {"health": [300.0, 9000.0]},
		Tier.STRUCTURE: {"health": [100.0, 10000.0]},
	},
	"life_support": {
		Tier.STRUCTURE: {"health": [100.0, 5000.0]},
	},
	"docking_port": {
		Tier.STRUCTURE: {"health": [200.0, 8000.0]},
	}
}

# ---------------------------------------------------------------------------
# 4.3 Handling bands -- max_speed / max_omega per tier.
# Note the inversion: lighter tiers are faster/nimbler.
# ---------------------------------------------------------------------------

const HANDLING_BANDS := {
	Tier.DRONE: {"max_speed": [0.0, 200.0], "max_omega": [0.0, 3.0]},
	Tier.LIGHT: {"max_speed": [1000.0, 3000.0], "max_omega": [2.0, 6.0]},
	Tier.MEDIUM: {"max_speed": [600.0, 1400.0], "max_omega": [1.2, 3.0]},
	Tier.HEAVY: {"max_speed": [300.0, 900.0], "max_omega": [0.6, 1.8]},
	Tier.STRUCTURE: {"max_speed": [0.0, 0.0], "max_omega": [0.0, 0.0]},
}
