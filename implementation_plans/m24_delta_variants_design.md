# M24 — Delta variants (skins of validated hulls)

Status: PLANNED. Depends on: M21 (swaps pull catalog parts); M23 desirable
(variants inherit the mechanized checks). Design:
`design_ideas/hull_shape_grammar.md` §5, §7.

## Goal

Most wanted variety is skins, not hulls: pirate LAC, ore shuttle, militia
frigate. Make a variant a ~10-line diff on a validated base, with a testing
rule that keeps skins from re-litigating 30-minute tactical sweeps.

## Scope / deliverables

- `scripts/components/ship_variants.gd` — `Variants.apply(base: Array,
  ops: Array) -> Array` plus `Variants.classify(ops) -> STATS_ONLY|GEOMETRY`.
  Ops v1:
  - `{"swap": id, "part": [family, tier, mark]}` — replace with a catalog part
    at the SAME rect (position preserved, size must match exactly — a
    size-mismatched swap is a hard error from `apply`). STATS_ONLY.
  - `{"tune": id, "field": f, "value": v}` — single-field override. STATS_ONLY.
  - `{"remove": id}` — drop a component. GEOMETRY.
- **Base-ship refactor (mechanical):** each base ship exposes
  `static func design() -> Array` returning its authored component array;
  `_init()` becomes `ship_components = design(); super()`. Behavior-identical
  by construction — `test_ship_designs` is the guard. This exists so variants
  can compose a base's loadout WITHOUT inheriting its `_init` (GDScript parent
  `_init` ordering makes subclass-mutation fragile; variants extend `ship.gd`
  directly and `preload` the base for `design()`).
- Two real variants, registered in `ShipCatalog` under a `VARIANTS` list:
  - **Pirate LAC** — engine swapped to `engine/LIGHT/HEAVY` mark, one hull
    plate removed (GEOMETRY — exercises re-validation), laser tuned to faster
    cooldown. Faster, more fragile, meaner.
  - **Ore shuttle** — cargo-flavored shuttle skin: comms tuned down, hull
    density mark swapped (heavier plating), name/flavor.
- `test_ship_designs` extended to auto-enumerate `ShipCatalog.VARIANTS` —
  every future variant is validated by existing without new test code.
- **Promotion rule documented in ShipCatalog** (comment + `role_key` per
  entry): a variant enters tactical sweeps only if it changes tier, weapon-
  class mix, or leaves ±20% of the base's accel. Neither v1 variant promotes.

## Execution (Sonnet)

Hand the agent: this doc, grammar doc §5/§7, `ship_variants` op table above,
`light_attack_craft.gd`, `cargo_shuttle.gd`, `ship_catalog.gd`, guardrails.
Forbid: changing any base ship's components (the `design()` extraction must be
value-identical — copy, don't retype), touching the validator.

## Test plan (Fable) — `test_ship_variants.gd`

1. **Op mechanics.** On a fixture array: `swap` preserves the rect exactly
   (position AND size) while changing stats; `tune` changes only the named
   field (full dict-diff assert — nothing else moved); `remove` drops exactly
   one component. `apply` never mutates the input array (deep-copy contract).
2. **Size-mismatch swap rejected.** Swapping a 5×5 laser slot with a HEAVY
   5×8 part must raise/return an error, not silently resize. This is the
   geometry-safety contract that makes STATS_ONLY classification trustworthy.
3. **classify() correctness.** swap/tune → STATS_ONLY; any op list containing
   remove → GEOMETRY.
4. **GEOMETRY deltas are still caught by the validator.** Fixture: remove a
   bridging hull piece from a minimal ship → `ShipDesignValidator` reports the
   disconnect error. Proves variants get no validation bypass.
5. **design() extraction fidelity.** For each refactored base ship:
   `Base.design()` multiset-equals the pre-refactor authored array (the test
   pins a checksum/count + spot fields; full behavioral guard is
   `test_ship_designs` staying green).
6. **Pirate LAC gates.** Validator `ok == true`; expected layout warnings (the
   removed plate should surface as a coverage warning — enumerate it);
   `thrust_rating` strictly > base LAC's; mass ≤ base (plate removed); derived
   accel strictly > base — the variant must actually BE faster, not just
   labeled faster.
7. **Ore shuttle gates.** Validator ok; unarmed still; mass > base shuttle
   (heavier plating); dockable flag preserved.
8. **Spawn smoke.** Instantiate both variants headless, run 60 physics frames
   — zero script errors (proves `_ready()` normalization + AI attach paths
   accept variant-built ships).
9. **Auto-enumeration.** `ShipCatalog.VARIANTS` non-empty; `test_ship_designs`
   demonstrably iterates it (assert its ship count grew by the variant count).

Pass marker: `>>> [TEST PASSED] test_ship_variants <<<`.

## Validation phase checklist

- Run `test_ship_variants`, `test_ship_designs`, `test_parts_catalog`,
  `test_hull_builders`, `test_layout_checks`.
- Diff review: base ships' `design()` arrays byte-identical to the old
  literals; promotion-rule comment present in `ship_catalog.gd`.
- Optional campaign flavor (record if done): swap one Slag Bay cargo lane to
  the ore shuttle — `test_cargo_run` + `test_campaign_bootstrap` must stay
  green if touched.
- Mark DONE + commit (`feat: M24 delta variants (pirate LAC, ore shuttle)`).
