# Approach guidance and collision avoidance: what the literature says, and which of it we need

Written 2026-07-27. The control-theory companion to
[docking_approach_control.md](docking_approach_control.md), which owns the
docking *geometry* and the economic case. This doc owns the **guidance law** —
how a hull is actually commanded — and the wider avoidance question TASKS.md
has been carrying ("project multiple paths, slow down, avoid them all").

It exists because the same failure kept recurring under different disguises,
five attempts running, and each attempt was a locally reasonable idea that
could not have worked. Naming the class is worth more than any of the fixes.

## The recurring failure: two different problems, one solved instead of the other

Every attempt at the unzoned docking approach treated it as **waypoint
capture** — pick a point, fly at it, test whether you arrived. The measured
behaviours, in order:

| attempt | what it did | how it failed |
|---|---|---|
| distance-to-seat gate | released avoidance within `capture_radius` of the seat | gate sat inside the avoidance standoff; lone shuttle spiralled, 3 cycles/600s |
| angular-only gate | released avoidance when roughly on-axis | angular tolerance GROWS with range; released from arbitrary distance, rock field 0.00% → 1.00% |
| angular + derived zone | both of the above | gate condition sat at the standoff (~1550 at a SmallStation); hulls parked and orbited |
| approach fix + arrival latch | fly to a point at 2× standoff, latch on arrival | never satisfied the arrival test; limit cycle 1315 → 3816 → 895 → 3981 → 1060 → 5762, amplitude GROWING |
| LOS lookahead (shipped) | steer at a carrot sliding along the axis | converges; see below |

The first three are potential-field equilibria. The fourth is a distinct and
better-known failure, and it is worth stating precisely because it looks like a
tuning problem and is not:

> **A constant-speed, bounded-turn-rate mover cannot converge on a point whose
> capture tolerance is smaller than its turn radius.** It sails through, swings
> back, and the oscillation is unstable rather than damped.

`_cruise_toward` commands full speed at its target on every tick. At 700 u/s a
CargoShuttle's turn radius is far larger than a 275-unit capture radius, so no
value of the latch, the tolerance, or the fix distance could have converged it.
Adding hysteresis to an unstable oscillator does not stabilise it.

## The fix: path following, not waypoint seeking

The distinction is standard and we had simply never drawn it. Waypoint
following wants to *hit a point*; path following wants to *lie on a line*. The
docking approach is the second: nothing cares whether the hull passes through
any particular spot, only that it arrives along the berth axis.

**Lookahead-based line-of-sight guidance** (Lekkas & Fossen) is the standard
answer. Project the hull onto the path, then aim at a point one *lookahead*
further along it:

```
proj  = docking_point + outward * along
aim   = proj - outward * lookahead      # carrot slides; never arrived at
```

Cross-track error then decays as `e(s) = e₀ · exp(-s / L)` over distance run
`s` — exponential convergence, no waypoint to overshoot, and **no arrival
condition to satisfy**, which is precisely what the latch could never meet.

**Lookahead is the whole tuning knob**, and it trades the two failure modes
against each other: large L gives smooth but slow convergence, small L gives
fast convergence with overshoot. Lekkas & Fossen's own refinement is to make it
**time-varying**; we express it as a *time* (`LOS_LOOKAHEAD_TIME`, 3 s) rather
than a distance, so one constant stays correct across a 700 u/s shuttle and a
loaded freighter, and it tightens automatically as the hull sheds speed.

### Speed is part of the guidance law

The first LOS attempt still failed — cross-track *grew* 271 → 1082 on the way
in — because geometry alone is not sufficient. The run from the rejoin point to
the seat is only ~1200 units; at 700 u/s that is 1.7 seconds, less than the
hull's own turn time constant. **No lookahead can converge a path shorter than
the vehicle's transient.** Braking against the aim point (not against the
station hull, which `approach_speed_limit` already covers and which only bites
within ~1.5 bounding radii) is what made it work.

But braking is only needed *while there is cross-track left to kill*. A hull
already on the axis has nothing to steer around, so it runs in at cruise and
lets `approach_speed_limit` govern contact speed. Braking for convergence and
braking for contact are two different jobs; paying both everywhere cost 5.3 s
per cycle and, on a heat-limited hull, that was fatal — see below.

## Why the potential field kept producing orbits

Three of the five attempts died the same way, and this is the single most
useful thing to carry forward. `Steering._avoidance` is an artificial potential
field: goal attraction plus obstacle repulsion, summed. Its two textbook
failure modes (Borenstein & Koren, *Potential Field Methods and Their Inherent
Limitations*) are **local minima** — attraction and repulsion cancel, the hull
stalls — and **cyclic behaviour / oscillation**, where the hull circles without
converging.

Both are structural, not tuning bugs. The operational consequence for this
codebase:

> **You cannot steer to a point that is pushing you away.** Any gate or target
> placed inside the avoidance standoff (`r_self + r_obs + MARGIN`, ~1550 at a
> SmallStation) is unreachable by construction.

That single sentence would have killed three of the five attempts before they
were written. It is why the shipped fix puts the rejoin point at 2× standoff,
in genuinely free space, and why the exclusion gate is **cross-track** (an
absolute tolerance) rather than **angular** (a tolerance that grows with range,
which is what let a hull release avoidance from 5000 units out and drift in).

## The wider question: multi-path avoidance

TASKS.md carries this as "project multiple paths, slow down, avoid them all".
The literature name is **velocity obstacles** (VO), and its reciprocal
multi-agent form is **ORCA** (Optimal Reciprocal Collision Avoidance).

**What VO/ORCA actually do.** Instead of computing a force in *position* space,
they work in *velocity* space: for each obstacle, the set of velocities that
would eventually collide forms a cone, and the agent picks the closest velocity
outside the union of all cones (ORCA does it with half-plane constraints solved
by linear programming). Two consequences matter to us:

- **Slowing down is a first-class option.** Our avoidance can only ever *bend*
  the heading — `steer()` returns a direction, and speed is decided elsewhere.
  A velocity-space method can answer "there is no safe heading at this speed,
  so go slower", which is exactly the manoeuvre a human pilot would make and
  the one we currently cannot express. This is the single biggest capability
  gap, and it is independent of everything else here.
- **All threats at once, without cancellation.** We deliberately react to the
  single worst threat because *summing* near-opposite dodge vectors collapses
  toward zero and flies the hull down the middle (the wrong-combinator bug in
  `collision_avoidance.md`). VO does not have that failure: constraints
  intersect rather than add, so N obstacles narrow the feasible set instead of
  averaging into nonsense. Worst-threat-only is a real limitation — it is blind
  to the second-worst threat until the first clears — and this is the principled
  fix for it.

**What the comparisons say.** VO methods succeed in symmetric situations where
potential fields fail outright, which is the relevant class here (converging
traffic at a station mouth is exactly symmetric). The costs are equally
documented and we should expect them:

- ORCA's linear constraints are **overly conservative in dense crowds**, and
  can become infeasible — no velocity satisfies every constraint.
- It can **deadlock**: agents creep or stop entirely. Our current field at
  least always moves.
- It assumes **reciprocity** — every agent running the same algorithm and
  taking half the avoidance burden. Asteroids do not reciprocate, and neither
  does a player. Non-reciprocal obstacles have to be modelled as plain VO
  (take the full burden), which is a per-obstacle distinction we would need to
  carry.

**Recommendation.** Do not replace `Steering._avoidance` wholesale. The
sequenced-worst-threat field works, is cheap, and is in the hottest path in the
game. Take the *one* thing that is a genuine capability gap — **speed as an
avoidance output** — and add it first: let `_avoidance` report "no safe heading
at this speed" and have `_cruise_toward` slow down instead of only turning.
That is a small change against a measured problem. A full VO/ORCA rewrite is a
large change against a hypothetical one, and it brings deadlock and
conservatism we do not currently have.

## The thermal coupling nobody had costed

Fixing the approach surfaced a genuine and previously invisible constraint.

A CargoShuttle's heat is **thrust-driven** with a real equilibrium: it rises at
~2.66/s while manoeuvring and falls sharply once the hull coasts (144 → 55 over
15 s of coasting). Heat is therefore a proxy for *time spent under thrust*, and
a proper docking approach spends much more of it than cutting the corner does.

Measured on `test_visitor_itinerary`, one dock cycle:

| | reaches berth at | heat at berth | after exit burn |
|---|---|---|---|
| baseline (cut the corner) | frame 2216 | 111 / 150 | 144 (96% — survives) |
| LOS approach | frame 2585 | 131 / 150 | **pegged at 150 → reactor drained → `hulk()`** |

The exit burn costs ~26 heat on both. Baseline clears it with 6 points to
spare; the LOS approach does not. **The hull dies of its own approach**, at 90%
structural health, and because `hulk()` makes `JobRunnerLeaf.tick` return
FAILURE immediately, the corpse coasts in a straight line forever — it flew
*through* its exit point 159 units away without despawning, which reads in the
log as a navigation failure and is nothing of the sort.

Three things follow:

1. **Arrival gentleness is paid for in ship heat, and somebody has to pay it.**
   Going from cruise to berthed is a fixed Δv. Baseline offloads it to the
   bay's servo (and, when that misses, to the station's hull — which is the
   12.5 lots/hr of self-repair this whole line of work exists to remove). The
   LOS approach pays it with engines. That is the correct trade for the
   *cluster*, and it moves a cost from stations onto hulls.
2. **The CargoShuttle's envelope has no margin for it.** 96% peak at baseline
   is not a healthy figure; it means any approach change at all was going to
   break this. Whether that is fixed by raising `max_heat` (150, vs the Ship
   default 200), by raising `heat_dissipation_rate` (never overridden on this
   hull), or by leaving it as a real constraint the fleet must live with, is a
   **balance decision, not a guidance one** — which is why this change does not
   quietly widen it.
3. **`hulk()` is silent.** A thermally-dead hull produces no console line, no
   log entry, and no visible difference from a ship flying badly. That is worth
   fixing on its own — `economy_traffic` runs for hours and nothing would
   report ships cooking themselves.

## Sources

- [Design, validation and comparison of path following controllers for autonomous vehicles](https://pmc.ncbi.nlm.nih.gov/articles/PMC7660643/) — pure pursuit / LOS / carrot-chasing compared; overshoot at speed
- [A time-varying lookahead distance guidance law for path following](https://www.sciencedirect.com/science/article/pii/S1474667016312629) — Lekkas & Fossen; the lookahead trade-off and its cross-track-dependent refinement
- [A uniform semiglobal exponential stable adaptive line-of-sight (ALOS) guidance law](https://www.sciencedirect.com/science/article/pii/S0005109824000487) — exponential convergence of cross-track error
- [An improved ELOS guidance law for path following of underactuated USVs](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11359112/) — convergence vs guidance stages
- [Potential field methods and their inherent limitations for mobile robot navigation](https://www.cs.cmu.edu/~motionplanning/papers/sbp_papers/integrated1/borenstein_potential_field_limitations.pdf) — local minima, oscillation, cyclic behaviour
- [Reciprocal n-body collision avoidance](https://www.researchgate.net/publication/225369513_Reciprocal_n-Body_Collision_Avoidance) — ORCA
- [Comparison of velocity obstacle and artificial potential field methods for collision avoidance in swarm operation](https://www.mdpi.com/2077-1312/10/12/2036) — the trade we would be making
- [Directional optimal reciprocal collision avoidance](https://www.sciencedirect.com/science/article/abs/pii/S0921889020305455) — ORCA's conservatism and infeasibility in dense cases
