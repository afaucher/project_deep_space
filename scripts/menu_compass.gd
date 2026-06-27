extends Node2D

# Decorative slowly-rotating compass for the opening menu, drawn in thick dark-grey lines
# behind the menu UI (top-right of the screen). Purely cosmetic -- no gameplay role.
@export var radius: float = 150.0
@export var line_color: Color = Color(0.22, 0.22, 0.25)
@export var line_width: float = 5.0
@export var spin_speed: float = 0.10   # rad/s -- a full turn in roughly a minute
@export var corner_margin: float = 60.0 # distance of the compass centre from the corner

func _ready() -> void:
	_place_top_right()
	get_viewport().size_changed.connect(_place_top_right)

func _place_top_right() -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - radius - corner_margin, radius + corner_margin)

func _process(delta: float) -> void:
	rotation += spin_speed * delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2.ZERO
	# Concentric rings.
	draw_arc(c, radius, 0.0, TAU, 96, line_color, line_width, true)
	draw_arc(c, radius * 0.72, 0.0, TAU, 80, line_color, line_width * 0.5, true)
	draw_arc(c, radius * 0.12, 0.0, TAU, 24, line_color, line_width * 0.5, true)

	# Tick marks every 15 degrees; longer + heavier at the four cardinals.
	var n := 24
	for i in range(n):
		var dir := Vector2.from_angle(TAU * float(i) / float(n))
		var cardinal := i % 6 == 0
		var inner := radius - (radius * 0.16 if cardinal else radius * 0.07)
		draw_line(dir * inner, dir * radius, line_color, line_width * (0.8 if cardinal else 0.5), true)

	# Cardinal cross-hair.
	draw_line(Vector2(-radius, 0), Vector2(radius, 0), line_color, line_width * 0.4, true)
	draw_line(Vector2(0, -radius), Vector2(0, radius), line_color, line_width * 0.4, true)

	# North pointer.
	var pts := PackedVector2Array([
		Vector2(-radius * 0.10, -radius * 0.66),
		Vector2(0, -radius * 0.92),
		Vector2(radius * 0.10, -radius * 0.66),
	])
	draw_polyline(pts, line_color, line_width * 0.7, true)
