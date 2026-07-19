extends Control
class_name TimeSeriesGraph

# Rolling history of a target's OBSERVED heat/EM signature -- i.e. whatever
# push_sample() is fed (the caller's own sensor-fused, lerp-smoothed contact
# data), not the target ship's actual internal current_heat/em_signature.
# This class has no way to tell the difference; it's purely a display for
# whatever values it's handed. Sampled at most once every SAMPLE_INTERVAL
# real seconds so a ~60Hz update_data() call doesn't pack the buffer with 60
# near-identical points per second. Each axis auto-scales independently to
# whatever's currently in the window -- heat and EM live on very different
# scales, and fixed thresholds (like SpiderChart's) would clip the M2
# event-driven spikes (reactor whiteout, weapon fire pulses) this graph
# exists to show.
const HISTORY_DURATION := 20.0
const SAMPLE_INTERVAL := 0.2
const HEAT_COLOR := Color(1.0, 0.5, 0.2, 0.9)
const EM_COLOR := Color(0.3, 0.7, 1.0, 0.9)

var _samples: Array = [] # [{"t": float, "heat": float, "em": float}, ...]
var _last_sample_time := -INF

func reset() -> void:
	_samples.clear()
	_last_sample_time = -INF
	queue_redraw()

func push_sample(heat: float, em: float) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_sample_time < SAMPLE_INTERVAL:
		return
	_last_sample_time = now
	_samples.append({"t": now, "heat": heat, "em": em})
	var cutoff = now - HISTORY_DURATION
	while _samples.size() > 0 and _samples[0]["t"] < cutoff:
		_samples.pop_front()
	queue_redraw()

func _draw() -> void:
	var margin_left = 28.0
	var margin_bottom = 14.0
	var margin_top = 10.0
	# Room for the HEAT/EM legend, moved out here (was inside the plot's
	# top-left). Widened from 34 -> 56 so a live 4-digit value ("HEAT 1234")
	# still fits without clipping.
	var margin_right = 56.0
	var plot_w = size.x - margin_left - margin_right
	var plot_h = size.y - margin_top - margin_bottom
	var origin_y = size.y - margin_bottom

	var default_font = ThemeDB.fallback_font
	var font_size = 9

	draw_rect(Rect2(margin_left, margin_top, plot_w, plot_h), Color(0.05, 0.05, 0.05, 0.5))

	# Legend -- right side of the chart (always shown, even with no data yet).
	# This is now the ONLY heat/EM readout in the weapons panel (the numeric
	# "Heat: X | EM: Y" text and the spider chart were both removed as
	# duplicates of what this graph already shows). Live: shows the most
	# recent sample's value ("HEAT 37") once there's data, just the bare word
	# until then.
	var legend_x = margin_left + plot_w + 4.0
	var heat_legend = "HEAT"
	var em_legend = "EM"
	if not _samples.is_empty():
		var last = _samples[_samples.size() - 1]
		heat_legend = "HEAT %.0f" % last["heat"]
		em_legend = "EM %.0f" % last["em"]
	draw_string(default_font, Vector2(legend_x, margin_top + font_size), heat_legend, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HEAT_COLOR)
	draw_string(default_font, Vector2(legend_x, margin_top + font_size * 2.5), em_legend, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, EM_COLOR)

	if _samples.is_empty():
		draw_string(default_font, Vector2(margin_left + 4, origin_y - plot_h / 2.0), "NO DATA", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)
		return

	var now = Time.get_ticks_msec() / 1000.0
	var t_min = now - HISTORY_DURATION

	# Floor at each ship's typical full operating range (same constants
	# SpiderChart uses) so ordinary idle jitter -- a few points of baseline
	# heat/EM wobble -- doesn't fill the whole vertical scale and read as a
	# dramatic swing. Real events (weapon hits, reactor whiteout) still push
	# the scale higher than the floor via max(), so they're never clipped.
	var max_heat = SpiderChart.MAX_HEAT_DISPLAY
	var max_em = SpiderChart.MAX_EM_DISPLAY
	for s in _samples:
		max_heat = max(max_heat, s["heat"])
		max_em = max(max_em, s["em"])

	for i in range(1, 4):
		var y = margin_top + plot_h * (float(i) / 4.0)
		draw_line(Vector2(margin_left, y), Vector2(margin_left + plot_w, y), Color(0.3, 0.3, 0.3, 0.3), 1.0)

	# Top-of-scale for BOTH axes, color-keyed to their line -- they're two
	# independent auto-scales sharing the same vertical extent, so both
	# numbers are needed to read either line's height correctly. Heat on top
	# (orange), EM right below it (blue).
	draw_string(default_font, Vector2(0, margin_top + 4), "%.0f" % max_heat, HORIZONTAL_ALIGNMENT_LEFT, margin_left - 2, font_size, HEAT_COLOR)
	draw_string(default_font, Vector2(0, margin_top + 4 + font_size + 2), "%.0f" % max_em, HORIZONTAL_ALIGNMENT_LEFT, margin_left - 2, font_size, EM_COLOR)
	draw_string(default_font, Vector2(0, origin_y), "0", HORIZONTAL_ALIGNMENT_LEFT, margin_left - 2, font_size, Color.GRAY)
	draw_string(default_font, Vector2(margin_left, size.y - 2), "-%ds" % int(HISTORY_DURATION), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)
	draw_string(default_font, Vector2(size.x - margin_right - 22, size.y - 2), "now", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)

	var heat_points = PackedVector2Array()
	var em_points = PackedVector2Array()
	for s in _samples:
		var frac_x = clampf((s["t"] - t_min) / HISTORY_DURATION, 0.0, 1.0)
		var x = margin_left + frac_x * plot_w
		heat_points.append(Vector2(x, origin_y - clampf(s["heat"] / max_heat, 0.0, 1.0) * plot_h))
		em_points.append(Vector2(x, origin_y - clampf(s["em"] / max_em, 0.0, 1.0) * plot_h))

	if heat_points.size() >= 2:
		draw_polyline(heat_points, HEAT_COLOR, 1.5)
	if em_points.size() >= 2:
		draw_polyline(em_points, EM_COLOR, 1.5)
