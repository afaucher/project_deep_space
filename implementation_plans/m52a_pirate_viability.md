# M52a — Pirate viability: why zero takes, instrument, then rebalance

Sub-milestone of the M52 design pass (m48_m55_economy_piracy_roadmap.md).
Triggered by a campaign observation: across an entire session the guild
ledger read `takes_total=0 losses=3` — every pirate either looped on the
same failed robbery until something killed it, or exfiled empty. The design
target (economy_and_piracy.md) is a *sustainable* predation rate, not
zero.

The rule for this milestone: **measure before rebalancing.** We have three
strong hypotheses from reading the log against the code (below), and each
suggests an obvious knob — but the whole point of the instrumentation stage
is to find out which of them actually dominates before touching balance.

## 1. What the campaign log shows

```
SELECT_VICTIM done (victim_iid=128865799210)
INTERCEPT done   (same victim)
DEMAND_STOP ABORT -> 'hunt'          # no cause printed = patience/outpaced
SELECT_VICTIM done (victim_iid=128865799210)   # SAME victim again
... (loop x3) ...
'Last Call' missed check-in (observed dead) -> OVERDUE -> LOST (losses 3)
# next pirate, same victim:
DEMAND_STOP ABORT (third_party_in_range) -> 'exfil'
[Collision] Cluster_9003 hit Missile_0_... dmg=4000    # killed by missile
```

Three read-offs: (a) the same victim is re-selected forever after a failed
demand — SELECT_VICTIM has no memory; (b) DEMAND_STOP aborts dominate, and
the un-caused variant (patience expiry / outpaced) doesn't say WHY; (c)
pirates die to missile-armed responders mid-loop instead of withdrawing.

## 2. Hypotheses (from code, unverified until instrumented)

**H1 — The victim always runs: comply-or-run compares the wrong speeds.**
`threat_response_leaf.gd`: `will_run = actor.max_speed > threat_speed *
ratio`, where `threat_speed` is the PIRATE'S CURRENT observed speed from
the victim's own track. A pirate decelerating to hail range reads as slow
(→ `threat_speed * 1.6` is tiny), so any cargo hull with a working drive
decides it can outrun the "slow" pirate — every time. It should compare
against the threat's plausible *pursuit* capability (hull-class max speed
off the observed signature, or observed peak speed over the encounter),
not its instantaneous approach speed. If H1 dominates, no demand ever
completes and everything downstream is moot.

**H2 — The beacon road makes "alone" nearly impossible.** Buoys are
EM-loud (comms + active sensor) with cross-section above
ORDNANCE_CS_THRESHOLD → they classify as UNIDENTIFIED VESSEL and count as
witnesses in BOTH the SELECT_VICTIM alone-check and the
`third_party_in_range` abort. The seven road beacons sit at ~25k spacing
ON the Ironhold↔Drift Market lane — a victim transiting the lane is within
the 6 km witness bubble of a beacon for a large fraction of its trip, and
the M51.5 tradecraft fix DOUBLED `_R_THIRD_PARTY` 3 km → 6 km, which
widened exactly this failure. A beacon is a relay, not a witness with
eyes... or is it? (Design question either way: does the road *see*? If
yes, robbing on the road should be hard and pirates should hunt the
off-road lanes; if no, exclude BEACON-kind hulls from witness checks. This
is a design decision to make WITH data, not a bug to silently fix.)

**H3 — Failure has no memory and no price.** SELECT_VICTIM re-picks the
same (now-alerted, running) victim because nothing records the failed
attempt; DEMAND patience (25 s) + re-hunt loops until a patrol arrives or
kills the pirate. Meanwhile showing pirate colors (`show_colors: true`)
near the road advertises the robbery to every patrol in comms range. The
missing behavior isn't better aim, it's *patience*: fail → move on →
different lane point, different victim → eventually give up and leave
ALIVE.

## 3. Instrumentation (build first, ship with logs on)

Console logging is omniscient by declaration — these are developer logs,
not guild knowledge. The guild's own ledger stays honest (check-ins only).

- **Flip `pirate_guild_log` and `job_log` defaults to ON** (DebugSettings).
  Done in this milestone — the console is omniscient, no reason to hide
  the only visibility we have into a systemic loop.
- **Abort causes, always.** The JobRunner ABORT line gains the cause the
  way DONE lines carry detail: `DEMAND_STOP ABORT (patience 25s expired,
  victim at 4.1km receding)` / `(outpaced beyond hail range)` /
  `(victim track lost)`. The abort_when-routed causes already print; the
  step-internal ones don't.
- **Witness identity.** When `third_party_in_range` (or the SELECT_VICTIM
  alone-check) trips, log WHO: contact id, classification, distance, and
  whether its record-kind is BEACON. One session of logs settles H2.
- **Demand outcomes on the victim side.** threat_response_leaf logs its
  decision: `comply` vs `run (my max 900 > threat 240*1.6)` — with the
  numbers. One session settles H1.
- **Cause of death.** On observed-dead resolution, log the killer if the
  hulk knows it (take_damage's attacker attribution is already recorded
  for the aggression bus — surface it): `LOST 'Last Call' (killed by
  Patrol_2, missile)`.
- **Per-attempt ledger (guild-side, honest).** Each hunt job counts its
  attempts and abort causes into the member's check-in state; on any
  resolution the guild logs an attempt summary: `attempts=4
  demand_aborts{patience:3, third_party:1} outcome=LOST`. This is the
  success-rate metric the rebalance stage keys off.
- **Headless measurement run.** A `--run-tactical-sim pirate_viability`
  runner: home cluster + guild, N sim-minutes, dumps per-attempt rows to
  `tactical_analysis/data/pirate_viability.csv` (attempt outcome, abort
  causes, time-to-outcome, witness kinds seen). This is the calibration
  instrument — rerunnable after every knob change.

## 4. Behaviors (design pinned now, built after data confirms)

- **Patient circulation, not thrash.** SELECT_VICTIM gains a small
  per-job `failed_victims` memory (iid → cooldown); a failed demand
  blacklists that victim for minutes. On abort, re-roll a DIFFERENT lane
  point (the guild already computes them) before re-hunting. A pirate that
  can't find isolated prey keeps moving — lurk, drift, next spot.
- **Withdraw alive.** A hunt job gets a total time/attempt budget. Budget
  exhausted → exit via wormhole WITHOUT loot, transponder lit under the
  current cover. New guild resolution: **RETURNED_EMPTY** — alive, no
  take, not a loss. This is "we'd be more profitable elsewhere," and it's
  also how a scared-off pirate pops back up later: the hull leaves, the
  ledger remembers, a fresh arrival gets scheduled on the normal window.
- **Guild backoff (profitability governor).** Consecutive profitless
  resolutions (LOST or RETURNED_EMPTY both count) stretch the arrival
  window (e.g. x2 per streak step, capped); a take resets it. The guild
  commits fewer ships to a lane that isn't paying — and recovers on its
  own clock. This subsumes the existing cap streaks rather than replacing
  them: cap says how many at once, backoff says how often.
- **Presumed-lost calibrated from data.** `presumed_lost_delay` (45 s) and
  the arrival window were guesses. The viability CSV gives actual attempt
  durations; set presumed-lost from the observed distribution (e.g. p95
  attempt duration + margin), and document the derivation in the config
  comment. Consider intent-aware delays later (a member last seen heading
  to exfil with loot deserves more patience than one that went silent
  mid-hunt) — only if the flat calibrated value proves wrong.
- **(Held for the data)** H1's comply-or-run fix (compare pursuit
  capability, not instantaneous speed) and H2's witness rules (do beacons
  see?) are design decisions this milestone RESOLVES but doesn't presume.

## 5. Test coverage gaps (why the suite said green while the campaign said zero)

The unit tests validate the *mechanisms* in isolation and they all pass —
`test_pirate_ambush` runs one victim, no beacons, no patrols, and the
victim complies. Nothing exercises the hunt *in the environment it
actually runs in*. To add:

- **Comply-or-run truth table** (unit): victim vs slow-approaching pirate
  whose hull can outrun it — expected: comply (post-H1-fix); vs genuinely
  slower threat — run. Locks the H1 decision either way.
- **Same-victim blacklist** (unit): failed demand → SELECT_VICTIM must not
  return the same iid within the cooldown.
- **Withdraw-alive** (guild): a hunt that exhausts its budget resolves
  RETURNED_EMPTY, no loss counted, backoff stretches the next arrival.
- **Beacon-witness rule** (whichever way H2 resolves): pinned by a test so
  the next tradecraft tweak can't silently flip it.
- **Environment smoke** (sim, not unit): the viability sim runner asserts
  a floor, e.g. "≥1 successful take in N minutes with the default config"
  — deliberately loose (physics nondeterminism; margins per CLAUDE.md),
  it exists to catch the *systemic zero*, which is exactly the class of
  failure the unit suite can't see.

## 6. Order of work

1. Log defaults ON + abort causes + witness identity + demand-decision
   logging + death attribution (pure instrumentation, no behavior change).
2. Viability sim runner + CSV; run it; write the findings into this doc.
3. Resolve H1/H2 design calls from the data; implement with their tests.
4. Patience/blacklist/withdraw/backoff behaviors with their tests.
5. Calibrate presumed-lost + arrival window from the CSV; re-run the sim;
   record before/after rates here.
