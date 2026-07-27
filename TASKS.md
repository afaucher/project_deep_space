# Task dock

Open threads, one entry each. **Reference-driven**: the entry says what the
thread is and where the real detail lives — it is an index, not a second copy
of the design docs. If an entry starts growing prose, that prose belongs in
`design_ideas/` or `implementation_plans/` and the entry should shrink to a
pointer.

Conventions:
- **Decision** = blocked on a human call, not on work.
- **Ready** = scoped, nothing in the way.
- **Open** = known, unscoped.
- Dates are when the thread was opened or last moved.
- Delete an entry when it lands. Git remembers; this file should stay short.

Last swept: 2026-07-26.

---

## Decisions waiting on a human

### Pirates pick WHERE from geometry but never WHO — *2026-07-26, unscoped*
The milestone that made pirates better after the economy grew was **M53a
Slice D** ("pirate circulation", explicitly ordered *last, needs the enlarged
route set*), answering the 2026-07-20 playtest note *"we don't have enough
traffic for pirates to have a good target selection"*. It landed, then M53d
silently reverted it — the entry below is Slice D re-derived for emergent
traffic.

Slice D only ever improved **where** pirates hunt. Nothing improves **who**
they take: a pirate grabs whatever enters its lurk radius, with no notion that
one hull is worth more than another, even though the economy now has urgency,
postings and differentiated cargo.

**The posting board is fair game for pirates** — knowing a hub is desperate
for ore tells you which lane to sit on, and a market-reading guild is exactly
the emergent behaviour worth having. What is unresolved is the **information
economy** around it: who sees which postings, at what latency, at what cost,
and how that access is earned or bought. That is the same question the mail
network exists to answer, and settling it for pirates settles it generally.
Observables (hull class, which hub a ship just left, whether it rides heavy)
are the other half. Natural M53e or an M54 slice; not scoped anywhere today.
→ `implementation_plans/m53a_economic_expansion.md` Pass 4,
`design_ideas/2026-07-20-pirate_playtest.md`, `design_ideas/mail_network.md`

### Pirates catch nothing — three compounding faults, none about targeting — *2026-07-26*
Measured over 180 game-min each, campaign-real guild config, 8 haulers
(`pirate_effectiveness` sim). **Do not pick a targeting strategy off this
table — fix the faults first, then re-measure.**

| strategy | members | resolved | takes | losses | empty |
|---|---|---|---|---|---|
| STATION_CHORD | 1 | 0 | — | — | — |
| CROSSROADS | 1 | 0 | — | — | — |
| APPROACH_RING | 5 | 5 | **0** | 1 | 4 |

**Fault 1 — an unlabelled ABORT reads as JOB COMPLETE and strands the hull.
FIXED 2026-07-26, needs re-measurement.** The exfil tail's
`AWAIT track_quiet` carried `timeout: 60.0` and no `on_abort`.
`JobRunnerLeaf._abort_to("")` sets `current = steps.size()`, which the runner
treats as completion and clears the assignment — so the timeout skipped
RELIGHT and EXIT_AT. The pirate never reached the wormhole, never despawned,
never resolved; it sat dark and motionless forever while the ledger held it
ACTIVE. Traced directly: `step 9 AWAIT` → `step -1/0 ?` with `speed=0` for the
rest of the run.

It also selected AGAINST success: SELECT_VICTIM aborts to the `"exit"` label
and jumps straight to EXIT_AT, so a pirate that found nobody went home
cleanly while a pirate that actually engaged reached this step and stranded.
Every hull that got far enough to attempt a robbery was removed from the
population — which is the real reason every strategy measured zero takes.

**Two earlier explanations of this were WRONG and are recorded so nobody
re-derives them: it is not slow transit** (traced at a flat 700 u/s closing
21k units per 30s, ~8 min to target) **and not the unbounded opening
`GO_TO`** (real as a missing bound, never reached). The map is ~15 min across;
any "never arrived" theory should have died on that arithmetic immediately.

**Still open at the runner level:** `_abort_to("")` making "aborted with
nowhere to go" indistinguishable from "ran to completion" is a trap for every
future job, not just this one. An unlabelled abort should at minimum log
distinctly, and arguably should not clear the slot.

**Fault 2 — one stuck member kills the guild permanently.** `base_cap: 1` and
`takes_per_cap_raise: 2` mean the guild has one hull until it robs twice. With
fault 1, that hull never resolves, so no arrival is ever scheduled again —
silently, with no error anywhere. `presumed_lost_delay` does not catch it (it
applies to OVERDUE members whose record is gone; this one is happily ACTIVE).
A director whose ledger can stall forever is a bug independent of targeting.

**Design target (2026-07-26): a LOW take rate is fine.** Pirates need enough
successes to justify their presence and make occasional encounters
interesting — not a high catch rate. That reframes fault 3 below, and it puts
the current tuning in direct conflict with the intent:

- **The profitability governor treats normal as failure.** Five consecutive
  profitless resolutions drove backoff to x8.0, so arrivals become eight
  times rarer. If a low take rate is intended, four empties between takes IS
  the design working — and the governor throttles hardest exactly then. It
  should trigger on a drought materially longer than the natural run of
  empties.
- **Cap growth is gated behind the scarce metric.** `takes_per_cap_raise: 2`
  at a deliberately low take rate means ~10 cycles per extra hull, so the
  guild sits at one pirate indefinitely — which is also why a single stranded
  hull could zero the faction.
- **The sim measures the wrong success.** `RETURNED_EMPTY` lumps "sat in empty
  space and gave up" together with "held a freighter at gunpoint until a
  patrol drove me off". Only the second is content. Count ENCOUNTERS
  (intercept / demand issued) separately from takes, and give the sim real
  acceptance criteria: takes > 0 over a session horizon, backoff not pinned
  at max, encounters at a readable interval.

**Fault 3 — the strategy that WORKS still takes nothing.** APPROACH_RING
resolved 5 cycles: 4 withdrawals, 1 death, zero takes. So there is a second,
separate ACQUISITION problem underneath, which cannot even be measured until
pirates reliably arrive. The profitability governor then throttles arrivals
8x (backoff x8.0 after 5 profitless resolutions) and cap never leaves 1 — the
guild quietly throttling itself out of the game.
→ `tactical_analysis/data/pirate_effectiveness_*.csv`,
`tactical_analysis/sim_runners/pirate_effectiveness.gd`

### Authority-side warrant resolution is missing — *2026-07-26*
`resolve_warrant` works but the only caller is the player's own un-MARK, so
`SUSTAINED_ASSAULT` and `ARMED_ROBBERY` are permanent and unclearable by any
means in play. The doc's forgiveness half never shipped.
→ `design_ideas/2026-07-26-warrant_stickiness_audit.md`, mismatch 4

### Campaign playtest items are documented, none implemented — *2026-07-26*
Nine items across identity/standing, weapons safety, UI and naming. A1 (a
station opens fire on the player at campaign start) is the severe one.
→ `design_ideas/2026-07-26-campaign_playtest.md`

---

## Ready to pick up

### Drift Market is a pure sink and never gets served — *2026-07-26*
Zero deliveries of anything across a 3-hour sim. It only ever posts IMPORT, so
a round-trip-scoring planner with a profitability floor has no reason to fly
there. Agreed fix is a small REFINED→GOODS converter, blocked until the
refinery actually runs at rate (below).
→ `design_ideas/station_economy.md`, "Worked reference case"

### Per-hull cargo capacity from `cargo_bay` components — *2026-07-26*
`LOT_SIZE` is a flat 4.0 interim: a CargoShuttle and an Ore Barge lift the
same load. `ComponentSpec.CARGO_AREA_PER_UNIT` and the validator's capacity
maths already exist and nothing reads them at runtime. Blockers: CargoShuttle
authors no `cargo_bay` at all, and area-units need calibrating into lots.
Brings with it a **mid-tier freight hauler** (nothing exists between shuttle
and Freighter) and **per-trip travel cost**, which is what makes a big hull
economically worth owning.
→ `design_ideas/station_economy.md`, "Haul capacity is a property of the HULL"

### Regression test for SOS/relay clock coupling — *2026-07-26*
Four assertions were pinned to tick counts and broke when the relay stopped
running every frame. They now derive budgets from `DATALINK_RELAY_HZ`. Worth
one test that asserts the *contract* directly (state change reflected within
N ms) so the next cadence change has something to fail against.
→ `Ship._reconcile_sos_contact`, `Ship.DATALINK_RELAY_HZ`

---

## Open / unscoped

### Heat/EM is the top perf cost — diagnosed, not fixed — *2026-07-26*
`heat_em_component_loop` is 9.99% of tick (1664 µs/frame), now the largest
single block after the relay dropped to 6.44%. Existing sub-probes already
break it down and account for 93% of it: `he_comp_loop` 777 µs / 4.66%,
`he_totals` 509 µs / 3.05%, `he_em_prep` 255 µs / 1.53%.

**The cost is the number of passes, not the cost of a lookup.** All of it is
ship-local arithmetic over ~30 component dicts, walked ~7 times per ship per
frame. Three redundancies, in order of size:

1. `_component_powered` runs TWICE per component per frame — once in
   `he_totals`' passive loop, once in `he_comp_loop`. It is the expensive
   predicate (4 dict reads plus the cached reactor check). Fold the passive
   accumulation into the main loop, or stash the flag on the first pass.
2. `get_total_power_rating("reactor")` is called in both `he_totals` and
   `he_em_prep`. Reuse is correct EXCEPT during overheat, where the drain
   between them makes the reused value one frame stale — decide deliberately.
3. `get_sys_health("sensors")` + `get_sys_max_health("sensors")` are two full
   scans producing one ratio.

Together ~400 µs (~25% of the block) with no new caching machinery. After
that, the structural win is routing `get_total_rating` through the existing
`_comps_by_type_cache` and extending the invalidate-on-change pattern that
`_get_reactor_power_rating_cached` already established (the M45 fix, which its
own comment records as converting ~2.9 ms/frame).

**Do NOT reach for StringName or an enum for speed.** At ~200 component-visits
per ship per frame the cost is the visits; a cheaper comparison cannot beat
deleting the pass. An enum for component `type` is still worth doing on
TYPE-SAFETY grounds — 238 authored `"type": "..."` sites where a typo is a
silent runtime miss today, the same bug family as the missing-`cooldown` dict
that stopped stations running physics at all — but that is a separate change
judged on its own merits, and CLAUDE.md's mechanical-multi-site-rewrite scar
applies. Nothing serializes `ship_components`, so there is no format risk.

### Docking damage SOLVED; one throughput regression open — *2026-07-26*
The corridor cut-out landed and station damage is essentially gone. Measured
by `test_dock_approach` (six scenarios, **~190s** — the fast instrument, not
the 3-hour sim):

| scenario | before | after |
|---|---|---|
| traffic / MediumStation | 0.300 hits/cyc, 0.44% HP | **0.01% HP** |
| traffic + rocks (Coldreach) | 0.250 hits/cyc, 0.43% HP | **0.000 hits, 0.00%** |
| Nexus Freighter + shuttles | 0.100 hits/cyc, 0.14% HP | **0.01% HP** |
| traffic / SmallStation | 0.033 hits/cyc | **0.000 hits** |

**What actually worked was NOT what the design doc predicted.** Three things
were tried and measured separately:
- **The cut-out (station avoidance active until inside the approach cone) is
  the whole win.** Steering at the seat with avoidance ON produces the
  arc-around for free.
- **Lane-following waypoints were pure cost and were removed.** Steering at
  the corridor MOUTH meant aiming at a point on the boundary circle while
  avoidance pushed the hull off it — arriving tangentially, never lining up.
  Cycle time tripled with a SINGLE ship, and the 300-mass Freighter circled
  for 600s and logged ZERO dockings. The corridor's real job is deciding WHEN
  the station stops being an obstacle; it is not a waypoint.
- **Widening the cone (45 -> 70 degrees) made damage WORSE** (Medium 0.01% ->
  0.50%) by releasing avoidance before hulls were aligned. Reverted.

**OPEN: solo shuttle / SmallStation is 3 cycles per 600s against a 4-per-223s
baseline** — ~180s/cycle vs ~55s, with one ship and nothing to dodge. Cone
width is NOT the cause (identical at 45 and 70). Traffic scenarios at the same
station are barely slower, so it is specific to having no other traffic to
jostle it into alignment. Next suspect is the interaction between
station-avoidance standoff and a berth seated close to a small hull's centre.

Also: `MAX_DAMAGING_STATION_CONTACTS_PER_CYCLE` is 0.50 and the old worst case
was 0.300 — the threshold certified the problem. Tighten it once the
regression above is closed.

### Docking approach design — *2026-07-26*
The highest-value item on the board. `PortChannel` (cone, guide, hatch cutout)
is referenced ONLY by `navigation_panel.gd` and `exclusion_hatch.gd` — both
rendering. The AI has never flown it: `step_dock_at` aims at a single point
~300u off the hull and passes `station.position` as `exclude_pos`, the body
steering will never dodge. So ships fly a straight line at a station with
avoidance disabled, and if the berth faces away that line goes through the
hull. Speed was never the problem — the braking work helped and could not fix
it, because a ship arriving slowly through a station still hits it.
Design (corridor-as-constraint, mouth→guide→capture waypoints, keep-out with a
cone cut-out replacing the binary `exclude_pos`) and the open decisions are in
→ `design_ideas/docking_approach_control.md`

### Station repair drain exceeds the cluster's entire trade surplus — *2026-07-26*
Self-repair burns ~7.6 lots/hr of REFINED+GOODS against a combined authored
margin of ~1.3/hr. Ironhold is the sharp case: only GOODS producer, 23%
margin, spends more than that patching itself, so GOODS reads UNSERVED
cluster-wide. This is a **navigation** finding, not an economy one — no rate
change fixes it.
→ `design_ideas/port_zones_and_channels.md`, "Rules and enforcement"
(published-limit rule specified, unbuilt)

### `SPEED_VIOLATION` has a constant, a table row, and no posting site
Consistent with the port-zones doc's own "specified and unbuilt" status.

### Economy sim runtime — *2026-07-26*
~2 real hours for 3 game-hours. The 15Hz relay cut `datalink_relay` from 18.1%
to 6.45%. Ideas not pursued: dropping the 15 beacons (all `Ship`-derived, full
pipeline each) at the cost of changed contact propagation; asteroid fields are
NOT droppable (rocks in a station approach were the 230× docking-damage
cause). The two-sim split was explicitly rejected.

---

## Recently closed (kept briefly for context, then delete)

- **Global `wanted_names` registry** — deleted 2026-07-26. Three writers, zero
  readers; the last ambient-global "enemy forever" structure.
- **Warrant unreachable after an identity change** — fixed 2026-07-26, with
  the `self_resolves_on_id` exception that keeps `NO_ID` self-resolving.
  → `scripts/tests/test_warrant_identity_change.gd`
- **Pirates stopped distributing across the cluster** — fixed 2026-07-26.
  Caused by M53d removing authored `route` arrays that hunt-point selection
  read. Strategy choice is still open (above).

### Docking: hold points would recover the last 85% — *2026-07-26*
`test_dock_approach` now PASSES with both the departure interlock and the
avoidance cut-out. Total station HP lost across all six scenarios:
baseline **851** -> both **255** (-70%) -> cut-out alone **15** (-98%).

**The interlock is a net negative today and is kept for FICTION, not
numbers** (a port handing a berth to an arrival while the previous occupant
backs out of it reads wrong). It costs 17x the damage and ~70s of throughput
because denying a grant does not stop the approach — the ship loiters near
the station re-requesting every tick and an unstructured holding stack forms
in the worst place. The rendezvous literature pairs an interlock with HOLD
POINTS precisely for this; we built the first half.

Give denied arrivals a designated waiting position outside the exclusion zone
and the interlock should stop costing anything. That is the one layer of the
four-layer model we still have no geometry for.

Also still true: `MAX_DAMAGING_STATION_CONTACTS_PER_CYCLE` is 0.50 and the
worst surviving case is 0.067 — tighten it, or it will certify a regression.

### Interlock disabled pending hold points — *2026-07-26, decided*
`INTERLOCK_ENABLED = false` in `Ship.issue_docking_grant`. Code and full
measurement retained at the call site; only the reservation write is off.

Shipping config is **cut-out only**: total station HP lost across
`test_dock_approach`'s six scenarios **851 -> 15 (-98%)**, and five of six
scenarios now take ZERO damaging contacts. Projected effect on the economy:
self-repair ~12.5 lots/hr -> ~0.25, against a combined authored REFINED+GOODS
margin of ~1.33/hr — i.e. this should flip the cluster from structurally
insolvent (repair ~9x the surplus) to solvent. **Projection, not measured** —
confirm with a 180-min `economy_traffic` run against the 12.54 baseline.

Re-enable the interlock together with HOLD POINTS, not before. Every duration
tried was a net negative (long: ships pile up waiting; short: more hold grants
at once so they pile up arriving) because denying or clearing a ship never
tells it WHERE TO BE.

### Approach fix outside the standoff — CLOSE, needs arrival + hysteresis — *2026-07-27*
Tried and reverted, but it produced the **best damage numbers of any variant**:
total station HP **15** across `test_dock_approach` (vs 238 shipped), with the
Coldreach rock field back to **0.00%** and `traffic/SmallStation` 0.00%.

Construction: aim at a point on the berth axis at **2x the avoidance standoff**
(`actor.radius + station.radius + Steering.MARGIN`), in free space, so the hull
arrives ALIGNED without fighting repulsion; then a short run down the axis it
is already on. Lined-up test by axis projection (`along > 0` and
`lateral <= capture_radius`), not distance.

**Why it was reverted:** solo docking at unzoned stations fails outright
(0 cycles; `nav_gauntlet` fails at Deepcut/Coldreach/Slag Bay). Traffic
scenarios at the SAME stations pass, so ships only get in when jostled.
`_cruise_toward` has no arrival condition, so a hull reaching the fix point
overshoots and orbits it, `lateral` oscillates across the threshold, and it
dithers between "go to fix" and "go to seat". Needs an arrival test plus
hysteresis — exactly what the zoned corridor gate already has and this did not.

This is the mechanism the unzoned outposts (~45% of the economy's repair
drain) and the departure interlock are both waiting on. Worth finishing.

### Approach fix + arrival latch — WORKS, blocked on two time budgets — *2026-07-27*
Stashed as `approach-fix-with-latch` (`git stash list`). **Best result yet and
the first that passes `test_dock_approach` outright**, all six scenarios
completing their cycles:

| | shipped | with latch |
|---|---|---|
| total station HP | 238 | **86** (851 baseline, **-90%**) |
| traffic + rocks | 0.43% | **0.14%** |
| traffic / SmallStation | 0.01% | **0.00%** |
| solo / SmallStation | 4 cyc / 223s | 4 cyc / 320s |

The latch is what the earlier attempt lacked: `_cruise_toward` has no arrival
condition, so a hull reaching the fix overshot and orbited, `lateral`
oscillated across the threshold, and it dithered between fix and seat forever.
Latch on arrival at the fix; drop it only if the hull ends up genuinely behind
the berth.

**BLOCKED ON (unverified hypothesis):** `test_nav_gauntlet` still fails at
Deepcut and Slag Bay, `test_visitor_itinerary` at EXIT_AT — but the visitor now
gets to **640 units from the exit** (was 15,046) and nav_gauntlet is down from
three stations to two. Solo cycle time is **+43%** (223s -> 320s) because the
fix adds a genuine detour, and both those tests have budgets calibrated to the
old direct approach. **Verify that before touching the budgets** — "the test
timeout is wrong" is exactly the reasoning that needs checking, not assuming.

Next: instrument whether those two are timing out mid-progress or genuinely
stuck, then either widen the budgets with justification or shorten the detour
(fix at 1.5x standoff instead of 2x).
