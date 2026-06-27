# Input Prompt Glyphs — Attribution & Lineage

These input-prompt glyphs are vendored from a third-party asset pack. Recorded here so
their origin stays clear even though the license does not require attribution.

- **Pack:** Kenney Input Prompts, version 1.5
- **Author:** Kenney — <https://kenney.nl>
- **Pack page:** <https://kenney.nl/assets/input-prompts>
- **License:** Creative Commons Zero (CC0 1.0) — public domain.
  <https://creativecommons.org/publicdomain/zero/1.0/>
  Free for personal, educational, and commercial use; attribution not required (kept
  here as lineage). Full text in [License.txt](License.txt).
- **Usage guide:** <https://kenney.nl/knowledge-base/game-assets-2d/using-input-prompts>
- **Vendored into this repo:** 2026-06-27

## What was vendored (a curated subset, not the full pack)

Only the **Vector (SVG)** glyphs for two device sets were copied:

- `keyboard/` — 257 "Keyboard & Mouse" SVGs (`keyboard_w.svg`, `keyboard_space.svg`,
  `keyboard_tab.svg`, mouse/scroll, …)
- `generic/` — 36 device-agnostic "Generic" controller SVGs (`generic_button_*`,
  `generic_joystick_*`, `generic_button_trigger_*`, d-pad)

The full pack (~4,644 files / ~19 MB) also contains PNG raster variants, sprite sheets,
prompt fonts, and per-device sets (Xbox, PlayStation, Switch, Steam Deck, and more). A
single **generic** controller set was chosen instead of per-device packs; SVG-only for
crisp, themeable scaling.

## Adding more later

Download the full pack from the pack page above and copy the desired
`<Device>/Vector/*.svg` folders in alongside these. Keep the original filenames — the F1
help overlay maps InputMap actions to glyph filenames (e.g. `keyboard_space.svg`,
`generic_button_trigger_a.svg`), so renaming would break the lookup.
