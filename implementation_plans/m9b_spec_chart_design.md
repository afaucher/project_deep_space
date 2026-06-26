# M9b — Component Spec Chart + Tier Ladder + Validator (design)

Parent: [m9_ship_catalog_design.md](m9_ship_catalog_design.md) (milestone M9b).

This is the **design** deliverable. Implementation (writing the `.gd` files +
test) is mechanical and handed to a Sonnet subagent against this spec.

## Goal

A single source of truth that says, for each ship tier, what a "legal" component
looks like, plus a validator that fails the build when an authored ship violates
it. The frigate (the only real ship today) must validate **clean** as tier
MEDIUM — so the MEDIUM band is grounded in the frigate's actual numbers, not
invented. Bands for the other four tiers are **provisional first-cut** scaffolding
to be tuned in M9c when shuttle / light-attack-craft / destroyer are authored;
they live in one chart so tuning is a one-file edit.

## Scope boundary

The validator targets **catalog ship classes** (Frigate, and the M9c ships).
It does **not** validate `missile.gd` (ordnance, not a catalog ship — it's fast
and weird on purpose) or `buoy.gd`/`sensor_drone.gd` for now. A ship opts in by
declaring a real `ship_tier`; classes left at `UNVALIDATED` are skipped.

---

## 1. Tier ladder

Add to `scripts/components/component_spec.gd`:

```gdscript
class_name ComponentSpec

enum Tier { UNVALIDATED = -1, DRONE = 0, LIGHT = 1, MEDIUM = 2, HEAVY = 3, STRUCTURE = 4 }
```

Ship-class assignments (this milestone only sets Frigate; the rest are M9c):

| Tier | Class today | M9c additions |
|------|-------------|---------------|
| DRONE | — | (mine, sensor buoy later) |
| LIGHT | — | cargo shuttle, light attack craft |
| MEDIUM | **Frigate** | (freighter, system defence pod later) |
| HEAVY | — | destroyer |
| STRUCTURE | — | (station later) |

### How a ship declares its tier

On `Ship` base (`ship.gd`), add:
```gdscript
var ship_tier: int = ComponentSpec.Tier.UNVALIDATED
```
In `Frigate._init()` (before or after the loadout, doesn't matter — just before
`super()` is fine), add:
```gdscript
ship_tier = ComponentSpec.Tier.MEDIUM
```

---

## 2. Validator API

New file `scripts/components/ship_design_validator.gd`:

```gdscript
class_name ShipDesignValidator

# Returns { "ok": bool, "tier": int, "violations": Array }
# Each violation: { "component_id": String, "field": String, "reason": String }
# A ship at Tier.UNVALIDATED returns ok=true with an empty violations list
# (explicitly opted out), NOT a failure.
static func validate(ship) -> Dictionary
```

`violations` is a list, not a bool, so the test can print every problem at once
(readable per-component reasons) rather than failing on the first.

---

## 3. Validation rules

Two groups. **Structural** rules need no balance numbers and catch real authoring
bugs — these are the backbone. **Banded** rules check stats against the chart.

### 3a. Structural (apply to every validated ship)

1. **Schema**: every component dict has the required keys `id, type, rect,
   health, max_health, density`. Missing key → violation.
2. **Unique ids**: no two components share an `id`.
3. **Health sanity**: `0 < health <= max_health` and `max_health > 0` and
   `density > 0`.
4. **Has a hull**: ≥1 component of type `hull`.
5. **Has a reactor**: ≥1 component of type `reactor` with `power_rating > 0`.
6. **Mobility** (tiers DRONE..HEAVY): ≥1 component of type `engines` with
   `thrust_rating > 0`. Tier STRUCTURE is **exempt** (immobile by design) —
   for STRUCTURE, having any `engines` component is itself a violation.
7. **Not blind**: ≥1 component of type `sensors`.
8. **Reactor sufficiency** (structural form, no draw model yet): if the ship has
   any powered component of a type that consumes power (anything not `hull` or
   `reactor`), it must have ≥1 reactor. (We don't yet sum a numeric draw vs
   output — that's a later refinement noted in §6. This catches the gross case:
   "powered systems, no reactor.")

### 3b. Banded stat checks (chart-driven, §4)

For each component, look up its **spec class** (§4.1), then its
`(spec_class, tier)` band, and assert each listed stat falls within
`[min, max]` inclusive. A component whose spec class has no entry for the ship's
tier is **skipped** (not a violation) — e.g. a STRUCTURE has no engine band.

Bands across adjacent tiers deliberately **overlap**: a stat near a tier
boundary is legal in both. The band is selected by the ship's declared tier, so
overlap never causes ambiguity.

### 3c. Handling (authored only, this milestone)

Check `ship.max_speed` and `ship.max_omega` against the per-tier handling band
(§4.3). Derived linear/angular acceleration banding is **deferred to M9d** (the
handling-taxonomy milestone) to avoid pinning mass-scale constants here.

---

## 4. The spec chart

All numbers live in `component_spec.gd` as nested const dictionaries. MEDIUM is
ground truth (frigate). **Bands for DRONE/LIGHT/HEAVY/STRUCTURE are provisional**
— marked so in the file, tuned in M9c.

### 4.1 Spec-class resolution

A component's spec class is derived from its dict:
- type `hull` → `"hull"`
- type `reactor` → `"reactor"`
- type `engines` → `"engine"`
- type `comms` → `"comms"`
- type `sensors` → `"sensor"` (not sub-classed by role this cut — see §6)
- type `weapons` + `weapon_type == "laser"` → `"laser"`
- type `weapons` + `weapon_type == "missile"` → `"missile"`

### 4.2 Component bands `[min, max]` per tier

Stats checked per class are listed under each. Frigate (MEDIUM) reality, for
reference: hull health 1000; reactor power_rating 100; engine thrust 5000 /
torque 10000; comms range 30000; sensor health 20–50; laser damage 500 / range
4000 / cooldown_max 1.0; missile range 28000 / cooldown_max 5.0.

**hull** — check `health`:
| Tier | health |
|------|--------|
| DRONE | [10, 300] |
| LIGHT | [80, 600] |
| MEDIUM | [400, 1500] |
| HEAVY | [1000, 5000] |
| STRUCTURE | [3000, 60000] |

**reactor** — check `power_rating`:
| Tier | power_rating |
|------|--------------|
| DRONE | [10, 80] |
| LIGHT | [40, 160] |
| MEDIUM | [80, 300] |
| HEAVY | [250, 900] |
| STRUCTURE | [500, 6000] |

**engine** — check `thrust_rating`, `torque_rating`:
| Tier | thrust_rating | torque_rating |
|------|---------------|---------------|
| DRONE | [300, 3000] | [600, 6000] |
| LIGHT | [2000, 7000] | [4000, 14000] |
| MEDIUM | [4000, 12000] | [8000, 24000] |
| HEAVY | [10000, 32000] | [20000, 64000] |
| STRUCTURE | (no entry — STRUCTURE has no engines; §3a rule 6) |

**comms** — check `range`:
| Tier | range |
|------|-------|
| DRONE | [0, 25000] |
| LIGHT | [10000, 45000] |
| MEDIUM | [20000, 60000] |
| HEAVY | [40000, 120000] |
| STRUCTURE | [40000, 250000] |

**sensor** — check `health` only this cut (range is too role-dependent to band —
frigate sensors span 1500–80000 across collision/search/passive roles; §6):
| Tier | health |
|------|--------|
| DRONE | [5, 60] |
| LIGHT | [10, 80] |
| MEDIUM | [15, 120] |
| HEAVY | [30, 250] |
| STRUCTURE | [30, 500] |

**laser** — check `damage`, `range`, `cooldown_max`:
| Tier | damage | range | cooldown_max |
|------|--------|-------|--------------|
| DRONE | [50, 300] | [1000, 4000] | [0.2, 3.0] |
| LIGHT | [100, 600] | [2000, 6000] | [0.2, 3.0] |
| MEDIUM | [300, 1200] | [3000, 8000] | [0.2, 3.0] |
| HEAVY | [800, 4000] | [4000, 12000] | [0.2, 3.0] |
| STRUCTURE | [300, 4000] | [2000, 8000] | [0.2, 3.0] |

**missile** — check `range`, `cooldown_max` (damage lives on the spawned missile
entity, not the tube — not banded here):
| Tier | range | cooldown_max |
|------|-------|--------------|
| DRONE | [5000, 20000] | [1.0, 10.0] |
| LIGHT | [10000, 30000] | [1.0, 10.0] |
| MEDIUM | [20000, 40000] | [1.0, 10.0] |
| HEAVY | [28000, 60000] | [1.0, 10.0] |
| STRUCTURE | [20000, 60000] | [1.0, 10.0] |

### 4.3 Handling bands

`max_speed`, `max_omega` per tier. Note the **inversion**: lighter tiers are
faster/nimbler. Frigate (MEDIUM) is max_speed 1000, max_omega 2.0.

| Tier | max_speed | max_omega |
|------|-----------|-----------|
| DRONE | [0, 200] | [0, 3.0] |
| LIGHT | [1000, 3000] | [2.0, 6.0] |
| MEDIUM | [600, 1400] | [1.2, 3.0] |
| HEAVY | [300, 900] | [0.6, 1.8] |
| STRUCTURE | [0, 0] | [0, 0] |

(DRONE here is the slow station-keeping/mine sense, not ordnance — missiles are
excluded from validation, §scope.)

---

## 5. Test: `scripts/tests/test_ship_designs.gd`

Mirror the structure of the other `test_*.gd` runners (setup → run cases →
print `>>> [TEST PASSED/FAILED] <<<` → `get_tree().quit(0/1)`). Cases:

1. **Frigate validates clean.** `var r = ShipDesignValidator.validate(Frigate.new())`
   → assert `r.ok == true` and `r.violations` empty. If it fails, print every
   violation (this is also how we confirm the MEDIUM bands match reality).
2. **Malformed fixture fails with reasons.** Build a throwaway ship (subclass or
   a Frigate with mutated `ship_components` + `ship_tier = MEDIUM`) that breaks
   several rules at once: e.g. remove all reactors (rule 5 + 8), set a laser
   `damage` to 5 (below MEDIUM [300,1200]), give it a max_omega of 0.1 (below
   MEDIUM band), and duplicate a component id. Assert `r.ok == false` and that
   `r.violations` contains a distinct entry naming each broken thing.
3. **UNVALIDATED opt-out.** A bare `Ship.new()`-style instance left at
   `ship_tier = UNVALIDATED` → `r.ok == true`, empty violations (skipped, not
   failed).

**No registration needed** — tests are auto-discovered. `build.ps1` globs
`scripts/tests/*.gd`, and `main.gd._run_test()` loads
`res://scripts/tests/<name>.gd` by path convention and calls `test_node.setup(self)`.
So the file just needs a `func setup(main: Node) -> void:` entry point, and it
must print `>>> [TEST PASSED] test_ship_designs <<<` (exact bracket text — the
runner greps for `[TEST PASSED]`) and call `get_tree().quit(0)` on success, or
print failures + `get_tree().quit(1)` on failure.

Validation is synchronous and pure (reads `ship_components` + `max_speed` /
`max_omega` / `ship_tier` off a fresh `Frigate.new()` — no physics, no tree-add
required), so `setup()` can do everything and quit immediately; no
`_physics_process` frame-waiting needed (unlike the physics-driven tests).
Build must stay green.

---

## 6. Explicitly deferred (do NOT build now)

- **Numeric reactor sufficiency** (sum powered components' draw vs reactor
  output). Needs a per-component `power_draw` field that doesn't exist yet.
  §3a rule 8 is the structural placeholder.
- **Sensor sub-classing** by role (fire-control / search / passive / collision)
  with per-role range bands. This cut bands sensor `health` only.
- **Derived-acceleration handling bands** (thrust/mass, torque/inertia) → M9d.
- **Cross-ship ordinal checks** ("HEAVY out-tanks LIGHT") → these are matchup
  properties, validated empirically in M9f, not per-ship here.
- **PD-laser vs ship-laser split** — one `laser` band for now; the frigate uses
  a single laser profile, so there's nothing to split against until M9c needs it.
