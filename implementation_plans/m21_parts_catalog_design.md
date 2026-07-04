# M21 — Parts catalog

Status: DONE (2026-07-04). Depends on: nothing. Design: `design_ideas/hull_shape_grammar.md` §3.

Shipped: `scripts/components/parts_catalog.gd` (PARTS table, 8 families ×
tiers × 3 marks; sensor sub-kinds via `opts.sensor_kind`; hull density grades
15/20/35 with `opts.size` + per-tier `HULL_REFERENCE_AREA` calibration),
`ShipDesignValidator.check_component_bands()` extraction (behavior-identical —
`test_ship_designs` output unchanged), `scripts/tests/test_parts_catalog.gd`
(all 8 items green; re-verified in validation phase). Accepted deviations:
(1) sensor primary stat is `sensor_quality_score()` (bins/refresh) since the
spec bands only cover sensor health; (2) scratch-key policing scoped to weapon
`cooldown` + sensor `timer` — `powered_on` stays authored, matching fleet
convention (frigate/LAC author it; the plan over-specified); (3) the
integration smoke asserts heat/sensor-timer progression as the proxy for "no
silent frame-abort" per CLAUDE.md's Dictionary-access trap.

## Goal

A `scripts/components/parts_catalog.gd` of named component variants ("marks")
per spec class per tier, where better stats cost a bigger footprint. Ships stop
hand-tuning stats; per-ship stat auditing collapses into one catalog test.

## Scope / deliverables

- `scripts/components/parts_catalog.gd` — static factories returning plain
  component dicts:
  `Parts.make(family: String, tier: int, mark: int, pos: Vector2, opts: Dictionary = {}) -> Dictionary`
  with `enum Mark { COMPACT, STANDARD, HEAVY }`. `opts` carries `id`, `heading`,
  and field overrides. Families v1: `laser`, `missile`, `engine`, `rcs`,
  `reactor`, `sensor` (sub-kinds: `omni_search`, `omni_pd`, `dir_search`,
  `passive_em`, `collision`), `comms`, `hull` (marks are **density** grades:
  civilian d=15 / standard d=20 / armored d=35, plus a size param since hull
  rects are layout-driven).
- Marks are data rows (one `PARTS` dict), not code per part. Every stat sits
  inside the `component_spec.gd` band for its tier; footprint grows with mark.
- Refactor: extract the validator's band-check loop into a reusable static
  `ShipDesignValidator.check_component_bands(comp, tier) -> Array` so the
  catalog test and the validator share one implementation (no drift).
- **No ship files change in this milestone.**

## Execution (Sonnet)

Hand the agent: this doc, `hull_shape_grammar.md` §3, `component_spec.gd`,
`ship_design_validator.gd`, one exemplar ship (`light_attack_craft.gd`), plus
the standing guardrails. Explicitly forbid: touching any `scripts/ships/*.gd`,
changing any band values in `component_spec.gd`.

Sizing guidance: STANDARD marks should reproduce the footprints and stats the
fleet already uses (LAC's 5×5 laser @ 250 dmg IS `laser/LIGHT/STANDARD`), so
existing designs are expressible in the catalog unchanged. COMPACT/HEAVY sit
near band floor/ceiling with smaller/larger rects.

## Test plan (Fable) — `test_parts_catalog.gd`

1. **Enumeration completeness.** `Parts.families()` returns the v1 family list;
   every family × its supported tiers × all three marks constructs without
   error. A family/tier hole (e.g. no STRUCTURE engine — correct, structures
   have no engines) must be an *explicit* absence the test asserts, not a crash.
2. **Band conformance (the core gate).** Every constructed part passes
   `check_component_bands(part, tier)` with zero violations. This must go
   through the *shared* validator helper — if the agent writes a private band
   check in the test instead, reject in validation phase.
3. **Schema completeness.** Every part carries `REQUIRED_KEYS` plus its
   type-specific fields (weapons: `weapon_type/cooldown_max/range/heading/
   arc_width` + `damage` or `ammo`; sensors: `sensor_type/range/arc_width/
   num_bins/refresh_interval/heading`; engines: `thrust_rating/torque_rating/
   power_rating`; reactor: `power_rating`; comms: `range`). Parts must NOT
   hand-set runtime scratch (`cooldown`, `timer`, `powered_on`) — that is
   `Ship._ready()` normalization's job; assert scratch keys absent.
4. **Monotonic-marks invariant (the grounded-tradeoff gate).** Within each
   family × tier, COMPACT ≤ STANDARD ≤ HEAVY in BOTH primary stat (laser:
   damage; engine: thrust_rating; reactor: power_rating; sensor: num_bins/
   refresh quality; comms/missile: range) AND rect area — with the primary stat
   strictly increasing. A part that gets better without getting bigger breaks
   the physical grounding and must fail here.
5. **Placement & identity.** `rect.position == pos`; `opts.heading` lands in
   the dict; `opts.id` respected; two calls without `id` yield distinct ids.
6. **Negative control (test the test).** A test-local malformed part (damage
   10× over band) run through the same helper MUST yield a violation. Guards
   against a vacuous band check.
7. **Integration smoke.** Assemble a minimal ship in-test (raw hull frame +
   catalog reactor/engine/sensor/laser), run the full `ShipDesignValidator` →
   `ok == true`, and instantiate it on a Ship-derived node headlessly to prove
   `_ready()` normalization accepts catalog parts (no script errors for 60
   physics frames).
8. **STANDARD-reproduces-fleet spot check.** `laser/LIGHT/STANDARD` equals
   LAC's authored laser on damage/range/cooldown_max and rect size;
   `engine/MEDIUM/STANDARD` matches the frigate's engine thrust/torque. Locks
   the catalog to reality instead of a parallel universe of numbers.

Pass marker: `>>> [TEST PASSED] test_parts_catalog <<<`.

## Validation phase checklist

- Run `test_parts_catalog`, then `test_ship_designs` (must be untouched-green —
  no ship files changed).
- Diff review: band values in `component_spec.gd` unchanged; validator refactor
  is extraction-only (same violations before/after — `test_ship_designs`
  green proves it).
- Mark DONE + commit (`feat: M21 parts catalog with spec-by-volume marks`).
