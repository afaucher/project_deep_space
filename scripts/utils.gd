class_name Utils

static func format_dist(meters: float) -> String:
	if meters < 1000.0:
		return "%.0f m" % meters
	else:
		return "%.1f km" % (meters / 1000.0)
