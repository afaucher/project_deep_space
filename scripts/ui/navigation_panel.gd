extends Control

signal contact_selected(c_id: String)

const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const FoamPhysics = preload("res://scripts/cluster/foam_physics.gd")

# WORLD_HALF_EXTENT clamps the grid/camera to +/- this on each axis. It tracks
# home_cluster.gd's `def.bounds` half-extent (+/-500000 as of M53a's 2x
# reshape) with a +10k margin -- if the cluster is ever rescaled again, update
# BOTH together (same coupling FoamPhysics.BOUNDARY documents for the physics
# side; see FOAM_BOUNDARY below, which reads that value directly instead of
# duplicating it, so this constant is the only literal left to keep in sync).
const WORLD_HALF_EXTENT := 510000.0
# Foam-current fade distance from the world edge -- reads FoamPhysics.BOUNDARY
# directly (not a duplicated literal) so it can never drift out of sync with
# the physics boundary again.
const FOAM_BOUNDARY := FoamPhysics.BOUNDARY
const FOAM_FADE_DIST := 10000.0

# v1.1 outline revision (design_ideas/ship_outline_rendering.md "first-
# playtest revision"): the fade window is SIZE-PROPORTIONAL -- an angular-
# resolution model where shape resolves when the target subtends enough of
# your view. fade_start = START_RADII * bounding_radius, full = FULL_RADII *
# radius. Reproduces the old hand-picked constants at both scales (frigate
# ~54r -> 2700/1350 vs old 3000/1500; medium station ~264r -> 13200/6600 vs
# old 12000/6000) while scaling continuously to mines and asteroid stations.
# Replaces the old two-case ship/station window switch.
const OUTLINE_START_RADII := 50.0
const OUTLINE_FULL_RADII := 25.0

# Below this many screen pixels of bounding radius, an outline is too small to
# read -- keep the cheap blip/marker instead (matches the v1 design doc's LOD
# gate, "~12px", applied here as a radius-in-pixels floor).
const OUTLINE_LOD_MIN_PX := 6.0

# Signature-scaled fallback for _bounds_radius_for when a contact's instance
# isn't live/valid (dead-reckoned after a kill, or never resolvable). Keeps
# the bounds ring's scale roughly honest (bigger cross_section -> bigger
# ring) instead of collapsing to one flat guess for every unknown contact.
const BOUNDS_FALLBACK_MIN := 50.0
const BOUNDS_FALLBACK_CS_SCALE := 1.0

# v1.1: outlines and dots draw in the CONTACT's color (_get_contact_color --
# classification x confidence), the same channel as the blip they replace.
# The old component-type color table left the panel with the per-component
# boxes (that detail belongs to the engineering panel, not the tactical map).
const OUTLINE_DOT_RADIUS_PX := 1.5

const ShipSilhouette = preload("res://scripts/components/ship_silhouette.gd")
const NavCorridor = preload("res://scripts/nav/nav_corridor.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const PortChannel = preload("res://scripts/port/port_channel.gd")
const ExclusionHatch = preload("res://scripts/port/exclusion_hatch.gd")

# M34 -- Docking nav aids (assigned slip highlight + approach lane). See
# implementation_plans/m31_m36_port_authority_roadmap.md, M34 scope.
# LANE_LENGTH is how far back from the berth the guide corridor's approach
# waypoint sits, measured along the berth's outward heading (bay.rotation --
# same convention DockingBay._servo uses: "global_rotation + PI - port_heading"
# faces the ship INTO the berth, so the berth's own forward axis points OUT of
# the station, and the lane runs from a point LANE_LENGTH out back down to the
# berth). LANE_HALF_WIDTH is the corridor's authored half-width fed to
# NavCorridor.corridor().
const LANE_LENGTH := 1500.0
const LANE_HALF_WIDTH := 120.0

# F9 omniscience debug overlay -- per-Kind color/size so STATION/WORMHOLE/
# BEACON/ASTEROID read as distinct from the TRAFFIC/PLAYER ships the mode was
# originally built for (those two keep the original magenta). Asteroids are
# numerous (~69 in the home cluster) so they're drawn noticeably smaller and
# dimmer -- see DEBUG_ENTITY_BACKGROUND_KINDS below, which also keeps them
# (and beacons) drawn UNDER the ship/station/wormhole markers.
const DEBUG_ENTITY_STYLE := {
	ClusterEntity.Kind.PLAYER: {"color": Color.MAGENTA, "radius": 15.0, "border": Color.WHITE},
	ClusterEntity.Kind.TRAFFIC: {"color": Color.MAGENTA, "radius": 15.0, "border": Color.WHITE},
	ClusterEntity.Kind.STATION: {"color": Color(0.3, 0.7, 1.0, 1.0), "radius": 15.0, "border": Color.WHITE},
	ClusterEntity.Kind.WORMHOLE: {"color": Color(0.7, 0.3, 1.0, 1.0), "radius": 15.0, "border": Color.WHITE},
	ClusterEntity.Kind.BEACON: {"color": Color(1.0, 0.7, 0.1, 1.0), "radius": 10.0, "border": Color.WHITE},
	ClusterEntity.Kind.ASTEROID: {"color": Color(0.55, 0.55, 0.55, 0.5), "radius": 4.0, "border": Color(0.75, 0.75, 0.75, 0.4)},
}
# Drawn in an earlier pass (before the rest) so numerous small markers never
# sit on top of the ship/station/wormhole markers.
const DEBUG_ENTITY_BACKGROUND_KINDS := [ClusterEntity.Kind.ASTEROID, ClusterEntity.Kind.BEACON]

# Authority-colored highlight (distinct from any existing classification hue --
# GREEN=friendly, RED=hostile, YELLOW=ordnance, GRAY=asteroid, CYAN=sensor --
# so a granted slip never gets confused with an IFF/threat read). Gold reads as
# "clearance" without overlapping the classification palette. Only the
# assigned/open bay(s) draw at all now (see _draw_slip_marker) -- a dim ring
# per unassigned slip was dropped as redundant with the capture zone circle.
const SLIP_HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const LANE_CENTERLINE_COLOR := Color(1.0, 0.85, 0.2, 0.8)
const LANE_EDGE_COLOR := Color(1.0, 0.85, 0.2, 0.25)

# M35 -- zone boundary ring color. Same gold family as the M34 slip/lane
# markers (SLIP_HIGHLIGHT_COLOR) -- "authority-colored" per the roadmap, i.e.
# it reads as "controlled space", not a threat/classification color. Kept
# distinct (lower alpha, no fill) so a docked-in-Ironhold nav map doesn't
# double up two full-strength gold rings once a lane is also drawn.
# M46 (revised) -- zone geometry is BACKGROUND terrain, not a foreground
# element: it draws first inside the world transform (right after the grid,
# under everything else), in colors blended ~halfway toward the nav panel's
# background (0.05, 0.05, 0.1) so contacts/lanes/markers always pop over it,
# with THICKER strokes so it still reads as a boundary at a glance rather
# than a wire. The zone the player is inside is emphasized; every other
# station dims further.
const ZONE_BOUNDARY_COLOR := Color(0.52, 0.45, 0.15, 0.55)
const ZONE_BOUNDARY_DIM_COLOR := Color(0.52, 0.45, 0.15, 0.22)
const ZONE_RING_WIDTH := 4.0        # / map_zoom at draw time

# Exclusion zone (hull -> exclusion_radius, warmer hue than the control-ring
# gold so "no-fly" reads differently from "controlled space"): a single
# boundary ring at exclusion_radius plus 45-degree hatching filling the
# whole disc down to the hull. There is no second inner ring/policy boundary
# -- the hatch's inner bound is just the station's own hull bounding radius,
# a pure visual choice (don't hatch on top of the hull's own drawing), not a
# distinct "keep-out" zone (design_ideas/port_zones_and_channels.md
# terminology). Same emphasized/dimmed and blended-toward-background
# treatment as the control ring.
const EXCLUSION_DISC_COLOR := Color(0.52, 0.3, 0.12, 0.5)
const EXCLUSION_DISC_DIM_COLOR := Color(0.52, 0.3, 0.12, 0.2)

# Hatch fill (ExclusionHatch.hatch_fragments): filled diagonal stripes, drawn
# TO SCALE in world units like the rest of the zone geometry (not a
# constant-screen-width stroke) -- spacing is center-to-center, stripe_width
# a fraction of that so stripe/gap read roughly evenly.
const EXCLUSION_HATCH_SPACING := 150.0
const EXCLUSION_HATCH_STRIPE_WIDTH := 60.0

# The capture zone: a circle centered on the DOCKING POINT (not the station
# center), sized to DockingBay.capture_radius -- "the only area the docking
# clamp applies" (design_ideas/port_zones_and_channels.md terminology).
# Distinct from the small SLIP_HIGHLIGHT_COLOR ring at pos_tolerance (the
# precise DOCKED-state acceptance gate) -- this is the much larger physics
# reach of the clamp, drawn dim/informational since it's not something to
# aim at precisely, just something to know exists. Only drawn for the
# ASSIGNED bay while a live grant is held (same gating as the M34 marker/
# lane -- see _draw_docking_nav_aids).
const CAPTURE_ZONE_COLOR := Color(1.0, 0.85, 0.2, 0.18)

# M46 (revised) -- the channel through the keep-back zone is a 90-degree CONE
# (PortChannel.sector_polygon/lane_edges) centered on the assigned berth's
# approach axis: both circles gap over the cone's span, and the sector's
# radial edges are drawn to show the legal corridor's boundary. Still ZONE
# geometry (background, subdued) -- the ACTIONABLE "fly here" cue is the M34
# lane/slip marker (_draw_docking_nav_aids below), bright gold, which already
# runs from well outside this boundary all the way to the berth.
const CHANNEL_EDGE_COLOR := Color(0.55, 0.42, 0.12, 0.5)

# M41 -- contract markers (see scripts/story/contract_feed.gd) are NAV
# knowledge, never a sensor detection -- a known coordinate/area/place, the
# same knowledge family as destinations/beacon routes/docking lanes. They
# reuse the contact-rendering AFFORDANCES (on-screen marker, off-screen edge
# arrow) but get their OWN color so nav knowledge always reads as a distinct
# channel from classification-colored sensor contacts (green=friendly,
# red=hostile, yellow=ordnance, gray=asteroid, cyan=sensor) and from the
# docking-gold slip/lane markers above (a different context -- "clearance",
# not "objective"). Amber, per the roadmap's suggestion, but visibly warmer/
# more saturated than SLIP_HIGHLIGHT_COLOR so the two golds don't blur
# together when a mission objective happens to be at a controlled station.
const CONTRACT_COLOR := Color(1.0, 0.68, 0.05, 0.95)
const CONTRACT_RING_COLOR := Color(1.0, 0.68, 0.05, 0.4)

const CONTRACT_MARKER_RADIUS_PX := 9.0
# GO_TO_AREA ring dash pattern, in WORLD units (not screen pixels) so the
# dash rhythm holds steady across zoom -- only the stroke WIDTH stays
# constant-pixel (the "N.0 / map_zoom" convention used throughout this file).
const CONTRACT_DASH_LEN := 400.0
const CONTRACT_GAP_LEN := 250.0

# The friendly-identification convention this whole file already uses:
# Utils.classification_color/_get_contact_color key off classify_contact()'s
# string output, and "FRIENDLY VESSEL"/"FRIENDLY ORDNANCE" are the only two
# strings that mean "one of ours" (see ship.gd's classify_contact() and
# utils.gd's classification_color()). Reused here, not reinvented, so the
# demotion rule can never disagree with what the blip color already tells
# the player.
static func _is_friendly_contact(contact: Dictionary) -> bool:
	var classification: String = contact.get("classification", "")
	return classification == "FRIENDLY VESSEL" or classification == "FRIENDLY ORDNANCE"

# The M26 measured-dot outline is a DebugSettings-gated fallback lever, OFF by
# default (see DebugSettings.SensorDotOutlines). When off, EVERY ship contact --
# friendly or not -- renders as the authoritative cached silhouette instead of
# sampled dots. Kept as a toggle so the dot path stays live and re-enableable.
static func _sensor_dots_enabled() -> bool:
	if DebugSettings == null:
		return false
	return DebugSettings.get_choice("sensor_dot_outlines") == DebugSettings.SensorDotOutlines.ON

# Pure fade function -- alpha 1.0 at/inside `full`, 0.0 at/beyond `start`,
# linear between, clamped both sides. Kept as a static pure function (no draw
# calls, no node state) so it's directly unit-testable per the M25 plan.
static func outline_alpha(dist: float, full: float, start: float) -> float:
	if start <= full:
		return 1.0 if dist <= full else 0.0
	return 1.0 - clampf((dist - full) / (start - full), 0.0, 1.0)

# Live/valid target's true get_bounding_radius() when resolvable; otherwise a
# signature-scaled default that at least tracks cross_section instead of one
# flat guess for every unknown contact. Never returns 0 -- repoints the old
# hardcoded 50-radius "physical bounds" ring at real geometry (or an honest
# stand-in) instead of a flat lie for every hull size.
static func _bounds_radius_for(contact: Dictionary) -> float:
	var instance_id: int = contact.get("instance_id", -1)
	if instance_id != -1:
		var inst = instance_from_id(instance_id)
		if inst != null and is_instance_valid(inst) and inst.has_method("get_bounding_radius"):
			return inst.get_bounding_radius()

	var cross_section: float = contact.get("signature", {}).get("cross_section", 0.0)
	return max(BOUNDS_FALLBACK_MIN, cross_section * BOUNDS_FALLBACK_CS_SCALE)

# Testable seam, v1.1: builds SILHOUETTE draw entries for a contact -- the
# ship's union contour loops (ShipSilhouette, cached per class), NOT
# per-component rects (those leaked module layout and read as clutter; see
# ship_outline_rendering.md "first-playtest revision"). Entries:
# {points: PackedVector2Array (ship-local loop), is_hole: bool, rotation:
# float (the ship's current heading -- caller/tests apply rotate+translate)}.
# A freed/stale/unresolvable instance (dead-reckoned contact after a kill --
# a hot path) returns [] without erroring; .get() defensively throughout per
# CLAUDE.md's missing-key/freed-instance frame-abort warning.
static func _outline_draw_list(contact: Dictionary) -> Array:
	var out: Array = []
	var instance_id: int = contact.get("instance_id", -1)
	if instance_id == -1:
		return out

	var inst = instance_from_id(instance_id)
	if inst == null or not is_instance_valid(inst):
		return out
	if inst.get("ship_components") == null:
		return out

	var ship_rot: float = inst.get("rotation") if inst.get("rotation") != null else 0.0

	for loop in ShipSilhouette.loops_for(inst):
		out.append({
			"points": loop["points"],
			"is_hole": loop["is_hole"],
			"rotation": ship_rot,
		})
	return out

# M26 -- parallel seam to _outline_draw_list, deliberately NOT collapsed into
# it (see the M26 plan: "extend _outline_draw_list or add a parallel
# _dot_draw_list(contact) seam ... don't collapse them" -- v1's rects and v2's
# dots are demoted/promoted independently per contact, so keeping them as two
# testable pure functions lets the no-leak check assert on each in isolation).
#
# Returns the contact's outline_dots translated into world space using the
# SAME rotation-resolution convention _outline_draw_list already uses (the
# live instance's actual current rotation) -- consistent with how v1 always
# rendered "true" rotation and only the shape became measured in v2. Each dot
# is stored in TARGET-local space (ship.gd's _sample_outline_dots comment
# explains why), so it rides the hull as the target turns: world_pos =
# c_pos (the contact's DRAWN/fused position, not the live instance's true
# position -- same anchor-to-blip rule _draw_contact_outline already follows
# for the v1 rects) + pos_local.rotated(current rotation).
#
# Pure: no draw_* calls. Returns [] for a stale/freed/missing instance or a
# contact with no outline_dots yet (a legitimate "sensors haven't touched it"
# state, not an error).
static func _dot_draw_list(contact: Dictionary, c_pos: Vector2) -> Array:
	var out: Array = []
	var dots = contact.get("outline_dots", [])
	if dots == null or dots.is_empty():
		return out

	var instance_id: int = contact.get("instance_id", -1)
	if instance_id == -1:
		return out
	var inst = instance_from_id(instance_id)
	if inst == null or not is_instance_valid(inst):
		return out

	var ship_rot: float = inst.get("rotation") if inst.get("rotation") != null else 0.0

	for dot in dots:
		var pos_local: Vector2 = dot.get("pos_local", Vector2.ZERO)
		out.append(c_pos + pos_local.rotated(ship_rot))
	return out

# ---------------------------------------------------------------------------
# M34 -- Docking nav aids. Pure/testable seams (no draw_* calls, no scene
# lookups) -- the panel's _draw() is a thin wrapper that resolves live
# DockingBay nodes then calls these. See test_docking_nav_aids.gd.
# ---------------------------------------------------------------------------

# Given a station's list of DockingBay children and the player's docking_grant
# (or null/empty), returns the ONE bay the grant is assigned to, or null:
#   - no grant, or grant.slip_id doesn't match any bay -> null (nothing to
#     highlight -- scenario 3, "no grant -> no aid").
#   - grant.slip_id == "" (any-open, the MINIMAL/STAFFED degraded style) ->
#     null too. Any-open highlights ALL open bays equally (see
#     open_bays_for below), not one assigned bay/lane -- there's nothing
#     specific to line up on (roadmap: "draw no single lane").
#   - grant.slip_id == a concrete bay's slip_id -> that bay (scenario 2,
#     "assignment binding": grant for slip 2 finds bay 2, not bay 1).
static func assigned_bay_for(bays: Array, grant) -> Node:
	if grant == null:
		return null
	var slip: String = grant.get("slip_id", "")
	if slip == "":
		return null
	for b in bays:
		if b.slip_id == slip:
			return b
	return null

# Any-open grant support: every bay not currently DOCKED/CAPTURING (i.e. still
# open to a landing) reads as an equally-valid target. Empty bays array or no
# open bays -> empty (nothing to highlight).
static func open_bays_for(bays: Array) -> Array:
	var out: Array = []
	for b in bays:
		if b.state == DockingBay.State.EMPTY:
			out.append(b)
	return out

# The docking lane's 2-point path: an approach waypoint LANE_LENGTH back from
# berth_pos along berth_heading's outward axis, down to berth_pos itself.
# berth_heading follows the same convention as DockingBay.global_rotation --
# "forward" (angle 0) points OUT of the station along the berth's own facing,
# so walking back along -heading by `length` places the waypoint further out,
# and the path [waypoint, berth_pos] reads as "fly this heading inbound to
# berth". Pure fixtures -- no node/scene state (test scenario 1).
static func lane_path(berth_pos: Vector2, berth_heading: float, length: float) -> PackedVector2Array:
	var outward: Vector2 = Vector2.RIGHT.rotated(berth_heading)
	var waypoint: Vector2 = berth_pos + outward * length
	return PackedVector2Array([waypoint, berth_pos])

# Full lane corridor (centerline + edges) for a berth pose -- composes
# lane_path with the shared NavCorridor helper (see scripts/nav/nav_corridor.gd).
static func lane_corridor(berth_pos: Vector2, berth_heading: float, length: float, half_width: float) -> Dictionary:
	return NavCorridor.corridor(lane_path(berth_pos, berth_heading, length), half_width)

# M41 -- pure geometry for the off-screen "dorito" arrow: given a marker's
# SCREEN position, the panel's center/size, and the safe-area margin, returns
# null if the point is already on-screen, else {edge_pos, dir} where `dir` is
# the outward unit direction the arrowhead points along and `edge_pos` is
# where its tip anchors on the panel's safe-area border. Factored out of the
# original inline pinned-contacts off-screen-indicator code below (unchanged
# math -- same offset/ratio/edge_pos derivation) so M41's contract markers
# reuse the EXACT SAME arrow geometry instead of a second copy that could
# drift from the contact arrows.
static func edge_arrow_geometry(screen_pos: Vector2, center: Vector2, panel_size: Vector2, margin: float):
	var safe_rect := Rect2(Vector2.ZERO, panel_size).grow(-margin)
	if safe_rect.has_point(screen_pos):
		return null
	var offset = screen_pos - center
	var x_ratio = abs(offset.x) / (panel_size.x / 2.0 - margin)
	var y_ratio = abs(offset.y) / (panel_size.y / 2.0 - margin)
	var max_ratio = max(x_ratio, y_ratio)
	if max_ratio <= 0.0:
		return null # dead-center -- can't be off-screen, avoid a divide-by-zero
	var edge_pos = center + offset / max_ratio
	var dir_to_contact = offset.normalized()
	return {"edge_pos": edge_pos, "dir": dir_to_contact}

# M35 -- zone boundary LOD suppression. Mirrors the existing outline LOD gate
# exactly (OUTLINE_LOD_MIN_PX / _outline_alpha_for's "bounds_radius * map_zoom
# < OUTLINE_LOD_MIN_PX" check at the bottom of this file): below this many
# screen pixels of radius, a boundary ring is too small to read and just adds
# noise, so skip the draw entirely. Reuses the SAME constant (not a second
# threshold) per the ground-truth brief -- one "too small to read" pixel floor
# for the whole panel. Pure/testable: test_port_rules.gd scenario 1 calls this
# directly with fixture radius/zoom pairs, no scene/draw involved.
static func zone_boundary_visible(radius: float, zoom: float) -> bool:
	return radius * zoom >= OUTLINE_LOD_MIN_PX

# M35 -- resolves the LIVE controlled station whose port_zone.authority
# matches the given name, scanning the "ships" group. Same group/lookup
# pattern _draw_docking_nav_aids already uses to turn a grant's authority
# string into a station node (and the same cardinality note: a handful of
# controlled stations, not hundreds). Returns null if no controlled station
# currently answers to that authority (e.g. it was destroyed since the ship
# entered its zone -- draw nothing rather than stale geometry).
func _station_for_authority(authority: String) -> Node:
	if authority == "":
		return null
	for s in get_tree().get_nodes_in_group("ships"):
		if not s.has_method("get_port_zone"):
			continue
		var zone: Dictionary = s.get_port_zone()
		if zone.get("authority", "") == authority:
			return s
	return null

var current_state: Dictionary = {
	"pos": Vector2.ZERO,
	"rot": 0.0,
	"vel": Vector2.ZERO
}

var map_zoom: float = 1.0

var zoom_slider: HSlider

var active_lasers: Array = []

# Toggles
var show_weapon_arcs: bool = true
var show_sensor_arcs: bool = false
var show_contact_labels: bool = true
var show_velocity_vectors: bool = true
var show_grid: bool = true
var show_port_control: bool = true

func _ready() -> void:
	clip_contents = true # Ensure drawings don't bleed out of panel
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Top overlay container for controls
	var overlay = HBoxContainer.new()
	overlay.position = Vector2(10, 10)
	overlay.size = Vector2(300, 40)
	add_child(overlay)
	

	
	var zoom_label = Label.new()
	zoom_label.text = "Zoom:"
	overlay.add_child(zoom_label)
	
	zoom_slider = HSlider.new()
	# Range widened for campaign scale (the home cluster spans ~500k units, well
	# past what 0.01 could zoom out to show) -- a few more steps at both ends:
	# out far enough to see the whole cluster, in tighter for close maneuvering
	# (docking approaches etc).
	zoom_slider.min_value = 0.001
	zoom_slider.max_value = 5.0
	zoom_slider.step = 0.0005
	zoom_slider.exp_edit = true
	zoom_slider.value = 0.5
	zoom_slider.custom_minimum_size = Vector2(100, 20)
	zoom_slider.value_changed.connect(func(val: float):
		map_zoom = val
		queue_redraw()
	)
	overlay.add_child(zoom_slider)
	
	_add_toggle(overlay, "Weapon Arcs", "show_weapon_arcs")
	_add_toggle(overlay, "Sensor Arcs", "show_sensor_arcs")
	_add_toggle(overlay, "Contact Labels", "show_contact_labels")
	_add_toggle(overlay, "Velocity Vectors", "show_velocity_vectors")
	_add_toggle(overlay, "Grid", "show_grid")
	_add_toggle(overlay, "Port Control", "show_port_control")

# Binds a checkbox directly to one of this panel's own show_* bool properties
# by name, instead of hand-writing a near-identical CheckButton + closure for
# each toggle.
func _add_toggle(parent: Control, label: String, property_name: String) -> void:
	var cb = CheckButton.new()
	cb.text = label
	cb.button_pressed = get(property_name)
	cb.toggled.connect(func(pressed: bool):
		set(property_name, pressed)
		queue_redraw()
	)
	parent.add_child(cb)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_slider.value *= 1.25
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_slider.value /= 1.25
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)

func _handle_click(click_pos: Vector2) -> void:
	var pos = current_state.get("pos", Vector2.ZERO)
	var rot = current_state.get("rot", 0.0)
	var camera_pos = pos
	
	var is_ship_oriented = current_state.get("is_ship_oriented", false)
	if not is_ship_oriented:
		var grid_size = WORLD_HALF_EXTENT
		var visible_half = (size / 2.0) / map_zoom
		if visible_half.x < grid_size:
			camera_pos.x = clampf(camera_pos.x, -grid_size + visible_half.x, grid_size - visible_half.x)
		else:
			camera_pos.x = 0.0
		if visible_half.y < grid_size:
			camera_pos.y = clampf(camera_pos.y, -grid_size + visible_half.y, grid_size - visible_half.y)
		else:
			camera_pos.y = 0.0

	var t = Transform2D()
	t = t.translated(-camera_pos)
	t = t.rotated(Utils.get_map_rotation(is_ship_oriented, rot))
	t = t.scaled(Vector2(map_zoom, map_zoom))
	t.origin += size / 2.0
	
	var best_dist = 20.0 # Pixel radius for clicking
	var best_id = ""
	
	var contacts = current_state.get("contacts", {})
	for c_id in contacts.keys():
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		var screen_pos = t.basis_xform(c_pos) + t.origin
		
		var dist = screen_pos.distance_to(click_pos)
		if dist < best_dist:
			best_dist = dist
			best_id = c_id
			
	if best_id != "":
		emit_signal("contact_selected", best_id)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	if packet.has("transient_events"):
		for ev in packet["transient_events"]:
			if ev["type"] == "laser":
				active_lasers.append({"start": ev["start_pos"], "end": ev["end_pos"], "age": 0.0})
	queue_redraw()

func _process(delta: float) -> void:
	var zoom_axis = Input.get_axis("nav_zoom_in", "nav_zoom_out")
	# don't get stuck at max zoom
	if abs(zoom_axis) > 0.1:
		map_zoom *= (1.0 - zoom_axis * delta * 2.0)
		map_zoom = clampf(map_zoom, zoom_slider.min_value, zoom_slider.max_value)
		zoom_slider.set_value_no_signal(map_zoom)
		queue_redraw()
		
	if active_lasers.size() > 0:
		for i in range(active_lasers.size() - 1, -1, -1):
			active_lasers[i]["age"] += delta
			if active_lasers[i]["age"] > 0.1:
				active_lasers.remove_at(i)
		queue_redraw()

func _draw() -> void:
	var is_ship_oriented = current_state.get("is_ship_oriented", false)
	var center = size / 2.0
	var pos = current_state.get("pos", Vector2.ZERO)
	var rot = current_state.get("rot", 0.0)
	var vel = current_state.get("vel", Vector2.ZERO)
	
	# Transform logic
	var grid_size = WORLD_HALF_EXTENT
	var camera_pos = pos
	
	# Removed old camera clamping: The Foam boundary acts as a physical barrier now,
	# and the grid visually fades into the void, so we want the camera to always
	# perfectly follow the ship into the dark edge without artificially stopping.

	var t = Transform2D()
	t = t.translated(-camera_pos) # 1. Move camera target to origin
	t = t.rotated(Utils.get_map_rotation(is_ship_oriented, rot)) # 2. Rotate around origin if needed
	t = t.scaled(Vector2(map_zoom, map_zoom)) # 3. Scale around origin
	t.origin += center # 4. Shift origin to center of screen

	draw_set_transform_matrix(t)
	
	# Draw background grid (Dynamic scale based on zoom)
	var visible_width_world = size.x / map_zoom
	var ideal_step = visible_width_world / 10.0
	var log_step = log(ideal_step) / log(10.0)
	var pow_step = pow(10.0, floor(log_step))
	var grid_step = pow_step
	if ideal_step > pow_step * 5.0:
		grid_step = pow_step * 5.0
	elif ideal_step > pow_step * 2.0:
		grid_step = pow_step * 2.0
	
	grid_step = max(100.0, grid_step)
	
	if show_grid:
		# Calculate visible bounds (using diagonal to account for rotation)
		var visible_radius = (size.length() / 2.0) / map_zoom
		# Pad the bounding box heavily so the square bounds never rotate into the visible screen
		visible_radius += grid_step * 3.0 
		
		var min_x = max(-grid_size, camera_pos.x - visible_radius)
		var max_x = min(grid_size, camera_pos.x + visible_radius)
		var min_y = max(-grid_size, camera_pos.y - visible_radius)
		var max_y = min(grid_size, camera_pos.y + visible_radius)
		
		var start_x = floor(min_x / grid_step) * grid_step
		var start_y = floor(min_y / grid_step) * grid_step
		
		for x in range(start_x, max_x + grid_step, grid_step):
			if x >= -grid_size and x <= grid_size:
				for y in range(start_y, max_y, grid_step):
					var p1 = Vector2(x, y)
					var p2 = Vector2(x, min(y + grid_step, max_y))
					var mid_len = ((p1 + p2) / 2.0).length()
					var alpha = 1.0
					if mid_len > FOAM_BOUNDARY:
						alpha = max(0.0, 1.0 - (mid_len - FOAM_BOUNDARY) / FOAM_FADE_DIST)
					if alpha > 0.0:
						draw_line(p1, p2, Color(0.1, 0.2, 0.1, alpha), 1.0 / map_zoom)
				
		for y in range(start_y, max_y + grid_step, grid_step):
			if y >= -grid_size and y <= grid_size:
				for x in range(start_x, max_x, grid_step):
					var p1 = Vector2(x, y)
					var p2 = Vector2(min(x + grid_step, max_x), y)
					var mid_len = ((p1 + p2) / 2.0).length()
					var alpha = 1.0
					if mid_len > FOAM_BOUNDARY:
						alpha = max(0.0, 1.0 - (mid_len - FOAM_BOUNDARY) / FOAM_FADE_DIST)
					if alpha > 0.0:
						draw_line(p1, p2, Color(0.1, 0.2, 0.1, alpha), 1.0 / map_zoom)
		
	# Draw origin reference
	draw_circle(Vector2.ZERO, 10.0, Color(0.2, 0.2, 0.5))

	# M35/M46 -- controlled-zone rings + keep-back discs: BACKGROUND terrain,
	# drawn first (right after the grid) so every other element -- own-ship,
	# contacts, lanes, contract markers, lasers -- reads on top of it.
	if show_port_control:
		_draw_controlled_zones(current_state.get("current_port_zone", null), current_state.get("docking_grant", null), current_state.get("departing_slip", {}))

	# Draw velocity vector
	if show_velocity_vectors and vel.length() > 0:
		draw_line(pos, pos + vel * 2.0, Color(0.5, 0.5, 0.0), 2.0 / map_zoom)
		
	# Draw ship rotation indicator
	var forward = Vector2.RIGHT.rotated(rot) * 40.0
	draw_line(pos, pos + forward, Color.CYAN, 2.0 / map_zoom)
	
	# Draw ship blip and physical bounds
	var bounds_radius = current_state.get("bounding_radius", 50.0)
	if bounds_radius * map_zoom > 15.0:
		var has_drawn = false
		
		# Derive true physical outline from engineering components if available
		if current_state.has("engineering") and current_state["engineering"].has("ship_components"):
			var all_pts: PackedVector2Array = PackedVector2Array()
			for c in current_state["engineering"]["ship_components"]:
				var r: Rect2 = c.get("rect", Rect2())
				all_pts.append(r.position)
				all_pts.append(r.position + Vector2(r.size.x, 0))
				all_pts.append(r.position + Vector2(0, r.size.y))
				all_pts.append(r.position + r.size)
				
			if not all_pts.is_empty():
				var hull = Geometry2D.convex_hull(all_pts)
				if not hull.is_empty():
					var world_outline: PackedVector2Array = PackedVector2Array()
					for pt in hull:
						world_outline.append(pos + pt.rotated(rot))
					# Geometry2D.convex_hull usually returns a closed polygon, but ensure it draws nicely
					if world_outline[0] != world_outline[-1]:
						world_outline.append(world_outline[0])
						
					draw_polyline(world_outline, Color.GREEN, 2.0 / map_zoom)
					draw_circle(pos, 3.0 / map_zoom, Color.GREEN)
					has_drawn = true
					
		if not has_drawn:
			# Fallback to AABB if components aren't available
			var aabb = current_state.get("aabb", Rect2(-50, -50, 100, 100))
			var outline_pts = PackedVector2Array([
				pos + aabb.position.rotated(rot),
				pos + (aabb.position + Vector2(aabb.size.x, 0)).rotated(rot),
				pos + (aabb.position + aabb.size).rotated(rot),
				pos + (aabb.position + Vector2(0, aabb.size.y)).rotated(rot),
				pos + aabb.position.rotated(rot)
			])
			draw_polyline(outline_pts, Color.GREEN, 2.0 / map_zoom)
			draw_circle(pos, 3.0 / map_zoom, Color.GREEN)
	else:
		draw_circle(pos, 8.0 / map_zoom, Color.GREEN)
		draw_arc(pos, bounds_radius, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.5), 2.0 / map_zoom)
	
	# Draw weapon firing arcs
	if show_weapon_arcs:
		var weapons = current_state.get("weapons", []) # Array of ship_components weapon entries
		for w in weapons:
			if w.has("range") and w.has("arc_width") and w.has("heading"):
				var r = w["range"]
				var arc_w = w["arc_width"]
				var w_heading = w["heading"]
				var mount_rect = w.get("rect", Rect2())
				var mount_pos = mount_rect.position + mount_rect.size / 2.0
				var global_mount = pos + mount_pos.rotated(rot)
				
				var start_angle = rot + w_heading - arc_w / 2.0
				var end_angle = rot + w_heading + arc_w / 2.0
				var arc_color = Color(1.0, 0.3, 0.0, 0.2) # slightly more transparent
				draw_arc(global_mount, r, start_angle, end_angle, 32, arc_color, 2.0 / map_zoom)
				draw_line(global_mount, global_mount + Vector2(r, 0).rotated(start_angle), arc_color, 1.0 / map_zoom)
				draw_line(global_mount, global_mount + Vector2(r, 0).rotated(end_angle), arc_color, 1.0 / map_zoom)
				
	# Draw sensor arcs and wedges
	if show_sensor_arcs:
		var sensor_config = current_state.get("sensor_config", [])
		for sensor in sensor_config:
			var s_heading = rot + sensor.get("heading", 0.0)
			var s_arc_width = sensor.get("arc_width", TAU)
			var s_range = sensor.get("range", 40000.0)
			
			if s_arc_width >= TAU - 0.01:
				draw_arc(pos, s_range, 0, TAU, 64, Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
			else:
				var s_start = s_heading - (s_arc_width / 2.0)
				var s_end = s_heading + (s_arc_width / 2.0)
				draw_arc(pos, s_range, s_start, s_end, 32, Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				draw_line(pos, pos + Vector2(s_range, 0).rotated(s_start), Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				draw_line(pos, pos + Vector2(s_range, 0).rotated(s_end), Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				
		var sensors_dict = current_state.get("sensors", {})
		for sensor_id in sensors_dict.keys():
			var bins = sensors_dict[sensor_id]
			if bins.size() == 0: continue
			
			var s_heading = bins[0].get("sensor_heading", 0.0)
			var s_arc_width = bins[0].get("sensor_arc_width", TAU)
			var bin_angle = bins[0].get("bin_angle", TAU/36.0)
			
			var s_start_angle = s_heading - (s_arc_width / 2.0)
			for sig in bins:
				var b_idx = sig.get("bin_idx", 0)
				var b_start = s_start_angle + (b_idx * bin_angle)
				var b_end = b_start + bin_angle

				var dist = sig.get("distance", 0.0)
				var b_center = (b_start + b_end) / 2.0
				var dot_pos = pos + Vector2(dist, 0).rotated(b_center)

				draw_circle(dot_pos, 4.0 / map_zoom, Color.CYAN)

		# One more sensor-range ring: comms range, folded into the Sensor Arcs
		# toggle rather than its own checkbox (it's just another range line).
		var comms_range: float = current_state.get("comms_range", 0.0)
		if comms_range > 0.0:
			draw_arc(pos, comms_range, 0, TAU, 64, Color(0.8, 0.4, 1.0, 0.4), 2.0 / map_zoom)

	# M41 -- GO_TO_AREA search rings, drawn under contacts (a search-area ring
	# the player is standing inside should never occlude a real contact
	# sitting on it). Zone rings/discs draw even earlier -- see the
	# _draw_controlled_zones call right after the grid above.
	var contracts: Array = current_state.get("contracts", [])
	_draw_contract_rings(contracts)

	# F9 omniscience overlay -- every cluster entity (all Kinds), styled per
	# DEBUG_ENTITY_STYLE above. Two passes: background kinds (asteroids/
	# beacons) first, then foreground kinds (stations/wormhole/traffic/
	# player) -- keeps the numerous small asteroid markers from drawing over
	# the more important ship/station ones. The whole overlay still draws
	# here, before (under) the real contacts loop below, per the "a debug
	# overlay must never occlude a real contact" rule.
	var debug_entities: Array = current_state.get("debug_entities", [])
	for want_background in [true, false]:
		for entity in debug_entities:
			var kind: int = entity.get("kind", ClusterEntity.Kind.TRAFFIC)
			var is_background: bool = kind in DEBUG_ENTITY_BACKGROUND_KINDS
			if is_background != want_background:
				continue
			var style: Dictionary = DEBUG_ENTITY_STYLE.get(kind, DEBUG_ENTITY_STYLE[ClusterEntity.Kind.TRAFFIC])
			var e_pos: Vector2 = entity.get("pos", Vector2.ZERO)
			# Note: We must divide by map_zoom because draw_circle operates in
			# world space, and the camera transform scales everything down
			# when zoomed out.
			var r: float = style["radius"] / map_zoom
			draw_circle(e_pos, r, style["color"])
			draw_arc(e_pos, r, 0, TAU, 16, style["border"], 2.0 / map_zoom)

	# Draw Contacts
	var contacts = current_state.get("contacts", {})
	for c_id in contacts.keys():
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		var color = _get_contact_color(c)
		var cross_section = c.get("signature", {}).get("cross_section", 0.0)
		var screen_radius = (cross_section / 2.0) * map_zoom

		# v1.1: blip and outline are ONE footprint channel -- the bubble
		# crossfades out exactly as the resolved shape fades in, so closing on
		# a contact reads as refining its footprint, not gaining a second
		# overlay (ship_outline_rendering.md "first-playtest revision").
		var outline_a: float = _outline_alpha_for(c, c_pos)
		if outline_a < 1.0:
			var blip_color := Color(color.r, color.g, color.b, color.a * (1.0 - outline_a))
			if screen_radius > 15.0:
				# Draw the radar cross section circle when zoomed in enough
				draw_arc(c_pos, cross_section / 2.0, 0, TAU, 16, blip_color, 2.0 / map_zoom)
			else:
				# Just draw a solid blip
				draw_circle(c_pos, 8.0 / map_zoom, blip_color)

		# Draw velocity vector (full color -- velocity knowledge doesn't fade
		# with the footprint refinement)
		if show_velocity_vectors and c.get("vel", Vector2.ZERO).length() > 0:
			draw_line(c_pos, c_pos + c.get("vel", Vector2.ZERO) * 2.0, color, 1.0 / map_zoom)

		_draw_contact_outline(c, c_pos, outline_a)

	# Contact labels are drawn later, after the transform reset below --
	# world-space text would scale with map_zoom otherwise.

	# M41 -- contract PIN markers draw on top of contacts (unlike the ring
	# above) so a mission marker never gets lost under a dense sensor picture.
	_draw_contract_pins(contracts)

	# The M34 berth marker/lane are ARRIVAL aids ("fly here to dock") -- keyed
	# on a live grant only, NOT departing_slip. Departure keeps the CHANNEL
	# open (_draw_controlled_zones, above/below) so there's a legal path back
	# out, but not the marker/lane -- once released you already know where
	# the berth is; "you can see yourself out." Gated by the same "Port
	# Control" toggle as the zone/channel drawing above.
	if show_port_control:
		_draw_docking_nav_aids(current_state.get("docking_grant", null))

	# Draw active lasers
	for laser in active_lasers:
		var alpha = max(0.0, 1.0 - (laser["age"] / 0.1))
		draw_line(laser["start"], laser["end"], Color(1.0, 0.2, 0.2, alpha), 2.0 / map_zoom)

	# Draw HUD overlay (Reset Transform)
	draw_set_transform_matrix(Transform2D())
	
	var selected_id = current_state.get("selected_contact_id", "")
	
	if show_contact_labels or selected_id != "":
		var font = ThemeDB.fallback_font
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var c_pos = c.get("pos", Vector2.ZERO)
			var screen_pos = t.basis_xform(c_pos) + t.origin
			var color = _get_contact_color(c)
			
			if show_contact_labels:
				var display_name = c.get("name", c_id)
				draw_string(font, screen_pos + Vector2(10, 10), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
				
			if c_id == selected_id:
				_draw_selection_bracket(screen_pos, Color.WHITE)

				# Draw telemetry
				var s_pos = current_state.get("pos", Vector2.ZERO)
				var dist = s_pos.distance_to(c_pos)
				var rel_pos = c_pos - s_pos
				var rel_vel = c.get("vel", Vector2.ZERO) - current_state.get("vel", Vector2.ZERO)
				var closing_vel = 0.0
				if rel_pos.length() > 0.001:
					closing_vel = -rel_pos.normalized().dot(rel_vel)
					
				var info_text = "Dist: %s\nCls: %.1f m/s" % [Utils.format_dist(dist), closing_vel]
				if not show_contact_labels:
					info_text = c_id + "\n" + info_text
					
				var text_y = screen_pos.y + (24.0 if show_contact_labels else 10.0)
				for line in info_text.split("\n"):
					draw_string(font, Vector2(screen_pos.x + 10, text_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
					text_y += 12.0
	
	# Scale Reference
	if show_grid:
		var scale_text = "Grid: %s" % Utils.format_dist(grid_step)
		var scale_font = ThemeDB.fallback_font
		var scale_text_size = scale_font.get_string_size(scale_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14)
		
		var ref_len = grid_step * map_zoom
		var bottom_right = size - Vector2(20, 20)
		
		# Draw line
		draw_line(bottom_right - Vector2(ref_len, 0), bottom_right, Color.WHITE, 2.0)
		# Draw tick marks
		draw_line(bottom_right - Vector2(ref_len, 5), bottom_right - Vector2(ref_len, -5), Color.WHITE, 2.0)
		draw_line(bottom_right - Vector2(0, 5), bottom_right - Vector2(0, -5), Color.WHITE, 2.0)
		
		# Draw text centered above the line
		var scale_text_pos = bottom_right - Vector2(ref_len / 2.0 + scale_text_size.x / 2.0, 10)
		draw_string(scale_font, scale_text_pos, scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)



	# Reset transform to draw absolute overlays (UI, Compass)
	draw_set_transform_matrix(Transform2D())
	
	# Draw Compass Ring
	var compass_radius = min(size.x, size.y) / 2.0 - 40.0
	draw_arc(center, compass_radius, 0, PI*2, 64, Color(0.0, 0.5, 0.0, 0.3), 2.0)
	
	var map_rot = Utils.get_map_rotation(is_ship_oriented, rot)

	var font = ThemeDB.fallback_font
	var font_size = 14

	for i in range(0, 360, 30):
		var draw_angle = deg_to_rad(i - 90.0) + map_rot

		var dir = Vector2.RIGHT.rotated(draw_angle)
		var p1 = center + dir * compass_radius
		var p2 = center + dir * (compass_radius + 10.0)

		var style = Utils.compass_tick_style(i)
		draw_line(p1, p2, style["color"], style["width"])

		var text_pos = center + dir * (compass_radius + 25.0)
		var text = Utils.compass_label_text(i)

		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, text_pos - text_size / 2.0 + Vector2(0, font_size / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, style["color"])
	
	# Draw telemetry text
	var default_font_size = 16
	draw_string(font, Vector2(10, size.y - 40), "X: %.2f Y: %.2f" % [pos.x, pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, Color.GREEN)
	draw_string(font, Vector2(10, size.y - 20), "SPD: %.2f HDG: %.2f" % [vel.length(), wrapf(rad_to_deg(rot) + 90.0, 0.0, 360.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, Color.GREEN)

	# Draw Pinned Contact Off-screen Indicators
	var pinned_contacts = current_state.get("pinned_contacts", []).duplicate()
	if selected_id != "" and not pinned_contacts.has(selected_id):
		pinned_contacts.append(selected_id)
		
	var rect = Rect2(Vector2.ZERO, size)
	var margin = 30.0
	var safe_rect = rect.grow(-margin)
	
	for c_id in pinned_contacts:
		if not contacts.has(c_id): continue
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)

		# Transform world pos to screen pos manually
		var screen_pos = t.basis_xform(c_pos) + t.origin

		var geo = edge_arrow_geometry(screen_pos, center, size, margin)
		if geo != null:
			var display_name = c.get("name", c_id)
			_draw_offscreen_indicator(geo["edge_pos"], geo["dir"], _get_contact_color(c), display_name, font)

	# M41 -- contract markers reuse the SAME off-screen edge-arrow affordance
	# as pinned contacts above (edge_arrow_geometry), own color (CONTRACT_COLOR)
	# so nav knowledge reads distinct from sensor knowledge. Entries with
	# pos == null (e.g. TALK_TO Todd -- no known position, finding him IS the
	# gameplay) are skipped here entirely; they're still listed in the
	# contacts/comms panels, just never drawn on the map.
	var selected_contract_id: String = current_state.get("selected_contract_id", "")
	for entry in contracts:
		var c_pos = entry.get("pos", null)
		if c_pos == null:
			continue
		var title: String = entry.get("title", "")
		var screen_pos = t.basis_xform(c_pos) + t.origin

		if entry.get("id", "") == selected_contract_id and selected_contract_id != "":
			_draw_selection_bracket(screen_pos, CONTRACT_COLOR)

		var geo = edge_arrow_geometry(screen_pos, center, size, margin)
		if geo != null:
			_draw_offscreen_indicator(geo["edge_pos"], geo["dir"], CONTRACT_COLOR, title, font)
		else:
			# On-screen: always label (there are at most a couple active
			# objectives at once, unlike the dense sensor picture
			# show_contact_labels gates against).
			var text_size = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(font, screen_pos + Vector2(10, -10 - text_size.y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CONTRACT_COLOR)

	# M52 -- SOS markers removed as a special case (implementation_plans/
	# m52_sos_as_contact.md item 7): a "DISTRESS CALL"-classified contact now
	# flows through the SAME generic per-contact drawing path every other
	# contact already uses (_get_contact_color -> Utils.classification_color),
	# blip/label/off-screen-arrow all already generic -- no bespoke pulsing-
	# cross marker or NAV-layer packet["sos"] channel needed anymore.

# Draws the four-corner white-bracket "selected" highlight around a screen
# position -- factored out of the contact-selection code above (M41) so
# contract-marker selection can reuse the identical visual treatment (own
# color) instead of a second hand-copied set of draw_line calls.
func _draw_selection_bracket(screen_pos: Vector2, color: Color) -> void:
	var b_size = 15.0
	draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size/2, -b_size), color, 2.0)
	draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size, -b_size/2), color, 2.0)

	draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size/2, -b_size), color, 2.0)
	draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size, -b_size/2), color, 2.0)

	draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size/2, b_size), color, 2.0)
	draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size, b_size/2), color, 2.0)

	draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size/2, b_size), color, 2.0)
	draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size, b_size/2), color, 2.0)

# Draws the off-screen "dorito" arrow + label at an edge point, given the
# geometry edge_arrow_geometry() computed -- factored out of the original
# inline pinned-contacts drawing (M41) so contract markers reuse it exactly.
func _draw_offscreen_indicator(edge_pos: Vector2, dir_to_contact: Vector2, color: Color, label: String, font: Font) -> void:
	var p_tip = edge_pos + dir_to_contact * 10.0
	var p_left = edge_pos + dir_to_contact.rotated(PI * 0.8) * 10.0
	var p_right = edge_pos + dir_to_contact.rotated(-PI * 0.8) * 10.0

	var pts = PackedVector2Array([p_tip, p_left, p_right])
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([p_tip, p_left, p_right, p_tip]), color, 2.0)

	if label == "":
		return
	var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
	var label_pos = edge_pos - dir_to_contact * 15.0 - Vector2(text_size.x/2.0, -text_size.y/3.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)

func _get_contact_color(c: Dictionary) -> Color:
	# Dim by confidence-from-age so stale dead-reckoned contacts fade toward ghosts
	# instead of reading as solid as freshly-measured ones. Every blip/label/vector/
	# off-screen-indicator path goes through here, so they all inherit the fade.
	var base = Utils.classification_color(c.get("classification", ""))
	return Utils.fade_color(base, Utils.contact_confidence(c))

# v1.1: the outline is a REFINED FOOTPRINT -- the same knowledge channel as
# the blip, not extra intel. This helper computes how far along that
# refinement is [0..1]; the contact loop draws the blip at (1 - this) and the
# outline at (this), so the bubble crossfades OUT as the shape fades IN.
# Returns 0 when there is nothing to refine INTO (no silhouette resolvable
# for a friendly; no/few dots yet for a hostile -- dots ramp the fade by
# coverage so a two-dot contact doesn't lose its bubble).
func _outline_alpha_for(contact: Dictionary, c_pos: Vector2) -> float:
	var bounds_radius: float = _bounds_radius_for(contact)
	if bounds_radius * map_zoom < OUTLINE_LOD_MIN_PX:
		return 0.0

	# Size-proportional window (see OUTLINE_START_RADII comment).
	var full: float = OUTLINE_FULL_RADII * bounds_radius
	var start: float = OUTLINE_START_RADII * bounds_radius

	var self_pos: Vector2 = current_state.get("pos", Vector2.ZERO)
	var dist: float = self_pos.distance_to(c_pos)
	var alpha: float = outline_alpha(dist, full, start)
	if alpha <= 0.0:
		return 0.0

	if _is_simple_body(contact):
		# An asteroid (or any non-ship body) has no component rects, but its
		# true shape IS its bounding circle -- the refined footprint is just
		# that circle (a seeded rocky blob), always drawable.
		return alpha
	if _sensor_dots_enabled() and not _is_friendly_contact(contact):
		# Measured-dot outline for an unidentified/hostile contact: ramp the
		# fade by how many dots we've accrued so a two-dot contact keeps its
		# bubble.
		var dots = contact.get("outline_dots", [])
		var dot_count: int = dots.size() if dots is Array else 0
		return alpha * clampf(dot_count / 16.0, 0.0, 1.0)
	# Friendly, OR the dot sampler is off (fallback) -- the authoritative cached
	# silhouette, resolvable for any ship we can currently see.
	return alpha if not _outline_draw_list(contact).is_empty() else 0.0

# A live instance with real bounds but NO ship_components -- an asteroid or
# similar simple obstacle. Its outline is a rocky blob sized to its bounding
# circle (see _rock_outline); ships (including dead hulks, which keep their
# rects) never take this path.
static func _is_simple_body(contact: Dictionary) -> bool:
	var instance_id: int = contact.get("instance_id", -1)
	if instance_id == -1:
		return false
	var inst = instance_from_id(instance_id)
	if inst == null or not is_instance_valid(inst):
		return false
	return inst.get("ship_components") == null and inst.has_method("get_bounding_radius")

# A perfectly round circle reads as a UI artifact, not a rock -- so simple
# bodies get a deterministic jagged polygon instead. Seeded (from the rock's
# static position, stable across bubble promote/demote cycles) so the same
# asteroid always shows the same face and never shimmers frame to frame.
# Vertex radii hug the TRUE bounding circle (0.88-1.08 x) -- rocky to look at,
# but never under-representing the collision extent by more than ~12%, and
# just as often over-warning, which is the safe direction for navigation.
static var _rock_outline_cache: Dictionary = {}

static func _rock_outline(seed_val: int, radius: float) -> PackedVector2Array:
	var key := "%d_%d" % [seed_val, int(radius)]
	if _rock_outline_cache.has(key):
		return _rock_outline_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var n: int = 9 + rng.randi_range(0, 4)
	var pts := PackedVector2Array()
	for i in range(n):
		var ang: float = TAU * float(i) / float(n) + rng.randf_range(-0.12, 0.12)
		var r: float = radius * rng.randf_range(0.88, 1.08)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	_rock_outline_cache[key] = pts
	return pts

# Thin rendering wrapper (math lives in the pure/static helpers above).
# Demotion rule (M26): identified friendlies get the true SILHOUETTE
# (_outline_draw_list -- union contour only, v1.1, no per-component boxes);
# hostile/unidentified contacts get ONLY measured sensor dots. Both draw in
# the CONTACT's color -- the refinement never changes the color story the
# blip already told. Called inside the world-space transform, same as the
# rest of the per-contact drawing.
func _draw_contact_outline(contact: Dictionary, c_pos: Vector2, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var base_color: Color = _get_contact_color(contact)
	var draw_color := Color(base_color.r, base_color.g, base_color.b, base_color.a * alpha)

	if _is_simple_body(contact):
		# Asteroid/simple body: a seeded rocky blob at its true bounding
		# radius -- the collision extent a rock field actually threatens,
		# without the perfect-circle UI-artifact look. Rotates with the body
		# (rocks tumble slowly).
		var inst = instance_from_id(contact.get("instance_id", -1))
		if inst != null and is_instance_valid(inst):
			var true_pos: Vector2 = inst.get("position") if inst.get("position") != null else Vector2.ZERO
			# Quantized to a 64u grid: stable across bubble promote/demote AND
			# under small collision-drift (a big shove may re-roll the face --
			# acceptable, rare).
			var seed_val: int = hash(Vector2i(int(floor(true_pos.x / 64.0)), int(floor(true_pos.y / 64.0))))
			var rock_pts: PackedVector2Array = _rock_outline(seed_val, _bounds_radius_for(contact))
			var rot: float = inst.get("rotation") if inst.get("rotation") != null else 0.0
			var poly := PackedVector2Array()
			for p in rock_pts:
				poly.append(c_pos + p.rotated(rot))
			poly.append(poly[0])
			draw_polyline(poly, draw_color, 1.5 / map_zoom)
	elif _sensor_dots_enabled() and not _is_friendly_contact(contact):
		# Dot sampler ON + unidentified/hostile: draw the MEASURED dots.
		for pt in _dot_draw_list(contact, c_pos):
			draw_circle(pt, OUTLINE_DOT_RADIUS_PX / map_zoom, draw_color)
	else:
		# Friendly, OR dot sampler off (fallback): the authoritative silhouette.
		for entry in _outline_draw_list(contact):
			var pts_local: PackedVector2Array = entry["points"]
			var rot: float = entry["rotation"]
			if pts_local.size() < 2:
				continue
			# Anchor to c_pos (the contact's DRAWN position) -- the outline
			# rides the blip; truth supplies only shape + rotation (M25 rule).
			var poly := PackedVector2Array()
			for p in pts_local:
				poly.append(c_pos + p.rotated(rot))
			poly.append(poly[0])
			draw_polyline(poly, draw_color, 1.5 / map_zoom)

# M46 -- control rings + exclusion discs for EVERY controlled station on
# screen (design_ideas/port_zones_and_channels.md "Visibility"), replacing
# M35's inside-only _draw_zone_boundary rule. `current_authority` is the
# packet's current_port_zone (authority-name String or null, see M35's
# packet-field comment on main.gd) -- the zone the player is inside draws
# emphasized (ZONE_BOUNDARY_COLOR / EXCLUSION_DISC_COLOR), every other
# controlled station's ring/disc draws dimmed. `grant` is the packet's
# docking_grant (or null) -- when it names a specific slip (slip_id != "") at
# the station currently being drawn, that station's exclusion disc gets a
# channel cutout to the assigned berth (see PortChannel); an any-open grant
# (slip_id == "") opens no channel, per roadmap scope.
#
# Scans the "ships" group same as _station_for_authority/_draw_docking_nav_aids
# -- a handful of controlled stations on screen, not hundreds, so this is
# trivially bounded per the same cardinality note those functions already
# make.
func _draw_controlled_zones(current_authority, grant, departing_slip: Dictionary = {}) -> void:
	# Knowledge gating: a port zone is COMMS knowledge (the authority
	# broadcasts its boundaries), so it only draws while the player and the
	# station are in mutual comms range -- same weaker-of-the-two-ranges rule
	# the datalink uses (ship.gd's relay block). Without this, every
	# controlled station in the loaded cluster drew its rings map-wide.
	var player_pos: Vector2 = current_state.get("pos", Vector2.ZERO)
	var player_comms: float = current_state.get("comms_range", 0.0)
	if player_comms <= 0.0:
		return
	# The DOCKING POINT (design_ideas terminology: "the exact spot the clamp
	# tries to hold you") is the clearance-adjusted seat
	# (DockingBay.berth_pos_for_bounding_radius), not the raw authored bay
	# position -- same fix as the M34 marker/lane, needed here too for the
	# guide's exact endpoint math (its angle is unaffected either way, since
	# the standoff only moves the seat along the same axis, but its length
	# is not).
	var player_radius: float = current_state.get("bounding_radius", 50.0)

	for s in get_tree().get_nodes_in_group("ships"):
		if not s.has_method("get_port_zone"):
			continue
		var zone: Dictionary = s.get_port_zone()
		if zone.is_empty():
			continue
		var radius: float = zone.get("radius", 0.0)
		if radius <= 0.0:
			continue
		if not zone_boundary_visible(radius, map_zoom):
			continue

		var link_range: float = min(player_comms, s.get_comms_range() if s.has_method("get_comms_range") else 0.0)
		if player_pos.distance_to(s.global_position) > link_range:
			continue

		var authority: String = zone.get("authority", "")
		var emphasized: bool = authority != "" and authority == current_authority
		var ring_color: Color = ZONE_BOUNDARY_COLOR if emphasized else ZONE_BOUNDARY_DIM_COLOR
		var disc_color: Color = EXCLUSION_DISC_COLOR if emphasized else EXCLUSION_DISC_DIM_COLOR
		draw_arc(s.global_position, radius, 0, TAU, 64, ring_color, ZONE_RING_WIDTH / map_zoom)

		var exclusion_radius: float = float(zone.get("exclusion_radius", 0.0))
		if exclusion_radius <= 0.0:
			continue

		# Channel: open for a live grant with a specific slip AT THIS station
		# (any-open grants -- slip_id "" -- have no single berth to align a
		# cone to, per roadmap scope), OR for departing_slip -- a ship that
		# JUST released from this station keeps its exit channel drawn until
		# it actually clears the disc (see ship.gd's departing_slip comment;
		# without this the channel slammed shut the instant a grant was
		# consumed on release, even while the ship was still deep inside).
		# Either source normalizes to the same {"authority","slip_id"} shape
		# assigned_bay_for() already reads.
		var channel_slip: Dictionary = {}
		if grant != null and grant.get("authority", "") == authority and authority != "" and grant.get("slip_id", "") != "":
			channel_slip = grant
		elif departing_slip.get("authority", "") == authority and authority != "" and departing_slip.get("slip_id", "") != "":
			channel_slip = departing_slip

		var channel_polygon := PackedVector2Array()
		var theta0: float = NAN
		var bay_node: Node = null
		if not channel_slip.is_empty():
			bay_node = _assigned_bay_for_station(s, channel_slip)
			if bay_node != null:
				theta0 = PortChannel.axis_angle(bay_node.global_position, bay_node.global_rotation, s.global_position, exclusion_radius)
				if not is_nan(theta0):
					# The hatch cut reaches the HULL -- the corridor's whole
					# job is to connect the exclusion boundary down to the
					# capture zone at the docking point, and the docking
					# point itself sits close to the hull.
					channel_polygon = PortChannel.sector_polygon(s.global_position, theta0, s.get_bounding_radius(), exclusion_radius)

		var has_channel: bool = not is_nan(theta0)

		# The exclusion boundary ring: full circle normally; when the
		# corridor is open, it gaps over the cone's angular span ("gaps open
		# when berth assigned"). There is no second inner ring -- the hatch
		# fill's inner bound is just the hull (see _draw_exclusion_hatch).
		_draw_gappable_ring(s.global_position, exclusion_radius, theta0, disc_color, has_channel)

		_draw_exclusion_hatch(s, exclusion_radius, disc_color, channel_polygon)

		if has_channel and bay_node != null:
			# Radial corridor edges: SUBDUED like the rest of the exclusion
			# zone (this is still zone/background geometry -- "here's the
			# legal corridor through the wall"). Inner bound is the hull,
			# matching the hatch cutout above (no separate inner ring).
			var edges: Array = PortChannel.lane_edges(s.global_position, theta0, s.get_bounding_radius(), exclusion_radius)
			for edge in edges:
				draw_line(edge[0], edge[1], CHANNEL_EDGE_COLOR, ZONE_RING_WIDTH / map_zoom)

			# The guide: a line down the corridor's center, from the mouth
			# (where the corridor crosses the exclusion boundary) to wherever
			# it enters the capture zone -- past that point the clamp's own
			# reach takes over, so the corridor's job is done. An earlier
			# version of this ended in a diamond at min(bay.capture_radius,
			# distance-to-mouth), removed when capture_radius still defaulted
			# to 5000u (always collapsing to the mouth, landing nowhere near
			# the berth). Safe to bring back now that capture_radius is
			# bounded -- and now that the capture zone itself is drawn
			# (_draw_docking_nav_aids), the guide's endpoint is finally
			# self-explanatory instead of an unexplained stop partway out.
			# The guide's job is getting you TO the capture zone -- once the
			# clamp actually has you (DOCKED) there's nothing left to steer
			# toward, so it goes away rather than sitting drawn over a ship
			# that's already stopped moving.
			if bay_node.state != DockingBay.State.DOCKED:
				var docking_point: Vector2 = bay_node.berth_pos_for_bounding_radius(player_radius)
				var guide: Dictionary = PortChannel.guide_segment(docking_point, bay_node.global_rotation, s.global_position, exclusion_radius, bay_node.capture_radius)
				if not guide.is_empty():
					draw_line(guide["mouth"], guide["engage"], CHANNEL_EDGE_COLOR, (ZONE_RING_WIDTH * 1.3) / map_zoom)

# One keep-back circle: a full ring, or -- while the docking cone is open --
# an arc leaving the cone's [theta0 - half, theta0 + half] span open.
func _draw_gappable_ring(center: Vector2, r: float, theta0: float, color: Color, gapped: bool) -> void:
	if gapped and not is_nan(theta0):
		draw_arc(center, r, theta0 + PortChannel.CONE_HALF_ANGLE, theta0 - PortChannel.CONE_HALF_ANGLE + TAU, 48, color, ZONE_RING_WIDTH / map_zoom)
	else:
		draw_arc(center, r, 0, TAU, 64, color, ZONE_RING_WIDTH / map_zoom)

# M46 -- resolves the DockingBay this grant is assigned to AT a specific
# station (as opposed to _draw_docking_nav_aids' version, which first has to
# find the station FROM the grant's authority -- here the caller already
# knows the station, since it's iterating every controlled station). Same
# "docking_bays" group + parent-match pattern as _draw_docking_nav_aids.
func _assigned_bay_for_station(station: Node, grant) -> Node:
	var bays: Array = []
	for b in get_tree().get_nodes_in_group("docking_bays"):
		if b.get_parent() == station:
			bays.append(b)
	if bays.is_empty():
		return null
	return assigned_bay_for(bays, grant)

# M46 (revised) -- one station's exclusion-zone hatching, filled (not
# stroked) diagonal stripes computed by ExclusionHatch via Geometry2D polygon
# boolean ops (see that file's header for why: generic boundary-clipping
# instead of per-boundary ray/circle math). Hatched from the station's own
# hull bounding radius (a pure visual choice -- don't hatch on top of the
# hull's own drawing, no separate policy boundary) out to exclusion_radius.
# `channel_polygon`, when non-empty, is subtracted the same way as the hull,
# so the open docking corridor reads as a clean cut through the hatching
# with no extra logic here.
func _draw_exclusion_hatch(station: Node, exclusion_radius: float, color: Color, channel_polygon: PackedVector2Array) -> void:
	var inner_radius: float = station.get_bounding_radius()
	if exclusion_radius <= inner_radius:
		return # station's own hull already fills (or exceeds) the disc -- nothing to hatch

	var fragments: Array = ExclusionHatch.hatch_fragments(
		station.global_position, exclusion_radius, inner_radius,
		EXCLUSION_HATCH_SPACING, EXCLUSION_HATCH_STRIPE_WIDTH, channel_polygon)
	for frag in fragments:
		draw_colored_polygon(frag, color)

# M41 -- GO_TO_AREA search-area rings, one per contract entry whose kind is
# GO_TO_AREA and radius > 0.0 (contract_feed.gd only sets a radius for that
# kind). Called inside the world-space transform, same convention as every
# other per-contact draw call in this file. DASHED, not a solid ring like the
# zone boundary above, so a search area reads distinctly from "controlled
# space" even though both use the gold/amber family.
func _draw_contract_rings(contracts: Array) -> void:
	for entry in contracts:
		if entry.get("kind", "") != "GO_TO_AREA":
			continue
		var c_pos = entry.get("pos", null)
		var radius: float = entry.get("radius", 0.0)
		if c_pos == null or radius <= 0.0:
			continue
		_draw_dashed_circle(c_pos, radius, CONTRACT_RING_COLOR, 2.0 / map_zoom)

# Manual dashed ring: draw_arc has no native dash support, so step around the
# circle in CONTRACT_DASH_LEN-world-unit arcs separated by CONTRACT_GAP_LEN-
# world-unit gaps. Dash/gap lengths are WORLD units (the dash rhythm holds
# steady across zoom); only the stroke `width` follows this file's constant-
# screen-width convention (divided by map_zoom by the caller).
func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	if radius <= 0.0:
		return
	var dash_angle: float = CONTRACT_DASH_LEN / radius
	var gap_angle: float = CONTRACT_GAP_LEN / radius
	var step: float = dash_angle + gap_angle
	if step <= 0.0:
		return
	var angle: float = 0.0
	while angle < TAU:
		var seg_end: float = min(angle + dash_angle, TAU)
		draw_arc(center, radius, angle, seg_end, 8, color, width)
		angle += step

# M41 -- contract PIN markers: a small diamond at every contract entry's pos
# (entries with pos == null draw nothing here -- e.g. TALK_TO Todd; they're
# still listed in the contacts/comms panels, just not on the map). Drawn
# in-world so it scales/tracks like every other map marker; the off-screen
# edge-arrow case is handled separately in the screen-space overlay section
# of _draw() (mirrors how contact blips vs. pinned-contact arrows split
# between the world-space and screen-space passes).
func _draw_contract_pins(contracts: Array) -> void:
	for entry in contracts:
		var c_pos = entry.get("pos", null)
		if c_pos == null:
			continue
		_draw_contract_pin(c_pos)

func _draw_contract_pin(p: Vector2) -> void:
	var r: float = CONTRACT_MARKER_RADIUS_PX / map_zoom
	var diamond := PackedVector2Array([
		p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)
	])
	draw_polyline(diamond, CONTRACT_COLOR, 2.0 / map_zoom)
	draw_circle(p, r * 0.35, CONTRACT_COLOR)

# M34 -- resolves the docking-grant nav aids (assigned-slip highlight + lane)
# from the packet's docking_grant and live DockingBay nodes, then draws them.
# Called inside the world-space transform (draw_set_transform_matrix is
# already set by the caller -- see _draw()), so every draw_* call here uses
# raw world coordinates, same convention as every other per-contact draw call
# in this file (no second screen-space conversion).
#
# Bay poses are never serialized through the packet -- they're resolved live
# via the "docking_bays" group (registered by DockingBay._enter_tree, see
# scripts/docking/docking_bay.gd:64), matching the existing instance_from_id/
# group-lookup pattern this project already uses for host/client-in-one-
# process node resolution (docking_control.gd's target_station, comms_panel's
# NPC resolution) rather than growing the packet with berth transforms that
# would just be re-deriving live node state.
func _draw_docking_nav_aids(grant) -> void:
	if grant == null:
		return
	var authority: String = grant.get("authority", "")
	if authority == "":
		return

	# Find the controlled station that issued this grant (stations live in the
	# "ships" group too -- same scan Ship._update_port_zone_membership and
	# issue_docking_grant's reserved-slip check already use).
	var station: Node = null
	for s in get_tree().get_nodes_in_group("ships"):
		if not s.has_method("get_port_zone"):
			continue
		var zone: Dictionary = s.get_port_zone()
		if zone.get("authority", "") == authority:
			station = s
			break
	if station == null:
		return

	var bays: Array = []
	for b in get_tree().get_nodes_in_group("docking_bays"):
		if b.get_parent() == station:
			bays.append(b)
	if bays.is_empty():
		return

	# Marker/lane positions must use the CLEARANCE-ADJUSTED seat
	# (DockingBay.berth_pos_for_bounding_radius), not the raw authored
	# global_position -- for a berth mounted close to a large hull the two
	# differ by hundreds of units, and the raw position can sit inside the
	# station's own footprint (the "ring is half inside the station" bug).
	# Keyed on the PLAYER's own bounding_radius since that's whose approach
	# this aid illustrates; already on the packet (see the own-ship bounds
	# read near the top of _draw()).
	var player_radius: float = current_state.get("bounding_radius", 50.0)

	var assigned: Node = assigned_bay_for(bays, grant)
	if assigned != null:
		var docking_point: Vector2 = assigned.berth_pos_for_bounding_radius(player_radius)

		# The capture zone (design_ideas terminology: "a wide circle...
		# centered on the docking point... the only area the docking clamp
		# applies") -- drawn for the assigned bay only, BEFORE the marker/
		# lane so those precision aids read on top of it, not the other way
		# around. Only while there's still something to reach for: once
		# DOCKED the clamp already has the ship, so the reach circle would
		# just be clutter sitting over a ship that isn't going anywhere.
		if assigned.state != DockingBay.State.DOCKED:
			draw_arc(docking_point, assigned.capture_radius, 0, TAU, 48, CAPTURE_ZONE_COLOR, ZONE_RING_WIDTH / map_zoom)

		# Specific slip: THAT bay bright/authority-colored, every other slip at
		# this station dimmed -- and draw the one lane down to it.
		for b in bays:
			_draw_slip_marker(b, b.berth_pos_for_bounding_radius(player_radius), b == assigned)
		_draw_lane(docking_point, assigned.global_rotation)
	else:
		# Any-open grant (slip_id == "") -- highlight ALL open slips equally,
		# no single lane (nothing specific to line up on; roadmap M34 scope).
		var open_bays: Array = open_bays_for(bays)
		var open_set := {}
		for b in open_bays:
			open_set[b] = true
		for b in bays:
			_draw_slip_marker(b, b.berth_pos_for_bounding_radius(player_radius), open_set.has(b))

func _draw_slip_marker(bay: Node, berth_pos: Vector2, highlighted: bool) -> void:
	if not highlighted:
		return # dim per-slip rings were redundant with the capture zone circle -- dropped
	# The docking point itself: a small solid dot, not a to-scale ring at
	# pos_tolerance -- that ring duplicated the (now-drawn) capture zone
	# circle without adding information ("the dark yellow circle is now
	# redundant"). This dot is the precise answer to "where exactly does the
	# clamp hold me", kept through capture/dock rather than fading with the
	# capture zone -- it's still meaningful to see once docked.
	var r: float = max(bay.pos_tolerance, 1.0) * 0.35
	draw_circle(berth_pos, r, SLIP_HIGHLIGHT_COLOR)

func _draw_lane(berth_pos: Vector2, berth_heading: float) -> void:
	var lane: Dictionary = lane_corridor(berth_pos, berth_heading, LANE_LENGTH, LANE_HALF_WIDTH)
	var centerline: PackedVector2Array = lane.get("centerline", PackedVector2Array())
	var left_edge: PackedVector2Array = lane.get("left_edge", PackedVector2Array())
	var right_edge: PackedVector2Array = lane.get("right_edge", PackedVector2Array())
	if centerline.size() < 2:
		return
	draw_polyline(centerline, LANE_CENTERLINE_COLOR, 2.0 / map_zoom)
	draw_polyline(left_edge, LANE_EDGE_COLOR, 1.0 / map_zoom)
	draw_polyline(right_edge, LANE_EDGE_COLOR, 1.0 / map_zoom)
