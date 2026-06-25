# Design Ideas Implementation Plan

Source docs: `design_ideas/ship_is_the_parts.md`, `responsive_heat_em.md`, `real-time-sensor-signal.md`, `point_defence.md`, `missile_tracking_tradeoffs.md`, `comms.md`.

## Dependency graph

```
M1 Component Architecture (ship_is_the_parts)
   |--> M2 Dynamic Heat/EM per component (responsive_heat_em)
   |        |--> M4 Sensor history UI (real-time-sensor-signal)
   |
M3 PD Target Prioritization (point_defence)        [independent]
M5 Missile Lost-Lock Behavior (missile_tracking_tradeoffs)  [independent, needs decision]
   |
   `--> M6 Multi-Ship Contact Fusion (comms)   [needs stable per-ship contact model;
                                                 benefits from M4's signal model]
```

M3 and M5 have no upstream dependency and are the cheapest, highest-value items — do them first while M1 is designed.

---

## M1 — Component Architecture Refactor (`ship_is_the_parts.md`)
**Why first:** every other milestone (per-component heat/EM, multi-ship sensor fusion) currently assumes ship-wide stats computed ad hoc in `ship.gd` (1200 lines, monolithic). Decoupling "ship" from "components" is the prerequisite for the rest making sense rather than being bolted on twice.

**Scope:**
1. Define a `Component` base resource/node with: physical extents + hardpoint, configuration (class/variant), runtime state (ammo, powered, health), and contribution functions (power, mass, heat, EM).
2. Move ship-wide aggregates (power, mass, EM, heat) to be *summed from components* instead of hardcoded on `Ship`. Support redundancy (e.g. two reactors, one needed).
3. Support one-to-many / many-to-one hardpoints by splitting the sensor dome into discrete sub-components (explicitly punted to "avoid for now" per the doc — keep it that way for this milestone).
4. Apply the same model to `scripts/ships/missile.gd` so missiles are "small ships" with the same component contract, just smaller classes.
5. Add a ship-design validator: each component class must meet baseline dimension/performance thresholds.

**Touches:** `scripts/ships/ship.gd`, `scripts/ships/missile.gd`, `scripts/ships/buoy.gd`, `scripts/ships/frigate.gd`, `scripts/ships/sensor_drone.gd`, `scripts/engineering_panel.gd`.

**Done when:** `test_component_states.gd` and `test_damage_propagation.gd` pass against the new model with no ship-wide special-casing of power/mass/heat/EM left in `ship.gd`.

Detailed design, including the sensor-dome split decision and the weapon-side merge it generalizes to, is in [m1_component_architecture_design.md](m1_component_architecture_design.md). That doc also adds **M1c**: a stateless per-weapon-class `WeaponBehavior` registry, replacing the `if weapon_type == "laser": ... elif ...` dispatch in `fire_weapon`/`_process_point_defense`/the heat-EM loop. M1c should land before M2 — M2's event-driven heat/EM pulses are the same "lifecycle state in the component dict, decay logic in the behavior class" pattern, just for reactor/engine/hull instead of weapons.

---

## M2 — Dynamic Per-Component Heat/EM (`responsive_heat_em.md`) — DONE
**Depends on:** M1/M1b (per-component mass/power/thrust/torque/heat helpers already landed), and M1c (so weapon fire pulses use the same behavior-class pattern reactor/engine pulses will reuse, instead of more inline `elif`s in `Ship`).

**Scope:**
1. Fix the combat-heat overwrite bug: `take_damage()`'s per-component heat increment is currently discarded every physics frame by the heat/EM dispatch loop's unconditional overwrite.
2. Unify EM directionality: generalize the cone-falloff mechanism sensors already use to every emitter (reactor/engine/passive default omni, sensors and weapons default directional) instead of the current two-tier scalar-plus-rear-bias hack.
3. Event-driven pulses: firing a laser → EM pulse (mechanic already exists in `LaserBehavior` but isn't wired into detection yet) + waste heat; taking a hit → heat burst; damaged engine → EM spike (currently inverted — damage suppresses emission instead of spiking it); reactor destroyed → 1-2s EM "whiteout".
4. Heat model resolved: no inter-component bleed, ship-wide cap only (per-component `heat` stays a signature/display quantity, not a second damage model).

**Touches:** `scripts/ships/ship.gd` (heat/EM dispatch loop, `_run_sensor_sweep`, `get_signature`), `scripts/components/weapon_behavior.gd` + `weapons/*_behavior.gd` (fire pulses).

**Done when:** EM/heat values visibly change over time per all four event triggers above, every emitter is direction-aware, validated by extending `test_component_states.gd`.

Detailed design, findings, and task breakdown are in [m2_dynamic_heat_em_design.md](m2_dynamic_heat_em_design.md).

---

## M3 — Point Defense Target Prioritization (`point_defence.md`) — DONE
**No dependencies — do this anytime, including before M1.**

**Scope:**
1. Replace "fire every weapon at each target before moving to next" with sort-by `(times_fired_ascending, range_ascending)`.
2. When selecting a weapon for a target, pick the shortest-range ready laser, reserving long-range lasers for farther targets.

**Touches:** `scripts/ships/ship.gd` (`_process_point_defense()`).

**Done when:** `test_point_defense.gd` covers the new sort order and weapon-selection rule.

Implementation notes: `active_contacts[c_id]["pd_shots_fired"]` is the persistent times-fired counter (lives on the contact dict, naturally resets when a contact is lost and re-acquired). Also folded in the long-standing `PD_RANGE` TODO -- removed the flat ship-wide engagement-range constant and replaced it with each laser's own authored `range` field (already checked per-weapon by `LaserBehavior.can_fire()`); the remaining `max_ready_range` pre-filter is just "could any ready laser conceivably reach this," not an engagement-range source of truth. No ship today has lasers with different ranges, so the weapon-selection rule is implemented and unit-tested but currently a no-op on the only ship that exists -- it'll become visible the moment a ship design mixes laser ranges.

---

## M4 — Real-Time Sensor Signal History UI (`real-time-sensor-signal.md`) — DONE
**Depends on:** M2 (there's nothing meaningful to chart over time until heat/EM are dynamic per-component signals rather than static).

**Scope:**
1. Add a "what do we know about my target" panel showing signal history over time (not just the current spider chart snapshot).
2. Add relative velocity and acceleration meters for combat.
3. Surface raw EM/heat time-series so players can spot patterns (e.g. heat dropping off) ahead of/alongside the classifier.

**Touches:** `scripts/panels/weapons_panel.gd` (targeting computer: history graph, closing-rate/acceleration), `scripts/timeseries_graph.gd`, `scripts/spider_chart.gd`.

**Done when:** a target hit by a weapon shows a visible, time-extended signal change in the UI, backed by `test_classifiers_e2e.gd`.

Implementation notes: items 1 and 3 landed in `weapons_panel.gd`'s TARGETING COMPUTER section (not `sensor_panel.gd`/`terminal_display.gd` as originally sketched -- that's where the locked-target context already lived) via `TimeSeriesGraph`, an independently-auto-scaling rolling plot floored at `SpiderChart.MAX_HEAT_DISPLAY`/`MAX_EM_DISPLAY` so ordinary idle jitter doesn't fill the scale while real spikes (reactor whiteout, fire pulses) still aren't clipped. Item 2 (closing rate + closing acceleration) is computed entirely client-side from data already in the state packet, no network changes. The "Done when" bar is covered by `test_classifiers_e2e.gd` firing a real laser hit and asserting `current_heat` spikes then dissipates within 5 seconds.

---

## M5 — Missile Lost-Lock Behavior (`missile_tracking_tradeoffs.md`)
**No hard dependency**, but should be decided before M6 since handed-off contact data (recent commits already pass contact data to missiles on launch) feeds directly into whichever approach is chosen.

**Scope (decision required before implementation):**
- Pick one of: dumb-fire (A), seek-last-coordinate (B), dead-reckoning (C), or search-pattern (D) as the default for the current single missile type.
- Recommendation: implement **C (dead reckoning)** first — it reuses the position+velocity hand-off already built (per `192ef99`, `4ee5c6f` commits) and is a strict superset of B in complexity terms, while D's search pattern can be layered on top later as a missile "class" without touching the core fallback.
- Keep the approach parameterized per missile class so A/D can be added later without rework (ties into M1's component-class system for missiles).

**Touches:** `scripts/missile_controller.gd`, `scripts/ships/missile.gd`.

**Done when:** `test_missile_ai.gd` covers lost-lock fallback behavior for the chosen approach.

---

## M6 — Multi-Ship Contact Fusion / Comms Relay (`comms.md`)
**Depends on:** a stable per-ship contact/sensor data model (already exists informally; M4 makes the "freshness vs. fusion" tradeoff visible to players, which should inform which fusion strategy to ship).

**Scope:**
1. Point-to-point radio link between friendly ships with line-of-sight requirement.
2. Share contact lists between linked ships; treat relayed contacts as additional sensor signal sources.
3. Start with **simplest fusion: take the freshest contact report** per target (explicitly called out as the easy first cut in the doc). Defer the recency-weighted quantile estimator approach.
4. Defer proxied/multi-hop relay delay (A→B→C) — explicitly punted in the doc.

**Touches:** new `scripts/comms_module.gd` (or similar) wired into `scripts/ships/ship.gd` contact list; `scripts/sensor_panel.gd` for display of relayed vs. direct contacts.

**Done when:** two friendly ships in line-of-sight share contacts, and a new e2e test (e.g. `test_comms_relay.gd`) verifies freshest-wins resolution.

---

## Suggested execution order

1. M3 (PD prioritization) — quick win, no dependencies.
2. M5 (missile lost-lock, Approach C) — quick win, no dependencies.
3. M1 (component architecture) — foundational, largest effort.
4. M2 (dynamic heat/EM) — built on M1.
5. M4 (sensor signal history UI) — built on M2.
6. M6 (comms relay) — built on stable contact model, informed by M4.
