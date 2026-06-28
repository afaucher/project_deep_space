class_name Utils

# Sensor id that gets a highlight color in tactical displays (navigation_panel,
# engineering_panel's EM chart, sensor_module_ui). Shared so all three can't
# silently drift onto different ids if the ship's sensor loadout ever changes.
const HIGHLIGHT_SENSOR_ID := "dir_high_res"

# Contact confidence-by-age. A tracked contact carries `last_seen_timer` (seconds
# since the last *real* sensor detection; ship.gd dead-reckons its position in the
# meantime and only drops it at CONTACT_TIMEOUT = 20s). A freshly-measured contact
# and one coasting on 15s-old data are otherwise drawn identically, so stale
# dead-reckoned blips read as solid as real ones -- the core "too many ghosts"
# problem. These map age -> a 0..1 confidence so every view can dim old contacts:
# bright = just seen, faint = coasting on stale extrapolation. Age only for now
# (resolution/cross-section could fold in later); see the fusion-grade discussion.
const CONTACT_FADE_FULL := 8.0          # seconds of no detection to dim from full to the floor
const CONTACT_CONFIDENCE_FLOOR := 0.2   # dimmest a still-tracked (not yet dropped) contact gets

static func contact_confidence(contact: Dictionary) -> float:
	var age = contact.get("last_seen_timer", 0.0)
	return clampf(1.0 - age / CONTACT_FADE_FULL, CONTACT_CONFIDENCE_FLOOR, 1.0)

# Scale a base color's alpha by confidence (keeps hue/value, just dims it).
static func fade_color(base: Color, confidence: float) -> Color:
	return Color(base.r, base.g, base.b, base.a * confidence)

static func format_dist(meters: float) -> String:
	if meters < 1000.0:
		return "%.0f m" % meters
	else:
		return "%.1f km" % (meters / 1000.0)

# Single source of truth for contact classification -> color, used by
# navigation_panel (blips, off-screen indicators) and sensor_panel (contact
# list border/font color) so the two views can't disagree about what a
# given classification looks like.
static func classification_color(classification: String) -> Color:
	match classification:
		"INCOMING ORDNANCE": return Color.YELLOW
		"UNIDENTIFIED VESSEL": return Color.RED
		"FRIENDLY VESSEL": return Color.GREEN
		"FRIENDLY ORDNANCE": return Color.DARK_GREEN
		"ASTEROID": return Color.GRAY
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
