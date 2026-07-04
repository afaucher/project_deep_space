# M25 — Geometry unification + static outline v1

Status: DONE (2026-07-04). Depends on: nothing upstream (independent chain).
Design: `design_ideas/ship_outline_rendering.md` — "Decided path", v1 section.

Shipped: `get_local_aabb`/`get_bounding_radius` were already public on Ship
(promotion had landed earlier) — added the missing empty-components fallback
(returns `SHIP_COLLISION_RADIUS`); nav panel gained the v1 outline pass
(fade 3000→1500, stations 12000→6000, zoom-LOD floor), `outline_alpha()` +
`_outline_draw_list()` testable seams, `_bounds_radius_for()` and a
contact-side bounds treatment; `test_ship_geometry.gd` (items 1–9 green).
Avoidance item 10: clearance 662u — IDENTICAL to the pre-M25 baseline (rock
radius + MARGIN dominate that scenario), so no Steering radius floor was
added. Validation-phase catch: the outline quad's first corner anchored to
the ship's TRUE position while the other three anchored to the contact's
drawn position — skewed quads under estimate drift; fixed so all corners ride
`c_pos` (truth supplies only shape+rotation). Known-red set, verified
PRE-EXISTING via stash-baseline: `test_campaign_bootstrap`,
`test_cluster_loader`, `test_static_landmarks` — all dormancy/demotion
assertions broken by the editor-WIP full-sim default policy (commit 6533676),
not by M25; they go green if/when the bubble default returns. Follow-up noted:
the OWN-ship bounds ring reads `current_state.bounding_radius`, which main.gd
never sets (silent 50 fallback) — one-line state-packet fix, deferred (main.gd
out of this milestone's file scope).

## Goal

One canonical physical geometry derived from component rects, and the first
player-visible payoff: ship/station outlines that fade in at close range on the
nav map, so you stop navigating docking approaches against a lying 50-unit ring.

## Scope / deliverables

- `ship.gd`: promote the `_cached_bbox` logic to public
  `get_local_aabb() -> Rect2` and add `get_bounding_radius() -> float` (max
  corner distance from origin; cached; fallback 50.0 for a rect-less ship).
- `navigation_panel.gd`:
  - Repoint the hardcoded 50-radius "physical bounds" ring at
    `_bounds_radius_for(contact)` — target's `get_bounding_radius()` when the
    instance is live/valid, signature-scaled default otherwise.
  - **Outline v1 draw pass**: per-component rects, rotated to target heading,
    colored by component type, alpha from `outline_alpha(dist)`:
    `OUTLINE_FADE_START := 3000.0` (≈ shortest laser range),
    `OUTLINE_FULL := 1500.0` (= the fleet's `omni_collision` sensor range —
    the in-fiction instrument). Stations: `12000/6000` (scale is the point).
    On top of the existing zoom-LOD (skip when bounding radius × zoom < ~6px).
  - Testable seams REQUIRED (the test plan drives these): pure
    `static func outline_alpha(dist, full, start) -> float` and
    `_outline_draw_list(contact) -> Array` (entries: rect, world transform,
    type) separated from the actual `draw_*` calls.
- Explicit non-goals this milestone: physics collision stays the flat-50
  circle (bigger change, separately planned); no sensor gating (v2/M26 does it
  honestly).

## Risk to watch: Steering picks up real radii

`Steering._radius_of()` already calls `get_bounding_radius()` when the method
exists, else defaults to 300. Ships don't have it today — **adding it changes
avoidance behavior**: ship obstacle radii drop from 300 to ~20–75, so AI cuts
much closer around ships (rocks unchanged). This may be strictly better
(honest margins) or may re-introduce grazes. The validation phase measures it
(below) rather than guessing; mitigation if needed is a radius floor in
`Steering._radius_of` (e.g. `max(r, 100.0)`), NOT weakening the tests.

## Execution (Sonnet)

Hand the agent: this doc, the design doc's Decided-path section, `ship.gd`
(bbox + collision regions), `navigation_panel.gd`, `steering.gd`, guardrails.
Forbid: touching `SHIP_COLLISION_RADIUS`/collision shapes, `Steering` constants
(floor decision is validation-phase, evidence-based), sensor code.

## Test plan (Fable) — `test_ship_geometry.gd`

1. **AABB oracle.** For EVERY catalog ship (and M24 variants): recompute the
   union of component rects independently in the test and assert
   `get_local_aabb()` equals it exactly. Independent recomputation — not
   comparing the method to itself via `_cached_bbox`.
2. **Radius oracle.** `get_bounding_radius()` == max corner distance of that
   AABB (recomputed in-test). Plus the two anchor facts from the design doc:
   destroyer radius > 50 (the flat-ring lie, now fixed) and LAC radius < 25.
3. **Cache correctness.** Two calls return identical values; mutating a
   component's health (non-geometric) doesn't invalidate; the cached values
   match what the damage raymarch used (`_cached_bbox_min/max` consistency).
4. **Fallback.** A Ship with an empty `ship_components` returns radius 50.0,
   no crash.
5. **outline_alpha() pure-function battery.** alpha(1500)=1.0, alpha(3000)=0.0,
   alpha(2250)=0.5, clamped both sides, strictly monotonic across the window.
6. **Draw-list correctness.** Fake contact backed by a live frigate at
   distance 1000, rotation PI/4: `_outline_draw_list` returns one entry per
   component; every entry's rect ∈ the frigate's authored rect set; spot-check
   one known component's four world-space corners against hand-computed
   rotate+translate values (transform bugs are THE likely defect here — the
   engineering panel's 90° convention must not leak in).
7. **Stale contact safety.** Contact whose instance was freed → empty list, no
   error (this is a dead-reckoned contact after a kill — a hot path, and
   exactly the kind of missing-key/freed-instance frame-abort CLAUDE.md warns
   about).
8. **Bounds ring.** `_bounds_radius_for`: live destroyer contact → its true
   radius; invalid instance → signature-scaled fallback; never returns 0.
9. **Station gating.** A station contact at 8000 has alpha 0 under ship
   thresholds but > 0 under station thresholds — assert the type switch works.

Avoidance regression measurement (the Steering risk, quantified):
10. Re-run `test_avoidance` and `test_docking_multi` and **record the reported
    clearance margins** in the DONE note vs. their pre-M25 values (test output
    already prints "cleared by N units"). Gate: both tests pass AND no
    clearance below `Steering.MARGIN`. If violated → apply the radius floor,
    re-measure, record the floor value.

Pass marker: `>>> [TEST PASSED] test_ship_geometry <<<`.

## Validation phase checklist

- Run `test_ship_geometry`, then the full campaign suite (this touches
  `ship.gd` + nav panel): `test_docking`, `test_docking_multi`, `test_patrol`,
  `test_cargo_run`, `test_nav`, `test_nav_autopilot`, `test_avoidance`,
  `test_campaign_bootstrap`, `test_cluster_bubble`, `test_cluster_loader`,
  `test_static_landmarks`, `test_ship_designs`, plus M21–M24 tests.
- Manual acceptance (record): campaign mode, fly the Ironhold approach —
  station outline fades in by 6000, frigate outline by 3000, ring hugs the
  destroyer instead of undershooting it.
- Mark DONE + commit (`feat: M25 derived ship geometry + close-range outline v1`).
