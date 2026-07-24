# M53a — Economic expansion: room, traffic, and a peer state

Sub-milestone pulled forward out of M53 (m48_m55_economy_piracy_roadmap.md)
by the 2026-07-20 pirate playtest (design_ideas/2026-07-20-pirate_playtest.md):
the player needed a debug mode just to FIND the pirate, because there isn't
enough traffic for pirates to have real target selection. M53's traffic
guild is the systemic answer; this sub-milestone is the WORLD the guild
needs to exist in first — geography and baseline traffic, no demand ledger
yet.

## Foundation: faction model + player setup (do FIRST, before the world grows)

Adding a peer sovereign exposes a degenerate hack that has to be fixed before
the jurisdiction seams mean anything. These are the "mechanical shape"
prerequisites; do them as the first slice.

1. **Player is a NEUTRAL independent, not crypto-kin of home** (decided).
   Today `home_cluster.gd`'s `HOME_IFF` is `["TEAM_PLAYER"]` — the whole home
   faction shares the PLAYER's crypto tag, so `compute_standing` returns
   FRIENDLY on the crypto handshake and the player can NEVER be marked HOSTILE
   by home (crypto beats flag), which silently breaks the M52 contract ("shoot
   a home station → Patrol Alpha turns, marks you… applies to the player").
   Fix: home gets its OWN crypto tag (placeholder `TEAM_DRIFT`); the player
   keeps `TEAM_PLAYER` (so their own drones/wingmen still read FRIENDLY) and
   keeps flying `FLAG_DRIFT`. The player now reads **NEUTRAL** to home — left
   alone (stations fire on HOSTILE only), dock grants still issued (NEUTRAL
   qualifies), reporting-so-no-challenge — but flippable to HOSTILE on
   aggression, so the whole warrant/interdiction system applies to the player
   symmetrically. Scoped to the campaign (`home_cluster.gd`); the sandbox's
   TEAM_PLAYER-vs-ENEMY setup is untouched. Cost: a combat-test audit for any
   test that assumed player↔home share the tag (the M48-style price; likely
   the campaign_* tests plus any home-friendly assertion).

2. **Player starter ship = CargoShuttle** (decided). Campaign spawns the player
   in the civilian hauler — slow, fragile, sensors + comms, UNARMED, on-theme
   "vulnerable hauler" (the escort fantasy makes you *be* the shuttle). Scoped
   to the campaign spawn path only; the sandbox ship-select keeps the full
   catalog. NOTE: CargoShuttle has no explicit `cargo_bay` component yet (cargo
   is abstract until M55), so "cargo capacity" is fiction-now / real-at-M55. A
   bespoke lightly-armed starter hull is deferred (a ship-design + validator +
   test task = its own fiction/design pass).

3. **Peer state name — PLACEHOLDER, pending a real fiction-authoring pass**
   (out of scope here; we only need the mechanical shape). Working default:
   **Meridian Combine** (crypto tag `TEAM_MERIDIAN`, flag `FLAG_MERIDIAN :=
   "MERIDIAN_COMBINE"`). Alternatives to swap in trivially: The Tarn Reach,
   Karst Compact, Ostrend Union, The Halcyon Combine. The `FLAG_*`/crypto
   constants land WITH the peer stations (task 3 of Scope below), not before —
   no dead constants ahead of a consumer. Each peer station defaults
   `warrant_authority` to its own flag (free from M52b) → the jurisdiction seam.

## Scope (the playtest's four asks)

1. **2x the cluster radius.** More room between things: lanes long enough
   to have lonely middles, distances that make "off-road" meaningful.
   Everything currently authored in home_cluster.gd scales — station/beacon
   positions, lane routes, patrol boxes. Watch items: comms/sensor ranges
   do NOT scale (that's the point — the world gets bigger relative to your
   senses), the beacon road's ~25k spacing rule keeps its ABSOLUTE spacing
   (more beacons, not sparser ones — it's a surveilled corridor, that's its
   identity), and the pirate guild's hazard keep-aways (15k beacon / 25k
   station) stay absolute for the same reason.
2. **Wormhole near the center station.** Today's wormhole sits on the
   periphery; moving it near the hub makes it the cluster's front door —
   transient traffic flows past the hub naturally, and pirate arrivals/
   exfils have to transit REAL space instead of skulking on the edge.
   (M52a's staging-anchors-at-the-lane fix already decoupled hunting from
   the wormhole's position, so this is safe for the guild.)
3. **Two mining colonies under a PEER STATE's flag.** New stations, new
   flag (a second sovereign in the cluster — not home, not pirate), each
   with a trade route back to the center station. Design consequences we
   get for free from M52b: their stations default `warrant_authority` to
   the PEER flag, so their warrants are visible-but-unenforced intel to
   home patrols and vice versa ("you killed someone in the next country
   over and nobody here cares" — now testable in-game). Their haulers are
   NEUTRAL to everyone reporting clean. Pirates now have jurisdiction
   seams to play in — rob a peer hauler where only peer warrants reach,
   and home space stays open to you.
4. **Transient wormhole freighters.** Freighters periodically emerge from
   the wormhole, run the beacon road end-to-end with a dock stop at each
   terminus, and LEAVE via the wormhole. Same arrival-record mechanism the
   pirate guild uses (ClusterEntity spawned at the wormhole, promoted on
   approach) — this is the "extract the shared guild skeleton" step M53
   already planned, proven here by a second consumer. These are through-
   traffic: they don't rebalance anything, they just make the road busy —
   witnesses for the road, targets for nothing (they never leave the
   corridor; robbing the road stays hard, which is correct).

## Pirate circulation (the other half of the playtest note)

"Pirates should bounce between available trade routes... They should NOT
always enter the route in the same spot."

- Route variety mostly exists already (M52a's `_pick_lane_point` rerolls
  across the WHOLE lane set per attempt) but with only two sparse home
  lanes it CONVERGES — the hazard-clearance reroll keeps picking the same
  clear stretch. Four+ routes (two peer colonies + hub lanes + the road)
  is what actually fixes it; verify with the viability sim that hunt
  points spread across routes run-to-run rather than piling onto one.
- **Entry-point variance**: `_staging_point` offsets from the lane at a
  fixed geometry today; widen to a randomized offset (seeded RNG, per
  CLAUDE.md) along the lane's length so two consecutive pirates on the
  same route don't surface at the same spot.
- **Posture variety**: today's tradecraft is always lurk-dark. Add the
  alternative from the playtest — cruise the lane LIT under the cover
  identity, looking like one more freighter (transponder on, cover name,
  normal lane speed), closing to demand range as an apparent fellow
  traveler. One new job-step parameter (posture: "dark_lurk" |
  "false_flag_cruise"), guild rolls between them. The false-flag cruise is
  also the fiction's answer to "how does a pirate hunt the ROAD at all"
  once mandatory IDs land (warrants.md's corridor future).

## Explicitly not this milestone

- Demand ledgers / per-station demand scores — that's M53 proper.
- Peer-state patrols or diplomacy — peers get stations, haulers, and a
  flag; their navy is later content.
- Physical cargo — M55.

## Tests

- Cluster validator passes at 2x scale (no overlapping keep-aways, lanes
  clear of hazards where intended).
- Peer colony haulers run their routes and dock (reuse cargo-run test
  shape against the new stations).
- Transient freighter lifecycle: arrives, transits road with two stops,
  departs, record cleaned up.
- Guild hunt points spread across >= 3 distinct routes over N sim runs
  (margin-based, physics nondeterminism per CLAUDE.md).
- Peer-flag warrant is visible but unenforced by a home patrol
  (pure-function check against warrant_enforceable_by — pins the
  jurisdiction seam).
