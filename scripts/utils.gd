class_name Utils

# Sensor id that gets a highlight color in tactical displays (navigation_panel,
# engineering_panel's EM chart, sensor_module_ui). Shared so all three can't
# silently drift onto different ids if the ship's sensor loadout ever changes.
const HIGHLIGHT_SENSOR_ID := "dir_high_res"

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
