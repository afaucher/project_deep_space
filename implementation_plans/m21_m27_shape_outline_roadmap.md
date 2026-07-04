# M21–M27 roadmap — hull shape grammar + close-contact outlines

Source designs: `design_ideas/hull_shape_grammar.md`,
`design_ideas/ship_outline_rendering.md`. Numbering continues from the
campaign milestones (M14–M20, complete).

## Dependency DAG

```
M21 parts catalog ──────► M22 hull builders ─────► M27 catalog expansion
        │                                              ▲    ▲
        └────────► M24 delta variants ─────────────────┘    │
M23 layout coverage checks ────────────────────────────────►┘

M25 geometry unification + outline v1 ──► M26 sensor-dot outlines
        (independent chain — can interleave anywhere)
```

Hard dependencies: M22←M21 (re-expression proof uses parts), M24←M21 (swaps
pull from the catalog), M26←M25 (dots render through the v1 pass and geometry
helpers), M27←{M21, M22, M23} (new ships are authored *in* the grammar and
gated by the mechanized checks). M23 and M25 have no upstream dependencies.

## Recommended order

M21 → M22 → M23 → M24 → M25 → M26 → M27.

Rationale: the grammar chain runs first because M23's mechanized checks must
exist *before* we start generating shapes in volume (M27), and M24 gives the
campaign visible traffic variety cheaply. The outline chain (M25/M26) is
independent and slots before M27 so the new silhouettes land visible. If close-
range navigation pain becomes urgent (docking approaches), M25 can be pulled
forward to any point without breaking anything.

## Execution model (applies to every milestone)

Each milestone runs as a two-phase loop:

1. **Implement — Sonnet subagent.** One agent per milestone via the Agent tool
   (`model: "sonnet"`), prompted with: the milestone plan doc, the relevant
   design doc sections, and the standing guardrails below. The agent writes
   code + the new tests named in the plan, runs them, and reports.
2. **Validate — Fable (main session).** The test plans below were authored at
   Fable effort because they are the actual gate. Validation phase: run the
   milestone's new tests, run the regression set, diff-review the
   implementation against the plan (especially validator/test changes — an
   implementer weakening a test to pass it must be caught here), triage any
   new validator warnings, then mark the plan DONE with a "Shipped:" note and
   commit.

**Standing guardrails handed to every implementation agent:**
- Reference scripts via `preload("res://...")` consts, never bare `class_name`
  globals (headless class-cache gap — see CLAUDE.md).
- Never validate with `--headless --check-only --script`; validate by running a
  test that loads the script.
- One headless Godot instance at a time; sims/tests run sequentially.
- Tests print `>>> [TEST PASSED] <name> <<<` on success and exit 0; failures
  exit nonzero.
- `Dictionary[key]` on a missing key aborts the rest of the function for that
  frame — use `.get(key, default)` for any non-guaranteed component field.
- `var x := arr.filter(...)` doesn't compile; write `var x: Array = ...`.
- Indent with tabs, match surrounding style, commit nothing — the validation
  phase commits.

**Regression set** (run in validation phase; grows as milestones land):
- Always: `test_ship_designs`, plus every prior M21+ test
  (`test_parts_catalog`, `test_hull_builders`, `test_layout_checks`,
  `test_ship_variants`, `test_ship_geometry`, `test_sensor_dots`).
- When a milestone touches `ship.gd`, the sensor sweep, or the nav panel
  (M25/M26 do): the campaign suite too — `test_docking`, `test_docking_multi`,
  `test_patrol`, `test_cargo_run`, `test_nav`, `test_nav_autopilot`,
  `test_avoidance`, `test_campaign_bootstrap`, `test_cluster_bubble`,
  `test_cluster_loader`, `test_static_landmarks`.

## Milestones

| # | Name | Delivers | Test gate |
|---|------|----------|-----------|
| M21 | Parts catalog | `parts_catalog.gd`, marks with spec×volume invariant | `test_parts_catalog` |
| M22 | Hull builders | `hull_builder.gd` (frame/mirror/rotate/…), LAC re-expression proof | `test_hull_builders` |
| M23 | Layout coverage checks | validator: hull-coverage + active-surface warnings, fleet audit ratchet | `test_layout_checks` + audit in `test_ship_designs` |
| M24 | Delta variants | `Variants.apply`, pirate LAC + ore shuttle, auto-enumerated validation | `test_ship_variants` |
| M25 | Geometry unification + outline v1 | `get_local_aabb`/`get_bounding_radius`, nav ring repoint, static fade-in outline | `test_ship_geometry` |
| M26 | Sensor-dot outlines | per-bin silhouette raycasts → dot cloud rendering | `test_sensor_dots` |
| M27 | Catalog expansion | freighter, pinnace, mine, defence pod, asteroid station | per-ship gates in plan |
