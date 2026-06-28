extends Node

# M13b: verify the F1 controls overlay CONSTRUCTS correctly headlessly -- glyph SVGs load
# as textures, the layout builds without API errors, and it starts hidden. The visual
# appearance still needs a human eye, but this guards the build (wrong glyph paths, bad
# TextureRect/StyleBox property names, etc.).
const HelpOverlay = preload("res://scripts/ui/help_overlay.gd")

func setup(main) -> void:
	print("Test test_help_overlay initialized.")
	var failures: Array = []

	var overlay = HelpOverlay.new()
	main.add_child(overlay) # runs _ready -> builds UI + loads glyphs

	if overlay.visible:
		failures.append("overlay should start hidden")
	if overlay.get_child_count() < 2:
		failures.append("overlay built %d children, expected >= 2 (backdrop + center)" % overlay.get_child_count())

	var tex = load("res://assets/input_prompts/keyboard/keyboard_space.svg")
	if tex == null:
		failures.append("keyboard_space.svg did not load as a texture")

	var glyphs = _count_texrects(overlay)
	if glyphs < 10:
		failures.append("expected >= 10 glyph TextureRects, built %d" % glyphs)

	overlay.queue_free()

	if failures.is_empty():
		print("HelpOverlay builds OK: %d glyph textures, hidden by default." % glyphs)
		print(">>> [TEST PASSED] test_help_overlay <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_help_overlay <<<")
		get_tree().quit(1)

func _count_texrects(node) -> int:
	var n = 0
	for c in node.get_children():
		if c is TextureRect:
			n += 1
		n += _count_texrects(c)
	return n
