# Jobs & itineraries: reactions are trees, missions are data

How NPC behavior composes from M50 onward. Companion to
[economy_and_piracy.md](economy_and_piracy.md) (the vision) and
[comms_verbs.md](comms_verbs.md) (the wire protocol); the pinned build plan
is [m50_pirate_tree_design.md](../implementation_plans/m50_pirate_tree_design.md).

## The problem

Every AI tree today is a priority Selector:

```
Selector: [ Disengage ] > [ reactive layers ] > [ role work ] > [ Idle ]
```

The reactive layers compose well — M49 slotted ThreatResponse into cargo and
Challenge into patrol without touching anything else. The failure mode is the
bottom: "role work" has always been a single looping leaf (FollowRoute,
CargoRun), and the NPCs we're building next don't loop — they run **missions**:

- **Pirate**: infiltrate → stage → go dark → lurk → select → intercept →
  demand → take → exfil → launder.
- **Trader**: arrive → dock → trade → depart.
- **Commuter/worker**: fly to work → shift → fly home.

Written as per-role leaf-FSMs (CargoRunLeaf's pattern scaled up), each new
class re-implements "fly to X", "dock", "wait", "leave", and abort handling.
Three classes in, we'd have three divergent copies of the same plumbing.

## The model: three layers

### 1. Reactive — trees (unchanged)

Priority selectors of shared leaves: Disengage/Flee, ThreatResponse
(comply-or-run), Engage, Challenge. Role differences up here are **policy
parameters** (authority_flags, comply thresholds, whether an Engage branch
exists at all), not new leaf code. The reactive layer ALWAYS outranks the
job — a crippled pirate flees mid-heist because Disengage sits above the
runner, not because the heist knows about damage.

Ship-level hard states stay below even that: compelled_stop (M49) overrides
motion and weapons in `ship.gd` no matter what any tree wants.

### 2. Jobs — data (new in M50)

One generic `JobRunnerLeaf` executes the ship's current **job**, a plain
data structure:

```
job = {
  "steps": [ {"verb": ..., <params>, "on_abort": <label>, "label": <opt>} ],
  "current": 0,
}
```

Each **step verb** has a small executor in a step library, reusing the same
Steering/docking calls today's leaves make. Executors are stateless — any
per-step scratch lives in the step dict itself — and return one of:

- **CONTINUE** — still working; runner returns SUCCESS this tick (it owns
  the tick).
- **DONE** — advance to the next step. Job past the last step = complete
  (runner returns FAILURE thereafter; the tree falls through to Idle or a
  director assigns a new job).
- **ABORT** — jump to the step whose `label` matches this step's
  `on_abort` (no label → job over). Abort edges make "patrol closes during
  the take → exfil" a data edge, not nested ifs.

The runner is small and never grows. New NPC classes add **data** (their
itinerary) and occasionally a **verb** (a genuinely new capability), never
new machinery.

### 3. Direction — who hands out jobs (M51+)

Directors assemble jobs from templates + world state: the pirate guild picks
the lane, the staging point, the cover name; a trade director will pick
routes and dwell times the same way. The job dict is the interface between
directors and ships — a director never reaches into a tree.

## The verb vocabulary

| Verb | Semantics | Who reuses it |
|---|---|---|
| `GO_TO {pos}` | cruise to a point, DONE within arrive radius | every route leg of every class |
| `GO_DARK` | transponder off, DONE | pirates; smugglers later |
| `RELIGHT {name, flag}` | transponder on under a (new) identity, DONE | pirates; anyone changing papers |
| `LOITER_NEAR {pos, radius, duration}` | station-keep loosely, DONE after duration | holding short of a busy port |
| `AWAIT {condition, timeout}` | wait for a named condition (small fixed set) | work shifts, trade dwell, the launder |
| `DOCK_AT {station}` | grant → capture → docked, DONE when berthed | trader/commuter core |
| `EXIT_AT {pos}` | fly to the exit and despawn | all departing traffic |
| `SELECT_VICTIM {...}` | lurk + score prey, DONE with a victim chosen | pirate-only |
| `INTERCEPT {target}` | close to demand range on a moving target | pirates; tugs/rescue later |
| `DEMAND_STOP {show_colors}` | the M49 verb + comply-or-flee outcome | pirate-only |
| `TAKE_ALONGSIDE {T}` | hold alongside a compliant victim T seconds = the take | same mechanic later = inspection, rescue |

Only three verbs are pirate-only. The rest is the shared vocabulary traders
and workers speak with zero new code — a trader IS
`GO_TO → DOCK_AT → AWAIT → GO_TO → DOCK_AT → ... → EXIT_AT` as data.

## Where role "personality" lives

- **Reactive policy**: which reactive branches the tree has + their
  parameters (a trader never has Engage; a pirate's Disengage threshold is
  lower than a patrol's).
- **The job data**: the itinerary the director assigned.
- **Role verbs**: the few executors only that class uses (SELECT_VICTIM's
  scoring IS the pirate's predatory read).
- **Per-AI assessment stays blackboard-local** (the four-tier lesson,
  economy_and_piracy.md): SELECT_VICTIM's prey scoring and the abort
  conditions ("witness in range", "victim outpacing me") are the pirate's
  own suspicion/opportunity read. Nothing of it touches the shared contact
  record — what other ships see is only what the pirate DOES.

## Honesty rule: no omniscient conditions

Job conditions may only read what the SHIP can know: its own contacts,
transponders it hears, its own state. The load-bearing case is the launder —
"stay dark until the home datalink forgets you" is not knowable, so the
pirate uses a conservative heuristic instead (dark for CONTACT_TIMEOUT + fat
margin while holding no fresh track on anyone — if I can't see them, they
likely can't see me). It can be WRONG: relight early near a patrol that
dead-reckoned you and the wanted-name assessment (M52) picks you up. That's
not a bug; that's the gameplay.

## What jobs are NOT

- Not a replacement for reactive trees — reactions stay trees; a job never
  handles being shot at.
- Not a scripting language — no branching beyond the single on_abort edge,
  no loops, no expressions. If a behavior needs more, it's either a new
  verb (capability) or it belongs in the reactive layer (reaction).
- Not migrated wholesale in M50: CargoRun/FollowRoute keep their leaves for
  now (load-bearing in many tests); migrating them onto jobs is a
  mechanical follow-up once the runner has proven itself (M53-ish, with the
  trade directors). M50 DOES ship a small non-pirate "visitor" itinerary
  test as the generality proof.
