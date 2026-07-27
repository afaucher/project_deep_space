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

## Terminology (settled 2026-07, after a round of visible confusion)

The words below are the ONLY vocabulary for this system — code comments,
this doc, and conversation should all use them consistently. Established
after `keep_out_radius` (a second policy ring) and a misread "yellow circle"
(actually the slip marker, not the capture zone) turned out to be
misunderstandings, not designed behavior:

- **exclusion_radius** — the distance no ship should be from the station
  unless it's docking, docked, or undocking. A single threshold (`port_zone`
  field, derived: hull bounding radius × 6, ~1584u for a medium station).
- **exclusion zone** — the AREA no ship should be in (the disc from the
  station's hull out to exclusion_radius). Hatched. Might trigger a response
  in a future milestone; today it's advisory for the player (see
  "Rules and enforcement") and mandatory for NPC traffic.
- **capture zone** — a circle ADJACENT TO THE STATION, centered on the
  DOCKING POINT (not the station center), sized by `DockingBay.
  capture_radius`. Typically large enough to make grabbing the ship easy.
  This is the ONLY area the docking clamp applies (`DockingBay._try_
  capture()`'s reach). Its size is independent of exclusion_radius — it can
  extend past the exclusion boundary on the far side, since it's centered
  off-axis from the station.
- **docking point** — the exact spot the clamp tries to hold you
  (`DockingBay.berth_pos_for_bounding_radius()`, the clearance-adjusted
  seat — NOT the raw authored `docking_port` component position, which can
  sit inside the station's own hull for a berth mounted close to a large
  hull).
- **docking corridor** — the area a specific-slip grant opens through the
  exclusion zone, connecting the exclusion boundary to the capture zone. A
  90° cone (`PortChannel`, half-angle 45°) centered on the docking point's
  approach axis.
- **the guide** — a line down the center of the corridor
  (`PortChannel.guide_segment`), from the corridor's mouth (where it crosses
  exclusion_radius) to wherever it enters the capture zone. Past that point
  the clamp's own reach takes over, so the corridor's job is done.

There is deliberately NO second inner ring/"keep-out" policy boundary. An
earlier revision derived one (`keep_out_radius`, hull × 2) as its own drawn
ring and hatch boundary — that was solving a purely VISUAL problem ("don't
hatch on top of the station, it's hard to see") with a policy-shaped fix.
The hatch's inner bound is just the station's own hull bounding radius now
— nothing more.

## Geometry

- **Control ring** (existing `port_zone.radius`, e.g. Ironhold 8000): where
  rules apply. Banner on crossing — unchanged semantics. Separate from the
  exclusion zone below (a much larger, outer zone — comms rules and speed
  advisory, not the no-fly boundary).
- **Exclusion zone**: one boundary ring at `exclusion_radius`, 45° hatching
  filling hull → `exclusion_radius`. Derived by default (every station
  consistent for free), authored/`port_patch` override wins.
- **Docking corridor**: opened only by a specific-slip grant. The exclusion
  ring GAPS over the corridor's angular span, the hatch is clipped out of
  the same sector all the way down to the hull, and the sector's radial
  edges are drawn as the corridor's boundary. Everyone else still sees a
  closed ring. The corridor's edges are ZONE geometry (subdued, background)
  — they show the legal path's boundary, not the precise line to fly; that's
  the guide, drawn brighter down the corridor's centerline, from the mouth
  to where it enters the capture zone.
- **Capture zone**: a circle at the docking point, radius
  `DockingBay.capture_radius`, drawn dim/informational (not a precision
  target) for the assigned bay while a grant is held. DEFAULT capture radius
  is derived (`PortZone.derive_capture_radius`, hull bounding radius × 1.5)
  for EVERY docking_port that doesn't author its own — deliberately
  independent of exclusion_radius, not clamped against it: a short-range
  docking arm / a very-short-range force field ("shouldn't just grab random
  passing ships out of space"), much smaller than the exclusion zone by
  construction (~396u vs ~1584u for a medium station), not because it's
  contained within it.
- **The M34 marker/lane** (predates this arc): a small ring at
  `pos_tolerance` (the literal DOCKED-state acceptance gate — NOT the
  capture zone) plus a bright lane running from well outside the corridor
  down to the docking point. Bright full-gold, unlike everything else on
  this list — it's the precision "fly exactly here" aid, keyed to a LIVE
  grant only.
- **Departure**: the corridor and guide stay open while the ship is inside
  `exclusion_radius`, via `Ship.departing_slip` (stamped on bay release,
  cleared on exiting the boundary) — separate from `docking_grant`, which
  is consumed immediately on release so the slip frees for a new arrival.
  The M34 marker/lane do NOT use `departing_slip` — arrival-only aids; once
  released you already know where the berth is.

## Visibility

Port zones are COMMS knowledge: an authority broadcasts its boundaries, so a
station's rings/disc draw ONLY while the player and station are in mutual
comms range (weaker-of-the-two-ranges, same rule as the datalink). Within
that: every controlled station in comms range draws, the zone the player is
inside emphasized, others dimmer; zoom-gated via `zone_boundary_visible`.
All of it (control ring, exclusion zone, corridor, capture zone, guide, M34
marker/lane) is gated by one nav-panel toggle: "Port Control".

Zone drawing (control ring, exclusion zone, hatch, corridor edges) is
BACKGROUND terrain, not a foreground element: it draws at the bottom of the
nav map's world-space stack (right after the grid), in colors blended toward
the panel background with thicker strokes — every contact, lane, marker, and
laser reads on top of it. The guide and the M34 marker/lane stay bright
full-gold: they're actionable aids, not terrain.

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
- **Two speed rules, not one — self-imposed and externally imposed.** An
  earlier version of this bullet said only "NPCs treat the advisory as
  mandatory: traffic AI clamps its in-zone cruise speed to the zone's limit."
  That conflates two different things, and the gap showed up as measured
  damage (2026-07-25, `economy_traffic` — see below). Only `MediumStation`
  authors a `port_zone` at all, so **five of the home cluster's eight
  stations — every outpost — publish no limit to respect.** A rule that only
  exists inside an authored zone cannot govern most of the cluster's traffic.

  1. **Approach discipline (self-imposed, universal).** Every hull decelerates
     on final approach to *any* dockable, zone or no zone, authority or none.
     This is competence, not compliance — you slow down because you do not
     want to hit the thing, and physics does not care about jurisdiction. This
     is the rule that actually fixes shuttles tapping stations hard enough to
     set them spinning.
  2. **Published limit (externally imposed, where there is an authority).**
     The zone's `speed_advisory`, obeyed inside the zone whether or not you
     are docking — a ship merely transiting Ironhold's zone slows too. NPCs
     treat this as mandatory.

  **Small ports publish nothing because they cannot enforce anything.** No
  port control, no patrol, no ability to sanction a hull that ignores them.
  That is the fiction and it is also the mechanism: a limit exists where
  someone can make it stick. Rule 1 is what keeps behavior sane at the other
  five.

  **This asymmetry is worth keeping for its own sake.** At an enforced port
  everyone conforms, so approach speed says nothing about who you are. At an
  unenforced outpost, only a ship with self-preservation slows down — so how
  something comes in at a place with no authority becomes a readable tell.
  Violating a *published* limit is an offence (warrants/standing); being a
  menace at an outpost is just a warning sign about the pilot.

  (STRUCTURE despin, capture timeout, and nearest-bay assignment remain as
  the recovery net.)

  **Status: rule 2 is specified and unbuilt; rule 1 was never specified.**
  `speed_advisory` is authored (`medium_station.gd`) and read in exactly three
  places — `port_rules.gd` for banner text, `helm_panel.gd` for the player's
  amber gauge, and `test_port_rules.gd`. Nothing under `scripts/ai/` reads it;
  the AI's three `get_port_zone()` call sites are all about docking
  permission. The cost is measurable: in `economy_traffic`, station
  self-repair drain tracks docking count and ignores the zone entirely
  (Refinery Prime, which publishes a 200 u/s limit, took the worst damage in
  the cluster at 9 dockings; Slag Bay, which publishes nothing, took none at
  2). Stations pay for the dents out of their own REFINED/GOODS bins, which
  is why this first surfaced as an *economy* anomaly rather than a collision
  report.
- Player no-fly violation: warn-only for now (banner + a port-control comms
  scold). Escalation — reputation, denied future grants, patrol response —
  is real gameplay and DEFERRED to its own milestone; nothing in the model
  above depends on how hard enforcement eventually bites.

## The speeding ticket — designed 2026-07-27, not built

The "escalation is deferred to its own milestone" note above now has somewhere
to land. M52b's warrants and the 2026-07-27 yellow tier
(`design_ideas/2026-07-26-campaign_playtest.md`) supply the whole enforcement
ladder; `Standing.OFF_SPEED_VIOLATION` is already authored — caution-grade,
no force, 60s clock — and is currently the **only offense in the table that
nothing ever posts**. That is the same shape the deleted `wanted_names`
registry had, so it either gets a posting site or it gets removed.

**Almost all of it already exists:**

- `medium_station.gd` authors `"speed_advisory": 200.0` in its `port_zone.rules`.
- `PortRules.speed_advisory_active(in_zone, speed, limit)` is a written, tested
  truth table (plus `speed_zone_state`'s three-state helm readout).
- Stations default `warrant_authority: [own flag]` ("stations ARE the
  authority"), so a station's warrant is **flagged, not personal-origin** — it
  relays to any patrol holding that flag with no new plumbing.
- Contacts already carry `vel` (`ship.gd`'s complied-stop check reads it).
- Downstream is untouched: caution tier → `InterdictLeaf` demands a stop →
  never engaged, and it yields to red threats and SOS.

**The only missing piece is the OBSERVATION.** `speed_advisory_active` is
called solely by the player's own helm HUD; nothing evaluates another ship's
speed against the zone rule.

**Why this offense fits the model unusually well.** The rule is documented as
warn-only, and the asymmetry is deliberate — *"NPCs comply, the player gets a
gauge and the freedom to be a menace."* NPCs self-limit inside `_cruise_toward`
via `Steering.approach_speed_limit`, so in practice **only player-controlled
hulls can speed**: this is a player-facing offense by construction. It is also
fair in the way the campaign playtest demanded, without any new UI — the
crossing banner announces the limit as you enter, and the gauge goes amber
*before* red. A ticket is never a surprise.

**Design decisions, settled:**

1. **It is an EVENT, not a STATE — the first regulatory offense that is.**
   `NO_ID` is a continuing condition, which is exactly why lighting a
   transponder self-resolves it. Speeding is a past act: slowing down must not
   erase the ticket, so it rides its 60s clock instead. This usefully splits
   the regulatory bucket — regulatory offenses drop when you leave the
   jurisdiction, but only *state* ones clear on compliance.
2. **Observed speed, with a tolerance and a dwell.** A station reads `c.vel`
   off its own sensor track, which carries per-frame noise by design. Ticketing
   on what it actually observed is correct by the warrant honesty rule, but a
   single noisy sample must never issue — it needs a margin over the limit and
   a sustained-over window, the same shape as `ChallengeLeaf`'s.
3. **Issued by the STATION, not by patrols.** The limit is a property of that
   zone's own `rules`; a patrol has no business enforcing a limit it does not
   publish. `scoped_origin` already gives this for free.
4. **Stays out of the docking denial.** That gate is identity-only on purpose
   (`Ship.issue_docking_grant`); locking a ship out of port over a speed
   infraction is disproportionate.

**Why it is worth building at all**, given the consequence is deliberately mild
(you get hailed, it expires in a minute): it is the **second** regulatory
offense, which is what turns the yellow tier from a fixture built for `NO_ID`
into an actual system — and it gives a player a low-stakes way to see the whole
enforcement ladder run without dying to it.

## Deliberately out of scope

- Enforcement escalation (above) — now designed, see the speeding-ticket
  section; still unbuilt.
- Level 4 content (multiple lanes, tolls, weapons-safe) — the schema leaves
  room; nothing authors it yet.
- Boarding-clamp mechanics for Level 0 targets — separate feature; this doc
  only fixes where it sits in the model.
