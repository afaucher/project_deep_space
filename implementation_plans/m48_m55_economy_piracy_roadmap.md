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
- Per-observer **standing** on contact tracks: FRIENDLY / NEUTRAL /
  UNREPORTED / SUSPICIOUS / HOSTILE + a reason string. Rules: crypto match →
  FRIENDLY; name+flag reported and flag not known-bad → NEUTRAL; in
  controlled space (port zones + beacon corridor) without reporting →
  UNREPORTED; known-enemy flag or witnessed aggression or manual flag →
  HOSTILE. Standing dies with the track.
- **Damage attribution**: `attacker_id` plumbed through take_damage and all
  weapon paths (lasers, missile warheads — missiles already know owner_id).
  Aggression event = attributed damage or a witnessed DEMAND_SURRENDER (M49).
- Witness rule: an observer that (a) has a live track on the aggressor and
  (b) saw the aggression event marks HOSTILE and shares it on datalink with
  attribution.
- **The pirate flag ships in M48** as the first known-enemy flag: flying it
  → automatic HOSTILE to every non-pirate observer, no witnessing needed.
  This is deliberately double-duty: fiction-side it's "showing colors" (see
  M49/M50 — pirates normally run quiet), and test-side it's the migration
  lever for `acquire_target_leaf` targeting HOSTILE only. Every combat test
  that spawns opposing iff_tags and expects a fight migrates by hoisting
  the pirate flag on one side — no test-only standing backdoor. Audit
  test-by-test, but the fix per test is one line.
- Player UI: contacts panel shows standing + reason; "MARK HOSTILE" button.
- Tests: dark stranger is NOT auto-engaged; witnessed attack flips standing
  and propagates on datalink; manual flag works; track loss forgets.
- **Risk**: the combat-test audit is the real cost of this milestone.
  Budget for it; it is the price of unwinding shoot-on-sight.

## M49 — Hail protocol, surrender, challenge

- Structured comms verbs (machine-to-machine, comms-range-gated, NOT
  dialogue): CHALLENGE, DEMAND_SURRENDER, COMPLY, SOS, MARK_HOSTILE-report.
  Ride the existing transient_events/comms plumbing.
- `surrendered` ship state: cut thrust (or brake to stop), transponder
  forced on, broadcast COMPLY. Hard AI honor rules: no leaf targets a
  surrendered ship (both directions — this is fiction-critical, test it).
- Cargo AI: on DEMAND_SURRENDER or attributed attack → surrender-or-run
  decision (speed ratio vs threat; baseline shuttles comply, fast hulls
  run; a demand under shown pirate colors weighs toward compliance),
  always broadcast SOS.
- Patrol AI: CHALLENGE UNREPORTED ships in controlled space; give a comply
  window; non-compliance → SUSPICIOUS (escort/shadow, not engage).
- SOS surfaces as NAV-layer data (ContractFeed-style marker; never injected
  into sensor fusion — the M41 rule).
- Player comms panel: receive/send the verbs (a surrender demand arriving on
  YOUR panel from a dark contact is the fear moment the design wants).
- Tests: demand→comply→resume cycle; fast ship runs; patrol challenge flow;
  surrender honored under fire.

## M50 — Pirate hulls + the piracy behavior tree

The loop itself, with an **abstract take** (no physical cargo yet).

- 1–2 pirate hulls as repurposed civilian designs (mining-laser shuttle,
  armed pinnace) — catalog + validator + design tests like every hull.
  Same silhouettes as civilian variants (sensors can't out them).
- Pirate tree: INFILTRATE (fly legit under cover flag) → go dark at a
  staging point → LURK near a lane → SELECT victim (unarmed, alone, no
  witness with a live track in range) → INTERCEPT → DEMAND_SURRENDER,
  optionally showing colors (hoisting the pirate flag at the demand for the
  compliance bonus, at the cost of unambiguous hostility to any listener;
  flying colors from the start is reserved for operating in force, a later
  arrival-mix option) →
  TAKE (alongside-hold T seconds against a compliant victim = success) →
  EXFIL dark → CASH-IN: wormhole exit, or relight far from the scene under
  a fresh name (track loss does the laundering). Abort rules: patrol
  approach, victim armed/resisting, damage → flee.
- Tests: scripted end-to-end run in a mini cluster (pirate arrives, goes
  dark, ambushes a shuttle, takes, exfils via wormhole); ambush aborts when
  a patrol closes.
- **Risk**: this is a long multi-phase FSM-in-a-tree; keep phases as
  blackboard state with one leaf per phase, mirroring CargoRunLeaf's
  two-state pattern rather than inventing new machinery.

## M51 — Pirate guild director

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

- Patrol tree grows: respond to SOS (comms range >> sensor range — fly to
  the marker), INTERCEPT posture on SUSPICIOUS/HOSTILE (close and demand
  surrender BEFORE weapons; engage on refusal/return fire), honor
  surrender, resume patrol.
- Witnessed-ambush escalation end-to-end: pirate demands surrender in
  patrol sensor sight → patrol marks HOSTILE (M48 rule), intercepts,
  engages on non-compliance.
- Tests: patrol saves a shuttle it can see; patrol answers an SOS from
  beyond sensor range; surrendered pirate is captured (held, not shot).

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
  pirate destroyed or forced to surrender). Offered via the existing
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
