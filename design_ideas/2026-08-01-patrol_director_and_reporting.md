# A patrol director, and the reporting layer it needs first

**Status: design thinking, nothing built.** Written 2026-08-01 alongside the
pirate tradecraft measurements. The behaviour changes (probabilistic colours,
probabilistic SOS, SOS reprisal) are implemented and being measured separately;
this is the "what would enforcement even look like" half, and it is deliberately
ahead of the code.

---

## 1. Why patrols cannot currently respond to anything

Measured, not assumed (see `2026-07-28-authority_scenarios.md` and the
2026-08-01 hunt-budget arithmetic):

| | |
|---|---|
| Patrol orbit | **24,000 u** around its home station (`12000 × SCALE`) |
| Controlled space (where Challenge may fire) | **8,000 u** around a station |
| Victim comms / SOS reach | **30,000 u** |
| Station-to-station leg | **~300,000 u** |

A robbery at a lane midpoint is **~150,000 u** from either station — five times
beyond the victim's SOS reach and far outside any patrol's sensors. The SOS goes
out and **nobody is in range to hear it.**

And the three enforcement leaves are each gated shut against a competent pirate:
Engage needs HOSTILE (a dark pirate reads CAUTION, a false-flag one NEUTRAL),
Interdict needs an enforceable warrant (a pirate that hasn't robbed anyone has
none), Challenge needs CAUTION **inside controlled space**.

So today's patrols are **station guards**. Nothing about them is broken; there
is simply no mechanism by which they could learn a lane robbery happened.

**The gap is not enforcement. It is reporting.** Building a patrol director
before a reporting layer would produce a director with an empty inbox.

---

## 2. The reporting layer

### 2.1 What exists, and what listens to it

| Signal | Written by | Read by |
|---|---|---|
| `sos_active` / `sos_nature` | `ThreatResponseLeaf` at incident start | Anyone within 30,000 u, **live only** — it evaporates when the incident ends |
| Docking registry (`DOCKED` / `DEPARTED`, monotonic seq) | `docking_bay.gd` at both transitions | **Nobody.** `get_docking_registry()`'s only caller is `test_docking_registry.gd` |
| Warrants | victims/witnesses via `post_warrant` | `compute_standing`, and they relay over the datalink |

So of three candidate signals, one is live-only and out of range, one is
**write-only**, and only warrants actually travel.

That is the answer to "did we ever hook the docking logs up": **no.** They are
recorded faithfully and consumed by nothing.

### 2.1b CORRECTION — the report object already exists, sealed

Written after §2.2 below, which proposed building an incident report from
scratch. Most of it is already there, and the real gap is one step narrower.

A completed robbery does exactly three things:

```gdscript
actor.loot_takes += 1                         # counter on the pirate
victim.looted = true                          # flag NOTHING reads
victim.post_warrant(OFF_ARMED_ROBBERY, ...)   # durable, subject-keyed, timestamped
```

The third is already the incident report §2.2 asks for — correct shape,
signature-keyed identity, timestamp, and warrants already relay.

**It cannot travel, for a precise reason.** A civilian hauler has
`warrant_authority = []`, so `Standing.scoped_origin` stamps `origin_flag = ""`
— a PERSONAL warrant. And personal-origin warrants **never relay**
(`test_standing_e2e` Scenario I pins exactly this). The victim survives, flies
home, docks, and carries a perfectly good record that nobody can receive and
only it may act on. For an unarmed hauler, that is nothing.

So the missing feature is not transport and not a new object. It is
**NOTARIZATION**: a civilian handing a personal grievance to an authority, which
re-posts it under its own flag and thereby makes it enforceable by every patrol
of that flag. Filing a police report, at the counter, on arrival.

That reuses every existing mechanism — warrant shape, `subject_key`,
enforceability scoping, relay — and hooks at `docking_bay.gd`'s DOCKED
transition, which is already the convergence point. It is a much smaller feature
than §2.2's mail network, and it should be built first; the courier network only
matters once there is something a courier can usefully carry.

**Also found: a robbery moves no cargo.** The ship has no manifest at all
(`cargo_docking`/`cargo_captured_seen` are AI state booleans), so a robbed
hauler delivers its freight intact. `loot_takes`/`takes_total` are a scoreboard,
not an economy. Piracy currently cannot affect a single station's stock — worth
settling before tuning how often it succeeds, since success presently costs the
victim nothing but a flag.

### 2.2 The missing object: an incident report

A durable, copyable record that outlives the incident and can be carried:

```
{ kind: ROBBERY | SIGHTING | OVERDUE,
  pos, timestamp,
  subject: {claimed_name, flag, signature},   # same shape warrants already use
  reporter, confidence }
```

The subject shape should be **exactly** `Standing.subject_key`'s inputs, because
the hard-won lesson from warrants applies unchanged: a dark pirate has no
claimed name, so identity has to fall back to signature, and any new identity
mechanism that forgets this will re-learn it the expensive way.

**Reports must travel, not broadcast.** The memory-worthy design direction is
already recorded (`mail_network.md`): information rides couriers. A robbed
hauler carries the report to the next station it docks at. That gives
enforcement an honest latency — the police learn about it when the victim limps
home, not instantly — and it makes the courier network itself worth attacking.

`docking_bay.gd`'s DOCKED transition is the natural delivery point. It is
already the convergence point for both the dialogue and fast-path docking
routes, which is exactly the property that made it the right hook for cargo
delivery.

### 2.3 Ships going missing

The docking registry already contains everything needed, unused:

- A hauler `DEPARTED` station A.
- `RoutePlanner` knew its destination and rough ETA.
- It never `DOCKED` at B.

Reconciling departures against arrivals yields **OVERDUE**, which is a genuine
intelligence signal that needs no witness at all — the strongest kind, because a
pirate cannot suppress it by killing the only observer.

This belongs to the **traffic guild**, not the patrol director: it already owns
hauler population per flag and already replenishes a LOST hauler on the same
route. Overdue detection is the same ledger asking a question it does not
currently ask. The patrol director should *consume* the resulting report, not
compute it.

Worth noting the honesty rule cuts correctly here: the traffic guild reading
its own members' arrival records is exactly the "radio report" the director
pattern permits, the same way `PirateGuild._check_ins` reads only its own
members' nodes.

---

## 3. What a patrol director would look like

Same shape as the two directors that exist (`jobs_and_itineraries.md` §3 — a
ledger plus a policy tick, plus the honesty rule). Note the deliberate
instruction in `traffic_guild.gd` not to factor the two together yet: a third
concrete director is what would earn the shared skeleton, so this should be
written concretely too.

**Ledger:** patrol hulls, their home station, current assignment
(`ORBIT` | `RESPOND` | `SWEEP` | `RETURN`), and time on task.

**Inbox:** incident reports, each ageing. A sighting is a **datum with decay**,
not a standing order — the pirate has moved, and a report five minutes old
points at empty space. Reports should lose priority on a clock, and expire.

**Policy tick:**
1. Age and expire reports.
2. Score open reports: severity × freshness ÷ transit time from the nearest
   idle patrol.
3. Assign at most one responder per report; leave the station covered.
4. Recall responders on expiry.

**The response job** reuses the existing step vocabulary rather than inventing
one: `GO_TO` the reported position, a lurk/sweep at radius, then `GO_TO` home.
`SELECT_VICTIM`'s scan is nearly the shape a sweep wants, pointed at
caution-tier and warranted contacts instead of prey.

### What it should NOT do

- **Not teleport knowledge.** The director may only act on delivered reports.
  If it reads live world state to find pirates, the whole fiction collapses and
  piracy becomes unplayable.
- **Not always succeed.** Arriving late and finding nothing is the correct
  common outcome. That is what makes a successful interception feel earned, and
  it is why response latency is a design dial rather than a bug.
- **Not strip the station.** A patrol pulled onto a lane is a station left
  uncovered — which is a real pirate strategy (bait), and worth being exploitable.

---

## 4. Open questions

- **Does a lane patrol need a different hull?** Patrol Alpha/Bravo are
  `LightAttackCraft` on 24,000 u orbits. Lane response over 150,000 u is a
  different job — possibly a different, faster, longer-legged hull, or a
  standing lane picket rather than a responder.
- **Sensor reach.** The pirate sees 20,000 u; a sweeping patrol has the same
  problem in reverse and will miss what it is sent to find. A sweep that cannot
  detect is theatre. This may want a dedicated sensor picket.
- **Who pays?** If enforcement is free, piracy is just a tax. Response cost
  (fuel, time off station, opportunity) is what makes the economy of it real.
- **Does the player get reports?** The comms panel already has the surfaces
  (HAILS, CONTRACTS). An incident board the player can read — and act on before
  the patrol does — is most of a bounty system for free.
- **Reprisal interaction.** Now that calling for help can get a hauler shot
  (2026-08-01), a rational hauler may stay quiet, which starves the report
  network. That is a good tension, but it means SOS cannot be the *only*
  reporting path — which is another argument for OVERDUE detection, since it
  works without a willing witness.

---

## 4b. How this fits the plans that already exist

Nothing above is a new direction. Both gaps this document found are already
covered by written plans, and the measurements mostly settle their ORDER.

### Cargo: `station_economy.md` §"Haul capacity is a property of the HULL"

"A robbery moves no cargo" has the same root cause as the flat
`RoutePlanner.LOT_SIZE`: **there is no cargo object to move.** The plan is
already specified — capacity derived from `cargo_bay` components, consistent
with "a ship is its parts" — and it notes the machinery is mostly present:
`ComponentSpec.CARGO_AREA_PER_UNIT` exists and `ship_design_validator.gd`
already computes `capacity = total_cargo_area / CARGO_AREA_PER_UNIT`, for
validation only, with nothing reading it at runtime. Its two named blockers
stand: CargoShuttle authors no `cargo_bay` at all, and area-units need
calibrating into lots.

So the dependency is one-way and firm: **capacity must land before robbery can
mean anything economically.** Until then `loot_takes` is a scoreboard, and
tuning how often pirates succeed is tuning the frequency of an event with no
consequence.

### Omniscience: `mail_network.md`

That doc already names the exact trick the pirate guild uses — reading only its
own members' live nodes, a "radio report" fiction — and states plainly that it
"does NOT generalize", quoting the 2026-07-20 playtest intent: pirates should
have to *comm in from each ship*, with contacts on stations that can be found
and removed. Its principle is one line: **a director knows only what has
physically reached its location.**

**That principle IS the notarization step in §2.1b, seen from the other side.**
A victim's personal warrant becoming an authority's enforceable one *on arrival
at a station* is the same rule applied to enforcement rather than to piracy. So
the transport layer mail_network describes serves both problems at once:

| | needs |
|---|---|
| Pirate guild honesty | members' reports physically reaching the guild |
| Patrol director inbox | victims' reports physically reaching an authority |

They are one feature seen from two factions, which is a good sign the principle
is the right one.

### What the measurements add: these three threads are independent

The hunt-budget A/B (0 sightings → 8, and the first campaign-scale take) matters
here because it decouples the work. Piracy can be made to *function* with a
config number, before any unbuilt mechanism exists:

- **Pirates finding prey** — a measured number, available now.
- **Robbery mattering** — blocked on cargo capacity.
- **Enforcement existing** — notarization (small), then mail (large).

None blocks another. That is worth knowing before committing to a big vertical.

### One piece that needs no mail at all

OVERDUE detection is buildable honestly **today**, by the traffic guild, using
the same trick the pirate guild already uses: haulers on authored lanes are its
OWN members, so reading their arrival records is a radio report, not
omniscience. A station noticing a stranger's non-arrival would need mail; a
guild noticing its own hull is overdue does not.

That makes it the cheapest real intelligence signal in the system, and the only
one that survives a pirate killing the sole witness.

## 4c. Verdict vs evidence — and why aggregation is a consumer's policy

The first version of this document proposed annotating warrants with a position
and a re-post counter, to build a contention map. **That is wrong**, and the
reason generalises.

A warrant is a **verdict**: keyed `(offense, subject)`, overwriting, answering
"is this hull wanted right now". That shape is correct for what reads it —
`compute_standing` does one O(1) lookup per contact per fusion tick — and the
overwrite is load-bearing in two measured places: a witnessed `ARMED_THREAT`
re-post keeps ONE warrant alive rather than accumulating N (observed: same
`event_key`, timestamp refreshed 318 → 408), and `SUSTAINED_ASSAULT` overwriting
prevents duplicate escalation. **Do not change warrant semantics.**

An incident is **evidence**: one immutable record per occurrence.

```
{ id, kind, subject, pos, timestamp, reporter }
```

Three robberies by one pirate are three incidents. Whether that is one problem
or three — whether last week weighs as much as this morning, whether to cluster
by lane — is **interpretation, and it belongs to the consuming director**, not to
the record. Bolting a counter onto the warrant would bake one consumer's policy
into a store every consumer shares, and would still discard the position of
every earlier occurrence.

The asymmetry that settles it: **a verdict can always be re-derived from
evidence; evidence can never be recovered from a verdict.** Today only verdicts
are kept, which is why a contention map is impossible — not because warrants
lack a `pos`, but because they lack PLURALITY.

An append-only log merges by union on a unique id: monotonic, order-independent,
re-sync safe — the same property `merge_warrant`'s latest-timestamp-wins
provides, and exactly the "monotonic per-source log" shape `mail_network.md`
is heading toward. Warrants become the second consumer of that pattern instead
of the only one.

Needs deciding (also policy): incidents need a **bound** — a ring like
`last_hails`, or expiry — or an append-only log grows without limit over a long
campaign.

## 4d. One map, three directors, opposite signs

The same incident log, read by different policies, produces opposing behaviour.
That is the argument for making it a shared substrate rather than three
bespoke feeds.

| Director | Reads incidents as | Wants |
|---|---|---|
| **Traffic / cargo** | danger | avoid the lane, or demand a higher payoff to fly it |
| **Patrol** | where the work is | go there, sweep, stay a while |
| **Pirate** | enforcement heat | **profitable AND quiet** — prey worth robbing, no patrol |

The pirate row is the interesting one, and it is NOT "cargo with the sign
flipped". A pirate wants what cargo wants — a safe lane — plus something cargo
does not care about: prey on it. It needs **two** layers, not one:

```
pirate_score  =  prey_density  -  enforcement_heat
cargo_score   =  payout        -  travel_cost  -  risk
```

Same shape. Every director is running one scoring function; they differ only in
what they call payoff and what they call risk. `RoutePlanner._score_pair` is
already the reference implementation of it.

### The pirate hunts where cargo feels safe

This falls out and is worth stating plainly, because it is the whole predator
loop in one line: cargo concentrates on the lanes it believes are safe, so
**the safe lanes are where the prey is**. A pirate preferring profitable-and-
quiet routes is therefore drawn to exactly the lanes cargo has decided are
fine — and robbing them makes them unsafe, so cargo leaves, so the pirate
follows. Piracy migrates around the map instead of parking on one lane, with no
migration logic written anywhere.

The three-way version, which is the behaviour to aim for: cargo flees a lane →
pirates follow the cargo → patrols follow the incident reports → pirates leave
→ heat decays → cargo returns. Nobody schedules that; it is three directors
subtracting risk from payoff on stale maps.

### The pirate guild's honest feed already exists

The standing objection is the guild's omniscience. But `step_select_victim`
already produces, from the hunting pirate's OWN sensors at a known `lane_pos`,
everything the map needs:

- it scans `actor.active_contacts` and builds `all_fresh_vessels` — a **prey and
  witness count at that position**;
- its two abort reasons already separate the two failures that matter —
  `"hunt time budget (Ns) spent, no take"` (**no prey here**) versus
  `"hunt budget spent (N attempts, nothing taken)"` (**prey here, couldn't land
  it**);
- and a hull lost to a patrol is enforcement heat at a position.

So the guild does not need to be told where the traffic is. It needs its own
returning members' hunt outcomes recorded **with position**, which is the
identical incident record §4c already defines. This is the same upgrade as
before: `profitless_streak` / `backoff_factor` is a global governor with no
spatial axis; positioned outcomes give "that lane is finished, try the other
one" instead of "the guild is discouraged."

Note the asymmetry in what heat can be built from — a pirate cannot read a
patrol's warrants or its routes. It knows enforcement only by having been
interdicted, chased, or having lost a hull. That means pirate heat maps lag
patrol movement badly, which is correct and is the pirate's actual risk.

### Each director's map is built only from its own members

This is the honesty rule doing real work rather than being a constraint to route
around. `PirateGuild._check_ins` already reads only its own members' nodes — a
radio-report fiction. Applied to incidents:

- **Traffic guild** learns a lane is dangerous because ITS haulers were robbed
  on it, or went OVERDUE on it. It cannot see Meridian's losses.
- **Patrol director** learns from what its own patrols witnessed, plus civilian
  reports notarized at its stations (§2.1b).
- **Pirate guild** learns from its own members' outcomes — took / returned empty
  / lost, and WHERE.

The result is that every director holds a **partial, biased, stale** map, and no
two agree. That is far better fiction than a shared truth table, and it comes
free from a rule already in place.

Note what this buys the pirate guild specifically: it already has
`profitless_streak` / `backoff_factor` — a global "is this working" governor
with **no spatial resolution at all**. Incidents give the same machinery a
per-lane axis, turning "the guild is discouraged" into "that lane is finished,
try the other one."

### The cargo seam already exists

`RoutePlanner._score_pair` already computes:

```gdscript
var risk: float = _risk_estimate(pickup_rec, dropoff_rec)
var score: float = payout - travel_cost - risk
```

`_risk_estimate` returns `0.0`, deliberately, with a comment naming precisely
this: *"risk comes from HEARD news, which is what lets a hauler fly into an
ambush the player already knows about"*, deferred to the mail substrate and
"kept as its own named function so the seam is obvious and a later phase changes
exactly one function, not every call site."

So "cargo avoids dangerous routes" is **one function body**. And because the
term is subtracted from a payout, avoid-vs-price-higher is not a design fork:
a risky lane simply needs a bigger payout to win, which IS pricing the risk.

Patrols read the same number with the sign flipped.

### The feedback loop, and why it self-corrects

The obvious worry with risk-weighted routing is terminal abandonment: cargo
flees a lane, the lane dies, the economy behind it starves.

It does not, and the reason is already in the economy. Postings price on
urgency — as a lane goes unserved, the destination's unmet demand rises, its
posting price rises, and `payout` grows until it once again exceeds
`travel_cost + risk`. **Somebody eventually takes the dangerous job because it
finally pays enough.** The loop is self-limiting, and it produces exactly the
fiction wanted: dangerous routes are lucrative routes.

Expect predator-prey oscillation across all three directors — cargo leaves,
pirates starve, patrols relax, cargo returns. Incident expiry is the damping
term, and its half-life is the main tuning dial for how fast that cycle runs.

## 4e. WHERE the decision is made decides what it may see

The honesty rule constrains *what a director knows*. It says nothing about
**where a decision physically happens**, and that second axis is what actually
determines whether a risk term produces the intended fiction or destroys it.

Three decision sites exist today, with three very different visibility stories:

| Site | Code | Sees | Honest? |
|---|---|---|---|
| Ship, docked | dock event → plan next leg | that station | yes — you hear the news in port |
| Ship, mid-flight | `RoutePlannerLeaf` line 81 | **the whole cluster** | no |
| Director tick | `tick(dt, cluster)` → `for rec in cluster.records` | **everything** | discipline only |

### The mid-flight re-plan is the sharp edge

`RoutePlannerLeaf` re-plans on a timer, from `actor.position`, against the live
`cluster` — so a hauler halfway down a lane already re-prices every station's
postings instantly. That is tolerable for prices (arguably a market feed). It is
NOT tolerable for risk: a hauler would divert *because* it learned the lane ahead
went bad, with no physical way to have learned it. That is precisely the
"hauler flies into an ambush the player already knows about" fiction, inverted —
the risk term would make haulers omniscient about danger rather than blind to it.

**Rule: mid-flight re-planning may use only what the ship itself senses, plus
what it carried out of its last dock.**

The implementation is **not** a snapshot — that was this document's first
proposal and it is wrong. `mail_network.md` already specifies the right one: each
ship carries a **mailbag**, `{source, version, confirmed_at}` per source it has
heard of, advanced only by strictly newer data (`max` on both holder clocks).
Mid-flight re-plan reads the ship's own mailbag rather than the live cluster.

Why the distinction matters rather than being pedantry: a wholesale snapshot
**erases** — docking at a poorly-informed station would make a hauler forget the
robbery it personally witnessed. `max` merge cannot lose information. It also
copies payloads per ship, where the real model keeps content global and clamps
reads to your delivered version — *that clamp is the fog*, and it costs one
integer per source.

### The map belongs on the station, not on the director

If the incident map hangs off a director, every member reads it instantly from
anywhere — omniscience under a new name, and the honesty rule is defeated by
where we put a dictionary.

A **station is a place**. Things arrive there; two stations hold different
things; a ship learns by docking. Hanging the map on the station record gets
fog, staleness and disagreement for free out of geometry and docking cadence,
with no fog system written. It also makes §2.1b's notarization natural — the
victim's report is co-signed *and lands* at the same counter.

### Not every director is an agent

Worth stating so this doesn't get over-applied. `station_economy.gd` walks
`cluster.records` deliberately and with a comment saying so — and that is
CORRECT. It is world bookkeeping, not a viewpoint; nobody in the fiction is
"the station economy". Traffic guild, pirate guild and the patrol director are
different: they are actors with a seat, and their reads should be constrained to
it. Applying visibility rules to the economy would be cargo-culting the rule
onto a system that has no observer.

### Where each agent-director sits

- **Traffic guild** — at its stations. Several seats, which disagree. A hauler
  planning at Coldreach uses Coldreach's map.
- **Patrol director** — at its HQ / home station. Note the consequence already
  measured: a patrol orbiting 24,000u out is *outside* its own information
  source for the whole patrol. It flies the plan it left with.
- **Pirate guild** — has NO station. Its only sync point is the den at cash-out.

That last one promotes a known bug. The cash-out failure (`vanished_near_
wormhole` needs a 10s check-in inside an 8000u ring the pirate crosses in ~11s)
is currently filed as an accounting error — booking a successful robbery as
`presumed LOST`. Under this model it is an **information** failure as well: a
pirate that never completes cash-out never delivers its positioned hunt outcome
to the guild and never picks up an updated map. Fixing cash-out is what closes
the pirate guild's learning loop, not just its ledger.

## 4f. Two tiers of transport, and what falls out of them

The transport rule, stated once:

> **News moves free and instantly between IFF kin inside mutual comms range.
> Otherwise you must physically dock somewhere that holds it.**

There is deliberately **no middle tier** — no slow trickle, no partial range
falloff. That binary is what makes distance mean something: either you are in
the net or you are flying on what you left port with.

**The two tiers are the same operation.** Worth stating up front, because it
collapses what reads below like two mechanisms: both are a per-source `max`
merge of mailbags (§4e). Kin-relay and dock-merge differ only in *who* you are
allowed to merge with and *how often* — continuously for crypto-kin in range,
once for whoever you tie up next to. There is one merge function in the whole
model, and "news reaches you" and "news happens to you" are also the same thing:
a ship is a source, and witnessing something advances the log it alone writes.

### The pipe already exists

This is not a new system. `ship.gd`'s `datalink_relay` already does exactly
this, at `DATALINK_RELAY_HZ = 15.0` (~100ms — instant at human scale):

```gdscript
var link_range = min(self_comms_range, their_comms_range)   # mutual, not mine
if dist > link_range: continue
...
if not _iff_tags_overlap(iff_tags, s.iff_tags): continue    # crypto-kin only
```

plus a LOS gate. It carries contacts today and warrants already. **Incidents /
news are a third payload on a working pipe.** `merge_warrant`'s monotonic
latest-wins is the merge model to copy.

### Sync points per faction — the asymmetry IS the faction design

| Faction | Where news refreshes | Density |
|---|---|---|
| Cargo | any station it docks at | frequent, everywhere |
| Patrol | HQ check-in, + kin relay while on station | periodic |
| Pirate | dens, at cash-out | sparse, hidden |

Cargo is the best-informed faction and can act on it least (it can only avoid).
Pirates are the worst-informed and are hurt most by it. Patrols sit between and
their responsiveness is bounded by **rotation cadence, not report latency** —
a patrol 24,000u out is outside its own information source for the whole orbit,
and flies the plan it left with. Kin relay means a patrol *pair* shares
instantly while the pair as a whole stays stale, which is the right texture.

**Multiple pirate dens** then become the guild's actual infrastructure — more
dens means fresher news and shorter exfil, which is a thing to build, lose, and
have raided, rather than a number on a director.

### Looting the mailbag

§4e proposes a hauler carry a map snapshot out of its last dock. That snapshot
is **cargo**, and `TAKE_ALONGSIDE` can take it.

This is the best feature in this section, for several reasons at once:

- it gives pirates a second feed that is **opportunistic rather than
  infrastructural** — earned by robbery, not granted by a director;
- stolen news is *someone else's* news: stale, and biased by that hauler's
  route. It is honest by construction;
- a single take tells the pirate where the OTHER haulers were going — a prey
  density map from one robbery, which is exactly the feed §4d wanted;
- it gives a reason to rob a ship carrying nothing you want, which the current
  take (no cargo model at all) badly needs;
- and it makes the well-connected hauler the valuable target, which is a nice
  inversion of "rob the richest".

### Competing bands under one flag — free, from the existing sets

`iff_tags` is a SET and `transponder flag` is a separate public field. Two crews
that both `set_transponder_flag(FLAG_PIRATE)` while holding disjoint tags
(`TEAM_RED_BAND` / `TEAM_BLUE_BAND`) **already cannot relay to each other** —
`_iff_tags_overlap` simply fails. Nothing needs building for the isolation; it
is the default, and today's single-band setup is the special case.

So: rival bands fly the same colours, compete for the same lanes, sync only at
their own dens, and the player cannot tell them apart from outside. All of that
is emergent from a set intersection already in the hot path.

The same mechanism answers the Home-vs-Meridian patrol question from §3: two
legitimate authorities with disjoint tags do not share news, which is *why* they
can hold different beliefs about the same event without anyone being wrong.
One rule, both cases.

Open, deliberately not decided here:

- **Do rival bands read each other as hostile?** Without tag overlap they fall
  through to flag-based classification, and both read `FLAG_PIRATE`. Whether
  that is HOSTILE (bands fight) or merely not-friendly is a real design choice
  with real consequences, not an implementation detail.
- **Is stolen news attributable?** If it carries the victim's identity, holding
  it is evidence — which makes a captured pirate's data a prosecutable thing and
  gives patrols a reason to board rather than destroy.
- **Are dens discoverable?** They must be, or they are not infrastructure.

## 5. Suggested order

> **Superseded — now scheduled.** This sketch has been turned into milestones in
> [implementation_plans/m57_m61_information_economy_roadmap.md](../implementation_plans/m57_m61_information_economy_roadmap.md)
> (M57 incidents → M58 transport → M59 risk-aware routing + patrol director →
> M60 pirate information economy → M61 competing bands). That document also
> carries the **verified-claims table** — the fifteen facts about the existing
> code that §4c–§4f rest on, each with a file:line, so they can be re-checked
> rather than re-remembered. The order below is kept because its reasoning still
> holds and M57/M59 follow it.

1. **Overdue detection in the traffic guild.** Uses only data already recorded,
   needs no new mechanism, and produces reports without depending on a
   surviving witness.
2. **The incident report object + courier delivery** at the docking hook.
3. **Patrol director** consuming the inbox.
4. **Lane response job**, and only then tune latency and sweep radius.

Deliberately last: making patrols good at catching pirates. Piracy currently
lands roughly zero takes in the campaign for reasons that have nothing to do
with enforcement, so tightening enforcement first would tune against a system
that is not yet functioning.
