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

# M46 -- exclusion_radius default derivation (design_ideas/port_zones_and_channels.md
# "Exclusion disc"). A controlled station's no-fly annulus radius, when not
# explicitly authored, is derived once (Ship._ready()) as the hull's own
# bounding radius (get_bounding_radius() -- the same circumscribing-circle
# measure used for docking standoff/steering margins/nav bounds rings
# throughout the codebase) times this factor.
#
# Tuned (not the roadmap's "start ~2.5" literal value) so a medium station
# (Ironhold, get_bounding_radius() ~264u) lands in the roadmap's own stated
# target order for a medium station's exclusion disc, ~1500-2000u
# (design_ideas/port_zones_and_channels.md "Geometry"): 264 * 6.0 ~= 1584u,
# comfortably inside that range and a sane fraction (~20%) of Ironhold's
# 8000u control ring. A lower factor near 2.5 would derive ~660u -- far
# short of the design doc's own target, so this was tuned upward from that
# starting point per CLAUDE.md's "tune so Ironhold's disc looks sane".
const EXCLUSION_RADIUS_FACTOR := 6.0

static func derive_exclusion_radius(hull_bounding_radius: float) -> float:
	return hull_bounding_radius * EXCLUSION_RADIUS_FACTOR
