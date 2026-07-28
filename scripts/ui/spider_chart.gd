extends Control

class_name SpiderChart

const UIStyle = preload("res://scripts/ui/ui_style.gd")

# Display ceilings for each axis (values clamp/scale against these, they
# don't change the underlying signature). EM was raised from its original
# 100.0 -- a reactor whiteout pulse (Ship.REACTOR_WHITEOUT_MULTIPLIER x
# power_rating) can spike well past that, e.g. 500.0 for the Frigate's own
# reactor, and would otherwise just clip flat against the old ceiling.
const MAX_HEAT_DISPLAY := 200.0          # matches Ship.max_heat
const MAX_EM_DISPLAY := 500.0
const MAX_CROSS_SECTION_DISPLAY := 300.0
const MAX_DENSITY_DISPLAY := 500.0

var max_values: Array[float] = [MAX_HEAT_DISPLAY, MAX_EM_DISPLAY, MAX_CROSS_SECTION_DISPLAY, MAX_DENSITY_DISPLAY]
var axis_labels: Array[String] = ["HEAT", "EM", "C_SEC", "DENS"]
var current_values: Array[float] = [0.0, 0.0, 0.0, 0.0]

var ring_count: int = 4
var radius: float = 60.0

func set_values(heat: float, em: float, cs: float, den: float) -> void:
	current_values[0] = clampf(heat, 0.0, max_values[0])
	current_values[1] = clampf(em, 0.0, max_values[1])
	current_values[2] = clampf(cs, 0.0, max_values[2])
	current_values[3] = clampf(den, 0.0, max_values[3])
	queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	center.y += 5 # Offset slightly to avoid cutting off top label
	var angle_step = (PI * 2.0) / 4.0
	
	var default_font = ThemeDB.fallback_font
	var font_size = UIStyle.FONT_CANVAS_TINY
	
	# Draw concentric rings
	for r in range(1, ring_count + 1):
		var points = PackedVector2Array()
		var frac = float(r) / float(ring_count)
		var current_radius = radius * frac
		
		for i in range(4):
			var angle = -PI/2.0 + float(i) * angle_step
			var pt = center + Vector2(cos(angle), sin(angle)) * current_radius
			points.append(pt)
		points.append(points[0]) # close polygon
		
		draw_polyline(points, Color(0.3, 0.3, 0.3, 0.5), 1.0)
		
	# Draw axes from center
	for i in range(4):
		var angle = -PI/2.0 + float(i) * angle_step
		var pt = center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(center, pt, Color(0.4, 0.4, 0.4, 0.8), 1.0)
		
		# Draw labels at extremities
		var label_pt = center + Vector2(cos(angle), sin(angle)) * (radius + 12.0)
		var txt = axis_labels[i]
		var str_size = default_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(default_font, label_pt - str_size/2.0 + Vector2(0, font_size/3.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)
		
	# Draw data polygon
	var data_points = PackedVector2Array()
	var data_colors = PackedColorArray([Color(0.8, 0.2, 0.2, 0.4)])
	
	for i in range(4):
		var frac = max(0.01, current_values[i] / max_values[i])
		var angle = -PI/2.0 + float(i) * angle_step
		var pt = center + Vector2(cos(angle), sin(angle)) * (radius * frac)
		data_points.append(pt)
		
	if data_points.size() >= 3:
		draw_polygon(data_points, data_colors)
		data_points.append(data_points[0])
		draw_polyline(data_points, Color(1.0, 0.3, 0.3, 0.8), 2.0)
