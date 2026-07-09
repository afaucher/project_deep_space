extends RefCounted
class_name PortRules

# M35 -- Zone boundary aid + local rules (port_zone.rules as data).
# implementation_plans/m31_m36_port_authority_roadmap.md, M35 scope.
#
# `port_zone.rules` is a plain Dictionary authored on a controlled station
# (see medium_station.gd). This file is the RULE -> HANDLER dispatch seam the
# roadmap calls for: a registry (not an if/elif chain) mapping a rule key to a
# pure function that renders that rule's contribution to the crossing-banner
# summary line. Adding a new rule (weapons_safe, a hard speed limit, tolls,
# ...) is a one-entry addition to RULE_SUMMARY_HANDLERS -- no change to the
# banner-building code (banner_summary/banner_text below) or to the crossing
# HUD that calls them (terminal_display.gd). An unknown rule key already in a
# `rules` dict (e.g. authored ahead of its handler landing, or a stale/typo'd
# key) is skipped, not a crash -- see banner_summary's `.get` lookup.
#
# Mirrors DebugSettings.OPTIONS' "const registry, keyed dispatch, no per-knob
# UI wiring" shape (scripts/debug_settings.gd) -- same idea here: a rule's
# presentation logic lives entirely in its own registry entry.

# Each handler: func(value: Variant) -> String, returning the summary
# fragment for that rule (joined with " · " by banner_summary), or "" to
# contribute nothing (a handler CAN suppress its own output, e.g. a
# docking_permission_required: false would read oddly if surfaced).
static func _docking_permission_summary(value) -> String:
	if value:
		return "docking by permission"
	return ""

static func _speed_advisory_summary(value) -> String:
	var limit: float = float(value)
	if limit <= 0.0:
		return ""
	return "speed advisory %d" % int(round(limit))

# GDScript can't initialize a `const` Dictionary with Callable values (static
# method references aren't constant expressions at parse time -- confirmed
# directly: "Assigned value for constant... isn't a constant expression").
# Built lazily instead via this static func returning a fresh Dictionary of
# Callables each call -- still a genuine keyed rule->handler REGISTRY (the
# thing the roadmap calls for), not an if/elif chain; only the "const"
# storage had to move from a dict literal to a function. Callers/tests query
# this directly (PortRules.rule_summary_handlers()) to prove a rule key is
# (or isn't) registered -- see test_port_rules.gd's extensibility scenario.
static func rule_summary_handlers() -> Dictionary:
	return {
		"docking_permission_required": _docking_permission_summary,
		"speed_advisory": _speed_advisory_summary,
	}

# Builds the data-driven summary line from a zone's `rules` dict, e.g.
# "docking by permission · speed advisory 200". Iterates `rules` in whatever
# order the Dictionary holds (insertion order in GDScript, so authoring order
# in medium_station.gd controls display order); any key with no registered
# handler is skipped silently (graceful-ignore, per roadmap scenario 4) rather
# than raising or crashing. Empty `rules` (or every handler returning "") ->
# "".
static func banner_summary(rules: Dictionary) -> String:
	var handlers: Dictionary = rule_summary_handlers()
	var parts: Array = []
	for key in rules.keys():
		if not handlers.has(key):
			continue
		var handler: Callable = handlers[key]
		var fragment: String = handler.call(rules[key])
		if fragment != "":
			parts.append(fragment)
	return " · ".join(parts)

# Full crossing-banner text. entering=true -> "Entering IRONHOLD CONTROL --
# docking by permission · speed advisory 200" (summary omitted entirely, no
# dangling "--", when rules is empty/every rule is unhandled/suppressed);
# entering=false -> "Leaving IRONHOLD CONTROL" (leaving never shows the rules
# summary -- nothing to advise once you're on your way out).
static func banner_text(entering: bool, authority: String, rules: Dictionary) -> String:
	if not entering:
		return "Leaving %s" % authority
	var summary: String = banner_summary(rules)
	if summary == "":
		return "Entering %s" % authority
	return "Entering %s — %s" % [authority, summary]

# M35 speed-advisory truth table (pure, no node/scene state -- roadmap test
# scenario 3 calls this directly). Advisory is active only while BOTH
# conditions hold: inside a controlled zone that authors a positive
# speed_advisory, AND current speed is over that limit. Outside any zone, or a
# zone with no/zero speed_advisory rule, never advises regardless of speed --
# this is a WARN-ONLY readout (color state), never a thrust clamp or other
# gameplay effect (see helm_panel.gd's EngineSlider amber state).
static func speed_advisory_active(in_zone: bool, speed: float, limit: float) -> bool:
	if not in_zone:
		return false
	if limit <= 0.0:
		return false
	return speed > limit

# Convenience wrapper reading the limit straight out of a rules dict (0.0/no
# rule -> never active, same as speed_advisory_active's own guard). Kept
# separate from the pure 3-float truth table above so callers that already
# have a `rules` Dictionary (helm_panel.gd, via the resolved zone) don't have
# to dig out "speed_advisory" themselves, while the test can still exercise
# the exact truth table in isolation.
static func speed_advisory_active_for_rules(in_zone: bool, speed: float, rules: Dictionary) -> bool:
	var limit: float = float(rules.get("speed_advisory", 0.0))
	return speed_advisory_active(in_zone, speed, limit)
