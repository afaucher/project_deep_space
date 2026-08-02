# M51 — Pirate guild director: detailed design

Parent: [m48_m55_economy_piracy_roadmap.md](m48_m55_economy_piracy_roadmap.md);
the director pattern (ledger + policy tick, the director honesty rule) is in
[jobs_and_itineraries.md](../design_ideas/jobs_and_itineraries.md) §3 — read
it first. Deliverable: the piracy loop becomes self-sustaining — kill the
pirate and a replacement "trader" comes through the wormhole minutes later
under a fresh cover identity; success breeds more pirates (bounded), losses
thin them (floored at 1). No player-facing surface except a debug toggle —
the guild is an invisible hand.

## Grounding facts (verified against source)

- `ClusterManager` (scripts/cluster/cluster_manager.gd): `records: Array`
  of ClusterEntity; `tick(dt)` dead-reckons dormant movers then
  `_reconcile()`s liveness; `_promote(rec)` builds `rec.hull_script.new()`,
  applies `rec.name` → ship_name, `rec.iff_tags`, `rec.transponder_flag`
  (AFTER add_child), then `_attach_ai(rec, node)` which switches on
  `rec.behavior` (route/cargo keys today). `_demote(rec)` reads state back
  and frees. Tests drive `tick()` manually for determinism (viewpoint_node
  null).
- **The cluster layer has NO concept of death.** Nothing notices a live
  ship became a hulk (`is_dead == true`; hulks are never freed, so
  `rec.is_live()` stays true). If a hulk's record ever demoted and
  re-promoted, `_promote` would resurrect a fresh, alive hull. M51 fixes
  this where it bites (LOST pirates' records are removed); the general
  traffic case is filed as a separate follow-up task.
- Wormhole: a record with `kind == ClusterEntity.Kind.WORMHOLE` ("Nexus
  Wormhole", home_cluster.gd id 500). Cargo lanes: TRAFFIC records whose
  `behavior` carries `{"route": [a, b], "cargo": true}` — public knowledge
  a guild plausibly has (they watch the lanes). The director derives BOTH
  from `records` at tick time instead of carrying authored copies.
- M50 surface: `build_pirate()` (ai_tree_factory), `assign_job(job)` +
  `loot_takes` (ship.gd), the canonical hunt job shape
  (implementation_plans/m50_pirate_tree_design.md), pirate hulls
  `pirate_ore_shuttle.gd` / `armed_pinnace.gd`.
- Debug knobs: append ONE entry to the `DebugSettings` autoload's
  `OPTIONS` registry; read with `DebugSettings.get_choice(key)` (CLAUDE.md).

## New: `scripts/directors/pirate_guild.gd`

RefCounted (preload-const convention, standing.gd-style header). Owned by
and ticked from ClusterManager:

- `ClusterManager` gains `var directors: Array = []` and, at the end of
  `tick(dt)`: `for d in directors: d.tick(dt, self)`. That's the ENTIRE
  cluster-manager surface for directors (plus the `_attach_ai` branch
  below). Campaign bootstrap (wherever home_cluster's ClusterManager is
  wired — follow the existing load path) appends a configured PirateGuild;
  the sandbox gets none.
- Construction: `PirateGuild.new(config: Dictionary)`. Config is DATA (the
  M54 story-phase lever), with defaults:

```gdscript
{
  "policy_period": 10.0,        # s between policy passes (dt-accumulated)
  "presumed_lost_delay": 45.0,  # OVERDUE -> resolved, s
  "arrival_window": [120.0, 300.0],  # eta roll, s
  "base_cap": 1, "max_cap": 3,       # floor of 1 pirate, bounded growth
  "takes_per_cap_raise": 2,     # take_streak needed to raise the cap
  "losses_per_cap_cut": 2,      # loss_streak needed to cut it
  "cashin_radius": 8000.0,      # "vanished near the wormhole" = cashed out
  "hull_mix": [pirate_ore_shuttle, armed_pinnace],  # scripts, alternated
  "name_pool": ["Fair Trader", "Slow Light", ...],  # cover + relight names
}
```

  Tests pass a FAST config (period 0.5, delay 2.0, window [4, 8]) — config
  is data, so this is legitimate tuning, not a test backdoor.

## The ledger (plain serializable state on the guild)

- `members: Dictionary` — record_id → `{state, cover_name, relight_name,
  last_seen_pos, last_loot_takes, overdue_since}` with states
  `SCHEDULED | ACTIVE | OVERDUE | LOST | CASHED_OUT` (resolved members are
  kept for the ledger's history; they hold no record refs).
- `arrivals: Array` — `[{eta_remaining, cover_name, relight_name, hull_idx}]`.
- Totals: `takes_total, losses, take_streak, loss_streak, cap`.
- Nothing here references live nodes across ticks — record ids and plain
  values only (serializable for saves later).

## The policy tick

`tick(dt, cluster)` accumulates dt; every `policy_period`:

1. **Check-ins** (the honesty rule made mechanical — the director reads
   only its OWN members' state, the fiction of a radio report): for each
   ACTIVE member, find its record. Live and not dead → refresh
   `last_seen_pos` / `last_loot_takes` (read off the live node). Dead,
   record gone, or node gone → `OVERDUE` with `overdue_since` stamped
   (once — don't re-stamp).
2. **Resolve overdue** past `presumed_lost_delay`: vanished (NOT observed
   dead) with `last_seen_pos` within `cashin_radius` of the wormhole →
   `CASHED_OUT`: `takes_total += last_loot_takes`, `take_streak += 1`,
   `loss_streak = 0`. Anything else (observed dead, or vanished elsewhere)
   → `LOST`: `losses += 1`, `loss_streak += 1`, `take_streak = 0`, and
   **erase the member's ClusterEntity from `cluster.records`** (the hulk
   node stays in the world as ordinary wreckage; the record must go or the
   cluster will eventually resurrect it — the death gap above).
3. **Cap adjust**: `take_streak >= takes_per_cap_raise` → `cap += 1`
   (clamped to max_cap), reset take_streak; `loss_streak >=
   losses_per_cap_cut` → `cap -= 1` (clamped to base_cap), reset
   loss_streak.
4. **Floor**: while `active_count + overdue_count + arrivals.size() < cap`
   → schedule an arrival: `eta_remaining = randf_range(window[0],
   window[1])` (global seeded RNG — determinism under the test seed),
   cover + relight names drawn from `name_pool` avoiding names in use by
   ACTIVE/SCHEDULED members, hull alternating through `hull_mix`.
5. **Spawn due arrivals** (`eta_remaining -= policy_period`, spawn at
   <= 0): build a ClusterEntity — kind TRAFFIC, `name = cover_name`,
   `hull_script = hull`, `transponder_flag = Standing.FLAG_CIVILIAN`,
   `iff_tags = ["PIRATE_GUILD_<n>"]` (unique per member — pirates are not
   crypto-friends of each other in v1), `pos` = wormhole pos (+ small
   seeded scatter), `behavior = {"pirate": true, "job": <hunt job>}`.
   Member goes ACTIVE keyed on the record id.

**Hunt-job assembly** (the M50 canonical shape, parameterized from records):
staging point = a seeded point off the beacon road (offset perpendicular
from the wormhole→lane direction, well outside comms range of stations);
`lane_pos` = a seeded point along a randomly-chosen cargo lane's route
segment; exfil = another off-road dark point; exit = the wormhole pos;
RELIGHT uses `relight_name` + FLAG_CIVILIAN. Same abort topology as M50's
test job (third_party → exfil from INTERCEPT onward; victim_lost → hunt).
Assembled as pure data in the guild — `_attach_ai` just delivers it.

## ClusterManager `_attach_ai` branch

Before the route/cargo checks: `if behavior.get("pirate", false):
node.add_child(AITreeFactory.build_pirate());
node.assign_job(behavior.get("job", {}).duplicate(true)); return`. The
duplicate matters — a demote/promote cycle must hand the fresh node a
clean copy, not the half-run job the previous body mutated. (Job progress
does NOT survive demotion in v1 — a re-promoted pirate starts its hunt
over; acceptable, the record keeps its position, and a full fix is
director/M53 territory.)

## Debug surface

One `DebugSettings.OPTIONS` entry (e.g. `pirate_guild_log`: off/on). When
on, the guild prints one line per policy pass: counts by state, cap,
streaks, pending etas. That's the whole player-facing footprint of M51.

## Tests — `test_pirate_guild` (manual `cluster.tick()` drive, fast config)

- (a) **Bootstrap floor**: fresh guild, empty roster → one arrival
  scheduled → after its eta, exactly one ACTIVE pirate record exists at
  the wormhole, carrying build_pirate + an assigned hunt job (promote it
  and check the tree/job).
- (b) **Replacement on kill**: hulk the active pirate (call `take_damage`
  to destruction or `hulk()` directly) → OVERDUE → LOST after the delay →
  its record is GONE from cluster.records (no-resurrection assertion:
  tick past demote/promote boundaries, count pirate hulls, must stay 0
  until the replacement) → a replacement arrival lands within the window
  under a DIFFERENT cover name; `losses == 1`.
- (c) **Cash-out**: walk an ACTIVE member's node to the wormhole
  (teleport per CLAUDE.md's body_set_state + wake rules, or drive
  last_seen_pos via a scripted exit), set `loot_takes = 1`, free the node
  → CASHED_OUT after the delay, `takes_total == 1`, take_streak bumped,
  NOT counted as a loss.
- (d) **Streaks move the cap both ways, bounded**: scripted sequences of
  cash-outs then losses; cap climbs to max_cap and never past, falls to
  base_cap and never below; floor keeps the roster at cap throughout.
- (e) **Determinism**: two fresh guilds with the same config, same seed
  (`seed(N)` before each), same scripted event sequence → identical
  arrival etas and cover names.
- Full build.ps1 gate green; perf_combat band unaffected (the guild is one
  O(members) pass every 10s).

## As-built notes

- **The cash-out path required a second cluster fix the spec missed**: the
  production despawn (EXIT_AT's queue_free) leaves the record in
  `cluster.records` with a dangling live_node — `_reconcile()` would
  re-promote a fresh, alive pirate the next pass, and the member would
  never resolve CASHED_OUT (the check-in finds it alive again). Fixed in
  `_reconcile()`: records whose live node was freed EXTERNALLY are retired
  (removed). Discriminator: `_demote()` nulls live_node, so external death
  is a dangling reference — and since **a freed instance compares EQUAL to
  null in GDScript**, the check must be `typeof(live_node) == TYPE_OBJECT
  and not is_instance_valid(live_node)`, never `!= null`. test_pirate_guild
  scenario (c) drives this real path (queue_free + tick), not a synthetic
  record splice.
- SCHEDULED exists in the MemberState enum for the doc's state list but is
  never stored in `members` — a scheduled arrival has no record id yet, so
  it lives only in `arrivals`; name-avoidance treats both alike.
- Member entries carry an `observed_dead` flag (needed to distinguish
  "observed dead" from "vanished" at overdue resolution).
- Spawned record ids start at 9000 — clear of every authored home_cluster
  id.

## Out of scope (lands later)

Patrol/SOS interdiction (M52). Trade/traffic directors + CargoRun
migration (M53). Story-phase config-table swaps + player consequences of
"held" (M54). Physical cargo/economy (M55). Fixing the death gap for
non-pirate traffic (filed as a separate task). Pirates operating in force
/ crypto-linked pirate wings (arrival-mix option, later).

## 2026-08-01 — the omniscience objection now has an honest answer

The standing objection to this director is that it sees the cluster. Verified
against the tree 2026-08-01: it does not need to. `step_select_victim` already
produces, from the hunting pirate's OWN sensors at a known `lane_pos`, every
input a target-selection map needs — `all_fresh_vessels` is a prey-and-witness
count at that position (`job_steps.gd:915`), and the step's two abort reasons
already separate the two failures that matter: *no prey here*
(`job_steps.gd:891`, time budget) versus *prey here, couldn't land it*
(`:898`, attempts).

So the guild needs its returning members' hunt outcomes recorded **with
position** — not a wider view. Scheduled as M60
(`m57_m61_information_economy_roadmap.md`), which also gives
`profitless_streak`/`backoff_factor` (`pirate_guild.gd:134–135`) a spatial axis:
"that lane is finished, try the other one" instead of "the guild is discouraged".

That milestone also re-files the cash-out bug. `vanished_near_wormhole` needs a
`policy_period` 10s check-in inside a `cashin_radius` 8000u ring the pirate
crosses in ~11s, so a successful robbery books as `presumed LOST`. Filed as
accounting; it is also an **information** failure — a pirate that never cashes
out never delivers its hunt outcome and never picks up a fresh map. It is the
guild's only sync point, because a pirate guild has no station.

## 2026-08-02 — why campaign takes are zero, measured rather than guessed

`information_loop` at 6-8 concurrent pirates, 10 haulers, 60 game-minutes:
**15 hunts, 0 takes** (12 returned_empty, 3 lost). Six times the authored
pressure changed nothing, so this is not a volume problem.

Reconciling with `pirate_scenarios`' 26/36: that harness pre-positions a pirate
at the midpoint of a **14,000u** lane with a victim inbound. It measures
CAPABILITY. The campaign has **~300,000u** lanes against a 20,000u detection
radius, and measures ENCOUNTER RATE. Both numbers are right; a harness that
supplies the encounter cannot discover that encounters do not happen.

Breakdown from the abort reasons (`JOB_LOG=1`, 25-min run):

| Failure | Evidence | n |
|---|---|---|
| Never found prey | `hunt time budget (Ns) spent` | **8** |
| Witness present at the take | `TAKE_ALONGSIDE ABORT (third_party_in_range; witness at 6000) -> exfil` | 2 |
| Victim bolted mid-hold | `TAKE_ALONGSIDE ABORT; victim bolted (complied_stop cleared)` | 1 |
| Ran out of attempts | `hunt budget spent (N attempts)` | **0** |

**SPEED IS NOT THE CAUSE, and that is worth recording because it is the
intuitive suspect.** ArmedPinnace is `max_speed 2000` against CargoShuttle's
`1000`. The low observed capabilities in the comply-or-run log (287, 299) are
the pirate CRUISING at 300 inside `SELECT_VICTIM`, not its capability -- and
M52a's overtaken-check demonstrably works: a hauler ran, was overtaken at 700,
and complied. Tuning speed would move a number that is not binding.

Two distinct fixes, in priority order:

1. **Encounter (dominant).** 8 of ~13 hunts ended having seen nobody. This is
   geometry: a 20,000u detection radius on a 300,000u lane. Lurk placement,
   detection range, or lane-adjacency are the levers -- not hunt duration, which
   the earlier A/B already pushed to 900s for one take.
2. **The witness rule at the take.** TWO pirates reached `DEMAND_STOP done`
   (actual compliance) and still lost it to a third party within
   `_R_THIRD_PARTY` (~6000u). With 10 haulers, 2 patrols and 13 stations in one
   cluster, a pirate working a lane is rarely alone at that radius. Worth asking
   whether "alone" should scale with how far from traffic the pirate has pulled
   its victim, rather than being a fixed ring.

Everything in M57-M59 is downstream of a robbery, so until (1) is addressed the
incident/mail/risk chain cannot be exercised in a campaign at all -- `risk p95`
was 0.0 across 5,206 routing decisions, which is the same fact from the other
end.

### Proposed: LANE_RUN — the posture that was named but never built

`_roll_posture()` picks `dark_lurk` or `false_flag_cruise`, and the header
describes the latter as *"one more freighter closing to demand range"*. But the
posture only changes whether `AWAIT{clear}->GO_DARK` runs before the hunt —
**both postures then execute the same `SELECT_VICTIM`, which HOLDS STATION**
inside a 2,500u lurk radius (`_hold_station` once within `lurk_radius`). The
"cruise" is the staging approach, not the search. Nothing in the game runs a
lane.

That matters because ENCOUNTER is the measured dominant failure. A parked hull
covers `2 * detection / lane_length` of a lane — even with the new 45,000u
passive array that is ~30% of a 300,000u lane, and only while prey happens to
pass. A hull that TRANSITS the lane sweeps all of it per pass.

**The trade, which is what makes it a posture rather than a straight upgrade:**
running the lane means running LIT under a cover identity — visible, identified,
and repeatedly logged by everything it passes (the beacon road is explicitly the
EM-loud "sees and reports" corridor, `_R_STATION_AVOID` exists because lane
endpoints are stations). Dark lurking is invisible but nearly blind; lane
running sees everything and is itself seen.

**Every piece of the risk model already exists:**

- the cover identity is transponder name + flag;
- `Standing.subject_key` keys warrants on `name:` when a name is claimed, so a
  REPORTED cover name is precisely what becomes wanted;
- **M58's notarization is what burns it** — a victim carries the cover name to
  port, an authority co-signs, and that identity is now enforceable by everyone
  flying that flag;
- `Ship.identity_documents` is a FINITE array, and `step_relight`'s `from_kit`
  draws the next unused paper and ABORTS when the kit is empty.

So the loop closes without inventing anything: **run the lane → get seen → get
reported → the name burns → spend a document → the kit runs out.** That gives
M58's notarization its first real consequence (today a notarized warrant has
nowhere to bite) and turns identity papers from flavour into a metered resource.

Open questions, deliberately not decided here:

- Does the runner flip on ANY viable prey, or only when alone? The witness rule
  already costs takes at 6000u; a lane-runner is by definition in traffic.
- Does being *scanned* burn a name, or only being *robbed while wearing it*?
  Only the latter creates evidence, and the former would make the posture
  unplayable.
- Should the kit's size be the real dial on pirate aggression, rather than
  `hunt_seconds`?

**Sequence AFTER the passive-array A/B reports.** Both changes attack ENCOUNTER,
and landing them together would make the measurement unattributable — the exact
mistake that made the LOT_SIZE regression hard to read.

#### LANE_RUN refined: stalk, then decide what to leave behind

**Flip only when ALONE.** The runner shadows prey at the edge of its own
sensors and waits for third parties to clear, rather than closing immediately.
Mechanically this INVERTS a check that already exists: `_third_party_in_range`
is currently an ABORT condition, and here it becomes a WAIT condition. That
turns the two measured witness-aborts (pirates that reached `DEMAND_STOP done`
and lost the take to a contact at 6000u) from failures into patience, which is
the more interesting behaviour anyway — a predator that waits reads as competent
where one that flees reads as broken.

Following at sensor limit is also what the new passive array is FOR: it hears a
loud hauler without emitting, so trailing is possible without being the reason
the victim runs.

**Destruction is the pirate's counter-move to the information economy.** This
is the consequence worth being deliberate about, because it is a systems
interaction rather than a flavour choice:

- a victim that SURVIVES carries its incident to port, where M58 notarizes it —
  the pirate's cover name burns and a warrant becomes enforceable flag-wide;
- a victim that is DESTROYED files nothing. Its `incident_log` lives on its own
  ClusterEntity record, and that record is erased with the hull.

So killing the witness is genuinely effective, and it SHOULD be — but it does
not buy silence, because `TrafficGuild._resolve_overdue` records its OVERDUE
incident on the GUILD's own log *before* calling `_erase_record`. The signal
degrades rather than vanishing:

| Victim | What the world learns |
|---|---|
| Survives | who (cover name), where, notarized, enforceable |
| Destroyed | "a hull stopped arriving, last seen near here" |

That is exactly the property M57 claimed for OVERDUE — "the only intelligence
signal that survives a pirate killing the sole witness" — and it lands here
without anything new being built.

**Log-wiping interacts with tier-1 relay, and the interaction is free.** An
incident is written to the victim's record, but if the victim was within comms
range of ANY crypto-kin when it happened, the mailbag relay already carried it
at 15Hz. So wiping or destroying only suppresses the report when the victim was
ISOLATED — which is the same condition the pirate already needs in order to
strike. **Being alone protects both the robbery and the cover-up**, from one
geometric fact, with no special-casing.

**Escalation ladder (future, not scoped here).** Each rung has a different cost
and a different economic footprint:

- **Prize** — take the hull. `Ship.hulk()` already exists as the state, and
  design_ideas/hulk_revival_contract.md is the natural home.
- **Destroy outright** — no loot, maximum silence, and it removes a hauler from
  the economy permanently rather than taxing it. This is the rung that turns
  piracy from something an economy absorbs into something that depopulates it,
  so it wants to be rare and expensive.
- **Kill the crew / take the crew** — depends on the human-space axis (crew
  derived from `living_quarters`); taking crew makes people a cargo type and so
  depends on M55a manifests.

The severity ladder should also feed `Standing`: robbery and murder are not the
same offense, and the existing `_OFFENSE_TABLE` already grades response class
and `authorizes_force` per offense — so escalation has somewhere to land.

#### Prize-taking: the hull leaves under one of the pirate's clean IDs

Definition (2026-08-02): a prize is not salvage. The captured hull receives a
clean identity from the pirate's kit and **exits under pirate control**.

**The architecture already fits.** Allegiance is a RECORD property applied at
promotion — `cluster_manager.gd` does `if rec.behavior.get("pirate", false):
add_child(AITreeFactory.build_pirate())`, and the papers ride the same record
via `rec.behavior.get("identity_kit", [])`. So capture is *editing the victim's
record*: set the pirate behavior, hand it a document, re-crew on the next
promote. That is the same "the record is canonical" pattern the incident log,
the mailbag and the docking registry all follow. No ownership concept to invent.

**The kit becomes the single currency for both pirate behaviours, which is what
makes it a real decision.** `Ship.identity_documents` is finite and
`step_relight`'s `from_kit` ABORTS when exhausted. Under LANE_RUN a document is
armour for yourself; under prize-taking it is a disguise for a stolen hull.
Every clean ID is one or the other, never both — so kit size, not
`hunt_seconds`, is plausibly the honest dial on pirate aggression.

**The prize is self-incriminating, and this was designed in before anyone
proposed prizes.** `identity_documents`' own comment: *"The documents stay
aboard (used or not): a future ship-search mechanic reads THIS array and
cross-references the wanted-names registry — a hold full of papers, some of them
confirmed pirate names, IS the evidence."* M55e's boarding/inspection is exactly
that reader. So the very document that lets a prize fly is what convicts it when
a patrol boards. The counter-play is obvious and costly: run the prize with a
thin kit aboard, or accept the risk.

**A prize also inherits its victim's `incident_log` and `mailbag`** — including
the incident naming its own captor. Capturing a hull means capturing the
evidence against you, which is what makes the log-wiping idea a real chore
rather than flavour, and it stacks with the papers: wiping the log does not
remove the documents.

**Economically the three rungs are different in kind, not degree:**

| Rung | Effect on the traffic pool |
|---|---|
| Rob | a **tax** — the hull returns to service |
| Destroy | a **deletion** — hull gone, replacement scheduled by the guild |
| **Prize** | a **transfer** — hull leaves the economy AND joins the other side |

Transfer is the strongest of the three and should be rarest. It also compounds:
a prize given the band's `iff_tags` joins the tier-1 relay net, so a captured
hull becomes a node in the pirate information network — the mail model's own
mechanics applied to a stolen ship, again with nothing new built.

Depends on: crew disposition (a prize with its original crew aboard is
incoherent), so this sits behind the human-space axis and the kill/take-crew
rungs.

### RESULT: the passive array works (A/B, 2026-08-02)

Identical config both sides — 6-8 concurrent pirates, arrivals 20-60s, hunt
300s, 10 haulers, 60 game-minutes. One variable changed: ArmedPinnace gains a
45,000u `passive_em` array.

| | before | after |
|---|---|---|
| robberies completed | 0 | **2** |
| incidents recorded | 0 | 2 |
| stations holding foreign news | 0 of 13 | **7 of 13** |
| patrols holding foreign news | 0 of 2 | **2 of 2** |
| risk p95 / max | 0.0 / 0.0 | 4.6 / 5.3 |
| decisions changed by risk | 0 of 5206 | **250 of 5199** |
| chain breaks at | stage 1 | **stage 4** |

Encounter was the binding constraint, as diagnosed. The chain now runs four
stages deep.

**Two things previously unverifiable are now confirmed in a live campaign:**

- **Tier-1 mailbag relay works.** Patrols hold foreign news 2 of 2, and the
  authored patrol never docks — so that news arrived by radio. This is the M58
  half that was missing entirely, verified end to end rather than by a test that
  hand-set the mailbag.
- **Cargo actually reroutes.** 250 of 5,199 decisions differ from their
  risk-blind counterfactual.
- **Latency, measured**: a station learned in ~0.1s (kin relay), a patrol in
  ~1005s (~17 min). "Information has a position and a velocity", as a number.

**Stage 4 is probably CORRECT behaviour, not a break.** The comply-or-run log
shows `x1.6` ratios — pirates demanding under the PIRATE flag — and pirates run
`GO_DARK`, so the victim holds no transponder record, `pirate_claimed` is `""`,
and `notarize_from` refuses. That is the deliberate 2026-08-01 rule: an
authority cannot charge "a ship, about this big". **Going dark defeats
notarization by design.** Two hulls were also lost, so a victim may not have
survived to report. The instrument cannot yet separate those two causes — it
should record WHY notarization declined.

**Instrument bug found by this run.** The precondition line printed "RISK NEVER
GOT BIG ENOUGH ... UNTESTED" while the counterfactual showed 250 changed
decisions. `HYSTERESIS_MARGIN` is the bar for RE-PLANNING AN EXISTING JOB, not
for changing which route wins a fresh search; near-equal lanes flip on a few
points. Recalibrated: the check now only distinguishes "risk was literally
always zero" from "risk existed — read the counterfactual", because the
counterfactual is the direct measurement and the margin comparison was giving
exactly the wrong verdict.

Still open: takes remain rare (2 in 60 min at 6-8x authored pressure), 17 hunts
still ended finding nobody, and `returned_empty` is 14. Encounter is improved,
not solved — which is what LANE_RUN is for.
