extends "res://scripts/ships/ship.gd"
class_name AsteroidStation

# M27 -- STRUCTURE-tier asteroid station. Cluster archetype (irregular
# dense-rect blob, modules embedded inside the rock --
# design_ideas/hull_shape_grammar.md §2): six rock columns of DIFFERENT
# heights running left-to-right (spine 40 tall, then 70, 90, 100, 80, 50 --
# the "stepped/blobby" silhouette, deliberately not a neat rectangle), each
# of the five right-hand columns split top/bottom to sandwich exactly one
# functional module in its middle band. The module sits flush between its
# own column's top/bottom rock (covered above/below) and touches its
# neighboring columns' rock at the shared X seam (covered left/right) -- so
# every module reads as embedded IN the rock, not bolted to its surface.
#
# THE SIGNATURE MODEL (read scripts/ships/ship.gd's classify_contact + M27's
# ship_parameter_table.md signature-axis section before touching any number
# below):
#   - Ship.density (the flat per-ship var, NOT the per-component "density"
#     field on each hull dict) is what get_signature() reports and what
#     classify_contact actually keys on. Component-level "density" only
#     drives get_ship_mass()/damage-soak. So the rock-shell posture requires
#     BOTH: (a) density = 300.0 on THIS class (past ASTEROID_DENSITY_THRESHOLD
#     250.0) so the SHIP-LEVEL signature reads dense, AND (b) rock hull
#     component dicts also authored at density >= 300 (mass/armor to match --
#     see the file-header exemption note below) even though the validator
#     never checks a component's density against a band.
#   - classify_contact's activity gate is EM alone (em_noise > 5.0 -> treated
#     as powered, regardless of heat). em_signature is the sum of reactor
#     power_rating (only while powered_on), active-sensor base_em_emission
#     (only while powered_on), weapon base_em_emission (fleet convention: 0
#     for PD lasers regardless of power state), and a flat 0.5/component
#     passive leak for every OTHER powered, non-hull component. So the
#     "cold and dark" posture is simply: reactor, sensors, and PD lasers all
#     start powered_on = false. With every non-hull component off, em_noise
#     is exactly 0.0 <= ACTIVE_EM_THRESHOLD (5.0), cross_section (from the
#     hull's overall AABB) comfortably clears ASTEROID_CS_THRESHOLD (50.0)
#     given this hull's ~140x100 footprint, and density (300) clears
#     ASTEROID_DENSITY_THRESHOLD (250) -- classify_contact's exact branch:
#       em <= 5.0 AND density > 250.0 AND cross_section > 50.0 -> "ASTEROID"
#   - "Waking up" the station (see WAKE_COMPONENT_IDS below) flips
#     powered_on = true on the reactor + active sensors + PD lasers. The
#     reactor alone pushes em_signature to its power_rating (1500, per the
#     parameter-table target row), which is enormously past the 5.0
#     threshold -- classify_contact's first branch fires instead
#     ("UNIDENTIFIED VESSEL"/"FRIENDLY VESSEL" depending on observer IFF),
#     and density/cross_section stop mattering at all (they're only read in
#     the em <= threshold branch). No AI, no scripted behavior change is
#     needed for this flip -- it is a pure consequence of the same
#     classify_contact the rest of the fleet already runs through.
#
# WAKE-UP CONVENTION: flip `powered_on = true` on these component ids to
# bring the station to full alert (reverse to return to cold-and-dark). No
# AI/behavior-tree wiring -- this is a data flag toggle only, same mechanism
# any switchable component already exposes (see Ship.is_component_powered).
const WAKE_COMPONENT_IDS := [
	"reactor_core",
	"sensor_search", "sensor_pd",
	"pd_north", "pd_south",
]

# Targets (design_ideas/ship_parameter_table.md M27 pre-step row): mass
# ~4000+ (density >= 300 rock shell -- NOT back-solvable from the fleet's
# usual density-20 area*0.036 shortcut, see that doc's note), STRUCTURE tier
# (immobile), reactor power_rating ~1500, PD + a search dish + a fast/fine PD
# sensor, sensors + PD OFF by default (cold posture), comms 90k range /
# transponder off by default (per the plan's "beacon/transponder OFF by
# default" decision -- see get_active_transponder_data()'s
# transponder_active gate).
#
# static func design() + thin _init() per fleet convention.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

# ---------------------------------------------------------------------------
# HULL-MARK DENSITY EXEMPTION (per M27 plan item 7): every rock hull dict
# below is authored at density 300.0 -- far past Parts.HULL_DENSITY's HEAVY
# mark ceiling of 35.0. This is the one sanctioned exception in the whole
# fleet: hull marks (civilian/standard/armored) exist to grade ARMOR, but
# this shell's entire purpose is to clear classify_contact's
# ASTEROID_DENSITY_THRESHOLD (250.0) so a cold hull reads as rock, which no
# armor mark comes close to. Per the plan, this does NOT get a new
# Parts.HULL_DENSITY mark/catalog entry -- it is a one-off, ship-local
# density used only here and documented here, not a new sanctioned catalog
# point other ships should reach for.
# ---------------------------------------------------------------------------
const ROCK_DENSITY := 300.0

static func _rock(comp_id: String, rect: Rect2, hp: float) -> Dictionary:
	return {"id": comp_id, "type": "hull", "rect": rect, "health": hp, "max_health": hp, "density": ROCK_DENSITY, "heat": 0.0, "em_emission": 0.0, "switchable": false}

# ---------------------------------------------------------------------------
# Grammar friction notes (per M27 plan -- report every place the grammar
# couldn't express something):
#  - HullBuilder has no "irregular blob" shape -- frame()/taper()/arm()/
#    zipper() all assume a regular, symmetric envelope. The cluster's
#    stepped-column silhouette (six columns of six DIFFERENT heights) is
#    authored as raw hull rects, same as small_station.gd's arms; this is a
#    real, expected gap for this one archetype (the design doc calls the
#    shape "irregular dense-rect blob" specifically because it's NOT meant
#    to reduce to a builder idiom).
#  - Each module-sandwiching column (reactor/cargo_bay/living_quarters/
#    comms+sensor/rcs+sensor) IS the same "wall carries more than one
#    component" gap defence_pod.gd already flagged for frame()'s single-rect-
#    per-side walls -- same root cause, same workaround (hand-split sub-rects
#    that reproduce the intended band geometry).
#  - cargo_bay/living_quarters have no Parts family (same gap freighter.gd
#    already flagged) -- raw dicts, STRUCTURE band [100,10000] per
#    component_spec.gd.
# ---------------------------------------------------------------------------

static func design() -> Array:
	var comps: Array = []

	# --- COLUMN A: x -70..-50, y -20..20 (h40) -- pure rock, no module ------
	comps.append(_rock("rock_a", Rect2(-70, -20, 20, 40), 8000.0))

	# --- COLUMN B: x -50..-30, y -35..35 (h70) -- reactor sandwich ----------
	comps.append(_rock("rock_b_top", Rect2(-50, -35, 20, 27), 5000.0))
	comps.append(_rock("rock_b_bot", Rect2(-50, 8, 20, 27), 5000.0))
	comps.append(Parts.make("reactor", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(-49, -8), {"id": "reactor_core"}))
	comps.append(_rock("rock_b_mid", Rect2(-33, -8, 3, 16), 1440.0))

	# --- COLUMN C: x -30..-5, y -45..45 (h90) -- cargo_bay sandwich ---------
	comps.append(_rock("rock_c_top", Rect2(-30, -45, 25, 30), 9000.0))
	comps.append(_rock("rock_c_bot", Rect2(-30, 15, 25, 30), 9000.0))
	comps.append({"id": "cargo_bay_main", "type": "cargo_bay", "rect": Rect2(-30, -15, 25, 30), "health": 750.0, "max_health": 750.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	# --- COLUMN D: x -5..25, y -50..50 (h100) -- CORE column, tallest ------
	# living_quarters sandwich -- the widest/tallest module, at the cluster's
	# structural center (per the archetype: modules embedded inside the rock,
	# and the biggest one sits where the rock is tallest).
	comps.append(_rock("rock_d_top", Rect2(-5, -50, 30, 41), 12300.0))
	comps.append(_rock("rock_d_bot", Rect2(-5, 9, 30, 41), 12300.0))
	comps.append({"id": "living_quarters_main", "type": "living_quarters", "rect": Rect2(-5, -9, 30, 18), "health": 900.0, "max_health": 900.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	# --- COLUMN E: x 25..50, y -40..40 (h80) -- comms + search-sensor -------
	comps.append(_rock("rock_e_top", Rect2(25, -40, 25, 31), 7750.0))
	comps.append(_rock("rock_e_bot", Rect2(25, 9, 25, 31), 7750.0))
	comps.append(Parts.make("comms", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(25, -4), {"id": "comms_main", "transponder_active": false}))
	comps.append(Parts.make("sensor", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(33, -4.5), {"id": "sensor_search", "sensor_kind": "omni_search"}))
	comps.append(_rock("rock_e_mid_l", Rect2(33, -9, 9, 4.5), 810.0))
	comps.append(_rock("rock_e_mid_r", Rect2(33, 4.5, 9, 4.5), 810.0))
	comps.append(_rock("rock_e_mid_far", Rect2(42, -9, 8, 18), 2880.0))

	# --- COLUMN F: x 50..70, y -25..25 (h50) -- rcs + PD-tracking sensor ----
	comps.append(_rock("rock_f_top", Rect2(50, -25, 20, 17), 3400.0))
	comps.append(_rock("rock_f_bot", Rect2(50, 8, 20, 17), 3400.0))
	comps.append(Parts.make("rcs", ComponentSpec.Tier.STRUCTURE, Parts.Mark.STANDARD,
		Vector2(50, -4), {"id": "rcs_main"}))
	# Fast/fine PD-tracking sensor (stations' omni_short_pd pattern -- fast
	# refresh + fine bins so the two PD lasers below have a firing solution
	# once awake; ship_design_validator.gd's PD-coherence check). Raw dict
	# (same convention as defence_pod.gd's sensor_pd) since the catalog's
	# omni_pd sub-kind range_mult doesn't need to be reached for here.
	comps.append({"id": "sensor_pd", "type": "sensors", "rect": Rect2(58, -4, 8, 8), "health": 400.0, "max_health": 400.0, "density": 20.0, "heat": 0.0, "base_em_emission": 5.0, "em_emission": 5.0, "switchable": true, "powered_on": false,
		"sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 1800, "refresh_interval": 0.15, "timer": 0.0, "heading": 0.0})
	comps.append(_rock("rock_f_mid", Rect2(66, -4, 4, 8), 480.0))

	# --- DEFENSIVE PD: "almost certainly armed" per the design doc ---------
	# Two PD lasers (STRUCTURE HEAVY mark, 8x12) mounted flush against the
	# core column's N/S rock faces (rock_d_top's top edge is y=-50; rock_d_bot's
	# bottom edge is y=50) -- oriented outward, same turret-on-hull idiom as
	# small_station/medium_station/defence_pod. No separate mount rect needed:
	# the laser's own 12-tall footprint sits pos=(5,-62)..(13,-50), touching
	# rock_d_top's (−5,−50,30,41) top edge exactly at y=-50 (touching, not
	# overlapping -- the validator's overlap check excludes touching edges).
	# base_em_emission left at the family default (0.0, fleet convention for
	# lasers) so an idle-but-powered PD turret contributes no EM by itself;
	# only the reactor coming on is what flips the signature.
	comps.append(Parts.make("laser", ComponentSpec.Tier.STRUCTURE, Parts.Mark.HEAVY,
		Vector2(5, -62), {"id": "pd_north", "heading": -PI / 2.0, "arc_width": PI / 2.0}))

	comps.append(Parts.make("laser", ComponentSpec.Tier.STRUCTURE, Parts.Mark.HEAVY,
		Vector2(5, 50), {"id": "pd_south", "heading": PI / 2.0, "arc_width": PI / 2.0}))

	# --- RCS: station-keeping only (STRUCTURE forbids engines) --------------
	# rcs_main above (column F) already satisfies the validator's STRUCTURE
	# rcs requirement; no second rcs needed.

	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	max_speed = 0.0
	max_omega = 0.0
	max_heat = 300.0
	# Ship-level signature density (see file header) -- NOT the per-component
	# hull density field above; get_signature()/classify_contact reads THIS
	# var. Past ASTEROID_DENSITY_THRESHOLD (250.0) so a cold-and-dark station
	# reads as rock.
	density = ROCK_DENSITY
	ship_components = design()
	super()
	ship_name = "Rockhold Station"

	# Cold-and-dark default posture: reactor, active sensors, and PD lasers
	# start powered OFF (still switchable -- see WAKE_COMPONENT_IDS above).
	# comms/rcs/hull stay on (comms' own transponder_active=false already
	# keeps it silent to the datalink layer; rcs draws no EM on its own and
	# station-keeping should not require "waking up" the rock).
	for c in ship_components:
		if WAKE_COMPONENT_IDS.has(c.get("id", "")):
			c["powered_on"] = false

# One berth on the aft (-X) face, clear of the hull's own bounding radius --
# same offset convention as small_station.gd (a station-class berth needs to
# sit outside the collision circle so force-capture doesn't fight physics).
func get_berths() -> Array:
	return [{"pos": Vector2(-90, 0), "heading": PI}]
