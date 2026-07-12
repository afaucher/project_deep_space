extends RefCounted
class_name PortControl

# M33 -- Port Control comms. Pure-logic helpers shared by BOTH the dialogue
# mutation (comms_panel -> DialogueManager -> a .dialogue "do" line) and the
# top-level "Request Docking"/"Undock" fast-path button, so there is exactly
# ONE behavior to trust regardless of which route the player takes. Neither
# route re-implements Station.issue_docking_grant()'s pool logic (M32,
# ship.gd) -- both call through request_docking() below, which calls it.
#
# Authority styles (roadmap table, "Authority styles" section): OPEN has no
# comms/grant at all (never reaches this class -- no port_zone). MINIMAL,
# STAFFED, AUTOMATED all share identical grant/gate/undock mechanics; only
# presentation + reliability differ, driven entirely by port_zone["style"].

const STYLE_OPEN := "OPEN"
const STYLE_MINIMAL := "MINIMAL"
const STYLE_STAFFED := "STAFFED"
const STYLE_AUTOMATED := "AUTOMATED"

# MINIMAL-style "terse/flaky computer" stall: the roadmap calls for a
# "seeded stall chance (deterministic in tests)" -- rather than fight the
# single global RNG seed() in main.gd's _run_test (CLAUDE.md: don't add a
# second seed, don't rely on raw randf() timing for test determinism), this
# is a plain per-station attempt counter. The first MINIMAL_STALL_ATTEMPTS
# requests to a given station return "stand by" with no grant; the next
# request goes through normally. Deterministic regardless of RNG stream.
const MINIMAL_STALL_ATTEMPTS := 1

# Per-station (by instance id) attempt counters for the MINIMAL stall. Module-
# level state is fine here -- it's presentation/reliability flavor, not part
# of the (shared, single-pool) grant bookkeeping itself, and tests construct a
# fresh station per scenario so counters never leak across cases in practice.
# Exposed so a test can reset a specific station's count deterministically.
static var _minimal_attempt_counts: Dictionary = {}

static func reset_minimal_attempts(station) -> void:
	_minimal_attempt_counts.erase(station.get_instance_id())

static func get_style(station) -> String:
	if station == null or not station.has_method("get_port_zone"):
		return STYLE_OPEN
	var zone: Dictionary = station.get_port_zone()
	if zone.is_empty():
		return STYLE_OPEN
	return zone.get("style", STYLE_AUTOMATED)

# The name port control answers to, driven by style. AUTOMATED = the
# impersonal zone authority name ("Ironhold Control"); MINIMAL = a terse
# label (still identifies the station, but reads as a machine, not a person);
# STAFFED = a personal dockmaster name (NOT "...Control") -- the roadmap's
# explicit STAFFED requirement. Falls back to the zone authority for OPEN /
# unrecognized styles (shouldn't be hailed in practice -- OPEN has no zone).
static func get_controller_name(station) -> String:
	var zone: Dictionary = station.get_port_zone() if station != null and station.has_method("get_port_zone") else {}
	var authority: String = zone.get("authority", "Port Control")
	var style: String = get_style(station)
	match style:
		STYLE_STAFFED:
			return zone.get("dockmaster_name", "Dockmaster Reyes")
		STYLE_MINIMAL:
			return authority + " (auto)"
		_:
			return authority

# THE single issuance entry point for both the dialogue mutation and the
# fast-path button. Returns a Dictionary describing the outcome so callers
# (dialogue text, UI banner) can present it without re-deriving state:
#   {"outcome": "granted", "grant": <DockingGrant dict>}
#   {"outcome": "already_docked", "slip_id": String} -- this ship is physically at one of THIS station's berths right now
#   {"outcome": "out_of_zone"}        -- requester isn't inside this authority's control zone; a grant issued now would
#                                        silently expire on the very next tick (_update_docking_grant's zone check), which
#                                        read as "permission granted then nothing happened" -- surface it instead
#   {"outcome": "no_berths"}          -- station.issue_docking_grant() denied (pool full)
#   {"outcome": "stalled"}            -- MINIMAL style, still within its stall window; no grant issued, no pool call wasted
# station.issue_docking_grant(ship) is the M32 single pool allocator
# (ship.gd) -- called here and ONLY here, so the dialogue path and the
# fast-path button can never diverge on outcome. verbose=true here (this is
# the player/comms path, a handful of calls) turns on the allocator's
# per-berth check log; the NPC AI's direct issue_docking_grant() calls stay
# quiet (they retry every tick while a pool is full).
static func request_docking(station, ship) -> Dictionary:
	var style: String = get_style(station)

	# Already at one of this station's berths (CAPTURING or DOCKED): asking
	# for permission again is a no-op, not a denial -- without this, a docked
	# ship's own bay reads non-EMPTY and the OTHER berth's availability
	# decides the answer, so port control would either double-grant a second
	# slip or say "no open berths" to a ship sitting on its dock.
	var bay = ship.get("docking_bay")
	if bay != null and bay.get_parent() == station:
		return {"outcome": "already_docked", "slip_id": bay.slip_id}

	# Outside the control zone: don't issue a grant that _update_docking_grant
	# will kill next tick (its zone check compares against M31 membership).
	# GEOMETRIC test, not the ship's current_port_zone field -- membership
	# only updates on physics ticks, so a synchronous request right after
	# spawn (tests, scripted scenes) would false-deny on a stale field. The
	# radius gets the same PORT_ZONE_EXIT_MARGIN dead band membership uses,
	# so a ship hovering exactly on the boundary can't be granted here and
	# instantly expired there.
	var zone: Dictionary = station.get_port_zone() if station.has_method("get_port_zone") else {}
	if not zone.is_empty():
		var zone_radius: float = float(zone.get("radius", 0.0))
		if zone_radius > 0.0 and not PortZone.contains(station.global_position, zone_radius, ship.position):
			return {"outcome": "out_of_zone"}

	if style == STYLE_MINIMAL:
		var sid: int = station.get_instance_id()
		var attempts: int = _minimal_attempt_counts.get(sid, 0)
		if attempts < MINIMAL_STALL_ATTEMPTS:
			_minimal_attempt_counts[sid] = attempts + 1
			return {"outcome": "stalled"}
		# Stall window has elapsed -- fall through to a real request. Leave the
		# counter at/above the threshold so subsequent requests keep succeeding
		# (a single retry clears it, per the roadmap: "re-request to retry").

	var grant = station.issue_docking_grant(ship, true)
	if grant == null:
		return {"outcome": "no_berths"}
	return {"outcome": "granted", "grant": grant}

# Top-level context-flip control logic (fast path). is_docked = the ship is
# currently captured by a bay (CAPTURING or DOCKED -- see docking_control.gd
# for the exact UI-facing check); when true the control reads "Undock" and
# undock() below is the action; otherwise it reads "Request Docking" and
# request_docking() above is the action. Kept here (not just in the UI layer)
# so a test can assert the button text purely from ship/station state with no
# Control node involved.
static func button_text(is_docked: bool) -> String:
	return "Undock" if is_docked else "Request Docking"

# Delegates to Ship.request_undock() -- the SAME M32 undock command the
# dialogue-free player path and NPC docking AI use. No duplicate logic.
static func undock(ship) -> void:
	if ship.has_method("request_undock"):
		ship.request_undock()
