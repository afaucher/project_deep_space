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

Same code, different **packet size vs. that 2000/step cap**:

- **Laser** — `actual_damage = comp["damage"] × health_ratio` fired repeatedly on
  cooldown; each packet (tens to low hundreds) is far below the cap, so it fully
  deposits into the *first live* component and stops. Across many shots the
  component chips down, dies, and the next shot's ray reaches the layer behind.
  Sustained fire visibly eats inward, one layer at a time.
- **Collision (M28)** — one big lump in a single call. A 400 u/s frigate head-on
  is ~1407, which is **below** the 2000/step cap, so `min(1407, 2000) = 1407` —
  the entire lump is absorbed **in the first step**, by the outermost component
  the ray touches (on a frigate nose that's `dir_high_res`, a 50-HP sensor:
  health goes to 50 − 1407 = −1357), then `remaining_damage` hits 0 and the loop
  ends. No burn-through; ~1357 of the 1407 is wasted overkilling a sensor, so the
  ship's clamped total only drops by that component's 50 HP.

A collision lump *bigger* than the cap (> 2000 into a full-health face) would
burn through in one call — 2000 in step 1, kill the outer component, march the
remainder into the structure behind. M28's tuned `COLLISION_DAMAGE_K` just never
produces a lump that large against a full-health face, so every ram clips exactly
one outermost component.

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
