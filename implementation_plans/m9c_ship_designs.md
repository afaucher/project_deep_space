# M9c — Author the first catalog ships (design spec)

Parent: [m9_ship_catalog_design.md](m9_ship_catalog_design.md). Targets and
rationale come from [../design_ideas/ship_parameter_table.md](../design_ideas/ship_parameter_table.md).

Author three new ships against the table's draft targets, let M9f's matchup sim
drive retuning later. Frigate (T2) already exists as the reference anchor.

## Enabling change FIRST — bands become non-blocking

"Don't band everything today." Split `ShipDesignValidator` violations by
severity so band deviations don't fail the build:

- Add `"severity"` to each violation: `"error"` or `"warning"`.
- **Structural rules (§3a: schema, unique ids, health sanity, has hull/reactor/
  engine/sensor, STRUCTURE-no-engines)** → `"error"`.
- **Banded stat checks (§3b) and handling checks (§3c)** → `"warning"`.
- `validate()` returns `ok = (count of error-severity violations == 0)`.
- `test_ship_designs.gd`: fail the build only on error-severity violations;
  **print** warnings (so sub-floor thrust on a tiny ship is visible, not fatal).
  The existing malformed-fixture case must still fail — keep at least one
  structural break in it (missing reactor, dup id) so `ok == false` still holds;
  its band breaks (laser damage, max_omega) become warnings, which is fine.

This unblocks small/large ships that legitimately sit outside the provisional
T1/T3 bands without us having to perfect the bands now.

## Mass shortcut (for hitting targets)

All ship components are density 20, `MASS_SCALE = 100/55500`, so
**mass ≈ total_rect_area × 0.036** → for target mass M, total area ≈ M × 27.75.
**accel = thrust ÷ mass**; size rects to land mass within ~±15% of target, then
set `thrust_rating = round(target_accel × achieved_mass)`. Report achieved
mass/accel per ship so we can check against the table.

Follow the frigate loadout (`frigate.gd`) as the structural template: same
component dict schema (`id, type, rect, health, max_health, density, ...`),
forward = +X, set `ship_tier` in `_init()` before `super()`, and reference
`ComponentSpec` via the inherited const (don't add a bare global reference).

---

## Ship 1 — Cargo Shuttle (`scripts/ships/cargo_shuttle.gd`, tier LIGHT)

Slow civilian hauler, unarmed, fragile, big cargo volume.

- **Targets:** mass ~40, accel ~25 → thrust ~1000, torque ~2600, max_speed 700,
  max_omega 1.8, cross_section 40, max_heat 150.
- **Hull:** a large light cargo bay + a small nose. Total hull health ~260
  (fragile for its size). Suggest `hull_bay` (big rect, health ~180) +
  `hull_fwd` (health ~80).
- **Reactor:** one, `power_rating 50`, health ~80.
- **Engine:** one, `thrust_rating ~1000`, `torque_rating ~2600`,
  `power_rating 40`, health ~70 (small engine → slow).
- **Sensors:** one basic omni — `sensor_type active`, range 22000, `arc_width TAU`,
  `num_bins 36`, `refresh_interval 1.5`, `base_em_emission 8`, health ~30.
- **Comms:** range 22000, health ~30.
- **Weapons:** none (unarmed — validator allows it).

## Ship 2 — Light Attack Craft (`scripts/ships/light_attack_craft.gd`, tier LIGHT)

Cheap, fast, darty, paper armor, single short laser + light missile. Engine is
*oversized for its mass* — that's what makes it fast.

- **Targets:** mass ~14, accel ~110 → thrust ~1500, torque ~3500, max_speed 2200,
  max_omega 4.5, cross_section 22, max_heat 130.
- **Hull:** small, low health ~90 total ("effectively no armor"). 1–2 small hull
  components.
- **Reactor:** one, `power_rating 55`, health ~50.
- **Engine:** one, `thrust_rating ~1500`, `torque_rating ~3500`,
  `power_rating 50`, health ~50 — physically a big share of the hull.
- **Weapons:** `hp_fwd_laser` (laser, `damage 250`, `range 3000`,
  `cooldown_max 0.8`, health ~55) + `hp_fwd_missile` (missile, `range 12000`,
  `ammo 4`, `cooldown_max 6.0`, health ~55).
- **Sensors:** one forward fire-control — active, range 25000, `arc_width PI/1.5`,
  `num_bins 60`, `base_em_emission 8`, health ~25.
- **Comms:** range 20000, health ~25.

## Ship 3 — Destroyer (`scripts/ships/destroyer.gd`, tier HEAVY)

Big true warship: heavy armor + reactor armor, full broadside suite, rear PD,
sluggish. Must out-armor and out-gun the frigate while being slower.

- **Targets:** mass ~210, accel ~28 → thrust ~5900, torque ~16000, max_speed 700,
  max_omega 1.0, cross_section 75, max_heat 400.
- **Hull:** large, total hull health **~7600** (clearly > frigate's 4000), incl.
  a dedicated armored core wrapping the reactors ("reactor armor"). Spread across
  fwd / port / stbd / aft / core components.
- **Reactors:** two (redundant), `power_rating 300` + `250` = 550 total, health
  ~300 each.
- **Engine:** one large, `thrust_rating ~5900`, `torque_rating ~16000`,
  `power_rating 100`, health ~500.
- **Weapons (full suite):**
  - `hp_fwd_laser` — laser, damage 600, range 5000, cooldown_max 1.0
  - `hp_port_laser_1/2`, `hp_stbd_laser_1/2` — laser, damage 500, range 4000,
    cooldown_max 1.0 (the 2×2 broadside)
  - `hp_aft_pd` — rear PD laser, damage 300, range 3000, cooldown_max 0.5 (fast,
    fills the frigate's aft blind spot)
  - 10 missile tubes: 2×4 broadside (`hp_port_tube_1..4`, `hp_stbd_tube_1..4`) +
    `hp_fwd_tube_1/2`, all missile, range 30000, ammo 5, cooldown_max 5.0
  - Weapon `heading`/`arc_width` set per mount like the frigate (fwd 0±PI/3,
    port −PI/2±PI/2, stbd +PI/2±PI/2; aft PD heading PI, arc ~PI/2).
- **Sensors:** a frigate-class suite (5–6): dir_high_res, omni search, an
  `omni_short_hi_res` close-in fire-control for its own PD (TAU, high num_bins,
  refresh 0.0 — reuse the frigate's tuned values), passive_em, omni_collision.
- **Comms:** range 60000, health ~80.

---

## Catalog + validation wiring

1. **Register all three** in `ShipCatalog.SPAWNABLE` (`scripts/ship_catalog.gd`)
   with display names, via `preload(...)`. They then auto-appear in the M10 F2
   spawn dropdown.
2. **Activate the M9b forward-link:** `test_ship_designs.gd` iterates
   `ShipCatalog.SPAWNABLE`, instantiates each, and runs
   `ShipDesignValidator.validate()`. Assert **no error-severity violations** for
   any (structural validity). Print any warnings. Keep the existing explicit
   Frigate-clean, malformed-fixture, and UNVALIDATED cases.
3. Each new ship sets its `ship_tier` (LIGHT/LIGHT/HEAVY) in `_init()`.

## Done when

`build.ps1` is green: all three ships instantiate, validate with zero structural
errors (warnings allowed/printed), appear in the spawn dropdown, and the
reported mass/accel for each lands near the table targets (shuttle sluggish,
attack craft darty, destroyer slow-but-tanky). Tune later via M9f; do not
hand-tune to perfection now.

## Report back (for orchestrator review)
Per ship: achieved mass, achieved accel (thrust/mass), total hull health,
weapon count, and any band warnings the validator printed. Flag anything that
lands far from the table target.
