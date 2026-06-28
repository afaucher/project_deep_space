# Missile Warhead & the Laser Special Case

How a missile deals damage today, why it bypasses the ship weapon system, and what it
would take to unify them. Companion to [`missile_tracking_tradeoffs.md`](missile_tracking_tradeoffs.md)
and the PD/overkill thread in [`contact_tracing_and_cleanup.md`](contact_tracing_and_cleanup.md).

---

## 1. The special case

Ship weapons are first-class components and go through a uniform pipeline:

- a `weapons`-type entry in `ship_components` (ammo, cooldown, range, damage, arc, health),
- `WeaponBehaviorRegistry` → `LaserBehavior` / `MissileBehavior`,
- `Ship.fire_weapon()` → `behavior.can_fire()` (gates on `is_component_powered` → **health > 0**)
  → `behavior.execute_fire()`,
- `LaserBehavior` even scales damage by the weapon's own `component_health_ratio`.

A **missile's warhead is none of this.** On the missile, `warhead` is a plain `hull`-type HP
box ([`missile.gd`](../scripts/ships/missile.gd)). The actual damage is hardcoded in
[`missile_controller.detonate()`](../scripts/missile_controller.gd): a raycast that deals a
constant `WARHEAD_DAMAGE = 250` of `"laser"`-type damage. It is "a laser-head," special-cased
outside the weapon-component / behavior / health system entirely.

## 2. Consequences of the divergence

- **Warhead health gated nothing (now partially fixed).** Because `detonate()` never read the
  warhead component, shooting the warhead to 0 HP did **not** stop the missile — it still
  detonated for full damage. A ship laser, by contrast, stops firing the instant its hardpoint
  dies. *First step shipped:* `detonate()` now checks `warhead` health and duds the missile if
  it's destroyed (the missile still expends itself on the fuse but deals no damage). This makes
  the warhead a meaningful PD target — but it's a one-off `if`, not real unification.
- **No health-scaled falloff.** A laser does `damage × health_ratio`; a missile warhead is
  all-or-nothing (full 250 while alive, 0 when dead). No graceful degradation.
- **Not data-driven.** Warhead damage/range/type live as constants in the controller, not as
  tunable component fields, so missile lethality can't be authored per hull the way weapon
  hardpoints can.
- **Damage-type coupling.** "Missiles are laser-heads" hardcodes the `"laser"` damage type
  (which applies extreme heat). Any future warhead variety (kinetic, HE) has nowhere to live.

## 3. What full unification takes

Model the warhead as a real `weapons`-type component with a behavior:

1. **Schema:** give the missile a `weapons` component (`weapon_type: "warhead"`, with
   `damage`, `range`/fuse, `damage_type`, health) instead of a `hull` box named "warhead".
2. **Behavior:** add a `WarheadBehavior` (or reuse `LaserBehavior`'s damage application) under
   `WeaponBehaviorRegistry`, so detonation fires through `can_fire()`/`execute_fire()` — health
   gating and `damage × health_ratio` falloff come for free and stay consistent with ship guns.
3. **Fuse as the trigger:** `detonate()` becomes "the proximity fuse calls the warhead
   behavior once," rather than open-coding the raycast + damage. The one-shot, raycast nature
   (vs. a repeatable hardpoint) is the main impedance mismatch to design around.
4. **Result:** warhead lethality is data-driven, health-scaled, damage-type-flexible, and
   killing the warhead disables it through the *same* path that disables a ship laser — no
   special case.

**Why deferred:** it's a refactor touching the component schema, a new behavior, and the
fuse path, for a missile that fires its weapon exactly once. The shipped warhead-health gate
captures ~80% of the gameplay value (warhead is now a real PD target) at ~1% of the cost; full
unification is a tidiness/extensibility play, worth doing when warhead variety or per-hull
missile authoring is actually wanted.

---

## 4. Related: missile survivability levers (PD rebalance)

Overkill made PD lethal enough that a single frigate hard-counters anything below a ~6-missile
salvo (see the saturation sweep). Levers to give missiles a chance, independent of the special
case above:

1. **Decrease PD accuracy** — slow / coarsen the close-in fire-control sensor
   (`omni_short_hi_res` `refresh_interval` ↑, `num_bins` ↓). Pure PD nerf, no effect on
   ship-vs-ship. *Being swept now (`run_pd_sensor_sweep`).*
2. **Shift ship lasers toward dedicated low-power PD mounts** — fewer/short-range PD points
   instead of every main laser doubling as PD, so the PD envelope is smaller and weaker.
3. **Missile evasiveness (jink)** — every 1/N s, offset the steering aim by ±~10° of the
   true target bearing, so the track the PD solution is built on keeps shifting. Trades a
   little terminal accuracy for a much harder firing solution.

These stack with raising missile reactor HP (so one laser can't one-shot to the core).
