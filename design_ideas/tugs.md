# Tugs: rescue & road maintenance

The working-boat class of the drift — the tow truck and the road crew.
Expressed entirely in the jobs model
([jobs_and_itineraries.md](jobs_and_itineraries.md); this doc is the
class's write-up, the catalog table there stays the index). Not scheduled
into a milestone yet — natural landing is M53 alongside the traffic
directors, or earlier if the world should self-heal sooner.

## Why this class earns its slot

- It closes a loop playtesting exposed: **collisions displace live beacons
  and the displacement persists** (position syncs back to the cluster
  record on demote) — today a shoved beacon bends the road forever, and
  nothing in the world will ever fix it.
- It's the first **infrastructure keeper**: visible, mundane maintenance is
  what makes the drift read as a lived-in place (a tug trundling its
  inspect circuit is ambient life the player can idly watch on the nav
  map).
- It pays off systems already built: M49's `SOS {nature: DISABLED}` is its
  dispatch signal; M40's repair system is what it carries shipboard; the
  docking bay's capture spring is its tow physics; the two-slot job model
  (standing duty + assignment) is exactly its work pattern.
- The player is a customer: burn out your reactor, throw the battery SOS,
  and a tug hauls you to a station for repairs — the wreck-recovery
  experience already sketched in the class validation pass.

## Role 1 — rescue (the tow truck)

- **Standing duty**: standby at its home station (`AWAIT`), or a short
  loiter near the road.
- **Dispatch**: the station/port-authority director hears `SOS(DISABLED)`
  (or a wreck report) and issues a tow **assignment** — the two-slot
  fallback in its designed use.
- **Assignment**: `INTERCEPT casualty → GRAPPLE → GO_TO repair station
  (towing) → RELEASE_TOW` (hand off to the berth). Abort edges: casualty
  gone → back to standby; under attack → `RELEASE_TOW` then the reactive
  layer flees (a tug never fights).
- The casualty can be a live-but-dead-reactor ship (the player!) or a
  hulk. Towing a hulk interacts with the cluster death gap — the tug is
  the eventual in-fiction answer to wreckage cleanup, which is another
  reason the record-retirement plumbing matters.

## Role 2 — road maintenance (the road crew)

- **Standing duty** (`repeat`): the inspect circuit — `GO_TO` each beacon
  on the road in sequence. At each stop, two checks against **authored
  infrastructure data** (where the beacon is SUPPOSED to be — public
  knowledge, honest under the director rule; no sensor omniscience):
  - **Displaced** past tolerance → `GRAPPLE → TOW to authored position →
    RELEASE_TOW`. The road heals.
  - **Damaged** → `REPAIR` in place (the M40 repair system, shipboard),
    or — past a damage threshold — tow it to a repair station and (later,
    with the economy) a replacement gets seeded.
- Nothing found → cruise to the next beacon. The circuit is pure `GO_TO`
  data plus the two checks; a maintenance tug and a rescue tug are the
  same hull with different jobs.

## New machinery required (small)

- **`GRAPPLE` / `TOW` / `RELEASE_TOW` verbs** — reuse the docking-bay
  capture-spring mechanic ship-to-ship; towing modifies the tug's
  effective mass/handling (the existing mass-from-components model gives
  this almost for free).
- **`REPAIR` verb** — M40's repair logic executed by a ship on another
  ship's components, gated on holding alongside (the TAKE_ALONGSIDE
  proximity pattern, peaceful edition).
- **A maintenance/dispatch director** — ledger + policy tick per the
  director pattern; plausibly the port authority rather than a new
  organization. Knows the road (authored data), hears SOS (public
  broadcast), dispatches assignments.
- **Beacon displacement check** — |actual − authored| > tolerance, where
  "actual" is read on-site during the circuit visit (the tug flies there
  and looks — no remote omniscience needed).

## Open questions (for the design pass when it lands)

- Sleeping-body gotcha: a displaced beacon at rest is a sleeping
  RigidBody2D — the tow-drop must wake/re-register it properly (CLAUDE.md's
  teleport rules apply to the RELEASE placement).
- Does a tug get robbed? A pirate demanding a stop from a tug towing
  salvage is delightful and probably just works (ThreatResponse +
  RELEASE_TOW-on-abort), but the salvage-value story needs the economy.
- Who pays for repairs-by-tug (player rescue) — credits land with M54's
  mission economy; until then rescue is a public service.
