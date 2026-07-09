extends "res://scripts/tests/fixtures/test_rcs_ship.gd"

# Distinct script identity from test_rcs_ship.gd so RadarCrossSection's
# per-class cache (keyed by script.resource_path) doesn't collide between
# unrelated fixtures in the same test run -- see test_radar_cross_section.gd's
# empty-ship-no-crash case.
