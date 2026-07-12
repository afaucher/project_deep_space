# Port zones, no-fly discs, and docking channels

The unified model for port control across every dockable thing in the game —
from a mobile home to a major station — and the visual language that draws it.
Decided 2026-07 after the M31-M36 port-authority arc and the campaign
docking-wedge fix. Implementation: `implementation_plans/
m46_m47_port_zone_visuals_roadmap.md`.

## The problem

One solid circle (the M35 zone-boundary ring) carried three different
meanings: "rules apply here," "don't fly here," and "here's how to get in" —
and it only drew for the zone the player was already inside. Meanwhile NPC
cargo shuttles cruise at 700 u/s straight to an approach point beside the
hull; a hull tap sets a station spinning (the campaign docking-wedge bug's
root cause — despin now recovers it, but the hazard itself remained).

## The ladder: five levels, one schema

Port control is a LADDER of authored data, not a set of station types. Each
level just authors more fields on the same `port_zone` dict + berth list; the
renderer and the AI read only what's authored, so every level is consistent
by construction.

| Level | Who | Berths | Grant | Ring + rules | No-fly disc | Channel |
|---|---|---|---|---|---|---|
| 0 None | random ships, wrecks; boarding targets | none/clamp | — | — | — | — |
| 1 Open berth | mobile homes (Todd, Hermit's Rest) | 1 | none — fly up, dock | — | — | — |
| 2 Assignable | small stations (Slag Bay, Coldreach) | 1-2 | via comms/auto | optional thin ring | — | — |
| 3 Controlled | medium stations (Ironhold) | 2+ | required | yes | yes | opens on grant |
| 4 Major port | large stations (future) | many | required | yes + weapons-safe, tolls, ... | yes | per-berth arrival/departure lanes |

Principles that keep the use cases coherent:

- **Pirate boarding is Level 0 by definition.** Docking without permission is
  the existing mechanics minus a grant — the capture path must never assume a
  grant exists (open stations already dock grantless). No-fly means nothing
  to someone who intends to violate it; boarding stays orthogonal to port
  control. Enforcement (below) is what makes violation *matter*, later.
- **Mobile homes stay Level 1.** The M43 Slag Bay trailer field must not be a
  visual mess of overlapping rings — you just fly up to Todd's berth.
- **Open vs assignable at Level 1/2 is an authoring choice per station**, not
  a code path — both already work mechanically.
- **One renderer.** The nav panel draws ring / stripes / channel purely from
  authored fields plus the player's grant state. Promoting a station up the
  ladder is a data edit.

## Geometry

- **Control ring** (existing `port_zone.radius`, e.g. Ironhold 8000): where
  rules apply. Thin solid ring, banner on crossing — unchanged semantics.
- **Exclusion disc** (new `exclusion_radius`, order ~1500-2000 for a medium
  station): annulus from the hull to the exclusion radius, diagonal-hatched.
  Entering without a grant is a violation. DERIVED by default (hull bounding
  radius × factor, so every station is consistent for free) with an optional
  authored override — story overlays can patch it via `port_patch` (a
  paranoid outpost with an oversized keep-out).
- **Channel**: with a grant, a corridor-shaped cutout opens from the
  exclusion boundary to the ASSIGNED berth, aligned with the berth's heading
  (the same approach vector the M34 lane and the capture cone already use).
  Hatching gaps out over the channel; NavCorridor edges draw through it.
  Everyone else still sees a closed disc. Channel width must fit the capture
  cone with margin.
- **Departure**: the channel stays open while the grant is held; the grant
  expires when the ship EXITS the exclusion boundary after undocking (not on
  a countdown) so you never undock into a violation.

## Visibility

Zones draw for EVERY controlled station on screen, not just the one the
player is inside (a no-fly zone you can't see until you're in it defeats the
purpose). The zone the player is inside gets the emphasized treatment; others
draw dimmer. Zoom-gated the same way the current boundary ring is
(`zone_boundary_visible`).

## Rules and enforcement

- `speed_advisory` stays WARN-ONLY for the player (amber helm state — never a
  thrust clamp; the player is free to be a menace).
- **The limit is displayed with the speedometer, not the mission area** —
  it's local traffic law (a property of where you are), not an objective.
  Helm velocity gauge gets a limit tick + a "current / limit" readout with
  three color states (under / approaching / over) while inside a zone; the
  gauge tick makes the limit actionable when SETTING a target velocity, not
  just when already speeding.
- **NPCs treat the advisory as mandatory.** Traffic AI clamps its in-zone
  cruise speed to the zone's limit and decelerates down the channel — this,
  not despin, is the real fix for shuttles tapping the station hard enough
  to set it spinning. (STRUCTURE despin, capture timeout, and nearest-bay
  assignment remain as the recovery net.)
- Player no-fly violation: warn-only for now (banner + a port-control comms
  scold). Escalation — reputation, denied future grants, patrol response —
  is real gameplay and DEFERRED to its own milestone; nothing in the model
  above depends on how hard enforcement eventually bites.

## Deliberately out of scope

- Enforcement escalation (above).
- Level 4 content (multiple lanes, tolls, weapons-safe) — the schema leaves
  room; nothing authors it yet.
- Boarding-clamp mechanics for Level 0 targets — separate feature; this doc
  only fixes where it sits in the model.
