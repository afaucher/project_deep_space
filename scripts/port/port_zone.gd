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

# Capture-zone default derivation (design_ideas/port_zones_and_channels.md
# "Terminology" -- capture zone): the docking clamp's physical reach is
# meant to read as a short-range robotic arm / a very-short-range force
# field grabbing a ship that's already lined up on approach, NOT a giant net
# that can snatch a ship out of open space. It must stay MUCH smaller than
# exclusion_radius even though the two are conceptually independent (a
# capture zone is centered on the docking point, not the station center, so
# there's no containment relationship to enforce -- this factor just keeps
# it small by construction for any station size).
#
# Deriving proportionally to the HOST's own hull bounding radius (rather
# than a flat constant) scales sensibly whether the host is a compact small
# station or a sprawling medium one: 1.5x lands a medium station (Ironhold,
# ~264u hull) at ~396u -- about a quarter of its exclusion_radius (~1584u,
# factor 6.0) -- and a small station (~180u hull) at ~270u, both comfortably
# larger than pos_tolerance (60u) + settle_speed (25u/s) reaction margins
# without being anywhere near exclusion-zone scale.
const CAPTURE_RADIUS_FACTOR := 1.5

static func derive_capture_radius(hull_bounding_radius: float) -> float:
	return hull_bounding_radius * CAPTURE_RADIUS_FACTOR
