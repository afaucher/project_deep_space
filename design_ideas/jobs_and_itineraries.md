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

Priority selectors of shared leaves, holding two kinds of things that
compose identically: **reactions** (Disengage/Flee, ThreatResponse, Engage)
and **ambient duties** (Challenge — side-effect scans that never claim the
tick; don't try to force these into jobs, they aren't missions). Role
differences up here are **policy parameters** (authority_flags, comply
thresholds, whether an Engage branch exists at all), not new leaf code. The
reactive layer ALWAYS outranks the job — a crippled pirate flees mid-heist
because Disengage sits above the runner, not because the heist knows about
damage.

One policy parameter is load-bearing enough to name here: **rules of
engagement** on the Engage layer. Today acquire_target engages ANY fresh
HOSTILE in weapons range — right for patrols, wrong for a battle fleet that
should ignore civil matters (it would open fire on a marked pirate it
happens to cruise past). ROE becomes a per-ship policy: `weapons_free`
(today's behavior) / `self_defense` (engage only what attacked us or our
faction) / `escort_only` (later). Witness rules are untouched — the fleet
still MARKS the pirate and the standing rides the datalink; it reports the
crime, it just doesn't chase it.

Ship-level hard states stay below even that: compelled_stop (M49) overrides
motion and weapons in `ship.gd` no matter what any tree wants.

### 2. Jobs — data (new in M50)

One generic `JobRunnerLeaf` executes the ship's current **job**, a plain
data structure:

```
job = {
  "steps": [ {"verb": ..., <params>, "on_abort": <label>, "label": <opt>} ],
  "current": 0,
  "repeat": false,   # standing duties loop; assignments don't
}
```

A ship holds up to TWO jobs — **assignment falls back to standing duty**,
no stack:

- `default_job` — the standing duty (patrol shift, cargo lane, tug
  standby), usually `repeat: true`; re-enters at step 0 whenever it comes
  back into effect (a shift's progress is regenerable by design).
- `assignment` — an overriding mission (a guild hunt, an M52 interdiction
  pushed by an SOS trigger, a director's order). The runner runs the
  assignment when present; on completion or abort it clears and the
  standing duty resumes.

Ship-facing API is deliberately tiny — `assign_job()` / `set_default_job()`
— so the runner's internals stay swappable. A real LIFO stack is
deliberately NOT built: it's justified only by NESTED preemption over
NON-REGENERABLE progress (a mission interrupting a mission, where the
interrupted one can't just be reissued), and nothing through M55 has that
shape. When something does, prefer the director-mediated answer first (the
director knows what it assigned and reissues the remainder) before adding
stack frames to ships. A suspended job that resumes minutes later would
need to re-validate every ship/wreck it references — complexity the
fallback-to-duty model never pays.

Each **step verb** has a small executor in a step library, reusing the same
Steering/docking calls today's leaves make. **Steps must be resumable from
arbitrary position and elapsed time**: while a reactive layer owns the tick
(cargo fleeing a pirate mid-haul), the runner simply isn't ticked, and later
resumes mid-step from wherever the ship ended up — GO_TO steers from
anywhere, DOCK_AT re-requests. A verb that can't recover from displacement
is a broken verb. Executors are stateless — any per-step scratch lives in
the step dict itself — and return one of:

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

A director is **a ledger plus a policy tick**: a plain serializable object
(not a Node, not a ship) living in `ClusterManager.directors`, ticked from
`ClusterManager.tick()` — so tests drive it with the same deterministic
manual tick as the cluster. Its config (name pools, caps, cadences, hull
mixes) is a data table; story phases (M54) swap tables, never code.

**Director honesty rule** (the director-side twin of the job-condition
rule): a director may know only what its members report and what's public.
The guild is an off-map organization; knowledge arrives by check-in. A
member going silent goes OVERDUE, and only after a presumed-lost delay does
the ledger act — no instant death notifications, no reading other ships'
sensors. This is why killing a pirate buys quiet MINUTES, not a same-frame
respawn, and it's the knowledge model every later director (trade, traffic,
militia) inherits.

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

AWAIT's condition set grows additively as classes need it: `duration`,
`track_quiet` (M50), `undocked` (dock dwell), later `unloaded`,
`until_time` (scheduled departures), `trade_complete`. Conditions obey the
honesty rule below.

## Validation: the classes this was tested against

Re-expressing existing behaviors and five planned classes on paper (before
committing the model) — each row is data + at most a couple of verbs:

| Class | Itinerary | New machinery it forces |
|---|---|---|
| Cargo lane (exists) | `GO_TO → DOCK_AT → AWAIT{undocked} → ...` repeat | `repeat`, `AWAIT{undocked}` |
| Patrol shift (exists) | `GO_TO wp1..wpN` repeat; Challenge stays an ambient tree leaf | patrols get SHIFTS for free (dock at base between them) |
| M52 interdiction | assignment: `GO_TO sos → INTERCEPT → DEMAND_STOP` — same verbs as the robbery, judged by flag | the assignment/default_job fallback |
| Fleet patrol | leader runs the sweep; wingmen `FORM_UP {leader, slot}` repeat | `FORM_UP`; the ROE parameter (above) |
| Mining | `GO_TO field → MINE → GO_TO station → DOCK_AT → AWAIT{unloaded}` repeat | `MINE` |
| Civilian transport | scheduled port calls | nothing — pure data |
| Smuggler | legit arrival → `GO_DARK → DROP_CARGO → AWAIT{track_quiet} → RELIGHT → EXIT` | `DROP_CARGO`/`PICKUP`; reuses the pirate's whole stealth family |
| Tug | duty: standby `AWAIT`; assignment on SOS(DISABLED): `INTERCEPT wreck → GRAPPLE → GO_TO station → RELEASE_TOW` | `GRAPPLE`/`RELEASE_TOW` (docking capture-spring, reused ship-to-ship) |

No case needed branching jobs, parallel steps, or a stack — the flat shape
held. Convergences worth trusting: the police stop and the stickup are one
itinerary skeleton (the same collapse comms_verbs.md found on the wire);
M49's SOS nature field is the dispatch signal for BOTH patrols
(UNDER_ATTACK) and tugs (DISABLED); smugglers reuse the pirate's stealth
verbs wholesale.

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
  no loops beyond the job-level `repeat` flag (itself a bridge: today's
  loop-forever lanes/patrols are an artifact of having no directors — the
  target state is directors assigning DISCRETE runs and shifts), no
  expressions. If a behavior needs more, it's either a new verb
  (capability) or it belongs in the reactive layer (reaction).
- Not migrated wholesale in M50: CargoRun/FollowRoute keep their leaves for
  now (load-bearing in many tests); migrating them onto jobs is a
  mechanical follow-up once the runner has proven itself (M53-ish, with the
  trade directors). M50 DOES ship a small non-pirate "visitor" itinerary
  test as the generality proof.
