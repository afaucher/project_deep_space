# M28–M30 — Collision roadmap: damage first, accurate concave shapes last

Status: M28 SHIPPED (2026-07-04); M29 + M30 PLANNED. Design context:
`design_ideas/ship_outline_rendering.md` (geometry-consistency problem, the
collision open-decision findings) and the outline v1.1 work — `ShipSilhouette`
already computes the exact contours these milestones reuse.

Ordering principle (user-set): **easy solutions first**, ending at accurate
collision for concave hulls. Holes are explicitly IGNORED throughout — the
defence pod's ring center stays physically solid (outer contour only); the
drawn hole vs solid physics is an accepted, documented gap.

```
M28 kinetic collision damage (shapes as-is)   -- plumbing + gameplay, no shape risk
  └─► M29 convex-hull collision (one shape/ship) -- polygon physics de-risked
        └─► M30 decomposed concave collision      -- notches real, see-it-touch-it
```

Execution model: same loop as M21–M27 — Sonnet subagent implements from this
doc, Fable validates (re-runs gates + regression, diff review, commits). One
milestone per agent, sequential, standing guardrails (preload consts, no
--check-only, one Godot instance, tabs, `.get()` defaults, no test weakening).

---

## M28 — Kinetic collision damage (the easy win, current shapes)

Goal: physical impacts hurt. Works on today's bounding-circle shapes; no
shape changes at all.

### Scope

- `ship.gd`: enable `contact_monitor = true`, `max_contacts_reported = 4`,
  connect `body_entered`. Ships cache `_prev_linear_velocity` each physics
  tick (one Vector2 store) so impact speed uses PRE-solve velocities — the
  bounce has already altered `linear_velocity` by the time the signal fires.
  For the other body: its own cached prev-velocity when it's a Ship; its
  current velocity when it's an asteroid (rocks are heavy, their post-bounce
  delta is negligible; do NOT add a per-frame script to rocks just for this).
- Damage on contact, both parties damage THEMSELVES from their own handler:
  - `v_impact = (v_self_prev - v_other).length()`
  - below `COLLISION_DAMAGE_MIN_SPEED := 150.0` → free (docking settle is
    ~25 u/s; routine traffic bumps stay consequence-free)
  - else `damage = COLLISION_DAMAGE_K * reduced_mass * pow(v_impact - COLLISION_DAMAGE_MIN_SPEED, 2)`
    with `reduced_mass = m1*m2/(m1+m2)` (symmetric by construction; K tuned
    so a 400 u/s frigate-vs-frigate head-on wrecks hull plates but doesn't
    one-shot either ship — pick K in-test, document the chosen value)
  - `take_damage(damage, hit_pos, hit_dir, "kinetic")` with
    `hit_dir = (other.position - position).normalized()` and
    `hit_pos = position + hit_dir * get_bounding_radius()` (exact for
    circles; good-enough approximation that M29/M30 inherit). The existing
    raymarch then chews components inward from the impact side — armor
    matters for rams with zero new damage-model code. "kinetic" already
    takes the low heat modifier path.
- Gating — **the speed threshold is the only gate; no blanket exemptions**
  (user decision). Routine traffic is protected by physics, not special cases:
  - **Docking is NOT exempt.** A routine capture+settle should fall below
    `COLLISION_DAMAGE_MIN_SPEED` on its own (settle is ~25 u/s), so it costs
    nothing — but if someone *slams* you into a station at speed, that SHOULD
    hurt. We test this rather than carve an exception: if the capture spring
    legitimately drives contact speed past the threshold during a normal dock,
    the fix is to soften the spring / raise the threshold, not to exempt the
    host. The test asserts routine docking stays sub-threshold AND that a
    high-speed slam into the station deals damage.
  - **Missiles DO collide and DO take/deal contact damage.** Physical
    collision is a legitimate way to stop a missile, so there is no
    `collision_damage_enabled` exclusion. A missile is low-mass, so its
    reduced-mass term makes a contact hit naturally *mild* kinetic damage — no
    special-casing needed. The warhead is a *separate* system: "exploding" is
    the missile firing a laser at a distance, not a contact event, so there is
    no double-count to guard against. Missiles participate in the same
    symmetric contact-damage path as any other body.
  - Asteroids take nothing (no `take_damage` method — guard with
    `has_method`); ships (and missiles) hitting them still take their own
    share.
- Optional: a `DebugSettings.OPTIONS` knob ("collision_damage" on/off) for
  playtesting.

### Test plan (Fable) — `test_collision_damage.gd`

1. **Head-on above threshold**: two frigates closing at ~400 u/s combined →
   both take damage; on each, the impact-side hull plate's health < the
   far-side plate's (proves the raymarch entered from the contact face).
2. **Gentle bump**: closing at 60 u/s → zero damage, both sides.
3. **Rock ram**: ship into an asteroid well above threshold → ship damaged,
   asteroid unaffected, zero script errors (the has_method guard).
4. **Routine docking stays sub-threshold (no exemption)**: reuse the
   freighter-capture harness end to end → ship at full (or near-full) health
   after capture+settle+release *because contact speed never crosses the
   threshold*, NOT because docking is exempt. If the capture spring pushes
   contact speed over the gate, that's a spring/threshold tuning bug to fix —
   assert the observed peak contact speed and pin it below the gate.
   Companion assertion: a deliberate high-speed ram into the station host DOES
   deal damage (proves the host isn't specially protected).
5. **Missile contact = mild kinetic**: a missile physically colliding with a
   ship deals NON-zero contact damage via the shared path, but small (low
   reduced mass) — assert it's positive and well under a like-speed frigate
   ram. The warhead/ranged-laser system is separate and out of scope here.
6. **Symmetry**: identical ships, mirrored approach → damage totals equal
   within 10%.
7. **Monotonicity**: three impact speeds (200/300/400) → strictly increasing
   damage; threshold+epsilon → near-zero.
8. **Negative control**: with the DebugSettings knob off (if built) or
   threshold raised in-test, the head-on case deals zero — proves the gate
   is the gate.

Regression: `test_docking`, `test_docking_multi`, `test_freighter_docking`,
`test_cargo_run`, `test_patrol`, `test_avoidance`, `test_mine`,
`test_defence_pod` — all must stay green, which doubles as proof that no
existing behavior generates accidental ram damage.

### Shipped (2026-07-04)

Implemented in `ship.gd` (`_on_body_entered`, `_prev_linear_velocity` cached at
the top of `_physics_process`, `contact_monitor`/`max_contacts_reported` in
`_ready`), `debug_settings.gd` (`collision_damage` ON/OFF knob), and
`test_collision_damage.gd` (8 phases). **`COLLISION_DAMAGE_K = 0.0005`**,
`COLLISION_DAMAGE_MIN_SPEED = 150.0`. Friction findings:
- **Damage direction:** `take_damage`'s `global_dir` must point INWARD from the
  contact face (`-impact_dir`); backwards, the raymarch starts at the hull and
  heads away, silently dealing zero.
- **Gating validated with no exemptions:** routine freighter docking never even
  brings the collision circles into contact (M27 standoff → peak *contact* speed
  0), so it's free by physics; a 500 u/s ram into a station deals ~5300 (no host
  exemption); a missile hit is 167 vs a 1407 frigate ram (mild, by reduced mass).
- **Damage concentrates on the outermost component the ray hits** (a 400 u/s ram
  overkills one ~50-HP forward component and stops; whole-ship health barely
  moves). That's existing `take_damage` raymarch behavior, not new here — noted
  as a *playtest* question for whether rams should feel heftier (a future
  penetration/spread tweak), out of scope for M28's plumbing milestone.

---

## M29 — Convex-hull collision (one polygon per ship)

Goal: replace every Ship's bounding-circle collision with the convex hull of
its silhouette — a single `ConvexPolygonShape2D`, always solver-legal, no
decomposition yet. The easy 80%: elongated hulls stop colliding at their
circumscribed radius (destroyer broadside drops from r≈66 to its true ~25
half-width). Concave hulls get tighter but their notches stay filled — that's
M30. Depends on: M28 (its suite becomes the contact-behavior regression
harness), ShipSilhouette (exists).

### Scope

- `ship.gd` `_ready()`: collision shape becomes
  `ConvexPolygonShape2D(Geometry2D.convex_hull(outer_loop_points))` from the
  ship's cached silhouette (outer loops only). Rect-less fallback stays the
  50u circle. `asteroid.gd` untouched (a rock's circle IS its truth).
  Explicit mass/inertia are authored, not shape-derived — handling feel must
  not change.
- Docking standoff, Steering margins, nav bounds ring: all stay on
  `get_bounding_radius()` — conservative and correct (the circle circumscribes
  the hull). No retunes this milestone.
- Watch-item: tunneling. A 2200 u/s LAC moves ~37u/frame — comparable to thin
  hull features. The test plan probes it; the contingency is
  `continuous_cd = CCD_MODE_CAST_RAY` on LIGHT-tier fast hulls, applied only
  if the test demonstrates tunneling.

### Test plan (Fable) — `test_collision_shapes.gd`

1. **Shape policy**: every catalog ship + variant carries exactly one
   `ConvexPolygonShape2D` (≥4 points); asteroids still `CircleShape2D`.
2. **Hull correctness**: shape points == `Geometry2D.convex_hull` of the
   silhouette outer loop (point-set equality within epsilon).
3. **Tightness, physically probed** (space-state point/shape queries):
   destroyer broadside at ~50u from centerline → NO hit (old circle r≈66 hit
   it); destroyer nose at the same distance along +X → hit. The before/after
   pair is the milestone's proof.
4. **Ram accuracy**: M28's head-on test re-run — impact-side damage still
   lands on the contact face with polygon-derived contact points.
5. **Tunneling probe**: LAC at max_speed crossing a station arm's line —
   assert it either contacts or (with CCD contingency applied) contacts;
   document which. No silent pass-through.
6. Full regression: M28 suite + docking suite + `test_avoidance` +
   `test_patrol` + `test_cargo_run` + campaign bootstrap suite (contact
   normals feed the docking spring's environment now).

---

## M30 — Accurate concave collision (the last milestone)

Goal: see-it-touch-it. Concave hulls collide as their true outer contour —
station notches become flyable, the freighter's pod gap is real space, a hull
only bumps where its drawn outline touches. **Holes ignored by design** (user
decision): decomposition uses the OUTER loop only; the defence pod's ring
center stays solid and the drawn hole remains a documented cosmetic gap.
Depends on: M29.

### Scope

- Selection rule (measure, don't author — same philosophy as the outline
  work): `ShipSilhouette` gains `concavity_ratio(loops) -> float`
  (= area(convex_hull) / area(outer union)). Ratio < 1.15 → keep M29's single
  convex hull (compact hulls: cheaper, already accurate within tolerance).
  Ratio ≥ 1.15 → `Geometry2D.decompose_polygon_in_convex(outer_loop)` → one
  `ConvexPolygonShape2D` per convex piece, all on the body. Expected to
  promote: stations (plus-shapes), defence pod (ring → outer square ring
  decomposes to ~4 pieces around a solid center is WRONG — the ring's outer
  loop is just its outer square, which decomposes to 1 piece; that is exactly
  the holes-ignored behavior we want — note it explicitly), freighter
  (spine+pods), possibly the asteroid station (blobby but near-convex —
  let the ratio decide).
- Decompose the same weld-inflated contour the outline draws (0.1 fatter —
  invisible, consistent).
- Piece-count sanity cap: warn (not fail) if any hull decomposes to > 12
  pieces — that's a sign the silhouette needs simplification, not a bigger
  cap.
- Berth/standoff retune explicitly OUT of scope (radius-based stays;
  a future milestone may let big ships dock closer along notch lines).

### Test plan (Fable) — extend `test_collision_shapes.gd`

1. **Promotion policy**: medium/small station + freighter carry multiple
   convex shapes; frigate/LAC/shuttle still exactly one (ratio below
   threshold). Assert the ratio values driving each decision (printed +
   pinned within loose bands) so a silhouette change can't silently flip
   policy.
2. **Coverage equivalence (the accuracy gate)**: sample a grid of points —
   every point inside the outer contour (point-in-polygon oracle) is inside
   ≥1 collision piece; every notch point (outside the contour, inside the
   convex hull) is inside NONE. Run for the medium station and freighter.
3. **Notch flyability, physically probed**: space-state query at a
   medium-station notch point (diagonal between two arms, radius chosen
   inside the old bounding circle) → no hit; at an arm point → hit.
4. **Ring stays solid**: query at the defence pod's center → HIT, asserted
   intentionally with a comment citing the holes-ignored decision.
5. **Park in the notch**: a shuttle positioned in the station notch for 120
   physics frames → zero contacts, zero damage, no ejection (the M28+M30
   integration proof).
6. **Ram the arm**: LAC into a station arm above threshold → damage lands,
   impact-side, exactly as on convex hulls.
7. Full regression: everything M29 ran, plus `test_asteroid_station` and the
   sensor/outline suites (`test_ship_geometry`, `test_sensor_dots`,
   `test_ship_silhouette` — collision changes must not touch render seams).

### Validation-phase extras (all three milestones)

- Manual acceptance after M30: campaign mode — fly into Ironhold's notch and
  sit there; graze an arm at speed and watch the impact-side plates dim on
  the engineering panel; thread the Slag Bay field where every rock's blob,
  circle, and hitbox now agree.
- Mark each milestone DONE with a Shipped note; commit per milestone;
  friction findings (decomposition counts, CCD decision, K tuning) recorded
  in the DONE notes.
