# Ship parameter sanity table (M9c working doc)

Purpose: eyeball the *controlling* parameters across current + planned ships
before committing M9c loadouts. Not a validator/band exercise — a pattern check.

Derived-mass shortcut: every ship component is density 20, and
`MASS_SCALE = 100/55500`, so **mass ≈ total_rect_area × 0.036**. The knob that
actually makes a ship feel fast vs sluggish is **accel = thrust ÷ mass** (and
**ang_accel = torque ÷ inertia** for turn snappiness). `max_speed`/`max_omega`
are independent *caps* on top of that.

## Current ships (real authored values)

| Ship | Tier | Mass | Hull HP | Reactor pwr | Thrust | accel (T/m) | max_speed | max_omega | Weapons | Sensors (max range) | Comms |
|------|------|------|---------|-------------|--------|-------------|-----------|-----------|---------|---------------------|-------|
| Frigate | T2 MED | 100 | 4000 (4×1000) | 100 | 5000 | **50** | 1000 | 2.0 | 6× laser (500/4k), 7× missile tube (28k) | 5 (80k) | 30k |
| SensorDrone | — | 22.5 | 200 | 100 | 0 | **0** | 0 | 2.0 | none | 1 (40k) | 50k |
| Missile | T0 (ordnance) | 6.0 | 50 (20+30) | 10 | 2991 | **499** | 3000 | 10.0 | warhead (laser, 250) | 1 seeker (30k) | — |
| Buoy | — | 50 (flat) | 100 | — | 0 | **0** | 0 | — | passive only | relay |

## Planned ships (DRAFT — proposed targets to sanity-check)

| Ship | Tier | Mass | Hull HP | Reactor pwr | Thrust | accel (T/m) | max_speed | max_omega | Weapons | Sensors | Comms |
|------|------|------|---------|-------------|--------|-------------|-----------|-----------|---------|---------|-------|
| Cargo Shuttle | T1 LIGHT | ~30 | ~250 | 50 | ~1000 | **~33** | 700 | 2.0 | none | 1 (20k) | 20k |
| Light Attack Craft | T1 LIGHT | ~12 | ~120 | 55 | ~1500 | **~125** | 2200 | 4.0 | 1 laser (250/3k), 1 missile (12k) | 1–2 (25k) | 20k |
| Destroyer | T3 HEAVY | ~220 | ~7000 | ~500 (dual) | ~5500 | **~25** | 700 | 1.2 | 5× laser, 10× missile tube (28k+) | 6 (80k+) | 60k |

## Patterns worth noting

1. **accel is the spine.** The proposed accel column reads
   missile 499 ≫ attack-craft 125 > frigate 50 > shuttle 33 > destroyer 25 >
   drones 0. That's the intended "small/combat = darty, big/hauler = ponderous"
   gradient, and it's set by the **thrust:mass ratio**, not thrust alone.

2. **You cannot share one engine across hulls.** Drop the frigate engine
   (thrust 5000) onto a mass-12 attack craft and accel = 417 — uncontrollable.
   So "engines identical today" only holds when masses are close; across tiers,
   thrust must scale ~with mass to keep accel in a sane band. The attack craft
   getting a *proportionally larger* engine is the mechanism for its high accel
   at low mass — exactly the within-band variation that separates it from the
   same-size-but-slow shuttle.

3. **Same-size, different speed = caps + thrust, not size.** Shuttle and attack
   craft are both LIGHT/T1, but shuttle max_speed 700 / accel 33 vs attack craft
   max_speed 2200 / accel 125. Pure within-tier role variation — no band change
   needed.

4. **Concern — destroyer must out-armor the frigate, and the frigate is already
   tanky.** Frigate hull is 4000 (4×1000). "Moderate armor" destroyer has to
   clear that with margin → ~7000 proposed. Watch that the frigate's hull HP
   isn't already over-set relative to where we want the tier ladder to sit.

5. **Concern — the M9b LIGHT thrust band [2000,7000] doesn't fit tiny ships.**
   Shuttle/attack-craft thrust lands ~1000–1500 (to keep accel sane at low
   mass), below the band floor. This is fine — it confirms we should treat that
   band as advisory for now, not widen-and-fuss. (Per "don't band everything
   today.")

6. **Reactor sizing is unprobed.** power_rating is 50–500 across the set but we
   don't yet model power *draw*, so these are vibes. Flagging as the next thing
   to make real if reactors are meant to be a constraint (M9b deferred numeric
   reactor-sufficiency for this reason).

## Signature axis (orthogonal to handling/combat)

These are the "how detectable / what do I read as" levers — separate knobs from
mass/thrust/guns, and the basis of the sensor game. **`cross_section` is an
authored flat var, NOT derived from rect size** — so apparent size is decoupled
from physical size. `density` is per-component and feeds mass + damage-soak +
classification at once. heat/EM output govern detectability and identity.

| Ship | cross_section | density | heat output | EM output | max_heat | reads as |
|------|---------------|---------|-------------|-----------|----------|----------|
| Frigate | 50 (Ship default) | 20 | reactor/sensor floors, moderate | loud — active sensors 20+10+5 | 200 | VESSEL |
| SensorDrone | **50 (inherited — likely unintended)** | 20 | low | 1 active (10) + passive | 200 | VESSEL |
| Missile | 2.0 | 20 | hot (runs near 500 cap) | seeker 10 | 500 | ORDNANCE (cs<10) |
| Buoy | 10 | 20 | **50 (deliberately high to mimic a ship)** | **50 (deliberate)** | — | VESSEL (by design) |

### Classification levers (from `classify_contact` thresholds)
- `cross_section < 10` → reads as **ORDNANCE** not a vessel (missile = 2).
- `em ≤ 5` AND `heat` low → reads as **dead/cold** (wreckage); if also
  `density > 250` AND big → **ASTEROID**. So a cold, dense, sensor-quiet ship
  can *hide as a rock* — the asteroid-station archetype, and a stealth option.
- Loud EM (active sensors / hot reactor) → unmistakably a powered **VESSEL**.

### Planned ships — signature draft
| Ship | cross_section | heat/EM posture | reads as |
|------|---------------|-----------------|----------|
| Cargo Shuttle | ~40 | moderate, civilian (not hiding) | VESSEL |
| Light Attack Craft | ~22 | lower EM, wants to close unseen | small VESSEL |
| Destroyer | ~75 | loud — big reactor + sensor suite, can't hide | large VESSEL |

### Signature observations
7. **Apparent size ≠ physical size.** `cross_section` is authored, so we can
   make a ship that's physically large but sensor-small (stealth hull) or tiny
   but loud. A lever we've barely used — only Buoy/Missile set it deliberately.
8. **SensorDrone inherits cross_section 50** (never sets its own) — a small
   relay buoy reading as a medium vessel. Probably a bug/oversight; a
   "runs dark, hard to find" recon platform (per the design doc) wants a *small*
   cross_section + low EM. Worth fixing when we touch it.
9. **density is an unused armor/disguise lever.** All ships are 20. Bumping hull
   density gives heavier + more damage-soak per volume ("armor plating") without
   changing footprint; pushing it past 250 on a cold ship makes it read as rock.
   The asteroid station will want this; combat ships could use mild density
   variation for armor tiers.
10. **heat/EM is the third differentiator** after handling and firepower. A
    sensor buoy / mine "runs dark"; a destroyer is a lighthouse. This maps onto
    the M2 dynamic-emission work — these are starting baselines the event pulses
    ride on top of.

## Open question for tuning

Is the frigate the *reference* the others scale around (keep its numbers, fit
shuttle/attack/destroyer to it), or is the frigate itself due a retune once the
ladder is visible (e.g. its 4000 hull / 50 accel as the T2 anchor)? The table
suggests the frigate is internally fine; the risk is the **destroyer** needing
to clearly exceed it on armor + firepower while staying slower.
