extends RefCounted
class_name ZoneBanner

# M35 -- crossing-banner STATE, factored out of terminal_display.gd as a pure/
# testable seam (same "pure static, thin _draw()/UI wrapper" pattern M34 set
# for navigation_panel.gd's assigned_bay_for/lane_path/etc. -- see that
# milestone's Shipped note). terminal_display.gd owns the actual Label node
# and the frame-to-frame countdown; this file is the text-composition +
# on/off decision, callable with no scene/node/SceneTree at all, so
# test_port_rules.gd can drive scenario 2 (crossing banner state) without
# constructing the full terminal (audio players, every sub-panel, docking
# control, etc.) just to reach one Label's text.
#
# Show/hide semantics (roadmap: "entering sets a banner...leaving clears
# it"): entering sets the text to "Entering <authority> — <rules summary>"
# and marks the banner visible; leaving does NOT hide the banner outright --
# it OVERWRITES the text to "Leaving <authority>" (still visible, still
# driven by the event) so the player sees confirmation they're clear of the
# zone, then terminal_display.gd's per-frame timer auto-fades it after
# ZONE_BANNER_DURATION regardless of which event set it last. This mirrors
# the roadmap's own worked example ("Leaving IRONHOLD CONTROL" is a real
# displayed message, not silence) while still satisfying "leaving clears
# it" -- the ENTER message is unambiguously replaced/cleared on exit.
const PortRules = preload("res://scripts/port/port_rules.gd")

# Composes the banner text for a crossing event. entering=true -> reads the
# rules dict for the summary (see PortRules.banner_text); entering=false ->
# "Leaving <authority>", rules ignored (nothing to advise on the way out).
static func text_for_crossing(entering: bool, authority: String, rules: Dictionary) -> String:
	return PortRules.banner_text(entering, authority, rules)

# Whether the banner should be showing right now, given the countdown timer
# terminal_display.gd drives in _process(). Pure: no Label/node touched.
static func is_visible(timer_remaining: float) -> bool:
	return timer_remaining > 0.0
