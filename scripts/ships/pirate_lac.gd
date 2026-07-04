extends "res://scripts/ships/ship.gd"
class_name PirateLAC

# M24 -- delta variant: pirate-refit Light Attack Craft. Faster, more
# fragile, meaner. See implementation_plans/m24_delta_variants_design.md and
# design_ideas/hull_shape_grammar.md §5.
#
# Extends ship.gd DIRECTLY (not LightAttackCraft) and preloads the base for
# design() -- GDScript parent _init ordering makes subclass mutation of an
# already-built ship_components array fragile, so variants compose the base's
# design() array via Variants.apply() instead of inheriting _init(). See
# ship_variants.gd file header.
#
# Engine upgrade note (plan's open question, resolved here): the plan
# describes swapping "engine_main" to engine/LIGHT/HEAVY mark. The catalog's
# engine/LIGHT/HEAVY rect is 12x14; the LAC's engine_main slot is a 10x10
# same-rect footprint -- a same-size swap is impossible (Variants.apply's swap
# op is a hard error on any size mismatch, by design, to keep STATS_ONLY
# geometry-safe). Rather than resize the slot (that would be a GEOMETRY
# change disguised as a stats swap), this variant instead TUNEs engine_main's
# thrust_rating/torque_rating up to the engine/LIGHT/HEAVY mark's own catalog
# values (6500.0 / 13000.0, vs the base's 2500.0 / 5000.0) in place. Same
# rect, same footprint, strictly more powerful engine -- an honest "same box,
# hotter reactor tap" reading, and it keeps the delta classified STATS_ONLY
# for everything except the plate removal below.
#
# Deltas:
#  - tune engine_main thrust_rating/torque_rating up to the HEAVY mark's
#    values (see note above) -- ship ends up strictly faster (test item 6).
#  - remove hull_fwd_port (GEOMETRY -- one hull plate stripped for speed;
#    connectivity confirmed to survive since hp_fwd_laser/omni_fwd_fc stay
#    edge-adjacent to hull_fill_port; the removal surfaces as a hull_coverage
#    warning, frozen in test_ship_designs.gd's EXPECTED_LAYOUT_WARNINGS).
#  - tune hp_fwd_laser cooldown_max down to 0.6 (faster trigger).

const Variants = preload("res://scripts/components/ship_variants.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")
const PartsComponentSpec = preload("res://scripts/components/component_spec.gd")

# engine/LIGHT/HEAVY mark's thrust/torque, looked up once here so the tune
# values aren't a second hand-copy of the catalog numbers (if the catalog's
# HEAVY mark ever moves, this variant tracks it instead of silently going
# stale). Vector2.ZERO position -- only the stat fields are used.
static func _heavy_engine_stats() -> Dictionary:
	return Parts.make("engine", PartsComponentSpec.Tier.LIGHT, Parts.Mark.HEAVY, Vector2.ZERO, {"id": "_scratch"})

static func design() -> Array:
	var heavy_engine := _heavy_engine_stats()
	return Variants.apply(LightAttackCraft.design(), [
		{"tune": "engine_main", "field": "thrust_rating", "value": heavy_engine["thrust_rating"]},
		{"tune": "engine_main", "field": "torque_rating", "value": heavy_engine["torque_rating"]},
		{"remove": "hull_fwd_port"},
		{"tune": "hp_fwd_laser", "field": "cooldown_max", "value": 0.6},
	])

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	ship_name = "Pirate LAC"
	max_speed = 2600.0   # LIGHT band [1000, 3000] -- pushed up from base's 2200
	max_omega = 5.0      # LIGHT band [2.0, 6.0] -- pushed up from base's 4.5
	max_heat = 130.0
	ship_components = design()
	super()
