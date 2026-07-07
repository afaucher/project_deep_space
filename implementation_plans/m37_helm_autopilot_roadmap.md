# M37 — Helm Autopilot (Flight Macros)

Goal: Provide the player with a layer of automated flight control that overrides manual helm inputs to execute specific, high-level maneuvers (Emergency Stop, Intercept, Auto-Dock). The UI dials will animate to reflect the server-driven autopilot's commands, and any manual input instantly breaks the autopilot lock.

## Scope

- **Autopilot State:**
  - Add an `autopilot_mode` enum to `Ship` (e.g. `OFF`, `STOP`, `HOLD_STATION`, `INTERCEPT`, `DOCK`).
  - Add an RPC `request_autopilot(mode, target_id, target_pos)` to `ship.gd`.
- **The Execution Layer (Server-Side):**
  - In `_physics_process`, if `autopilot_mode != OFF`, bypass the player's manual `target_heading` and `target_velocity` inputs.
  - Compute the required thrust/heading dynamically each tick:
    - **`STOP`:** Find the retrograde vector of `linear_velocity`. Set `target_heading = retrograde`. If `abs(angle_diff) < 0.1` and `linear_velocity.length() > 5.0`, apply maximum safe thrust. Set `rcs_translation_cmd` to counter drift.
    - **`HOLD_STATION`:** Functions exactly like `STOP`, but also snaps the ship's current global position when activated. Once velocity reaches zero, the autopilot acts as a position-hold PID, automatically commanding translation thrust (via RCS or main engines) to return to that exact coordinate if bumped. This mimics how static objects like Beacons maintain their positions.
    - **`INTERCEPT`:** Point at the target's current position (`target_id`). Accelerate to combat/nav speed. Once within `DECEL_MARGIN` (calculated based on current speed and max acceleration), command retrograde thrust to achieve `rel_vel = Vector2.ZERO` at a 500-unit standoff.
    - **`DOCK`:** Attach a lightweight `beehave` behavior tree (or reuse `cargo_run_leaf`) to the player's ship to navigate the final approach lane.
- **The UI Layer (Client-Side):**
  - In `helm_panel.gd`, add toggle buttons for "STOP", "INTERCEPT", and "AUTO-DOCK".
  - If the server reports `autopilot_mode != OFF`, the player's mouse/gamepad inputs are locked out (or, better yet, attempting to use them fires `request_autopilot(OFF)` to instantly break the lock).
  - The `HeadingDial` and `EngineSlider` should read the server's actively commanded `target_heading` and `throttle` and animate them as "ghost" inputs, so the player sees the autopilot doing the flying.
- **Feedback:**
  - Provide a transient banner or a distinct sound effect (like a mechanical clunk or a UI chime) when autopilot engages and disengages.

## Test plan (Fable) — `test_helm_autopilot.gd`

1. **State Override:** When an autopilot mode is engaged, manual RPCs for helm input do not alter the ship's actual flight path.
2. **Auto-Stop Kinetics:** A ship moving at 800 m/s with a random spin is commanded to `STOP`. Within X seconds, both its `linear_velocity` and `angular_velocity` resolve to zero.
3. **Hold Station Kinetics:** A ship in `HOLD_STATION` mode is subjected to an external physics impulse (like a collision). The autopilot successfully fires engines/RCS to return it to the exact original hold position and zeros out its velocity.
4. **Intercept Math:** A ship is commanded to `INTERCEPT` a target moving at a steady 200 m/s. The ship successfully accelerates, approaches, and stabilizes at exactly the target's velocity at a safe standoff distance.
5. **Manual Breakaway:** Pushing a steering axis (simulating a gamepad input) while `autopilot_mode` is active instantly reverts the mode to `OFF` and returns control to the player.
