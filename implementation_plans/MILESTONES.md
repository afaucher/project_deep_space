# Milestone status index

One line per milestone. No prose. For the reasoning behind anything here, open
the referenced doc.

**BUILT** shipped · **PARTIAL** some sub-milestones done · **SCOPED** planned, not built · **SKIP** deliberately not doing

Pre-M48 status is taken from each plan doc's own DONE/BUILT markers.

| M | Name | Status | More info |
|---|---|---|---|
| M1 | Component architecture | BUILT | `m1_component_architecture_design.md` |
| M2 | Dynamic per-component heat/EM | BUILT | `design_ideas_implementation_plan.md` |
| M3 | PD target prioritization | BUILT | `design_ideas_implementation_plan.md` |
| M4 | Sensor signal history UI | BUILT | `design_ideas_implementation_plan.md` |
| M5 | Missile lost-lock behaviour | **SKIP** | dumb-fire fallback judged sufficient |
| M6 | Datalink relay + contact fusion | BUILT | `design_ideas_implementation_plan.md` |
| M7 | IFF beacons | BUILT | `design_ideas_implementation_plan.md` |
| M8 | Text comms | BUILT | `design_ideas/comms.md` |
| M9 | Ship catalog + component tiers | BUILT | `m9_ship_catalog_design.md`, `m9b`, `m9c` |
| M10 | Sandbox spawn | BUILT | `m10_sandbox_spawn_design.md` |
| M11 | Flight input | BUILT | `m11_flight_input_design.md` |
| M12 | AI behaviour | BUILT | `m12_ai_behavior_design.md` |
| M13 | Playable sandbox | BUILT | `m13_playable_sandbox_design.md` |
| M14 | Cluster sim bubble | BUILT | `m14_cluster_sim_bubble_design.md` |
| M15 | Cluster loader | BUILT | `m15_cluster_loader_design.md` |
| M16 | Static landmarks | BUILT | `m16_static_landmarks_design.md` |
| M17 | Nav routing | BUILT | `m17_nav_routing_design.md` |
| M18 | Patrol AI | BUILT | `m18_patrol_ai_design.md` |
| M19 | Docking | BUILT | `m19_docking_design.md` |
| M20 | Traffic wiring | BUILT | `m20_traffic_wiring_design.md` |
| M21–M27 | Parts catalog, hull builders, outlines, catalog expansion | BUILT | `m21_m27_shape_outline_roadmap.md` |
| M28–M30 | Collision (kinematic → accurate) | BUILT | `m28_m30_collision_roadmap.md` |
| M31–M36 | Port authority (zones, control, corridors) | BUILT | `m31_m36_port_authority_roadmap.md` |
| M37 | Helm autopilot | BUILT | `m37_helm_autopilot_roadmap.md` |
| M38 | Angle-accurate signatures | BUILT | `m38_angle_accurate_signatures_design.md` |
| M39–M44 | Homefront / family | BUILT | `m39_m44_homefront_roadmap.md` |
| M45 | Physics perf (+45b datalink, +45c PD kill-wave) | BUILT | `m45_physics_perf_investigation.md` |
| M46–M47 | Port zone visuals, NPC compliance | BUILT | `m46_m47_port_zone_visuals_roadmap.md` |
| M48 | Standings & flags (IFF v2) | BUILT | `m48_standings_flags_design.md` |
| M49 | Hail protocol, DEMAND verb, honored stop | BUILT | `m48_m55_economy_piracy_roadmap.md` |
| M50 | Pirate hulls + piracy behaviour tree | BUILT | `m50_pirate_tree_design.md` |
| M51 | Pirate guild director | BUILT | `m51_pirate_guild_design.md` |
| M52 | Patrol interdiction + SOS (a/b/c/d) | BUILT | `m52_patrol_interdiction.md` + `m52a`–`m52d` |
| M53 | Traffic guild + demand routing (a/b/c/d) | BUILT | `m53a`, `m53bc`, `m53c`, `m53d` |
| M54 | Credits + escort & hunt missions | SCOPED | `m48_m55_economy_piracy_roadmap.md` — no code |
| **M55** | **Physical cargo + boarding** | **PARTIAL** | `m48_m55_economy_piracy_roadmap.md` |
| M55a | — the manifest | BUILT | commit `de02ce7` |
| M55b | — theft moves goods | BUILT | commit `b77955b` |
| M55c | — capacity from parts | SCOPED | deferred: not the binding constraint (D71) |
| M55d | — mid-tier hull | SCOPED | load-bearing for M55c calibration |
| M55e | — boarding / inspection | SCOPED | `m55e_boarding_inspection.md` |
| M55f | — validator learns roles | SCOPED | must follow M55c |
| M56 | Contact freshness timestamps | BUILT | `m56_contact_freshness_timestamps.md` |
| M57 | Incidents as evidence | BUILT | `m57_m61_information_economy_roadmap.md` |
| M58 | Two tiers of transport (mailbag) | BUILT | `m57_m61_information_economy_roadmap.md` |
| M59 | Risk-aware routing + patrol director | BUILT | `m57_m61_information_economy_roadmap.md` |
| M60 | Pirate information economy | SCOPED | `m57_m61_information_economy_roadmap.md` |
| M60d | — port control logs | SCOPED | `m60d_port_control_logs.md` — no code |
| M61 | Competing bands under one flag | **SKIP** | no gameplay value for the cost |
| M62 | Overdue detection | SCOPED | `m62_overdue_detection.md` |
| M63 | Pirate information network | MERGED | folded into M60/M60d |
| M64 | Price fog | SCOPED | `m64_price_fog.md` — blocked on M64c decision |
| M65 | Pirate identity kit | SCOPED | `m65_pirate_identity_kit.md` |
| M66 | Cargo route planning (multi-stop, mixed loads) | SCOPED | `m66_cargo_route_planning.md` |
| — | Human capacity (crew/quarters) | SCOPED | sibling of M55; `m48_m55_economy_piracy_roadmap.md` |

## Running decision log

`design_ideas/2026-08-02-three-systems-ledger.md` — D1–D73, every gameplay and
policy decision with what was measured. Long by design; this index is the short
form.
