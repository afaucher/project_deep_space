# Docking approach: making the drawn corridor the flown one

The control half of [port_zones_and_channels.md](port_zones_and_channels.md).
That doc owns the model, the vocabulary and the rendering; this one owns what
the AI actually does with it. Written 2026-07-26, after measurement made
docking damage the binding constraint on the whole economy.

## Why this is now the highest-value work

Station self-repair burns **~12.5 lots/hr of REFINED and GOODS** against a
combined *authored* cluster margin of ~1.3/hr — roughly **ten times the entire
trade surplus**. Stations pay for collision damage out of the two commodities
the cluster is already shortest of, which is why this first surfaced as an
economy anomaly rather than a collision report.

Worse, it scales with success. Raising `LOT_SIZE` 1.0 → 4.0 produced **+55%
deliveries and +66% self-repair** in the same run: every delivery is a docking
and every docking is a collision opportunity. **The cluster cannot trade its
way out, because trading costs hull.** No rate change in `home_cluster.gd`
touches this, and every future throughput improvement makes it worse.

## The actual defect: three of four layers are drawings

The standard structure for autonomous rendezvous and docking has four layers.
We have geometry for three of them and fly none:

| layer | authored / implemented? | does the AI use it? |
|---|---|---|
| keep-out (`exclusion_radius`, hull × 6) | yes, derived + drawn | **no** |
| approach corridor (`PortChannel`, 90° cone) | yes — cone, guide, hatch cutout | **no — render only** |
| hold points | — | — |
| glide slope (`Steering.approach_speed_limit`) | yes | **yes** |

`PortChannel` is referenced by exactly two files: `navigation_panel.gd` and
`exclusion_hatch.gd`. Both are rendering. **The corridor the player sees drawn
has never been a depiction of what any ship was doing.**

What `step_dock_at` actually does:

```gdscript
var approach_pt = target_berth.global_position
    + Vector2.RIGHT.rotated(target_berth.global_rotation) * (target_berth.capture_radius * 0.8)
_cruise_toward(actor, approach_pt, station.position, 700.0)
```

Two things wrong, and neither is speed:

1. **One waypoint, not a path.** `_cruise_toward` flies a straight line from
   wherever the ship happens to be. If the berth faces away from the ship's
   approach, that line passes **through the hull**. The aim point itself sits
   ~300u off the hull (`capture_radius` ≈ 396u for a medium station, × 0.8),
   deep inside the ~1584u exclusion zone.
2. **`exclude_pos` is binary.** The second argument is the body steering will
   *never* dodge — and it is the station. The ship explicitly disables
   avoidance for the object it is flying at, from any range and any angle.

**This is why the braking work helped but did not fix it.** A ship that arrives
slowly through the middle of a station still hits the station. Speed was never
the problem; path was.

## What the literature does, and what transfers

Standard practice (see Sources) is a keep-out volume over the target's surface
with a **cone-shaped approach corridor along the docking axis as the only legal
way in**, discrete **hold points** on that axis where the vehicle stops and
waits for clearance, and a **glide slope** — commanded speed falling with range
so contact velocity is correct by construction rather than by luck.

The V-bar / R-bar distinction does not transfer literally (no orbital mechanics
here), but the *reason* for it does: approach direction is chosen for **passive
safety**, R-bar being preferred because a thrust failure drifts you away from
the station instead of into it. Our version of that principle: prefer approach
geometries where losing control does not put a hull through a station.

## Design

**1. The corridor becomes a constraint, not a picture.** A ship may cross
`exclusion_radius` only inside the approach cone. Outside the cone the
exclusion zone is a keep-out like any other obstacle.

**2. Replace the single waypoint with the sequence the geometry already
describes**: corridor **mouth** (where the cone crosses `exclusion_radius`) →
down the **guide** (centreline) → **capture zone**, where the clamp takes over.
`PortChannel.guide_segment()` already returns exactly this and is currently
called only by the nav panel. Wire it into `step_dock_at`.

**3. Keep-out WITH a cut-out, replacing the binary `exclude_pos`.** Station
avoidance stays active everywhere except inside the approach cone. This is the
same shape `exclusion_hatch.gd` already computes for rendering (subtracting
`PortChannel.sector_polygon`). The steering contract changes from "never dodge
this body" to "don't dodge this body while inside its corridor" — which is
the honest statement of what docking needs.

**4. Glide slope stays as-is.** `approach_speed_limit`'s
`v = √(v_dock² + 2·a·d)` with per-hull decel is already the right shape. It
was necessary and is not sufficient.

**5. Degrade down the ladder, don't branch.** Levels 0–2 (mobile homes, small
stations) author no corridor and draw none. The AI should still **derive** an
approach axis from the berth's own heading and keep the hull avoided — that is
[port_zones_and_channels.md](port_zones_and_channels.md)'s *approach discipline
(self-imposed, universal)*: you slow down and come in straight because you do
not want to hit the thing, not because someone is enforcing it. The authored
corridor at Level 3+ is then a *published, enforceable* version of a rule every
competent hull already follows — which is exactly the asymmetry that doc wants
to keep.

## Decisions this needs

- **No grant, no corridor?** A pirate boarding a hull (Level 0 by definition)
  has no grant and no corridor. Does it get approach discipline anyway
  (competence, applies to everyone) while losing the corridor's *legal*
  protection? Leaning yes — the rules are separate: discipline is physics,
  the corridor is jurisdiction.
- **Hold points: worth it, or over-engineering?** They buy something real for
  gameplay — a visible queue outside a busy port makes port control matter and
  reads instantly. But they are the one layer we have no geometry for yet.
- **Corridor contention.** Two ships granted adjacent berths with overlapping
  cones. Today convergence-shoving is already a measured damage source. A hold
  point is the standard answer; first-come-first-served on the mouth is the
  cheap one.
- **Does the player get the constraint?** No — existing rule stands, the player
  is free to be a menace. But the guide is already drawn for them, so the
  affordance exists.

## Explicitly NOT this work

- Not a physics change, not a speed change (the glide slope exists), and not
  new geometry — `PortChannel` is implemented and tested.
- Not the *published speed limit* (rule 2 in the port-zones doc), still
  specified and unbuilt. Independent of this.

## How we will know it worked

`economy_traffic`'s self-repair total is the instrument, currently **12.54
lots/hr** cluster-wide with 99 deliveries. Success is that figure falling
substantially while delivery count holds — the coupling broken, not the trade
suppressed. `test_dock_approach` already asserts per-cycle damaging-contact
rates and station HP loss, and is the cheap gate; the sim is the verdict.

Watch for the trap the `LOT_SIZE` change exposed: a change that *reduces*
deliveries will reduce repair too, and look like a win. Read both columns.

## Sources

- [V-bar and R-bar glideslope guidance for fixed-time rendezvous](https://www.sciencedirect.com/science/article/pii/S2405896316315397)
- [Approach corridor defined by a cone about the docking axis](https://www.researchgate.net/figure/Approach-corridor-for-rendezvous-defined-by-a-cone-with-the-docking-axis-n-and-apex_fig8_268557803)
- [Autonomous rendezvous and mating with keep-out zone and collision-avoidance manoeuvring](https://www.sciencedirect.com/science/article/pii/S0094576525001754)
- [Safety motion planning for spacecraft proximity operations](https://www.eucass.eu/doi/EUCASS2019-0908.pdf)
- [Model predictive control for autonomous rendezvous and docking](https://www.sciencedirect.com/science/article/abs/pii/S1270963817301293)
