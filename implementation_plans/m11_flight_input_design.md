# M11 — Direct Flight Input (keyboard + gamepad)

Parent: [m9_ship_catalog_design.md](m9_ship_catalog_design.md) (sibling QoL
milestone). Source: direct request — basic keyboard/gamepad steering so you can
actually fly during playtesting instead of dragging a mouse dial.

**Pairs with M10:** M10 lets you spawn ships and teams; M11 lets you fly your
own ship by hand to fight them. Together they make the catalog playtestable.

## The control model this must respect

Flight is **fly-by-wire / intent-based**, not arcade. The helm panel doesn't
apply torque — it sets a *target heading* (dial) and *target throttle or
velocity* (sliders), then calls
`main.send_helm_input(thrust, target_velocity, heading, steering_mode, linear_mode)`
([helm_panel.gd:239](../scripts/panels/helm_panel.gd:239)). That routes to the
host and ends in `ship.apply_control_input(...)`
([main.gd:271](../scripts/main.gd:271), [main.gd:282](../scripts/main.gd:282));
the ship's controller flies toward the targets.

**So keyboard/gamepad must feed the same `send_helm_input` pipeline** — NOT a new
direct-torque control path. This keeps Smooth/Combat steering modes, the
client→host RPC, and the helm panel's readouts all working unchanged. The panel
already re-syncs its dial/sliders from server state in `update_data()`, so it
will visually follow keyboard/gamepad input for free.

## Scope (basic)

In scope: **turn** (left/right) and **thrust** (forward/back) via keyboard and
gamepad, feeding the intent pipeline. Optional stretch: a **fire** action.
Everything else (strafe, rebind UI, absolute-stick pointing) is deferred.

## 1. InputMap actions (`project.godot` — new `[input]` section)

Define unified actions so `Input.get_axis()` blends keyboard (digital) and
gamepad stick/trigger (analog) automatically:

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| `helm_turn_left` | A, Left | left stick X− (axis 0) |
| `helm_turn_right` | D, Right | left stick X+ (axis 0) |
| `helm_thrust_fwd` | W, Up | R2 / right trigger (axis 5), or left stick Y− |
| `helm_thrust_back` | S, Down | L2 / left trigger (axis 4), or left stick Y+ |
| `helm_fire` (optional) | Space | A button (button 0) |

Set a stick deadzone (~0.2) on the joypad-motion events.

## 2. Client-side input poller (`scripts/helm_input.gd`)

A small node polling each frame (`_process`), client-side (it sends intent; the
host applies it):

- `var turn = Input.get_axis("helm_turn_left", "helm_turn_right")` → −1..1
- `var thrust = Input.get_axis("helm_thrust_back", "helm_thrust_fwd")` → −1..1
- Maintain a local `target_heading`, **seeded from the player ship's current
  rotation** so engaging the keys doesn't snap the nose. Each frame with active
  turn input: `target_heading = wrapf(target_heading + turn * TURN_RATE * delta, -PI, PI)`.
- `target_thrust = thrust` (momentary: hold = thrust, release = 0).
- **Only call `send_helm_input` on frames where there is active input**
  (`turn != 0` or `thrust != 0`, plus a one-frame "release" send so letting go
  commands thrust 0 / holds heading). This is what lets the mouse helm and the
  keyboard coexist: idle keyboard never stomps a heading set on the dial;
  last-input-wins.
- Pass through the current `steering_mode` / `linear_mode` (linear_mode = 0
  Throttle for the momentary thrust model). Leave a TODO for binding a key to
  toggle Combat steering if it's wanted later.

`TURN_RATE` is a tunable const (start ~PI rad/s — a half-turn per second held).

## 3. "My ship" resolution

The poller needs the local player's ship to seed heading from. In offline/host
single-player the player is `players[1]` (or `players[multiplayer.get_unique_id()]`).
Reuse whatever `terminal_display.gd` already uses to find the local ship (it has
a `_get_my_ship()` helper per the M-series notes) rather than re-deriving it.

## 4. Testability

Raw device input can't be exercised headlessly, but the **mapping is pure** and
must be factored so it can be: a static
`HelmInput.compute_intent(turn, thrust, prev_heading, delta) -> {heading, thrust}`.
A headless `test_helm_input`-style test (one already exists for the panel path)
feeds synthetic `turn`/`thrust`/`prev_heading` values and asserts the resulting
heading delta and thrust. Optionally drive the live action path with
`Input.action_press("helm_turn_left")` + a physics tick and assert the ship's
`target_heading` moved, since Godot allows synthetic action injection in code.

## Done when

In a running single-player session, holding A/D (or moving a gamepad stick)
turns the ship and W/S (or triggers) drives it forward/back — with the helm
panel's dial and throttle visibly following — and the pure mapping is covered by
a headless test. Build stays green.

## Deferred (not now)

- **Lateral strafe / translational RCS** — no such mechanic in the flight model
  today; thrust is forward/back along the heading only.
- **Absolute-stick pointing** (twin-stick: stick direction = heading) — a nicer
  gamepad feel, but turn-rate is the basic cut.
- **Rebindable controls UI** and saved bindings.
- **Full weapon control** (target cycling, weapon select) via pad — only an
  optional basic `helm_fire` here, if included at all.

**Touches:** `project.godot` (`[input]`), new `scripts/helm_input.gd` (+ a pure
`compute_intent` it and the test share), `scripts/main.gd` /
`scenes/main.tscn` (instantiate the poller for a local session).
