extends Node

# Autoload singleton: DebugSettings
# ----------------------------------
# Global debug knobs, deliberately the SIMPLEST possible thing. Game code reads these
# directly (e.g. DebugSettings.get_choice("missile_cleanup")) instead of routing a
# selection through the host/client packet -- so flipping a menu item on the local
# terminal changes host-side behavior immediately. This breaks the networking
# abstraction on purpose: it's a sandbox debug surface, not authoritative state. If a
# knob ever needs to be correct across a real multiplayer session, promote it out of
# here; until then, ease of adding new toggles wins.
#
# TO ADD A NEW DEBUG SELECTION: append one entry to OPTIONS. The top-bar "Debug" menu
# builds itself from this registry (see terminal_display._build_debug_menu), and any
# code anywhere can read it with get_choice("your_key"). No UI wiring needed.

signal changed(key: String, value: int)

# Stable indices for the "missile_cleanup" choices, so host code reads named values
# instead of magic ints. Order MUST match the "choices" array below.
enum MissileCleanup { OFF, ALL, VISIBLE, DISPROVAL }

# How a sensor bin holding more than one object collapses to a single blip.
# BLEND (current): max heat/EM, summed cross-section, largest object owns the id --
#   lets a hot enemy's signature bleed onto a co-bearing asteroid ("signature bleed").
# NEAREST: keep only the nearest object's clean signature+id; farther objects are
#   shadowed and their tracks dead-reckon, so neither identity is ever corrupted.
enum SignatureMerge { BLEND, NEAREST }

# key -> { label, choices (display strings, index == stored value), default }
const OPTIONS := {
	"missile_cleanup": {
		"label": "Missile contact cleanup",
		"choices": [
			"Off (20s dead-reckon timeout)",   # OFF      -- current shipped behavior
			"Purge all immediately",           # ALL      -- Option 1
			"Purge only if visible",           # VISIBLE  -- Option 2
			"Trace disproval (WIP)",           # DISPROVAL-- Option 3 (placeholder, see decay loop)
		],
		"default": MissileCleanup.ALL,
	},
	"signature_merge": {
		"label": "Co-bearing bin merge",
		"choices": [
			"Blend (max heat/EM, sum CS)",     # BLEND   -- current shipped behavior
			"Nearest-wins (no bleed)",         # NEAREST -- shadow farther objects
		],
		"default": SignatureMerge.BLEND,
	},
}

var _values := {}

func _ready() -> void:
	for key in OPTIONS:
		_values[key] = OPTIONS[key]["default"]

func get_choice(key: String) -> int:
	return _values.get(key, OPTIONS.get(key, {}).get("default", 0))

func set_choice(key: String, value: int) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key, value)
