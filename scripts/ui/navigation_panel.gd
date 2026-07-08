extends Control

signal contact_selected(c_id: String)

const ComponentSpec = preload("res://scripts/components/component_spec.gd")

const WORLD_HALF_EXTENT := 260000.0 # map clamps the camera/grid to +/- this on each axis -- matches the home cluster's +/-250k bounds with margin

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
	
	if not is_ship_oriented:
		# Clamp camera so map boundaries don't pan past the center of screen
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
				draw_line(Vector2(x, min_y), Vector2(x, max_y), Color(0.1, 0.2, 0.1), 1.0 / map_zoom)
				
		for y in range(start_y, max_y + grid_step, grid_step):
			if y >= -grid_size and y <= grid_size:
				draw_line(Vector2(min_x, y), Vector2(max_x, y), Color(0.1, 0.2, 0.1), 1.0 / map_zoom)
		
	# Draw origin reference
	draw_circle(Vector2.ZERO, 10.0, Color(0.2, 0.2, 0.5))
		
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
				var mount_pos = w.get("rect", Rect2()).position
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
				# Draw bracket
				var b_size = 15.0
				draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size/2, -b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size, -b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size/2, -b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size, -b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size/2, b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size, b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size/2, b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size, b_size/2), Color.WHITE, 2.0)
				
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
		
		if not safe_rect.has_point(screen_pos):
			# It's off screen, calculate edge intersection
			var offset = screen_pos - center
			var x_ratio = abs(offset.x) / (size.x/2.0 - margin)
			var y_ratio = abs(offset.y) / (size.y/2.0 - margin)
			var max_ratio = max(x_ratio, y_ratio)
			if max_ratio <= 0.0: continue # contact is dead-center, can't be off-screen -- avoid a divide-by-zero

			var edge_pos = center + offset / max_ratio
			
			var dir_to_contact = offset.normalized()
			
			# Draw an arrow at edge_pos pointing outward
			var p_tip = edge_pos + dir_to_contact * 10.0
			var p_left = edge_pos + dir_to_contact.rotated(PI * 0.8) * 10.0
			var p_right = edge_pos + dir_to_contact.rotated(-PI * 0.8) * 10.0
			
			var color = _get_contact_color(c)
			
			var pts = PackedVector2Array([p_tip, p_left, p_right])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([p_tip, p_left, p_right, p_tip]), color, 2.0)
			
			
			# Draw label
			var display_name = c.get("name", c_id)
			var text_size = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			var label_pos = edge_pos - dir_to_contact * 15.0 - Vector2(text_size.x/2.0, -text_size.y/3.0)
			draw_string(font, label_pos, display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)

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

