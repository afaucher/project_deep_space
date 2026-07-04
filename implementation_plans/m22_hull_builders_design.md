# M22 — Hull builders (the grammar ops)

Status: PLANNED. Depends on: M21 (re-expression proof uses catalog parts).
Design: `design_ideas/hull_shape_grammar.md` §4.

## Goal

`scripts/components/hull_builder.gd` — pure static functions that generate
component-dict arrays for the layout idioms every ship hand-expands today.
Authoring compresses from ~200 lines of raw dicts to ~30 lines of composition.

## Scope / deliverables

- `frame(rect: Rect2, thickness: float, hp: float) -> Array` — 4 wall segments.
- `taper(x0, x1, widths: Array) -> Array` — stepped bow/stern profile.
- `arm(dir: Vector2, offset, length, width, hp) -> Array` — arm + cap + flanks
  (the station idiom).
- `armor_box(inner: Rect2, thickness, hp) -> Array` — wrap a reactor.
- `zipper(x0, x1, cell_w, cells: Array) -> Array` — alternating hull/weapon
  flank (destroyer idiom); `cells` mixes hull specs and pre-built weapon dicts.
- `mirror_y(comps: Array) -> Array` — port⇄stbd: rect `(x, −y−h, w, h)`,
  heading → wrapped(−heading), id suffix `_port`⇄`_stbd` (param for custom
  suffixes).
- `mirror_x(comps: Array) -> Array` — fwd⇄aft: rect `(−x−w, y, w, h)`,
  heading → wrapped(PI − heading), suffix `_fwd`⇄`_aft`.
- `rotate_90(comps: Array, n: int) -> Array` — radial stamp; rect corners
  rotated n·90°, headings advance n·PI/2 wrapped.
- All functions return plain dicts; **runtime untouched** (`ship.gd`,
  validator, renderer unchanged). **No real ship file is converted this
  milestone** — the re-expression proof lives in the test only.

Reality note discovered in design: the existing stations are NOT rotationally
symmetric (small station: fwd/aft arms 40 long, port/stbd arms 100 long), so
their shells are a `mirror_x`/`mirror_y` composition, not `rotate_90`.
`rotate_90` is for future radially-symmetric designs (mine plus-shape, defence
pod ring) and gets synthetic unit tests only.

## Execution (Sonnet)

Hand the agent: this doc, grammar doc §4, `light_attack_craft.gd`,
`small_station.gd`, guardrails. Forbid: editing any ship file, editing the
validator. Angle comparisons in tests must wrap (−PI ≡ PI); provide/use a
`wrapf(a, -PI, PI)`-based `angles_equal` helper — naive float equality on
headings is the predictable failure mode here.

## Test plan (Fable) — `test_hull_builders.gd`

1. **frame():** exactly 4 walls; pairwise non-overlap (`intersects(_, false)`
   all false); mutually connected (each touches ≥1 other); outer envelope
   equals the requested rect; cavity probe points (center, corners inset by
   thickness+ε) covered by no wall.
2. **mirror_y():** exact rect math on a known input; heading cases 0→0,
   PI/2→−PI/2, PI→PI (wrapped), PI/4→−PI/4; id suffix swap both directions;
   **involution**: `mirror_y(mirror_y(c))` reproduces rects exactly and
   headings within wrap-epsilon. Same battery for **mirror_x()** with its
   formula and PI−heading rule.
3. **rotate_90():** known rect at n=1 lands at hand-computed coords; n=4 is
   identity (rects exact, headings wrap-equal); directional heading advances
   n·PI/2; a TAU-arc omni sensor's heading change is harmless (assert arc_width
   preserved).
4. **armor_box():** four segments enclose the inner rect on all sides (probe
   rays outward from inner-rect face centers cross a segment), none overlap
   the inner rect.
5. **zipper():** alternation matches the cells spec; expected count; no
   overlaps; chain connectivity end to end.
6. **Re-expression proof (the gate).** Rebuild the LightAttackCraft component
   set in-test from builders + M21 parts. Compare against a real
   `LightAttackCraft.new()` BEFORE `_ready()` normalization mutates anything
   (compare the `_init`-time array): (a) component count equal; (b) multiset
   of `(type, rect)` pairs exactly equal; (c) `ShipDesignValidator.validate`
   verdicts equal (ok flag AND violation multiset); (d) derived mass within
   1e-4; (e) component-union AABB identical. Any mismatch = the grammar can't
   express a real ship = milestone fails its premise.
7. **Station-shell proof.** Reproduce `small_station.gd`'s 4 hull caps + 8
   flanks from ONE authored arm's shell via `mirror_x`/`mirror_y` composition —
   multiset `(type, rect)` equality against the hand-authored values. Proves
   the mirror ops handle the real asymmetric-arm case (long port/stbd, short
   fwd/aft), not just synthetic fixtures.
8. **Determinism.** Two identical builder calls yield identical arrays (no
   RNG, no shared mutable state).

Pass marker: `>>> [TEST PASSED] test_hull_builders <<<`.

## Validation phase checklist

- Run `test_hull_builders`, `test_parts_catalog`, `test_ship_designs` (all
  green; ship files untouched by diff inspection).
- Diff review: builders are pure (no autoload access, no Node dependencies) —
  they must be callable from `_init()` contexts and tests alike.
- Mark DONE + commit (`feat: M22 hull builder grammar ops`).
