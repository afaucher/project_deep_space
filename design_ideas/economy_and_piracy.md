# The Living Drift: local economy + pirate activity

The next gameplay vertical: the Sovereign Drift gets a working local economy
(mining outposts feeding hubs feeding the wormhole) and a piracy problem that
preys on it. Traffic volume and composition become a barometer of the story
arc and local conditions; the player enters the loop through escort and hunt
missions. Companion roadmap:
`implementation_plans/m48_m55_economy_piracy_roadmap.md`.

## The fantasy (short-term target: the basic piracy loop)

A pirate enters through the Nexus wormhole flying an ordinary trader flag and
transponder. It cruises somewhere plausible, slips off into dark space, kills
its transponder, and drifts in cold across an off-road shipping lane. When a
lone cargo shuttle passes, the pirate closes and demands surrender over comms.
The shuttle — unarmed, slow — cuts thrust and complies; the pirate holds
alongside, takes the cargo, and runs dark. It cashes in one of two ways:
exiting via the wormhole, or relighting its transponder far from the scene
under a fresh name and strolling back into common space. If a patrol saw any
of it happen, the pirate is marked hostile and the patrol closes to intercept.
If the player took the escort contract, they were flying next to that shuttle
when the dark contact appeared on sensors — and a dark contact should *feel*
threatening.

## Why the current IFF model blocks all of this

`classify_contact` is binary: IFF-tag overlap → FRIENDLY VESSEL, otherwise →
UNIDENTIFIED VESSEL, and `acquire_target_leaf` shoots exactly that bucket.
Consequences: every stranger is auto-hostile, a pirate can't hide among
civilians, a patrol can't "get suspicious", and the player never gets the
judgment call. The fix is a **two-layer split**:

- **Classification stays sensor truth** (what the physics says: vessel /
  ordnance / wreckage / asteroid, friendly-by-crypto or not). No change.
- **Standing is judgment** — a per-observer ledger about a *tracked contact*.
  Every entry criterion is an observable event with a threshold (each row is
  a headless test), every entry carries a reason string, and UNREPORTED is a
  location-independent FACT ("this track is not identifying itself" — which
  is why a dark contact in deep space feels threatening) while the
  *enforcement response* is location-dependent (only controlled space makes
  it a patrol matter):

  | Standing | Meaning | Entry criteria (any one; each carries a reason) | Exit / decay |
  |---|---|---|---|
  | FRIENDLY | crypto-verified own side | IFF tag overlap (unforgeable handshake) | track loss (traitor/friendly-fire demotion: deferred edge case) |
  | NEUTRAL | identified, clean | broadcasting name + flag; flag not known-enemy; no live evidence on the track | resting state — no decay needed |
  | UNREPORTED | not identifying itself | no name + flag broadcast received for this track (anywhere) | instantly → NEUTRAL on reporting with a clean flag |
  | SUSPICIOUS | judged worth watching | 1. challenge comply-window expired (controlled space) 2. dark/unreported contact loitering near a lane (~15k of a lane, <~20% max speed, >30s) 3. sustained intercept geometry toward a third ship (~20s closing lead-pursuit) 4. datalink report from ally (relays reason + attribution) 5. *(later)* transponder claim vs tracked position mismatch | decays → NEUTRAL after a clean interval (~3 min reporting, no new events); challenge compliance clears reason 1 immediately; track loss forgets |
  | HOSTILE | **earned** enemy | 1. attributed aggression (`attacker_id` == this track, vs me / my faction / anything I hold a live track on — stations witness attacks on themselves) 2. DEMAND_SURRENDER heard from it (aggression by speech-act) 3. flying a known-enemy flag (pirate flag, day one) 4. player MARK HOSTILE 5. faction datalink share (with attribution) | **sticky for the life of the track — never decays**; the only way out is breaking the track (that is what laundering IS) |

  What each tier authorizes:

  | Actor | FRIENDLY / NEUTRAL | UNREPORTED | SUSPICIOUS | HOSTILE |
  |---|---|---|---|---|
  | Weapons AI (`acquire_target`) | never | never | never | engage — *unless surrendered* |
  | Patrols | ignore | controlled space: CHALLENGE (close, hail, ~20s window); outside: observe only | intercept posture: divert, shadow, demand ID; stop-and-inspect once M55 lands; weapons tight | interdict: close, DEMAND_SURRENDER, engage on non-compliance |
  | Cargo / civilians | ignore | wide berth (steer around) | evade: reroute, hold at station, pre-emptive SOS ("possible pirate near lane") | flee + SOS |
  | Port authority | grants issued | no dock grants until reported | grants denied; sighting reported to faction | grants denied; alarm |
  | Player UI | green / white | dim yellow, "NOT REPORTING" | orange + reason ("ignored challenge", "dark, loitering near lane") | red + reason; MARK HOSTILE is how the player writes this tier |

  Notes: **surrendered is orthogonal to standing** (a surrendered pirate is
  still HOSTILE — standing records judgment, surrender gates weapons; that
  separation is what makes "held, not shot" enforceable in one place). Only
  HOSTILE requires an act and only HOSTILE is permanent — the middle tiers
  are deliberately forgiving, which stops the ladder from ratcheting the
  cluster into war, and the pirate's laundering trick is that same
  forgiveness working as intended. The thresholds (15k, 30s, 20s window,
  3 min decay) are starting values to tune, not commitments. The player gets
  a "mark hostile" button on the contacts panel (you saw the surrender
  demand on comms — that's your evidence), plus visibility into *why* an AI
  marked something.

- **Flags are cheap talk.** The transponder gains a `flag` field — a public
  declaration of allegiance (trader guild, home militia, no flag). It is
  spoofable by design; crypto IFF tags remain unforgeable and are only for
  actual friendlies. A pirate flying a trader flag is the whole game.
- **The pirate flag is a real flag anyone *could* fly** — and flying it makes
  you automatically HOSTILE to every non-pirate (it is a standing declaration
  of war; the one flag whose meaning is never ambiguous). Pirates therefore
  normally run quiet: false colors in transit, dark on the hunt. **Showing
  colors** is a deliberate act with mechanical weight: a pirate may hoist the
  flag at the moment of DEMAND_SURRENDER (the historical Jolly Roger beat —
  intimidation that makes the demand credible and tips the victim's
  surrender-vs-run decision toward compliance), fly it openly when operating
  in force (escorted, outgunning the local response), or never show it at
  all and rely on force alone. This also keeps hostility legible: a flagged
  demand needs no witness inference — everyone who hears it knows.
- **Standing sticks to the track, not the hull.** It lives on the observer's
  contact record. If the track is lost (dark, out of range, CONTACT_TIMEOUT)
  the judgment dies with it. This is deliberate and free: it's what makes
  "run dark, relight under a fresh name two hundred klicks away" actually
  launder identity, with zero extra code.
- **Standing is shareable.** Datalink already merges tracks; hostile/suspect
  markings ride along with attribution ("Patrol Alpha flagged: fired on
  Mule"). A patrol that saw the ambush makes the whole home faction react.
- **The flag does not replace attribution — both rules ship together.**
  Witnessed aggression stays the primary hostility trigger; the flag is the
  shortcut for the unambiguous case. The canonical attribution case: firing
  on a space station is a hostile act, full stop. The station is its own
  witness and it's on the faction datalink, so the marking is instant and
  shared — patrols flip immediately and open with DEMAND_SURRENDER (the
  interdiction protocol, not a silent weapons-free). **This applies to the
  player**: shoot a home station and Patrol Alpha turns, marks you, and
  demands your surrender like anyone else. Comply and you're held, not shot.

**Controlled space** = port zones + the beacon road corridor (within beacon
comms range of the road). Inside it, ships are *required* to report name +
flag. Failing to do so draws patrol challenges; civilian traffic just steers
clear of you. Outside controlled space, dark is legal — merely ominous.

## Key behaviors to enable

1. **Pirate lifecycle** (one behavior tree + a little state):
   arrive-legit (cover flag) → transit to a staging point in dark space →
   go dark → lurk near an off-road lane → pick a victim (scoring: unarmed,
   alone, no patrol/witness in range, cargo worth taking) → intercept →
   DEMAND_SURRENDER via comms → loot the compliant victim (hold alongside) or
   disengage if it runs and outpaces → exfil dark → cash in (wormhole exit,
   or relight + re-enter as "someone else"). Abort rules throughout: patrol
   inbound, victim armed, damage taken → flee, possibly SOS (pirates have
   friends too — later).
2. **Cargo ships under threat**: on DEMAND_SURRENDER (or being fired on),
   decide surrender-vs-run: baseline shuttles comply — cut thrust or stop,
   force transponder on, broadcast COMPLY; fast hulls (speed advantage over
   the threat) run instead; a demand under shown pirate colors weighs the
   decision toward compliance; everyone broadcasts SOS. Resume route when the
   threat leaves. Surrendered is a hard ship state honored by ALL AI: pirates
   stop shooting compliant victims, patrols hold fire on surrendered pirates.
3. **Patrols policing**: challenge UNREPORTED ships in controlled space
   (close to comms range, CHALLENGE, give seconds to comply); witness
   aggression → mark HOSTILE + broadcast the marking; respond to SOS beyond
   sensor range (comms is longer-ranged than sensors — by design); intercept
   before weapons: close, demand surrender, engage only on refusal/fire.
4. **Player missions**: escort (fly with a cargo run end-to-end; it arriving
   alive is the win) and hunt (patrol the lanes yourself, spot the dark
   contact, intercept — force surrender or destroy). Both paid in credits.
5. **Guild directors** shaping traffic to conditions and story phase: more
   activity at a mining outpost → more runs there; combat losses → wormhole
   replenishment; pirate success → more pirates; story phases changing the
   *arrival mix* (armed patrol formations, a weapons dealer who sets up shop).

## Systems that need to exist

- **Standings & flags (IFF v2)** — the ladder above. The foundation.
- **Hail protocol** — structured machine-to-machine comms verbs (not
  dialogue trees): CHALLENGE, DEMAND_SURRENDER, COMPLY, SOS, and a standing
  broadcast (MARK_HOSTILE with reason). Rides the existing comms-range and
  transient-event plumbing; the comms panel grows the player-facing verbs.
- **Surrender state** — `surrendered` on Ship with hard guarantees (no
  thrust or full stop, transponder forced on) and AI honor rules.
- **Damage attribution** — `take_damage` currently doesn't know the shooter.
  Witnessing and "aggression" need attacker identity plumbed through lasers
  and missiles (missiles already carry `owner_id`).
- **Cargo as stuff** — `cargo_bay` components exist but hold nothing. A
  manifest (units of ore/goods), station load/unload on dock, and transfer.
  Piracy v1 can run on an *abstract* take (alongside-hold = success) so this
  can land after the loop is proven.
- **Boarding (abstraction)** — v1 is "hold alongside": within range, low
  relative velocity, T seconds → transfer/inspect. No interior gameplay.
  Same mechanic later serves inspection ("does this hold look like stolen
  loot?") and rescue.
- **Currency** — a credits ledger (player first; guild ledgers are separate
  and abstract). Pays escort/hunt missions; later buys weapons from dealers.
- **SOS** — distress broadcast at comms range, surfaced as NAV-layer data
  (a marker/arrow like contracts — never injected into sensor fusion, per
  the M41 rule).
- **Pirate hulls** — repurposed civilian designs (mining laser strapped to a
  shuttle; armed pinnace). Crucially they share civilian silhouettes, so
  sensors alone can't out them — which the cross-section system gives us
  for free.
- **Guild directors** — see below.

## Do we need a pirates' guild orchestrator? Yes — as a ledger + policy tick

Exactly the question "last ship destroyed — send another? last 5 runs paid —
send more?" is director logic, and the codebase already has the pattern
(spawn director M10, liveness policy M14): **plain data + a dumb periodic
policy, no omniscient AI**.

- **Guild ledger** (plain dict, serializable like StoryState): ships active,
  arrivals scheduled, losses, successful takes, streaks.
- **Policy tick** (~every 10s of game time):
  - `active < floor (1)` → schedule an arrival at the wormhole with a random
    2–5 min delay ("word gets back through the Nexus").
  - take streak ≥ N → raise the concurrency cap (bounded); loss streak ≥ N →
    back off (longer delays — or, later, send a better-armed pair instead).
  - Every arrival gets a cover identity: fresh name, plausible flag.
- The **traffic guild** is the same skeleton pointed at commerce: per-station
  demand scores (docking/mining activity) weight where cargo runs go —
  including periodic off-road runs to the mining outposts (the ambush
  habitat); a population floor replenishes lost haulers via wormhole
  arrivals, same mechanism.
- **Story phases modulate the arrival tables, not the directors.** Directors
  read StoryState flags to pick which arrival mix is in force (peacetime
  traders / pirate surge / militia formations / weapons dealer moves in).
  Content lands as data.

Directors operate on **ClusterEntity records** (dormant-friendly, spawn as
records at the wormhole and dead-reckon until promoted), never on live nodes,
and draw randomness only from the seeded global RNG (the test-determinism
rule in CLAUDE.md).

## Design decisions locked by this doc

1. Classification (sensor truth) and standing (judgment) are separate
   layers; `classify_contact` is not overloaded.
2. Hostility is earned per observer with an audit reason — never automatic
   from "not one of us".
3. Flags are spoofable declarations; IFF tags stay crypto-truth.
3a. The pirate flag exists as a flyable flag and is auto-HOSTILE to
   non-pirates. Showing colors is an AI decision (at the demand, in force,
   or never), and it is the clean test lever: a spawned ship flying the
   pirate flag is hostile with zero setup — existing combat tests migrate
   by hoisting it rather than through any test-only standing backdoor.
4. Standing lives on the contact track → identity laundering falls out of
   existing sensor mechanics.
5. Surrender is a hard state with behavioral guarantees on both sides.
6. Boarding is an alongside-hold abstraction, no interiors.
7. Directors are ledgers + policy ticks over cluster records; story phases
   swap their data tables.
8. Encounters resolve live-only in v1 (a dormant pirate just moves). If the
   world needs off-bubble ambushes later, the liveness ROUTE_TICK tier is
   the designed hook for abstract resolution.

## Known hazards

- **Damage attribution plumbing** touches every weapon path — do it early
  (it's in the foundation milestone) and keep it a single `attacker_id`
  field on the damage call.
- **AI honor of surrender** must be bulletproof or the fiction collapses
  (patrol executes a surrendered pirate = the player learns surrender is
  fake). Belongs in tests from day one.
- **Traffic population = live-ship count in the bubble.** The perf work
  (M45 + hulk/missile fixes) bought real headroom (5.6ms avg vs 16.7ms
  budget at missile saturation), but directors own hard population caps and
  `perf_combat`'s census is the watchdog.
- **Godot physics nondeterminism**: encounter tests assert robustly
  (margins/majorities), per CLAUDE.md.
- **Comms range vs sensor range asymmetry is the tension the design leans
  on** (SOS travels farther than sight; dark ships are close before seen).
  Any future comms/sensor rebalance must re-run the piracy scenario tests.
