# M9 — Ship Catalog & Component Tiers (`ship_designs.md`)

Source doc: `design_ideas/ship_designs.md`.

**Scope decision (confirmed):** *foundation-first*. Build the spec/validation
machinery and prove it end-to-end against 3-4 representative ships before
authoring all ~12 designs. Loadouts live in **GDScript subclasses** (each ship
class sets its own `ship_components` in `_init()`), not external data files —
lowest friction, type-safe, same pattern the codebase already uses.

The full 12-ship catalog, the sandbox ship-switcher, and docking mechanics are
**out of scope for M9** and tracked as M10+ at the bottom of this doc.

---

## Where we're starting from (what M1 already gave us)

M1 ("ship is the parts") did the hard part. Components are already data-driven
dicts on `ship_components` ([ship.gd:118](../scripts/ships/ship.gd:118)), and
every ship-wide aggregate is *summed/derived from components*, not hardcoded:

- `get_ship_mass()` / `get_ship_inertia()` — derived from each component's
  `rect` area × `density` × scale ([ship.gd:321](../scripts/ships/ship.gd:321)).
- `get_ship_max_thrust()` / `get_ship_max_torque()` — summed from per-engine
  `thrust_rating` / `torque_rating` fields.
- `get_total_power_rating()` — summed from per-reactor `power_rating`.
- Weapons/sensors are generic behavior-dispatched, no per-class special-casing.

So a *new ship class is already just a different `ship_components` array.* The
machinery to turn that array into mass, handling, power, heat, and signature
already exists and is tested.

### The three real gaps

1. **Loadout lives on the base `Ship` class, not per-ship.** The frigate
   loadout is the `ship_components` literal on `Ship`, and
   [frigate.gd](../scripts/ships/frigate.gd) is a no-op subclass that inherits
   it. Every new ship would inherit the *frigate's* full weapon suite unless we
   first move the loadout down into `Frigate` and leave `Ship` loadout-empty.

2. **No spec/tier system.** Every component value (`damage: 500`, `range: 4000`,
   `power_rating: 100`) is a hand-tuned literal with no notion of tier and
   nothing to validate against. This is greenfield.

3. **Handling is half-derived, half-flat.** Turn/accel come from
   `thrust_rating`/`torque_rating` ÷ derived mass/inertia, but `max_omega` /
   `max_speed` are still flat vars ([ship.gd:108](../scripts/ships/ship.gd:108))
   with no size-consistent scaling. There is no "handling band per ship class."

### Findings that affect the plan

- **The TTK sim runner is stale and broken.** `run_time_to_kill.gd` is
  hardcoded Frigate-vs-Frigate and still calls `shooter.weapons.has(w_id)`
  ([run_time_to_kill.gd:114](../tactical_analysis/sim_runners/run_time_to_kill.gd:114))
  — an API M1/M7 deleted when `weapons` was merged into `ship_components`. It is
  the natural home for the "bigger ships win" validation but must be repaired
  and generalized to asymmetric matchups first.
- **Sweeps are serial.** `run_analysis_suite.ps1` launches one headless Godot
  process that runs the *entire* config grid inside one `_physics_process`
  loop. At >30 min for the current grid, adding ship-vs-ship matchups (an N×N
  explosion) makes it unusable. Parallelization is a hard prerequisite for
  thread #2, not a nice-to-have.

### Tactical pipeline contract (the report surface M9 must not break)

The canonical entry point and report flow are documented in the
`tactical-analysis` skill at `.agent/skills/tactical_analysis/SKILL.md` (odd
location, but it's authoritative). The pipeline is fixed-shape:

- `run_analysis_suite.ps1` runs each sim runner (headless Godot) → each writes a
  **canonical CSV** at a hardcoded path (`tactical_analysis/data/<sim>_results.csv`).
- `aggregate_and_chart.py` reads those *exact* canonical paths
  ([aggregate_and_chart.py:96](../tactical_analysis/scripts/aggregate_and_chart.py:96)),
  builds one markdown table per sim, and injects them into
  `templates/tactical_report_template.md`'s `{{..._TABLE}}` placeholders →
  writes `reports/latest_report.md` (the user-facing output).
- The template already anticipates growth: *"Additional sections will be
  appended here as new simulation runners are added."* So a ship-matchup section
  is the intended extension path.

Two consequences for M9:
- **M9e (parallelization):** the merge step must reassemble shards back into the
  canonical CSV filename the aggregator already expects — *don't* teach the
  aggregator about shards, just concat shards → `<sim>_results.csv` before the
  Python step. Zero aggregator change for parallelization itself.
- **M9f (asymmetric TTK):** `aggregate_ttk()` is hardwired to symmetric
  `ShipA`/`ShipB` win-rate grouped by `(range, axis)`
  ([aggregate_and_chart.py:58](../tactical_analysis/scripts/aggregate_and_chart.py:58)).
  Asymmetric matchups need a **class-identity dimension** threaded through all
  three layers: CSV schema (add `class_a`/`class_b`) → aggregator (group by
  matchup, report higher-tier win-rate) → template (new/expanded section).

---

## M9a — Move the loadout off `Ship`, into `Frigate`

**Why first:** nothing else can exist until "a ship class owns its own
loadout." This is a pure refactor with zero behavior change — the frigate must
play identically before and after.

**Scope:**
1. Cut the `ship_components` literal out of `Ship`, leave `Ship.ship_components`
   as `[]` (the generic base).
2. Add a `Frigate._init()` that sets `ship_components` to the (verbatim) frigate
   loadout, then calls `super()` so the existing `duplicate(true)` deep-copy
   still runs. Verify ordering: subclass `_init` must populate before `Ship._init`
   duplicates, or duplicate the array in `Frigate._init` itself.
3. Same treatment for any other class that silently leaned on the base loadout.

**Status: DONE.** Audit result: `sensor_drone.gd` and `missile.gd` already set
their own `ship_components` in `_init()` (no regression). `target_drone.gd` did
**not** — it was an empty subclass silently inheriting the base (frigate)
loadout, so emptying the base would have left it a componentless husk.

That surfaced a design smell worth keeping as a rule: **`TargetDrone` conflated
a ship hull with an AI role.** The role was already a separate node
(`AIDroneController`, attached as a child in `main.gd._spawn_drone()`), so the
class added nothing but a role-flavored name on a Frigate hull. Resolution:
deleted `target_drone.gd`; `_spawn_drone()` now builds a `Frigate` hull +
`AIDroneController` role, and `test_e2e_drone_vs_bouy.gd` preloads `frigate.gd`.
**Principle for the catalog: ship classes are hulls/loadouts only — never name a
ship class after a role/faction/AI.** Role is a controller node, faction is
`iff_tags`, both attached at spawn.

**Touches:** `scripts/ships/ship.gd`, `scripts/ships/frigate.gd`,
`scripts/ships/target_drone.gd` (deleted), `scripts/main.gd`,
`scripts/tests/test_e2e_drone_vs_bouy.gd`.

**Done when:** `test_component_states.gd`, `test_damage_propagation.gd`, and the
PD/TTK behavior are byte-identical to pre-refactor (the frigate's derived mass,
thrust, torque, heat, and signature are unchanged). ✅ All 11 tests pass; clean
export.

---

## M9b — Component spec chart + tier constants + validator

**Full design (tier ladder, exact spec-chart numbers, validator rules, test
spec) in [m9b_spec_chart_design.md](m9b_spec_chart_design.md).** In progress.

**Why:** this is the doc's central ask (#3, #4) — "baseline sizes at each tier
and levels of spec progression between tiers… validate designs against the
spec chart for consistency."

**Scope:**
1. **Define a tier ladder.** A small enum/const set, e.g. by hull size class:
   `T0_DRONE`, `T1_LIGHT`, `T2_MEDIUM`, `T3_HEAVY`, `T4_STRUCTURE`. (See proposed
   mapping below — tunable.)
2. **Author a `ComponentSpec` chart** (`scripts/components/component_spec.gd`, a
   const dictionary): for each `(type, tier)` pair, the *baseline* rect size,
   health, density, power draw, and type-specific stats (laser: damage/range/
   cooldown band; missile: damage/range; reactor: power_rating; engine:
   thrust/torque), plus an allowed ± tolerance band. Progression between tiers
   is expressed as multipliers so the chart stays terse.
3. **Write a validator** (`ship_design_validator.gd`): given a ship's
   `ship_components` + declared class tier, assert every component's stats fall
   within its `(type, tier)` band, and the ship's *derived* handling (accel =
   thrust/mass, ω = torque/inertia, top speed) falls within the class's handling
   band. Returns a structured pass/fail list, not just a bool.
4. **Wire the validator into the test suite** as a new `test_ship_designs.gd`
   that validates every authored ship class. Authoring a ship that violates the
   chart fails the build — this is the consistency guarantee the doc wants.

**Touches (new):** `scripts/components/component_spec.gd`,
`scripts/components/ship_design_validator.gd`,
`scripts/tests/test_ship_designs.gd`.

**Done when:** the frigate validates clean against its declared tier (T2), and a
deliberately-malformed test fixture fails with a readable per-component reason.

### Proposed tier mapping (starting point — tune in M9c)

| Tier | Class examples | Mobility | Armor | Weapon tier |
|------|----------------|----------|-------|-------------|
| T0 Drone | mine, sensor buoy, missile | slow / immobile | none | single PD-class or none |
| T1 Light | cargo shuttle, pinnace, light attack craft | fast | none/light | 1× light laser + light missile |
| T2 Medium | frigate, freighter, system defence pod | moderate | light | ship laser + PD + missile broadside |
| T3 Heavy | destroyer | moderate (high mass) | moderate + reactor armor | full suite, capital missiles |
| T4 Structure | station, asteroid station | immobile | extreme | heavy PD + missile, no engines |

### Proposed component progression (starting point)

Weapons scale *opposite* on rate vs damage as tier climbs (the doc's "PD =
small/fast/low-damage, capital missile = big/long/high-damage"):

- **PD laser** (T0-T2): small rect, short range (~2-4k), fast cooldown (~0.5-1s),
  low damage. Scales mostly in *count*, not per-shot power.
- **Ship laser** (T2-T3): bigger rect, mid range (~4-6k), slower cooldown,
  high damage.
- **Capital missile** (T3-T4): large rect, long range (~28k+), high damage,
  low ammo.
- **Reactor**: `power_rating` scales with total component power draw of the hull
  it sits in (validator can derive "is the reactor big enough to power this
  ship" as a check).
- **Engine**: `thrust_rating` scales with hull mass to keep *acceleration bands*
  consistent per tier (a T1 light craft and a T3 heavy can have wildly different
  thrust but should sit in their tier's accel band). `torque_rating` likewise vs
  inertia for turn-rate bands.

---

## M9c — Author 3-4 representative ships against the chart

**Why:** prove the chart spans the real range before committing to all 12. Pick
the corners of the design space:

- **Cargo shuttle** (T1) — unarmed, slow, cargo. Tests "valid ship with no
  weapons" and the small end of the handling band.
- **Light attack craft** (T1) — single short laser + light missile, fast, no
  armor. Tests the "small ship that can fight but can't take hits" archetype.
- **Frigate** (T2) — already exists; becomes the reference mid-tier.
- **Destroyer** (T3) — the heavy end; tests reactor armor, capital missiles, and
  the large mass/inertia handling band.

Each is a `scripts/ships/<name>.gd` subclass setting its `ship_components` +
declared tier, validated by `test_ship_designs.gd`.

**Done when:** all four validate clean, and their derived handling stats
(printed by a small debug dump) visibly separate by tier — shuttle nimble-but-
weak, destroyer sluggish-but-armored.

---

## M9d — Handling taxonomy: size-consistent scaling

**Why:** doc thread #1 (turn/accel/top speed) + the "smaller ships avoid combat"
requirement. Today `max_speed`/`max_omega` are flat and unrelated to the derived
thrust/mass.

**Scope:**
1. Decide whether `max_speed` is authored-per-class or derived (e.g. a
   thrust-vs-drag terminal velocity). Recommend: keep `max_speed` as a per-class
   field but *validate* it against the tier band, and keep `max_omega` derived
   from torque/inertia so it can't drift from the physical layout.
2. Add the handling band to the spec chart so the validator enforces "T1 ships
   are faster/nimbler than T3."

**Touches:** `scripts/ships/ship.gd` (handling vars → per-class + validated),
`component_spec.gd`.

---

## M9e — Parallelize the tactical sweep

**Why:** the doc's embedded NOTE — sweeps already take >30 min and the N×N
matchup grid for "bigger ships win" makes serial runs impossible.

**Scope:**
1. Add a shard argument to the sim runners: a sim runs only configs
   `[shard_idx, shard_idx+N, ...]` of the grid, writing to a per-shard CSV
   (`..._results.shard_<k>.csv`).
2. Update `run_analysis_suite.ps1` to launch K headless Godot processes
   concurrently (`Start-Process` without `-Wait`, collect handles, join), then
   merge the shard CSVs **back into the canonical `<sim>_results.csv` filename**
   the aggregator already reads, before the Python step.
3. Keep determinism: each shard owns a disjoint config slice; the merge is a
   plain concat (header once). No shared state between processes.

**Touches:** `run_missile_vs_pd.gd`, `run_time_to_kill.gd`,
`run_analysis_suite.ps1`. **Not** `aggregate_and_chart.py` — the canonical-CSV
merge keeps its input contract unchanged.

**Done when:** the existing PD grid produces an identical aggregate report at a
wall-clock roughly divided by K.

---

## M9f — Asymmetric tactical validation ("bigger ships win")

**Why:** doc thread #2. Depends on M9c (ships to fight) and M9e (so the matchup
grid is runnable).

**Scope:**
1. **Repair `run_time_to_kill.gd`** — replace the dead `shooter.weapons.*` API
   with the M1 component/behavior path; make ship classes a config parameter
   instead of hardcoded `Frigate`.
2. Add a matchup grid: each `(class_a, class_b, range, axis)` cell, recording
   winner, TTK, survivor health. **Extend the CSV schema** with `class_a`/
   `class_b` (today's TTK CSV has no class identity — it assumes both are
   frigates).
3. **Update `aggregate_ttk()`** to group by matchup and report higher-tier
   win-rate instead of the symmetric `ShipA`/`ShipB` columns; add the matchup
   section to the report template (its appended-sections note invites exactly
   this).
4. Assert the design invariants as report checks (not hard test failures, since
   they're tuning targets): higher-tier consistently wins same-range engagements;
   lower-tier ships can break contact (reach `max_speed` away faster than the
   heavy can close); lower-tier weapons struggle to deplete higher-tier armor.

**Touches:** `run_time_to_kill.gd`, `aggregate_and_chart.py`,
`tactical_report_template.md`.

**Done when:** the report shows destroyer > frigate > light-attack-craft in
win-rate at matched range, and light craft escaping a destroyer's engagement
envelope.

---

## Sequencing

```
M9a Loadout extraction (pure refactor, no behavior change)
   |--> M9b Spec chart + validator + test
            |--> M9c Author 3-4 ships
                     |--> M9d Handling scaling (validated)
                     |--> M9f Asymmetric TTK validation
M9e Sweep parallelization  [independent — can land any time, unblocks M9f's grid]
```

M9a and M9e have no interdependency and are both cheap/high-value — either can
go first. M9b is the keystone everything downstream validates against.

**M10 (sandbox spawn UI) is pulled forward** to land alongside / just before
M9c — it's the test instrument that makes each authored ship immediately
playable. See [m10_sandbox_spawn_design.md](m10_sandbox_spawn_design.md).

---

## Deferred to M10+ (explicitly out of M9 scope)

- **Full 12-ship catalog** — freighter, pinnace, sensor buoy*, mine, system
  defence pod, station, asteroid station. (* buoy exists as a separate
  `RigidBody2D`, not a `Ship` subclass — folding it into the component model is
  its own question.)
- **~~Sandbox / ship-switcher~~ → promoted to M10** (friendly/enemy/pirate
  subset). Neutral/beacon stays deferred — it needs M7 (IFF beacons). See
  [m10_sandbox_spawn_design.md](m10_sandbox_spawn_design.md).
- **Docking mechanics** — station docking (doc #5); no existing system, a real
  new mechanic, lowest priority.
- **Cargo as a system** — shuttles/freighters imply cargo capacity as a real
  attribute; currently nonexistent. Decide if it's cosmetic or mechanical when
  the catalog needs it.

---

## Open questions to resolve during M9b

1. **Is `max_speed` authored or derived?** (M9d) — recommend authored-but-
   validated.
2. **Do immobile classes (station, T4) share the `Ship` base** with zero engines
   and a validator exemption, or get their own base? Recommend: same base, the
   validator just allows `engines: 0` for T4.
3. **Reactor-sufficiency check** — should the validator hard-fail a ship whose
   total power draw exceeds reactor `power_rating`, or warn? Recommend hard-fail
   — it's exactly the kind of consistency bug the chart exists to catch.
