# M64 — Price fog: postings behind the mailbag

## Why

Criterion (3) is *"the information economy actually driving route planning, with
urgent routes still being risked"*. The first half is proven; the second has
never once happened.

```
decisions changed by risk     : 460 of 6701   (risk p95 69.1 vs margin 60)
decisions changed by risk     : 1614 of 6685  (risk p95 78.2)
flew a KNOWN-risky lane anyway: 0             EVERY run ever recorded
```

**D36, corrected**: this is NOT a missing payout term. `RoutePlanner` already
scores `payout - travel_cost - risk`, and `payout` derives from urgency via
`StationEconomy.price()` — the exact mechanism `station_economy.md`'s
self-healing cascade runs on (*"a starved refinery's ore urgency climbs, raising
the ore price, pulling haulers onto the ore lane"*).

The real cause is **substitutability**. The winner is an argmax over ~13
stations x commodities — hundreds of candidate pairs. A risky lane never has to
beat its own payout, only the **margin to the next-best substitute**, and with
that many comparable routes that margin is tiny. Measured risk (p95 69-78)
against a payout ceiling near 200/lot is a ~35% penalty, which reliably loses to
*something* safe. Nothing is mispriced; there is simply always another lane.

## The asymmetry that causes it

M57-M59 put **incidents** behind the fog and left **postings** global.

| input to one routing decision | how it is obtained |
|---|---|
| danger (incidents) | carried by courier, clamped to delivered version |
| price (postings) | read directly, globally, instantly |

`RoutePlanner._score_pair` calls `StationEconomy.get_posting(rec, ...)` and
`accept_posting(rec, ...)` on **any record in the cluster**
(`route_planner.gd:270, 293-296, 304-305`) with no mailbag involved. So a hauler
hears about a robbery days late and knows every price in the cluster instantly.

That is not just a missing feature — **the two inputs to one decision come from
different epistemologies**, and the fogged one is systematically disadvantaged.

## What fixes it

Postings become a mail source, clamped exactly like incidents: a hauler knows a
port's board only if it has been there, or met someone who had. Substitutes
become scarce, and the urgent risky lane it actually heard about can win on its
merits.

**The fog is what creates the scarcity that makes danger worth accepting.**

This is `mail_network.md`'s **phase 3 — "Relocate the director"**, applied to
cargo. That doc calls it *"the fiction fix"* and *"the one phase with real
behavioral blast radius"*, which is the honest framing here too.

## THE RISK, and it is not small

`station_economy.md`'s cascade **depends on price signals propagating**:

> lose a mining ship → refinery stalls → haulers arrive to find no refined to
> ship → … a starved refinery's ore urgency climbs, raising the ore price,
> pulling haulers onto the ore lane, restarting it.

Fog that signal and **a station can starve because nobody heard it was
starving**. The termination argument for the cascade quietly assumes the price
is visible. That is the failure mode this milestone must be measured against,
not merely noted.

Mitigations available without inventing anything:

- **The beacon road already exists** (~25k spacing between the two main hubs) and
  is the natural mail backbone — D25 proposed exactly this.
- **TrafficGuild's population floor** is already the deadlock breaker for the
  circular-repair case; fresh hulls arrive with fresh (empty) mailbags and go
  looking.
- **Staleness is not blindness**: a hauler that visited a port keeps a *version*,
  so it plans against a remembered price. Wrong-but-recent beats unknown, and
  `confirmed_at` already expresses "how sure am I that this is still true".

## Scope

- **M64a — postings as a versioned source.** A per-station posting log with a
  monotonic seq, the same `SourceLog` shape incidents and `docking_registry`
  already use. No new transport; the mailbag carries it.
- **M64b — clamped read.** `Mailbag.read_postings(cluster, bag)`, sibling of
  `read_incidents`. `RoutePlanner` takes heard postings as a parameter instead
  of reaching into `StationEconomy` per record — the same change `known_incidents`
  already made for risk, so the seam exists.
- **M64c — seeding.** Decide what a hull knows at spawn. **Nothing** is
  defensible and brutal; **its home port's board** is defensible and kind. This
  is a gameplay decision, not an implementation detail, and it sets the floor on
  how much traffic exists at all.
- **M64d — the player.** The player files no flight plan and reads no global
  board either; whatever cargo gets here, the player UI must be able to express
  ("last known price at X, as of Y"). `confirmed_at` is already the field for it.

## Measurement — BOTH numbers, or the result is meaningless

The funnel already reports both sides, which is the point:

1. **`risked_anyway` rises above zero, with NO change to the risk term.** That is
   the falsifier recorded in D36: if substitutability was the binding constraint,
   scarcity alone should produce risk-taking. If it stays 0, the correction in
   D36 is also wrong and the cause is elsewhere.
2. **Starved bins stay at 0** (`_report_economy`). If risk-taking rises while
   stations starve, the milestone traded one criterion for another and has not
   succeeded — it has moved the failure.

Seed-matched pairs, one variable. `economy_traffic.gd` remains the authority for
the full SERVED/UNDERSUPPLIED verdict; the funnel's starvation check is a
survival floor, not a substitute.

## Interacts with

- **D36 / D25 / D26** — these converge here. D26 ("mail urgency") and D25
  ("prices are globally readable so the loop doesn't bite") are the same
  milestone, and this is it. Until now it had a design section and a ledger
  entry but no plan.
- **M60d** — and note the ORDERING. M64 is a hard prerequisite for pirates
  reasoning economically at all: `RoutePlanner.best_route` is static and takes a
  flag, so a pirate could predict cargo's lane with its cover flag today — but
  today that data is omniscient. Fogging postings is what makes pirate economic
  targeting honest, so M64 unblocks the best fix for criterion (1) as well as
  being the fix for criterion (3). One milestone, both blockers.
- **M60d (registry)** — the pirate mirror. Pirates must travel for institutional
  intelligence (port logs); cargo must travel for prices. Same phase-3 move,
  different director.
- **M53c** — postings are its output; this changes who can see them, not how
  they are produced.
- **M59** — supplies the `known_incidents` seam this copies.
