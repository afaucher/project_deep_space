# Control remapping

Keyboard + gamepad rebinding, reachable from the main menu (CONTROLS button),
persisted to a config file in the project directory.

## Shape

- **Defaults are never edited.** project.godot's `[input]` section stays the
  single source of default bindings (what `test_input_bindings` asserts).
  The `InputBindings` autoload (`scripts/input_bindings.gd`) applies saved
  overrides on top of the runtime `InputMap` at startup and is the only code
  that writes the config.
- **Config**: `input_bindings.cfg` at the repo root (`res://` in the
  from-source workflow; gitignored). Human-editable, one section per action:

  ```ini
  [combat_fire_all]
  keys=PackedStringArray("F")
  pad="button:1"          ; or "axis:5:+"
  ```

  Key names round-trip through `OS.get_keycode_string` /
  `OS.find_keycode_from_string`; pad bindings are one button OR one signed
  axis direction per action.
- **UI**: `scripts/ui/controls_menu.gd`, built in code like help_overlay --
  one row per action, a keyboard slot and a gamepad slot, press-to-capture.
  Gamepad-navigable via the engine's built-in `ui_*` focus actions.

## Rules the implementation relies on

- **A rebind replaces the whole device class for that action**: capturing a
  key replaces ALL keyboard events (multi-key defaults like A+Left collapse
  to the one captured key), capturing a pad input replaces ALL pad events.
  Reset-to-defaults (`InputMap.load_from_project_settings()` + delete the
  config) restores multi-key defaults.
- **Conflicts are refused, not stolen**: binding an input already used by
  another remappable action shows which action owns it and keeps the old map.
- **Capture handling lives in `_input()` and marks events handled** so a
  press being bound can't double as a focused-button activation or reach
  main.gd's `_unhandled_input` (which quits on `system_exit` -- this is what
  makes Esc/Start safe to have bound at all while the screen is open).
  Esc always cancels a capture, so Escape itself is not capturable.
- **Stick-settle grace**: joypad motion is ignored for 300ms after a pad
  capture starts and needs |value| >= 0.6, so the stick deflection that
  navigated focus to the button doesn't instantly self-bind.
- **Automated runs skip overrides**: the autoload's `_ready` returns early
  under `--run-test` / `--run-tactical-sim`. Tests assert project defaults
  and sims must not inherit a developer's personal remaps. Anything testing
  the remap API points `InputBindings.config_path` at a scratch file and
  calls `load_bindings()` itself (see `test_input_remap`,
  `test_controls_menu_ui`).

## Known gaps

- The F1 help overlay (`scripts/ui/help_overlay.gd`) still shows hardcoded
  default glyphs -- after a remap it's stale. Making it read the live
  InputMap (via `InputBindings.keyboard_text`/`gamepad_text`) is a natural
  follow-up.
- One pad binding per action (matches the current defaults; nothing in the
  game uses two).
