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

## M53 — Traffic guild + demand-driven cargo

- Traffic ledger: per-station demand scores fed by activity (docking
  events, mining ticks — start simple: dock count decay-averaged).
  Policy tick assigns runs per-trip instead of fixed loops: hub↔hub down
  the road, periodic off-road runs to whichever outpost demand favors
  (the ambush habitat the piracy loop needs).
- Population floor + wormhole replenishment for lost haulers (same arrival
  mechanism as M51 — extract the shared "guild" skeleton now, second
  consumer proves the shape).
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

- `cargo_bay` manifests (units of ore/goods); stations load/unload on dock
  (CargoRunLeaf's existing dock cycle gets content); pirate TAKE transfers
  manifest instead of scoring abstractly; guild ledgers count real units.
- Boarding = the alongside-hold formalized as a reusable mechanic
  (inspection: "does this hold look like stolen loot?" — patrols and the
  player can check a surrendered ship's manifest).
- Mining outposts generate ore over time → the economy becomes a real flow:
  outposts fill, haulers move it, hubs consume, pirates leak it.
- Tests: manifest conservation across load/theft/unload; inspection reads.

## Later (designed for, not scoped)

- Story-phase arrival content: armed militia formations (needs formation
  flying), weapons dealer + station shops (needs credits sink UI).
- Off-bubble abstract encounter resolution via the ROUTE_TICK liveness tier.
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
