class_name Utils

# Sensor id that gets a highlight color in tactical displays (navigation_panel,
# engineering_panel's EM chart, sensor_module_ui). Shared so all three can't
# silently drift onto different ids if the ship's sensor loadout ever changes.
const HIGHLIGHT_SENSOR_ID := "dir_high_res"

# Contact confidence-by-age. A tracked contact carries `last_seen_at` (M56: an
# absolute Engine.get_physics_frames() stamp, not an accumulated duration --
# see Ship.contact_age(); ship.gd dead-reckons its position in the meantime
# and only drops it at CONTACT_TIMEOUT = 20s). A freshly-measured contact
# and one coasting on 15s-old data are otherwise drawn identically, so stale
# dead-reckoned blips read as solid as real ones -- the core "too many ghosts"
# problem. These map age -> a 0..1 confidence so every view can dim old contacts:
# bright = just seen, faint = coasting on stale extrapolation. Age only for now
# (resolution/cross-section could fold in later); see the fusion-grade discussion.
const CONTACT_FADE_FULL := 8.0          # seconds of no detection to dim from full to the floor
const CONTACT_CONFIDENCE_FLOOR := 0.2   # dimmest a still-tracked (not yet dropped) contact gets

static func contact_confidence(contact: Dictionary) -> float:
	var age = Ship.contact_age(contact, 0.0)
	return clampf(1.0 - age / CONTACT_FADE_FULL, CONTACT_CONFIDENCE_FLOOR, 1.0)

# Scale a base color's alpha by confidence (keeps hue/value, just dims it).
static func fade_color(base: Color, confidence: float) -> Color:
	return Color(base.r, base.g, base.b, base.a * confidence)

static func format_dist(meters: float) -> String:
	if meters < 1000.0:
		return "%.0f m" % meters
	else:
		return "%.1f km" % (meters / 1000.0)

# Speed variant of format_dist -- same m/km auto-scaling (reused directly,
# not reimplemented), "/s" appended, sign handled separately since format_dist
# itself is magnitude-only (distances are never negative; speeds can be).
static func format_speed(mps: float) -> String:
	var sign := "-" if mps < 0.0 else ""
	return sign + format_dist(absf(mps)) + "/s"

# --- Contact colour: THE single source of truth -----------------------------
# Playtest A2, 2026-07-26 ("Ironhold is classified inconsistently -- enemy in
# one place, neutral in another"; the follow-up report that map and list
# disagreed). Three surfaces each had their own rule and only ONE consulted
# Standing:
#
#   contacts_panel row colour   SOS > standing > classification   CORRECT
#   navigation_panel blips      classification only               red
#   helm_panel heading dial     classification only               red
#
# classification_color below genuinely WAS shared -- it was just shared over
# the wrong axis, and structurally cannot see standing. That matters far beyond
# one station: classify_contact() returns "UNIDENTIFIED VESSEL" for any live
# vessel without an IFF crypto handshake, INCLUDING a fully identified,
# reporting, neutral one. So every neutral station and civilian in the game
# drew red on the nav map. The name is the lie -- it means "not IFF-friendly",
# not "unknown".
#
# contact_color() is the precedence contacts_panel already had right, lifted
# here so every surface inherits it. Takes the whole contact dict rather than a
# classification string precisely so it CAN see standing and sos.
#
# The three colour tables that used to live in contacts_panel.gd move here with
# it. Each of those files carried a comment explaining that the other module's
# colours were "not ours to touch" -- which is exactly how three rules drifted
# apart in the first place.
# ONE TIER RESOLUTION, TWO CONSUMERS. Colour and list-section are both derived
# from contact_tier() below, so they cannot drift apart -- a contact can never
# be filed as an enemy while being painted neutral, which is the literal
# contradiction A2 reported. Adding or changing a tier is one row here, with
# its colour and its section side by side.
#
# Same "const registry, keyed dispatch" shape the codebase already uses for
# DebugSettings.OPTIONS and PortRules.rule_summary_handlers().
#
# Tier keys are internal to this table; TIER_* consts name them so callers and
# tests never spell them as bare strings.
const TIER_SOS := "SOS"
const TIER_HOSTILE := "HOSTILE"
const TIER_CAUTION := "CAUTION"
const TIER_FRIENDLY := "FRIENDLY"
const TIER_NEUTRAL := "NEUTRAL"

# Section display order, top to bottom. The two attention-demanding sections
# sit adjacent at the top. Exported so contacts_panel builds its UI from THIS
# rather than keeping its own parallel list (the panel appends its own
# "Contracts" section, which holds contract-feed entries, not contacts).
const CONTACT_SECTIONS := ["Enemies", "Alerts", "Ships", "All Contacts"]

const _TIERS := {
	TIER_SOS:      {"color": Color(1.0, 0.25, 0.1, 0.95), "section": "Alerts"},
	TIER_HOSTILE:  {"color": Color(0.85, 0.2, 0.2),       "section": "Enemies"},
	TIER_CAUTION:  {"color": Color(0.75, 0.7, 0.25),      "section": "Alerts"},
	TIER_FRIENDLY: {"color": Color(0.2, 0.8, 0.2),        "section": "Ships"},
	TIER_NEUTRAL:  {"color": Color(0.85, 0.85, 0.85),     "section": "All Contacts"},
}

# Standing string -> tier. Standing.UNREPORTED is the yellow CAUTION tier (it
# means "cannot resolve from here" -- not reporting, OR holding a warrant, OR
# demanding our submission); see standing.gd's CAUTION alias.
const _STANDING_TIERS := {
	"HOSTILE": TIER_HOSTILE,
	"UNREPORTED": TIER_CAUTION,
	"NEUTRAL": TIER_NEUTRAL,
	"FRIENDLY": TIER_FRIENDLY,
}

# SOS beats standing. A ship in distress is more urgent than its ordinary
# relationship to you. Returns "" for a contact with no standing at all -- a
# non-vessel (ordnance, wreckage, asteroid) or one we have not judged yet --
# whose callers fall back to the classification layer.
static func contact_tier(c: Dictionary) -> String:
	if c.get("sos", false):
		return TIER_SOS
	return _STANDING_TIERS.get(c.get("standing", ""), "")

static func contact_color(c: Dictionary) -> Color:
	var tier: String = contact_tier(c)
	if tier != "":
		return _TIERS[tier]["color"]
	return classification_color(c.get("classification", ""))

# Which list section a contact files under. Non-vessels fall through to the
# classification buckets so ordnance/wreckage/asteroids behave as they always
# have. Whether INCOMING ORDNANCE deserves "Alerts" is a live question -- it is
# arguably the most urgent thing on the board -- but it sat in All Contacts
# before this change too, so leaving it is not a regression. Not decided here.
static func contact_section(c: Dictionary) -> String:
	var tier: String = contact_tier(c)
	if tier != "":
		return _TIERS[tier]["section"]
	if c.get("classification", "") == "FRIENDLY VESSEL":
		return "Ships"
	return "All Contacts"

# Classification -> color. Kept as the FALLBACK layer under contact_color()
# above (non-vessels, and anything that genuinely only has a classification
# string). Do not call this directly for a contact you hold the full dict for
# -- it cannot see standing, which is the A2 bug.
static func classification_color(classification: String) -> Color:
	match classification:
		"INCOMING ORDNANCE": return Color.YELLOW
		"UNIDENTIFIED VESSEL": return Color.RED
		"FRIENDLY VESSEL": return Color.GREEN
		"FRIENDLY ORDNANCE": return Color.DARK_GREEN
		"ASTEROID": return Color.GRAY
		# M52 -- SOS is now a real classified contact (implementation_plans/
		# m52_sos_as_contact.md item 6), riding the same generic per-contact
		# drawing path as everything else instead of navigation_panel.gd's
		# old special-case marker. Same literal that marker used to use
		# (this file doesn't import colors from navigation_panel.gd -- local
		# literal, matching the convention everywhere else in this area).
		"DISTRESS CALL": return Color(1.0, 0.25, 0.1, 0.95)
		_: return Color.WHITE

# True world-to-screen rotation offset shared by every map/compass-style
# widget (navigation_panel, helm_panel's heading dial, sensor_module_ui):
# when ship-oriented, "up" on screen is the ship's nose, so the world is
# rotated by -rot - 90deg under it; otherwise the world stays north-up.
static func get_map_rotation(is_ship_oriented: bool, rot: float) -> float:
	if is_ship_oriented:
		return -rot - PI / 2.0
	return 0.0

# Cardinal (N/E/S/W) vs. ordinal tick styling, shared by every compass-ring
# drawer (navigation_panel's compass, helm_panel's heading dial). Geometry
# (tick length/direction) differs enough between the two widgets that only
# the color/width/label lookup is factored out here.
static func compass_tick_style(degrees: int) -> Dictionary:
	var is_cardinal = (degrees % 90 == 0)
	return {
		"is_cardinal": is_cardinal,
		"color": Color.GREEN if is_cardinal else Color(0.0, 0.8, 0.0, 0.6),
		"width": 3.0 if is_cardinal else 1.0,
	}

static func compass_label_text(degrees: int) -> String:
	match degrees:
		0: return "N"
		90: return "E"
		180: return "S"
		270: return "W"
		_: return str(degrees)

# World-frame math angle (radians, 0 = +X/east, CCW-in-screen-space) -> the
# compass bearing (degrees, 0 = N, 90 = E) that matches this file's ring
# conventions above: tick i is drawn at deg_to_rad(i - 90), so a needle at
# angle `a` lines up with tick i when i = rad_to_deg(a) + 90. Always ship-
# frame-independent (map_rotation is a DISPLAY offset, not part of the
# bearing itself) -- callers add it back in only when drawing on a
# ship-oriented ring.
static func compass_bearing_deg(angle_rad: float) -> int:
	return int(round(wrapf(rad_to_deg(angle_rad) + 90.0, 0.0, 360.0))) % 360

static func is_directional_emitter(comp: Dictionary) -> bool:
	return comp.get("type", "") == "sensors" or comp.get("type", "") == "weapons"

static func get_directional_em_power(comp: Dictionary, target_rotation: float, angle_from_target: float) -> float:
	var em_emission = comp.get("em_emission", 0.0)
	if em_emission <= 0.0:
		return 0.0
	if not is_directional_emitter(comp):
		var relative_angle = angle_from_target - target_rotation
		var rear_bias = 1.0 + 0.5 * max(0.0, cos(relative_angle + PI))
		return em_emission * rear_bias
	var comp_heading = target_rotation + comp.get("heading", 0.0)
	var arc = comp.get("arc_width", TAU)
	var diff = abs(wrapf(angle_from_target - comp_heading, -PI, PI))
	if diff > arc / 2.0:
		return 0.0
	return em_emission * (1.0 - diff / (arc / 2.0))

static func get_directional_em(sig: Dictionary, angle_from_target: float) -> float:
	var target_rotation = sig.get("rot", 0.0)
	var total = 0.0
	for comp in sig.get("em_emitters", []):
		total += get_directional_em_power(comp, target_rotation, angle_from_target)
	return total
