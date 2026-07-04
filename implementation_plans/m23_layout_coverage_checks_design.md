# M23 — Mechanized layout checks (hull coverage + active surfaces)

Status: DONE (2026-07-04). Depends on: nothing (validator-only). Ordered before M24/M27
so shape generation never outruns review capacity.

Shipped: `_check_hull_coverage` + `_check_active_surface` in the validator
(ray march at the damage-raymarch step 2.0 so verdicts agree with real damage
propagation; omnis coverage-checked on all four faces; engines' active face
always −X), `scripts/tests/test_layout_checks.gd` (fixture items 1–8), and the
`EXPECTED_LAYOUT_WARNINGS` ratchet in `test_ship_designs.gd` (multiset, both
directions, unregistered catalog ships fail). Registry reviewed line-by-line
in validation phase — anchor notes: frigate 13 warnings (all 4 end-of-row
sponson weapons flag; middle tubes are genuinely covered by neighboring
tubes); station PD turrets flag 2 faces, not the guessed ~3 (inboard face
really touches the arm cap — verified by independent re-trace); destroyer
near-clean at 2, one of which is a REAL find: `dir_high_res` fire-control
dish is masked by `hull_spine_mid3` directly in front of it. Decisions:
frigate sponsons accepted as historical (re-wrap is an M24-style refit
candidate); destroyer dish flagged as a future fix candidate (harmless today
— sensors don't raycast yet — but M26 sensor-dot work is where it would start
to matter). Case 1 of test_ship_designs now filters only the two new layout
fields; all prior coverage intact.
Design: `design_ideas/hull_shape_grammar.md` §6; rules being mechanized:
`.agents/skills/ship-design/SKILL.md` §4a (hull-first) and §4e (active surfaces).

## Goal

Turn the ship-design skill's two human-eyeball checklist items into validator
**warnings**, so a shape experiment is machine-reviewed instead of needing an
engineering-panel session per design. Then audit the existing fleet and freeze
the result as a ratchet.

## Scope / deliverables

- `ship_design_validator.gd` gains two checks (static, operating on the
  components array only — no Ship instance; ship AABB computed from rects):
  - `_check_hull_coverage` — for each weapon/sensor/engine, cast an outward ray
    from the center of each **non-active** face (start 0.5u outside the face,
    march at the damage-raymarch step). If the ray exits the ship AABB without
    crossing any other component rect → warning `exposed face <dir>` on that
    component. Omni sensors have no active face → all four faces checked
    (fully enclosed is the good state).
  - `_check_active_surface` — the face in the component's `heading` direction
    (mapped to the nearest cardinal: 0→+X, PI→−X, ±PI/2→±Y; engines' active
    face is always −X) must reach the AABB edge **without** crossing another
    component → else warning `masked active face`. Omni (arc_width ≈ TAU)
    exempt; comms/reactor/hull exempt from both checks.
- Both severity `"warning"` — `ok` stays true. Deliberate glass-cannon designs
  stay legal; the point is visibility, not prohibition.
- **Fleet audit ratchet** in `test_ship_designs.gd`: a per-ship
  `EXPECTED_LAYOUT_WARNINGS` registry (component_id + field), asserted to match
  the actual warning set exactly — warnings can neither silently appear nor
  silently vanish.

## Execution (Sonnet)

Hand the agent: this doc, grammar doc §6, `ship_design_validator.gd`,
`ship.gd`'s damage-raymarch block (for step-size and containment semantics —
the checks must agree with how damage actually propagates), guardrails.
Forbid: changing any existing check's behavior, changing severities, touching
ship files. Known audit expectations (sanity anchors — the agent enumerates
the full sets, validation phase reviews them):
- Frigate port/stbd tubes + broadside lasers WILL flag exposed faces (the
  sponson layout predates the skill; it is the skill's own "BAD" example).
- Station PD turrets sit entirely outside the arm caps (e.g. small station
  `pd_fwd` at x 70–90 vs cap ending at 70) — expect 3-face exposure warnings.
- Destroyer should come out near-clean (it was authored to the skill).

## Test plan (Fable) — `test_layout_checks.gd` + `test_ship_designs` extension

Fixture tests (hand-built component arrays, no Ship node needed):
1. **Enclosed weapon** — hull on three faces, active face at the AABB edge →
   zero warnings. The baseline-good case.
2. **Exposed flank** — same but one flanking hull removed → exactly ONE
   coverage warning, naming the component AND the face direction. Count must
   be exact (over-firing checks are as useless as under-firing ones).
3. **Masked active face** — hull rect directly in front of a laser's heading →
   exactly one active-surface warning.
4. **Engine semantics** — engine protruding aft past hull: NO coverage warning
   for the aft face (it's the active face); a rect placed behind the engine →
   masked warning. This is the skill's "one acceptable protrusion" rule,
   encoded.
5. **Omni sensor** — fully enclosed omni → zero warnings (enclosure is good,
   no masking concept applies); omni with an exposed face → coverage warning.
6. **Directional sensor** — flush with the hull edge (active face at AABB
   boundary) → no warning; buried one rect deep → masked warning.
7. **Severity contract** — a fixture with both warning types still returns
   `ok == true`, and every new violation dict carries
   `severity == "warning"` and the standard keys (component_id/field/reason).
8. **Negative control** — a deliberately terrible fixture (all guns hanging in
   space) must produce ≥ N warnings; guards against both checks silently
   no-opping.

Fleet audit (in `test_ship_designs.gd`):
9. For every catalog ship, assert actual layout-warning set ==
   `EXPECTED_LAYOUT_WARNINGS[ship]` exactly (set equality on
   component_id+field pairs). The frozen sets are reviewed line-by-line in
   validation phase against the sanity anchors above before being accepted.
10. All ships still `ok == true` — proves nothing got promoted to error.

Pass markers: `>>> [TEST PASSED] test_layout_checks <<<` and the existing
`test_ship_designs` marker.

## Validation phase checklist

- Run `test_layout_checks`, `test_ship_designs`, `test_parts_catalog`,
  `test_hull_builders`.
- Review the frozen `EXPECTED_LAYOUT_WARNINGS` sets against the three sanity
  anchors; any surprise entry gets explained or fixed before accepting.
- Decide-and-record (in this doc's DONE note): frigate sponsons — accept the
  warnings as historical, or schedule a re-wrap. Default: accept; re-wrap is
  an M24 delta-variant candidate ("frigate refit"), not a blocker.
- Mark DONE + commit (`feat: M23 layout coverage + active-surface validator checks`).
