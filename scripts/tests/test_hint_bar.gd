extends Node

# M13b/M13c -- the bottom-bar hint. hint_for() is a PURE state -> String
# function (that is why it takes a Dictionary instead of reaching for nodes),
# so the rules are checked directly here rather than by flying the game and
# reading a label. Plus a headless construct check on the Label shell, in
# test_help_overlay's style -- guards the build, not the look.
#
# Copy is asserted loosely (does it name the key the player needs?) so
# rewording does not fail the test.

const HintBar = preload("res://scripts/ui/hint_bar.gd")

func setup(main) -> void:
	print("Test test_hint_bar initialized.")
	var failures: Array = []

	# --- Rules, in priority order -------------------------------------------
	var no_ship: String = HintBar.hint_for({"has_ship": false, "contact_count": 5, "has_selection": true})
	if no_ship != HintBar.PREFIX:
		failures.append("no-ship hint should be the bare prefix, got '%s'" % no_ship)

	var empty: String = HintBar.hint_for({"has_ship": true, "contact_count": 0, "has_selection": false})
	if not (empty.contains("W/S") and empty.contains("A/D")):
		failures.append("empty-sensors hint should name the movement keys, got '%s'" % empty)

	var untargeted: String = HintBar.hint_for({"has_ship": true, "contact_count": 3, "has_selection": false})
	if not untargeted.contains("Q/E"):
		failures.append("contacts-but-no-target hint should name Q/E, got '%s'" % untargeted)

	var targeted: String = HintBar.hint_for({"has_ship": true, "contact_count": 3, "has_selection": true})
	if not targeted.contains("Space"):
		failures.append("target-selected hint should name Space, got '%s'" % targeted)

	# Selection outranks contact count -- a player who has selected something is
	# past the "find one" step even if the count is momentarily stale.
	var sel_priority: String = HintBar.hint_for({"has_ship": true, "contact_count": 0, "has_selection": true})
	if not sel_priority.contains("Space"):
		failures.append("selection should outrank contact_count, got '%s'" % sel_priority)

	# Missing keys degrade to the movement case -- never claim a target exists.
	var sparse: String = HintBar.hint_for({"has_ship": true})
	if sparse.contains("Space"):
		failures.append("a state with no selection info must not advertise firing: '%s'" % sparse)

	# F1 stays discoverable in every branch.
	for h in [empty, untargeted, targeted, sparse]:
		if not h.begins_with(HintBar.PREFIX):
			failures.append("hint lost the '%s' prefix: '%s'" % [HintBar.PREFIX, h])

	# --- The Label shell ------------------------------------------------------
	var bar = HintBar.new()
	main.add_child(bar) # runs _ready
	bar.set_version_suffix("  |  test-build")

	bar.refresh({"has_ship": true, "contact_count": 2, "has_selection": false})
	if not bar.text.contains("Q/E"):
		failures.append("refresh() did not apply the hint, text='%s'" % bar.text)
	if not bar.text.contains("test-build"):
		failures.append("refresh() dropped the version suffix, text='%s'" % bar.text)

	# Off-switch falls back to the old static nudge; the version stays.
	DebugSettings.set_choice("hint_bar", DebugSettings.HintBar.OFF)
	bar.refresh({"has_ship": true, "contact_count": 2, "has_selection": false})
	if bar.text.contains("Q/E"):
		failures.append("hint_bar=OFF should suppress the contextual half, text='%s'" % bar.text)
	if not bar.text.contains("F1"):
		failures.append("hint_bar=OFF should still show 'F1  Controls', text='%s'" % bar.text)
	DebugSettings.set_choice("hint_bar", DebugSettings.HintBar.ON)

	# The Debug menu builds itself from OPTIONS -- no entry, no off-switch in UI.
	if not DebugSettings.OPTIONS.has("hint_bar"):
		failures.append("DebugSettings.OPTIONS is missing the 'hint_bar' entry")

	bar.queue_free()

	if failures.is_empty():
		print("HintBar rules OK. Sample: '%s'" % untargeted)
		print(">>> [TEST PASSED] test_hint_bar <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		printerr(">>> [TEST FAILED] test_hint_bar <<<")
		get_tree().quit(1)
