# M39–M44 — Homefront: Aunt Stephanie & the "Check on Your Cousin" mission

The first authored story content: Ironhold becomes a home base with a named
character (Aunt Stephanie, the mechanic — free repairs when you dock), who gives
the first real mission: your cousin Todd, living in one of the Drift's mobile
homes, isn't answering their calls. Fly out, search the fields, talk to the
neighbors, find Todd, hear him out, and bring a present back to Stephanie.

This document scopes the six systems that scenario decomposes into, orders
them into milestones, and records the design decisions and known hazards.
Each milestone gets its own detailed design doc when picked up; this is the
route map.

## What already exists (verified against the code, 2026-07)

- **World**: `home_cluster.gd` already authors Ironhold (medium hub) + 3
  small-station mining outposts, each with an asteroid field, and FIVE
  MobileHome entities parked in those fields (Hermit's Rest, Claim 42, The
  Deep Freeze, Lucky Strike, Rock Bottom). The stage is literally built.
- **Dialogue**: Dialogue Manager runs end to end (port_control.dialogue) —
  mutations (`do station.method()`), conditions, loop-back menus, and the
  headless test pattern that drives the real DialogueManager singleton
  (test_port_control_comms.gd). The import-cache staleness fix
  (import_check.ps1) makes rapid .dialogue iteration safe headlessly.
- **NPCs**: `NPCProfile` (name/faction/tier/dialogue) broadcast via station
  transponders; comms_panel discovers in-range NPCs and starts dialogues,
  threading `{station, player}` into extra_game_states. `CommsLedger`
  exists (vouched/ephemeral) but is barely wired.
- **Docking**: grants/berths/port-control all work. Mobile homes have a
  docking port and NO port_zone → they're already open/permissionless
  docks (`docking_bay.gd::_dockable_seeking`'s zone-empty branch).
- **Nav**: NavComputer routes named destinations over the beacon graph;
  NavAutopilot flies it; the nav panel already draws overlay layers
  (docking lanes, slip highlights) — precedent for objective markers.
- **Per-instance identity on shared hulls**: ClusterManager._promote()
  already rebrands port authority + port-control NPC per entity (the
  campaign docking fix). The generalization of this IS one of the
  milestones below.

**Not present at all**: any mission/objective system, any repair mechanic,
any quest-item/inventory notion, any persistent story state, any save
system, any per-entity NPC casts.

## The six systems

1. **Story state** — flags + quest items that outlive a single conversation
   ("mission accepted", "todd_found", "has present"). Dialogue conditions
   read them; dialogue mutations write them.
2. **Mission log** — missions with ordered/parallel objectives, each typed
   (GO_TO_AREA, TALK_TO, DELIVER), granted by dialogue mutation, completing
   off game events.
3. **Repair services + engineering log** — repairs are granted through
   conversation (you talk to Stephanie to get the family rate), the
   mechanism heals docked ships' component health over time, and a
   ship-side engineering log makes damage/repair events legible
   ("Reactor overload", "<component> repaired").
4. **Objective indicators** — active objectives publish as synthetic
   contacts ("contracts"): nav-map marker + off-screen directional arrow
   via the existing contact rendering, a "Contracts" section in the
   contacts panel, a search-area ring for GO_TO_AREA (searching IS the
   gameplay), and a Missions section in the comms panel.
5. **Characters** — a story overlay (see architecture section below):
   character registry + per-entity decorations keyed by entity slug,
   merged into cluster records at load and applied generically at
   promote. Stephanie at Ironhold; residents in the homes; Todd the cousin.
6. **The mission content itself** — dialogue trees, breadcrumb hints, the
   silent home, the present, the payoff conversation.

## Story data architecture: the overlay

The load-bearing decision for everything above. We will be stamping out
MANY instances — homes, stations, NPCs, later whole clusters — and story
content will keep accreting. If casts, character data, and per-instance
tweaks get authored inline in the spatial def (home_cluster.gd) or on
hull classes, story growth means editing sim files forever, and the
spatial def becomes a god-file. So: THREE layers with separate authorship,
merged at load time.

1. **Hull templates** (`scripts/ships/*.gd`) — physical design, shared by
   every instance. NEVER story-specific. (Exists.)
2. **Cluster def** (`scripts/cluster/home_cluster.gd`) — spatial placement
   and simulation role: ids, positions, kinds, behaviors, iff. Sim only.
   (Exists.) One addition: entities that story content references get a
   stable string slug (`sid: "ironhold"`, `sid: "claim_42"`) — display
   names are for humans and may change; int ids are positional bookkeeping;
   slugs are the join key story data uses.
3. **Story overlay** (new, `story/` directory) — everything narrative,
   keyed by slug:
   - `story/characters.gd` — the character registry:
     `{"aunt_stephanie": {name, role, dialogue_path, home_sid}, "todd":
     {...}, ...}`. One entry per person; dialogues live in
     `dialogue/characters/`.
   - `story/home_cluster_overlay.gd` — per-entity decorations:
     `{"ironhold": {cast: ["aunt_stephanie"], port: {services: {repairs:
     "free"}}}, "claim_42": {cast: ["todd"], component_overrides:
     {comms_array: {range: 1500.0}}}, ...}`.

**Merge point**: ClusterLoader folds the overlay into ClusterEntity
records at load time (records carry cast/overrides/port data as plain
fields); ClusterManager._promote() applies whatever the record carries —
generic mechanism, zero story knowledge. ClusterManager never learns who
Stephanie is.

What this buys as content scales:
- Adding a resident = one characters.gd entry + one overlay line + a
  .dialogue file. No sim code touched, no hull touched, no cluster def
  touched (unless the entity is new).
- Missions reference people and places symbolically ("TALK_TO todd",
  "DELIVER to aunt_stephanie") and resolve through the same registry —
  no node paths or display-name string matching in mission definitions.
- Static content (overlay, characters) stays cleanly separate from
  mutable state (StoryState flags/items) — the save-system boundary is
  already drawn.
- Tests can load a tiny synthetic overlay against a synthetic cluster —
  story machinery is testable without the real script.

## Milestones

### M39 — Story state & mission log (foundation, no UI)

- `StoryState`: a plain autoload holding `flags: Dictionary` and
  `quest_items: Dictionary` with get/set/has API. Exposed to every dialogue
  via comms_panel's `_dialogue_game_states()` (add it to the dict, same as
  `station`/`player`) so `.dialogue` files write `do story.set_flag(...)` /
  `if story.has_flag(...)`. NOT persisted to disk yet — but keep it all
  plain-Dictionary so a save file later is `var_to_str` away.
- `MissionLog` (node on the player ship, like CommsLedger): missions are
  Dictionaries — `{id, title, giver, objectives: [...], state}` — with
  objectives `{id, kind, text, target, state}`. Kinds for this arc:
  `GO_TO_AREA {center, radius}`, `TALK_TO {npc_name}`, `DELIVER
  {item, npc_name}`. API: `start_mission(def)`, `complete_objective(...)`,
  signals for UI. Objective completion hooks: GO_TO_AREA proximity check
  ticks in MissionLog's OWN _physics_process (never added to ship.gd's
  already-hot per-frame path); dialogue mutations for TALK_TO and DELIVER.
- Tests: pure-logic mission lifecycle; a dialogue-driven test where a
  .dialogue mutation starts a mission and a later condition branches on a
  story flag (DialogueManager-singleton pattern).

### M40 — Repair mechanism + engineering log

Repairs are GRANTED THROUGH CONVERSATION, not automatic-on-dock: you have
to talk to Aunt Stephanie to get the free family rate. M40 builds the
mechanism and the observability; M42 wires Stephanie's dialogue as the
in-fiction trigger (until then, tests drive the method directly).

- Mechanism: `station.begin_repairs(ship)` — valid only while `ship` is
  DOCKED at that station; restores `health` toward `max_health` across
  ship_components at a rate; stops on undock. Respect the
  ship-is-its-parts invariants (never resurrect a hulk; repairing a
  destroyed reactor on a live ship is fine). Callable from dialogue via
  the extra_game_states station object — the same surface port control
  uses.
- Engineering log: a ship-side event log (ring buffer of
  {time, severity, text}) the ship writes to from the code paths that
  already exist — "Reactor overload", "Thermal shutdown", "<component>
  damaged", "<component> destroyed", "<component> repaired", "Repairs
  complete". Displayed as a scrolling section in the engineering panel.
  This is general observability, not repair-specific — combat damage
  becomes legible the same way.
- Tests: damaged ship docks + begin_repairs → heals to full and the log
  records it; undocks mid-repair → stops; begin_repairs while not docked
  → refused; hulk stays dead; damage/overheat events land in the log.
- **Fold-in — a second Ironhold berth.** MediumStation authors exactly
  ONE docking_port while two NPC cargo shuttles loop through Ironhold.
  Verified shuttle behavior is already polite: the grant is requested
  only within 4000u (inside the 8000 zone — cargo_run_leaf's
  DOCK_REQUEST_RADIUS), the bay auto-releases after 1.5s docked
  (dock_duration), and the grant self-clears on zone exit
  (_update_docking_grant's zone check) — so a berth is held well under a
  minute of each ~10-minute round trip. Contention is therefore
  OCCASIONAL (player and shuttle wanting the one berth at the same
  moment), not chronic — but home base must never bounce the player, so:
  add a SECOND docking_port to MediumStation. Ripple to manage:
  test_port_control_comms scenario 2's "full station denies" premise
  assumes a single-bay MediumStation — rework against a genuinely-full
  station — and re-validate the hull layout (overlap/connectivity) after
  adding the port.

### M41 — Objective indicators: contracts are NAV-layer data

Framing: a contract entry is NAV data — a known coordinate, a general
area, a named place — the same knowledge family as destinations, beacon
routes, and docking lanes. It is NOT a sensor detection, so it lives in
the nav layer alongside them, never in ship.contacts (which would make no
sense anyway: the fusion machinery would correlate real blips into it and
decay it like a stale track — nav knowledge doesn't decay).

What contracts BORROW from contacts is presentation: the nav panel
already renders on-screen markers and an off-screen edge arrow pointing
at things out of view (navigation_panel.gd's edge-intersection arrows,
~line 772) — contract markers reuse those affordances (the directional
"dorito" comes free), with their own color/style so nav knowledge reads
distinct from sensor knowledge. Only the GO_TO_AREA area ring is new
drawing.

- MissionLog publishes active objectives as contract entries
  {id, title, kind, pos, radius, mission_id} — a nav-layer feed the
  panels consume alongside the sensor contact list.
- Nav panel:
  - Contract markers with contact-style affordances (marker + off-screen
    edge arrow), own color/style.
  - GO_TO_AREA additionally draws a dashed ring at {center, radius}.
- Contacts panel: a new collapsible "Contracts" section at the END of the
  existing sections (Enemies / Ships / All Contacts / Contracts), same
  header-with-count affordance. Selecting one focuses the nav map on it
  (same contact_selected flow).
- Comms panel: a small "Missions" section listing active missions +
  current objective text (this panel is where missions are GRANTED, so
  it's also where you review them).
- Per-mission indicator mute, designed-in NOW (rendered later if needed):
  each mission carries `indicators_visible: bool` (default true); the
  contract feed filters on it. This is the future "ignore this mission /
  one-at-a-time" affordance — the UI toggle can come whenever, the data
  path exists from day one so it never needs a refactor.
- NavComputer: allow routing to a contract's position (it already routes
  to arbitrary positions internally; expose contracts as destinations —
  natural, since contracts ARE nav destinations with mission context).
- Tests: headless assertions on the contract feed (active objective ->
  published entry; muted mission -> filtered out; completed -> removed);
  rendering itself stays eyeball-verified like other panel layers.

### M42 — Characters v1: the story overlay + Aunt Stephanie

Builds the overlay architecture (see "Story data architecture" above) and
proves it with the first character.

- Entity slugs (`sid`) on cluster-def entities story content references.
- `story/characters.gd` (character registry) + `story/home_cluster_overlay.gd`
  (per-entity decorations), merged into ClusterEntity records by
  ClusterLoader at load time.
- ClusterManager._promote() applies record-carried decorations
  generically: cast (instantiate NPCProfiles onto `available_npcs`),
  port patches. Injection APPENDS: MediumStation._init() already
  self-appends its port-control NPC and _rebrand_port_zone mutates it —
  cast injection must not clobber that (order: construct → rebrand →
  apply overlay). (Class-level defaults on shared hulls are how we got
  the docking bug — record-carried decorations are the antidote,
  extended from port identity to people.)
- NPCProfile stays lean; add only what's needed: `role: String` (e.g.
  "mechanic"), maybe `portrait` later. Full character sheets are a
  design_ideas doc for another day.
- Aunt Stephanie: registry entry + Ironhold overlay entry + her own
  .dialogue with real personality (short, warm, busy-mechanic voice),
  the free-repairs flavor ("family doesn't pay") calling M40's
  begin_repairs, and the mission grant mutation gated on a story flag so
  she only offers it once.
- Tests: synthetic overlay against two promoted stations → distinct
  casts; overlay port patch lands; Stephanie's mission mutation fires
  once and sets the flag; re-hail branches to the post-accept text.

### M43 — The Drift residents & the silent home

How Todd reads on sensors was talked through explicitly (see the decision
note below): his comms are DAMAGED, not off — transmitter range collapsed
from 30k to ~1.5k. The home still runs its reactor and life support, so
it's EM-loud and classifies as a VESSEL like its neighbors — but it
broadcasts no transponder at normal range, so it's the one vessel in the
field WITHOUT a name tag. Finding Todd is process of elimination: hail
the named homes (the breadcrumb conversations), notice the unnamed
contact, fly close. Inside his crippled ~1.5k range the existing
discovery/hail machinery works unchanged — NO new comms channel needed.

Rejected alternative, recorded: fully powered-down home. EM-dark +
component density 20 classifies as WRECKAGE (classify_contact's
density split) — the player would read Todd as dead, which fights the
brief ("explain why he's not answering", not "fear the worst"), and
"living in a cold hull" strains the fiction. Damaged-transmitter also
locks the theme together: the family mechanic, the apology present.

- **(Revised at pickup, 2026-07)** All five homes live in ONE community —
  the Slag Bay field, expanded (10k → 16k radius) to fit them with real
  flying distance between them. The original layout spread them across
  three outposts' fields, which made the search trivial (one named + one
  unnamed contact in the search area).
- **(Revised)** Two of the four neighbor homes are ANONYMOUS, not chatty:
  `transponder_share_name: false` (an existing ship.gd mechanism — they
  broadcast "UNKNOWN" but comms stay healthy). They're false positives for
  the elimination search, and they give the mission its two kinds of
  silence: the anonymous homes WON'T talk (hail them, they answer — go
  away / don't know him), Todd CAN'T talk (dead air until you close to his
  collapsed range). Learning that difference is the search.
- The cast (fiction approved in-session): Hermit's Rest — Mae & Gus,
  retired mining couple, hadn't heard from Todd and didn't think it odd.
  The Deep Freeze — Wex, loony rambling with the arc's one real buried
  clue (antenna snapped in the gravel storm, lights still on, spinward
  edge). Lucky Strike — Dost, anonymous, tells you to clear off. Rock
  Bottom — Prell, anonymous, doesn't know Todd, barely talks. Breadcrumb
  content is mission-gated (`[if story.has_flag("todd_mission_accepted")]`);
  the residents themselves exist regardless (world feels lived-in).
- Todd's home: comms component `range` collapsed (damaged) — one number,
  authored as a `component_overrides` entry in the story overlay
  (`"claim_42": {component_overrides: {comms_array: {range: 1500.0}}}`),
  NEVER an edit to mobile_home.gd: `MobileHome.design()` is a class-level
  static shared by all five homes; touching it silences the whole Drift.
  _promote() applies overrides generically like the rest of the overlay —
  the same record-carried-identity pattern, extended from "who's aboard"
  to "what shape this instance is in". Whether the component also shows
  damaged health (visible if scanned close) is flavor to decide in the
  milestone design doc.
- Tests: Todd's home undiscoverable at normal hail range; discoverable
  and hailable inside the collapsed range; classifies as a VESSEL (not
  WRECKAGE); breadcrumb lines appear only mission-active.

### M44 — "Check on Todd" end to end

**Fiction is co-authored: ASK before writing.** The dialogue content —
Stephanie's voice, Todd's explanation, the neighbors' texture, what the
present is — gets written WITH the user, not drafted unilaterally. Bring
the structural skeleton (branch points, state reads/writes, mutation
hooks) to that conversation; leave the words blank until it happens.

- The mission definition: Stephanie grants → GO_TO_AREA (the Slag Bay
  field, radius 16k since M43's expansion) → TALK_TO Todd (satisfied by
  hailing him inside his collapsed comms range; the conversation is the
  arc's centerpiece — why the transmitter's dead, a bit of family
  texture, branch flavor by what the player asked the neighbors) → Todd's
  mutation grants `quest_items["stephanies_present"]` → DELIVER to
  Stephanie at Ironhold → completion, Stephanie's payoff lines, flag set
  for future arcs.
- Which home is Todd's: FIXED (decided) — testable, and the breadcrumbs
  are authored against it. Randomized variants are a later-arc idea.
- The E2E headless test: drive the entire flow — accept at Ironhold, warp
  the test ship to the field (tests teleport via PhysicsServer2D, the
  established trick), assert the area objective completes, close within
  Todd's collapsed comms range, run his dialogue through the real
  DialogueManager, assert the present lands in quest_items, return,
  deliver, assert mission COMPLETE and Stephanie's dialogue branches to
  post-mission text.

**Status: part 1 SHIPPED (Todd's conversation, commit 99a795c, 2026-07).**
Fiction co-authored and approved in-session; family canon recorded in
design_ideas/homefront_family.md (Stephanie is aunt to BOTH cousins;
Todd's parents out of the picture; voice recognition, never ship). What
shipped beyond the sketch above:

- Todd's conversation (dialogue/characters/todd.dialogue, placeholder
  gone): antenna broke on an unlucky rock in the gravel storm (agrees
  with Wex), replacement ordered THROUGH Prell, mine overwork explains
  the three silent weeks, "Do you think I should have called her?" beat.
- The Prell callback: prell.dialogue's ask branch sets
  `asked_prell_about_todd` (even as Prell stonewalls); Todd's dialogue
  offers "Prell told me they'd never heard of you" only on that flag —
  "And THAT is why I like Prell."
- The present is UNDISCLOSED (revised from an early named-tool draft):
  handed over sealed, the reveal belongs to Stephanie's payoff. Handoff
  is DOCK-GATED via player.is_docked_at(station) — "come dock and take
  it" is literal; `todd_present_given` guards against any re-grant.
- talk_todd completes via MissionLog.notify_talked_to on first contact;
  mission advances to deliver_present. Covered by test_todd_dialogue.

**Part 2 REMAINING (the arc close — fiction still to co-author):**
- Stephanie's delivery branch: a response offered while carrying
  `stephanies_present` (+ deliver_present active), the REVEAL of what the
  box actually is (the headline open decision), notify_delivered
  completing the mission, payoff lines, a completion flag for future arcs.
- Her post-mission revisit state: "Any word from Todd?" needs a new
  answer once he's found/mission complete.
- The E2E headless test above.

## Order & dependencies

M39 (state+missions) is the root; everything reads or writes it.
M40 (repairs) is independent of M39 — can run in parallel or first.
M41 (indicators) needs M39's objective data.
M42 (casts+Stephanie) needs M39 (grant mutation writes mission/flags).
M43 (residents+silent home) needs M42's cast machinery.
M44 (the mission) needs all of the above.

Suggested sequence: **M39 → M40 → M42 → M41 → M43 → M44** (M40 early
because it's small, self-contained, and immediately felt in play; M41
after M42 so there's a real mission to indicate while building it).

## Significant challenges (and positions taken)

1. **Where story/mission state lives.** The story_driven_comms design doc
   wants hull-locked, per-player ledgers with server-authoritative
   mutations. Full multiplayer authority is NOT this arc's problem — but
   don't paint into a corner: StoryState/MissionLog are plain-data
   (Dictionaries), accessed through a narrow API, owned per-player-ship
   where sensible (MissionLog on the ship node like CommsLedger; StoryState
   an autoload for now). Migrating to replicated per-peer state later is a
   move, not a rewrite.
2. **Per-instance identity on shared hull classes.** The campaign docking
   bug was exactly this trap. The story overlay (M42) is the general fix:
   per-instance identity lives in record-carried overlay data, applied at
   promote. Nothing story-visible may live as a class-level literal on a
   hull that campaign instantiates more than once.
3. **Promote/demote and state.** Campaign currently runs FullSim (nothing
   demotes), but the bubble may return. Rule: no story or mission state on
   live nodes, ever — it lives in StoryState/MissionLog/ClusterEntity
   records, and promote re-derives node-side presentation (casts, zone
   branding) from records. That rule is cheap to follow now and brutal to
   retrofit.
4. **No save system.** Out of scope for the arc, but every piece of state
   introduced (flags, quest items, mission dicts, objective progress) must
   be plain serializable data so "write it to user:// as one dict" is a
   single small milestone later. No Object references inside state.
5. **Search-gameplay tuning.** Fields are ~10–12k radius and healthy home
   comms reach 30k, so the NEIGHBORS are findable the moment the player
   enters the ring — good, they're the breadcrumb source. Todd is the one
   VESSEL contact with no transponder name; the search is elimination
   (hail the named ones, investigate the unnamed one) plus closing to his
   collapsed ~1.5k hail range. If it plays too easy, widen the field /
   shrink his range further; if too tedious, the breadcrumb hints narrow
   the sub-area. Tunables, not architecture.
6. **Dialogue as the mutation surface.** Mutations calling into
   station/ship methods worked for port control but each new callable
   grows the .dialogue↔code contract. Keep ONE pattern: dialogue reaches
   game systems only through objects handed in extra_game_states
   ({station, player, story, missions}) — never autoload lookups inside
   .dialogue files — so tests can hand in fakes and the contract stays
   visible in one place (comms_panel._dialogue_game_states + the test
   helpers).
7. **Conversation scale.** Todd's conversation is the biggest
   authored dialogue yet (branches, state reads/writes, revisit behavior).
   The DialogueManager-driven headless test pattern + the import-staleness
   fix are the enabling tooling — both already landed. Write the
   conversation-flow test alongside the .dialogue file, not after.

## Deferred: cargo (noted, not in this arc)

There is NO cargo system in the game today — cargo shuttles and the
CargoRun leaf are choreography; nothing actually carries anything. This
arc deliberately does NOT build one: the present is a quest item
(`quest_items["stephanies_present"]` in StoryState), because the mission
never exercises cargo mechanics — it can't be lost, sold, or crowded out
of a hold, so a cargo system would add surface area without adding play.

Cargo IS clearly coming (ore shuttles, mining outposts, Drift Market, a
refinery — the economy loop is on the map). When a mission or trading
loop actually needs it, ship-is-its-parts gives it a natural shape: a
`cargo_hold` COMPONENT with capacity and contents, loaded mass genuinely
changing flight dynamics (mass already derives from components), holds
targetable/losable in combat. That's its own milestone.

Migration path, kept cheap by two rules followed in this arc:
- DELIVER objectives name their payload generically (`item_id`), so the
  mission definition doesn't care which system backs the item.
- When cargo lands, "the present" becomes an item in a hold and DELIVER
  checks the hold instead of quest_items — a small, contained change to
  MissionLog's DELIVER handling, invisible to mission definitions.
