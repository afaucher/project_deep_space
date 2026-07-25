# The Mail Network: information as a physical, latent, tradeable good

The next foundational model after the economy/piracy vertical. It retires the
last piece of omniscience in the sim — the director that "just knows" what
happened to its ships — and replaces it with knowledge that has to physically
travel to reach the mind that acts on it. That single change (information gets
a position and a velocity) turns the whole missions layer from *authored* into
*emitted by directors' blind spots*.

Parent context: [economy_and_piracy.md](economy_and_piracy.md) (the directors),
[jobs_and_itineraries.md](jobs_and_itineraries.md) §3 (the director honesty
rule this generalizes). Roadmap home:
[m48_m55_economy_piracy_roadmap.md](../implementation_plans/m48_m55_economy_piracy_roadmap.md).

## Why now / what it fixes

The pirate guild (`scripts/directors/pirate_guild.gd`) currently fakes honesty
by a narrow trick: it only ever reads its *own members'* live nodes (the
`_check_ins` pass — a "radio report" fiction) plus public geometry (wormhole,
lane routes). That was enough to avoid an omniscient AI while the guild only
cared about its own hulls. It does NOT generalize:

- A **commerce** guild needs to know about *other people's* ships (who docked
  where, what demand looks like at an outpost). There's no honest channel for
  that today — reading it globally is omniscience.
- The playtest already named the endgame (2026-07-20 note): *"we want the
  pirate guild to not 'file reports' but actually have to comm in from each
  ship… pirate contacts on various stations… finding and removing these people
  literally tears down the pirate network."* That's this doc.

The fix is one idea applied uniformly: **a director knows only what has
physically reached its location.** Everything below is the machinery and the
gameplay that falls out of it.

## The model — four parts

1. **Docking registry (per station).** Each port keeps a timestamped,
   append-only log of its own dock/undock events: `{subject_name, flag,
   station_id, event: DOCKED|DEPARTED, stamp, …}`. Ground truth, *locally*.
   The events already fire — port grants and releases exist (M46/M47,
   `port_control.gd`); today they just aren't recorded as durable news. This
   is the cheapest part and it can land first with zero behavior change (see
   Phasing, phase 1).

2. **News/mail bag = a source's log at a version.** Each *source* (a port's
   docking registry, a pirate informant feed, a sport's results desk) owns ONE
   monotonically-growing append-only log, with a per-source sequence counter it
   alone increments on every new entry. A "mailbag" is that log identified by
   source and version — *"Ironhold Port Control Docking Registry @ v412."* The
   log content is global (one canonical sequence per source); a holder carries,
   per source, only its high-water version and may read the log up to it. The
   merge is then trivial (see "The merge is just a version compare" below): no
   per-fact reconciliation, just "whose version is higher."

3. **Courier transport.** Mail rides ships and merges station-to-station *on
   dock*. This is the load-bearing twist: **information has a position and a
   velocity.** It propagates at ship-speed across the station graph, so it is
   laggy and interceptable. Datalink shares tracks at the speed of radio;
   mail shares registry facts at the speed of a hull. That latency is not a
   defect to minimize — it is the entire source of value (see Gameplay).

4. **The director as a *located subscriber*.** A guild reads the news that has
   reached *its* node(s), never a global view. Its existing decision machinery
   is unchanged — it's the same OVERDUE→(LOST | CASHED_OUT | RETURNED_EMPTY)
   state machine already in `pirate_guild.gd:184` — but now fed by mail:
   *"I expected a check-in here by T and it hasn't arrived → behind / pursued /
   presumed lost; a 'spotted destroyed' report just came in on the mail →
   confirmed lost."* The state machine is right; only its **input** moves from
   direct node reads to delivered news.

## The merge is just a version compare (the sender owns a monotonic log)

Simplification (decided): do NOT reconcile per fact. Each **source** keeps a
single append-only log with a monotonic sequence counter it *alone* increments —
single-writer, so the counter is trivially, unarguably ordered (no distributed
clocks, no conflict resolution, ever). Crucially the log **content is global** —
one canonical sequence per source, never privately-copied bundles — and a
**holder** (any ship or station) carries, per source, nothing but the highest
version delivered to it:

    held = { "Ironhold Docking Registry": 412,
             "Drift Market Registry":      88,
             "Drift Circuit Results":      37, … }

The entire model then collapses to scalars:

- **"Do I have mail for you?"** — for any source, *my version > your version*.
  O(1) per source, and you never read contents to decide.
- **"Merge."** — for each source, keep the higher version (and its log). `max`.
  That's the whole operation. Because a source's log is append-only and
  single-writer, a higher version is a strict superset of a lower one — newer
  literally *is* better, with zero per-entry logic.
- **Current state and history are the same object.** The log already IS the
  append-only history (the forensic substrate a locate/bounty contract reads);
  "current state" is just reading its tail. There is no second union rule — this
  replaces the earlier "two merge rules" framing entirely.
- **Content is global; reads are clamped to your delivered version.** There is
  one canonical log per source; a reader may see entries only up to *its own*
  delivered version and no further. **That clamp IS the fog** — no private
  content copies to keep in sync, no way to peek past what's physically reached
  you (the global store is engine storage, not a peek-hole). A holder's entire
  tier-3 knowledge is therefore a cheap, serializable, deterministic per-source
  **version vector of integers**; delivering mail = advancing the recipient's
  integer, which unlocks reading the prefix it now points at.

This **kills the multi-hop hazard outright**: the version is the *source's own*
sequence number, carried unchanged through every hop, so an intermediate carrier
can never re-stamp it fresher than it is (the exact bug M56 warns about for
contacts simply cannot arise here).

### Three clocks, not two (corrected)

The earlier framing said "two clocks" and called the frame stamp display-only.
That is right for log *entries* and wrong for *mailbag metadata*, and the
difference is load-bearing once anyone **pays** for freshness (see "Information
is a priced good", below). The clocks are:

1. **Source sequence number** (per log entry, per source) — a logical clock.
   Merge/ordering only. `max`.
2. **Entry frame stamp** (per log entry) — when that event happened. Age display
   only, never ordering. This is the M56 frame-stamp idiom, and the note in
   `ship.gd`'s `docking_registry` doc comment is correct *for entries*.
3. **`confirmed_at`** (per holder, per source) — **when this holder last synced
   that source**, regardless of whether anything had changed. NEW, and it merges.

So a mailbag is `{source, version, confirmed_at}` and **both holder-side clocks
merge as a max**:

    version      = max(mine, theirs)
    confirmed_at = max(mine, theirs)

Both are monotonic, so the merge stays order-independent and idempotent — the
property that made this model elegant survives intact.

**Why the third clock is necessary.** Version measures *content*; `confirmed_at`
measures *uncertainty*. If Deepcut has had no docks, `v12` is still perfectly
correct — what is stale is the holder's confidence that it is *still* `v12`. A
courier arriving with `Deepcut@v12, confirmed 5 minutes ago` has therefore
delivered something real even though the version did not move: it collapsed
uncertainty. Without `confirmed_at` there is no way to represent that, no way to
price it, and "nothing happened" becomes unsellable — which would make a courier
circuit a lottery that only pays when there happens to be news.

**Do not "simplify" this back to two clocks** by reading the entry stamp of the
log tail as freshness. A quiet source's newest entry can be hours old while the
holder's knowledge of it is a minute old; those are different facts and the
economy depends on the difference.

Two consequences of content being global:

- **Only an integer moves on delivery.** A hand-off just advances the
  recipient's version pointer — "how much log body rides along" is a
  non-question. Compaction (a registry grows forever) is therefore a single,
  central concern for the one canonical log — a current-state snapshot plus a
  bounded recent tail — not something every bag or holder duplicates.
- **Opacity still holds, via *whose* pointer advances.** The read-clamp is the
  same mechanism for both source classes; what differs is when your pointer
  moves. A **public feed** (a port's docking registry, sport results) advances
  *your own* read-version when you're present at the source — you read it, then
  carry it onward. A **sealed dispatch** advances only the *addressee's*
  pointer, on delivery — never the carrier's. So "Carrying is not reading"
  (below) is exactly "hauling a sealed bag doesn't move *your* integer, only the
  recipient's" — the global store never becomes a peek-hole.

## The player is a node, not an observer (decided: no player omniscience)

The player is subject to the same rule as every director: **you know only what
you've collected.** The player is not exempted "for playability" — they're just
another located subscriber who docks, reads the local registry, carries news,
and knows the wider world only as well as their last port visit and their own
sensors tell them. This is what makes the player-side contracts (courier,
locate, bounty) *mean* anything: the player operates under the same information
limits as the guild paying them.

Crucially, "no omniscience" is NOT "the player is blind" — it's a layering, and
only the third tier is fogged:

1. **Live sensor truth (real-time, local).** What the player's own sensors +
   datalink see *right now* is unrestricted, immediate, and honest — the
   existing `active_contacts` fusion in `ship.gd`. This is never taken away.
   The player always has ground truth about what's in front of them. The whole
   sensor/EM/classification game stays exactly as-is.
2. **Charted geography (static, known — scoped to the home cluster).** Fixed
   landmarks of the home cluster — hubs, beacon road, wormhole, the mining
   outposts, and the M53a peer colonies — are common knowledge the player
   starts with: **you live here.** The whole home Drift is pre-charted. This
   scope is deliberate and bounded: **past the wormhole, geography itself
   becomes discovery** (see "The wormhole is where the fog thickens" below).
   Even at home, a *deliberately hidden* claim (an off-books habitat, a pirate
   safe-house) can still be unknown until heard of — hiddenness is a property
   of the specific location, not of the cluster.
3. **World state / news (latent, collected).** Who docked where, who's overdue,
   what a bounty is worth, which lane went hot, what demand looks like at an
   outpost — this is the mail. The player knows it only if they collected it at
   a port or received it via a courier/mail merge. **This is the tier the fog
   applies to**, and it's the same tier the directors are now limited to.

Consequences that follow directly, and are therefore in-scope for this vertical
rather than afterthoughts:

- **The nav/contacts UI must distinguish KNOWN from STALE from UNKNOWN.** A
  station you haven't visited in a while shows *aged* registry info (with its
  as-of stamp), not live truth; one you've never reached shows nothing but its
  charted position. The fog has to be *legible* — the player should always be
  able to see how old their picture is. This is the UI payoff of the M56
  timestamp being an honest as-of stamp.
- **Contracts/missions are LEARNED, not globally posted.** The ContractFeed
  nav-layer markers (M41) currently just appear; under this model an offer is
  something you hear about at a port or over the mail. Authored story missions
  can stay privileged (the story reaches you directly), but *generated*
  director contracts enter the player's world through the same channel as
  everyone else's news.
- **The player is a legal courier — of sealed cargo.** The "pay per mail
  delivery" contract is the player doing what every hull already does; but per
  "Carrying is not reading" below, the bag is opaque — the player earns the
  haul without reading it, and learns the world only by *reading a port's
  registry when docked*, never by ferrying mail through.

This layers in around phases 3–4 (once the registry is latency-gated and
directors are located); it is a *feel* change with real UI blast radius, so it
is built deliberately alongside the director relocation, not bolted on after.

## The wormhole is where the fog thickens (decided: home known, elsewhere discovered)

Tier-2 geography is scoped by cluster, and the wormhole is the boundary:

- **Home cluster: fully charted.** The whole Sovereign Drift — hubs, road,
  wormhole, outposts, the M53a peer colonies — is on the player's chart from
  the start. You're a local; you know your own backyard. So M53a's peer
  colonies **spawn onto the chart** (no discovery gate at home). The fog at
  home is purely tier-3 (news/world-state), never geography.
- **Other clusters: discovery.** Past the Nexus wormhole, geography *itself* is
  progressively revealed — you don't know what stations, lanes, wormholes, or
  factions a foreign cluster holds until you go, hear of them, or read it off
  mail that traveled from there. Exploration has real stakes because the map is
  genuinely unknown, and *"there's a colony at X in the next cluster over"*
  becomes a first-class piece of deliverable news, not a given.
- **Hiddenness is per-location, not per-cluster.** Even at home, a deliberately
  hidden site (an off-books habitat, a pirate safe-house) can be uncharted
  until heard of — that's a property of the specific location.

This confirms the **multi-cluster structure** as real future content (the
wormhole is a threshold between charted-home and discovered-abroad, not just
piracy set-dressing), and it gives the mail network its longest-range purpose:
across clusters, mail may be the *only* way word travels at all.

## Carrying is not reading: mail is opaque in transit (decided)

A courier does not know what it carries. The mail bag is **sealed cargo** — you
are the truck, not the recipient. This applies to every carrier, the player
included, and it is the rule that keeps the fog-of-war from trivially
collapsing: without it, ferrying bags around would be a free omniscience
exploit (carry everything, read the world). The clean separation is:

- **A port's registry is readable when you're present.** Docking lets you read
  what has openly accumulated at that node (the harbormaster's log / notice
  board). That is how you collect tier-3 news — by *visiting*, not by hauling.
- **A sealed dispatch in transit is opaque.** It merges into its *recipient's*
  worldview on delivery; it never merges into the *carrier's*. You learn
  nothing from a bag just by moving it.

This is a lot of good gameplay for one rule:

- **The courier sells transport, not intelligence.** "Pay per mail delivery"
  pays for the haul, full stop — if you want to *know* things, you read a
  port's registry or you're the addressed recipient. Keeps the information
  economy honest.
- **Dramatic irony as a mechanic.** You may be carrying a bounty on yourself, a
  warning about the very lane you're flying into, or the evidence that convicts
  a contact you like — and you can't see it. An unwitting accomplice ferrying
  pirate dispatches is ordinary play, not an edge case.
- **Inspection reveals cargo (the payoff tie-in).** The alongside-hold / boarding
  abstraction (economy_and_piracy.md; the identity-kit search) already says a
  search finds *all the papers aboard*. Mail is exactly that kind of paper: a
  patrol inspecting a courier extracts the sealed dispatch as intel, and a
  pirate robbing the mail can delay or read it. Opacity is what makes those
  acts *do* something — you can't inspect open information.
- **Forgery rides free.** A carrier can't vet what it can't read, so forged mail
  (the provenance open question below) propagates through honest couriers
  without their knowledge — the spoofable-flag design, applied to news.

## The asymmetry is the point: two information graphs over one station set

Different actors read different feeds, with different latencies, over the same
physical station map. That asymmetry is a feature to design *toward*, not an
accident to normalize away:

- **Commerce guild** reads the **official docking registry** — ships that
  actually docked and were logged by a port.
- **Pirate guild** reads **informants** — pirates mostly don't dock; they "com
  in" to a contact planted at a station, who folds the report into that
  station's *unofficial* mailstream. (Playtest: *"pirate contacts on various
  stations."*)

Same map, two overlay graphs. And the player's ways of attacking each are
**mirror gameplay**:

| Attack the… | commerce graph | pirate graph |
|---|---|---|
| by blinding a node | rob / delay the mail courier so a lane reads "safe" after it's gone hot | find and remove the informant — literally tears down the network |
| by poisoning it | feed a forged registry entry / false sighting | feed the informant bad intel |

Design so both graphs are made of the same primitives (registry + carriers +
located subscribers) with different *access rules* — don't build two systems.

## The contracts fall straight out of directors' blind spots

Every contract the economy wants is "sell information, or sell risk-absorption,
to a director that no longer knows everything." Enumerated against substrate
that already exists:

| Contract | What the player sells | Existing substrate |
|---|---|---|
| **Courier** — pay per delivery | You *are* the transport; carry the **sealed** bag between nodes — you sell the haul, not knowledge of its contents | ClusterEntity payload field; the on-dock merge |
| **Locate a missing ship** | Ground truth faster than the news would arrive | the director's OVERDUE record + M56 stamps + the history log |
| **Cargo escort** (dangerous runs) | Risk-absorption for the guild's own hull | M54 escort missions |
| **Contract hauling** — take the risky run *instead of* a guild hull | You absorb the *hull* risk; the guild keeps its ships | new, and the biggest unlock — the player becomes a subcontractor |
| **Salvage** a wrecked ship | Recover value from a confirmed-LOST record | [hulk_revival_contract.md](hulk_revival_contract.md), [tugs.md](tugs.md), [recovery_mining.md](recovery_mining.md) |
| **Bounty** on a known pirate | Turn a wanted-name into a paid kill/capture | **M52b warrants already ship this** ([warrants.md](warrants.md)) |

The missions layer stops being hand-authored (StoryState missions) and starts
being *generated by the gap between what a director wants to be true and what
its mail can confirm*.

## Information is a priced good: parties buy freshness

The economy model ([station_economy.md](station_economy.md)) makes this concrete
rather than thematic. A fleet operator's business depends on knowing where demand
is, so it will publish a posting whose payload is **version numbers**:

> *"Stock/pricing data fresher than X, for all stations."*

Mechanically that is "sync any source whose `confirmed_at` is older than X,
paying P" — and the monotonic log is what makes it *purchasable*: you cannot
double-sell `Ironhold@v42`, because **the buyer's own version is the receipt**.
No new bookkeeping; the merge rule already prevents the double-sell.

Why this is the payoff of the whole model:

- **Information staleness is just another urgency.** A station's stockpile
  drains → physical urgency climbs → someone hauls. A party's picture ages →
  informational urgency climbs → someone couriers. Same
  accumulate-until-someone-bites price discovery, same posting board, same
  distance discount, **no new pricing math**. A courier circuit is a haul route
  through information space, scored by the identical function.
- **You get paid for confirming nothing happened** (this is what clock 3 buys —
  see "Three clocks" above). Steady value for a circuit, instead of a lottery.
- **Geography compounds.** Corvus Yards is 453k out, so it is chronically
  underserved for cargo *and* its data is chronically stale — same cause, two
  reinforcing effects, making the far corner of the map the high-risk/high-reward
  zone without anyone authoring it as one.
- **It makes "whose mail, whose enemy" economically real.** The allegiance choice
  below is only a *choice* if there is a buyer; a rival operator paying for fresh
  station data is exactly that buyer. Provenance label visible, contents sealed
  (per "Carrying is not reading") is what turns it into a decision rather than an
  accident.

Note this composes with opacity rather than breaking it: buying a *public feed*
(a port registry, sport results) advances the buyer's read-version because the
courier read it at the source and can retail it onward. A **sealed dispatch** is
still never readable by its carrier, so it cannot be sold as intelligence — only
hauled.

**Hazard — sync farming.** If a party pays per sync, a courier can farm it by
shuttling between two nearby stations forever. The freshness window X is the
natural defence (you are only paid for sources *past* X), but X must be long
relative to trip times or the farm reopens. This needs an explicit test, not just
a tuned constant.

## World-building the model earns

Two directions the mail model makes possible — captured now so they're designed
*into* it, not bolted on:

- **A sport, and news of it as social capital — the Drift Circuit.** Invent a
  cluster sport: **drift-current racing**, pilots riding the natural currents
  (`foam_currents`, already in the sim) between stations on a seasonal circuit,
  each hub and outpost backing its own pilot/crew, with fierce parochial
  loyalties (the existing hub/outpost rivalries — and the peer-state seam — map
  straight onto fan lines). Race *results* are just another source log
  (`"Drift Circuit Results @ vN"`) that has to travel: a race ran at Deepcut,
  and fans at Ironhold haven't heard yet. **Being first to bring a station's
  fans a fresh result — especially their crew winning — nudges their
  disposition toward you**: warmer greetings, a small standing bump, maybe a
  looser challenge or a friendlier dock. It's the low-stakes, high-charm proof
  that *news is social capital*, wholly separate from the commercial/tactical
  feeds, and it makes a courier's route a **social** choice, not only a
  logistical one. Easily reflavored; the keeper is the mechanic — a cultural
  feed whose freshness changes how fans treat the carrier.
- **Whose mail, and whose enemy — the delivery *choice*.** Long-term, handing a
  bag over carries allegiance weight: *"maybe I shouldn't give Ironhold Port
  Control's docking registry to an enemy state."* This composes cleanly with
  opacity — contents stay sealed, but a bag's **provenance label** (source +
  owning flag) is visible, so the player makes an allegiance call on *who* the
  mail serves without reading *what* it says. Delivering a faction's feed to its
  rival helps the rival, can betray the source (a standing hit if it's traced),
  and is exactly the grey choice the information economy wants. Needs a
  provenance/sensitivity tag on a source and a consequence path through
  warrants/standing — later content, but "label visible while contents opaque"
  is a constraint to honor from the start.

## Dependencies (what this stands on)

- **Newest-wins reconciliation** — the discipline is proven twice already
  (datalink contact fusion; SOS passive-sync). Third instance, same rules, new
  transport.
- **M56 contact-freshness timestamps** — related, but NOT a merge dependency.
  The monotonic-log simplification (see "The merge is just a version compare")
  means the merge orders on each source's own sequence number, not on an
  observation stamp, so the multi-hop hazard M56 addresses can't arise for mail
  at all. M56 stays worth doing for *contacts*, and the mail network borrows its
  frame-stamp idiom for the per-entry AGE display (how stale a delivered
  registry reads), never for ordering. Position: shared idiom + still-worthwhile
  contact cleanup, not a hard dependency of this vertical.
- **Docking events** (M46/M47, `port_control.gd`) — the raw registry source.
  They fire already; they need to be recorded and stamped.
- **Director honesty rule / OVERDUE state machine** (M51,
  jobs_and_itineraries.md §3) — the consumer. Its logic is right; its input
  changes.
- **Warrants / wanted-names** (M52b) — the bounty and forensic-evidence layer.
- **ClusterEntity records + promote/demote + record retirement** (M14/M51) —
  couriers are ordinary TRAFFIC records with a payload field; the M51
  death-gap/record-retirement fix already handles a carrier that dies with the
  mail aboard.
- **SOS as a relayable contact** (just shipped) — a distress / "spotted
  destroyed" report is itself a news class that can ride both the datalink
  (fast, short) and the mail (slow, long, durable).

Blast radius on the director model is **M48-sized** (it changes what "a
director knows" means everywhere), so it earns the same treatment: built
deliberately, phased, with the omniscience swap isolated to one phase.

## Phasing — so the omniscience fix is never a big bang

1. **Registry.** Stations record timestamped dock/undock events into a durable
   per-station log. Directors stay omniscient (they read the log globally). No
   behavior change — this is pure instrumentation, and it lets the traffic
   guild (M53c) read demand from the *right shape* immediately. Cheap.
2. **Transport.** Couriers carry + merge registries on dock; a station's
   worldview becomes the merge of mail it has received. Still no director
   dependency — you can watch news propagate across the map before anything
   acts on its latency.
3. **Relocate the director.** Its knowledge source becomes "what's in my
   node's merged registry," not the global view. **This is the fiction fix.**
   Latency now bites: an OVERDUE resolves late, a demand shift reaches the
   dispatcher a courier-hop after it happened. This is the one phase with real
   behavioral blast radius; everything before it is safe scaffolding.
4. **Contracts.** Courier / locate / contract-haul / salvage / bounty surfaces.
   The player enters the information economy.

## What this changes about what we build *next* (before this vertical starts)

M53c (the traffic guild) is about to read demand from an omniscient global
view. If the mail model is coming, **build M53c's demand read against a
per-station docking-registry shape from day one** — even while that registry is
still globally visible (phase-1 style). Then phase 3 later just changes the
registry's *visibility* (latency-gates it), not the director's *shape*. That's
a cheap decision now that avoids ripping out a god-object later. Recorded as an
edit to the roadmap's M53 section.

**Updated 2026-07-24 — it goes further than a registry shape.** Working through
the demand model ([station_economy.md](station_economy.md)) established that the
thing which must be built latency-gate-ready is not just the registry but the
**posting**: a station converting its own private stock into a public offer at a
price. Two consequences for M53c:

- **Demand must not be a director-side scalar.** The first scoping pass proposed
  exactly that and it was wrong — a director-internal number gives the fog
  nothing real to be stale about, and cannot be seen, served, or paid for by the
  player. Stock lives on stations; parties read *postings*.
- **No global optimizer.** Dispatch scores over postings a party has actually
  heard of, weighted by that party's own interest — never a cluster-welfare
  objective. Phase 3 then narrows the input set rather than rewriting the
  decision rule.

Both are data-shape decisions: cheap now, expensive to retrofit.

## Open questions (not yet decided)

- **Courier scheduling.** Is mail a dedicated carrier class, or does every
  TRAFFIC hull opportunistically carry whatever news it holds and swap bags on
  dock (news as a free rider on ordinary commerce)? The latter is richer and
  cheaper but harder to reason about; the former is legible and contract-able.
  Leaning: ordinary hulls carry opportunistically (news rides commerce), with
  *dedicated* courier runs existing as the high-value, contractable premium
  tier the player competes for.
- **False news.** Forged registry entries / fake sightings are obviously
  desirable emergent play (mirrors the pirate's spoofable-flag design), but
  need a provenance model so a forgery is *possible but riskable*, not free.
  Park until phase 3 — it only means anything once directors act on mail.
- **Off-bubble resolution.** Couriers dead-reckoning news across a huge 2×
  cluster while dormant is the natural user of the unused ROUTE_TICK liveness
  tier (economy_and_piracy.md decision 8). Worth confirming the tier can carry
  a payload merge, not just position.
```
