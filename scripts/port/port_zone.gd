extends RefCounted
class_name PortZone

# M31 -- Port Zone spatial substrate. A controlled station owns a circular
# authority zone (center = station position, one radius); this is the pure
# geometry test so callers (Ship membership tracking, later the M35 boundary
# HUD) can drive it with fixtures with no scene/node state involved.
#
# Kept as a static helper (no instance state) per the M31 spec so
# test_port_zone.gd can call PortZone.contains(...) directly against fixture
# centers/radii/points without spinning up a station or a ship.

static func contains(center: Vector2, radius: float, point: Vector2) -> bool:
	return center.distance_to(point) <= radius
