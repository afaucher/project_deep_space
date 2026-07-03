# Collision Avoidance — a shared steering layer

## The problem

Avoidance today is a single feature on one behavior: `FollowRouteLeaf._separation`
repels patrolling ships from nearby hulls. Nothing else avoids anything — cargo
shuttles, the nav autopilot, and combat AI all fly straight lines and rely on
`RigidBody2D` collision *response* (bodies bounce apart after they touch) instead
of *avoidance* (steering so they don't). And nothing avoids **asteroids or station
hulls** at all — routes just assume clear space.

We want the opposite: every AI hull — cargo, LAC, pirate, warship — should look
where it's going and make sane dodges, especially through asteroid fields. The
hard question isn't the dodge math; it's **when a dodge takes precedence over the
ship's actual goal** (chasing a target, running a cargo lane, fleeing).

## The mechanism — velocity-lookahead, not blind repulsion

The current `_separation` repels from *any* close ship regardless of whether
you're moving toward it — so it fires even for a neighbor you're already leaving,
and it can't reason about a rock dead ahead vs. one off to the side. Replace it
with **predictive, velocity-based avoidance**:

- Look along the ship's current velocity vector (its actual path, per your
  intuition). For each nearby obstacle, compute the **closest-approach** given
  relative position and relative velocity — time-to-closest-approach (TTCA) and
  the miss distance.
- An obstacle is a **threat** only if it's *ahead* (TTCA > 0, within a lookahead
  horizon) *and* the miss distance is inside `obstacle_radius + ship_radius +
  margin`. You only dodge what you'd actually hit — nothing beside or behind you.
- Steer to widen the miss: a lateral push (perpendicular to velocity, away from
  the obstacle's projected side), scaled by imminence. For a head-on static
  obstacle, also bleed speed.
- Keep a small **anti-overlap floor**: a short-range repulsion for bodies already
  within a hull-radius or two, so zero-relative-velocity bunching (two ships
  nose-to-nose) still separates. Velocity-lookahead alone misses that case.

This dodges *through* an asteroid field (steer for the gaps) rather than orbiting
every rock, and it's cheap: O(neighbours) per moving hull, and the sim bubble
already bounds how many hulls are live.

## Precedence — the actual question

Avoidance is **not** a behavior-tree node competing with Engage/Patrol/Cargo. It's
a **steering layer underneath all of them**: the active behavior decides the
*goal* velocity; the avoidance layer *shapes or overrides* that velocity before it
reaches `apply_control_input`. Precedence is expressed as the layer's intensity,
in four tiers:

1. **Suppressed — external control owns the hull.** While docked/captured
   (`docking_bay != null`) or in the docking-yield coast, the berth spring owns
   the motion; avoidance would fight it. Off. (Cargo already yields on capture —
   generalize that suppression.)

2. **Excluded target.** Never avoid the thing you're deliberately approaching —
   the station you're docking at, or the contact you're closing to firing range.
   The current goal's target body is removed from the obstacle set, else a shuttle
   would refuse to approach its own dock and a hunter would refuse to close.

3. **BLEND — a threat exists but isn't imminent (TTCA above the escalation
   threshold).** Add the avoidance vector to the behavior's desired velocity; the
   behavior still leads, the path just bends around obstacles. This is the common
   case: patrol / cruise / attack-run while easing around things. Blend weight is
   lower in combat so it doesn't jitter a firing solution.

4. **OVERRIDE — imminent collision (TTCA below threshold, obstacle squarely in
   path).** Avoidance dominates for those frames: steer hard for the nearest gap
   (and brake if head-on), ignoring the behavior's heading. Survival of the hull
   outranks the current goal — a pirate breaks off its attack run to not eat an
   asteroid; a fleeing ship dodges rather than run straight into a rock. It's a
   few frames, then control returns to the behavior.

So the tree's behavior priority (Disengage > Engage > Patrol/Cargo > Idle) is
**unchanged** — it still picks the *goal*. Avoidance arbitrates the *execution* of
whatever goal is active. "Takes precedence" == tier 4 override; otherwise it's a
modifier, not a mode.

### Who it applies to

- **All AI hulls + the nav autopilot** — universal, as you want.
- **NOT the player's manual helm.** The player decides; avoidance never fights
  live player input. (The player's *autopilot* does avoid — it's flying for them.)
- **Stations** don't move, so N/A (they're obstacles *to* others, via tier 2/3).

### Coarse plan vs. fine dodge

"Generally plan where they're going" already exists as the coarse layer: nav/beacon
routes (M17) and authored patrol/cargo lanes pick the *corridor*. This avoidance is
the *fine* layer that dodges within it. True path-planning around a whole field
(A* through obstacles) is a separate, heavier feature — deferred; reactive
lookahead handles fields well enough to "dodge reasonably easily."

## Enabling change — obstacles must be findable

Ships/stations are in the `"ships"` group and expose `get_bounding_radius()`.
**Asteroids are in no group and expose no radius** (hardcoded 300 collision
circle). Avoidance can't see them today. Prereq: put asteroids (and any large
body) in an `"obstacles"` group with a queryable radius, and have avoidance scan
`"ships"` (dynamic: hulls/stations, with velocity) + `"obstacles"` (static: rocks).
Per-body radius drives the miss-distance test.

## Integration points

A shared `scripts/ai/steering.gd` (static `avoid(actor, desired_vel, exclude) ->
{vel, override}`) called by every mover:
- `FollowRouteLeaf` (replaces its bespoke `_separation`)
- `CargoRunLeaf` (transit; excludes the dock-target station)
- `NavAutopilot`
- `SteerToTargetLeaf` + `StationSteerToTargetLeaf`? (combat — excludes the target;
  low blend weight)
- `FleeLeaf` (dodge while fleeing)

## Open decisions

- **Escalation threshold** — the TTCA (or distance) at which BLEND becomes
  OVERRIDE. One global value vs. per-hull (a nimble LAC dodges later than a barge).
  Default: a global time-to-collision (~1.5–2 s of closing) tuned per the test.
- **Combat blend weight** — how much a mid-fight ship bends for a non-imminent
  rock (0 = only hard-override in combat, ignore gentle threats; >0 = eases around
  them but may spoil aim). Default: small but non-zero.
- **Obstacle query** — group scan (`"ships"` + `"obstacles"`) vs. a physics
  shape-cast along the velocity ray. Group scan is simpler and bubble-bounded;
  shape-cast is more accurate but costlier. Default: group scan.
- **Does the player get an optional avoidance assist** on manual flight (a "flight
  assist" toggle), or strictly hands-off? Default: hands-off for v1.
