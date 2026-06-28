---
name: ship-design
description: >
  Design and author ship component layouts for Project Deep Space.
  Use when creating new ship classes, modifying existing ship layouts,
  fixing validation errors, or rebalancing ship component geometry.
  Covers coordinate system, Rect2 placement rules, the validator,
  mass/inertia formulas, damage model implications, and tier band constraints.
---

# Ship Design Skill

## Project Context

- **Stack**: Godot 4.x + GDScript
- **Key files**:
  - Ship base: `scripts/ships/ship.gd`
  - Validator: `scripts/components/ship_design_validator.gd`
  - Spec bands: `scripts/components/component_spec.gd`
  - Ship designs: `scripts/ships/{frigate,destroyer,light_attack_craft,cargo_shuttle,sensor_drone,missile}.gd`
  - Catalog: `scripts/ship_catalog.gd`
  - Engineering renderer: `scripts/panels/engineering_panel.gd` (inner class `ComponentSpatialView`)
  - Tests: `scripts/tests/test_ship_designs.gd`

---

## 1. Coordinate System

All component rects are defined relative to the ship's center `(0, 0)`:

- **+X = Forward** (bow)
- **-X = Aft** (stern)
- **+Y = Starboard** (right when facing forward)
- **-Y = Port** (left when facing forward)

`Rect2(px, py, w, h)` defines a box from `(px, py)` to `(px + w, py + h)`.

> [!IMPORTANT]
> The engineering panel renders with a 90° rotation: X maps to screen-vertical (up = forward), Y maps to screen-horizontal (right = starboard). Keep this in mind when visualizing layouts.

---

## 2. Component Dictionary Schema

Every component is a Dictionary with at minimum:

```gdscript
{
  "id": String,          # Unique within the ship
  "type": String,        # hull | reactor | engines | sensors | weapons | comms
  "rect": Rect2,         # Spatial footprint
  "health": float,       # Current health (set = max_health at init)
  "max_health": float,   # Maximum health (> 0)
  "density": float,      # Mass density (always 20.0 by convention)
}
```

Type-specific required fields:
- **reactor**: `power_rating` (float > 0)
- **engines**: `thrust_rating` (float > 0), `torque_rating`, `power_rating`
- **sensors**: `sensor_type`, `range`, `arc_width`, `num_bins`, `refresh_interval`, `heading`
- **weapons**: `weapon_type` (`laser` | `missile`), `ammo`, `cooldown_max`, `range`, `heading`, `arc_width`
- **comms**: `range`

---

## 3. Layout Rules (Enforced by Validator)

### 3a. No Overlap Between Any Components

No two components may have `Rect2`s that intersect (excluding touching edges). This applies to **all** component types — hull, reactor, sensors, weapons, everything.

- **Touching edges (shared border) is fine** and is required for connectivity.
- **Overlapping area is never allowed**, even hull-on-hull.
- Use separate adjacent segments instead of overlapping layers.

### 3b. Full Connectivity (No Floating Parts)

Every component must be reachable from every other component via a chain of touching/overlapping rects. The validator does a BFS flood-fill from component 0; any unreachable component is flagged as a disconnected error.

**Design approach**: Start with hull segments that form a connected frame, then attach everything else to hull edges.

### 3c. Structural Requirements

- At least one `hull` component
- At least one `reactor` with `power_rating > 0`
- At least one `engines` component (unless `STRUCTURE` tier)
- At least one `sensors` component
- All `id` values unique

---

## 4. Layout Design Philosophy

The core principle is **hull coverage**: weapons, sensors, and other fragile components should sit **inside** the hull envelope wherever possible. The hull absorbs incoming damage via ray-marching — a weapon that extends beyond the hull silhouette has no armor protecting it from that direction.

### 4a. Hull-First Design

Design the hull as a solid outline that **encloses** weapons and sensors, not as a core that weapons stick out of.

**GOOD** — weapons enclosed by hull above and below:
```
HHHHHHHHH
WWWHWWWH
HHHHHHHHH
```

**GOOD** — asymmetric but still covered:
```
HHHHHH
WWWHH
HHWWW
HHHHHH
```

**ACCEPTABLE** — small indentations, mostly covered:
```
_HHHHH_
WWWHH_
_HHWWW
_HHHHH_
```

**BAD** — weapons extending far beyond hull (current problem):
```
___HHH___HHH___
WWWHHH___HHHWWW
___HHH___HHH___
```

The hull outline should extend to cover the weapons' port/starboard extents. Think of the hull as the ship's skin — everything else is inside it.

### 4b. Redundant Components Must Be Physically Separated

The purpose of redundancy (e.g., dual reactors) is **damage tolerance**. If both redundant components are next to each other, a single hit that penetrates one will likely damage the other.

**BAD** — dual reactors side-by-side in one box:
```
┌──────────────┐
│ R_fwd │ R_aft │  ← one hit damages both
└──────────────┘
```

**GOOD** — dual reactors in separate armored boxes, physically separated:
```
┌───────┐         ┌───────┐
│ R_fwd │  (gap)  │ R_aft │
└───────┘         └───────┘
```

Place hull, weapons, or other components between redundant systems so a damage ray must pass through multiple unrelated components before reaching the second reactor.

### 4c. Sensors

- **Omnidirectional sensors** (TAU arc): can sit anywhere inside the hull — they don't need line of sight.
- **Directional sensors** (narrow arc): should sit on the hull surface at the relevant facing. They can be **flush** with the hull edge — they don't need to protrude. A small 1–2 unit bump past the hull is acceptable but large extensions are not.
- **Fire-control sensors** (hi-res, fast refresh): protect these inside hull when possible since losing fire-control cripples PD.

### 4d. Engines

Engines must sit at the stern (lowest X). They **must** extend slightly past hull_aft since they need exhaust clearance. This is the one acceptable protrusion — keep it minimal (the engine's aft face extends past hull, but the engine body overlaps with/touches hull_aft).
### 4e. Active Surfaces (Soft Rule)

Every component has a functional face — its **active surface** — that should not be covered by hull or other components. This is a guideline, not a hard validator rule: exceptions can make sense, but there should be logical consistency in why a surface is or isn't exposed.

| Component Type | Active Surface | Guideline |
|---|---|---|
| **Engines** | Aft face (-X) | Exhaust must point into open space. The aft edge of the engine should be the ship's aftmost feature on that axis. |
| **Forward weapons** | Forward face (+X) | Barrel/tube exit needs a clear line outward. The weapon's forward edge should reach the hull's forward edge or sit just inside it. |
| **Broadside weapons** | Outboard face (±Y) | Tubes fire outward. The weapon's port/starboard edge should be near the hull's outer edge on that side. |
| **Directional sensors** | The face in the sensor's `heading` direction | The sensor dish needs line-of-sight. Place it so its sensing face is at or near the hull surface. |
| **Omni sensors** | None — 360° coverage | Can be fully enclosed. |
| **Comms** | None required | Can be fully enclosed by hull. |
| **Reactors** | None — internal | Should be as deep inside the hull as possible. |

**Example — forward weapons placement:**
```
  Hull envelope:
  HHHHHHHHHH
  HHHWWWWW→H    ← weapon's active face (+X) at hull's forward edge
  HHHHHHHHHH
```
The weapon's forward edge is flush with or 1–2 units inside the hull's forward edge. Hull covers the weapon's sides and rear. The active face (→) points outward.

**Example — broadside tubes:**
```
  HHHH
  HHHH
  HWWW→    ← tube's active face points outboard (toward hull outer edge)
  HHHH
  HHHH
```
The tube's outboard edge sits at the hull's outer Y boundary. Hull covers above, below, and inboard.

### 4f. Step-by-Step Layout Process

1. **Determine the size** based on the tier's target mass and density (Area = Mass / (Density * MASS_SCALE)).
2. **Place weapons and sensors** first. Position weapons so their active surfaces point outward, and group sensors/comms logically.
3. **Place internal systems** (reactors, engines). Ensure redundant systems (e.g., dual reactors) are physically separated from each other.
4. **Fill the gaps with hull boxes**. Wrap the hull around the components to enclose them fully (except active surfaces), creating the ship's skin and internal bulkheads. Ensure full connectivity.
5. **Verify** no overlaps, full connectivity, active surfaces exposed, and visual coverage in the engineering panel.

### 4g. Hull Frame Patterns

**Simple frame** (frigate, LAC):
```
  ┌──────────┐
  │ hull_fwd │      ← covers weapons and sensors inside
  ├──────┬───┤
  │ port │stb│      ← center gap for reactor/comms/sensors
  ├──────┴───┤
  │ hull_aft │
  └──────────┘
```

**Wide frame** (destroyer — hull extends to cover broadside weapons):
```
  ┌────────────────────┐
  │     hull_fwd       │
  ├──────┬─────┬───────┤
  │      │ gap │       │
  │ port │     │ stbd  │  ← wide enough to enclose broadside tubes
  │      │     │       │
  ├──────┴─────┴───────┤
  │     hull_aft       │
  └────────────────────┘

**Tapered Frame** (avoiding perfect rectangles):
```
  _┌────────┐_
  ┌┴────────┴┐
  │ mid_hull │  ← corners stepped in to create a natural ship shape
  └┬────────┬┘
  _└────────┘_
```
Avoid designing ships as perfect rectangular "buildings in space." Pull in the extreme corner blocks of the bow and stern to create a stepped or tapered profile, which adds visual interest and avoids a blocky appearance.
```

---

## 5. Mass & Inertia Formulas

Mass and inertia are **derived from rect geometry**, not authored directly:

```
mass_component = rect.size.x * rect.size.y * density * MASS_SCALE
MASS_SCALE = 100.0 / 55500.0  (≈ 0.0018)

inertia_component = mass_component * centroid.length_squared()
INERTIA_SCALE = 1000.0 / 40422.30
```

> [!WARNING]
> **Rect area directly affects ship mass.** Larger rects = heavier ship = slower acceleration. When fixing overlaps by spreading components out, the total rect area (and thus mass) stays the same, but inertia changes because centroid distances change. Components further from center increase rotational inertia (slower turning).

### Mass Budget Implications

| Tier | Target Mass | Target Accel |
|------|-------------|--------------|
| DRONE | ~5–15 | ~60–120 |
| LIGHT | ~15–40 | ~25–110 |
| MEDIUM | ~80–120 | ~40–60 |
| HEAVY | ~150–250 | ~25–35 |

`accel = thrust_rating / mass`

---

## 6. Damage Model Implications

The damage system uses **ray-marching** through component rects in local space:

1. A damage ray enters the ship from the hit direction
2. It steps through local space in `DAMAGE_RAYMARCH_STEP` increments
3. At each step, it checks which component rects contain the current position
4. Each component absorbs damage proportional to `effective_density * step_size`
5. Remaining damage continues deeper into the ship

**Design implications:**

- **Hull on the outside** absorbs damage first, protecting internals
- **Overlapping rects double-absorb** — a ray passing through two overlapping components damages both per step (undesirable for non-hull; intentional for hull armor layers)
- **Gaps between components** let damage rays pass through unimpeded
- **Reactors deep inside** are protected by hull + other components in the ray path
- **Engines at the stern** are exposed from behind

---

## 7. Tier Band Constraints (Warnings, Not Errors)

These are from `component_spec.gd`. Values outside bands produce warnings:

### Hull Health per Segment
| Tier | Min | Max |
|------|-----|-----|
| DRONE | 10 | 300 |
| LIGHT | 80 | 600 |
| MEDIUM | 400 | 1500 |
| HEAVY | 1000 | 5000 |

### Engine Ratings
| Tier | Thrust Min–Max | Torque Min–Max |
|------|---------------|----------------|
| DRONE | 300–3000 | 600–6000 |
| LIGHT | 2000–7000 | 4000–14000 |
| MEDIUM | 4000–12000 | 8000–24000 |
| HEAVY | 10000–32000 | 20000–64000 |

### Handling (Ship-Level)
| Tier | Speed Min–Max | Omega Min–Max |
|------|--------------|---------------|
| DRONE | 0–200 | 0–3.0 |
| LIGHT | 1000–3000 | 2.0–6.0 |
| MEDIUM | 600–1400 | 1.2–3.0 |
| HEAVY | 300–900 | 0.6–1.8 |

### Laser Weapon Stats
| Tier | Damage Min–Max | Range Min–Max |
|------|---------------|---------------|
| DRONE | 50–300 | 1000–4000 |
| LIGHT | 100–600 | 2000–6000 |
| MEDIUM | 300–1200 | 3000–8000 |
| HEAVY | 800–4000 | 4000–12000 |

### Reactor Power Rating
| Tier | Min | Max |
|------|-----|-----|
| DRONE | 10 | 80 |
| LIGHT | 40 | 160 |
| MEDIUM | 80 | 300 |
| HEAVY | 250 | 900 |

---

## 8. Validation Checklist

Before committing a ship design, verify:

- [ ] All component `id` values are unique
- [ ] **No rects overlap at all** (use `Rect2.intersects(other, false)` to check — applies to ALL types including hull)
- [ ] All components form a connected graph (every rect touches at least one neighbor)
- [ ] Hull segments form a connected frame that **encloses** weapons and sensors
- [ ] Weapons and sensors sit **inside** the hull envelope (not protruding beyond hull edges)
- [ ] Redundant components (dual reactors) are **physically separated** with other components between them
- [ ] Required components present: hull, reactor, engines (if mobile), sensors
- [ ] Health, power_rating, thrust_rating, damage, range are within tier bands
- [ ] max_speed and max_omega are within handling bands
- [ ] Run `.\build.ps1` and check for zero error-severity violations
- [ ] Review the engineering panel visually in-game for clean layout

---

## 9. Common Mistakes

1. **Weapons extending beyond hull** — The #1 mistake. Weapons should sit inside hull coverage, not stick out like antennae. Widen the hull to enclose them, or move weapons inward.

2. **Redundant reactors in the same box** — Defeats the purpose of redundancy. Separate them with hull or weapons between so a single damage ray can't hit both.

3. **Hull segments overlapping each other** — Even hull-on-hull overlap is now an error. Use adjacent segments that share edges, not overlapping slabs.

4. **Sensors protruding far past hull** — Directional sensors can sit flush with the hull surface. A 1–2 unit bump is fine; a 10-unit antenna is not.

5. **Engine overlapping hull_aft** — The engine should touch hull_aft at a shared edge, not sit inside it. Place engine at hull_aft's aft edge (lowest X).

6. **Internal components overlapping hull walls** — When hull uses a 4-wall box pattern, internals must fit inside the cavity, not overlap the walls. Double-check Y coordinates against hull_port/hull_stbd inner edges.

7. **Identical rects for different components** — e.g., comms and a sensor at the exact same position. Tile them as adjacent cells.

8. **Broadside weapons wider than hull** — If you want broadside tubes, the hull port/stbd walls must extend far enough (in Y) to cover them. Don't hang tubes off hull edges into empty space.

---

## 10. Ship Catalog Registration

After creating a ship class:

1. Add its scene/script path to `ShipCatalog.SPAWNABLE` in `scripts/ship_catalog.gd`
2. The ship select dropdown and spawn director automatically pick it up
3. Add a test case in `scripts/tests/test_ship_designs.gd`
