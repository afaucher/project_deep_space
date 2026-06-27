# Close-range ship outline rendering & geometry consistency

Status: design exploration. No implementation yet.

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

- The world is a top-down zoomable tactical map ([navigation_panel.gd](../scripts/panels/navigation_panel.gd),
  world→screen transform, zoom 0.01–2.0).
- Ships are `RigidBody2D`s built from **component rects** (the loadout in each
  ship class). Those rects ARE the true geometry — position + size in ship-local
  space, forward = +X.
- Component rects already partially flow to the client: the nav panel reads each
  weapon's `rect` to draw firing arcs ([navigation_panel.gd:233](../scripts/panels/navigation_panel.gd:233)).
  So at least some rect data crosses the wire today; full-loadout availability
  for arbitrary contacts needs confirming/extending.

## The geometry-consistency problem (answers "do bounds map to dimensions?")

There are **four different notions of a ship's "size," and they don't agree:**

| Notion | Source | Value | Derived from real geometry? |
|--------|--------|-------|------------------------------|
| Component AABB | `_cached_bbox_min/max` ([ship.gd:461](../scripts/ships/ship.gd:461)) | per-ship, from rects | **Yes** — but used only for the damage raymarch |
| Collision circle | `SHIP_COLLISION_RADIUS` ([ship.gd:601](../scripts/ships/ship.gd:601)) | **flat 50** for every ship | No |
| Nav "physical bounds" ring | hardcoded `draw_arc(pos, 50.0, ...)` ([navigation_panel.gd:223](../scripts/panels/navigation_panel.gd:223)) | **literal 50** | No |
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
2. **Hull silhouette** — one outline polygon = convex hull (or just the AABB) of
   the component rects. Cleaner, reads as a ship shape, less busy. Good for
   farther/zoomed-out LOD.
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
  conveys facing, which the existing rotation indicator ([navigation_panel.gd:218](../scripts/panels/navigation_panel.gd:218))
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

## Open decisions
- Per-component rects vs silhouette as the *default* close-range style.
- Whether collision becomes non-circular now or stays a (size-correct) circle.
- How much of a hostile's outline sensor resolution should reveal.
- Contact dimension: scalar anchored baseline (Option C) now vs aspect-dependent
  signature later — and which `f(true size)` formula keeps the missile "ordnance."
