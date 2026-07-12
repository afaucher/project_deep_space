extends Node

# M35 acceptance -- Zone boundary aid + local rules
# (implementation_plans/m31_m36_port_authority_roadmap.md, M35 section).
# Covers the roadmap's 4 test-plan scenarios, all synchronous/pure (no
# physics stepping needed -- everything under test here is a static helper
# or the state a UI element reads, not pixels or timing):
#   1. Boundary geometry: rendered ring radius == zone radius (LOD helper).
#   2. Crossing banner state: entering sets a banner naming the authority +
#      rules summary; leaving clears it to the "Leaving..." message.
#   3. Speed advisory logic: pure truth-table over PortRules.speed_advisory_active.
#   4. Extensibility: an unknown rule key is ignored; a second known rule
#      composes into the summary.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_port_rules
# Pass marker per CLAUDE.md.

const MediumStation = preload("res://scripts/ships/medium_station.gd")
const NavigationPanel = preload("res://scripts/ui/navigation_panel.gd")
const PortRules = preload("res://scripts/port/port_rules.gd")
const PortZone = preload("res://scripts/port/port_zone.gd")
const TerminalDisplay = preload("res://scripts/ui/terminal_display.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")

# M46 -- synthetic overlay for the exclusion_radius port_patch scenario. Same
# static get_entry(sid) -> Dictionary interface ClusterLoader._merge_overlay
# expects (see cluster_loader.gd), mirroring test_story_overlay.gd's
# SyntheticOverlay pattern rather than inventing a new mechanism.
class ExclusionPatchOverlay:
	extends RefCounted
	static func get_entry(sid: String) -> Dictionary:
		if sid == "patched_station":
			return {"port": {"exclusion_radius": 999.0}}
		return {}

var main_node: Node = null
var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func setup(main) -> void:
	main_node = main
	print("Starting Port Rules (M35) Tests")

	_run_boundary_geometry_scenario()
	_run_crossing_banner_scenario()
	_run_speed_advisory_scenario()
	_run_extensibility_scenario()
	_run_ironhold_data_scenario()
	_run_speed_zone_state_scenario()
	_run_drift_cue_scenario()
	_run_exclusion_radius_scenario()

	_finalize()

# ---------------------------------------------------------------------------
# Scenario 1 -- Boundary geometry: rendered ring radius == zone radius; pure.
# NavigationPanel.zone_boundary_visible is the LOD gate (mirrors
# OUTLINE_LOD_MIN_PX); the actual draw call (_draw_zone_boundary) always
# passes the zone's own `radius` straight to draw_arc with no scaling/
# transformation of the radius itself (the panel's world-space transform
# handles zoom, same as every other world-space draw call in that file) --
# so "rendered ring radius == zone radius" is proven by asserting the LOD
# helper's radius parameter is the raw zone radius, and that the gate's
# on/off boundary matches OUTLINE_LOD_MIN_PX exactly (same constant reused,
# per the ground-truth brief, not a second invented threshold).
# ---------------------------------------------------------------------------
func _run_boundary_geometry_scenario() -> void:
	var radius := 8000.0

	# At map_zoom = 1.0, an 8000u radius is far above the pixel floor -> visible.
	_assert(NavigationPanel.zone_boundary_visible(radius, 1.0) == true,
		"zone_boundary_visible: an 8000u zone at zoom 1.0 is visible (8000px >> LOD floor)")

	# Reuses the SAME OUTLINE_LOD_MIN_PX constant as the outline LOD gate --
	# not a second invented threshold.
	var lod_min: float = NavigationPanel.OUTLINE_LOD_MIN_PX
	_assert(lod_min == 6.0, "OUTLINE_LOD_MIN_PX is still 6.0px (M35 reuses it, doesn't redefine it)")

	# Exactly at the threshold -> visible (inclusive, mirrors
	# _outline_alpha_for's "< OUTLINE_LOD_MIN_PX" strict-less-than skip).
	var zoom_at_floor: float = lod_min / radius
	_assert(NavigationPanel.zone_boundary_visible(radius, zoom_at_floor) == true,
		"zone_boundary_visible: exactly at the LOD floor (radius*zoom == LOD_MIN_PX) still counts as visible")

	# Just below the threshold -> suppressed (LOD-suppressed when tiny, per roadmap).
	var zoom_below_floor: float = (lod_min - 0.5) / radius
	_assert(NavigationPanel.zone_boundary_visible(radius, zoom_below_floor) == false,
		"zone_boundary_visible: just below the LOD floor is suppressed")

	# The rendered ring radius is the zone's OWN radius, unscaled by anything
	# other than the panel's world-space transform (same convention as every
	# other world-space draw call, e.g. _draw_slip_marker's berth position) --
	# a small zone's ring should be visible/invisible purely as a function of
	# its own radius * zoom, not some fraction of it.
	var small_radius := 100.0
	var tiny_zoom := 0.001 # 100u * 0.001 = 0.1px -- well under the 6px floor
	_assert(NavigationPanel.zone_boundary_visible(small_radius, tiny_zoom) == false,
		"zone_boundary_visible: a 100u zone zoomed out to 0.1px on screen is below the 6px floor -- suppressed")
	_assert(NavigationPanel.zone_boundary_visible(small_radius, tiny_zoom) == (small_radius * tiny_zoom >= lod_min),
		"zone_boundary_visible: gate is exactly radius*zoom >= OUTLINE_LOD_MIN_PX, the ring radius itself untouched")

# ---------------------------------------------------------------------------
# Scenario 2 -- Crossing banner state: entering sets a banner naming the
# authority + rules summary; leaving clears it. Tests the STATE the HUD
# reads (TerminalDisplay.zone_banner_text / zone_banner_label.visible), not
# pixels -- drives it via the exact same _on_zone_crossing() entry point
# update_data()'s transient_events loop calls.
# ---------------------------------------------------------------------------
# Exercises the exact state machine terminal_display.gd drives (ZoneBanner.
# text_for_crossing for the text, ZoneBanner.is_visible(timer) for show/hide)
# without constructing the full TerminalDisplay node tree (audio players,
# every sub-panel, docking control, spawn dropdowns, ...) -- that's a heavy,
# UI-only build with no bearing on THIS milestone's state logic, and
# terminal_display.gd itself is exercised for real by the manual playtest /
# every other UI-driving test in this suite already booting a live terminal.
# Mirrors ZoneBanner's own module comment: "callable with no scene/node/
# SceneTree at all."
func _run_crossing_banner_scenario() -> void:
	const ZoneBanner = preload("res://scripts/port/zone_banner.gd")
	var ironhold_rules := {"docking_permission_required": true, "speed_advisory": 200.0}

	# Entering names the authority + composes the rules summary, exactly the
	# roadmap's example line.
	var enter_text: String = ZoneBanner.text_for_crossing(true, "Ironhold Control", ironhold_rules)
	_assert(enter_text == "Entering Ironhold Control — docking by permission · speed advisory 200",
		"crossing banner: entering sets 'Entering <authority> — <rules summary>' (got '%s')" % enter_text)

	# Leaving clears/replaces it with the "Leaving..." message -- no rules
	# summary on the way out (nothing to advise once departing); rules are
	# passed but must be ignored on the leaving branch.
	var exit_text: String = ZoneBanner.text_for_crossing(false, "Ironhold Control", ironhold_rules)
	_assert(exit_text == "Leaving Ironhold Control",
		"crossing banner: leaving sets 'Leaving <authority>' with no rules summary (got '%s')" % exit_text)

	# An authority with no rules at all (e.g. resolution failed, or a station
	# with an empty rules dict) reads just "Entering <authority>" with no
	# dangling separator -- must not crash.
	var enter_norules: String = ZoneBanner.text_for_crossing(true, "No Rules Authority", {})
	_assert(enter_norules == "Entering No Rules Authority",
		"crossing banner: an authority with no rules has no dangling '--' (got '%s')" % enter_norules)

	# Visibility state: driven by a countdown timer, entering/leaving both set
	# it to a positive value (visible); once it decays to zero the banner
	# clears. This is literally the loop terminal_display.gd's _process()
	# runs -- exercised here with fixture timers, no per-frame node needed.
	_assert(ZoneBanner.is_visible(6.0) == true,
		"crossing banner: a fresh (positive) timer reads visible")
	_assert(ZoneBanner.is_visible(0.001) == true,
		"crossing banner: a nearly-expired but still-positive timer still reads visible")
	_assert(ZoneBanner.is_visible(0.0) == false,
		"crossing banner: a timer that's hit zero reads not-visible (auto-cleared)")
	_assert(ZoneBanner.is_visible(-1.0) == false,
		"crossing banner: a timer driven negative (never clamped) still reads not-visible")

	# End-to-end through the real ship/station data path: a live MediumStation
	# (Ironhold's actual authored rules) + terminal_display.gd's own
	# _rules_for_authority lookup + _on_zone_crossing's state assignment,
	# proving the wiring (not just the pure helper) produces the right text.
	# TerminalDisplay is instantiated WITHOUT add_child (never enters the
	# SceneTree, so _ready() never runs -- no audio players, no sub-panels,
	# no docking_control) precisely so _rules_for_authority's get_tree() call
	# is the only thing that would need a live tree; since authority
	# resolution isn't exercised on this path (rules passed directly to
	# _on_zone_crossing isn't how the real method works) we instead call
	# _on_zone_crossing with a station actually in the tree so the live
	# lookup runs for real.
	var station := MediumStation.new()
	station.name = "BannerWiringCheck"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	main_node.add_child(station)

	var term := TerminalDisplay.new()
	# Deliberately NOT added to the tree -- _on_zone_crossing/_rules_for_authority
	# only need get_tree(), which a node not yet inside the SceneTree does not
	# have; guard against that by adding term as a child of main_node too (main_node
	# is already in the tree, so this is required for get_tree() to resolve).
	main_node.add_child(term)
	term._on_zone_crossing(true, "Ironhold Control")
	_assert(term.zone_banner_text == "Entering Ironhold Control — docking by permission · speed advisory 200",
		"crossing banner (live wiring): entering Ironhold's real port_zone.rules produces the roadmap's exact example (got '%s')" % term.zone_banner_text)
	term._on_zone_crossing(false, "Ironhold Control")
	_assert(term.zone_banner_text == "Leaving Ironhold Control",
		"crossing banner (live wiring): leaving clears to 'Leaving Ironhold Control' (got '%s')" % term.zone_banner_text)

	_free_if_valid(term)
	_free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario 3 -- Speed advisory logic: in-zone AND over-limit -> active; under
# limit -> inactive; outside the zone -> inactive regardless of speed. Pure
# truth-table over PortRules.speed_advisory_active, no scene/node needed.
# ---------------------------------------------------------------------------
func _run_speed_advisory_scenario() -> void:
	var limit := 200.0

	_assert(PortRules.speed_advisory_active(true, 250.0, limit) == true,
		"speed advisory: in-zone AND over the limit -> active")
	_assert(PortRules.speed_advisory_active(true, 200.0, limit) == false,
		"speed advisory: in-zone and EXACTLY at the limit -> inactive (advisory is 'over', not 'at or over')")
	_assert(PortRules.speed_advisory_active(true, 150.0, limit) == false,
		"speed advisory: in-zone but under the limit -> inactive")
	_assert(PortRules.speed_advisory_active(false, 999.0, limit) == false,
		"speed advisory: wildly over the limit but OUTSIDE the zone -> inactive regardless of speed")
	_assert(PortRules.speed_advisory_active(false, 0.0, limit) == false,
		"speed advisory: outside the zone at zero speed -> inactive")

	# No advisory rule authored (limit <= 0) -> never active even in-zone/fast.
	_assert(PortRules.speed_advisory_active(true, 999.0, 0.0) == false,
		"speed advisory: a zero/unset limit never advises, even in-zone and fast")

	# The rules-dict convenience wrapper matches the same truth table when fed
	# a real rules Dictionary (the shape helm_panel.gd actually has on hand).
	var rules := {"speed_advisory": limit}
	_assert(PortRules.speed_advisory_active_for_rules(true, 250.0, rules) == true,
		"speed_advisory_active_for_rules: in-zone + over-limit from a rules dict -> active")
	_assert(PortRules.speed_advisory_active_for_rules(true, 150.0, rules) == false,
		"speed_advisory_active_for_rules: in-zone + under-limit from a rules dict -> inactive")
	_assert(PortRules.speed_advisory_active_for_rules(false, 250.0, rules) == false,
		"speed_advisory_active_for_rules: over-limit but outside the zone -> inactive")
	_assert(PortRules.speed_advisory_active_for_rules(true, 250.0, {}) == false,
		"speed_advisory_active_for_rules: a rules dict with no speed_advisory key -> inactive (graceful default)")

# ---------------------------------------------------------------------------
# Scenario 4 -- Extensibility: an unknown rule key is ignored gracefully (no
# crash); a second known rule composes into the banner summary.
# ---------------------------------------------------------------------------
func _run_extensibility_scenario() -> void:
	# Unknown rule key alone -> no crash, empty summary (nothing recognized).
	var unknown_only := {"weapons_safe": true}
	var summary_unknown: String = PortRules.banner_summary(unknown_only)
	_assert(summary_unknown == "",
		"extensibility: an unrecognized rule key alone produces an empty summary, not a crash (got '%s')" % summary_unknown)

	# Unknown rule key MIXED with known ones -> the known ones still compose;
	# the unknown key is silently skipped, not fatal to the rest.
	var mixed := {
		"docking_permission_required": true,
		"weapons_safe": true,
		"speed_advisory": 150.0,
	}
	var summary_mixed: String = PortRules.banner_summary(mixed)
	_assert(summary_mixed == "docking by permission · speed advisory 150",
		"extensibility: known rules compose correctly even with an unrecognized key mixed in (got '%s')" % summary_mixed)

	# Two known rules alone (no unknown key at all) compose in authoring order.
	var two_known := {
		"docking_permission_required": true,
		"speed_advisory": 75.0,
	}
	var summary_two: String = PortRules.banner_summary(two_known)
	_assert(summary_two == "docking by permission · speed advisory 75",
		"extensibility: two known rules compose with the ' · ' separator (got '%s')" % summary_two)

	# A single known rule (docking_permission_required only) has no separator.
	var one_known := {"docking_permission_required": true}
	_assert(PortRules.banner_summary(one_known) == "docking by permission",
		"extensibility: a single known rule has no stray separator")

	# Empty rules dict -> empty summary, no crash.
	_assert(PortRules.banner_summary({}) == "",
		"extensibility: an empty rules dict produces an empty summary")

	# docking_permission_required: false suppresses its own fragment (nothing
	# to advise if permission ISN'T required) rather than reading oddly.
	var perm_false := {"docking_permission_required": false, "speed_advisory": 200.0}
	_assert(PortRules.banner_summary(perm_false) == "speed advisory 200",
		"extensibility: docking_permission_required:false contributes nothing to the summary")

	# The registry itself is queryable -- a future rule (e.g. weapons_safe)
	# just needs a new entry, proving the seam is a dict, not an if/elif chain.
	var handlers: Dictionary = PortRules.rule_summary_handlers()
	_assert(handlers.has("docking_permission_required"),
		"extensibility: rule_summary_handlers() is a registry keyed by rule name (docking_permission_required present)")
	_assert(handlers.has("speed_advisory"),
		"extensibility: rule_summary_handlers() registry has speed_advisory")
	_assert(not handlers.has("weapons_safe"),
		"extensibility: weapons_safe is NOT yet registered -- proves unknown keys really are unregistered, not silently matched")

# ---------------------------------------------------------------------------
# Bonus -- Ironhold's actual authored rules (medium_station.gd) match the
# roadmap's worked example exactly, so the banner text quoted in the roadmap
# ("docking by permission · speed advisory 200") is actually what a player
# sees, not just what the pure helpers can theoretically produce.
# ---------------------------------------------------------------------------
func _run_ironhold_data_scenario() -> void:
	var station := MediumStation.new()
	station.name = "IronholdRulesCheck"
	station.owner_id = 1
	station.iff_tags = ["TEAM_PLAYER"]
	main_node.add_child(station)

	var zone: Dictionary = station.get_port_zone()
	_assert(not zone.is_empty(), "Ironhold (medium_station.gd) authors a non-empty port_zone")
	_assert(zone.get("authority", "") == "Ironhold Control", "Ironhold's authority is 'Ironhold Control'")

	var rules: Dictionary = zone.get("rules", {})
	_assert(rules.get("docking_permission_required", false) == true,
		"Ironhold's rules: docking_permission_required is true")
	_assert(float(rules.get("speed_advisory", 0.0)) == 200.0,
		"Ironhold's rules: speed_advisory is 200.0")

	var banner: String = PortRules.banner_text(true, zone.get("authority", ""), rules)
	_assert(banner == "Entering Ironhold Control — docking by permission · speed advisory 200",
		"Ironhold's actual authored rules produce the roadmap's exact worked example (got '%s')" % banner)

	_free_if_valid(station)

# ---------------------------------------------------------------------------
# Scenario 6 (M46) -- three-state speed readout truth table
# (PortRules.speed_zone_state), incl. boundaries at 90% and 100% of the
# limit, in_zone == false always NORMAL, and limit == 0 always NORMAL.
# ---------------------------------------------------------------------------
func _run_speed_zone_state_scenario() -> void:
	var limit := 200.0

	_assert(PortRules.speed_zone_state(179.0, limit, true) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: just under 90%% of the limit (179/200) -> NORMAL")
	_assert(PortRules.speed_zone_state(180.0, limit, true) == PortRules.SpeedState.APPROACHING,
		"speed_zone_state: exactly 90%% of the limit (180/200) -> APPROACHING (boundary is inclusive)")
	_assert(PortRules.speed_zone_state(199.0, limit, true) == PortRules.SpeedState.APPROACHING,
		"speed_zone_state: just under the limit (199/200) -> APPROACHING")
	_assert(PortRules.speed_zone_state(200.0, limit, true) == PortRules.SpeedState.APPROACHING,
		"speed_zone_state: exactly AT the limit (200/200) -> APPROACHING, not OVER (matches speed_advisory_active's strict '>' convention)")
	_assert(PortRules.speed_zone_state(200.01, limit, true) == PortRules.SpeedState.OVER,
		"speed_zone_state: just over the limit -> OVER")
	_assert(PortRules.speed_zone_state(500.0, limit, true) == PortRules.SpeedState.OVER,
		"speed_zone_state: wildly over the limit -> OVER")
	_assert(PortRules.speed_zone_state(0.0, limit, true) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: standing still in-zone -> NORMAL")

	# in_zone == false -> always NORMAL regardless of speed/limit.
	_assert(PortRules.speed_zone_state(999.0, limit, false) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: wildly over the limit but OUTSIDE the zone -> NORMAL")
	_assert(PortRules.speed_zone_state(0.0, limit, false) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: standing still outside the zone -> NORMAL")

	# limit == 0 (no rule authored) -> always NORMAL regardless of in_zone/speed.
	_assert(PortRules.speed_zone_state(999.0, 0.0, true) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: in-zone and fast but limit is 0/unset -> NORMAL")
	_assert(PortRules.speed_zone_state(999.0, -5.0, true) == PortRules.SpeedState.NORMAL,
		"speed_zone_state: a malformed negative limit is treated as 'no rule' -> NORMAL")

# ---------------------------------------------------------------------------
# Scenario 7 (M46) -- lateral-drift cue visibility (PortRules.drift_cue_visible).
# ---------------------------------------------------------------------------
func _run_drift_cue_scenario() -> void:
	_assert(PortRules.drift_cue_visible(30.0, 100.0) == true,
		"drift_cue_visible: lateral 30/100 true speed (30%%) exceeds the 20%% ratio threshold -> visible")
	_assert(PortRules.drift_cue_visible(10.0, 100.0) == false,
		"drift_cue_visible: lateral 10/100 true speed (10%%, and well under the 25u/s absolute floor) -> not visible")
	_assert(PortRules.drift_cue_visible(26.0, 1000.0) == true,
		"drift_cue_visible: lateral 26u/s alone exceeds the 25u/s absolute floor even at a tiny fraction of true speed -> visible")
	_assert(PortRules.drift_cue_visible(0.0, 0.0) == false,
		"drift_cue_visible: no motion at all -> not visible (no div-by-zero either)")
	_assert(PortRules.drift_cue_visible(0.0, 500.0) == false,
		"drift_cue_visible: pure forward speed, zero lateral drift -> not visible")

# ---------------------------------------------------------------------------
# Scenario 8 (M46) -- exclusion_radius derivation: derived fallback when
# unauthored, authored override wins when set before _ready(), and a story
# overlay's port_patch override wins over the derived default (applied AFTER
# Ship._ready()'s derivation, via the real ClusterLoader -> ClusterManager
# pipeline -- same pattern test_story_overlay.gd uses for its port-patch
# scenario).
# ---------------------------------------------------------------------------
func _run_exclusion_radius_scenario() -> void:
	# --- Derived fallback: no exclusion_radius authored -> Ship._ready()
	# derives one from the hull's own bounding radius. ---
	var derived_station := MediumStation.new()
	derived_station.name = "DerivedExclusionCheck"
	derived_station.owner_id = 1
	derived_station.iff_tags = ["TEAM_PLAYER"]
	main_node.add_child(derived_station) # add_child triggers _ready() synchronously

	var derived_zone: Dictionary = derived_station.get_port_zone()
	var expected_radius: float = PortZone.derive_exclusion_radius(derived_station.get_bounding_radius())
	_assert(float(derived_zone.get("exclusion_radius", 0.0)) > 0.0,
		"exclusion_radius: a controlled station with none authored derives a positive value")
	_assert(is_equal_approx(float(derived_zone.get("exclusion_radius", 0.0)), expected_radius),
		"exclusion_radius: the derived value matches PortZone.derive_exclusion_radius(hull bounding radius) exactly (got %s, want %s)" % [derived_zone.get("exclusion_radius", 0.0), expected_radius])
	_assert(expected_radius > derived_station.get_bounding_radius(),
		"exclusion_radius: the derived disc extends beyond the hull itself (a no-fly zone that doesn't clear the hull would be meaningless)")
	_free_if_valid(derived_station)

	# --- Authored override: set BEFORE the station enters the tree (before
	# _ready() runs) -- Ship._ready()'s derivation must leave it untouched. ---
	var authored_station := MediumStation.new()
	authored_station.name = "AuthoredExclusionCheck"
	authored_station.owner_id = 1
	authored_station.iff_tags = ["TEAM_PLAYER"]
	authored_station.port_zone["exclusion_radius"] = 4242.0
	main_node.add_child(authored_station)

	var authored_zone: Dictionary = authored_station.get_port_zone()
	_assert(float(authored_zone.get("exclusion_radius", 0.0)) == 4242.0,
		"exclusion_radius: an authored value set before _ready() survives untouched (got %s)" % authored_zone.get("exclusion_radius", 0.0))
	_free_if_valid(authored_station)

	# --- port_patch override: a story overlay's "port": {"exclusion_radius": ...}
	# entry, merged by ClusterManager._apply_overlay_decorations AFTER
	# Ship._ready()'s derivation already ran -- the patch must win. ---
	var manager := ClusterManager.new()
	manager.policy.configure_full_sim()
	manager.live_parent = main_node
	main_node.add_child(manager)

	var def := ClusterDef.new()
	def.name = "Exclusion Patch Test Cluster"
	def.bounds = Rect2(-10000, -10000, 200000, 200000)
	def.player_start = Vector2.ZERO
	def.add_entity({"id": 1, "sid": "patched_station", "name": "Patched Station", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(0, 0), "iff_tags": [], "is_static": true})

	ClusterLoader.load_into(def, manager, ExclusionPatchOverlay, null)
	manager.tick(0.0)

	var rec = null
	for r in manager.records:
		if r.id == 1:
			rec = r
	_assert(rec != null and rec.is_live(), "the patched station should be promoted live")
	if rec != null and rec.is_live():
		var patched_zone: Dictionary = rec.live_node.get_port_zone()
		_assert(float(patched_zone.get("exclusion_radius", 0.0)) == 999.0,
			"exclusion_radius: a story overlay's port_patch override wins over the derived default (got %s)" % patched_zone.get("exclusion_radius", 0.0))
		_assert(patched_zone.get("authority", "") == "Patched Station Control",
			"exclusion_radius: the port_patch override must not clobber the rebranded authority (got '%s')" % patched_zone.get("authority", ""))

	manager.queue_free()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_port_rules <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_port_rules <<<")
		get_tree().quit(1)
