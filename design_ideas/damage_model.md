# Damage model — one raymarch, and the collision-vs-laser feel question

How damage lands on a ship, and one **parked decision** about how kinetic
collision damage (M28) distributes across components. Revisit later.

## One function for all damage

Every damage source — lasers, missile warheads, and M28 kinetic collisions —
calls the same `Ship.take_damage(amount, global_pos, global_dir, damage_type)`
(`scripts/ships/ship.gd`). There is no separate collision-damage or laser-damage
path. A ray enters at the hit point and marches inward in `DAMAGE_RAYMARCH_STEP`
(2.0 u) steps; at each step the component in that cell absorbs:

```
dmg_absorbed = min(remaining_damage, effective_density × STEP × ABSORPTION_PER_DENSITY)
effective_density = max(MIN_EFFECTIVE_DENSITY, density × health_ratio)
```

With the current constants (`ABSORPTION_PER_DENSITY = 50`, `STEP = 2.0`) a
**full-health** component of `density 20` soaks up to **20 × 2.0 × 50 = 2000
damage in a single step.**

Two rules produce "burn-through":
- **Ablation** — as a component loses health, `effective_density` (hence its
  per-step soak) shrinks toward the `MIN_EFFECTIVE_DENSITY` floor.
- **Skip-when-dead** — a component at `health <= 0` is skipped, so the ray
  advances to the next live component. That advance *is* the burn-through.

## Why lasers burn through but a ram (currently) doesn't

Same code; the difference is that a **laser fires repeatedly** while a **ram is
one event**, plus how each interacts with the per-step cap (which scales with
the *target* component's health: `cap = max(5, 2000 × health_ratio)`).

- **Laser** — `actual_damage = comp["damage"] × health_ratio`, fired each
  cooldown. A frigate laser is **500/shot** (catalog weapons run 250–3200). On
  **fresh, full-health armor** 500 < the 2000 cap, so the cap does **not** bind:
  the shot deposits fully into the first live component, and burn-through to the
  next layer happens **across shots via the skip-when-dead rule** — the cap is
  irrelevant to this common case. The cap starts to matter in two situations:
  (a) once the outer component is ablated below ~25% health, `2000 × ratio` drops
  under 500, so a single shot finishes the dying layer **and** punches the
  remainder into the component behind it in the same shot; and (b) heavy weapons
  above 2000/shot (e.g. the 3200 laser) penetrate multiple full-health layers in
  one shot. So the cap governs *single-shot penetration*, not the routine chip.
- **Collision (M28)** — one lump, one chance, no follow-up shot. A 400 u/s
  frigate head-on is ~1407, **below** the 2000 cap, so the cap doesn't bind here
  either: `min(1407, 2000) = 1407` deposits **in the first step** into the
  outermost component the ray touches (a frigate nose's `dir_high_res`, a 50-HP
  sensor: 50 − 1407 = −1357), then `remaining_damage` hits 0. Because there's no
  next shot to skip the now-dead sensor, it **stops there** — ~1357 of the 1407
  is wasted, and the ship's clamped total drops by only that 50 HP.

So the ram's weakness isn't the cap (1407 < 2000) — it's the lack of repetition.
A collision lump *bigger* than the cap (> 2000 into a full-health face) *would*
burn through in one call, exactly like the 3200 laser (2000 in step 1, kill the
outer component, march the remainder inward). M28's tuned `COLLISION_DAMAGE_K`
just never produces a lump that large against a full-health face.

## Decision: PARKED (accept M28 as-is, revisit)

For the M28 plumbing milestone we **accept** that a ram concentrates on the
outermost component and barely moves whole-ship health — the damage system is
correct and consistent (lasers still burn through, collisions still respect
armor via the same raymarch), it just doesn't *feel* heavy. This is a tuning /
feel question, not a bug, and it is explicitly deferred.

When we revisit (candidate: alongside the M29/M30 collision-shape work), the
options, roughly increasing effort:
1. **Scale K up** so rams routinely exceed the ~2000/step cap and penetrate.
   Blunt — also makes light taps swingier.
2. **Lower the per-step cap** so any big hit is forced to march. But the cap is
   the shared `ABSORPTION_PER_DENSITY` constant, so this also changes laser feel.
3. **Bias ram damage into `hull`-type components** rather than whatever 20–50 HP
   sensor is outermost. Most physically sensible — a hull ram should crush
   structure, not shear off an antenna. Preferred starting point.
4. **Spread the lump over a few sub-steps/frames** so it ablates-then-advances
   like a sustained beam.

## See also

- `implementation_plans/m28_m30_collision_roadmap.md` — M28 Shipped note records
  the same observation as a friction finding; M29/M30 are the likely revisit
  window.
- `design_ideas/warhead_laser_special_case.md` — the warhead's ranged-laser
  path, which also routes through `take_damage` with the `"laser"` type.
