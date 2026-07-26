# Known contacts: the chart, the briefing, and the sensor are one list

Today the player's tactical contacts section shows only what the sensors are
*currently holding* (`ship.gd`'s `active_contacts`, built by the angular-bin
sweep → correlate → classify → decay pipeline in
`real-time-sensor-signal.md`). Everything else the player knows about the
world — where Ironhold is, where the mission says to look — either lives in a
different panel or lives nowhere at all.

That is backwards in two directions at once.

**The AI is better informed than the player, for no fictional reason.**
`RoutePlanner.best_route()` reads every station's position straight off
`cluster.records` (`route_planner.gd`), live or dormant, at any range. A hauler
navigates by a chart. The player, watching that hauler fly confidently toward a
station their contacts panel has never heard of, has strictly less information
than the NPC — not because they haven't earned it, but because we never built
the chart on their side. Station positions are constants and publicly known.
Withholding them models nothing.

**Mission locations are already the same mechanism, spelled differently.**
`mission_catalog.gd` objectives already carry exactly the shapes this needs:

- `"target": {"marker_sid": "ironhold"}` — resolved to a position through
  ClusterManager records by `contract_feed.gd`. *That is the chart lookup*,
  already written, already working.
- `"target": {"center": Vector2(300000, 220000), "radius": 16000.0}` — the M43
  Slag Bay search. A location known only as a **region**.
- `"target": {"npc": "Todd"}`, with the catalog's own comment: *his position is
  unknown; finding him IS the gameplay.*

So we have three separate expressions of "somewhere the player knows about but
is not currently sensing," and one of them is already implemented twice.

## The claim

There is one concept: **a known contact** — an entry in the tactical contacts
section that exists whether or not a sensor is currently returning it. What
varies is *how we came to know it* and *how precisely*.

Provenance and precision are **fields**, not separate systems.

## Principles

**1. One list, not three.** The chart, the mission briefing, and the sensor
feed all produce rows in the same tactical contacts section. A player should
never have to ask "which panel would this be in?" — the answer is always the
same panel, and the row says where the knowledge came from.

**2. Every position is `(center, radius)`.** A point is a radius of zero. This
is the single change that makes the unification work, because it lets a charted
station (radius 0), a decayed sensor track (radius growing with `pos_timer`), a
16km search region, and "Todd is somewhere" all be the same shape. Half of this
already exists: `active_contacts` entries carry `"resolution"` (the
`bin_angle` the contact was detected in) and `"pos_timer"`. Those are an
uncertainty radius wearing a different name.

**3. Uncertainty shrinks with evidence and grows with time.** A briefed region
narrows as the player eliminates candidates inside it — which is *precisely*
the M43 search gameplay already authored ("eliminating the unnamed contacts
takes real flying"). A held track's radius grows as it decays and
dead-reckons. Same field, opposite directions, one rule: knowledge degrades
unless refreshed.

**4. Freshness semantics follow provenance.**

| Provenance | Radius | Ages? | Lifetime |
|---|---|---|---|
| `CHART` | 0 | No — it's a constant | Permanent |
| `BRIEFED` | As authored (region or point) | No, but can be contradicted | Mission-scoped |
| `SENSED` | From `resolution`, grows on decay | Yes | Per `contact_tracing_and_cleanup.md` |
| `HEARD` (future, mail) | 0 for position, as-of for the *claim* | The claim ages, not the position | Until superseded |

A charted station does not "go stale." A sensor track does. Conflating those is
what makes a single freshness model feel wrong on half the rows.

**5. A charted entry cannot be classified.** `classify_contact` keys on EM
(`ship.gd`) — a live ship is EM-loud, a hulk is EM-dark. A station 400k units
away is emitting nothing the player is *receiving*. So chart and briefing rows
enter the list already labelled from their source and never pass through
classification. This is a hard seam, not a special case: classification is a
statement about a signal, and there is no signal.

**6. Sensors outrank claims, and disagreement is content.** When the player
comes into range of a charted station, the chart row and the fresh sensed
contact must resolve to **one** row — the same correlate step fusion already
does, not a special case, or the panel double-lists every station you visit.
But when they *disagree* — the chart says a station is here and the sensors
say empty space, the briefing says Todd is at Claim 42 and he isn't — that is
a genuine moment and we should render it rather than suppress it. The chart is
a **claim**. The sensor is **evidence**. A player who learns to feel that
difference is a player ready for the mail network, where every claim has an
age and a source who might be wrong.

**7. The chart is free; the market is not.** This is the constraint that keeps
the whole thing honest as the mail vertical lands. Split what a known contact
carries into two layers:

- **Static layer** — position, name, flag, kind. Constant, publicly known, no
  courier required. Give it away.
- **Volatile layer** — urgency, price, open postings, who was last seen here,
  is it under attack. This is what `mail_network.md` exists to make travel at
  hull speed, and it must never be free.

Folding the chart into contacts now is what makes the mail UI cheap later:
once a row can render "charted, unobserved" versus "held, fresh," then
*"Coldreach — VOLATILES urgent, as of 4 hours ago"* has an obvious home and an
existing freshness idiom to borrow. Without this, the mail vertical has to
invent its own display surface.

## What this makes possible that isn't possible now

- **The player can plan like a hauler.** Same chart, same postings board (once
  priced), same ability to reason about a run — which is the whole premise of
  the economy being player-legible rather than set dressing.
- **A mission marker stops being special.** "Go here" is a briefed contact with
  radius 0. "Search this field" is a briefed contact with radius 16000. The
  mission log stops owning a private notion of location.
- **Todd becomes representable.** A briefed contact with an unknown position is
  a row with no position at all — visible in the list, not on the map, until
  evidence arrives. Right now the catalog handles this by simply not emitting a
  marker, which means the player's only cue is dialogue.
- **A stale chart is a story.** A charted station that is gone, or a briefing
  that points at the wrong rock, becomes readable in the fiction instead of a
  bug report.

## Open questions

- **Where does it live?** The user's call is the tactical contacts section
  (`contacts_panel.gd`), not a separate map screen — right, because the point
  is to make the epistemics legible side by side. But `navigation_panel.gd`
  renders the spatial view and will need the same rows. Which owns the merged
  list, and does the nav panel read it or rebuild it?
- **Filtering.** 13 `Kind.STATION` records, plus five mobile homes, plus
  beacons, plus live traffic, in one list. Needs grouping or filters from day
  one or the panel is unusable.
- **Does the chart cover beacons and the wormhole?** They're static and public
  by the same argument. Probably yes, same source, no extra mechanism.
- **The mobile-home wrinkle.** The five M43 mobile homes are `Kind.STATION` but
  `is_static: false` — dead-reckoned while dormant. "Positions are constants"
  does not hold for them. They should probably be chart-visible as a *region*
  (last known + drift), which is another argument for principle 2 being the
  right primitive.
- **Who authors the chart?** Reading `cluster.records` directly gives the
  player literal omniscience over every record, including things they have no
  business knowing (a pirate's dormant record). The chart needs to be an
  explicit, curated *subset* — probably keyed on a record field — not "every
  record with a position."

That last one is the real design work, and it is worth doing carefully: the
chart is the first thing in this game that hands the player information
directly rather than making them sense it, and the boundary of what's on it is
a fiction decision as much as a technical one.

## What this does not change

Sensor fusion is untouched. Classification is untouched — it stays a statement
about a received signal (principle 5), which is why chart rows route around it
rather than through it. The mission log keeps owning objective *state*
(active/complete, ordering); it stops owning objective *location*. And no
market data becomes free: principle 7 is a constraint on this design, not a
concession by it.
