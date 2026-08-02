# M48–M55 — Economy & Piracy: the living Drift

Parent design: [economy_and_piracy.md](../design_ideas/economy_and_piracy.md).
This is the route map; each milestone gets its own detailed design doc when
picked up (the M39–M44 convention). Ordering is by dependency: the standings
rework unblocks everything, the pirate loop lands as early as possible (the
stated short-term focus), physical cargo comes after the loop is proven.

## What already exists (verified against the code, 2026-07)

- **World**: 3 hubs, 3 mining outposts on asteroid fields, the 7-beacon road
  Ironhold↔Drift Market, the Nexus wormhole out in dark space, 2 LAC patrols
  looping hubs, 2 cargo shuttles on fixed lanes (one off-road:
  Ironhold↔Coldreach). `home_cluster.gd`.
- **Sim**: ClusterManager promote/demote over ClusterEntity records; dormant
  dead-reckoning; behavior wiring at promote (route→patrol tree, cargo→cargo
  tree). Liveness policy has an unused ROUTE_TICK middle tier (future hook).
- **AI**: beehave trees from `ai_tree_factory.gd`; leaves for acquire/steer/
  fire/flee/follow-route/cargo-run/station-keeping/broadcast-transponder.
  Hostile == classification "UNIDENTIFIED VESSEL" (the thing M48 replaces).
- **Sensors/IFF**: EM-keyed classify_contact; transponders broadcast
  name/location and can go dark (`set_transponder_active(false)`); NPC
  profiles + dialogue over comms; datalink track sharing; contact tracks die
  at CONTACT_TIMEOUT (identity laundering falls out free).
- **Docking**: station berths, grants, port zones + channels + NPC
  compliance (M46/47). No ship-to-ship docking.
- **Story**: StoryState flags, MissionLog (GO_TO_AREA/TALK_TO/DELIVER),
  ContractFeed nav-layer markers, story overlay + characters.
- **Perf**: ~5.6ms avg physics tick at full missile saturation (16.7 budget);
  `perf_combat` census tracks population. Headroom exists; caps still owned
  by directors.
- **Not present**: standing/suspicion of any kind, damage attribution
  (take_damage has no attacker), structured ship-to-ship hails, surrender,
  cargo contents, currency, ship-to-ship docking/boarding, SOS, mission
  *generation* (only authored missions), any director beyond sandbox spawn.

## M48 — Standings & flags (IFF v2) [foundation]

The enabling refactor; nothing else lands without it.

- Transponder gains a `flag` field (public allegiance declaration; spoofable
  data, distinct from crypto `iff_tags`). Fused into contact records.
- **Model revised after M48 shipped** (see design doc): standing is FOUR
  tiers, not five. "Suspicious" is NOT a standing — it has no shared meaning
  (patrol "acting like a predator" vs pirate "prey/trap") and belongs in each
  AI's own assessment, not the shared contact record. The shipped M48 code
  carries a vestigial SUSPICIOUS tier and needs a small simplification (see
  "M48 code delta" at the end of this section).
- Per-observer **standing** on contact tracks: FRIENDLY / NEUTRAL /
  UNREPORTED / HOSTILE + a reason string. Rules: crypto match → FRIENDLY;
  name+flag reported and flag not known-bad → NEUTRAL; not reporting →
  UNREPORTED (a fact anywhere; only controlled space makes it a patrol
  matter); known-enemy flag or witnessed aggression or manual flag →
  HOSTILE. Standing dies with the track.
- **Damage attribution**: `attacker_id` plumbed through take_damage and all
  weapon paths (lasers, missile warheads — missiles already know owner_id).
  Aggression event = attributed damage or a witnessed non-authority
  DEMAND(STOP) (M49).
- Witness rule: an observer that (a) has a live track on the aggressor and
  (b) saw the aggression event marks HOSTILE and shares it on datalink with
  attribution. Ships and stations witness attacks on THEMSELVES too —
  firing on a station is the canonical case: the station marks the shooter
  instantly and the datalink spreads it, no third-party observer needed.
  The pirate flag (below) is additive, not a replacement for this.
- The three subjectivity rules from the design doc ship WITH the witness
  rule (they are corrections to it, not extras): the assistance exemption
  (attacking a target HOSTILE-to-me is not aggression), authority flags
  (a DEMAND(STOP) under a flag I consider legitimate is a police stop),
  and the attribution confidence gate (apparent target flips HOSTILE on
  first hit; third parties and single stray hits need N attributed hits via
  a HIDDEN counter on the track before flipping — no visible tier). Tests:
  patrol does NOT flip on a ship engaging a patrol-marked pirate; bystander
  does not flip on a militia-flag interdiction; one stray splash does NOT
  permanently mark a civilian's home patrol HOSTILE.
- **The pirate flag ships in M48** as the first known-enemy flag: flying it
  → automatic HOSTILE to every non-pirate observer, no witnessing needed.
  This is deliberately double-duty: fiction-side it's "showing colors" (see
  M49/M50 — pirates normally run quiet), and test-side it's the migration
  lever for `acquire_target_leaf` targeting HOSTILE only. Every combat test
  that spawns opposing iff_tags and expects a fight migrates by hoisting
  the pirate flag on one side — no test-only standing backdoor. Audit
  test-by-test, but the fix per test is one line.
- Faction **wanted-names list** (militia intel, NOT a standing): shared
  HOSTILE markings carry the claimed name. A new track claiming a wanted name
  stays NEUTRAL by standing (names are cheap talk) but draws the patrol's
  *assessment* — a look, a challenge, a shadow (M52). This is what makes
  laundering require a fresh identity instead of a transponder flicker
  (design doc: breaking the track is necessary, not sufficient).
- Player UI: contacts panel shows standing + reason; "MARK HOSTILE" button.
- Tests: dark stranger is NOT auto-engaged; witnessed attack flips standing
  and propagates on datalink; manual flag works; track loss forgets.
- **Risk**: the combat-test audit is the real cost of this milestone.
  Budget for it; it is the price of unwinding shoot-on-sight.
- **M48 code delta — DONE** (post-ship simplification, folded the revised
  model into the shipped 5-tier code): dropped the `wanted-name → SUSPICIOUS`
  rule from `Standing.compute_standing` (wanted-names registry stays as the
  M52 patrol-assessment input; `is_wanted` now called only by the patrol tree
  when it lands); the stray-fire logic is now a hidden `aggro_hits` counter
  that flips HOSTILE at the threshold with NO intermediate SUSPICIOUS write;
  removed the SUSPICIOUS decay block in `ship.gd`, the SUSPICIOUS row from
  `contacts_panel`'s color map, and the `SUSPICIOUS` constant + severity
  entry. Standing is four clean tiers; `test_standing_rules`/`test_standing_e2e`
  updated; full gate green.

## M49 — Hail protocol, the DEMAND verb, the honored stop

> **SHIPPED.** `scripts/comms/hail.gd` (wire format + delivery),
> receiver rules + honored stop in `ship.gd`, `threat_response_leaf.gd` /
> `challenge_leaf.gd`, comms/contacts-panel verbs + nav-layer SOS markers.
> Tests: `test_hail_protocol`, `test_honored_stop`, `test_patrol_challenge`.

> **Revised before execution** — the original verb list (CHALLENGE,
> DEMAND_SURRENDER, COMPLY, SOS) collapsed under a scenario differential:
> CHALLENGE and DEMAND_SURRENDER differ ONLY in what's demanded, and
> "surrender" is the receiver's interpretation, not a wire message (the
> SUSPICIOUS lesson again). Full reasoning + scenario table in
> [comms_verbs.md](../design_ideas/comms_verbs.md) — that doc is the spec.

- Structured comms verbs (machine-to-machine, comms-range-gated, NOT
  dialogue), riding the existing transient_events/comms plumbing:
  - `DEMAND {rung: IDENTIFY | STOP, target}` — one directive verb, two
    rungs. IDENTIFY compliance is *behavioral* (relight, keep flying — the
    transponder is the answer, no reply verb). STOP implies IDENTIFY;
    compliance is the honored state below.
  - `COMPLY {in_reply_to}` — STOP rung only (the honored state must be
    *declared*); in_reply_to required (simultaneous demands happen —
    pirate strikes just as the patrol arrives).
  - `RELEASE {target}` — resume; a held ship also resumes if the issuer
    departs/dies.
  - `SOS {nature: UNDER_ATTACK | DISABLED, pos, name, flag, threat?}` —
    NAV-layer marker (never sensor fusion — the M41 rule); nature picks the
    responder's posture (intercept vs rescue); carries identity, so SOS
    counts as reporting; sendable on battery power; fake-SOS bait is
    allowed emergent play.
  - `MARK_HOSTILE report` — broadcast form of the M48 standing share.
- **Stopped-under-compulsion** (the state formerly "surrendered"): brake to
  stop, transponder forced on, COMPLY broadcast. One state whether the stop
  is customs, arrest, or robbery — hard AI honor rules both directions (no
  leaf targets a compliant stopped ship; fiction-critical, test it).
- **Witness rule keyed on the rung** (extends the M48 aggression bus):
  DEMAND(IDENTIFY) is never aggression; DEMAND(STOP) from a non-authority
  flag is a witnessed aggression event, from a trusted flag a police stop.
- Cargo AI: on DEMAND(STOP) or attributed attack → comply-or-run (speed
  ratio vs threat; baseline shuttles comply, fast hulls run; shown pirate
  colors weigh toward compliance), always broadcast SOS.
- Patrol AI: DEMAND(IDENTIFY) at UNREPORTED ships in controlled space,
  ~20s window; non-compliance raises the patrol's own suspicion assessment
  (escort/shadow, not engage) — a blackboard verdict, not a standing.
  DEMAND(STOP) only with basis; engage only on refusal/fire.
- Player comms panel: receive/send the verbs (a STOP demand arriving on
  YOUR panel from a dark contact is the fear moment the design wants).
- Tests: demand→comply→release/resume cycle; fast ship runs; patrol
  IDENTIFY flow (relight ends it, no stop); honored stop under fire (both
  directions); in_reply_to disambiguation under simultaneous demands.

## M50 — Pirate hulls + the piracy behavior tree

> **SHIPPED.** `scripts/ai/jobs/` (two-slot runner + step library),
> `build_pirate()`, pirate_ore_shuttle/armed_pinnace hulls. Tests:
> `test_job_runner`, `test_visitor_itinerary` (the generality proof),
> `test_pirate_ambush`, `test_pirate_abort`. As-built deviations recorded
> in [m50_pirate_tree_design.md](m50_pirate_tree_design.md).

> **Revised before execution** — the "long multi-phase FSM-in-a-tree" risk
> below is resolved by a new composition model: **reactions stay trees,
> missions become data.** A generic job runner executes an itinerary of
> step verbs (GO_TO / GO_DARK / RELIGHT / SELECT_VICTIM / INTERCEPT /
> DEMAND_STOP / TAKE_ALONGSIDE / AWAIT / EXIT_AT ...) with declarative
> abort edges; the pirate lifecycle below is ~10 lines of job data, and
> traders/commuters (M53+) are the same runner with different data. Model:
> [jobs_and_itineraries.md](../design_ideas/jobs_and_itineraries.md);
> pinned build plan: [m50_pirate_tree_design.md](m50_pirate_tree_design.md)
> (also resolves the launder-knowledge question honestly: the pirate can't
> KNOW the datalink forgot it, so it waits out a fallible track-quiet
> heuristic — relighting early near a patrol is gameplay, not a bug). The
> hulls ship as M24 delta variants of ore_shuttle/pinnace. M50 also ships a
> non-pirate "visitor" itinerary test as the generality proof.

The loop itself, with an **abstract take** (no physical cargo yet).

- 1–2 pirate hulls as repurposed civilian designs (mining-laser shuttle,
  armed pinnace) — catalog + validator + design tests like every hull.
  Same silhouettes as civilian variants (sensors can't out them).
- Pirate tree: INFILTRATE (fly legit under cover flag) → go dark at a
  staging point → LURK near a lane → SELECT victim (unarmed, alone, no
  witness with a live track in range) → INTERCEPT → DEMAND(STOP),
  optionally showing colors (hoisting the pirate flag at the demand for the
  compliance bonus, at the cost of unambiguous hostility to any listener;
  flying colors from the start is reserved for operating in force, a later
  arrival-mix option) →
  TAKE (alongside-hold T seconds against a compliant victim = success) →
  EXFIL dark → CASH-IN: wormhole exit, or launder — stay dark until the
  track dies on the WHOLE home datalink (not just the pursuer), relight
  under a NEW name (the wanted-names rule makes the old one a liability),
  and re-enter reporting like a citizen. Abort rules: patrol
  approach, victim armed/resisting, damage → flee.
- Tests: scripted end-to-end run in a mini cluster (pirate arrives, goes
  dark, ambushes a shuttle, takes, exfils via wormhole); ambush aborts when
  a patrol closes.
- **Risk**: this is a long multi-phase FSM-in-a-tree; keep phases as
  blackboard state with one leaf per phase, mirroring CargoRunLeaf's
  two-state pattern rather than inventing new machinery.

## M51 — Pirate guild director

> **SHIPPED.** `scripts/directors/pirate_guild.gd` (ledger + five-stage
> policy tick), `ClusterManager.directors` + the `_attach_ai` pirate
> branch + external-despawn record retirement (the cash-out resurrection
> fix), campaign-bootstrap wiring, `pirate_guild_log` debug toggle. Test:
> `test_pirate_guild` (five scenarios, real queue_free despawn path).
> As-built deviations in [m51_pirate_guild_design.md](m51_pirate_guild_design.md).

> **Revised before execution** — pinned design in
> [m51_pirate_guild_design.md](m51_pirate_guild_design.md). Key additions
> over the sketch below: the **director pattern** (ledger + policy tick as
> a ClusterManager tenant; config as data) and the **director honesty
> rule** (knowledge by member check-in — a silent member goes OVERDUE and
> resolves LOST/CASHED_OUT only after a presumed-lost delay; cash-in is
> the vanished-near-the-wormhole heuristic), both recorded in
> [jobs_and_itineraries.md](../design_ideas/jobs_and_itineraries.md) §3.
> Also surfaces and partially fixes a latent cluster bug: the cluster
> layer has no concept of death (a hulk's record would re-promote as a
> live ship); M51 removes LOST pirates' records, the general case is a
> filed follow-up.

- Guild ledger (plain serializable data): active, scheduled arrivals,
  losses, takes, streaks. Policy tick (~10s): floor of 1 pirate in the
  area — a loss schedules a wormhole arrival 2–5 min out; take-streak
  raises the concurrency cap (bounded), loss-streak backs off. Arrivals get
  cover identities (name + plausible flag).
- Operates on ClusterEntity records (arrival = record spawned at the
  wormhole, dormant until promoted); randomness only via the seeded global
  RNG.
- Tests: kill the pirate → replacement inside the window; streaks move the
  cap both ways; deterministic under the test seed.

## M52 — Patrol interdiction + SOS response

> **SPLIT (campaign playtest, July 2026): sub-milestones now precede
> this milestone's original scope.** (a/b landed; c/d added by the
> 2026-07-20 playtest — design_ideas/2026-07-20-pirate_playtest.md.)
>
> - **M52a — Pirate viability** (implementation_plans/m52a_pirate_viability.md):
>   the campaign guild ledger read takes_total=0 — pirates loop on failed
>   demands until killed. Instrument (abort causes, witness identity,
>   comply-or-run decisions, death attribution, viability sim + CSV), then
>   fix from data: comply-or-run speed comparison, beacon-witness rule,
>   failed-victim memory, withdraw-alive (RETURNED_EMPTY), guild
>   profitability backoff, calibrated presumed-lost.
> - **M52b — Warrants** (design_ideas/warrants.md, build order in
>   implementation_plans/m52b_warrants.md): rescopes the M48
>   sticky-HOSTILE standing + MARK HOSTILE into observed, typed, expiring,
>   revocable warrant records with response levels, origin flags,
>   authority-scoped enforcement, and comms propagation with dedup. This
>   SUPERSEDES the parked playtest notes below (retraction verb, visible
>   flips, escalation ladder — all three fall out of the model), and the
>   patrol behaviors in this milestone's original bullets should be built
>   ON warrants, not on raw standing. Campaign framing decision leaning:
>   player starts in a small militia with no warrant feed (see the doc).
> - **M52c — Robbery mechanics** (implementation_plans/
>   m52c_robbery_mechanics.md): the stop itself — standoff intercept with
>   relative-velocity DONE (playtest: one pirate rammed the player and
>   died, another "intercepted" without stopping), speed-match pacing
>   during the demand, tightened 10s+ alongside robbery (soft-dock
>   formation lock; hard ship-to-ship docking deferred), and player-side
>   DEAD STOP autopilot.
> - **M52d — Hail lifecycle + comms UX** (implementation_plans/
>   m52d_hail_ux.md): pending_demand expiry on issuer-gone + RELEASE on
>   job abort (playtest: a dead pirate's demand persisted forever),
>   incoming-hail alert, COMPLY affordance (one press = declare + dead
>   stop), and the hails panel restructured per-VESSEL (header = track/
>   name/flag, consistent action buttons, no [TO YOU]).
>
> Original design-pass notes (now folded into M52b): a retraction verb
> (who may un-mark, before patrols act on shared markings); player-facing
> feedback when dispositions flip on you (overheard MARK_HOSTILE reports
> about you on the comms panel) + AI behavioral coherence with its own
> standing; and the escalation ladder — marked → challenged → fire only on
> refusal — which sharpens the intercept-before-weapons bullet below.

- Patrol tree grows, and this is where the patrol's SUSPICION ASSESSMENT
  lives (the former SUSPICIOUS-standing criteria — loiter off-lane, ignored
  challenge, wanted-name — as blackboard scoring, not a contact-record tier):
  respond to SOS (comms range >> sensor range — fly to the marker), INTERCEPT
  posture on its own suspicion OR a HOSTILE standing (close and demand
  surrender BEFORE weapons; engage on refusal/return fire), honor surrender,
  resume patrol.
- Witnessed-ambush escalation end-to-end: pirate demands surrender in
  patrol sensor sight → patrol marks HOSTILE (M48 rule), intercepts,
  engages on non-compliance.
- The intercept protocol is faction-blind — it fires on ATTRIBUTED
  aggression regardless of who the aggressor is, INCLUDING the player:
  fire on a home station and the nearest patrol flips, marks you hostile
  (the station's own witness event, datalinked), and opens with
  DEMAND(STOP). Complying player is held (shadowed, weapons tight),
  not executed — same surrender guarantees as everyone else. What "held"
  ultimately means for a player (fine? confiscation? standing decay?) is
  M54+ content; M52 only guarantees the stop-shooting contract.
- Tests: patrol saves a shuttle it can see; patrol answers an SOS from
  beyond sensor range; surrendered pirate is captured (held, not shot);
  player fires on a station → patrol demands surrender immediately, holds
  fire while the player complies.

> **Confirmed by playtest (2026-07-20), post-M52b.** Spawned a pirate,
> fired on it, and the home station attacked the player directly with no
> demand and no way to surrender. Expected under the CURRENT state of the
> world: M52b built the warrant DATA layer (an ASSAULT warrant posts
> correctly, INTERCEPT-class per the taxonomy) but no station/patrol
> behavior tree exists yet to READ that response class and execute the
> challenge-before-engage sequence above — this milestone's actual scope,
> not yet started. Real evidence the surrender contract (bullet above,
> "Complying player is held, not executed") needs to land here, not be
> assumed to fall out of the warrant plumbing alone.

## M53 — Traffic guild + demand-driven cargo

> **M53a LANDED** (world + peer state + pirate circulation). **M53b/M53c are
> scoped in [m53bc_traffic_guild.md](m53bc_traffic_guild.md)** — four passes:
> (1) the docking registry in mail-network shape, (2) a CONCRETE traffic
> director + the transient freighters absorbed from M53a Slice C, (3) extract
> the shared director skeleton only once two consumers exist, (4) demand-driven
> routing. Key sequencing call recorded there: extraction is NOT first, because
> a skeleton factored from a single consumer bakes in that consumer's
> assumptions.

> **M53a — Economic expansion** (implementation_plans/
> m53a_economic_expansion.md, from the 2026-07-20 playtest: "we don't have
> enough traffic for pirates to have a good target selection") pulls the
> world-building forward ahead of the demand ledger: 2x cluster radius,
> wormhole moved near the center station, two mining colonies under a PEER
> STATE's flag with routes back to center (jurisdiction seams via M52b's
> warrant_authority for free), transient wormhole freighters running the
> beacon road, and pirate circulation across the enlarged route set
> (varied entry points; a false-flag "cruise lit as a freighter" hunting
> posture alongside the existing dark lurk).

- **Traffic is per-flag** (decided): one traffic guild owns all non-pirate
  commerce (home + peer), and the jurisdiction seam comes from the `flag`
  stamped on each spawned record, not from a director per sovereign. Same
  ledger, per-flag arrival tables — matches how the pirate guild already
  stamps a cover identity per arrival.
- Traffic ledger: per-station demand scores fed by activity (docking
  events, mining ticks — start simple: dock count decay-averaged).
  Policy tick assigns runs per-trip instead of fixed loops: hub↔hub down
  the road, periodic off-road runs to whichever outpost demand favors
  (the ambush habitat the piracy loop needs).
  - **Read demand from a per-station docking-registry SHAPE from day one**,
    even while that registry is still globally visible. The mail network
    ([../design_ideas/mail_network.md](../design_ideas/mail_network.md)) will
    later latency-gate the registry's *visibility* to retire director
    omniscience; building the demand read against the registry shape now means
    that change swaps visibility, not the director's structure — no god-object
    to rip out later. This is the one mail-network decision that affects M53
    itself; the rest is a later vertical.
- Population floor + wormhole replenishment for lost haulers **first** — this
  is what stops the world depleting once pirates work (authored static traffic
  + working robbery thins killed haulers permanently; the floor is the fix, so
  land it ahead of demand-scoring). Same arrival mechanism as M51 — extract the
  shared "guild"/director skeleton now (M53a's transient freighter is the
  second consumer that proves the shape before it's extracted).
- Story-phase hook lands here as data: the arrival table the director draws
  from is keyed by StoryState flags (peacetime mix now; militia formations
  and the weapons dealer are later *content*, not new systems).
- Tests: killed hauler replenished; demand shift redirects runs; population
  cap respected.

## M54 — Credits + escort & hunt missions

The player enters the loop.

- Credits ledger (player-side; plain data behind StoryState's save
  boundary).
- Mission generation from director state (first generated, non-authored
  missions): ESCORT (attach to a real cargo run; success = it docks alive;
  fail = it dies/loses cargo) and HUNT (patrol a lane area; success =
  pirate destroyed or forced to surrender — but the target must be marked
  HOSTILE by home-faction standing first: under the assistance exemption,
  killing a contact the patrol has NO evidence on makes YOU the aggressor
  from the patrol's angle. The mission is force-the-reveal detective work and
  the contract brief says so). Offered via the existing
  comms/contract surfaces; MissionLog gains the two objective kinds it's
  missing (ESCORT/KILL_OR_CAPTURE); ContractFeed markers already generalize.
- Payment on completion; escort pay scales with pirate pressure (the guild
  ledgers already know it).
- Tests: escort completes on safe arrival and fails on loss; hunt pays on
  forced surrender; mission targets resolve against live director spawns.

## M55 — Physical cargo + boarding/loot transfer

Upgrades the abstract take into stuff.

### Scoped 2026-08-01 -- the previous version conflated two separable things

**Where it stands today, verified.** A robbery moves nothing. `Ship.loot_takes`
counts completed 8-second alongside holds, and the pirate guild's ledger `loot`
is *that same counter* (`pirate_guild.gd:231` reads `last_loot_takes`). A robbed
hauler continues to its destination and **delivers in full** --
`serve_posting(ship, acceptance, amount)` hands `amount` straight to
`StationEconomy.fulfill()` with nothing checking that the hull possesses
anything. Piracy is invisible to the economy, and it comes down to that one
unchecked argument.

**The scoping error to fix:** the old bullet list mixed *cargo existing as an
object* with *capacity varying by hull*. Those are independent, and only the
first is needed for pirates to affect the economy. Separating them is most of
what this milestone was missing.

- **M55a -- the manifest.** A hauler holds `{commodity, lots}` from pickup dock
  to dropoff dock; `serve_posting` requires and consumes it. Flat `LOT_SIZE`
  (4.0) still applies. This alone makes cargo a real object.
- **M55b -- theft moves goods.** `TAKE_ALONGSIDE` transfers the manifest; the
  guild ledger counts units instead of holds. Fencing needs no new mechanism --
  the existing wormhole cash-out already converts a successful exit into guild
  income, so stolen goods leave the cluster permanently and the pirate is paid
  in proportion to what it actually took. *(Axis worth deciding here rather than
  drifting into: theft that DIVERTS supply via a fence is richer than theft that
  destroys it, but diverting needs a sink -- and cash-out already is one.)*
- **M55c -- capacity from parts.** `cargo_bay` -> capacity, replacing flat
  `LOT_SIZE`, per "a ship is its parts". Two blockers, both still true:
  **CargoShuttle authors no `cargo_bay` at all** (only Freighter and the
  stations do, so the primary hauler needs a design change plus
  `test_ship_designs` revalidation), and area-units need calibrating into lots.
  This is what makes *which hull you fly* an economic decision.
- **M55f -- the validator learns what a hauler is.** The CargoShuttle shipped
  with NO cargo bay and validated clean, because `if not has_cargo_bay` sits
  inside the STRUCTURE-tier branch -- the one rule that would have caught a
  cargo ship with no cargo hold applies only to stations. Fixing the shuttle
  without fixing this just waits for the next hull.

  The catch, and it is the interesting part: `validate(ship)` keys on
  `ship.ship_tier`, and **no role metadata exists** -- tier is a size/capability
  band, not a purpose. So this cannot be inferred from the parts. A validator
  can check that a hull's components are mutually CONSISTENT; it cannot check
  them against an intent nobody stated. "This ship is meant to haul" is the one
  thing "a ship is its parts" genuinely cannot express, because it is about
  purpose rather than construction.

  So the hull must declare it. Scope, deliberately narrow:
  - a declared role/capability on Ship (set before `super()`, same idiom as
    `ship_tier`), defaulting to none so every existing hull is unaffected;
  - validator rule: a hull declaring itself a hauler MUST have a `cargo_bay`,
    and its derived capacity must clear a floor -- no vestigial bays;
  - **the same rule for crew**: a hull declaring itself crewed MUST have
    `living_quarters`. Every warship in the fleet currently has NONE, by the
    identical STRUCTURE-tier oversight -- see "The human axis" below. Build the
    rule for both axes at once or it gets written twice;
  - authored on CargoShuttle, Freighter and the M55d mid-tier;
  - a `test_ship_designs` case that FAILS on a hauler with no bay, which is the
    assertion whose absence let this through.

  Keep it a declaration, not a taxonomy. A full role enum invites behaviour to
  start keying off it, and that is a much larger change than this milestone
  wants. Sequence it AFTER M55c authors the bays, or the rule fails the catalog
  on its first run.

- **M55d -- a mid-tier hull.** The roster is a cliff: a small shuttle and the
  largest hull in the fleet, nothing between. Content, fully separable.
- **M55e -- boarding/inspection.** The alongside-hold formalized: patrols and the
  player read a surrendered ship's manifest and ask "does this look like stolen
  loot?" Needs M55a; nothing else needs it.
- Mining outposts generating ore over time -> outposts fill, haulers move it,
  hubs consume, pirates leak it.
- Tests: manifest conservation across load/theft/unload; a robbed hauler cannot
  deliver what it no longer has; inspection reads.

### The volume ratios, measured 2026-08-02

**Capacity TODAY is flat.** `_score_pair` computes
`amount = min(LOT_SIZE, min(pickup_qty, dropoff_qty))`, so **every hull carries
up to 4.0 lots** and nothing reads `cargo_bay` at runtime. A CargoShuttle and
the Freighter haul identically. That is the baseline any proposal is measured
against, not the validator formula below.

**What the validator's formula WOULD give**
(`capacity = cargo_area / ComponentSpec.CARGO_AREA_PER_UNIT`, constant 10.0):

| Hull | cargo rect(s) | area | formula | today |
|---|---|---|---|---|
| **CargoShuttle** | *none authored* | 0 | **0** | 4.0 |
| Freighter | `Rect2(9,25,52,36)` x2 mirrored | 3,744 | 374 | 4.0 |
| SmallStation | `Rect2(-20,20,40,100)` | 4,000 | 400 | n/a (bins) |
| MediumStation | `Rect2(-50,20,100,160)` | 16,000 | 1,600 | n/a (bins) |
| AsteroidStation | `Rect2(-30,-15,25,30)` | 750 | 75 | n/a (bins) |
| DefencePod | `Rect2(0,-65,15,10)` | 150 | 15 | n/a (bins) |

Against Refinery Prime's entire ORE bin of **39.6 lots**, the formula would give
a Freighter 374 lots -- 9.5x a whole refinery bin. Two orders of magnitude out,
because `CARGO_AREA_PER_UNIT = 10` is a VALIDATION constant ("is capacity
non-zero?") and was never economic.

**The CargoShuttle is simply MISAUTHORED, and the validator aimed its check at
the wrong tier.** `if not has_cargo_bay` lives inside the STRUCTURE-tier branch;
CargoShuttle is `Tier.LIGHT`. So the one rule that would have caught a cargo
ship with no cargo bay applies only to stations. Fixing the hull is easy; **M55f above is
the change that stops it recurring**, and it is part of this milestone.

**Both the geometry and the constant are free parameters**, so any target ratio
is reachable -- this is a design choice, not a discovered constraint. The real
question is what stays fictionally coherent: a visibly small shuttle must not
out-carry a freighter, and the ladder wants shuttle < mid-tier < freighter with
the lower rungs small enough that several ships still work one run (the design
doc's "a lot must stay small relative to a need"). That is what makes **M55d's
mid-tier hull load-bearing rather than optional** -- with only two rungs, any
calibration that keeps a shuttle useful makes the freighter enormous.

**Stations must NOT use this rule, and the reason is cleaner than "different
units": a station bin is POLICY, not physical space.** It is how much of a
commodity that holder is willing to hold, authored from throughput
(`rate_hint * hours`, floored at `MIN_BIN_LOTS`); when it is full the station
simply stops accepting. So bins have no obligation to sum to a station's
`cargo_bay` area, and the apparent over-subscription (5+ commodities against
~128 geometric lots) is not a conflict at all -- it was a category error in an
earlier draft of this section.

That also settles what a station's `cargo_bay` component IS: structure. Mass,
hitpoints, something to shoot off. It carries no capacity meaning, and
`CARGO_AREA_PER_UNIT` should never be applied to one.

The refusal is already built and already honest: `deliver()` clamps to the bin,
and `fulfill()` returns the ACTUAL delta with payout computed on what landed,
never on what was asked. Keep cargo-bay-derived capacity for SHIPS only.

**Consequence for M55a, worth deciding now rather than discovering.** Today a
partial delivery just means a smaller payout -- the ship holds nothing, so there
is no remainder to strand. Once cargo is a physical manifest, **a clamped
delivery leaves the hauler holding the difference**, which is a state that does
not exist anywhere in the game today. A hauler can arrive at a bin that filled
while it was in transit and be left with lots it cannot sell here.

Preferred answer: hold the remainder and re-plan (the planner already searches
for an open IMPORT posting; a laden hull just constrains its next search to its
own manifest). It is nearly free, and it makes the risk term more interesting
rather than less -- a laden hauler avoiding a lane has more to lose. It needs
ONE escape hatch, though, or a hull can hold an unwanted commodity forever:
dump after N failed re-plans, or a forced sale at a discount. Pick one in M55a;
do not leave it undefined, because "hauler idles laden, permanently" reads
exactly like the job-runner bug class that has already cost this project a
faction.

### Precisely what does and does not read `cargo_bay`

Stated exactly, because an earlier draft of this section said "nothing reads
cargo_bay" and that is wrong in both directions.

**The COMPONENT is fully live.** `ship.gd`'s mass loop is
`total += area * c["density"] * MASS_SCALE` over every component, so a cargo bay
contributes **mass**. It also carries health (damage model), a rect (collision,
silhouette, overlap and connectivity validation) and its own `COMPONENT_BANDS`
entry. It behaves like any other part.

**The CAPACITY is dead code.** `ship_design_validator.gd:162` assigns
`var cargo_capacity = total_cargo_area / CARGO_AREA_PER_UNIT` and **nothing
reads it** -- not the economy, and not even the validator that computes it (the
line below tests `human_capacity`). The comment above it, "log a warning if
capacity is unusually small (e.g. 0)", describes a check that exists for people
and was never written for cargo. That is the actual state: not "validation
only", but computed and discarded.

**Consequence, and it widens the sim requirement.** Because mass derives from
component area, **authoring a cargo bay onto the CargoShuttle makes it heavier
and therefore slower.** The shuttle's entire hull is ~1,100 area units; a bay
big enough to matter is a large fraction of that, so this is a double-digit
percentage mass change, not a rounding error.

That lands directly on a measured relationship: `pirate_scenarios` rates takes
against victim speed, and the designed curve is "slow prey always caught, prey
faster than the pirate always escapes". Making the primary hauler heavier moves
it along that curve. So M55c needs **fresh piracy runs as well as fresh economic
ones** -- and the two interact, because slower haulers also mean longer transit
and therefore different throughput on every lane.

### Cargo volume is PHYSICAL; person-area is a STANDARD OF LIVING

The two constants look like the same mechanism and must not be treated the same
way:

- **`CARGO_AREA_PER_UNIT` stays ONE global constant.** A lot of ore occupies the
  same space in a shuttle's hold as in a freighter's. Capacity must relate to
  the authored bay volume consistently across every hull -- no per-class fudge
  factor, because there is no fiction that justifies one. Recalibrate the single
  number; do not band it.
- **`AREA_PER_PERSON` SHOULD band by class.** Space per person is comfort, not
  volume: a marine hot-bunking, a merchant officer and a station resident
  legitimately differ several-fold. `COMPONENT_BANDS` is already tier-keyed, so
  this is an existing idiom rather than a new mechanism.

Getting this backwards in either direction is the trap. Banding cargo would let
a hull cheat physics; refusing to band people forces a warship berth and a
civilian apartment to be the same room.

### The warship catalog predates cargo AND crew -- revisit, do not patch

Frigate, LightAttackCraft, ArmedPinnace and CargoShuttle were all authored
before either system existed, which is why they have neither quarters nor bays.
So the right move is a deliberate catalog design pass (M9c-shaped work), not a
minimal component bolted on to satisfy a new validator rule.

**This widens the re-baseline requirement again, and this time onto combat.**
Mass derives from component area, so adding quarters to a Frigate or an
ArmedPinnace makes it heavier and slower -- and pirate-vs-prey outcomes are
explicitly a speed relationship (`pirate_scenarios` asserts "slow prey caught,
fast prey escapes"). A catalog pass therefore moves:

- every economy number (haul capacity, transit time) -> re-run `economy_traffic`
- every piracy number (chase outcomes) -> re-run `pirate_scenarios`
- combat-outcome tests that assert margins (`test_ai_duel` and friends), which
  CLAUDE.md already warns are jitter-sensitive -- expect to re-check those
  specifically, and re-run a failure SOLO to compare the NUMBER before assuming
  contention.

Sequence the catalog pass as its own step with its own gate, rather than folding
it into a milestone that also changes economic semantics. Two variables at once
is how the LOT_SIZE regression became hard to read.

### The human axis -- same machinery, same gap, deliberately its own milestone

`AREA_PER_PERSON := 40.0` is the exact parallel of `CARGO_AREA_PER_UNIT`, and
`living_quarters` is already authored across the fleet. Implied crew today:

| Hull | living area | crew @ 40 |
|---|---|---|
| MediumStation | 4,000 + 16,000 = **20,000** | **500** |
| SmallStation | 4,000 | 100 |
| Pinnace | 3 x 400 = 1,200 | 30 |
| AsteroidStation | 540 | 13.5 |
| Freighter | 460 | 11.5 |
| DefencePod | 120 | 3 |
| MobileHome | 50 | 1.3 |
| **Frigate / CargoShuttle / LAC / ArmedPinnace** | **none** | **0** |

Two findings:

**Every warship has zero crew space**, for the identical reason the CargoShuttle
has no cargo bay -- the `living_quarters` requirement lives in the same
STRUCTURE-tier branch, so it only ever applied to stations. **M55f therefore
generalizes**: a hull declares its role, and the validator checks
role-appropriate components. A hauler needs a bay; a crewed ship needs quarters.
One rule, both axes -- do not build it cargo-only.

**A MediumStation's habitat (20,000) EXCEEDS its cargo bay (16,000).** It is
already authored as a town of ~500 people, not a warehouse. That is a large
existing asset nothing currently reads.

**Why 40 is wrong as a universal**, which is the actual design question: one
number is currently serving a marine's bunk, a merchant's cabin and a civilian
apartment. Those plausibly differ by 5-10x. The fix uses machinery that already
exists -- `COMPONENT_BANDS` in `component_spec.gd` is already tier-keyed, so
per-class person-area is the same idiom, not a new mechanism. Rough shape:
warship berthing (cramped, hot-bunking) well under 40, merchant crew at ~40 as
the anchor, passenger accommodation above it, station habitation highest.

Two payoffs worth naming, because they connect to work already scoped:

- **Marines gate boarding (M55e).** A warship's quarters bound how many boarders
  it can put across. That turns the human axis from flavour into the input of a
  mechanic this milestone already contains.
- **Station population could drive CIVILIAN demand** -- but keep the split clean,
  and it follows directly from "bins are policy": industrial converter
  consumption stays authored (it is about machines), while civilian consumption
  (food, GOODS) could derive from population. That gives those commodities a
  demand driver tied to something physical, destroyable and defensible, without
  overriding the industrial rates that have been measured.

**Scope note: this is a SIBLING milestone, not part of M55.** It shares the
machinery (area -> capacity via a per-class constant) and the validator fix, so
M55f should be built to cover both. Everything else here -- per-class banding,
marines, population-driven demand -- is its own vertical and would balloon a
milestone that is already a hull-authoring task plus two sim re-baselines.

### Any capacity change REQUIRES fresh economic sim runs

Non-negotiable, and it is the main cost of this milestone rather than the code.
`LOT_SIZE` is the binding constraint on the whole cluster economy -- at 1.0 it
starved Refinery Prime while ore piled up unsold at every mine, and the 4.0
value was arrived at by measuring 180 sim-minutes, not by taste. Replacing one
flat number with per-hull capacity moves that constraint for every lane at once.

So M55c is not done when the code compiles. It is done when `economy_traffic`
AND `pirate_scenarios` have been re-run and the producer side checked (authored rates, never measured
ones -- backpressure makes a healthy source read as a weak one, which is how
the original diagnosis went wrong). Expect to re-baseline; treat a moved number
as a new measurement, not a regression.

### M55 and M59 are two halves of one loop

| Cause | Consequence |
|---|---|
| **M59** -- cargo *avoids* the lane out of fear | nothing delivered -> urgency rises -> price rises |
| **M55** -- cargo *flies* the lane and is robbed | nothing delivered -> urgency rises -> price rises |

Identical economic signature, opposite causes -- which hands the information
economy a genuinely good hook: **the price tells a player something is wrong on
that lane; only the mail tells them whether it is fear or theft.** A lane
everyone is avoiding and a lane being harvested look the same on the board.

Not a hard dependency either way: M59 is self-consistent without M55, because
avoidance alone stops deliveries. What M55 adds is that piracy becomes
**materially** rather than merely **psychologically** costly. M55a+M55b are
cheap, blocked by nothing, and are the largest fidelity gain per unit of work
in this roadmap.

## The Mail Network (named vertical — its own design doc)

[design_ideas/mail_network.md](../design_ideas/mail_network.md). The model that
retires director omniscience for good: a director knows only what has physically
reached its location, because information rides couriers (docking-registry news
merged station-to-station on dock, newest-wins for current state + append-only
union for history). Blast radius on the director model is M48-sized, so it's
built deliberately and phased (registry → transport → relocate the director →
contracts). It's the systemic home of the contract taxonomy — courier / locate /
contract-haul / salvage / bounty — that turns missions from authored into
emitted-by-blind-spots. Two hooks reach back into the milestones above:
**M53c reads demand from the registry shape now** (so phase 3 latency-gates
visibility, not structure). (M56 is NOT a merge dependency — the monotonic
source-log design merges on a per-source sequence number, not an observation
stamp; M56 stays a contact cleanup whose frame-stamp idiom the mail age-display
borrows.) Full ambition sits after M55; phase 1 (the registry) is cheap and
seeded during M53.

**Phased execution now lives in
[m57_m61_information_economy_roadmap.md](m57_m61_information_economy_roadmap.md)**
(M57 incidents → M58 transport → M59 risk-aware routing + patrol director →
M60 pirate information economy → M61 competing bands). Two facts verified
2026-08-01 vindicate the registry-first instinct and cut M57's risk sharply:
`docking_registry` **already lives on the `ClusterEntity` record** (not on a
director) and already survives promote/demote — so "the map belongs on the
station" needs no new architecture — and it currently has **no consumer at all**
outside its own tests. The signal is already being written in the right place,
at the right lifetime, and nothing reads it.

## Later (designed for, not scoped)

- Story-phase arrival content: armed militia formations (needs formation
  flying), weapons dealer + station shops (needs credits sink UI).
- Off-bubble abstract encounter resolution via the ROUTE_TICK liveness tier
  (also the natural carrier for off-bubble mail-payload merges — see the mail
  network's open questions).
- Pirate SOS/reinforcements, ransom demands, player piracy.
- Boarding depth (crew, capture-the-hull — ties into hulk revival contract,
  see design_ideas/hulk_revival_contract.md).

## Order and risk

M48 is the widest blast radius (every combat test's premise) and the least
glamorous — do it first and alone, with the test audit as an explicit
deliverable. M49–M50 are the payoff and can demo the fantasy end-to-end
with two ships and a stopwatch. M51–M53 make it self-sustaining. M54 makes
it the player's game. M55 makes it an economy. Each milestone leaves the
build green and the world no less alive than before it.
