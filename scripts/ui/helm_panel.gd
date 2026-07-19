extends Control

const PortRules = preload("res://scripts/port/port_rules.gd")

var current_state: Dictionary = {
	"pos": Vector2.ZERO,
	"rot": 0.0,
	"vel": Vector2.ZERO
}

var target_heading: float = 0.0
var target_thrust: float = 0.0
var steering_mode: int = 0 # 0 = Smooth, 1 = Combat

var heading_dial: Control
var thrust_slider: VSlider
var vel_gauge: ProgressBar
var mode_button: CheckButton

# Dial-side stat readouts (to the right of the heading dial -- the dial's
# needles are dense/unlabeled by design, so these make them self-discoverable
# without cluttering the ring itself). Terms, since "direction" is ambiguous
# with Newtonian flight (nose orientation != travel direction):
#   Speed   -- |velocity|, unsigned, regardless of facing.
#   Heading -- which way the ship's NOSE points (the cyan needle).
#   Course  -- which way the ship is ACTUALLY moving (the yellow prograde
#              marker) -- can differ from Heading under drift/momentum.
#   Bearing -- compass direction to the selected target, if any (the
#              colored compass-bug on the ring).
var speed_stat_lbl: Label
var heading_stat_lbl: Label
var course_stat_lbl: Label
var bearing_stat_lbl: Label

@onready var main_node = get_node_or_null("/root/Main")

class HeadingDial extends Control:
	signal target_angle_changed(angle: float)
	var target_angle: float = 0.0
	var actual_angle: float = 0.0
	var actual_vel: Vector2 = Vector2.ZERO
	var is_ship_oriented: bool = false

	# Selected-target overlays (set by helm update_data; see there).
	var has_target: bool = false
	var target_bearing: float = 0.0      # world bearing from own ship to the target
	var target_color: Color = Color.WHITE
	var rel_vel: Vector2 = Vector2.ZERO  # own_vel - target_vel; null it to match the target's speed
	# Relative speed (u/s) at which the match-speed needle reaches full length.
	# Log-scaled below it so small mismatches stay readable (fine control) and
	# high closing speeds clamp instead of shooting off the dial (no overshoot).
	const REL_VEL_FULL := 600.0

	func _ready() -> void:
		custom_minimum_size = Vector2(300, 300)
		
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var center = size / 2.0
				var clicked_angle = (get_local_mouse_position() - center).angle()
				if is_ship_oriented:
					clicked_angle += actual_angle + PI/2.0
				
				# Snap to actual_angle if within 5.7 degrees (0.1 rads)
				if abs(wrapf(clicked_angle - actual_angle, -PI, PI)) < 0.1:
					clicked_angle = actual_angle
					
				target_angle = wrapf(clicked_angle, -PI, PI)
				target_angle_changed.emit(target_angle)
				queue_redraw()
				
	func _draw() -> void:
		var center = size / 2.0
		var radius = min(size.x, size.y) / 2.0 - 10.0
		
		# Draw dial background
		draw_circle(center, radius, Color(0.1, 0.1, 0.15))
		draw_arc(center, radius, 0, TAU, 32, Color(0.3, 0.3, 0.4), 2.0)
		
		# Draw markings
		var font = ThemeDB.fallback_font
		var font_size = 12
		var map_rot = Utils.get_map_rotation(is_ship_oriented, actual_angle)

		for i in range(0, 360, 30):
			var draw_angle = deg_to_rad(i - 90.0) + map_rot
			var dir = Vector2.RIGHT.rotated(draw_angle)

			var style = Utils.compass_tick_style(i)
			var p1 = center + dir * (radius - (15.0 if style["is_cardinal"] else 8.0))
			var p2 = center + dir * radius
			draw_line(p1, p2, style["color"], style["width"])

			var text_pos = center + dir * (radius - 25.0)
			var text = Utils.compass_label_text(i)

			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, text_pos - text_size / 2.0 + Vector2(0, font_size / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, style["color"])

		# Draw velocity vector and retrograde if we're moving
		if actual_vel.length_squared() > 1.0:
			var vel_angle = actual_vel.angle()
			var draw_vel = vel_angle + map_rot
			
			var vel_dir = Vector2.RIGHT.rotated(draw_vel)
			var retro_dir = Vector2.RIGHT.rotated(draw_vel + PI)
			var yellow = Color(1.0, 1.0, 0.0)
			
			# Prograde indicator
			draw_line(center + vel_dir * (radius - 8.0), center + vel_dir * (radius + 8.0), yellow, 3.0)
			var vel_cw = Vector2.RIGHT.rotated(draw_vel + 0.1)
			var vel_ccw = Vector2.RIGHT.rotated(draw_vel - 0.1)
			draw_line(center + vel_cw * (radius - 5.0), center + vel_cw * radius, yellow, 2.0)
			draw_line(center + vel_ccw * (radius - 5.0), center + vel_ccw * radius, yellow, 2.0)
			
			# Retrograde indicator
			draw_line(center + retro_dir * (radius - 8.0), center + retro_dir * (radius + 8.0), yellow, 3.0)
			var retro_cw = Vector2.RIGHT.rotated(draw_vel + PI + 0.1)
			var retro_ccw = Vector2.RIGHT.rotated(draw_vel + PI - 0.1)
			draw_line(center + retro_cw * (radius - 5.0), center + retro_cw * radius, yellow, 2.0)
			draw_line(center + retro_ccw * (radius - 5.0), center + retro_ccw * radius, yellow, 2.0)

		# Draw ghost needle (Target)
		var draw_target = target_angle + map_rot
		var ghost_end = center + Vector2.RIGHT.rotated(draw_target) * radius
		draw_line(center, ghost_end, Color(0.5, 0.5, 0.5, 0.5), 6.0)
		draw_circle(ghost_end, 6.0, Color(0.7, 0.7, 0.7, 0.8))
		
		# Draw actual needle
		var draw_actual = actual_angle + map_rot
		var actual_end = center + Vector2.RIGHT.rotated(draw_actual) * radius
		draw_line(center, actual_end, Color.CYAN, 3.0)
		draw_circle(actual_end, 5.0, Color.CYAN)

		# --- Selected target: a "compass bug" on the ring in the target's color.
		# Line the yellow prograde (velocity) marker up with this bug and you're
		# flying straight at the target.
		if has_target:
			var tb = target_bearing + map_rot
			var tdir = Vector2.RIGHT.rotated(tb)
			var tip = center + tdir * (radius - 1.0)
			var wing_l = center + Vector2.RIGHT.rotated(tb + 0.11) * (radius + 13.0)
			var wing_r = center + Vector2.RIGHT.rotated(tb - 0.11) * (radius + 13.0)
			draw_colored_polygon(PackedVector2Array([tip, wing_l, wing_r]), target_color)

		# --- Relative-velocity needle: your motion RELATIVE to the target. Burn
		# opposite to it to null it out and match speed. Length is log-scaled +
		# clamped (see REL_VEL_FULL) so it's precise near a match and never
		# overshoots the dial at high closing speed.
		if has_target and rel_vel.length() > 2.0:
			var rv: float = rel_vel.length()
			var rdir: Vector2 = Vector2.RIGHT.rotated(rel_vel.angle() + map_rot)
			var norm: float = clampf(log(1.0 + rv) / log(1.0 + REL_VEL_FULL), 0.0, 1.0)
			var tip2: Vector2 = center + rdir * (norm * (radius - 6.0))
			var rcol: Color = Color(1.0, 0.55, 0.1)  # orange -- distinct from yellow prograde
			draw_line(center, tip2, rcol, 2.5)
			draw_circle(tip2, 4.0, rcol)

class EngineSlider extends Control:
	signal intent_changed(val: float)
	signal became_active()

	const DEADZONE_RATIO := 0.025 # fraction of the slider's full range snapped to exactly 0.0 near center -- narrow so low-throttle fine control isn't lost to the detent

	var is_active_control: bool = false
	var min_val: float = -1.0
	var max_val: float = 1.0
	
	var target_val: float = 0.0 # Red dot if active
	var actual_val: float = 0.0 # Mid-grey filled bar
	var implied_val: float = 0.0 # Light grey dot if inactive

	# M35 -- numeric speed readout (helm velocity control gains a current-speed
	# number; see roadmap M35 "speed_advisory" scope). show_speed_number is set
	# true ONLY on the velocity slider (helm_panel._ready() below) -- the
	# throttle slider stays exactly as before, no number, since "current
	# forward speed" doesn't mean anything on a -1..1 throttle axis. The number
	# reads ALWAYS (not just in a zone -- "a plain speed number is useful
	# everywhere" per spec); speed_advisory_active is the only thing a zone
	# drives, flipping the readout's color to amber as a warn-only cue (no
	# thrust clamp, no other gameplay effect).
	var show_speed_number: bool = false
	# Kept working (set every update_data() call below) even though the
	# gauge's own color no longer keys off it directly -- M35's own comment
	# already flagged "helm amber elsewhere may use it", and the M46 roadmap
	# explicitly says to leave it working.
	var speed_advisory_active: bool = false

	# M46 -- zone speed limit + three-state readout (design_ideas/
	# port_zones_and_channels.md: "current / limit readout with three color
	# states"). zone_limit is 0.0 outside a zone or in a zone with no/zero
	# speed_advisory rule -- see helm_panel.update_data(). zone_speed_state
	# is a PortRules.SpeedState value (NORMAL/APPROACHING/OVER), computed
	# from TRUE speed (vector magnitude) even though the readout NUMBER
	# below is forward speed -- see PortRules.speed_zone_state's doc comment
	# for why (a fast lateral drift must still read as approaching/over).
	var zone_limit: float = 0.0
	var zone_speed_state: int = PortRules.SpeedState.NORMAL

	# M46 -- lateral-drift cue: a small secondary number shown alongside the
	# main (forward-speed) readout when PortRules.drift_cue_visible() says
	# the color state is likely explained by sideways drift rather than
	# forward speed. lateral_speed is the magnitude of the velocity
	# component perpendicular to the ship's heading.
	var show_drift_cue: bool = false
	var lateral_speed: float = 0.0

	const SPEED_NORMAL_COLOR := Color(0.8, 0.8, 0.8)
	const SPEED_APPROACHING_COLOR := Color(1.0, 0.7, 0.1)  # amber
	const SPEED_OVER_COLOR := Color(1.0, 0.25, 0.15)       # red-tinted amber -- "over", not just "approaching"
	const ZONE_LIMIT_TICK_COLOR := Color(1.0, 0.7, 0.1, 0.85)
	const DRIFT_CUE_COLOR := Color(1.0, 0.55, 0.2)

	func _ready() -> void:
		custom_minimum_size = Vector2(40, 200)
		
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				if not is_active_control:
					is_active_control = true
					became_active.emit()
				
				var t = 1.0 - clampf(get_local_mouse_position().y / size.y, 0.0, 1.0)
				var new_val = lerpf(min_val, max_val, t)
				
				var range_val = max_val - min_val
				if abs(new_val) < (range_val * DEADZONE_RATIO):
					new_val = 0.0
					
				if target_val != new_val:
					target_val = new_val
					intent_changed.emit(target_val)
				queue_redraw()
				
	func _draw() -> void:
		var rect = Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.15, 0.15, 0.15))
		
		var zero_t = (0.0 - min_val) / (max_val - min_val)
		var zero_y = size.y * (1.0 - zero_t)
		draw_line(Vector2(0, zero_y), Vector2(size.x, zero_y), Color(0.4, 0.4, 0.4), 2.0)
		
		var actual_t = clampf((actual_val - min_val) / (max_val - min_val), 0.0, 1.0)
		var actual_y = size.y * (1.0 - actual_t)
		var fill_rect = Rect2()
		fill_rect.position.x = 0
		fill_rect.size.x = size.x
		if actual_val > 0:
			fill_rect.position.y = actual_y
			fill_rect.size.y = zero_y - actual_y
		else:
			fill_rect.position.y = zero_y
			fill_rect.size.y = actual_y - zero_y
		draw_rect(fill_rect, Color(0.5, 0.5, 0.5))
		
		var dot_val = target_val if is_active_control else implied_val
		var dot_t = clampf((dot_val - min_val) / (max_val - min_val), 0.0, 1.0)
		var dot_y = size.y * (1.0 - dot_t)
		var dot_color = Color.RED if is_active_control else Color(0.7, 0.7, 0.7)
		draw_circle(Vector2(size.x / 2.0, dot_y), 8.0, dot_color)

		# M46 -- zone speed-limit tick(s). Drawn at +limit AND -limit since this
		# gauge's axis is -max_speed..+max_speed (a limit is a magnitude, not a
		# direction) -- so dragging the target-velocity bug toward either end
		# shows legal-or-not before the ship is actually moving that fast, per
		# the roadmap's "actionable when SETTING a target velocity" goal.
		# zone_limit is 0.0 outside a zone / with no rule authored, so this is a
		# no-op there.
		if zone_limit > 0.0:
			var pos_t = clampf((zone_limit - min_val) / (max_val - min_val), 0.0, 1.0)
			var pos_y = size.y * (1.0 - pos_t)
			draw_line(Vector2(0, pos_y), Vector2(size.x, pos_y), ZONE_LIMIT_TICK_COLOR, 2.0)
			var neg_t = clampf((-zone_limit - min_val) / (max_val - min_val), 0.0, 1.0)
			var neg_y = size.y * (1.0 - neg_t)
			draw_line(Vector2(0, neg_y), Vector2(size.x, neg_y), ZONE_LIMIT_TICK_COLOR, 2.0)

		# M35/M46 -- numeric speed readout, screen-space text below the bar/dot
		# gauge (the gauge itself is unchanged -- this is purely additive).
		# "CUR / LIMIT" while in a zone with a positive limit (zone_limit > 0),
		# plain number outside/no-rule -- unchanged from M35 there. Three color
		# states (M46) replace the old binary amber; see PortRules.speed_zone_state.
		if show_speed_number:
			var font = ThemeDB.fallback_font
			var font_size = 14
			var speed_color := SPEED_NORMAL_COLOR
			match zone_speed_state:
				PortRules.SpeedState.APPROACHING:
					speed_color = SPEED_APPROACHING_COLOR
				PortRules.SpeedState.OVER:
					speed_color = SPEED_OVER_COLOR
			var speed_text: String
			if zone_limit > 0.0:
				speed_text = "%d / %d" % [int(round(actual_val)), int(round(zone_limit))]
			else:
				speed_text = "%d" % int(round(actual_val))
			var text_size = font.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = Vector2(size.x / 2.0 - text_size.x / 2.0, size.y + font_size + 4.0)
			draw_string(font, text_pos, speed_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, speed_color)

			# M46 -- lateral-drift cue: a small secondary number so an amber/over
			# state sitting over a legal-looking FORWARD number explains itself
			# (the readout's color keys off TRUE speed, this text shows why).
			if show_drift_cue:
				var drift_font_size = 11
				var drift_text = "lat %d" % int(round(lateral_speed))
				var drift_size = font.get_string_size(drift_text, HORIZONTAL_ALIGNMENT_CENTER, -1, drift_font_size)
				var drift_pos = Vector2(size.x / 2.0 - drift_size.x / 2.0, text_pos.y + font_size + 2.0)
				draw_string(font, drift_pos, drift_text, HORIZONTAL_ALIGNMENT_CENTER, -1, drift_font_size, DRIFT_CUE_COLOR)

var linear_mode: int = 0 # 0 = Throttle, 1 = Velocity
var target_velocity: float = 0.0
var throttle_slider: EngineSlider
var velocity_slider: EngineSlider
var max_speed: float = 1000.0

# Numeric readouts flanking the gauges: ACTUAL on the outside of each pair,
# SETPOINT on the inside -- so for either gauge, actual is one side and
# setpoint (whatever the gauge's own dot is currently showing -- target_val
# while that control is active, else implied_val) is the other:
#   [actual throttle] [THROTTLE] [setpoint throttle]   [setpoint velocity] [VELOCITY] [actual speed]
# The speed number used to draw inside the velocity gauge (EngineSlider.
# show_speed_number); it now lives out here to the side. (The controlled-
# zone LIMIT line lives on the engineering screen -- see engineering_panel.
# gd's zone_status_lbl.)
var throttle_readout_lbl: Label
var throttle_setpoint_lbl: Label
var velocity_setpoint_lbl: Label
var speed_readout_lbl: Label

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("helm_linear_toggle"):
		if linear_mode == 0:
			velocity_slider.became_active.emit()
		else:
			throttle_slider.became_active.emit()
	if event.is_action_pressed("combat_steer_toggle"):
		mode_button.button_pressed = !mode_button.button_pressed

var _detent_timer: float = 0.0

func _process(delta: float) -> void:
	var steer_axis = Input.get_axis("helm_steer_left", "helm_steer_right")
	if abs(steer_axis) > 0.1:
		const MAX_GAMEPAD_LEAD := deg_to_rad(15.0)  # 15° max lead over actual heading
		var old_angle = heading_dial.target_angle
		var new_angle = wrapf(old_angle + steer_axis * delta * 3.0, -PI, PI)
		var actual = heading_dial.actual_angle
		
		# Clamp so target can't run more than 90° ahead of actual
		var diff = wrapf(new_angle - actual, -PI, PI)
		if abs(diff) > MAX_GAMEPAD_LEAD:
			new_angle = wrapf(actual + sign(diff) * MAX_GAMEPAD_LEAD, -PI, PI)
		
		var old_diff = wrapf(old_angle - actual, -PI, PI)
		var new_diff = wrapf(new_angle - actual, -PI, PI)
		
		if sign(old_diff) != sign(new_diff) and abs(old_diff) < 0.5:
			Input.start_joy_vibration(0, 0.3, 0.3, 0.15)
			
		if heading_dial.target_angle != new_angle:
			heading_dial.target_angle = new_angle
			heading_dial.queue_redraw()
			_on_heading_changed(heading_dial.target_angle)

	var throttle_axis = Input.get_axis("helm_throttle_up", "helm_throttle_down")
	if abs(throttle_axis) > 0.1:
		if _detent_timer > 0.0:
			_detent_timer -= delta
		else:
			var slider = throttle_slider if linear_mode == 0 else velocity_slider
			var speed_mult = 2.0 if linear_mode == 0 else max_speed * 0.5
			var old_val = slider.target_val
			var new_val = clampf(old_val - throttle_axis * delta * speed_mult, slider.min_val, slider.max_val)
			
			if sign(old_val) != sign(new_val) and old_val != 0.0:
				new_val = 0.0
				_detent_timer = 0.25 # stick to 0 for 250ms
				Input.start_joy_vibration(0, 0.4, 0.4, 0.15)
				
			if slider.target_val != new_val:
				slider.target_val = new_val
				slider.intent_changed.emit(slider.target_val)
				slider.queue_redraw()

func _ready() -> void:
	# Build layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	
	# Dial + stat readouts, side by side -- the dial's needles are dense and
	# unlabeled, so these make Speed/Heading/Course/Bearing self-discoverable.
	var dial_row = HBoxContainer.new()
	dial_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dial_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dial_row.add_theme_constant_override("separation", 20)

	var dial_container = CenterContainer.new()
	dial_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heading_dial = HeadingDial.new()
	heading_dial.target_angle_changed.connect(_on_heading_changed)
	dial_container.add_child(heading_dial)
	dial_row.add_child(dial_container)

	var stats_center = CenterContainer.new()
	stats_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 10)
	speed_stat_lbl = Label.new()
	heading_stat_lbl = Label.new()
	course_stat_lbl = Label.new()
	bearing_stat_lbl = Label.new()
	for lbl in [speed_stat_lbl, heading_stat_lbl, course_stat_lbl, bearing_stat_lbl]:
		lbl.add_theme_font_size_override("font_size", 15)
		stats_vbox.add_child(lbl)
	stats_center.add_child(stats_vbox)
	dial_row.add_child(stats_center)

	vbox.add_child(dial_row)
	
	# Mode Toggle
	var mode_container = CenterContainer.new()
	mode_button = CheckButton.new()
	mode_button.text = "Combat Steering"
	mode_button.toggled.connect(_on_mode_toggled)
	mode_container.add_child(mode_button)
	vbox.add_child(mode_container)
	
	# Engine Controls (Thrust + Velocity)
	var engine_hbox = HBoxContainer.new()
	engine_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	engine_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	engine_hbox.add_theme_constant_override("separation", 24)

	# Throttle setting readout -- LEFT of the throttle gauge, vertically centered
	# against the tall slider.
	throttle_readout_lbl = Label.new()
	throttle_readout_lbl.text = "0%"
	throttle_readout_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	throttle_readout_lbl.custom_minimum_size = Vector2(52, 0)
	throttle_readout_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	throttle_readout_lbl.add_theme_font_size_override("font_size", 15)
	engine_hbox.add_child(throttle_readout_lbl)

	# Throttle Slider
	var throttle_vbox = VBoxContainer.new()
	var throttle_lbl = Label.new()
	throttle_lbl.text = "Throttle"
	throttle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	throttle_vbox.add_child(throttle_lbl)
	throttle_slider = EngineSlider.new()
	throttle_slider.min_val = -1.0
	throttle_slider.max_val = 1.0
	throttle_slider.is_active_control = true
	throttle_slider.target_val = 0.0
	throttle_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	throttle_slider.became_active.connect(func():
		linear_mode = 0
		throttle_slider.is_active_control = true
		velocity_slider.is_active_control = false
		velocity_slider.queue_redraw()
		_send_input()
	)
	throttle_slider.intent_changed.connect(func(val: float):
		target_thrust = val
		_send_input()
	)
	throttle_vbox.add_child(throttle_slider)
	engine_hbox.add_child(throttle_vbox)

	# Throttle setpoint readout -- RIGHT of the throttle gauge (inner side),
	# the counterpart to throttle_readout_lbl's actual value on its outer side.
	throttle_setpoint_lbl = Label.new()
	throttle_setpoint_lbl.text = "SP +0%"
	throttle_setpoint_lbl.custom_minimum_size = Vector2(56, 0)
	throttle_setpoint_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	throttle_setpoint_lbl.add_theme_font_size_override("font_size", 13)
	engine_hbox.add_child(throttle_setpoint_lbl)

	# Fixed gap so the two inner setpoint readouts don't visually run together.
	var setpoint_gap = Control.new()
	setpoint_gap.custom_minimum_size = Vector2(16, 0)
	engine_hbox.add_child(setpoint_gap)

	# Velocity setpoint readout -- LEFT of the velocity gauge (inner side),
	# the counterpart to speed_readout_lbl's actual value on its outer side.
	velocity_setpoint_lbl = Label.new()
	velocity_setpoint_lbl.text = "SP 0"
	velocity_setpoint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	velocity_setpoint_lbl.custom_minimum_size = Vector2(70, 0)
	velocity_setpoint_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	velocity_setpoint_lbl.add_theme_font_size_override("font_size", 13)
	engine_hbox.add_child(velocity_setpoint_lbl)

	# Velocity Slider
	var vel_vbox = VBoxContainer.new()
	var vel_lbl = Label.new()
	vel_lbl.text = "Velocity"
	vel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vel_vbox.add_child(vel_lbl)
	velocity_slider = EngineSlider.new()
	velocity_slider.min_val = -max_speed
	velocity_slider.max_val = max_speed
	velocity_slider.is_active_control = false
	velocity_slider.target_val = 0.0
	velocity_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	velocity_slider.show_speed_number = false # speed number now drawn in speed_readout_lbl to the right (see below)
	velocity_slider.became_active.connect(func():
		linear_mode = 1
		velocity_slider.is_active_control = true
		throttle_slider.is_active_control = false
		throttle_slider.queue_redraw()
		_send_input()
	)
	velocity_slider.intent_changed.connect(func(val: float):
		target_velocity = val
		_send_input()
	)
	vel_vbox.add_child(velocity_slider)
	engine_hbox.add_child(vel_vbox)

	# Speed readout -- RIGHT of the velocity gauge, vertically centered against
	# the slider. (The controlled-zone limit/rules line lives on the
	# engineering screen now -- see engineering_panel.gd.)
	speed_readout_lbl = Label.new()
	speed_readout_lbl.text = "0"
	speed_readout_lbl.custom_minimum_size = Vector2(96, 0)
	speed_readout_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_readout_lbl.add_theme_font_size_override("font_size", 16)
	engine_hbox.add_child(speed_readout_lbl)

	vbox.add_child(engine_hbox)

# M35 -- resolves a controlled zone's `rules` dict from its authority name.
# current_port_zone (see main.gd's packet field / ship.gd) is only the
# authority STRING, not the zone dict -- same live-resolution call M34/M35's
# navigation_panel.gd already make (station_for_authority there); mirrored
# here rather than shared because helm_panel has no existing coupling to
# navigation_panel and the lookup is a 4-line group scan, not worth a new
# shared module for. Returns {} (no rules) when there's no current zone or
# the authority no longer resolves to a live controlled station.
func _rules_for_authority(authority) -> Dictionary:
	if authority == null or authority == "":
		return {}
	for s in get_tree().get_nodes_in_group("ships"):
		if not s.has_method("get_port_zone"):
			continue
		var zone: Dictionary = s.get_port_zone()
		if zone.get("authority", "") == authority:
			return zone.get("rules", {})
	return {}

func _on_heading_changed(angle: float) -> void:
	target_heading = angle
	_send_input()

func _on_mode_toggled(pressed: bool) -> void:
	steering_mode = 1 if pressed else 0
	_send_input()

func _send_input() -> void:
	if main_node and main_node.has_method("send_helm_input"):
		main_node.send_helm_input(target_thrust, target_velocity, target_heading, steering_mode, linear_mode)

func update_data(packet: Dictionary) -> void:
	current_state = packet

	# Re-sync mode toggle/active-slider indicators from the server's reported
	# steering_mode/linear_mode -- these are otherwise only ever changed
	# locally on user interaction, so without this they can silently drift
	# from the ship's actual mode (e.g. after a reconnect, or if some other
	# input source changes it). set_pressed_no_signal avoids re-firing
	# _on_mode_toggled and bouncing a fresh _send_input() back out.
	var server_steering_mode = current_state.get("steering_mode", steering_mode)
	if server_steering_mode != steering_mode:
		steering_mode = server_steering_mode
		mode_button.set_pressed_no_signal(steering_mode == 1)

	var server_linear_mode = current_state.get("linear_mode", linear_mode)
	if server_linear_mode != linear_mode:
		linear_mode = server_linear_mode
		throttle_slider.is_active_control = (linear_mode == 0)
		velocity_slider.is_active_control = (linear_mode == 1)

	# Update dial
	var rot = current_state.get("rot", 0.0)
	heading_dial.actual_angle = rot
	heading_dial.actual_vel = current_state.get("vel", Vector2.ZERO)
	heading_dial.is_ship_oriented = current_state.get("is_ship_oriented", false)

	# Selected-target overlays: bearing bug (in the target's color) + relative-
	# velocity needle for speed-matching. Both key off the same selected contact
	# the contacts/weapons panels use.
	var sel_id: String = current_state.get("selected_contact_id", "")
	var contacts: Dictionary = current_state.get("contacts", {})
	if sel_id != "" and contacts.has(sel_id):
		var tc: Dictionary = contacts[sel_id]
		var own_pos: Vector2 = current_state.get("pos", Vector2.ZERO)
		var own_vel: Vector2 = current_state.get("vel", Vector2.ZERO)
		var tpos: Vector2 = tc.get("pos", own_pos)
		heading_dial.has_target = true
		heading_dial.target_bearing = (tpos - own_pos).angle()
		heading_dial.target_color = Utils.classification_color(tc.get("classification", ""))
		heading_dial.rel_vel = own_vel - tc.get("vel", Vector2.ZERO)
	else:
		heading_dial.has_target = false
		heading_dial.rel_vel = Vector2.ZERO

	heading_dial.queue_redraw()

	# Dial-side stat readouts (see field comments up top for Heading vs Course).
	# Course only means anything once actually moving -- same threshold the
	# dial itself uses to draw/hide the prograde marker, so the number and the
	# needle never disagree about whether the ship is "moving".
	speed_stat_lbl.text = "Speed    %d" % int(round(heading_dial.actual_vel.length()))
	heading_stat_lbl.text = "Heading  %03d" % Utils.compass_bearing_deg(rot)
	if heading_dial.actual_vel.length_squared() > 1.0:
		course_stat_lbl.text = "Course   %03d" % Utils.compass_bearing_deg(heading_dial.actual_vel.angle())
	else:
		course_stat_lbl.text = "Course   --"
	if heading_dial.has_target:
		bearing_stat_lbl.text = "Bearing  %03d" % Utils.compass_bearing_deg(heading_dial.target_bearing)
		bearing_stat_lbl.add_theme_color_override("font_color", heading_dial.target_color)
	else:
		bearing_stat_lbl.text = "Bearing  --"
		bearing_stat_lbl.remove_theme_color_override("font_color")

	# Update Engine Controls
	var actual_vel = current_state.get("vel", Vector2.ZERO)
	var forward = Vector2.RIGHT.rotated(rot)
	var forward_speed = actual_vel.dot(forward)
	var actual_throttle = current_state.get("throttle", 0.0)

	throttle_slider.actual_val = actual_throttle
	velocity_slider.actual_val = forward_speed

	# M35 -- speed advisory: amber the velocity readout while inside a
	# controlled zone AND over that zone's speed_advisory limit. True speed
	# (vector magnitude), not the signed forward component the gauge/number
	# otherwise track -- a fast lateral drift is still an overspeed relative
	# to a port's advisory even if forward_speed reads low. Warn-only: this
	# never touches target_thrust/target_velocity, just the readout color.
	# Kept working (M46 roadmap: "helm amber elsewhere may use it") even
	# though the gauge's OWN color below now comes from the three-state
	# truth table instead.
	var authority = current_state.get("current_port_zone", null)
	var rules: Dictionary = _rules_for_authority(authority)
	var in_zone: bool = authority != null and authority != ""
	var true_speed: float = actual_vel.length()
	velocity_slider.speed_advisory_active = PortRules.speed_advisory_active_for_rules(
		in_zone, true_speed, rules)

	# M46 -- zone speed limit + three-state readout color. limit is 0.0 when
	# not in a zone or the zone authors no/zero speed_advisory (PortRules.
	# speed_zone_state's own in_zone/limit<=0 guards already return NORMAL for
	# those cases, and zone_limit itself is explicitly zeroed outside a zone so
	# the readout falls back to a plain number -- see EngineSlider._draw()).
	var limit: float = float(rules.get("speed_advisory", 0.0))
	velocity_slider.zone_limit = limit if in_zone else 0.0
	velocity_slider.zone_speed_state = PortRules.speed_zone_state(true_speed, limit, in_zone)

	# M46 -- lateral-drift cue: magnitude of the velocity component
	# perpendicular to the ship's heading, and whether it's large enough
	# (relative or absolute -- see PortRules.drift_cue_visible) to explain the
	# readout's color on its own.
	var lateral_dir: Vector2 = forward.rotated(PI / 2.0)
	var lateral_speed: float = absf(actual_vel.dot(lateral_dir))
	velocity_slider.lateral_speed = lateral_speed
	velocity_slider.show_drift_cue = PortRules.drift_cue_visible(lateral_speed, true_speed)

	if linear_mode == 0:
		# Throttle is active. Implied velocity is just thrust * max_speed
		velocity_slider.implied_val = target_thrust * max_speed
	else:
		# Velocity is active. Implied throttle is the actual PID output
		throttle_slider.implied_val = actual_throttle

	# Flanking readouts. Throttle setting (LEFT) is the actual throttle as a
	# signed percentage; speed (RIGHT) is forward speed, colored by the same
	# three-state zone truth table the gauge ticks use, with the lateral-drift
	# cue appended when it explains the color; the LIMIT line (under speed)
	# echoes the controlling authority + its advisory.
	throttle_readout_lbl.text = "%+d%%" % int(round(actual_throttle * 100.0))

	var speed_text := "%d" % int(round(forward_speed))
	if velocity_slider.show_drift_cue:
		speed_text += "  lat %d" % int(round(lateral_speed))
	speed_readout_lbl.text = speed_text
	var speed_color := Color(0.8, 0.8, 0.8)
	match velocity_slider.zone_speed_state:
		PortRules.SpeedState.APPROACHING:
			speed_color = Color(1.0, 0.7, 0.1)
		PortRules.SpeedState.OVER:
			speed_color = Color(1.0, 0.25, 0.15)
	speed_readout_lbl.add_theme_color_override("font_color", speed_color)

	# Setpoint readouts -- INNER side of each gauge, mirroring whatever that
	# gauge's own dot is currently showing (target_val while that control is
	# active, else implied_val -- the same selection EngineSlider._draw() uses
	# for the dot, so the number and the dot never disagree). Red while that
	# control is the one actively being commanded, grey while it's just
	# following the other control's implied value.
	var throttle_setpoint: float = throttle_slider.target_val if throttle_slider.is_active_control else throttle_slider.implied_val
	throttle_setpoint_lbl.text = "SP %+d%%" % int(round(throttle_setpoint * 100.0))
	throttle_setpoint_lbl.add_theme_color_override("font_color", Color.RED if throttle_slider.is_active_control else Color(0.7, 0.7, 0.7))

	var velocity_setpoint: float = velocity_slider.target_val if velocity_slider.is_active_control else velocity_slider.implied_val
	velocity_setpoint_lbl.text = "SP %d" % int(round(velocity_setpoint))
	velocity_setpoint_lbl.add_theme_color_override("font_color", Color.RED if velocity_slider.is_active_control else Color(0.7, 0.7, 0.7))

	throttle_slider.queue_redraw()
	velocity_slider.queue_redraw()
