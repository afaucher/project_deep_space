extends Label

# M13b/M13c -- the persistent one-liner from m13_playable_sandbox_design.md:
#
#   "Persistent one-liner outside the overlay (e.g. 'F1: Controls, click a
#    contact, Space to fire') so a player who never opens F1 still gets the
#    core loop."
#
# The bottom bar already carried a static "F1  Controls" nudge, which tells a
# cold player that help EXISTS but not what to do. This makes the same line
# state-aware, so it names the next step of the core loop rather than the whole
# loop at once: fly -> find something -> target it -> fire.
#
# WHY A PURE FUNCTION: hint_for() takes a plain state Dictionary and returns a
# String, with no node access at all, so the whole rule table is verifiable
# headlessly (test_hint_bar) instead of needing a human to fly the game and
# watch a label. The Label half of this file is a thin shell around it.
#
# Every binding named below comes from help_overlay.gd's ROWS table -- the
# single place bindings are already written down -- so this cannot drift into
# advertising a key that does not exist.

const UIStyle = preload("res://scripts/ui/ui_style.gd")

# Always shown, so the F1 affordance never disappears behind a contextual tip.
const PREFIX := "F1  Controls"
const SEP := "   ·   "

# Priority order is the order of the checks in hint_for(); this table only holds
# the text, so adding a state is one entry plus one branch.
const HINTS := {
	# No ship yet (menu, or the moment before one spawns). Nothing to teach.
	"no_ship": "",
	# Flying, nothing on sensors: movement is the only thing that can help.
	"no_contacts": "W/S throttle   A/D steer",
	# Something is out there but not selected -- the step players miss most.
	"no_target": "Contact on sensors   ·   Q/E to target",
	# Selected: the payoff.
	"has_target": "Target selected   ·   Space to fire",
}

# A quiet line at the bottom edge of a console this dense is invisible --
# confirmed by playtest: all four states fired correctly and the player could
# not tell anything had changed. So the hint HIGHLIGHTS for a moment whenever it
# changes, putting attention exactly where the new instruction is. Same idea as
# the zone banner, at a fraction of the intrusion: no layout moves, no modal,
# and it settles back to the quiet resting line on its own.
#
# WHAT FLASHES IS THE BACKGROUND. Brightening the glyphs alone was tried first
# and playtested as too weak -- text on a dark console barely reads as
# "changed", whereas a filled block behind it is unmissable in peripheral
# vision, which is the whole job. (The glyphs do invert for the duration, but
# only so they stay legible on top of the fill -- see PULSE_FG.)
#
# The fill is AMBER, and brighter than any resting panel accent. Playtested through two
# duller options first: the modal blue (UIStyle.ACCENT_MODAL) read as more
# console rather than as an alert. Green was the other candidate and is worse
# here -- ACCENT_NAV/CONTACTS/HELM/SENSORS are all the same 0.3/0.7/0.3 green,
# so a green flash blends into four panels' worth of existing chrome. Amber is
# spoken only by engineering, and it means ATTENTION without claiming DANGER,
# which is what red (ACCENT_WEAPONS) is reserved for.
const PULSE_SECONDS := 1.4
const PULSE_BG := Color(1.0, 0.78, 0.15, 0.85)
# Glyphs go dark for the flash only. The resting line is light-on-dark, which
# inverts to unreadable the moment a bright fill lands behind it -- the point is
# to make the instruction easier to read at the exact moment it changes, so the
# text has to survive its own highlight. Fades back in step with the background.
const PULSE_FG := Color(0.05, 0.05, 0.08)
const REST_FG := Color(0.6, 0.8, 1.0)

var _version_suffix: String = ""
var _last_text: String = ""
var _pulse_tween: Tween = null
var _bg: StyleBoxFlat = null

# Pure: state -> line. Keys are all optional; anything missing reads as absent,
# so a caller that cannot answer a question never produces a wrong hint.
static func hint_for(state: Dictionary) -> String:
	var body := ""
	if not state.get("has_ship", false):
		body = HINTS["no_ship"]
	elif state.get("has_selection", false):
		body = HINTS["has_target"]
	elif int(state.get("contact_count", 0)) > 0:
		body = HINTS["no_target"]
	else:
		body = HINTS["no_contacts"]

	if body == "":
		return PREFIX
	return PREFIX + SEP + body

func _ready() -> void:
	add_theme_color_override("font_color", REST_FG)
	# FONT_TITLE, not FONT_BODY: this is the one line a brand-new player is meant
	# to read, so it sits a step above surrounding readouts in the hierarchy.
	add_theme_font_size_override("font_size", UIStyle.FONT_TITLE)
	# Label draws a "normal" stylebox behind its text -- start fully transparent
	# so the resting state is exactly the old bare line, and animate this box's
	# bg_color for the flash. Padding so the fill is a block, not a tight outline.
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(PULSE_BG.r, PULSE_BG.g, PULSE_BG.b, 0.0)
	_bg.set_content_margin_all(UIStyle.FRAME_PAD_V)
	_bg.content_margin_left = UIStyle.FRAME_PAD_H
	_bg.content_margin_right = UIStyle.FRAME_PAD_H
	_bg.corner_radius_top_left = 3
	_bg.corner_radius_top_right = 3
	_bg.corner_radius_bottom_left = 3
	_bg.corner_radius_bottom_right = 3
	add_theme_stylebox_override("normal", _bg)
	text = PREFIX

# Build version, appended verbatim to whatever the hint resolves to. Kept out of
# hint_for() so the rule table stays a pure function of GAME state.
func set_version_suffix(s: String) -> void:
	_version_suffix = s
	_last_text = "" # force the next refresh through

func refresh(state: Dictionary) -> void:
	# Off-switch lives in the DebugSettings registry (one entry, menu builds
	# itself). Falling back to ON keeps this working if the key is ever removed.
	var enabled := true
	if DebugSettings and DebugSettings.has_method("get_choice"):
		enabled = DebugSettings.get_choice("hint_bar") == DebugSettings.HintBar.ON

	var next := (hint_for(state) if enabled else PREFIX) + _version_suffix
	# Labels re-layout on assignment; this runs every frame, so only touch it
	# when the string actually changed.
	if next != _last_text:
		_last_text = next
		text = next
		_pulse()

# Brief brighten-then-settle on every change. Guarded for headless: create_tween
# needs the node in a tree, and the rule tests exercise refresh() directly.
func _pulse() -> void:
	if not is_inside_tree() or _bg == null:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	# Snap to the accent fill, then fade the ALPHA back to nothing. Tweening the
	# StyleBoxFlat resource directly (rather than the Label) leaves the glyphs at
	# their resting colour throughout, so only the block behind them moves.
	_bg.bg_color = PULSE_BG
	add_theme_color_override("font_color", PULSE_FG)
	_pulse_tween = create_tween()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(_bg, "bg_color",
		Color(PULSE_BG.r, PULSE_BG.g, PULSE_BG.b, 0.0), PULSE_SECONDS)
	# Theme overrides are not tweenable properties, so drive the font colour
	# through a method call on the same clock as the fill.
	_pulse_tween.tween_method(_set_font_color, PULSE_FG, REST_FG, PULSE_SECONDS)

func _set_font_color(c: Color) -> void:
	add_theme_color_override("font_color", c)
