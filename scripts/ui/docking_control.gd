extends Button
class_name DockingControl

# M33 -- top-level context-flip "Request Docking" / "Undock" control (see
# implementation_plans/m31_m36_port_authority_roadmap.md, M33 scope). One
# press runs the whole handshake (hail -> request -> grant -> surface
# clearance) via the SAME issuance path the dialogue branch uses
# (scripts/port/port_control.gd's request_docking(), which calls Station.
# issue_docking_grant() -- see ship.gd). When the ship is DOCKED the control
# flips to "Undock" and calls Ship.request_undock() (M32).
#
# This node is deliberately thin: it holds only wiring (which station/ship to
# act on, refreshing its own label) and delegates ALL behavior to
# PortControl's static helpers so the logic is identical (and testable
# headless with no Control node at all -- see test_port_control_comms.gd) for
# both this button and the dialogue mutation.

const PortControl = preload("res://scripts/port/port_control.gd")

signal docking_requested(outcome: Dictionary)
signal undock_requested()

var player_ship: Node = null
var target_station: Node = null

func _ready() -> void:
	pressed.connect(_on_pressed)
	refresh()

# is_docked mirrors the roadmap's "same control flips to Undock while docked"
# rule -- driven by whether the ship is actually captured by a bay
# (CAPTURING or DOCKED), not merely holding a grant (a grant with no capture
# yet should still read "Request Docking", since nothing to undock exists).
func _is_docked() -> bool:
	return player_ship != null and player_ship.get("docking_bay") != null

func refresh() -> void:
	text = PortControl.button_text(_is_docked())
	disabled = player_ship == null or (target_station == null and not _is_docked())

func _on_pressed() -> void:
	if player_ship == null:
		return
	if _is_docked():
		PortControl.undock(player_ship)
		undock_requested.emit()
		return
	if target_station == null:
		return
	var result: Dictionary = PortControl.request_docking(target_station, player_ship)
	if result.get("outcome", "") == "granted":
		# Surface clearance = raise wants_dock so the ship actually flies the
		# capture -- the fast path runs hail->request->grant->clearance in one
		# press; without this the grant would sit unused until something else
		# set wants_dock.
		player_ship.dockable = true
		player_ship.wants_dock = true
	docking_requested.emit(result)
