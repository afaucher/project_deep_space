# The station economy

The substrate under demand-driven traffic (M53c), contracts (M54), physical
cargo (M55), and the Mail Network's fog
([mail_network.md](mail_network.md)).

Written because M53c's first scoping pass reached for a director-side
`service_rate` scalar — a number with no referent, tuned until the traffic
looked plausible — which exposed that the game has **no economy at all**: no
stocks, no commodities, no production, no prices, no money anywhere in
`scripts/`. (`role` — "hub"/"outpost" — is authored on every station and
consumed by nothing.)

This doc defines the smallest model that is *honest* (every number means
something), says who makes decisions and on whose behalf, and stops well short
of a market simulation.

## Principles

1. **The economy is world state on STATIONS, not state in a director.** A
   director-internal demand scalar cannot be seen by the player, cannot be paid
   for, forces M54 contracts to invent a second parallel notion of "what a
   station wants", and gives the Mail fog nothing real to be stale *about*. Put
   it on the stations and one model feeds NPC dispatch, player hauling, contract
   payouts, prices, and the fog.
2. **Nobody optimizes globally.** There is no central planner and no
   cluster-welfare objective. Every decision-maker acts on its own interest with
   its own partial information. See "Who decides" below — this is the principle
   the first draft of this doc violated.
3. **The inefficiency IS the gameplay.** If some optimizer ran the economy well,
   every station would be adequately served and a hauler-for-hire would have
   nothing to do — a well-run economy designs the player out of a job. The goal
   is a plausibly *badly*-run economy whose badness has readable reasons.
4. **One source of truth.** If two systems disagree about what Refinery Prime
   needs, the bug is that there are two systems.
5. **Abstract until M55.** Quantities are scalars, not manifests. A delivery is
   an EVENT (a dock), not a cargo transfer. M55 makes it physical without
   changing the model's shape.
6. **Legible over accurate.** A player should be able to reason about why
   traffic goes where. A handful of numbers with obvious meanings; no hidden
   multi-variable simulation.
7. **Fog-ready by construction.** Anything a party "knows" must be derivable
   from something observable — a posting it heard, a registry it read, a hail.
   **You cannot see a stockpile from space.**
8. **The decision must live where the information lives.** Stations know their own
   stock, so stations price. Ships know where they are and what they have heard, so
   **ships route**. Owners know their finances and risk appetite, so owners set
   policy. A decision made at a level that does not hold the information requires
   magic to get it there.

   This principle was earned three times over — every draft that put a decision
   *above* its actor smuggled in information the actor should not have had:
   demand as a director-side scalar (stations own that), a global optimizer over
   cluster welfare (nobody holds that objective), and operator-side fleet dispatch
   (needs instantaneous command of a hull 400k away). If a rule here looks wrong,
   check this principle first.
9. **Need and terms are separate.** `urgency` is the objective state of a need and
   is never modulated by politics; **price is a policy applied on top of it**, and
   may depend on who is asking. "The state fleet carries local mail for nothing" is
   `policy_multiplier(own_flag) = 0`, not a different kind of need.

## Simulation depth (decided: depth 2 with clamps)

The ladder, and why we sit where we do:

| | Adds | Unlocks |
| --- | --- | --- |
| 0 | static sources/sinks, plausible manifests | observability, nothing else |
| **1** | stock is **mutable** | **the world can be wrong** → fog, consequence, contract reasons, player participation |
| **2** | + rates (stock drifts on its own) | need *renews*; neglect is visible; time matters |
| 3 | + prices | runs comparable by margin; trader gameplay |
| 4 | + credits | budgets, affordability, wealth |

**Depth 0 is foreclosed by the mail vertical.** If nothing varies, nothing can
be out of date, so stale mail is harmless and directors cannot make interesting
mistakes. Mail is a game about the map differing from the territory; depth 0 has
no territory, only a map that generates itself on demand.

**Depth 2 with hard clamps and no failure states** is the decision: stock varies
and rates tick, but stock clamps to `[0, capacity]` and *nothing bad happens at
the boundaries* — a starved outpost sits at zero being extremely urgent, a full
ore bin simply stops accumulating. That defers the question we're not ready to
answer ("can the cluster permanently lose a station?") while unlocking
everything the later verticals need. Starvation consequences become **content**
added later, not a system owed now.

The 0→2 step is cheap: authoring "Slag Bay produces ore, Refinery Prime consumes
it" is work you do at *every* depth. Depth 2 adds two numbers per
station-commodity on top. The real cost is balance and consequences, which the
clamps defer.

## The commodity classes, and the cluster's economic shape

**The Sovereign Drift is a resource frontier that EXPORTS.** It ships product out
through the Nexus wormhole and takes supplies back in. Ironhold — 35k from the
wormhole — is the **port of export**, which is finally *why* every authored lane
terminates there.

### Four classes, because "supplies" was doing too much work

An earlier draft had Ironhold *producing* SUPPLIES, which labels a **wormhole
import as production** — the same error as `service_rate`. It also fails on
volume: 9 lots/hr of life support through one wormhole is a supply line no
frontier could sustain. **The cluster must make most of its own survival goods.**

What settles the split is not realism but *what a blockade does*:

- If the cluster **imports its air**, cutting the wormhole kills everyone in days.
  That is a fail screen, not a game state — the chokepoint is too sharp to play with.
- If the cluster **imports its machinery**, a blockade means *decay*: ships go
  unrepaired, stations degrade, growth stops. Slow strangle, fully playable.

**Decided: self-sufficient in survival, dependent for technology.**

| Class | Source | Role |
| --- | --- | --- |
| **ORE** | mining outposts (parked ON asteroid fields) | the export product — *why the cluster exists* |
| **VOLATILES** | **Coldreach** (ice) — the name is the tell, as with Refinery Prime and Drift Market | life support: water, air, propellant — *survival, locally sourced* |
| **REFINED** | Refinery Prime, from ore | structure and parts — *why the refinery matters* |
| **GOODS** | **imported only**, via Ironhold | machinery, medicine, tech — *why the wormhole matters* |
| **RARE** *(M53d)* | **Meridian only** — Halvorsen Claim, Corvus Yards | exotics, consumed by nobody here — *why Meridian is a peer, not a client* |

Five, each doing a distinct narrative job; dropping any one loses something real.
RARE is the odd one out by design: it has **no domestic consumer at all**, so
every lot exists to leave. That is what makes it an income rather than a
utility, and it is also what makes it *weak* leverage — home does not need it,
so home can close the gate for free. See
[../implementation_plans/m53d_meridian_sovereignty.md](../implementation_plans/m53d_meridian_sovereignty.md).

```
                        Nexus wormhole
                          ^        |
                   ORE out|        |GOODS in  (bulk out, concentrate in, ~3:1)
                          |        v
  Deepcut ---\         [ IRONHOLD ] ------- the beacon road -------> Drift Market
  Halvorsen --> Refinery Prime                                          |
                    |REFINED (local use)                                v
  Coldreach --\                                                      Slag Bay
  Slag Bay ---->  raw ORE  -> Ironhold
  Corvus -----/
     ^
  Coldreach also = the ONLY VOLATILES source -> everyone
```

### The geography sorts itself

Two feeder patterns emerge purely from distance — nothing authored:

- **Refining district (south).** Deepcut is **108k** from Refinery Prime and
  Halvorsen **362k** (closer than Halvorsen→Ironhold's 382k). Their ore refines
  locally; the refined goods serve the cluster.
- **Raw export flow (north/east).** Coldreach (228k), Slag Bay (372k) and Corvus
  Yards (453k) are all far nearer Ironhold than the refinery (528k / 565k /
  744k). Their ore leaves **raw** through the port.

A frontier exporting raw ore and refining only what's economic is exactly right,
and it makes Refinery Prime's authored position meaningful rather than arbitrary.

### Three existing world features get their reason

- **The beacon road exists because it is the supply line to Drift Market** —
  408k, the cluster's longest lane, carrying supplies east and ore west. That is
  why it is the surveilled corridor.
- **Drift Market is the eastern regional depot**, not a second wormhole gateway:
  it takes supplies down the road and redistributes to Slag Bay (172k away, far
  closer to Drift Market than to Ironhold).
- **Refinery Prime stops being absurd.** It currently has zero traffic, which is
  nonsense for a refinery.

**Lanes EMERGE instead of being authored.** A hauler running outpost → port
carries ore out and supplies back — which is exactly why the existing cargo
behavior loops.

### The strategic consequence: the wormhole is a chokepoint

The cluster now **depends** on wormhole traffic. Cut it and supplies stop and
everything starves; the export flow is also the cluster's income. That makes
pirates operating near the Nexus an existential threat rather than a nuisance,
and it gives the world a single legible health metric — **lots/hour through the
wormhole**.

An unresolved knock-on: the outposts' nearest neighbours cross the sovereign
seam. **Corvus Yards (Meridian) is 226k from Coldreach (home)** but 453k from
Ironhold — the two peripheral colonies of *different* states are each other's
closest neighbours. Cheapest routing wants a cross-flag lane there. Left as a
hook, not a decision.

## The state

Stock is keyed by **(location, holder)**, not by station. A station is simply the
holder that happens to own the port; a private company with a warehouse at that
same station is another holder in the same shape. Get this wrong and party-held
stockpiles, hoarding, speculation, and competing prices at one port are all
foreclosed (trap 5 below).

### The bin — per (holder, location, commodity)

- `stock` — current abstract quantity (**the only thing that varies**)
- `capacity` — bin size
- `target` — the healthy level
- `surplus_line` — above this, the holder wants the excess gone

Note what is **not** here: a `rate`. See "Converters" below — an authored net rate
was the same smell as `service_rate`, a number standing in for a mechanism.

Everything else derives. The one number the rest of the game reads:

```
urgency(holder, location, commodity) -> (direction, 0..1)

  stock < target        ->  IMPORT urgency: (target - stock) / target
  stock > surplus_line  ->  EXPORT urgency: (stock - surplus_line) / (capacity - surplus_line)
  otherwise             ->  satisfied; no posting
```

**Direction keys off STOCK** (corrected twice). An earlier draft derived direction
from the sign of an authored `rate`, which made it impossible for a station to
flip: Ironhold *normally* imports volatiles, but once **over-served** it wants the
surplus gone. Stock is what says which way a holder currently *wants*.

## Converters: throughput is derived, not authored

**An authored per-station `rate` is a fudge factor.** Refinery Prime consuming
3.3 ore/hr is not a property of the station — it is *what happens when a converter
runs*. Authoring it as a constant means the causal chain cannot exist: run out of
ore and the number keeps ticking.

So the station's `"self"` entry authors its **industry**, not its rates:

```gdscript
"converters": [
    { "in": {"ORE": 3.3}, "out": {"REFINED": 2.2}, "rate": 1.0 },
]
"sinks":   {"VOLATILES": 0.45}   # population upkeep -- a genuine constant
"sources": {"ORE": 1.5}          # SCAFFOLDING -- stands in for mining traffic
```

### Stalls propagate in BOTH directions

Achieved throughput per tick is:

```
achieved = min(rate, input_availability, output_headroom)
           ... running PARTIALLY, scaled to the scarcest input (decided),
           but zero below a floor fraction so a converter never trickles at 3%
```

- **STARVED** — no ore; the refinery goes cold.
- **BLOCKED** — the refined bin is full because nobody is hauling it away. The
  refinery *also* goes cold, therefore stops consuming ore, therefore ore backs up
  at the mines, therefore mining stops.

Backpressure upstream and downstream, from one rule.

### The two stall states are two different pieces of news

*"Refinery Prime is cold — no ore"* and *"Refinery Prime is backed up — nobody is
hauling refined"* are **different problems with different fixes**, and both are
facts a station knows about itself. So both are postable and mailable, at different
values to different buyers.

A player who knows *which* stall is happening holds genuinely actionable
information that a player who only knows "refined is scarce" does not. That exists
only because a stall is a **state**, not a number quietly trending down.

### A stalled converter consumes NOTHING (decided — keep it simple)

A converter draws only its declared inputs, and only in proportion to what it
actually achieved. Stalled means zero in, zero out. No idle draw, no upkeep rule,
no second concept.

**Sinks are a separate mechanism and never stop.** The station's *population* keeps
requiring volatiles whether or not any industry is running. So a station with a
cold refinery does keep draining volatiles — because its people do, not because the
refinery does.

That distinction matters: an earlier draft gave the *converter* an idle upkeep of
volatiles, which conflated two unrelated mechanisms to produce an effect the
population sink already produces on its own. Same outcome, one fewer rule.

### `sources` is scaffolding — build the seam now

Ore and volatiles will eventually be restocked by **mining ships**, so `sources` is
explicitly temporary. What matters is that the fake uses the same entry point a
real delivery will:

```gdscript
deliver(holder, commodity, amount)   # the ONLY way stock increases
```

The fake calls it on the economy tick; a mining ship later calls it from the same
`docking_bay` DOCKED hook haulers already use. Deleting the fake is then a one-line
change rather than a restructure.

**Mining ships are a second traffic class** (later scope, flagged so the seam stays
clean): field↔station short hops are nothing like station↔station hauls — short
range, defenceless, clustered on the fields. And they are the **bottom** of the
supply chain, so killing them is the deepest possible attack.

### The cascade is wanted, and it self-heals

> lose a mining ship → refinery stalls → haulers arrive to find no refined to ship → …

That chain is the point, not a hazard. It terminates rather than spiralling into a
dead world: a starved refinery's ore urgency climbs, raising the ore price, pulling
haulers onto the ore lane, restarting it.

**The one real deadlock is circular** — repair needs REFINED, REFINED needs ore
hauled, hauling needs unbroken ships. If every hauler were damaged with no refined
anywhere, nothing could recover **except that `TrafficGuild`'s population floor
spawns fresh, undamaged hulls.** So the floor is the deadlock breaker. Recorded
because nobody designed it for that, and it could be "optimised" away by someone
who doesn't know it is load-bearing here.

### What the reference table becomes

The 8×4 rate matrix below stops being an *input* and becomes the **expected steady
state** — a far better test oracle than a set of authored constants, since
throughput is now bounded by real inputs and cannot be authored inconsistently.

### The secondary market falls out of that flip, for free

Over-service creates export urgency, so an over-supplied station posts to have the
surplus **removed** — and the existing "both ends pay" rule funds the move (the
surplus holder pays for removal, the deficit holder for receipt). **No capital
required and no new mechanism.**

Two consequences:

- A **two-tier market** emerges. The primary market at a producing station may be
  restricted (see eligibility, below — Coldreach could allow only locally-flagged
  hulls to carry volatiles), but the restriction stops **at the source**: once the
  goods are in Ironhold's bins they are Ironhold's to sell to anyone. The open
  secondary tier is the one the player can always work.
- **Arbitrage works at depth 2.** Moving surplus from over-served to under-served
  is a trade on urgency *spreads*, so this partially retracts the earlier claim
  that trader gameplay needs depth 3 prices — urgency differentials already *are*
  a spread. Credits are only needed to **buy and hold** rather than be paid to move.

### Negative feedback by construction

Delivering to a station raises `stock`, lowering its import urgency; hauling ore
away lowers `stock`, lowering its export urgency. Both directions self-correct,
so traffic **rotates** instead of collapsing onto one station.

(The rejected first model — "route toward stations with high dock counts" — had
the opposite sign. Dock count measures service already *rendered*; routing
toward it causes docks there, which is positive feedback. It would have made the
world more monotonous than the fixed lanes it replaced. **Write the
anti-collapse test first**: over N passes, every eligible station is served at
least once.)

### One lot must be small relative to a need

A lot (= one hauler-trip) has to be a fraction of a station's requirement, so
that **several ships can work the same run**. Refinery Prime's 16-lot deficit
against a 1-lot hull means 3–4 haulers on that route continuously — the right
ratio. This also dissolves the "herding" worry: if a need is bigger than one
hull, five ships converging is just freight.

So a posting carries a **quantity that depletes as it's served**, not an
exclusive claim. Convergence self-limits; the ship arriving after the need
closes eats the loss (see planning risk, below).

## Worked reference case — the home cluster

**This is an ORACLE, not an input.** Under the converter model above, net flow per
commodity is *derived* from industry, sinks and sources — so this table is the
**expected steady state** the sim should settle to, and it is what Phase A's tests
assert against. (It is a better oracle than authored constants precisely because
throughput is bounded by real inputs and therefore cannot be authored
inconsistently.)

Net flows in lots/hour. **Ore extraction is not invented** — `home_cluster.gd`
already authors 32 / 22 / 18 / 18 / 15 rocks per asteroid field, so Slag Bay
out-produces Deepcut by 2× because its field genuinely is 2× bigger. Reading a fact
the world already has is the difference between a model and a fudge factor. Note the
`sources` rows are **scaffolding** standing in for mining traffic.

Coldreach's 22-rock field reads as ice-rich (mostly VOLATILES, little ORE);
yield-per-rock stays consistent with Slag Bay's.

| Station | Role | ORE | VOLATILES | REFINED | GOODS | RARE |
| --- | --- | --- | --- | --- | --- | --- |
| **Ironhold** | port of export/import | **−0.8** *export sink* | −0.60 | **−2.10** *0.50 upkeep + 1.60 export* | **+1.85** *import source* | **−0.65** *export sink* |
| **Drift Market** | eastern depot | — | −0.50 | −0.50 | −0.30 | — |
| **Refinery Prime** | refinery | −6.6 *refining feed* | −0.45 | **+4.40** *only source* | −0.40 | — |
| **Coldreach** | 22 rocks, ice-rich *(Meridian)* | +0.6 | **+3.20** *only source* | −0.25 | −0.20 | — |
| **Slag Bay** | 32 rocks | +3.2 | −0.40 | −0.25 | −0.20 | — |
| **Halvorsen Claim** | 18 rocks *(Meridian)* | +1.8 | −0.22 | −0.25 | −0.15 | **+0.40** |
| **Corvus Yards** | 18 rocks *(Meridian)* | +1.8 | −0.21 | −0.20 | −0.10 | **+0.40** |
| **Deepcut** | 15 rocks | +1.5 | −0.22 | −0.25 | −0.15 | — |
| | **net surplus** | **+1.50** | **+0.60** | **+0.60** | **+0.35** | **+0.15** |

**The net row is a surplus, not a zero — and that is the whole M53d correction.**
The original table balanced every column to exactly 0.0, which reads as elegant
closure and was in fact a bug: an EXPORT posting only opens above `surplus_line`,
and a producer running at exactly 100% of demand never accumulates surplus, so
REFINED and GOODS could never be hauled anywhere at any fleet size. Cargo in
flight is a permanent deficit too, which a zero-margin system has no spare
production to refill. Every column now carries ~16–23% margin, and that margin is
precisely what leaves on the Nexus hauler.

The cells that are *conduits outside the cluster* are all Ironhold's: REFINED and
RARE are **sinks** (leaving), GOODS a **source** (landing). Note that ORE export
collapsed 5.6 → 0.8 — the cluster used to ship out more unprocessed rock than it
refined, which is a colony rather than an industrial base, and because an export
sink bids at full urgency like any consumer it beat Refinery Prime to a supply
that exactly covered both. The refinery now runs at the scale the ore supports
(6.6 in / 4.4 out) and **refined is the main export**, bound for the shipyard in
the next cluster.

**Capacity check (why the numbers aren't arbitrary).** CargoShuttle cruises at
700 u/s, so trips are real: Coldreach 5.4 min from Ironhold, Refinery Prime 7.4,
Slag Bay 8.9, Drift Market 9.7, Corvus Yards 10.8; Deepcut→Refinery Prime is just
2.6 min. With docking, round trips run 12–24 min, so ~8 haulers deliver roughly
**22 lots/hour** fleet-wide against a **15.5 lots/hour** baseline — about **30%
headroom**, which is the slack repair surges eat into. Through the Nexus: 5.6 out,
1.5 in, so roughly **3:1 outbound by volume** — bulk out, concentrate in, the
classic frontier trade. Net **exporter by volume, importer by value.**

## Repair closes the loop: damage becomes demand

The hook already exists. `Ship._process_repairs` ([../scripts/ships/ship.gd](../scripts/ships/ship.gd))
restores `REPAIR_RATE * delta` HP per component, currently free and unlimited.
Gate it on the host station's stock and combat feeds the economy. And because
**stations ARE Ships** (they carry `ship_components` — how the station-physics bug
once hid), station self-repair is the *same code path* as repairing a docked ship:
one mechanism, one ledger.

The component taxonomy is already in the data (`c["type"]`), so the split needs no
new fields:

| Damaged component | Draws | Rate |
| --- | --- | --- |
| `hull` | **REFINED** | 1 lot ≈ 500 HP |
| `reactor`, `engines`, `comms`, `sensors`, `weapons` | **GOODS** | 1 lot ≈ 150 HP |

**Systems cost ~3.3× more per HP than structure** — you can weld plate on a
frontier, you cannot fabricate a sensor array. That falls straight out of GOODS
being the scarce import, and it creates a real tactical asymmetry: hull damage is
cheap, systems damage hurts.

Worked, on the CargoShuttle (600 HP hull / 220 HP systems) at 50% damage: 300 HP
hull → **0.6 lots REFINED**; 110 HP systems → **0.73 lots GOODS**. Note which
binds — **GOODS**, the thing that only arrives through the wormhole. Patching up
after a fight reaches all the way back to the Nexus.

A station is a different order of magnitude: a medium station taking ~1800 HP of
structural damage is **~3.6 lots of REFINED**, roughly **1.6 hours of the entire
cluster's refined output**. Damage does not merely degrade a station — it
*reprices the whole cluster* for hours.

**No stock means no repair.** A station out of REFINED cannot fix your hull; you
wait for a delivery or fly elsewhere. That is the most direct, diegetic way the
economy touches the player.

### Three chokepoints, three different failure modes

None of this was authored — it falls out of the resource assignment:

| Node | Monopoly on | Cutting it means |
| --- | --- | --- |
| **Coldreach** | VOLATILES | no life support, no substitute, no import path — the *worst* loss |
| **Refinery Prime** | REFINED | nothing in the cluster can be structurally repaired |
| **Ironhold** | GOODS import + all export | slow decay: systems unfixable, income stops |

"Which station is worth defending" finally has different answers depending on what
you are afraid of.

**All three are currently home's** — which makes Meridian a total dependency and
the jurisdiction seam decorative. That is deliberately deferred to
[../implementation_plans/m53d_meridian_sovereignty.md](../implementation_plans/m53d_meridian_sovereignty.md)
(leading proposal: Coldreach is Meridian too, a one-line flag change that makes
the border contiguous and the leverage mutual). **The commerce mechanism below
does not depend on that balance.**

## Who decides, and on whose behalf

| | Owns | Cannot |
| --- | --- | --- |
| **Station** | truth about its own stock; the **posting** (converting private need into a public offer at a price); admission via port control; its registry | know who's coming |
| **Ship** (independent / player) | where it goes, what it takes, when | know anything it hasn't been told |
| **Fleet operator** (office, private company) | hulls, and absorbing planning risk for them | see past its own stale mail |

**Stations own state and offers; ships own movement.** Neither can perform the
other's job, neither needs the other's internals, and the **posting is the only
thing that crosses between them** — which is also the thing that travels as
mail. That's why the seam is in the right place.

A station's decisions are narrow but real, and they are the only ones it makes:
**urgency** (objective, from its own stock), **price policy** (what multiplier
applies to *whom*), and **eligibility** (who may take which posting at all). It
never decides who comes.

Agency is therefore three-sided, and each side holds exactly the information its
decision needs (principle 8): the **station** prices, the **ship** routes, the
**owner** sets policy. The player uses the ship interface, unmodified.

**Port control is already load-bearing.** A station's existing grant/refusal
machinery is how it controls *who it deals with* — a HOSTILE ship gets no dock,
so it cannot take that station's postings. Standing becomes an economic
instrument with no new code.

## Interstate commerce: pools are per-station, flag gates access

**Cross-flag sourcing is WANTED** (decided) — a ship under one flag visiting a
neutral state to source materials is traffic this model exists to create. The seam
only means something if ships routinely have to cross it, so the goal is not that
each sovereign is self-sufficient but that **none is**.

The key simplification: **flag does not partition inventory.** A station's stock is
its own; there is no "home REFINED" versus "Meridian REFINED". Flag gates *access
to the transaction*, through three gates of increasing subtlety:

| Gate | Mechanism | Exists? |
| --- | --- | --- |
| **Admission** | port control grants/refuses docking by standing | **yes** — `port_control` already does this |
| **Eligibility** | a posting may be flag-restricted (domestic-only work) | new: one field |
| **Price** | surcharge or discount by the server's flag — a tariff | new: one multiplier |

Preference lives in **price, not prohibition**; refusal stays reserved for HOSTILE.
That is the M53a lesson applied — a hard ban makes the seam invisible, a surcharge
makes it visible *and permeable*. A foreign hauler docking for volatiles is then
ordinary commerce: admitted because NEUTRAL, eligible because life support is not
restricted, paying a foreign-flag surcharge. The seam gets exercised every trip.

**This is also the second structural gap to avoid:** flag must be a weighting on
*postings*, not merely a tag on the record. Without it a foreign hauler serves a
domestic posting frictionlessly, which quietly undoes the per-flag traffic
decision.

## Routing: EVERY ship plans for itself; ownership is policy

**Decided, and it replaces an earlier "operator dispatches its hulls" design.**
There is ONE planner, on the ship. Ownership does not choose routes — it supplies
**constraints and duties** the ship's own planner obeys.

```
score(posting) = offered_price(posting, THIS ship)   <- what the station will pay ME
               - travel_cost(from where I am now)
               - risk_estimate(route, as I understand it)
```

Note there is no `flag_affinity` term. It was doing two jobs badly, and both moved
to where their information actually lives (see principle 8):

| Concern | Lives on | Expressed as |
| --- | --- | --- |
| what I'll pay *you* | the **station** | `policy_multiplier(server)` — zero-rate own flag, surcharge foreign, embargo |
| what you may / must do | the **owner** | constraints (allowed flags, risk ceiling, range from base) **+ duties** |

**Duty is what affinity was faking.** A state hull doing unprofitable domestic work
is not weighting its score — it is *obligated*. "Ironhold expects its own fleet to
carry local mail" is a must-serve clause, not a soft preference, and the owner
absorbs the cost (consistent with owners absorbing planning risk everywhere else).

### Why ship-side planning, not operator dispatch

The earlier design had an operator scoring postings and assigning a hull that might
be 400k away. **That silently requires instantaneous command and control**, which
contradicts "information travels at hull speed" — a latency exemption for fleet
orders. Ship-side planning has no such gap: a ship decides *where it is*, with
*what it has heard*, and nothing needs to reach it.

It gets better as a consequence: **ownership policy is itself something that
travels.** An owner who learns a lane went hot cannot recall a hull already out
there — it can only update the policy where its word reaches (a base, an office, or
by mail). So company hulls fly into danger on **stale orders**, by the same
mechanism as everything else, with no special case.

What this deletes: the greedy-per-hull assignment loop, reserve-within-fleet
quantity bookkeeping, deterministic hull ordering, and the whole operator-side
"which of my ships goes where" pass. The re-plan leaf on the ship becomes the only
planner. Two company hulls may now plan for the same posting — fine, and honest:
without instant coordination a real fleet does duplicate effort.

### The owner's job, then

- holds the hulls, so losses cost it
- sets the policy they carry: risk ceiling / routes off limits, which station flags
  they may visit, range from base, and **duties**
- updates that policy where its word can reach
- **buys mail and stages it** at stations where its hulls call — so the fleet's
  picture is *purchased*, never innate. Those staging points are **offices**:
  physical, and therefore infiltratable or removable. This is the same primitive as
  the pirate informant network in [mail_network.md](mail_network.md), which is the
  third instance of "one system, different access rules" — that instruction now has
  real weight.
- publishes its own postings (subcontracting) and pays
- **a fleet is an information network.** More hulls calling at more ports = a better
  picture, earned rather than granted. That is the honest scale advantage.

"Declining dangerous work" is now a line in the policy rather than a withheld
assignment — same emergent outcome (the posting stays up and bids toward an
independent), expressed as data instead of a control loop.

### Crisis drives interstate commerce

A foreign station under stress raises its urgency, hence its price, until the offer
beats a hull's domestic alternatives — so a stressed neighbour pulls *more* foreign
traffic. And a private carrier's lack of flag constraints is worth most exactly
when relations are worst.

**Protectionism is a luxury of the well-supplied.** If eligibility and pricing
policy both respond to urgency, Coldreach runs "locals only, cheap" when
comfortable and drops the restriction in a crisis because it needs throughput at
any flag. Two dials — who is eligible, and what multiplier they get — both keyed to
the urgency that already drives everything else.

### The niche this protects, without designing one

A fleet constrained to home ports **structurally cannot gather foreign data**. So a
state fleet must *buy* foreign port information, and the only sellers are hulls
willing to cross the seam. The independent's edge is not better stats — it is **not
being bound** — and it emerges from two unrelated rules (flag constraints and
information markets) rather than from a carve-out.

## Postings are the universal coupling

One data type: *who's offering, what's wanted, where, how much, quantity
remaining.* **Anyone can publish. Anyone can serve.** This is the commitment
that makes new parties cheap, and it is a *data-shape* decision — cheap now,
expensive to retrofit.

The entire contract taxonomy from the mail vertical collapses into it:

| Contract | As a posting |
| --- | --- |
| pay per mail delivery | deliver X to Y, paying P |
| pay to locate a missing ship | report the position of Z, paying P |
| pay for cargo escort | accompany Z on route R, paying P |
| pay independents for risky runs | *an owner's policy forbidding it, leaving the station's posting up* |
| pay for salvage | recover the wreck at W, paying P |
| pay bounties on pirates | kill/capture Z, paying P |
| **stock/price data fresher than X** | sync any source older than X, paying P (see Information, below) |

Seven features, one data type. If they are seven systems, adding a party means
touching seven; as one board, adding a party means adding a publisher, a server,
or both.

**Reuse note:** `ContractFeed` (M41) is *display-only* — it walks active
`MissionLog` objectives into nav markers. It is not a competing offer system,
and it means a posting the player accepts can render on the nav panel for free.

## Carriers: the split is how much leeway the policy allows

Every ship plans for itself (see Routing above). What differs is **how tightly
ownership constrains the planner**, and therefore who bears the consequences:

| | Constraints | Eats a bad guess |
| --- | --- | --- |
| Company hull | tight — allowed flags, risk ceiling, range from base, duties | the **owner** (it set the policy and holds the hull) |
| Independent / player | few or none | the **ship** |

That — not payment — is the real distinction. A company hull operating inside a
narrow policy has most of its choices pre-made, so its owner carries the
consequences of those choices; an independent owns every way choosing can go wrong:
stale posting, wasted deadhead, arrived after the need closed, lane turned out hot.
**This is why subcontracting costs a premium** — you're buying someone's
willingness to carry planning risk, not just their hull. And it is why an owner
keeps routine work in-house: routine work has little planning risk to shed.

Note the asymmetry that makes a *narrow* policy expensive for the owner rather than
free: because policy updates travel at hull speed, a tightly-constrained hull far
from home is executing **stale judgement** — the owner's, not its own.

### The independent's plan: the best route I can see from here

The decision point and the information point are **the same event** — a ship only
learns things while docked, and only decides while docked. The fog shapes routing
with no extra machinery.

**The plan is a ROUTE, not a next-haul, and it is sticky (decided):**

> *What is the most profitable route I can see from here? That is my plan. I
> follow it until I get better information.*

Two properties fall out, both of them wanted:

- **Re-planning is information-triggered, not arrival-triggered.** Docking
  refreshes what you know; if nothing material changed, you keep going. A ship
  that re-planned at every dock on unchanged information would just oscillate.
- **A profitable route is usually a loop**, so ships settle into **circuits**
  rather than chasing the top of the board. This is what makes the behavior
  legible from outside — an observer (or a pirate) can learn a hauler's beat.

That last point unifies something nicely: **the authored lanes stop being
special.** Mule (Ironhold↔Drift Market) and Ore Barge (Ironhold↔Coldreach) are
simply circuits an independent would converge on anyway. The move from authored
to emergent traffic is a smooth transition rather than a cliff, and the authored
records remain a perfectly good starting state.

**Commitment is what makes planning risk real.** A sticky plan means the ship is
committed *while the world changes underneath it* — the load gets taken by
someone faster, the lane goes hot, the need closes. An agent that re-planned
continuously against perfect information would carry no risk at all; the risk
lives precisely in the gap between committing and learning.

**Hysteresis is required, not optional.** Re-plan only when a competing route
beats the current plan's *remaining* value by a margin. Without a band, small
posting updates cause thrash — a hauler pirouetting between two nearly-equal
routes, which reads as broken AI rather than as commerce. Same class of fix as
the anti-collapse and herding cases above: a rule that looks fine for one
evaluation and degenerates under repetition.

Cheap to build: a plan is just a **longer itinerary** on the existing M50 job
runner (`GO_TO` / `DOCK_AT` / `AWAIT` steps already cover every leg, including
deadheads), plus a **re-plan leaf** that fires on itinerary completion *or* on a
material information change. `build_civilian_job()` already puts `JobRunner` in a
selector, so this is one leaf ordered ahead of it. The "authority on board" is
the current plan living in the ship's own `behavior` dict — which also means it
survives the ship going dormant outside the bubble, since `behavior` already
does.

Route search should stay **shallow** (2–3 legs). Deeper lookahead against
information this stale is false precision, costs more, and produces *less*
legible behavior — nobody watching can tell why a 6-leg plan made sense.

The failure modes are the point: the load isn't there (someone got there first);
the payout is **fixed at acceptance**, not recomputed on arrival, so delivering
into a now-full bin isn't a rules argument; and an independent with nothing worth
taking drifts toward a hub, because hubs aggregate postings — giving "hubs are
busy" as a consequence of information density rather than an authored fact.

## Pricing: urgency IS price discovery

Not a placeholder for price — **the mechanism**. A station that posts too low
attracts nobody, stays unserved, and its urgency climbs, so its price climbs,
until someone bites. Bidding up over time with no auction, no negotiation, no
market-clearing algorithm.

- **Price = f(urgency) x policy_multiplier(server)** (principle 9). Urgency is the
  objective need and is flag-blind; the multiplier is where every political
  decision lives — zero-rate for the station's own flag, a surcharge for foreign
  hulls, an embargo at zero. One function, one place, so politics never
  contaminates the need.
- **The station cannot price by DISTANCE, so it doesn't try.** It has no idea where
  the ships are. It posts its number (per asker) and each ship subtracts its own
  travel cost. Distance discrimination is ship-side; identity discrimination is
  station-side.
- **Price flows like mail.** A station's price is itself news, so a price you
  "know" is a price you *heard*, possibly stale. Remote price knowledge is always
  provisional, which is why the payout must be **agreed in person at the station**
  where the price is current. Flying somewhere on a remembered price and finding it
  moved is the fog doing its job, not a bug.
- **Both ends pay.** Slag Bay wants the ore gone; Refinery Prime wants it
  arrived. Payout is the sum of the two urgencies, so **a run that relieves two
  desperate stations pays roughly double** — the most valuable work is naturally
  the work that fixes two problems.
- **Mildly convex in urgency.** Linear makes everything lukewarm; strongly
  convex makes the world oscillate between neglect and stampede. Convex-ish
  keeps routine runs routine and gives genuine rescue economics at the extremes.
- **Scale stays abstract.** NPC decisions need only the *ordering* of offers, and
  ordering is scale-invariant — so no currency is required until the player has a
  wallet. Credits later multiply through without changing a decision rule.
- **Ship-side risk term.** An independent also subtracts perceived danger,
  sourced from the same fog (a lane where a hauler was lost *that it has heard
  about* reads hot). This is what lets an independent fly into an ambush the
  player already knows about.

### Geography becomes economically real, for free

With payout = `100 × (export urgency + import urgency)` against the reference
snapshot, the *same board* gives opposite answers by position:

| Run | Payout | From Ironhold | From Deepcut |
| --- | --- | --- | --- |
| Ironhold supplies → Coldreach | 156 | **net 122** | — |
| Deepcut ore → Refinery Prime | 147 | net 73 | **net 131** |
| Slag Bay ore → Refinery Prime | 172 | net 31 | **net −24** |

The juiciest posting in the cluster is *actively unprofitable* for the ship at
Deepcut. **Being already where the cargo is dominates**, which is why
independents settle into territories rather than chasing the top of the board.

And the periphery is structurally underserved: collecting Corvus Yards' ore from
Ironhold is a 906k round trip costing ~136 against a payout of 85 — **net −51,
nobody comes.** Solving for viability, Corvus's export urgency must reach **~0.94**
before a hauler will make the trip. That number falls out of the arithmetic
rather than being authored, and it is exactly where contracts and premiums should
live.

## Information is a priced commodity on the same board

A fleet operator's business depends on knowing where demand is, so it will buy
freshness: *"stock/pricing data fresher than X, for all stations."* That is a
posting whose payload is version numbers.

**Information staleness is just another urgency** — no new pricing math:

- a station's stockpile **drains** → physical urgency climbs → someone hauls
- a party's picture **ages** → informational urgency climbs → someone couriers

Same accumulate-until-someone-bites discovery, same board, same distance
discount. **The courier circuit is a haul route through information space**,
scored by the identical function.

Freshness measures **uncertainty, not content**: if Deepcut has had no docks,
`v12` is still correct — what's stale is the buyer's confidence that it's still
`v12`. So a courier arriving with `Deepcut@v12, observed 5 minutes ago` sold
something real even though nothing changed. **You get paid for confirming nothing
happened**, which is what gives a courier circuit steady value instead of making
information hauling a lottery. The mailbag mechanics and the required two-clock
merge correction live in [mail_network.md](mail_network.md).

Geography compounds here too: **Corvus Yards is chronically underserved for
cargo *and* its data is chronically stale** — same cause, two reinforcing
effects, making the far corner of the map the high-risk/high-reward zone with
nobody authoring it as one.

**Hazard:** if a party pays per sync, a courier can farm it by shuttling between
two nearby stations forever. The freshness window is the natural defence (you're
only paid for sources *past* X), but the window must be long relative to trip
times or the farm reopens. Needs an explicit test.

## Parties — and the five traps that would foreclose them

More parties is a primary goal: it is the cheapest way to make the simulation
more engaging later. Note that **not every party owns ships**, and that a
**sovereign flag can itself be a fleet owner**:

| Party | Assets | Acts by |
| --- | --- | --- |
| **A flag itself** (Drift, Meridian) | hulls + stations | setting duties on its own hulls, zero-rating its own flag's work, paying foreigners for foreign data |
| State shipping office | hulls | serving under policy |
| **Private shipping company** | hulls + **its own stockpiles** | serving without flag constraints; **hoarding and pricing its own inventory** per station |
| Smuggler | hulls + **access** | serving postings others can't (deals with parties who'd refuse a flagged hauler) |
| **Underwriter** | capital, no hulls | *paying* — losses cost it money, so it funds bounties and escorts |
| Mining consortium | stations | *publishing* aggressively |

The private company makes M53a's jurisdiction seam economically live: when
relations sour, **it is the only party that will still haul Meridian ore to a
home refinery.** A political dimension as one config rather than one system.

**Keep the seam in the data, not in a base class.** This does *not* contradict
the deferred Pass 3 skeleton extraction (see
[../implementation_plans/m53bc_traffic_guild.md](../implementation_plans/m53bc_traffic_guild.md)):
that was extracting a shared base class from divergent internals, measured and
rejected. This is making the *interface between parties and the world* be public
data. Data shapes are what you pay for retrofitting; class hierarchies can grow
once there are three examples.

What would actually foreclose more parties:

1. Station need readable only by a fleet owner (a private field, not a published posting)
2. The player special-cased instead of being another server on the board
3. "The traffic director" hardcoded as the singular economic actor
4. Politics baked into `urgency` instead of living in `policy_multiplier` — a
   station that can't quote different terms to different askers can't zero-rate its
   own flag, surcharge a foreigner, or embargo anyone
5. **Stock keyed to stations instead of `(location, holder)`** — this is the one
   I'd have walked into, having written "fields on `ClusterEntity`" as the leaning
   answer. A private owner with a warehouse at Ironhold, priced independently of
   Ironhold's own bins, is a *holder at a location*. Get it wrong and party
   stockpiles, hoarding, speculation, and competing prices at one port are all
   foreclosed.

None are hard to avoid now. All five are painful to undo.

## The three-way seam with existing directors

- **`TrafficGuild`** (exists, purpose unchanged) — owns **how many ships exist**:
  population floor, replenishment, ambient through-traffic, hard cap. Not
  economic; its current shape is right.
- **Fleet operator** (new, per party, *located*) — owns **hulls and their
  assignments**, plus declines work it won't risk.
- **Independent behavior** (light — a job-picker, not a director) — takes the
  best posting it knows about.

`TrafficGuild` decides *how many haulers exist*; the posting board decides *what
work exists*. Neither needs the other's internals.

## Piracy couples to the economy for free

A robbed hauler's delivery never lands, so the destination stays hungry, its
urgency keeps climbing, and more traffic is dispatched toward it — through the
same lane the pirate is already working. **Piracy creates demand**, with no
special-case code.

And the operator's risk assessment is fogged too: it believes a lane is safe
because it hasn't heard otherwise, sends a company hull, loses it, *then*
reclassifies the lane and stops sending its own ships — leaving the station's
posting to bid up until an independent bites. **The "dangerous work premium"
needs no premium mechanism at all**; it emerges from abstention plus
urgency-based pricing.

Watch for runaway behavior (a permanently raided lane pumping traffic forever);
`hard_cap` on roster pressure is the existing backstop.

## What is observable (the fog contract)

Stock is **private station state**. Legitimately knowable:

- the station's **docking registry** — who came, when, under what claimed flag
  (already built, M53b Pass 1)
- the station's **postings** — what it is publicly offering and at what price
- what it **says when hailed**
- inference from the above

A party's demand picture is *last heard postings + inference from the registry*.
Stale mail makes it wrong in a believable direction rather than simply
unavailable — which is what makes Mail phase 3 a gameplay feature instead of an
information blackout.

## Deliberately NOT in the first cut

- **Money / credits.** Payouts are abstract numbers derived from urgency.
- **Prices as an independent quantity.** Urgency is the proto-price.
- **Physical manifests.** M55.
- **Player-facing economy UI.** The first cut is legible through behavior (where
  traffic goes) and dialogue (what stations say).
- **Cross-cluster trade.** The wormhole is an abstract GOODS source and ORE sink.
- **A `Party` base class.** Commit to the posting shape, not the hierarchy.

## Open questions

- **~~Ironhold as transshipment~~ — RESOLVED (Ironhold is the port of export).**
  The original question assumed a closed cluster where all ore had to reach
  Refinery Prime, which made the refinery under-supplied by its neighbours and
  forced a choice between uneconomic long hauls and double-handling through
  Ironhold. Making Ironhold the **wormhole export hub** dissolves it: the refinery
  is sized to its own southern basin (Deepcut + Halvorsen), and the northern and
  eastern outposts ship raw ore straight to the port instead. No transshipment
  leg, no doubled trips. See "The commodity classes, and the cluster's economic
  shape" above.
- **~~What else does the cluster import?~~ — RESOLVED.** GOODS is that class
  (machinery, medicine, tech), and the blockade test is why it exists: importing
  *technology* makes a blockade playable decay, where importing *air* would make it
  a fail screen.
- **~~Should the cross-seam lane exist?~~ — YES, and it is now the point.**
  Cross-flag sourcing is wanted: interdependence *generates* the traffic, and the
  jurisdiction seam only means anything if ships routinely cross it. Under M53d's
  leading proposal (Coldreach is Meridian too) the shortest, highest-volume lane in
  the cluster — Ironhold↔Coldreach at 228k, already authored as record 701 — becomes
  the interstate artery.
- **Do independents arrive and leave through the wormhole based on cluster
  health?** A nice valve — a starved cluster loses its haulers, worsening it —
  but a doom loop if unclamped.
- **Does an independent ever refuse work and just sit?** If yes, a badly-run
  economy visibly strands ships at stations (great texture). If no, they always
  take the least-bad job and the world never looks broken.
- **Do outposts ever starve?** Clamps say no for now. A degrade path (distress
  call → contract → dead station) is a strong content hook needing a decision
  about whether the world can permanently lose a station.
- **Does the wormhole's GOODS source have a limit?** Unlimited means the economy can
  never truly fail; limited means an event can strangle the cluster. Also the lever
  M53d would use to make home genuinely need Meridian.
- **Where the model lives** — **note the leaning below is what trap 5 warns about.**
  Whatever the container, the KEY must be `(location, holder)`, not the station
  record, or party-held stockpiles are foreclosed. Candidates: fields on
  `ClusterEntity` (dormant-safe,
  serializable, consistent with how the cluster already carries state) versus a
  separate economy service. Leaning `ClusterEntity`, since a station's economy
  must keep ticking while outside the sim bubble.
- **Authoring vs deriving the per-station numbers.** `role` is already authored
  and unused — the obvious place to default rates from, with per-station
  overrides for the interesting cases. Cheap, and it finally gives `role` a job.
