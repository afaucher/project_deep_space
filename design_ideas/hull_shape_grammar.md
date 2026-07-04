# Hull shape grammar — more shape variety without more testing

Status: design. Companion to `.agents/skills/ship-design/SKILL.md` (authoring
rules) and `ship_outline_rendering.md` (what makes shape *visible*). These two
features feed each other: outlines only pay off if ships have distinct shapes;
shapes only pay off once the player can see them.

## 1. Where we are — the shape inventory

| Ship | Shape today | How it was authored |
|------|-------------|---------------------|
| Frigate | Box frame, weapons hung *outside* the walls as sponsons | Raw rects; predates the skill's hull-coverage rule (it's the skill's "BAD" example) |
| LAC | Winged dart — two wing slabs + nose | Raw rects + 2.5-unit fill shims |
| Cargo shuttle | Small box, stepped nose | Frigate template, shrunk |
| Destroyer | Spine + "zipper" flanks (alternating hull/weapon cells), stepped bow/stern | Raw rects, ~50 dicts, the most shape-conscious design we have |
| Small/medium station | Plus/X — core + 4 arms with caps and flanks | One arm's worth of geometry, hand-stamped 4 times with rotated coordinates |

Two observations fall out of reading these side by side:

1. **The idioms already exist — they're just unnamed and hand-expanded.**
   Frame walls, caps + flanks, mirrored port/stbd pairs, the destroyer zipper,
   reactor armor boxes, fill shims. The station X-shape is literally "author one
   arm, stamp it 4 times" done by hand with rotated Rect2 math. Every new ship
   re-derives these by copy-paste, and 50–70% of each file is hull plumbing that
   exists only to satisfy enclosure + connectivity.
2. **The validator checks correctness, not shape.** Overlap, connectivity,
   bands — all shape-agnostic. Shape variance is *free* at the validation layer.
   What it costs today is (a) authoring effort and (b) the human-eyeball steps in
   the skill's checklist (hull coverage, active surfaces), which don't scale.

So the bottleneck to "lots more shapes" is not the engine or the validator —
it's authoring cost and the manual review steps. The plan attacks both.

## 2. Shape archetypes (what variance looks like in axis-aligned rects)

With Rect2-only geometry, shape = the silhouette's step profile. The primitive
moves are: **taper** (step widths along the spine), **notch** (cutout), **arm**
(purposeful protrusion), **pod** (outboard mass joined by a strut), **hole**
(interior gap — damage rays pass through gaps, so a hole is a real weak point,
which for a ring station is flavor, not a bug).

Archetype library, mapped to the unbuilt catalog (`ship_designs.md`):

| Archetype | Silhouette | Fits | Why the shape is the role |
|-----------|-----------|------|---------------------------|
| Box / monohull | stepped rectangle | frigate (today), shuttle | compact = low inertia for its mass |
| Tapered dart | bow narrower than midship | **pinnace**, LAC | reads fast; small frontal aspect |
| Spine + pods | thin spine, fat outboard boxes | **freighter** | cargo pods ARE the silhouette; high inertia = ponderous handling for free |
| Zipper flank | alternating hull/weapon cells | destroyer (today) | broadside density visible from the side |
| Plus / X | core + radial arms | stations (today), **mine** (tiny 5-rect plus) | omnidirectional role, no facing |
| Ring | hollow square annulus | **system defence pod** | all-around PD arcs; the hole is the dock |
| Asymmetric L | spine + one outboard pod | tugs, industrial | instantly non-military at a glance |
| Cluster | irregular dense-rect blob, modules embedded | **asteroid station** | high-density rock rects double as armor *and* the reads-as-asteroid classifier |

Shape is also a *balance* knob, not just cosmetics: mass = total area, but
inertia = area **distribution**. Same-area layouts are handling-neutral in
accel and different in turn rate — a spine+pods freighter turns like a barge at
the same mass a box turns briskly. That's the physical grounding: silhouette
choices have consequences the sim already models.

## 3. Part variants — spec × volume marks

Today every component dict is hand-tuned within the spec bands. The bands
(`component_spec.gd`) already define what "legal" means; variants just name
points inside them, and — the key idea — **tie the stat point to a footprint**:

```
laser @ LIGHT tier:
  compact   4×4 rect   dmg 150  range 2500   (band floor-ish)
  standard  5×5 rect   dmg 250  range 3000   (band mid — what LAC has)
  heavy     5×8 rect   dmg 450  range 4500   (band ceiling-ish)
```

A better laser takes more volume → more mass → more hull to wrap it → slower
ship. The grounded tradeoff emerges from geometry we already simulate; no new
balance system. Same pattern for engines (thrust marks at growing rects),
sensors (bins/refresh marks), reactors. Hull gets **density** marks instead
(civilian d=15 / standard d=20 / armored d=35) — mass and damage-soak scale
together, and the classifier's density>250 asteroid line stays clear; the
asteroid station's rock shell is just an extreme hull mark.

Mechanically: `scripts/components/parts_catalog.gd`, static factories that
return plain component dicts:

```gdscript
Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD,
           Vector2(10, -7.5), heading, {"id": "hp_fwd_laser"})
```

Runtime doesn't change at all — ships still end up as arrays of dicts;
`Ship._ready()` normalization, the validator, and the renderer are untouched.

**Why this collapses testing:** a part from the catalog is in-band *by
construction*. One catalog test loops every part × tier × mark against the
bands — milliseconds, written once. Per-ship stat auditing stops being a thing;
per-ship validation narrows to geometry, which is the part that actually varies.

## 4. Layout builders — the grammar ops

`scripts/components/hull_builder.gd`, pure functions returning dict arrays:

- `frame(rect, thickness, hp)` → 4 wall segments (every box ship's opener)
- `taper(x0, x1, widths)` → stepped bow/stern profile
- `arm(dir, length, width, hp)` → station arm with cap + flanks
- `armor_box(inner_rect, thickness, hp)` → wrap a reactor (destroyer idiom)
- `zipper(x0, x1, cell_w, cells)` → alternating hull/weapon flank
- `mirror_y(comps)` → port⇄stbd: rect `(x, -y-h, w, h)`, heading negated,
  id suffix swapped. Half the frigate's weapon block is hand-mirrored today;
  this halves authoring and eliminates asymmetric-typo bugs.
- `rotate_90(comps, n)` → radial stamp; the station X becomes
  `core + rotate_90(arm(...), n)` for n in 0..3.

An authored ship becomes ~30 lines of composition instead of ~200 lines of raw
dicts, and the interesting decisions (silhouette, where the guns face, what's
armored) are the *only* lines left.

## 5. Delta variants — the "pirate LAC" problem

Most wanted variety isn't new hulls, it's skins of existing hulls: pirate LAC
(stripped armor, hotter engine), ore shuttle (same box, different flavor),
militia frigate (fewer tubes). Pattern:

```gdscript
static func pirate_lac() -> Array:
    return Variants.apply(LightAttackCraft, [
        {"swap": "engine_main", "part": ["engine", Tier.LIGHT, Mark.HEAVY]},
        {"remove": "hull_fwd_port"},
        {"tune": "hp_fwd_laser", "field": "cooldown_max", "value": 0.6},
    ])
```

The scaling rule that keeps testing sane: **classify deltas by whether they
touch geometry.**
- Same-footprint swaps and stat tunes → geometry-safe by construction; the
  catalog test already proved the stats legal. No new test burden.
- Deltas that add/remove/resize rects → rerun the validator (fast) like any
  ship.

## 6. Mechanize the eyeball checks

The skill's two human-only checklist items become validator **warnings**, so
shape experiments stay safe without a human review per design:

1. **Hull-coverage check** — for each weapon/sensor, cast a short ray outward
   from each non-active face; if it exits the ship AABB without crossing another
   component, flag "exposed face". (Reuses the damage-raymarch geometry — an
   exposed face is precisely one a damage ray reaches first.)
2. **Active-surface check** — the face in the component's `heading` direction
   must reach the AABB edge *without* crossing another component, else flag
   "masked weapon/sensor".

Warnings, not errors — deliberate low-armor designs stay legal (the frigate's
sponsons will flag; that's honest, and we decide per-ship to re-wrap or accept).
These two checks are what let a future "generate me 10 silhouettes" workflow
run without 10 engineering-panel eyeball sessions.

## 7. What scales how (the testing story)

| Layer | Cost today | Cost after |
|-------|-----------|------------|
| Stat legality | hand-checked per component per ship | one catalog test, O(parts), written once |
| Geometry legality | validator per ship (fast) — keep | same, auto-enumerated over catalog + variants |
| Coverage/exposure | human eyeball in engineering panel | validator warnings (§6) |
| Balance | >30 min tactical sweeps | **archetype promotion rule**: only a new *role* enters the sweeps (new tier, new weapon-class mix, accel band shift >~20%). Skins inherit their archetype's verdict. |

The promotion rule is the important one: without it, every pirate repaint
re-litigates a 30-minute sim. With it, sweep count tracks *roles* (a handful)
instead of *hulls* (dozens).

## 8. Phased plan

Now planned as milestones M21–M24 + M27 — see
`implementation_plans/m21_m27_shape_outline_roadmap.md` for the dependency DAG,
execution model, and per-milestone test plans.

- **A = M21 — Parts catalog.** `parts_catalog.gd` + `test_parts_catalog`. No
  ship edits yet. (Small, pure, immediately useful.)
- **B = M22 — Hull builders.** `hull_builder.gd` with frame/mirror/rotate first
  (the three with instant payback). Prove by re-expressing ONE ship (LAC or
  shuttle) and asserting identical validator result + mass + AABB vs. the
  hand-authored original. (Note: the existing stations are mirror-symmetric,
  not rotation-symmetric — their shells are the `mirror_x`/`mirror_y`
  showcase; `rotate_90` is for future radial designs.)
- **C = M23 — Mechanized checks.** Coverage + active-surface warnings in the
  validator; triage existing ships' flags (frigate sponsons: accept or re-wrap).
- **D = M24 — Delta variants.** `Variants.apply` + 2–3 real variants (pirate
  LAC, ore shuttle), auto-enumerated into `test_ship_designs`.
- **E = M27 — The unbuilt catalog.** Freighter (spine+pods), pinnace (tapered
  dart), mine (5-rect plus), defence pod (ring), asteroid station (cluster) —
  each authored *in* the grammar, which is the real proof it works. Campaign
  traffic (M20) gets visibly diverse silhouettes as the payoff.

Each phase lands independently; M21/M22/M23 have no gameplay risk at all (pure
authoring/validation tooling). The outline work is the independent M25/M26
chain (see `ship_outline_rendering.md`).

## 9. Open decisions

Friction found by M22's re-expression proof (the feedback loop working as
intended):
- The 5 sensor sub-kinds don't cover a wide-arc forward fire-control sensor
  (LAC's `omni_fwd_fc`, arc PI/1.5) — expressible only via raw opts overrides.
  Decide: add a 6th kind (`fwd_fc`?) or bless overrides as the escape hatch.
- `health_per_area` under-healths tiny hull shims (5×2.5 fill pieces land
  below the LIGHT band floor; the fleet authors a flat 80). The band floor is
  effectively a per-piece minimum — consider `max(band_floor, area × hpa)` in
  the hull mark, or a `min_health` field.

- Marks: three named marks (compact/standard/heavy) vs. a continuous size↔spec
  formula. Start with named marks — a formula invites false precision before we
  have enough parts to fit one.
- Footprint scaling rule: eyeballed per part family for now; revisit
  `area ∝ stat` once the catalog has enough entries to see a pattern.
- Whether phase E's asteroid station needs a `density` band added to the spec
  chart (rock shell d≫20) or stays validator-exempt like ordnance.
- Do builders live as static funcs (like `ComponentSpec`) or a RefCounted with
  chaining? Static funcs, per repo convention, unless composition gets awkward.
