# Helm Autopilot Control Scheme

## The Concept
Currently, the helm is a strict "fly-by-wire" system where the player dials in a target heading and thrust/velocity, and the ship's PID controller executes it. 

The new proposal adds an "Autopilot Mode" layer to the helm. The player can toggle between **Manual** (the current fly-by-wire) and a set of high-level **Autopilot** macros. When an autopilot mode is engaged, it overrides the manual dials and assumes control of the ship's PID inputs (and RCS thrusters) to achieve specific navigational goals.

## Proposed Autopilot Modes

1. **Emergency Stop (Zero All Motion)**
   - **Behavior:** Arrests all linear and angular momentum as quickly as possible. The ship points its main engines opposite its velocity vector (retrograde) and fires at maximum safe thrust, while RCS thrusters nullify any spin and drift. 
   - **UI:** A big red "STOP" button. When active, the helm dials lock and snap to the retro-burn profile.

2. **Hold Station (Zero Motion & Hold Position)**
   - **Behavior:** Acts like an Emergency Stop initially to zero all velocity. However, it also records the ship's exact global coordinate when activated. Once stopped, it acts as a position-hold PID—if the ship is bumped by an asteroid or another vessel, the autopilot will automatically fire engines and RCS to translate back to that exact coordinate. This mimics the station-keeping behavior of static beacons and stations.
   - **UI:** A "HOLD" toggle, commonly used when observing an area, mining, or loitering near a port.

3. **Intercept Target (Head Towards & Zero-Zero)**
   - **Behavior:** Calculates a rendezvous trajectory with the currently selected target. It points the ship at the target, accelerates to a cruising speed (or combat speed), and times a deceleration burn so that the ship comes to a complete halt (zero relative velocity) at a safe standoff distance from the target.
   - **UI:** An "Intercept" toggle. It relies on the contact selected in the Sensor/Contacts panel.

4. **Auto-Dock**
   - **Behavior:** The "fast way" to dock. When a docking clearance is granted (or an open port is nearby), engaging Auto-Dock hands the ship over to the same Behavior Tree (Beehave) logic that NPC cargo haulers use. The ship will automatically align with the approach lane, fly the glide slope, and slide into the slip.
   - **UI:** A "Dock" toggle that illuminates when a valid docking target or clearance is available. 

## Control Scheme & Architecture
- **The Override Mechanism:** The `helm_panel.gd` needs an `autopilot_mode` enum. When `autopilot_mode != MANUAL`, the player's gamepad/mouse inputs on the dials are ignored (or breaking the stick instantly disengages the autopilot).
- **Server-Side Execution:** The actual autopilot logic shouldn't run purely in the UI client. The UI should send an RPC (e.g., `set_autopilot_mode(mode, target_id)`). The server-side `Ship` then runs the autopilot logic (possibly delegating to a lightweight Beehave tree or a hardcoded state machine) and feeds the calculated `target_heading` and `target_velocity` into the ship's `_physics_process`.
- **UI Feedback:** Even while the server is flying the ship, the client's `helm_panel` dials (Heading Bug, Thrust Slider) will animate like a player piano, showing exactly what the autopilot is commanding.

## Open Design Questions
- Does pushing the manual flight stick during an autopilot sequence automatically disengage the autopilot (like cruise control in a car), or does it require an explicit toggle off?
- For the Intercept mode, how do we handle obstacles? Does it just fly a straight line (and rely on the player to disengage if an asteroid is in the way), or do we hook it into the NavServer for full pathfinding?
