# Project Deep Space - Test Coverage Report

*Last Updated: 2026-07-06*

The test suite has grown significantly and now contains over 50 automated tests running in headless mode. The tests cover a wide variety of systems from UI input to full AI combat engagements.

## Currently Covered Scenarios

### 1. Ship Design & Engineering
- **Component Layout & Geometry:** `test_ship_geometry.gd`, `test_ship_silhouette.gd`, `test_hull_builders.gd`, `test_layout_checks.gd`, `test_parts_catalog.gd`
- **Ship Configurations:** `test_ship_designs.gd`, `test_ship_variants.gd`
- **Component States & Power Grid:** `test_component_states.gd` verifies reactor limits, power toggles, and component isolation.
- **Damage Propagation:** `test_damage_propagation.gd` ensures hits correctly degrade individual sub-components (engines, weapons) and apply global effects.
- **Collision Mechanics:** `test_collision_damage.gd`, `test_collision_perf.gd`, `test_collision_shapes.gd` check physical interactions and damage thresholds.

### 2. AI & Behaviors
- **Combat Behaviors:** `test_ai_duel.gd`, `test_ai_vs_legacy.gd`, `test_ai_engage_tree.gd`, `test_ai_disengage.gd` test the Beehave-based drone AI's combat logic (broadsides, retreats, engagements).
- **Navigation & Avoidance:** `test_avoidance.gd`, `test_patrol.gd` check collision avoidance and waypoint following.
- **Ordnance & Defense:** `test_missile_ai.gd`, `test_point_defense.gd`, `test_mine.gd` cover automated tracking, PD interception, and mine proximity fusing.

### 3. Sensors, Stealth & Signatures
- **Classification:** `test_classifiers.gd`, `test_classifiers_e2e.gd`, `test_classify_ships.gd` test the signature evaluation logic (Heat, EM, Cross-Section, Density).
- **Sensor Mechanics:** `test_sensor_dots.gd`, `test_signature_bleed.gd` cover sensor resolution limits and signature blooming.
- **Occlusion & Stealth:** `test_sensor_stealth.gd` verifies line-of-sight occlusion by asteroids and passive EM detection mechanics.

### 4. Navigation & Flight
- **Flight Physics:** `test_inertial_flight.gd`, `test_helm_input.gd` verify Newtonian physics and zero-drag thrust application.
- **Autopilot & Routing:** `test_nav.gd`, `test_nav_autopilot.gd` test beacon-graph routing and automated transit.

### 5. Campaign, Docking & Clusters
- **Campaign Loading:** `test_campaign_bootstrap.gd`, `test_cluster_loader.gd`, `test_cluster_bubble.gd`, `test_static_landmarks.gd` test cluster streaming and entity persistence.
- **Port Operations:** `test_docking.gd`, `test_docking_multi.gd`, `test_freighter_docking.gd`, `test_cargo_run.gd`, `test_port_zone.gd` cover the capture radius, slip assignment, and zone boundary logic (M31).

### 6. Weapons & Combat
- **Weapon Systems:** `test_volley_metering.gd`, `test_weapon_groups.gd` verify weapon fire control, broadside synchronization, and reload times.

### 7. Comms & Networking
- **Dialogue & Messaging:** `test_comms_chat.gd`, `test_comms_relay.gd` verify NPC dialogue sequences and text relays.
- **Network Packets:** `test_nav_comms_range_packet.gd` checks payload serialization limits.

---

## Major Coverage Gaps (To Reassess)

1. **Multiplayer State Sync & RPC Emulation**
   - **Gap:** The massive `_distribute_state()` payload parsing is still mostly tested manually. We don't have a headless test that boots up a mock Client and mock Host to verify that UI components update correctly from incoming RPC dicts without type errors.
   - **Risk:** High. Changing a dictionary key on the host can easily break the client UI silently.

2. **Full E2E Campaign Progress**
   - **Gap:** While we have `test_campaign_bootstrap.gd` and `test_cargo_run.gd`, we don't have a test that runs a complete loop of discovering a transponder, talking to an NPC to unlock a route, jumping clusters, and completing a contract.
   - **Risk:** Medium. Story-driven mechanics might break in between isolated system tests.

3. **Performance Regressions (Stress Tests)**
   - **Gap:** We have `test_collision_perf.gd`, but no overarching stress test for hundreds of missiles, sensor dots, and AI trees running concurrently in a single cluster.
   - **Risk:** Low right now, but will increase as clusters get more populated.
