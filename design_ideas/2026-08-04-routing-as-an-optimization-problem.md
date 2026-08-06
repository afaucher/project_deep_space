# Routing as an optimization problem (2026-08-04)

Prompted by a single question about mail urgency: *if station C crosses its
staleness limit while I am already in flight carrying ore, and C does not want
ore, should I go?*

The answer is "sometimes, and you cannot tell from one leg" — and working out
why exposes that the planner's current shape cannot express the question. This
doc is the structure to build M63/D26 against, so that mail urgency arrives as a
term in a model rather than as a fourth thing bolted to an argmax.

It is a design doc, not a plan. Nothing here is built.

## The tell: the special case that already exists

`RoutePlanner.best_route()` is an argmax over `(pickup, dropoff, commodity)`.
The unit of decision is a **plan** — two legs bound together, chosen from an
empty hold.

Being mid-flight is not a first-class state in that model. It is patched:

```gdscript
const DROPOFF_LEG_START := 3   # route_planner.gd
# ... remaining_value() uses this to stop counting the pickup's payout/travel
# once it's sunk cost.
```

That patch is correct and it works. The problem is what happens next. A mail
bounty is collected on **arrival**, which means it interacts with the sunk-cost
rule in its own way, needing its own carve-out — and then two special cases have
to be kept in agreement forever.

`route_planner.gd`'s own header already names this failure by example: two
scoring rules drifted apart until `_chord_carriers` scored geometry while cargo
scored economics, and the two models of "where is the traffic" could never
agree. The fix then was one rule with two selection policies. The same fix
applies here, one level up.

## The structure

**State** is `(position, cargo, bag)`. **The decision is a leg.** A leg's value
includes the value of the state it lands you in.

That single change makes "sitting at a station" and "in flight holding ore" the
same computation with different starting cargo. The mid-flight special case does
not get a sibling; it disappears.

### Two rewards, attached to different objects

This is the part worth not re-deriving, and it is exactly what the ore/C/D
question is made of:

| reward | attaches to | condition |
|---|---|---|
| **cargo margin** | a `(pickup, dropoff)` **pair** — an edge | the destination must demand what you hold |
| **mail bounty** | **arrival at a node** | none — collected regardless of cargo |

Station C carries a node reward and has no viable edge into it: it wants news
and does not want ore. Station D has both. Under today's pair-shaped argmax, C
is not merely rejected — it is **unrepresentable**, because every candidate is a
commodity pair and C is not the far end of one.

### The worked example (added 2026-08-05, D72)

This doc shipped with an abstract ore/C/D illustration. A measured failure
existed in the cluster the whole time, and it is a better argument than the
hypothetical.

`economy_traffic`, 180 game-min: **VOLATILES is the only commodity with a
failing verdict anywhere.** Coldreach is the cluster's only source and shipped 13
loads; **eleven went to two destinations, and three consumers got zero** —
including Refinery Prime, UNSERVED at 5.8 hours of cover, the most desperate
station in the run.

That is the pair-shaped argmax doing what an argmax does. Every hauler
independently computes the same best destination, so one source with seven small
buyers resolves to *everyone flies to the biggest buyer*.

It needs a **milk run** — one commodity, one pickup, MANY dropoffs — which is a
different generalisation from the mixed hold (many commodities, one pickup, one
dropoff). Both are blocked by the same thing: `route_itinerary` is hard-wired to
six steps and cannot express a second stop. Under the leg model it needs no
special case, because a leg's value includes the state it lands you in, so
continuing from Ironhold to Refinery Prime with cargo still aboard is simply the
next leg. Buyer-bound loads run 0.13–1.4 lots against a 4.0 hold, so **one
circuit out of Coldreach could serve three to five consumers** — exactly the set
currently getting nothing.

And it is not a fidelity nicety: VOLATILES has the shortest buffer in the game
on purpose ("running out kills people; that should be a live threat you can watch
closing in"), and the routing model cannot serve it.

### Consequence 1: minimum depth is 2

Diverting to C for the bounty leaves you *still holding ore*. So C's real value
is not `mail(C)`; it is

```
mail(C) + V(C, ore)          # the value of standing at C with a full hold
```

A depth-1 greedy is wrong in **both** directions. It takes C when it sees only
the bounty (and strands the ore). It refuses C when it demands cargo profit on
every leg (and never carries news anywhere unprofitable). Neither is a tuning
error; one leg simply does not contain the information.

Depth 2 is already the house idiom — M53c's depth-2 stocks, and the planner's
existing two-leg pair. Cost is unchanged: depth-2 from a cargo state is
`stations x stations x commodities`, the same order the search already runs at
re-plan time. **This is a restructure, not an expansion.**

### Consequence 2: the objective is reward per unit TIME

Not per trip. A hauler is a continuously-operating agent, and a fat bounty
against a per-trip objective justifies an unbounded detour — the longer the
diversion, the better it looks, because the cost lands on a trip count that
never grows.

`MIN_VIABLE_SCORE`'s "don't fly a loss" floor then applies to the **rate**, and
its existing reasoning carries over unchanged: a hull on a loss-making run is
capacity the cluster does not get back.

## Where this stops, deliberately

The honest full problem is multi-agent. The best assignment of 8 haulers across
13 stations is a joint optimization, and every hauler independently taking its
own argmax is precisely what produces a herd: the mailbag's `merge` is *built*
to make holders converge, so a stale station is stale in everyone's bag at once,
they all divert, they all arrive, the bounty collapses, they all leave together.
Synchronized oscillation — the fleet-scale form of the limit-cycling in
`2026-08-04-deadbands-in-ai-behaviour.md`.

**Do not build the joint optimizer.** It requires exactly the omniscience M64
exists to remove, and "no global optimizer" is already a standing principle of
the economy model.

**Put the coordination in the price.** The herd then dissolves into ordinary
posting competition, which the economy already models. Postings as the one
coupling, doing real work.

### What that price is, and what it is not (corrected)

The first version of this said "a claimable, consumable posting". That is wrong,
and the objection that breaks it is one line: **paid on delivery, by the
receiver — but you do not know when they last got mail, by definition.** If they
were served yesterday, today's delivery is worth little, and you cannot learn
that until you arrive.

**Keep the epistemics.** This is the first point in the system where a hauler
can be genuinely WRONG rather than merely uncertain, which is the property M64
exists to create, arriving here for free.

**The defect is that the error is one-sided.** `confirmed_at[X]` is the latest
time anyone in your merge history confirmed X; others may have visited since and
nothing reports it. So the station's true staleness is *always* ≤ your computed
staleness, your bounty estimate is *always* an over-estimate, and mail runs are
systematically over-valued against cargo runs. Time-based, it is unbounded too —
the longer since you checked, the larger the imagined payday.

**So pay for the delta the merge actually moved, not for elapsed time.**
Computed at the dock from the two bags, locally, by both parties, with no
estimation on either side. `Mailbag.has_news_for(mine, theirs)` is already that
comparison. This bounds the optimism (the estimate is capped by what you
actually carry), makes the claim protocol unnecessary (`merge` is idempotent, so
the same news pays zero the second time *by construction*), and self-limits the
herd (first arrival paid, second not).

**Not version delta alone.** `mailbag.gd`'s header rejects that in advance and
is right: it makes "nothing happened" unsellable and turns a courier route into
a lottery that only pays when there happens to be news. Pay on **both** clocks —
version advance for new facts, `confirmed_at` advance for confirmed absence of
news. Both exist; both already merge as `max`.

**The gap this exposes.** Estimating the sale needs a belief about what X
*knows* — X as a HOLDER. A bag tracks X as a SOURCE: `{version, confirmed_at}`
describe X's own log, not X's knowledge of everyone else. Nothing tracks the
second and bags-of-bags is not worth building. The proxy: **dock merge is
bidirectional**, so at the last sync X knew everything you knew.
`confirmed_at[X]` therefore marks "X's bag was a superset of mine as of then",
and everything learned since is probably new to X.

This also disposes of a question that would otherwise need a tuned curve.
Earlier framing asked whether mail urgency should grow **unboundedly** (a
genuine bounded visit interval, since the term eventually beats any fixed
commercial gap) or **saturate** (a low-value station permanently outbid).
Delta-based payment answers it structurally: the ceiling is how much news
actually exists to deliver, not an asymptote someone chose.

## Two guardrails

**Feasibility is structural, not a penalty.** "C does not want ore" must mean
the sale reward is *absent*, not that a penalty is subtracted. A penalty is
tunable and can therefore be outbid by a large enough bounty — which is how a
hauler ends up selling ore to a station that does not want it. Absence cannot be
outbid.

**A monotonically growing term against a fixed hysteresis band will always
eventually cross it.** So the re-plan trigger cannot be "mail urgency beat
`HYSTERESIS_MARGIN`" — that is steering toward the number you test against,
which the deadband doc rules out, and it guarantees a re-plan on a schedule set
by the growth rate rather than by anything happening in the world. The band
stays on *remaining value*; the discrete event that justifies re-planning is the
bounty being **claimed**.

## What this predicts, and how it would be measured

Recorded here so the measurement is chosen before the result is seen.

The stage this changes is **coverage**, which is large-n and observable per
minute — not takes, and not `risked_anyway`:

- p95 and max of `confirmed_at` age across the fleet. If this works, the curve
  flattens instead of growing.
- the visit distribution across stations (how many stations, not how many docks).

`information_loop.gd` already samples per minute and already reports
`stations_with_news`, so most of the instrument exists.

Two things this must not be measured on:

- **Not `risked_anyway`.** A bounty attached to a station is a payout term
  uncorrelated with commodity prices, so it *can* make a specific risky lane the
  clear winner — which is genuinely relevant to criterion (3). But that is a
  second-order effect of a coverage change, and reading it as the primary result
  would repeat the LANE_RUN error: judging a mechanism at the end of the funnel
  rather than at the stage it changed.
- **Not in the same run as the staleness discount** (the other half of the
  mailbag work — discounting *risk* by `confirmed_at` rather than by incident
  age). Both are terms in the same score function. Landing them together is
  stacking two variables into one measurement.

And the precondition to lead any report with, per
`2026-08-02-preconditions-the-world-never-supplies.md`: **did `confirmed_at`
ages ever actually vary?** If haulers dock often enough that every age is near
zero, the term is inert, and a null result would mean nothing at all.
