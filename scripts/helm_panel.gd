extends Control

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

@onready var main_node = get_node("/root/Main")

class HeadingDial extends Control:
	signal target_angle_changed(angle: float)
	var target_angle: float = 0.0
	var actual_angle: float = 0.0
	var is_ship_oriented: bool = false
	
	func _ready() -> void:
		custom_minimum_size = Vector2(200, 200)
		
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var center = size / 2.0
				var clicked_angle = center.angle_to_point(get_local_mouse_position())
				if is_ship_oriented:
					clicked_angle += actual_angle + PI/2.0
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
		var map_rot = 0.0
		if is_ship_oriented:
			map_rot = -actual_angle - PI/2.0
			
		for i in range(0, 360, 30):
			var godot_angle = deg_to_rad(i - 90.0)
			var draw_angle = godot_angle + map_rot
			var dir = Vector2.RIGHT.rotated(draw_angle)
			
			var is_cardinal = (i % 90 == 0)
			var tick_color = Color.GREEN if is_cardinal else Color(0.0, 0.8, 0.0, 0.6)
			var tick_width = 3.0 if is_cardinal else 1.0
			
			var p1 = center + dir * (radius - (15.0 if is_cardinal else 8.0))
			var p2 = center + dir * radius
			draw_line(p1, p2, tick_color, tick_width)
			
			var text_pos = center + dir * (radius - 25.0)
			var text = str(i)
			if i == 0: text = "N"
			elif i == 90: text = "E"
			elif i == 180: text = "S"
			elif i == 270: text = "W"
			
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, text_pos - text_size / 2.0 + Vector2(0, font_size / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tick_color)
			
		# Draw ghost needle (Target)
		var draw_target = target_angle + map_rot
		var ghost_end = center + Vector2.RIGHT.rotated(draw_target) * radius
		draw_line(center, ghost_end, Color(0.5, 0.5, 0.5, 0.5), 6.0)
		
		# Draw actual needle
		var draw_actual = actual_angle + map_rot
		var actual_end = center + Vector2.RIGHT.rotated(draw_actual) * radius
		draw_line(center, actual_end, Color.CYAN, 3.0)
		draw_circle(actual_end, 5.0, Color.CYAN)

class EngineSlider extends Control:
	signal intent_changed(val: float)
	signal became_active()
	
	var is_active_control: bool = false
	var min_val: float = -1.0
	var max_val: float = 1.0
	
	var target_val: float = 0.0 # Red dot if active
	var actual_val: float = 0.0 # Mid-grey filled bar
	var implied_val: float = 0.0 # Light grey dot if inactive
	
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
				if abs(new_val) < (range_val * 0.05):
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

var linear_mode: int = 0 # 0 = Throttle, 1 = Velocity
var target_velocity: float = 0.0
var throttle_slider: EngineSlider
var velocity_slider: EngineSlider
var max_speed: float = 1000.0

func _ready() -> void:
	# Build layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	
	# Dial
	var dial_container = CenterContainer.new()
	dial_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heading_dial = HeadingDial.new()
	heading_dial.target_angle_changed.connect(_on_heading_changed)
	dial_container.add_child(heading_dial)
	vbox.add_child(dial_container)
	
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
	engine_hbox.add_theme_constant_override("separation", 20)
	
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
	
	vbox.add_child(engine_hbox)

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
	
	# Update dial
	var rot = current_state.get("rot", 0.0)
	heading_dial.actual_angle = rot
	heading_dial.is_ship_oriented = current_state.get("is_ship_oriented", false)
	heading_dial.queue_redraw()
	
	# Update Engine Controls
	var actual_vel = current_state.get("vel", Vector2.ZERO)
	var forward = Vector2.RIGHT.rotated(rot)
	var forward_speed = actual_vel.dot(forward)
	var actual_throttle = current_state.get("throttle", 0.0)
	
	throttle_slider.actual_val = actual_throttle
	velocity_slider.actual_val = forward_speed
	
	if linear_mode == 0:
		# Throttle is active. Implied velocity is just thrust * max_speed
		velocity_slider.implied_val = target_thrust * max_speed
	else:
		# Velocity is active. Implied throttle is the actual PID output
		throttle_slider.implied_val = actual_throttle
		
	throttle_slider.queue_redraw()
	velocity_slider.queue_redraw()
