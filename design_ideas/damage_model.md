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

## Playtest finding (2026-07-05): rams are bimodal, and thickness barely matters

First hands-on ram: from the campaign start, **full reverse into a station ~3k
away** destroyed the ship's `engine_main`, `hull_aft`, `reactor_core`, and one
aft sensor — and, because the reactor died, `is_sys_destroyed("reactor") →
hulk()`, so **the ram was fatal.** The model predicts this exactly:

- Reverse over 3000 u reaches ~550 u/s (`thrust 5000 / mass ~90 ≈ 55 u/s²`,
  `sqrt(2·a·d) ≈ 570`; below the 1000 max_speed cap). Against a station ~1000×
  heavier the reduced mass is ~the frigate's own (~90), so the lump is
  `0.0005 × 90 × (550−150)² ≈ 7200` — **well over the 2000/step cap.**
- Penetration ≈ `lump / 2000` components: each full-health component in the path
  costs a **flat ~2000** (one step at the density-20 cap) then dies and is
  skipped. 7200 → ~3.6 → four components deep. Matches what was observed.

Two properties this surfaces:
1. **Ram lethality is bimodal**, not weak: negligible below the cap (the 1407
   test lump clipped one sensor), then ~2000-per-component brutal above it. The
   "feel weak" note above is only the sub-cap half of the picture.
2. **Penetration ignores armor HP.** A 40-HP sensor and a 1000-HP hull plate each
   cost the ram the same ~2000 of budget, so ram *depth* is about component
   **count** in the path, not armor thickness — a heavily-armored hull and a
   paper one take about the same number of layers. Odd for a "kinetic" model.
3. **Reverse-ramming is a footgun.** `engine_main` (x −35) and `reactor_core`
   (x −15) sit at the aft face, so backing into something drives straight through
   the drive and powerplant (→ reactor death → hulk). A *forward* ram at the same
   speed spends itself on nose sensors/weapons + `hull_fwd` with the reactor
   better shielded — far more survivable. Emergent and arguably correct, but
   punishing.

## Decision: PARKED (accept M28 as-is, revisit)

For the M28 plumbing milestone we **accept** the behavior — the damage system is
correct and consistent (lasers and collisions share one raymarch), it just has
the bimodal feel and thickness-blindness above. This is a tuning / feel question,
not a bug, and it is explicitly deferred.

When we revisit (candidate: alongside the M29/M30 collision-shape work), the
sharpened read is that the real oddity is **penetration ignoring armor HP**, not
"rams too weak" — which argues *against* pure K-scaling. Options:
1. **Scale a component's per-step soak with its own HP** (so a thick hull plate
   actually stops more of a ram than a thin sensor does). Most directly fixes the
   thickness-blindness; now the leading candidate.
2. **Bias ram damage into `hull`-type components** rather than whatever 20–50 HP
   sensor is outermost — a hull ram should crush structure, not shear off an
   antenna. Good companion to (1).
3. **Spread the lump over a few sub-steps/frames** so it ablates-then-advances
   like a sustained beam.
4. **Scale K up** so light rams also bite — blunt, worsens the bimodal cliff and
   the reverse-ram one-shot; *least* preferred given the finding above.
5. **Lower the per-step cap** — but it's the shared `ABSORPTION_PER_DENSITY`
   constant, so it also changes laser feel.

## See also

- `implementation_plans/m28_m30_collision_roadmap.md` — M28 Shipped note records
  the same observation as a friction finding; M29/M30 are the likely revisit
  window.
- `design_ideas/warhead_laser_special_case.md` — the warhead's ranged-laser
  path, which also routes through `take_damage` with the `"laser"` type.
