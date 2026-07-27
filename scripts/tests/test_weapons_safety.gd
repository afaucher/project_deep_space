extends Node

# Playtest B -- weapons safety (design_ideas/2026-07-26-campaign_playtest.md).
# "Currently `space` (fire all) is live with no guard."
#
# Three requirements from the notes, all pinned here:
#   - disable fire-all when the ship has no weapons (a no-op key reads as
#     broken rather than as "you are unarmed")
#   - a safety switch, DEFAULT ENGAGED
#   - do not fire unless the target is a flagged enemy -- belt-and-braces with
#     the switch, deliberately: firing on a neutral station is exactly the kind
#     of accident that should be hard to have, especially given A1
#
# THE ROUTE COVERAGE IS THE POINT. There are three ways to pull the trigger --
# the FIRE ALL button, the `combat_fire_all` action (spacebar AND gamepad
# right-trigger, handled in the panel's own _input), and each weapon's
# individual FIRE button. That last one emitted fire_weapon_requested DIRECTLY,
# so a guard written into _fire_all alone would have left every individual
# hardpoint unguarded. All three now funnel through _request_fire, and this
# test drives all three rather than trusting that.
#
# Fixture-driven (hand-built packets, no live ship/physics), same
# "instantiate the Control directly" pattern as test_contacts_panel_sos.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_weapons_safety

const WeaponsPanel = preload("res://scripts/ui/weapons_panel.gd")
const Standing = preload("res://scripts/combat/standing.gd")

var failures: Array = []
var fired: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _packet(standing: String, with_weapons: bool = true) -> Dictionary:
	var contact: Dictionary = {
		"instance_id": 77,
		"classification": "UNIDENTIFIED VESSEL",
		"standing": standing,
		"pos": Vector2(500, 0),
		"vel": Vector2.ZERO,
		"signature": {},
		"last_seen_at": Engine.get_physics_frames(),
	}
	var weapons: Array = []
	if with_weapons:
		weapons = [{"id": "hp_fwd", "name": "Forward Laser", "cooldown": 0.0, "cooldown_max": 1.0, "ammo": 10}]
	return {
		"pos": Vector2.ZERO,
		"vel": Vector2.ZERO,
		"contacts": {"TRK-077": contact},
		"weapons": weapons,
	}

func setup(main) -> void:
	print("=== test_weapons_safety: playtest B -- the trigger has a guard ===")

	var panel := WeaponsPanel.new()
	main.add_child(panel)
	panel.fire_weapon_requested.connect(func(wid): fired.append(wid))

	# --- Default state -------------------------------------------------------
	print("\n--- the safety is ENGAGED by default ---")
	_assert(panel.safety_engaged,
		"a fresh console comes up with the safety ON -- the player disengages deliberately")

	# --- Safety blocks every route ------------------------------------------
	print("\n--- with the safety engaged, no control scheme fires ---")
	panel.update_data(_packet(Standing.HOSTILE), "TRK-077")

	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "FIRE ALL button / spacebar / gamepad RT: blocked by the safety")

	fired.clear()
	panel._request_fire("hp_fwd")
	_assert(fired.is_empty(), "an individual weapon's FIRE button: blocked too (it bypasses _fire_all)")

	_assert(panel.fire_all_btn.disabled,
		"the FIRE ALL button is visibly disabled, not silently inert")
	_assert("SAFETY" in panel.safety_status_label.text,
		"...and the status line says why (got '%s')" % panel.safety_status_label.text)

	# --- Safety off, hostile target -> every route fires ---------------------
	# The control. Without it, every assertion above would also pass against a
	# panel that had simply stopped firing altogether.
	print("\n--- safety off, target flagged HOSTILE: all three routes fire ---")
	panel._on_safety_toggled(false)

	fired.clear()
	panel._fire_all()
	_assert(fired == ["hp_fwd"], "FIRE ALL fires the loadout (got %s)" % str(fired))

	fired.clear()
	panel._request_fire("hp_fwd")
	_assert(fired == ["hp_fwd"], "the individual FIRE button fires (got %s)" % str(fired))

	fired.clear()
	panel._input(_fire_all_event())
	_assert(fired == ["hp_fwd"], "the combat_fire_all ACTION fires -- spacebar and gamepad RT (got %s)" % str(fired))

	_assert(not panel.fire_all_btn.disabled, "the FIRE ALL button is enabled")

	# --- Belt-and-braces: a non-hostile target is refused even armed ---------
	print("\n--- safety OFF but the target is not flagged: still refused ---")
	panel.update_data(_packet(Standing.NEUTRAL), "TRK-077")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(),
		"a NEUTRAL station is not fired on even with the safety off -- the accident A1 made expensive")
	_assert("HOSTILE" in panel.safety_status_label.text,
		"...and the console says the target is not flagged (got '%s')" % panel.safety_status_label.text)

	panel.update_data(_packet(Standing.CAUTION), "TRK-077")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "a CAUTION contact is not a firing solution either")

	# --- Unarmed -------------------------------------------------------------
	# The notes' first bullet: a no-op key reads as broken. It must SAY unarmed.
	print("\n--- no weapons fitted ---")
	panel.update_data(_packet(Standing.HOSTILE, false), "TRK-077")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "an unarmed hull fires nothing")
	_assert(panel.fire_all_btn.disabled, "the FIRE ALL button is disabled when unarmed")
	_assert("UNARMED" in panel.safety_status_label.text,
		"...and reads UNARMED rather than sitting silent (got '%s')" % panel.safety_status_label.text)

	# --- No target -----------------------------------------------------------
	print("\n--- no target locked ---")
	panel.update_data(_packet(Standing.HOSTILE), "")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "nothing fires with no target locked")
	_assert("NO TARGET" in panel.safety_status_label.text,
		"...and the console says so (got '%s')" % panel.safety_status_label.text)

	# --- Shared track-validity rule ------------------------------------------
	# Wreckage / the honor rule / staleness are NOT re-implemented in the panel;
	# it calls the same Standing.track_engageable_refusal AcquireTargetLeaf
	# uses. Spot-check that the console actually honours it.
	print("\n--- shared track-validity rule (not a panel-local copy) ---")
	var wreck: Dictionary = _packet(Standing.HOSTILE)
	wreck["contacts"]["TRK-077"]["classification"] = "WRECKAGE"
	panel.update_data(wreck, "TRK-077")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "a hulk is not fired on, armed or not")

	var complied: Dictionary = _packet(Standing.HOSTILE)
	complied["contacts"]["TRK-077"]["complied_stop"] = true
	panel.update_data(complied, "TRK-077")
	fired.clear()
	panel._fire_all()
	_assert(fired.is_empty(), "a ship that has complied is off the table (M49 honor rule)")

	panel.queue_free()
	_finish()

# A synthetic combat_fire_all press, so the test drives the real _input path
# rather than assuming it reaches _fire_all.
func _fire_all_event() -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = "combat_fire_all"
	ev.pressed = true
	return ev

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_weapons_safety <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_weapons_safety <<<")
		get_tree().quit(1)
