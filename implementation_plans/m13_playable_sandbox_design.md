# M13 — Playable Sandbox (pick-up-and-play)

**Goal:** hand the build to someone with no briefing and have them understand, within
~30 seconds, how to fly, find a target, and fight. The underlying systems already exist —
M10 (sandbox spawn), M11 (flight input), M12 (combat AI), and the Fire All control. M13
makes them **discoverable and complete for keyboard+mouse players**, which is what
"playable without explanation" actually requires.

This milestone is the integration/onboarding pass over everything built so far, not new
combat depth.

## 1. What "playable without explanation" needs — gap analysis

What already works:
- **Combat AI (M12)** — enemies bring broadsides to bear, mass synchronized volleys to
  punch through PD, and break off when crippled. There is something real to fight.
- **Sandbox spawn (M10)** — a dropdown in the terminal top bar spawns any catalog hull on
  Friendly / Enemy / Pirate.
- **Flight (M11)** — a **full gamepad scheme is wired** (steer, throttle, zoom, target
  cycle, fire, steering-mode toggles). The mouse helm dial also works.
- **Fire All** — Space / gamepad RT / a panel button fire everything that bears.

Gaps that block a cold hand-off:
1. **No keyboard controls.** The scheme is gamepad-only; a keyboard+mouse tester cannot
   fly. Because every handler already reads its action via `Input.get_axis()` /
   `is_action_pressed()` (helm_panel, sensor_panel, navigation_panel, terminal_display),
   this is an **InputMap augmentation — add keyboard events to the existing actions, no
   handler changes.**
2. **No on-screen control legend.** Even once bound, a newcomer cannot guess the keys. A
   visible/toggleable help is mandatory for "no explanation."
3. **The core loop is not self-evident.** start → fly → spawn/encounter an enemy → select
   a target → fire. The spawn control is visible, but targeting + firing need a first-run
   hint.
4. **Start flow naming.** The menu's "Local Test" button is the play button — clarify it
   ("Play" / "Sandbox").
5. **(Enrich, optional) Characterful enemies (M12d).** A bare frigate-vs-frigate sandbox
   is thinner than a civilian / pirate / flock / destroyer "food chain"; M12d makes the
   sandbox worth poking at, but is not required to clear the minimal playable bar.

## 2. Controls — main screen (in-flight terminal)

Every action below already exists and is wired; the **Keyboard** column is what M13a adds
(gamepad bindings are current). Gamepad labels assume an Xbox layout; the InputMap index
is authoritative.

| Function | Action | Keyboard (add) | Gamepad (current) |
|---|---|---|---|
| Turn left / right | `helm_steer_left` / `helm_steer_right` | **A / D** (+ ← / →) | Left stick X (axis 0) |
| Throttle forward / back | `helm_throttle_up` / `helm_throttle_down` | **W / S** (+ ↑ / ↓) | Left stick Y (axis 1) |
| Toggle throttle ↔ velocity mode | `helm_linear_toggle` | **V** | Start (btn 7) |
| Toggle smooth ↔ combat steering | `combat_steer_toggle` | **C** | X (btn 2) |
| Fire all weapons | `combat_fire_all` | **Space** ✓ (done) | Right trigger (axis 5) |
| Next target | `nav_next_contact` | **Tab** | R-stick click (btn 10) |
| Previous target | `nav_prev_contact` | **Shift+Tab** | L-stick click (btn 9) |
| Zoom map in / out | `nav_zoom_in` / `nav_zoom_out` | **Mouse wheel** (+ `=` / `-`) | Right stick Y (axis 3) |
| Toggle map orientation | `map_orient_toggle` | **M** | Y (btn 3) |
| Spawn enemy (debug) | `debug_spawn_enemy` | **F-key** (existing) | — |
| Start / play (menu) | `menu_start` | **Enter** | A (btn 0) |
| Quit | `system_exit` | **Esc** | Back (btn 6) |

Mouse (already works, keep): drag the **helm dial** to set heading; **click a sensor
contact** to select/lock a target; the nav map is the primary tactical view. So the
keyboard layer is additive — fly with WASD, cycle targets with Tab, fire with Space —
while mouse helm + click-to-target remain. Heading is last-input-wins between the mouse
dial and the keys, so an idle keyboard never stomps a dial heading.

The proposed keyboard keys are a starting point and bikeshed-friendly; the load-bearing
decision is that the keys map onto the existing actions.

## 3. Scope (phases)

- **M13a — Keyboard control parity. DONE (2026-06-27).** Bound keyboard events on the
  existing actions (A/D + arrows steer, W/S + arrows throttle, Space fire, Q/E target,
  =/- zoom, V/C/M mode toggles, Enter/Esc, F1 help). Target cycle uses **Q/E** (not Tab —
  Tab fights Godot's UI focus traversal) and zoom uses **=/-** keys (mouse-wheel is a
  later handler). `test_input_bindings` asserts every keycode loaded. Original scope:
  Add keyboard (and mouse-wheel) `InputEvent`s to the
  existing `[input]` actions in `project.godot` so the whole scheme is playable on
  keyboard+mouse. Pure InputMap work; handlers unchanged. Verify each action fires from
  its key (Godot allows `Input.action_press()` injection for a headless smoke test of a
  representative action or two).
- **M13b — On-screen controls legend (F1 help overlay). v1 DONE (2026-06-27).** Shipped
  the glyph-rich **reference list** form: F1 toggles `help_overlay.gd` (dimmed backdrop +
  centered panel listing each control with its keyboard glyph + generic gamepad glyph +
  label, Kenney CC0 glyphs), wired into `terminal_display` with a persistent "F1
  Controls" hint. `test_help_overlay` verifies it constructs headlessly (glyphs load, 10+
  TextureRects, hidden by default). **Still planned:** the **anchored-callouts** form
  below (boxes on the live controls via per-panel `get_help_annotations`), and
  last-input-device glyph swapping. Original design:
  - **F1 toggles** a full-screen overlay: a dimmed backdrop + **callouts anchored on the
    live UI controls**, each a highlight box around the control's `get_global_rect()` with
    a chip showing its **glyph + function** beside it (helm dial → steer/throttle, FIRE
    ALL button → fire, sensor contact list → target select, zoom, spawn dropdowns).
  - **Split by whether a control exists:** anchored callouts for actions with a visible
    widget; a **corner reference list** for keyboard/gamepad-only actions that have no
    widget (mode toggles, map orient, quit, debug spawn) — that list doubles as the full
    binding reference.
  - **Anchor to live nodes, never hardcoded positions:** each panel exposes
    `get_help_annotations() -> [{node, key, label}]`; `terminal_display` aggregates them so
    the overlay only annotates what is currently on screen and follows layout/resizes. (The
    FIRE ALL button must be stored as a member to be referenceable.)
  - **Glyphs for both devices.** Show keyboard **and** generic-gamepad glyphs from the
    vendored Kenney pack (see Assets below); default chips to the keyboard glyph with the
    gamepad glyph in the reference list (optionally swap on last-input-device detection).
  - **Persistent one-liner** outside the overlay (e.g. "F1: Controls · click a contact,
    Space to fire") so a player who never opens F1 still gets the core loop.
- **M13c — Onboarding-loop polish.** Rename the menu play button; make the spawn → select
  → fire loop legible (a first-run hint such as "Select a contact, then Space to fire");
  optionally spawn a starter enemy so there is instant action.
- **M13d — Characterful enemies (enrich; = M12d).** Wire the curated archetypes
  (civilian / light flock / pirate / destroyer) into the spawn menu so the sandbox is a
  food chain, not just "spawn a frigate." Pulls from M12d; can land as a fast follow.

**Foundation-first order:** M13a (keyboard) → M13b (legend) → M13c (onboarding) → M13d
(enrich). M13a + M13b alone clear the "a keyboard player can pick it up" bar.

## 4. Dependencies & relationship to other milestones

- **Absorbs the keyboard half of M11.** M11's gamepad steering is done; its keyboard
  steering becomes M13a (same intent pipeline, just more bound events). M11 can be marked
  "gamepad done; keyboard folded into M13a."
- **M13d == M12d.** The archetypes serve double duty: AI variety (M12) and sandbox content
  (M13). Whichever milestone drives it, the work is the same trees + spawn wiring.
- **Does not need M7/M8.** Neutral IFF and text comms are not on the path to a playable
  sandbox.

## 5. Assets — input glyphs

Vendored **Kenney Input Prompts 1.5** (CC0 — free for commercial use, no attribution
required; `License.txt` included) under `assets/input_prompts/`, SVG (vector) only:
- `keyboard/` — 257 keyboard & mouse glyphs (`keyboard_w.svg`, `keyboard_space.svg`,
  `keyboard_tab.svg`, mouse/scroll, etc.).
- `generic/` — 36 device-agnostic controller glyphs (`generic_button_*`,
  `generic_joystick_*`, `generic_button_trigger_*`, d-pad).

A **single generic** controller set (not Xbox/PS/Switch-specific) was chosen so we ship
one universal gamepad style; per-device packs can be added later if wanted. ~293 files /
~0.9 MB vs. the full 4,644-file / 19 MB pack. The overlay maps each InputMap action to a
glyph filename (a small lookup table: action/key → svg).

## 6. Open questions

- **Legend form:** transient overlay (toggle) vs. a persistent minimal control strip vs.
  both. Recommendation: a toggle overlay (full list) + a one-line persistent hint for the
  core loop.
- **Keyboard layout:** the table is a proposal; confirm preferred keys (e.g. Tab vs. E for
  target cycle, V vs. T for mode toggle).
- **Targeting primary:** mouse-click-to-select vs. Tab-cycle as the taught path — confirm
  the current sensor-panel selection UX reads clearly for a newcomer.
- **Starter scenario:** spawn a default enemy on entry, or leave the world empty and rely
  on the spawn control being obvious?
