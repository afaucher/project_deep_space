# Project Deep Space - Test Coverage Report

## Currently Covered Scenarios

1. **Ship Classification & Sensor Signatures** (`test_classifiers.gd`, `test_classifiers_e2e.gd`)
   - Signature evaluation based on Heat, EM, Cross-Section, and Density.
   - Classification fallbacks (e.g., `UNIDENTIFIED VESSEL` vs `WRECKAGE` vs `FRIENDLY ORDNANCE`).

2. **Flight Mechanics** (`test_inertial_flight.gd`, `test_helm_input.gd`)
   - Newtonian physics behavior (zero-drag environment).
   - Expected application of thrust vectors and helm rotation.

3. **Ordnance AI & Tracking** (`test_missile_ai.gd`)
   - Tests that a fired missile can independently locate, steer towards, and hit a stationary ship using its own active sensor sweep logic.

4. **Drone AI E2E Combat** (`test_e2e_drone_vs_bouy.gd`)
   - Spawns an AI Drone and a target Buoy.
   - Verifies the drone can autonomously acquire the buoy, maneuver into range, fire a missile, and successfully destroy the buoy within a time limit.

5. **Environmental Physics** (`test_asteroid.gd`)
   - Basic asteroid physical instantiation and collision behavior.

## Major Coverage Gaps (To Reassess)

1. **Engineering & Subsystem Damage**
   - **Gap:** We have no automated tests verifying that taking laser/missile damage properly trickles down into individual subsystem modules based on hit location.
   - **Risk:** We could easily break the "engines damaged -> max thrust reduced" or "weapons disabled -> can't fire" logic.

2. **Power Grid & Sensor Isolation**
   - **Gap:** The massive GDScript dictionary sharing bug we just fixed slipped through because we don't have a test that validates isolating power toggles between two independent ships.
   - **Risk:** High. We need a test that spawns two ships, disables sensors on Ship A, and ensures Ship B can still scan.

3. **Sensor Occlusion & Stealth**
   - **Gap:** We need a scenario where a ship tries to hide behind an asteroid (occluding the line-of-sight raycast) or powers down to `silent_running` to drop below the active radar's detection threshold.

4. **Multiplayer State Sync**
   - **Gap:** The `_distribute_state()` payload parsing is untested. We don't verify if the dictionary sent by the host correctly unpacks on the client UI side without throwing type errors.
