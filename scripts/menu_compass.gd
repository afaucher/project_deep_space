extends Node2D

# Decorative slowly-rotating compass behind the opening menu -- a background accent in the
# top-right. Sized RELATIVE to the viewport so it stays a consistent fraction of the
# screen at any resolution, with line weight scaled to the radius. Purely cosmetic.
@export var height_fraction: float = 0.25      # compass DIAMETER as a fraction of viewport height
@export var corner_margin_fraction: float = 0.05  # gap from the corner, fraction of viewport height
@export var line_color: Color = Color(0.22, 0.22, 0.25)
@export var line_width_fraction: float = 0.05  # base line thickness as a fraction of the radius
@export var spin_speed: float = 0.10           # rad/s -- a full turn in roughly a minute

var radius: float = 150.0

func _ready() -> void:
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)

func _update_layout() -> void:
	var vp := get_viewport_rect().size
	radius = vp.y * height_fraction * 0.5
	var margin := vp.y * corner_margin_fraction
	position = Vector2(vp.x - radius - margin, radius + margin)
	queue_redraw()

func _process(delta: float) -> void:
	rotation += spin_speed * delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2.ZERO
	var lw := radius * line_width_fraction

	# Concentric rings.
	draw_arc(c, radius, 0.0, TAU, 96, line_color, lw, true)
	draw_arc(c, radius * 0.72, 0.0, TAU, 80, line_color, lw * 0.5, true)
	draw_arc(c, radius * 0.12, 0.0, TAU, 24, line_color, lw * 0.5, true)

	# Tick marks every 15 degrees; longer + heavier at the four cardinals.
	var n := 24
	for i in range(n):
		var dir := Vector2.from_angle(TAU * float(i) / float(n))
		var cardinal := i % 6 == 0
		var inner := radius - (radius * 0.16 if cardinal else radius * 0.07)
		draw_line(dir * inner, dir * radius, line_color, lw * (0.8 if cardinal else 0.5), true)

	# Cardinal cross-hair.
	draw_line(Vector2(-radius, 0), Vector2(radius, 0), line_color, lw * 0.4, true)
	draw_line(Vector2(0, -radius), Vector2(0, radius), line_color, lw * 0.4, true)

	# North pointer.
	var pts := PackedVector2Array([
		Vector2(-radius * 0.10, -radius * 0.66),
		Vector2(0, -radius * 0.92),
		Vector2(radius * 0.10, -radius * 0.66),
	])
	draw_polyline(pts, line_color, lw * 0.7, true)
