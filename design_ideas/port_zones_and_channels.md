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

## Geometry (revised after first playtest)

- **Control ring** (existing `port_zone.radius`, e.g. Ironhold 8000): where
  rules apply. Banner on crossing — unchanged semantics.
- **Keep-back zone = two circles + hatch** (replacing the first-pass single
  disc + narrow rectangle channel):
  - **Inner keep-out ring** (`keep_out_radius`, derived: hull bounding
    radius × 2): the hard do-not-cross line just off the hull.
  - **Outer boundary** (`exclusion_radius`, derived: hull bounding
    radius × 6, ~1584u for a medium station): much larger, so approaches can
    come in well off-axis.
  - 45° hatching fills hull → outer boundary. Both radii derived by default
    (every station consistent for free), authored/`port_patch` override wins.
- **Channel = a 90° cone** (`PortChannel`, half-angle 45°) centered on the
  assigned berth's approach axis, opened only by a specific-slip grant: both
  circles GAP over the cone's span (the gaps line up by construction), the
  sector's radial edges are the drawn lane edges, and the hatch is clipped
  out of the sector all the way down to the hull. Everyone else still sees
  closed rings. The cone's edges are ZONE geometry (subdued, background) —
  they show the legal corridor's boundary, not the precise path; see
  "Approach guide" below for the actionable aid.
- **Departure**: the channel stays open while the grant is held; the grant
  is CONSUMED on bay release (undock/auto-release — landed with the grant-
  lifecycle fix), and M47 adds expiry on exclusion-boundary exit for the
  departure leg.

## Approach guide (pre-existing M34 aid, not new geometry)

A first pass at this rework added a second "docking guide" — a bright
centerline + diamond ending where `PortChannel.guide_points` computed the
docking clamps' engage point, `min(bay.capture_radius, distance-to-mouth)`.
**Removed** after first playtest ("I can't tell where to hit — only three
lines to the edge of the no-fly zone and one little diamond dot"): every
station's `capture_radius` (default 5000u) is larger than its whole
`exclusion_radius` (~1584u for a medium station), so that `min()` always
resolved to the mouth — the diamond always sat at the FAR edge of the no-fly
disc, nowhere near the berth, and it duplicated an aid that already existed
and already worked: the M34 lane/slip marker
(`navigation_panel._draw_docking_nav_aids`/`_draw_lane`, predates M46). That
marker — a filled gold ring with a heading tick right at the assigned
berth, plus a bright lane corridor running 1500u out from the berth — is
the actual "small zone near the station," and stayed bright/prominent while
the new cone geometry's colors were dimmed to zone-background levels so the
two stop competing for attention.

## Visibility

Port zones are COMMS knowledge: an authority broadcasts its boundaries, so a
station's rings/disc draw ONLY while the player and station are in mutual
comms range (weaker-of-the-two-ranges, same rule as the datalink). Within
that: every controlled station in comms range draws, the zone the player is
inside emphasized, others dimmer; zoom-gated via `zone_boundary_visible`.

Zone drawing (control ring, keep-back circles, hatch, cone edges) is
BACKGROUND terrain, not a foreground element: it draws at the bottom of the
nav map's world-space stack (right after the grid), in colors blended toward
the panel background with thicker strokes — every contact, lane, marker, and
laser reads on top of it. The M34 approach guide (lane + slip marker) stays
bright full-gold: it's the actionable aid, not terrain.

## Ship's log

Docking is recorded in the engineering log (M40): an entry on the DOCKED
transition ("Docked at <station> berth <slip>") and on release from a
completed stay ("Released from berth <slip>"). Aborted captures never log —
they'd spam the ring buffer on every timeout/retry cycle.

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
