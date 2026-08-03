# M62 — Overdue detection that isn't omniscient

## The problem

`TrafficGuild._check_ins` polls **live nodes directly**:

```gdscript
var rec = _find_record(cluster, record_id)
if rec != null and rec.is_live():
    if rec.live_node.is_dead: -> OVERDUE
else:                        -> OVERDUE (vanished)
```

No range gate, no channel. The guild learns a hull died **anywhere in the
cluster within ~55 seconds** (10s poll + 45s `presumed_lost_delay`), while a
robbery report takes **~22 game-minutes** to reach a station by hull (measured
2026-08-02).

Two separate faults:

1. **It is not an overdue judgement at all — it is death detection.** Nothing
   relates to failing to ARRIVE. A hull that is merely slow, rerouted, or docked
   elsewhere is indistinguishable from one that is fine, and 45 seconds is not a
   meaningful window for a leg that takes tens of minutes.
2. **The channel is omniscient**, which contradicts M57-M58 outright. The
   pattern was justified as a "radio report" from the guild's own members, but a
   hauler 300,000u out is ten times beyond the 30,000u comms range. There is no
   radio.

**This nearly shipped as a fix.** The plumbing gaps found the same day — the
TrafficGuild is not installed in the funnel sim, and its incident log lives on a
`RefCounted` director rather than a record, so nothing can read it — made
OVERDUE look like a wiring problem. Fixing the wiring WITHOUT fixing the physics
would have handed every director an instant, cluster-wide channel arriving ~24x
sooner than the mail it was meant to complement. Patrols would have looked
responsive for entirely fake reasons.

## What "overdue" actually means

> *"Didn't show up, and I haven't spotted it since — but I have the logged
> destination, so I have an arrival estimate plus a buffer."*

The three parts, each load-bearing:

- **Didn't show up.** A non-arrival is observed at the DESTINATION, not by
  watching the hull. `docking_registry` already records DOCKED per station and
  still has no consumer; it is the natural substrate (second time today it has
  turned out to be the missing reader).
- **Haven't spotted it since.** A hull seen alive elsewhere is not overdue, it
  changed its mind. Any sighting — own sensors, kin relay, another port's
  registry arriving by mail — resets the clock.
- **Arrival estimate + buffer.** Derived from the logged destination and the
  leg's transit time, so the window scales with the journey (tens of minutes)
  instead of a flat 45 seconds.

### Why this is genuinely harder than it looks

**Haulers do not have to follow a declared plan.** `RoutePlannerLeaf` re-plans
mid-flight on a timer; a hauler can legitimately abandon a leg for a better one.
So a "flight plan" is a statement of intent at departure, not a commitment, and
non-arrival is weak evidence on its own.

**The player files no flight plan at all.** Any mechanism that assumes a
declared destination cannot cover the player, so it must degrade gracefully to
"last seen at X, not seen since" rather than requiring an itinerary.

**Estimates are per-leg, not per-hull.** The same hauler on a short hop and a
long haul warrants completely different windows.

## The pirate guild has the same bug, more simply

`PirateGuild._check_ins` uses the identical live-node poll. It is easier there
for a structural reason: **pirates are SUPPOSED to come back.** A hunt job ends
at the wormhole, so the guild has a legitimate expectation of return and a
natural deadline (`hunt_seconds` + exfil transit + buffer). No destination log
is needed — the expectation is built into the job it issued.

Note the cash-out latch (2026-08-02) already fixed the adjacent sampling race
there; this is the remaining honesty problem, not the same bug.

## Scope

- **M62a** — expectation records. A departing hull's logged destination + ETA,
  written where the guild can honestly read it.
- **M62b** — non-arrival detection at the destination, off `docking_registry`.
- **M62c** — sighting resets: any fresh observation clears the overdue clock.
- **M62d** — the pirate variant: return-by-deadline, no destination log needed.
- **M62e** — OVERDUE incidents land on a RECORD (D3), carrying the **lane**
  (`route: [Vector2, Vector2]` is already on the member) rather than only
  `last_seen_pos`. Danger is a lane property; `lane_risk` measures distance to a
  SEGMENT, and "failed the Ironhold->Coldreach leg" is stronger evidence than
  "something happened near here".

## Blocked-on / interacts with

- The TrafficGuild is **not installed** in `information_loop.gd` (only
  `StationEconomy` and `PirateGuild` are). Fix that first or M62 is unmeasurable.
- Once honest, OVERDUE becomes the signal that works when **nobody survives to
  report** — the case patrols most need, and the one every measurement so far
  has been blind to.
