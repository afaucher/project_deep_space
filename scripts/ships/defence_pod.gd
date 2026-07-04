extends "res://scripts/ships/ship.gd"
class_name DefencePod

# M27 -- STRUCTURE-tier system defence pod. Ring / hollow-square-annulus
# silhouette (the "ring" archetype -- design_ideas/hull_shape_grammar.md §2):
# HullBuilder.frame() IS this shape, used twice at two radii -- an outer hull
# shell and, one band further in, a "module ring" of functional compartments
# (crew, cargo, reactor, sensors, comms) embedded in the same annulus idiom.
# The true center (the ring's hole) stays completely empty -- that's the
# archetype: an all-around PD emplacement with a dockable hole, not a filled
# disc.
#
# Targets (design_ideas/ship_parameter_table.md M27 pre-step row): mass ~900,
# STRUCTURE tier (immobile: max_speed/max_omega both 0 by construction), heavy
# PD lasers + missile tubes covering all four quadrants, small crew pod (2-4,
# ~100-160 area per the plan's "grounded" crew concession) + small cargo bay,
# rcs for station keeping, NO engines (STRUCTURE rule -- see
# ship_design_validator.gd rule 6), fast/fine PD sensor(s) (stations'
# omni_short_pd pattern) plus a strategic search dish.
#
# static func design() + thin _init() per fleet convention.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

# ---------------------------------------------------------------------------
# Grammar friction notes (per M27 plan -- report every place the grammar
# couldn't express something):
#  - frame() expressed the ring cleanly and TWICE over -- the outer hull shell
#    is literally `HullBuilder.frame(outer_rect, thickness, hp)` with nothing
#    else needed, and the module ring one band in is the SAME call at a
#    smaller rect/different thickness, just with its 4 wall segments
#    subdivided into functional cells afterward instead of staying plain hull.
#    This is the cleanest archetype-to-builder match of the whole M27 batch --
#    frame() was designed for exactly this shape.
#  - frame()'s wall segments are single rects per side, so once a wall needs
#    to carry more than one component (living_quarters + cargo_bay share the
#    "top" band, reactor + rcs share "bottom", etc.) the frame() output isn't
#    used directly for those two walls -- their footprint is authored as
#    hand-split sub-rects that reproduce frame()'s own wall geometry (same
#    thickness, same span) rather than calling frame() and further splitting
#    its output. A hypothetical "frame_with_slots(rect, thickness, hp,
#    slots_per_side)" would close this gap, same shape of gap as
#    hull_shape_grammar.md's noted taper/pinnace friction ("taper_with_slots").
#    The left/right module bands (comms+sensor, PD-sensor+passive) didn't need
#    this -- two same-shaped cells split a wall evenly with no further
#    reshaping, so those two came straight off frame()'s wall rects.
#  - Weapons (heavy PD lasers + missile tubes) are NOT a HullBuilder shape --
#    Parts.make() sizes them correctly for STRUCTURE tier, but their placement
#    (flush against each of the 4 outer-ring faces, oriented outward) is
#    per-ship arithmetic, same as every other ship's turret placement
#    (small_station, medium_station).
# ---------------------------------------------------------------------------

# Outer hull ring geometry -- frame(Rect2(-80,-80,160,160), 15, hp). Inner
# edge of this shell sits at |x|,|y| = 65.
const OUTER_RECT := Rect2(-80.0, -80.0, 160.0, 160.0)
const OUTER_THICKNESS := 15.0
const OUTER_HP := 5000.0

# Module ring geometry -- frame(Rect2(-65,-65,130,130), 30, hp). Inner edge of
# THIS band sits at |x|,|y| = 35 -- everything inside that (the 70x70 center
# square) is the ring's hole, left completely empty per the archetype.
const MODULE_RECT := Rect2(-65.0, -65.0, 130.0, 130.0)
const MODULE_THICKNESS := 30.0
const MODULE_HP := 3000.0

static func _hull(comp_id: String, rect: Rect2, hp: float) -> Dictionary:
	return {"id": comp_id, "type": "hull", "rect": rect, "health": hp, "max_health": hp, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}

static func design() -> Array:
	var comps: Array = []

	# --- OUTER HULL RING: frame() directly, no further splitting ----------
	comps.append_array(HullBuilder.frame(OUTER_RECT, OUTER_THICKNESS, OUTER_HP, {"id_prefix": "hull_outer"}))

	# --- MODULE RING: top/bottom walls carry 2 functional cells each -------
	# (living_quarters+cargo_bay / reactor+rcs), authored as sub-rects that
	# reproduce frame()'s own top/bottom wall span+thickness -- see friction
	# note above (frame() itself isn't called for these two walls since its
	# single-rect-per-side output can't be split post-hoc without re-deriving
	# the same geometry frame() would have produced anyway).
	#
	# Top wall span: x -65..65, y -65..-35 (width 130, height 30 == MODULE_THICKNESS).
	# Small crew pod (grounded: crew of 3, AREA_PER_PERSON=40 -> 120 area,
	# inside the plan's "~100-160" concession) + small stores bay, then hull
	# filling the rest of the top band so the wall's full span stays covered.
	comps.append(_hull("hull_top_a", Rect2(-65, -65, 53, 30), MODULE_HP * (53.0 * 30.0) / (130.0 * 30.0)))
	comps.append({"id": "living_quarters_main", "type": "living_quarters", "rect": Rect2(-12, -65, 12, 10), "health": 120.0, "max_health": 120.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})
	comps.append({"id": "cargo_bay_main", "type": "cargo_bay", "rect": Rect2(0, -65, 15, 10), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})
	comps.append(_hull("hull_top_b", Rect2(15, -65, 50, 30), MODULE_HP * (50.0 * 30.0) / (130.0 * 30.0)))
	comps.append(_hull("hull_top_mid", Rect2(-12, -55, 27, 20), MODULE_HP * (27.0 * 20.0) / (130.0 * 30.0)))

	# Bottom wall span: x -65..65, y 35..65. Reactor (STRUCTURE STANDARD mark,
	# 16x16, power_rating 1500 -- matches the plan's target row exactly) +
	# RCS (STRUCTURE STANDARD mark, 8x8, station keeping -- STRUCTURE requires
	# rcs and forbids engines per the validator's rule 6), both at their
	# native catalog footprint (Parts.make's "size" opt is hull-family-only --
	# every other family's rect is fixed by its mark row, see file header
	# friction notes), hull filling the remainder of the wall's span.
	comps.append(Parts.make("reactor", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(-65, 35), {"id": "reactor_main"}))
	comps.append(_hull("hull_bottom_a", Rect2(-65, 51, 16, 14), MODULE_HP * (16.0 * 14.0) / (130.0 * 30.0)))
	comps.append(Parts.make("rcs", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(-49, 35), {"id": "rcs_main"}))
	comps.append(_hull("hull_bottom_b", Rect2(-49, 43, 8, 22), MODULE_HP * (8.0 * 22.0) / (130.0 * 30.0)))
	comps.append(_hull("hull_bottom_c", Rect2(-41, 35, 106, 30), MODULE_HP * (106.0 * 30.0) / (130.0 * 30.0)))

	# Left wall span: x -65..-35, y -35..35 (width 30 == MODULE_THICKNESS,
	# height 70 -- frame()'s left/right walls are inset by MODULE_THICKNESS
	# top/bottom, unlike the full-width top/bottom walls) -- comms (strategic,
	# long-range, STRUCTURE STANDARD mark, 8x8 native) + omni search dish
	# (raw dict, sized to fill the rest of the wall's height), hull bridging
	# the gap between comms' narrow footprint and the wall's full 30-width.
	comps.append(Parts.make("comms", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(-65, -35), {"id": "comms_main"}))
	comps.append(_hull("hull_left_a", Rect2(-57, -35, 22, 8), MODULE_HP * (22.0 * 8.0) / (130.0 * 30.0)))
	comps.append({"id": "sensor_omni", "type": "sensors", "rect": Rect2(-65, -27, 30, 62), "health": 400.0, "max_health": 400.0, "density": 20.0, "heat": 0.0, "base_em_emission": 6.0, "em_emission": 6.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 30000.0, "arc_width": TAU, "num_bins": 72, "refresh_interval": 1.0, "timer": 0.0, "heading": 0.0})

	# Right wall span: x 35..65, y -35..35 -- the fast/fine PD-tracking sensor
	# (stations' omni_short_pd pattern: fast refresh + fine bins so the 8
	# turrets below have a firing solution -- ship_design_validator.gd's
	# PD-coherence check; raw dict, sized to fill most of the wall) + a
	# passive EM ear (STRUCTURE STANDARD mark, 9x9 native), hull filling the
	# remainder. num_bins/refresh matched to (a notch finer than) the
	# frigate's own dedicated PD dish (omni_short_hi_res: 3600 bins/0.1s) --
	# this is a purpose-built defence platform, not a civilian outpost's
	# afterthought PD (small/medium_station's coarser 720-bin/0.25s dish), so
	# it earns the fleet's sharpest firing solution.
	comps.append({"id": "sensor_pd", "type": "sensors", "rect": Rect2(35, -35, 30, 55), "health": 400.0, "max_health": 400.0, "density": 20.0, "heat": 0.0, "base_em_emission": 5.0, "em_emission": 5.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 6000.0, "arc_width": TAU, "num_bins": 3600, "refresh_interval": 0.08, "timer": 0.0, "heading": 0.0})
	comps.append(Parts.make("sensor", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(35, 20), {"id": "sensor_passive", "sensor_kind": "passive_em"}))
	comps.append(_hull("hull_right_fill", Rect2(44, 20, 21, 15), MODULE_HP * (21.0 * 15.0) / (130.0 * 30.0)))

	# --- WEAPONS: heavy PD laser + missile tube on all 4 outer faces -------
	# STRUCTURE HEAVY laser mark (8x12, 3200 dmg/7000 range) + STRUCTURE
	# STANDARD missile mark (8x18, 35000 range) -- one pair per cardinal face,
	# flush against the outer ring, heading outward so the active-surface
	# check's ray reaches the true hull edge with nothing beyond it.
	comps.append(Parts.make("laser", ComponentSpec.Tier.STRUCTURE, Parts.Mark.HEAVY,
		Vector2(80, -15), {"id": "pd_fwd", "heading": 0.0, "arc_width": PI / 2.0}))
	comps.append(Parts.make("missile", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(80, -3), {"id": "missile_fwd", "heading": 0.0, "arc_width": PI / 2.0}))

	comps.append(Parts.make("laser", ComponentSpec.Tier.STRUCTURE, Parts.Mark.HEAVY,
		Vector2(-88, -15), {"id": "pd_aft", "heading": PI, "arc_width": PI / 2.0}))
	comps.append(Parts.make("missile", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(-88, -3), {"id": "missile_aft", "heading": PI, "arc_width": PI / 2.0}))

	# +Y (stbd) and -Y (port) faces need the laser/missile footprints
	# transposed (12x8 / 18x8 instead of 8x12 / 8x18) since they face along Y
	# -- raw-dict authored (Parts.make always emits the mark's native w-by-h
	# orientation; there is no rotate opt for weapon footprints), same
	# dmg/range/cooldown numbers as the fwd/aft pair copied verbatim.
	comps.append({"id": "pd_stbd", "type": "weapons", "weapon_type": "laser", "rect": Rect2(-15, 80, 12, 8), "health": 55.0, "max_health": 55.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"damage": 3200.0, "range": 7000.0, "cooldown_max": 0.6, "heading": PI / 2.0, "arc_width": PI / 2.0})
	comps.append({"id": "missile_stbd", "type": "weapons", "weapon_type": "missile", "rect": Rect2(-3, 80, 18, 8), "health": 79.2, "max_health": 79.2, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"ammo": 10, "range": 35000.0, "cooldown_max": 5.0, "heading": PI / 2.0, "arc_width": PI / 2.0})

	comps.append({"id": "pd_port", "type": "weapons", "weapon_type": "laser", "rect": Rect2(-15, -88, 12, 8), "health": 55.0, "max_health": 55.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"damage": 3200.0, "range": 7000.0, "cooldown_max": 0.6, "heading": -PI / 2.0, "arc_width": PI / 2.0})
	comps.append({"id": "missile_port", "type": "weapons", "weapon_type": "missile", "rect": Rect2(-3, -88, 18, 8), "health": 79.2, "max_health": 79.2, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"ammo": 10, "range": 35000.0, "cooldown_max": 5.0, "heading": -PI / 2.0, "arc_width": PI / 2.0})

	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	max_speed = 0.0
	max_omega = 0.0
	max_heat = 260.0
	ship_components = design()
	super()
	ship_name = "Defence Pod"

# One berth in the ring's hole -- the archetype's "hole is the dock" flavor.
# Local origin, no offset needed the way outboard hulls need (the hole is
# already clear of the ring's own collision footprint at this radius).
func get_berths() -> Array:
	return [{"pos": Vector2(0, 0), "heading": 0.0}]
