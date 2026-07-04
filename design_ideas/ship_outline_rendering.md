# Close-range ship outline rendering & geometry consistency

Status: design — v1/v2 approach decided (see "Decided path" below). No
implementation yet. Shape variety on the authoring side is the companion doc
`hull_shape_grammar.md`; outlines are what make that variety visible.

## Motivation

Several scenarios put ships physically close together — docking, station
approach, close escort, point-blank knife-fights, boarding. At those ranges the
sensor-blip abstraction throws away something real: the *physical* sense of the
ship — its shape, size, orientation, and which way it's facing. We'd like to
**render actual ship outlines when a ship is close enough** (below a distance /
above a zoom threshold), so the player gets a bodily sense of the vessel instead
of a dot. This matters most for **stations**, where conveying *scale* (a station
should dwarf a frigate) is the whole point.

This also forces a question we've quietly dodged: **do our collision and contact
"bounds" indicators actually match the ships' physical component geometry?**
(Short answer below: no.)

## What we have to build on

- The world is a top-down zoomable tactical map ([navigation_panel.gd](../scripts/ui/navigation_panel.gd),
  world→screen transform, zoom 0.001–5.0 since the campaign-scale widening).
- Ships are `RigidBody2D`s built from **component rects** (the loadout in each
  ship class). Those rects ARE the true geometry — position + size in ship-local
  space, forward = +X.
- Component rects already partially flow to the client: the nav panel reads each
  weapon's `rect` to draw firing arcs ([navigation_panel.gd](../scripts/ui/navigation_panel.gd)).
  So at least some rect data crosses the wire today; full-loadout availability
  for arbitrary contacts needs confirming/extending.

## The geometry-consistency problem (answers "do bounds map to dimensions?")

There are **four different notions of a ship's "size," and they don't agree:**

| Notion | Source | Value | Derived from real geometry? |
|--------|--------|-------|------------------------------|
| Component AABB | `_cached_bbox_min/max` ([ship.gd:461](../scripts/ships/ship.gd:461)) | per-ship, from rects | **Yes** — but used only for the damage raymarch |
| Collision circle | `SHIP_COLLISION_RADIUS` ([ship.gd:601](../scripts/ships/ship.gd:601)) | **flat 50** for every ship | No |
| Nav "physical bounds" ring | hardcoded `draw_arc(pos, 50.0, ...)` ([navigation_panel.gd](../scripts/ui/navigation_panel.gd)) | **literal 50** | No |
| `cross_section` | authored sensor scalar ([ship.gd:431](../scripts/ships/ship.gd:431)) | 50 / 75 / 10 / 2 | No — it's a sensor signature, not physical units |

**Concrete mismatch, made worse by M9c:**
- Frigate's real envelope ≈ 80×60 units → a 50-radius (100Ø) circle roughly
  contains it. Coincidentally OK.
- **Destroyer's real envelope ≈ 108×69** (components reach ~59 fwd / ~49 aft) →
  it pokes well outside the flat 50 circle. Collisions, the bounds ring, and any
  rendered outline would visibly disagree.
- **Light attack craft** is tiny → the 50 circle is far too big.

So: collision, the on-map bounds ring, and cross_section are all **decoupled from
the actual component geometry**. The moment we render true outlines, that
disagreement becomes visible (a destroyer drawn 108 long but ringed/colliding as
a 100Ø circle looks broken).

### Proposed fix: one canonical geometry, sourced from components
Add helpers on `Ship`, derived from the same rects the raymarch already scans:
- `get_local_aabb() -> Rect2` (promote the `_cached_bbox` logic to a reusable
  method).
- `get_bounding_radius() -> float` (max corner distance from origin) for a
  size-correct collision circle / bounds ring.
Then drive **collision shape, the nav bounds ring, and outline rendering all from
these** — so what you see, what you hit, and what the indicator shows agree.
Non-circular collision (polygon/capsule from the AABB or convex hull) is a bigger,
separate change but is where the destroyer's mismatch eventually points.

## Outline rendering — style options to prototype

1. **Per-component rects** — draw each component's rect (rotated to ship
   heading), colored by `type` (hull/weapon/sensor/engine/reactor) and/or dimmed
   by health. Cheap, maximally data-faithful, reuses the loadout, and doubles as
   a **damage visualization** (a destroyed component dims/vanishes). Reads as
   "the ship is its parts."
2. **Hull silhouette** — one outline polygon derived from the component rects.
   Cleaner, reads as a ship shape, less busy. Good for farther/zoomed-out LOD.
   NOTE: "convex hull" was the original sketch here, but it's only faithful
   for compact hulls — see "Silhouette LOD: beyond the convex hull" below for
   the real shape menu and the auto-selection rule.
3. **Wireframe** — silhouette outline + internal component edges. Middle ground.

**Recommendation:** start with **(1) per-component rects colored by type/health**
— it's the most informative, reuses existing data, and doubles as damage feedback
— then add **(2) silhouette** as a lower-detail LOD for mid-range / many contacts.

## "Only the facing side"

The idea: render only the side of the ship facing the viewer (the near
silhouette edge), for realism, cheapness, and a clearer sense of orientation.
- In 2D top-down, "facing side" = the half of the silhouette toward the viewer →
  a 2D back-face cull: for a hull-outline polygon, draw only edges whose outward
  normal has positive dot with (viewer − target). For per-component rects, dim or
  drop the far-side components.
- Honest caveat: in flat top-down with no lighting this is **subtle** — it mostly
  conveys facing, which the existing rotation indicator ([navigation_panel.gd](../scripts/ui/navigation_panel.gd))
  already hints at. It pays off more if we ever add shading/pseudo-3D. Treat as
  polish to layer *after* basic outlines work, not a first cut.

## Distance / zoom gating (LOD)

Only draw outlines when the ship subtends enough pixels to be worth it:
- Switch blip → outline when `get_bounding_radius() * map_zoom > N px`
  (e.g. ~12 px). Below that, keep the cheap blip/marker.
- **Stations: always outline** (or a much larger threshold) — scale is the point.
- This keeps a busy battle readable (distant swarm = blips; the ship you're
  knife-fighting = full outline).

## Stations & scale

Stations (T4, future) are the strongest case: a station should *visibly* dwarf a
frigate. This **requires** the geometry-from-components unification — a station's
AABB is huge, so the flat 50 circle would be absurd. True outlines + the existing
world grid give an immediate sense of "this thing is enormous."

## Tie-back to the sensor game (important open question)

Do we render outlines for *everyone*, or gate by knowledge?
- Drawing a **hostile** contact's exact component layout from sensor data leaks
  information the sensor game is built to withhold (uncertainty is the point).
- Suggested coupling: **own ship + identified friendlies → full outline**;
  **hostile/unidentified contacts → silhouette only, detail scaled by sensor
  resolution** (a fine fire-control lock reveals more of the outline; a coarse
  contact shows only a fuzzy blob sized by estimated `cross_section`). This makes
  the visual a *reward* for good sensor work rather than free ground truth, and
  reuses the existing resolution/bin machinery.

## Dependencies / what to build first

1. `Ship.get_local_aabb()` / `get_bounding_radius()` (promote `_cached_bbox`).
2. Confirm/extend the state packet so a nearby contact's component rects (or at
   least its AABB + a coarse silhouette) reach the client.
3. Outline draw pass in the nav panel (style 1), gated by the LOD threshold.
4. Repoint the nav bounds ring (and later collision) at the derived geometry.
Then: silhouette LOD, facing-side cull, sensor-resolution gating, stations.

## Unifying the contact dimension (sensor size vs physical size)

The geometry-consistency fix above unifies the *physical* size notions
(collision / bounds / outline ← component AABB). The open mirror question:
should the **contact's** size — `cross_section`, the value sensors report and
carry in `active_contacts[id].signature` — also be unified with that physical
geometry, or stay an independent authored scalar?

**What cross_section does today (two jobs, conflated):**
1. **Apparent sensor size** — what a sensor "returns" for the contact; fused/
   lerped across readings ([ship.gd:926](../scripts/ships/ship.gd:926)).
2. **Physical-size proxy for classification** — `cross_section < 10` → ORDNANCE
   ([ship.gd:72](../scripts/ships/ship.gd:72)).
It is authored per ship (frigate 50, destroyer 75, shuttle 40, attack craft 22,
buoy 10, missile 2) with **no link to the real component geometry** (frigate
~80×60, destroyer ~108×69). The numbers track real size only by hand-tuned
coincidence, and nothing stops them drifting arbitrarily.

### Options

**A — Keep separate (status quo).** AABB for physics/render; cross_section a free
authored sensor stat.
- + Max authorial freedom; stealth = author a low absolute; simplest.
- − The two drift with no guardrail; "what size do I draw a sensor-only contact
  at?" has no principled answer (cross_section and true AABB disagree).

**B — Fully unify** (cross_section *is* derived from geometry; no authored value).
- + One true size; apparent size always tracks reality; no drift.
- − **Kills the stealth lever** — apparent size can never differ from physical
  size, so "physically big but sensor-small" (stealth hull, cold asteroid
  station hiding) becomes impossible. Also forces a classification-threshold
  recalibration.

**C — Layered: true size + signature multiplier (recommended).**
- One **true physical dimension** from geometry (`get_bounding_radius()` / AABB).
- `cross_section` baseline = `f(true size)`, times a per-ship **signature/stealth
  multiplier** (default 1.0; <1 = stealth hull; >1 = big flat reflective slab).
- Sensors then report that baseline with **noise + resolution** error; the
  contact carries the *estimate*, not ground truth.
- + Apparent size is anchored to real size (no accidental drift) **and** the
  stealth lever survives — now a principled multiplier on truth instead of a
  disconnected absolute. The asteroid-station / stealth-hull archetypes live on
  as low multipliers.
- + Resolves rendering cleanly: close/visual → draw **true AABB/outline**;
  sensor-only → draw a blob sized by the **reported** cross_section (true ×
  stealth × noise). The gap between the blob and the real outline you see when
  you close in becomes a gameplay beat ("it read smaller than it was").
- − One-time recalibration of the cross_section scale + classification thresholds.

**Recommendation: C.** Unify the *baseline* with physical truth; keep a
multiplier so apparent ≠ physical stays an intentional lever, not an accident.

### The multiplier is the valuable part — one knob at three timescales
Anchoring the baseline to geometry is the cleanup; the **signature multiplier**
is what earns its keep, because the *same* knob is controllable at every
timescale:
- **Per ship class (static):** stealth hull < 1, ordinary = 1, big reflective
  slab / unshielded hauler > 1. The design-doc archetypes (sensor buoy / mine
  "run dark") become a low multiplier instead of a magic absolute.
- **Per instance, dynamically (runtime):** "run silent" trades a low multiplier
  for some capability (drop active sensors / throttle the reactor); taking
  damage or venting heat spikes it. This is the EM/heat event model (M2) and the
  signature knob, unified — they're the same idea (a runtime signature that
  diverges from baseline).
- **Decoys (deployables):** a cheap object that broadcasts a **high** multiplier
  to read as a big warship and draw fire / fragment a sensor picture. This is
  literally what `buoy.gd` already does by hand — it sets `base_heat`/`em_noise`
  to 50 specifically "so it looks like a ship to sensors." The unified model
  generalizes that one-off into a reusable mechanic: a decoy is just an entity
  with a tiny true size and a large signature multiplier.

This is also what makes the sensor game *lie well*: a contact reading as a
destroyer might be a decoy, and the only way to disambiguate is to close to
visual range (→ the outline-vs-blob reveal above) or cross-correlate sensors.
The signature multiplier becomes a first-class EW surface, not a static stat.

Design implication: `cross_section` (and its heat/EM siblings) should be a
**runtime** value = `baseline(geometry) × signature_multiplier(t)`, where the
multiplier is a field ships/decoys/EW can drive — not a frozen authored constant.

### The hard sub-decision: what is `f(true size)`?
A single scalar is lossy, and the **missile proves it**. Its AABB is long-and-
thin (~25×8); `bounding_radius` ≈ 15.5 would push it *over* the ordnance
threshold (10) and misclassify it as a vessel. Candidate baselines:
- bounding radius — simplest, but wrong for long/thin bodies (missile).
- smaller AABB dimension / projected width — better for slender hulls.
- **aspect-dependent projected silhouette** — cross_section depends on viewing
  angle (nose-on missile ≈ nothing; broadside ≈ its full length). This is the
  realistic model, it naturally fixes the missile (you almost always see it
  nose-on), and it ties directly into the "facing side" rendering idea and adds
  real tactics (present your nose to shrink your signature). But it's more model
  and more state per contact.

So unifying the contact dimension **does** make sense — at the *baseline* level —
but the right formula is bound up with whether we want **aspect-dependence**.
That's the real fork: a single anchored scalar (cheap, good enough, recalibrate
thresholds) vs an aspect-projected signature (richer, self-fixes the missile,
feeds facing-side rendering and nose-on tactics). Recommend shipping the scalar
baseline first (Option C with projected-width `f`), and treating aspect-dependence
as the natural follow-on once outline rendering and the facing-side cull exist.

## Decided path: v1 static fade-in, v2 sensor-dot outlines

Primary use case, decided: **close-range navigation** — running into something
you can't see is bad. Stations on a docking approach, rocks in a field, a tiny
shuttle crossing your bow. Differentiating a station from a shuttle at a finer
grain than the cross_section scalar is the point; combat-intel gating is
secondary and deferred to v2's mechanism.

### v1 — static true outline, distance-gated (build first)

Draw the contact's **actual component rects** (style 1 above), rotated to its
heading, alpha-faded by distance. No sensor honesty yet — ground truth, gated
only by range:

- `OUTLINE_FADE_START := 3000.0` — roughly the shortest laser range; begin
  fading in.
- `OUTLINE_FULL := 1500.0` — matches the existing `omni_collision` sensor range
  (frigate/destroyer carry one: 1500u, 8 bins, 0.1s), which is the in-fiction
  instrument for "I can see its shape now."
- Alpha = `1 - clamp((dist - FULL) / (START - FULL), 0, 1)`, on top of the
  zoom-LOD pixel threshold above (no point drawing an outline 2px wide).
- Stations use a much larger fade window (scale is the point — see above).

Info-leak note: yes, this reveals a hostile's true layout inside 3000u. At that
range you are *inside its laser envelope* — the fight is already at knife range
and the leak is moot. Acceptable for v1; v2 replaces the leak with an honest
mechanism rather than a gating policy.

### v1.1 — first-playtest revision (2026-07-04): silhouette, not x-ray

Playtest finding (Ironhold approach): v1's per-component rects on the nav map
read as an information leak and as clutter — the player sees the boxes around
every module of a station they've merely flown near. Component-level detail
belongs to the engineering panel; the tactical map wants a *footprint*.
Decisions:

1. **Silhouette only.** The close-range outline is the rectilinear union
   contour of the component rects (see "Silhouette LOD: beyond the convex
   hull" below — pulled forward from 'later LOD' to THE primary close-range
   shape). Holes (ring hulls) render as extra loops; they're rare and cheap.
   No per-component boxes on the nav map, for anyone, ever. v1.1 always uses
   the exact contour; the convex-hull/concavity-ratio auto-selection and step
   simplification stay future refinements.
2. **Contact color, not component colors.** The outline draws in
   `_get_contact_color()` (classification color × confidence fade) — the same
   color channel as the blip. The component-type color table leaves the nav
   panel.
3. **The outline REPLACES the bubble.** Blip/cross-section circle and outline
   crossfade: `blip_alpha = 1 − outline_alpha`. One footprint channel that
   refines as you close — never two shapes for one contact. "It should look
   like we refined our contact footprint, not gained some other knowledge."
4. **Pop-in distance is size-proportional** (angular-resolution model — you
   resolve shape when it subtends enough of your sensor's view):
   `fade_start = K_START × bounding_radius`, `full = K_FULL × radius`,
   K_START ≈ 50, K_FULL ≈ 25. Reproduces the old hand-picked constants
   (frigate ~54r → 2700/1350 vs old 3000/1500; medium station ~264r →
   13200/6600 vs old 12000/6000) while scaling continuously: a mine (~10r)
   resolves only at ~500, an asteroid station earlier than anything. Replaces
   the two-case ship/station switch. The zoom-LOD pixel floor stays.
5. Hostile sensor dots (v2 below) recolor to the contact color as well.
6. **Asteroids/simple bodies refine to a seeded rocky blob at their true
   bounding radius.** They have no component rects for the dot sampler, and a
   perfect circle reads as a UI artifact — so the refined footprint is a
   deterministic jagged polygon (seeded from the rock's quantized position,
   stable across bubble promote/demote; vertex radii 0.88–1.08× the real
   collision circle, so it errs toward over-warning). Same crossfade, contact
   color, tumbles with the body. Rock fields (the original close-navigation
   motivation) get honest collision extents that look like rocks. Dead ship
   hulks keep their rects and stay on the dots path.

Test impact: the panel's draw-list seams switch from per-component entries to
silhouette loops; `test_ship_geometry` item 6 and `test_sensor_dots`' no-leak
item assert the new seam (friendly = silhouette loops, hostile = dots only).
The silhouette helper (merge_polygons fold, cached per ship class) gets its
own unit battery: touching-rects union, plus-shape contour, ring-with-hole
loop count, cache behavior.

### v2 — sensor dots: the outline is measured, not given

Each active sensor already sweeps angular bins. Extend the sweep: for a contact
inside outline range, the bins that cover its angular subtense **raycast into
the target's actual component-rect silhouette** (ray–AABB slab test per rect in
the target's local frame; nearest entry point wins) and return a **surface
point at measured distance** instead of just a center-of-mass blip. Those dots
accumulate into a point cloud the nav panel renders — the outline is literally
built from sensor returns.

What this buys:
- **Outline quality = sensor quality, for free.** The 8-bin collision sensor
  paints ~8 blobby dots — enough to not hit the thing. The 3600-bin/0.1s
  fire-control sensor paints a crisp hull trace inside 5000u — fire control
  resolving fine shape is exactly the right fiction. A coarse 36-bin search
  dish contributes almost nothing. No hand-authored "detail level" policy; the
  existing bins/refresh/range stats *are* the policy.
- **Honest hostiles.** No layout leak: you know the shape only where your rays
  have touched it. A target showing you its nose keeps its broadside secret.
- Dots age and fade like contacts do (~1–2s), so a rotating or maneuvering
  target smears honestly instead of teleporting its outline.

Cost is bounded: only contacts within outline range (a handful), only on that
sensor's refresh tick, and only the bins subtending the target (a 60u-radius
ship at 3000u subtends ~2.3° ≈ 23 bins of a 3600-bin sensor, not all 3600).
The ray–rect math is the damage raymarch's geometry reused at coarser grain.

### Build order (revised — planned as M25/M26, see
`implementation_plans/m21_m27_shape_outline_roadmap.md`)

1. **M25:** `Ship.get_local_aabb()` / `get_bounding_radius()` (unchanged from
   above) — also fixes the bounds-ring/collision lies, which matter for the
   same "don't hit what you can't see" reason.
2. **M25:** v1 static outline pass in the nav panel, distance fade as spec'd.
3. **M25:** Repoint the nav bounds ring at derived geometry.
4. **M26:** v2 sensor-dot sweep extension + dot rendering; demote the v1
   static outline to friendlies/own-ship only (they datalink their true
   layout), hostiles get dots only.
5. Then, independently: silhouette LOD (see "Silhouette LOD: beyond the
   convex hull" below), facing-side cull, Option C signature work
   (unscheduled).

## Silhouette LOD: beyond the convex hull

(Status update: the v1.1 playtest revision above pulled this forward — the
union contour is now THE close-range shape, not a mid-range LOD. The shape
menu and auto-selection below remain the roadmap for refinements on top.)

The close-range outline wants ONE clean shape per ship instead of v1's
per-component rects. The original sketch said "convex hull" — that's wrong as a default,
because the hull-shape grammar's variety primitives (`hull_shape_grammar.md`
§2) ARE concavity: notch, arm, pod, hole. A convex hull erases exactly what
the grammar builds:

- Plus/X station → diamond blob (the four inner corners bridge over).
- Ring defence pod → solid square (the hole — the dock! — disappears).
- Spine+pods freighter → one fat slab (the gap between pods bridges).
- Asymmetric L → its notch, the thing that reads "industrial," fills in.

Convex hull is only faithful for compact box-ish hulls (frigate, shuttle,
LAC) — where it's also the cheapest and smoothest-looking choice. So: a menu,
not a single style, selected automatically.

### The shape menu

1. **AABB** — cheapest; the far-LOD box before dropping to a blip.
2. **Convex hull** — compact hulls only. Smooth, closed, reads "warship."
3. **Exact rectilinear union contour** — all component rects are axis-aligned,
   so their union's boundary is a rectilinear polygon (plus interior hole
   polygons). Godot has this built in: fold `Geometry2D.merge_polygons()`
   over the rects (Clipper-based). Exact, preserves every notch/arm/hole.
   Geometry is static per ship class → compute once, cache per script.
4. **Simplified contour (recommended mid-LOD default)** — take (3), merge
   collinear runs, and collapse boundary steps shorter than ~5u (the 2.5u
   fill shims etc.). The result looks like a naval recognition-manual
   silhouette: keeps the plus-shape, drops the pixel noise.
5. **Marching-squares / bitmap trace** — rasterize rects to a coarse grid and
   trace. Chunkier look; keep only as a fallback if (3) hits polygon-merge
   robustness issues with edge-touching rects (inflate rects by ~0.01 before
   merging first — coincident edges are the common case here).
6. **Concave hull / alpha shapes** — rejected: approximate and tuning-fiddly
   when the exact union is available for free.

### Auto-selection (measure, don't author)

`concavity_ratio = area(convex_hull) / area(rect_union)`.
- ratio < ~1.15 AND the union has no holes → **convex hull** (style 2).
- otherwise → **simplified contour** (style 4).

Frigate/LAC/shuttle land at ~1.0 → smooth convex silhouettes. The plus
station lands near ~2 → stepped contour. A ring's hole forces contour
regardless. One tunable threshold const; a per-ship override field is
possible but shouldn't be needed. Using both styles IS the variety payoff:
compact warships read as smooth closed shapes, stations and industrial hulls
read as stepped machinery — at a glance, before any label.

### LOD chain (consolidated)

hostile: sensor dots (M26) → reported-cross-section blob (far).
friendly/own: per-component rects (close, v1) → convex-hull-or-contour
silhouette (mid, auto-selected) → AABB box → blip.

### Implementation notes

- Cache the computed silhouette per ship class (keyed by script path or a
  static on the class); never per frame, never per instance.
- `merge_polygons` returns hole polygons alongside the outer boundary — draw
  holes as separate inner polylines (the defence pod's dock ring).
- Simplification is axis-aligned-aware: only collapse steps, never introduce
  diagonals — the rectilinear look is the art style, not a limitation.

### Open decisions (silhouette LOD)

- Step-collapse threshold (~5u?) and the concavity-ratio threshold (~1.15?) —
  tune with real ships once M27's concave hulls exist (they're the test set).
- Whether the mid-LOD silhouette ever renders for hostiles (sensor-gated), or
  stays friendly/own-only with dots covering hostiles at all ranges.

## Open decisions
- ~~Per-component rects vs silhouette as the default close-range style~~ —
  **decided: per-component rects** (v1), sensor dots (v2).
- ~~How much of a hostile's outline sensor resolution should reveal~~ —
  **decided: v2's dots make this mechanical** (you see where your rays landed),
  no separate gating policy needed.
- ~~Whether collision becomes non-circular~~ — **planned** as
  `implementation_plans/m28_m30_collision_roadmap.md` (M28 kinetic damage →
  M29 convex hulls → M30 decomposed concave, holes ignored).
  Findings (2026-07-04): Godot's broadphase already makes polygon collision
  "progressive" for free (AABB cull first, exact narrowphase only for
  near-contact pairs), so at bubble-scale live counts there is no perf case
  for keeping circles on concave hulls. Recommended shape policy: always-on
  `CollisionPolygon2D` from the cached ShipSilhouette loops (engine
  auto-decomposes to convex; plus-station ≈ 3 pieces, ring ≈ 4) for
  stations / defence pod / freighter — the hulls whose circumscribed circle
  visibly lies (notches, ring hole, pod gap); keep circles for compact ships
  and rocks (a rock's circle IS its truth). A manual proximity-LOD (sentinel
  Area2D toggling `CollisionShape2D.disabled`, swap BEFORE contact at ~1.5×
  combined radii, never revert while anything is inside the circle — the
  fatten-around-occupant case ejects violently) is documented but deferred
  until profiling ever demands it.
- Contact dimension: scalar anchored baseline (Option C) now vs aspect-dependent
  signature later — and which `f(true size)` formula keeps the missile "ordnance."
- v2: do dots persist per-contact in the fusion store (alongside the existing
  contact fields) or in a separate render-side cache keyed by instance id?
