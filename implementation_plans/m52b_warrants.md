# M52b — Warrants: replace sticky HOSTILE with observed, typed, revocable records

Sub-milestone of the M52 design pass (m48_m55_economy_piracy_roadmap.md),
implementing design_ideas/warrants.md. That doc is the spec — offense
taxonomy, response classes, issuing authority, propagation/dedup rules,
militia framing — this plan is the build order against the actual M48
code it replaces. Read the design doc first; this file doesn't restate
its reasoning, only the concrete migration.

## 1. What's being replaced (current call sites)

Everything below currently mutates a sticky `contact["standing"]` bit.
Each becomes a warrant post instead.

- `Standing.compute_standing()` (standing.gd:79) — the rule cascade
  (crypto → sticky HOSTILE → known-enemy-flag → transponder → UNREPORTED).
  Rule 2 ("sticky: existing HOSTILE stays") is exactly the thing being
  retired; rules 1/3/4/5 stay as the FRIENDLY/NEUTRAL/UNREPORTED base and
  now feed a *default* standing that a matching warrant can escalate.
- `Ship.mark_contact_hostile()` (ship.gd:1826) — player MARK RPC, called
  from terminal_display.gd:650. Becomes: post an `OPERATOR_FLAGGED`
  warrant, `origin_flag` empty (player starts with no `warrant_authority`
  — design doc's issuing-authority section).
- `Ship.clear_contact_hostile()` (ship.gd:1845) — player UNMARK RPC.
  Becomes: set that warrant's `status = RESOLVED`, fresh timestamp (the
  doc's revocation mechanism), not an erase — same latest-timestamp-wins
  rule as every other resolution.
- The aggression-witness loop (ship.gd:2445-2494) — own-faction hit
  (instant HOSTILE) and stray-fire (`aggro_hits` gate) branches. Become
  `ASSAULT` (instant, own-faction) and `SUSTAINED_ASSAULT` (gate-crossed)
  warrant posts. `aggro_hits` itself is UNCHANGED — private per-observer
  scratch, per the design doc's settled confidence-gates-issuance answer.
- Hail STOP-demand handling (ship.gd:2523-2530 addressed-to-me,
  2536-2539 overheard) — non-authority STOP demand flips the issuer
  HOSTILE. Becomes `ARMED_THREAT` warrant post.
- `Standing.wanted_names` (standing.gd:121) — stays as-is; it's the
  patrol-assessment input the design doc explicitly keeps ("suspicion is
  not a standing"), orthogonal to warrants.
- Datalink relay's standing-share block (ship.gd:2763-2799,
  `PerfProbe.begin("datalink_relay")`) — currently does severity
  compare-and-copy on `contact["standing"]` piggybacked on the per-track
  record. This is the propagation mechanism the design doc means by
  "warrants ride the existing datalink/comms relay like contacts do" —
  see the architecture note below for why warrants get their OWN merge
  pass here rather than continuing to ride inside the contact dict.

## 2. Architecture note: warrant store is per-ship, NOT a `Standing` static

`Standing.wanted_names` and `Standing.aggression_events` are process-wide
`static var`s — genuinely global, visible to every ship unconditionally.
**Do not copy that shape for warrants.** The design doc's "not on the
network → you can't see it" visibility rule is meaningless against a
global list everyone can already see. Warrants need the SAME shape as
`active_contacts` and the datalink relay above: a store that lives ON
each `Ship` (`var warrants: Dictionary = {}`, keyed by `event_key`),
populated by warrants that ship personally posts, plus whatever a linked
peer relays in — same merge pass as the existing datalink-relay standing
share, just its own step (latest-timestamp-wins on `event_key`, not the
severity compare-and-copy contacts use) rather than piggybacked inside
the per-track dict. This also lets a warrant remain enforceable/visible
on the WANTED sense even when its subject isn't a currently-live contact
(out of sensor range right now, still on your list).

A second per-ship structure, rebuilt cheaply alongside it: a subject-key
→ worst-matching-open-warrant index (`Dictionary`, same key shape as
`event_key`'s subject component and `Standing.wanted_names`) — this is
what `compute_standing`'s replacement does an O(1) lookup against instead
of reading a sticky bit (design doc's settled Q3 answer).

## 3. Migration steps

1. **Warrant record + local store + expiry, no behavior change.**
   `Standing.gd` gains the record shape (design doc's `Core model`), a
   `static func make_warrant(...)`, and pure `is_expired`/`resolve`
   helpers. `Ship` gains `var warrants: Dictionary = {}` and
   `var warrant_authority: Array = []`. Nothing posts to it yet — this
   step is data-shape only, provable by a pure-function test.
2. **`warrant_authority` defaults + origin-scoping helper.** Stations and
   patrol/military archetypes default `warrant_authority` to their own
   flag; everyone else (including the player) stays empty. A pure
   `Standing.scoped_origin(issuer_flag: String, issuer_authority: Array)
   -> String` helper returns the flag or `""` per the design doc's rule —
   every posting call site below routes through this one function so the
   rule lives in exactly one place.
3. **Migrate the posting call sites one at a time**, each is its own
   commit-sized change with its own test update:
   a. `mark_contact_hostile`/`clear_contact_hostile` → `OPERATOR_FLAGGED`
      post/resolve. Lowest-risk first (single-player-local, no relay
      dependency yet).
   b. Aggression-witness loop → `ASSAULT`/`SUSTAINED_ASSAULT`.
   c. Hail STOP handling → `ARMED_THREAT`.
   d. Pirate job take-alongside completion → `ARMED_ROBBERY` (new call
      site — nothing posts this today; find the take-completion point in
      job_steps.gd's TAKE_ALONGSIDE success path).
4. **`compute_standing` reads the warrant index instead of the sticky
   bit.** Rule 2 (sticky HOSTILE) is deleted outright; a new rule between
   crypto and known-enemy-flag does the index lookup, maps the matched
   warrant's response class to one of the four shared tiers, and that's
   the new "escalated" case. `contact["standing"]` keeps being cached
   once per fusion tick exactly as today (design doc Q3) — only its
   INPUT changes.
5. **Datalink relay gets its own warrant merge pass**, adjacent to (not
   inside) the existing standing-share block, reusing the SAME peer loop
   and its four link gates (ship.gd:2666 — comms range both ways, LOS
   raycast, IFF-tag overlap): for each linked peer, latest-timestamp/
   highest-status-wins merge of `peer.warrants` into `self.warrants` by
   `event_key`. **Filter before merging: only warrants with
   `origin_flag != ""` are eligible to relay** — personal-origin warrants
   stay on their issuing ship regardless of link state (design doc's
   settled propagation answer). Rebuild the subject-key index after any
   merge that actually changed something (skip the rebuild on a no-op
   merge tick — most ticks).
6. **On-request station pull.** New `PortControl.request_warrant_list(
   station, ship) -> Dictionary`, same shared-entry-point shape as
   `request_docking()` (port_control.gd:82) so the dialogue path and any
   fast-path UI button call through one function and can't diverge. Wire
   it to fire on docking (and/or a hail action, mirroring how
   `request_docking` already serves both a dialogue "do" line and the
   fast-path button — port_control.gd's own header comment). The station
   answers with its own `warrants`; the caller merges matches into
   `ship.warrants` by the same latest-timestamp/`event_key` rule as the
   live relay, preserving the station's `origin_flag`. One-shot pull, not
   a subscription — no ongoing state to maintain once the query returns.
7. **Response classes (INTERCEPT/MAX) + per-tree enforcement policy.**
   Enforcement eligibility is the SAME `warrant_authority.has(origin_flag)`
   check step 2's scoping helper already established for issuing (design
   doc's now-unified Authority chain section) — no new field, just a
   second caller of the existing one. This is the input the M52
   patrol-interdiction milestone consumes, not UI-visible on its own — a
   patrol's behavior tree reads "do I enforce this offense's flag, and at
   what class" (per-tree policy list, same shape as the existing ROE
   parameter). Land the policy lookup here so M52's patrol tree has
   something to call; the patrol tree's own demand/engage sequencing is
   that milestone's scope, not this one's. A warrant present but NOT
   `warrant_authority`-eligible still feeds the derived-standing lookup as
   informational (avoid-worthy, not fire-worthy) — the player's UI case is
   trivial (just show it); whether any AI role (traders rerouting around a
   known-dangerous contact) consumes the informational case too is a call
   for whichever milestone builds that AI, not required here.
8. **UI**: targeting-computer warrant detail (replaces the standing-
   reason readout's guts — same panel MARK/UNMARK already lives in,
   terminal_display.gd), WANTED list at stations (reads a station's own
   `warrants`, filtered to `warrant_authority`-scoped + bounty-flagged —
   station bounty fields are future work per the design doc, so this can
   ship with no bounty column yet), and the station-pull trigger (docking
   UI / comms panel) from step 6.
9. **Militia framing**: campaign start-state seeds the player ship with
   empty `warrants`/`warrant_authority`/no datalink membership with home
   stations — confirm this is already true by default (new fields
   default empty) or needs an explicit campaign-init line if some other
   system currently grants the player a starting IFF/datalink link to
   home infrastructure.

## 4. Test coverage plan

Existing tests to update in place (they currently assert the sticky-bit
behavior directly and will need to assert on `warrants`/derived standing
instead):

- `test_standing_rules.gd` — the `compute_standing` rule-table tests;
  rule 2 gets replaced with warrant-index cases.
- `test_standing_e2e.gd` — end-to-end datalink propagation; needs the new
  warrant-merge pass covered alongside the existing severity-share
  assertions.
- `test_hail_protocol.gd` — STOP-demand-flips-HOSTILE assertions become
  STOP-demand-posts-`ARMED_THREAT` assertions.
- `test_sandbox_hostility.gd`, `test_mine.gd`, `test_missile_ai.gd` — all
  use `mark_contact_hostile` as an "immediate engagement" test lever
  (ship.gd:1820's own doc comment calls this out); confirm they still
  work unchanged (the RPC signature doesn't change, only its internals) —
  should be a green-without-edits check, not a rewrite, unless one of
  them asserts on `contact["standing"]` directly rather than just relying
  on the engagement behavior it causes.

New tests:

- **Warrant record pure functions** (unit): expiry, resolve/latest-
  timestamp-wins, `event_key` dedup collision vs distinct-subject
  non-collision.
- **`warrant_authority` origin-scoping** (unit): authorized issuer →
  `origin_flag` set; unauthorized → `origin_flag` empty, warrant still
  created. Covers the design doc's settled answer directly.
- **Revocation propagation** (integration): warrant resolved by its
  issuer → relayed peer's stale OPEN copy is overridden once the
  RESOLVED copy reaches it (not before).
- **Personal-origin warrants never relay** (integration): two linked
  ships sharing IFF, in range and LOS — an `origin_flag: ""` warrant on
  one (e.g. a MARK) must NOT appear in the other's `warrants` after a
  relay tick; an `origin_flag`-bearing warrant on the same ship, same
  tick, DOES appear on the peer. Proves the filter is applied per-
  warrant, not per-link.
- **MAX vs INTERCEPT patience** — deferred to the M52 patrol milestone
  (that's where a behavior tree actually consumes response class); this
  milestone only needs to prove the class is correctly attached to each
  warrant type, not that a tree acts on it yet.
- **Station pull merges, doesn't subscribe** (integration): dock, pull —
  matching station warrants land in `ship.warrants`; undock, wait, and
  confirm nothing further arrives without a second explicit pull (proves
  it's one-shot, not an accidental live link).
- **Enforcement gate matches the issuing gate** (unit): a ship holding a
  warrant whose `origin_flag` it lacks `warrant_authority` for computes
  as informational/non-enforceable; granting that flag's authority (same
  helper as issuing) flips it enforceable with no other state change —
  proves the two are genuinely one gate, not two that happened to agree.
- **Wreck gate still holds**: a warrant names a subject; killing the
  subject and having it become a wreck must not keep matching it (same
  guarantee M52a's wreck-gate fix already established for the old sticky
  bit — confirm the new warrant-index lookup preserves it, since
  `classify_contact` keying on EM-not-heat is unrelated to this change
  but the interaction is worth one explicit regression test).

## 5. Order of work

1. Step 3.1 (record shape + store, no behavior change) — provable in
   isolation, zero risk to existing green tests.
2. Step 3.2 (`warrant_authority` + scoping helper) — still no behavior
   change, just the rule that step 3's call sites will route through.
3. Steps 3a–3d one at a time, each with its test file updated in the same
   change, each independently buildable/testable (MARK first — lowest
   blast radius, no relay dependency).
4. Step 4 (`compute_standing` cutover) — this is the one that actually
   changes observable behavior; do it only once all four posting sites
   exist, so nothing regresses to "never HOSTILE" mid-migration.
5. Step 5 (relay merge pass) + its e2e test.
6. Step 6 (station pull) — independent of step 7, can land before or
   after it; grouped here because both build on the same merge-by-
   `event_key` primitive step 5 establishes.
7. Step 7 (response classes) — unlocks the M52 patrol milestone; land
   last among the behavior steps since nothing in THIS milestone
   consumes it yet.
8. Steps 8–9 (UI, militia start-state) — polish/framing, can slot in
   wherever convenient once 1–7 are green.

Full `build.ps1` gate before considering the milestone done, per this
repo's standing convention — this touches core standing/combat-response
plumbing that a huge fraction of the test suite exercises indirectly.

## Findings (as-built)

Built in the order section 5 lays out, steps 1–4 as one tested unit (see the
deviation below for why), then 5, 6, 7, and a scoped 8/9. Full `build.ps1`
gate is green: **0 test failures, export + package succeeded.**

### Steps 1–2 — record shape, store, origin-scoping

`standing.gd` gained the warrant record shape, the offense taxonomy table
(`OFF_*` constants → `{response, expires_after}`), `make_warrant`/
`resolve_warrant`/`is_expired`/`merge_warrant`/`subject_key`/
`warrant_subject_key`/`scoped_origin`/`warrant_enforceable_by`/
`build_warrant_index` — all pure functions, no Node state. `Ship` gained
`warrants: Dictionary` (event_key → record), `warrant_authority: Array`
(default empty), and `warrant_index: Dictionary` (subject_key → worst
enforceable OPEN warrant, rebuilt once per fusion tick).

Two deliberate, low-risk extensions beyond the doc's literal schema:

- **Clock**: `timestamp`/`expires`/`resolved_at` are physics-frame counts
  (`Engine.get_physics_frames()`), not wall-clock seconds — the same
  deterministic-under-`--fixed-fps` convention `job_steps.gd`'s patience/
  blacklist timers already use (CLAUDE.md's "flaky sim timeout" note).
  `PHYSICS_HZ` converts an offense's authored expiry (seconds) to a frame
  count once, at post time.
- **`reason` field**: added to the record (free text), not in the doc's
  literal "Core model" list. Every existing sticky-HOSTILE call site had a
  human-readable reason string (`"fired on us"`, `"sustained attack on
  X"`, `"demanding we stop"`, the player's own MARK reason) that several
  tests assert on verbatim — threading it through the warrant was the only
  way to preserve those assertions without inventing new UI-facing text.

**`event_key` simplified from the doc's `(offense, subject, coarse time
bucket, coarse location bucket)` to `offense + "|" + subject_key`** (no
time/location bucketing). Reasoning: bucketing exists to converge two
*independent* observers who each separately witness the *same* real-world
event onto one record. Every posting call site this milestone actually
wires (take_damage's own-hit flip, the witnessing ship's own aggro-hits
gate, the addressed/overheard hail witness, the robbery victim's own
report) is a single ship posting about its OWN observation — there is no
v1 call site where two different ships independently post about the
literal same offense instance, so the collision case the bucket exists to
solve never arises yet. Documented here rather than silently dropped;
worth revisiting if/when the M52 patrol milestone adds multi-observer
posting (e.g. two patrols independently witnessing one robbery).

**The enforcement gate (`warrant_enforceable_by`) was built here, not
deferred to step 7 as section 3's numbering suggests.** compute_standing's
step-4 cutover structurally needs it the moment step 5 (relay) or step 6
(station pull) can inject a foreign warrant into `observer.warrants` —
without the gate, compute_standing would escalate ANY visible warrant to
HOSTILE regardless of authorization, directly contradicting the design
doc's "cross-flag warrants are visible... but unenforced" and "you just
can't fire on the strength of it alone." Step 7 then reuses the exact same
function unchanged for its own purposes — exactly the "no new field, just
a second caller" shape the plan already anticipated, just landed one step
earlier than the section numbering implied.

### Steps 3a–3d — the four posting call sites

All four migrated: `mark_contact_hostile`/`clear_contact_hostile` →
`OPERATOR_FLAGGED` post/resolve; `take_damage`'s own-hit flip and the
aggression-witness loop's own-faction/stray-fire branches → `ASSAULT`/
`SUSTAINED_ASSAULT`; hail STOP (addressed-to-me and overheard) →
`ARMED_THREAT`; `job_steps.gd`'s `step_take_alongside` DONE path (new call
site, nothing posted this before) → `ARMED_ROBBERY`, posted by the
**victim** naming the pirate off its own held track (same "whoever
experienced it posts it" shape as `take_damage`).

**Deviation found and fixed: compute_standing does not run every physics
tick.** It only re-invokes on a contact's *own* sensor-bin update (the
correlate-update/new-contact call sites inside the bin loop), not
unconditionally every frame — sensor refresh cadence, not 60Hz. The old
sticky-bit code was invisible to this because every posting call site
wrote `contact["standing"]` **directly and immediately**, bypassing
compute_standing's cadence entirely for the flip itself (sticky only
mattered for making it *persist* on the next, later recompute). Cutting
those direct writes over to warrant-posting-only reintroduced a real
latency bug: `test_standing_e2e`'s Scenario C failed with the victim still
reading UNREPORTED several frames after `take_damage`, because no bin
update had re-run compute_standing yet. Fix, applied at all five posting
sites (including the robbery one, no existing test required it but the
same bug would have hit it): **post the warrant, then ALSO eagerly stamp
`contact["standing"]`/`["standing_reason"]` immediately**, same value the
warrant carries. The warrant stays the actual source of truth — the next
recompute (whenever the bin next updates) re-derives from `warrant_index`
and will correctly clear/downgrade the eager stamp once the warrant
resolves or expires. This is a same-tick cache-priming fix, not a
reintroduction of stickiness: nothing reads the sticky bit anymore,
compute_standing's rule 2 is 100% warrant-index-driven.

`test_standing_rules.gd`'s old sticky-bit cases (2, 8, 9) were rewritten
into warrant-index cases (dedicated observers with a preset
`warrant_index`, since the table-driven case list shares one mutable
`observer_a` across all rows). New pure-function coverage added: expiry
(short-vs-never per offense), resolve/latest-timestamp-wins merge (incl.
the RESOLVED-beats-OPEN tie-break), `subject_key` dedup collision vs
non-collision (claimed-name and signature-fallback paths both), the
enforcement/issuing gate mirroring itself (personal-origin enforceable
only by its own issuer; flagged enforceable only by a ship holding that
flag's `warrant_authority`), `build_warrant_index`'s worst-open-wins pick,
the response-class table, and an explicit wreck-gate regression (a
WRECKAGE-classified contact must never read a matching warrant — rule 0's
vessel-only gate already covered this for free, pinned with its own test
per the plan's ask).

### Step 4 — compute_standing cutover

Rule 2 (sticky HOSTILE) deleted outright; replaced with an O(1)
`observer.warrant_index` lookup keyed the same way `subject_key` derives
it at post time (claimed transponder name, else a signature fallback).
`warrant_index` is rebuilt once per fusion tick (`_rebuild_warrant_index`,
called at the top of `_physics_process` before the correlate loop) from
`warrants`, filtered to OPEN + unexpired + enforceable-by-this-observer —
so a merely-visible (cross-flag or undeputized-witness) warrant never
escalates standing to HOSTILE; it stays informational, readable off
`warrants` directly. `contact["standing"]` keeps being cached exactly as
before (per the design doc's settled Q3) — only rule 2's input changed.

### Step 5 — datalink relay warrant merge

Merge rule: `Standing.merge_warrant` (latest-timestamp/highest-status-
wins), filtered to `origin_flag != ""` before merging; rebuilds
`warrant_index` only if a merge actually changed something (skips on the
common no-op tick). Covered by three new `test_standing_e2e` scenarios
(G/H/I): flagged warrant relays to a linked peer; revocation propagates
and overrides a peer's stale OPEN copy; a personal-origin and a flagged
warrant posted by the SAME ship in the SAME tick diverge — the personal
one never leaves the issuer, the flagged one does (proves the filter is
per-warrant, not per-link, per the plan's explicit test description).

**Verification-pass fix (calling session, before commit):** the
as-built version of this step ran as a *second* full peer scan — its own
`get_tree().get_nodes_in_group("ships")` loop re-deriving the same four
link gates (range both ways, line-of-sight raycast, IFF overlap) a
second time, in its own `PerfProbe` scope (`warrant_relay`) — rather than
folding into the existing per-peer loop the standing-share block already
runs. That doubles an O(n) scan-with-raycast every physics tick for no
functional reason, in a subsystem CLAUDE.md specifically flags as having
a documented perf-regression history (M45). Folded the warrant merge
into the SAME loop/peer iteration the standing-share block already
performs (right after its line-of-sight check succeeds), reusing one
`space_state.intersect_ray` per peer instead of two; dropped the second
`PerfProbe` scope back into `datalink_relay`'s (matching this plan's own
step-5 wording, "same `PerfProbe` scope," which the as-built version had
drifted from). Purely a hot-path consolidation — no behavior change; all
three new e2e scenarios (G/H/I) and the full build gate were re-run
green after the fold.

### Step 6 — on-request station pull

`PortControl.request_warrant_list(station, ship) -> Dictionary`, same
`(station, ship) -> Dictionary` shared-entry-point shape as
`request_docking`. Merges the station's own `warrants` into the asking
ship's store by the same `merge_warrant` rule, preserving the station's
`origin_flag`. Wired to fire automatically inside `request_docking`'s
granted path (best-effort — a warrant-store issue never blocks docking
itself), so both the dialogue "do" line and the fast-path button get it
for free without separate UI wiring. New `test_warrant_pull.gd` (pure-
function style, no scene tree needed): confirms the merge, the
personal-origin filter applies on pull too, and it's genuinely one-shot
(a warrant added to the station after a pull does NOT appear until a
SECOND explicit pull; a re-pull with nothing new reports 0 merged).
`test_docking_grant_lifecycle` and `test_port_control_comms` re-run green
— the trigger doesn't disturb existing docking behavior.

### Step 7 — response classes + enforcement policy

The production surface this step needed (offense → response class table,
the shared enforcement gate) already existed from steps 1–2. What step 7
actually added: an explicit regression test pinning `response_class()` for
all seven offenses against the design doc's table, so a future tweak can't
silently flip which offenses get MAX's shortened patience. No patrol tree
exists yet to consume `warrant_index`/response class — correctly out of
scope per the plan ("nothing in THIS milestone consumes it yet"; MAX vs
INTERCEPT patience is explicitly deferred to the M52 patrol milestone).

### Step 8 — UI: partial, scoped down deliberately

**Built**: the station-pull trigger (see step 6) — the one piece of step 8
that was concrete, testable, and low-risk.

**Not built**: a targeting-computer warrant-detail view and a WANTED list
at stations. Two reasons. First, grepping the UI layer found no existing
"standing-reason readout" to "replace the guts of" — `contact
["standing_reason"]` currently has zero UI consumers (only `["standing"]`
drives the contacts-panel color, via `Standing.severity`/the cached tier);
the plan's phrasing assumed a display surface that doesn't concretely
exist, so this would be new layout work, not a refactor. Second, this
environment has no way to visually verify Godot Control-node layout (no
screenshot/render loop for the native game window), and no test in this
codebase's suite gates UI layout correctness — shipping new panels blind,
with nothing to catch a broken layout, was judged higher-risk than valuable
here. The plan's own "Order of work" explicitly frames steps 8–9 as
"polish/framing, can slot in wherever convenient once 1–7 are green," so
this is deferred, not silently dropped. Flagging for the calling session:
worth a follow-up pass with someone who can drive the actual editor/game
window.

### Step 9 — militia framing

`warrants`/`warrant_authority` default empty on every `Ship` (plain field
defaults, no campaign-init line needed) — confirmed directly, and the
player is never assigned a `warrant_authority` anywhere in `main.gd`. That
half of the design doc's start-state is true today with zero extra code.

**Open question flagged, not resolved:** the design doc's militia framing
also says home stations/the beacon road "do NOT share IFF or comms with
the militia by default." That's **not actually true today** —
`home_cluster.gd`'s `HOME_IFF := ["TEAM_PLAYER"]` already puts the player
on the SAME iff_tag as every home station and patrol (an M15/16-era
decision, "so hubs read friendly and their station AI never targets the
player," predating and unrelated to warrants). Since the step-5 relay pass
reuses the exact IFF-tag-overlap gate the design doc specifies reusing,
this means the player is structurally "on the network" with home
infrastructure for warrant relay purposes from campaign start — contradicting
the doc's "starts with no warrant feed, earns one via bounty work"
narrative. I did not invent a new gating mechanism to separate "shares IFF
for FRIENDLY-classification purposes" from "shares IFF for warrant-relay
purposes" (the doc doesn't ask for one, and it would be guessing on an
unresolved design question), and did not touch the pre-existing IFF-sharing
architecture (high blast radius, unrelated to this milestone, would risk
regressing "hubs read friendly"). In practice this is a soft gap, not an
active bug: home stations essentially never post warrants — there's no
`NO_ID`/`SPEED_VIOLATION` posting call site yet, `ASSAULT`/`ARMED_THREAT`/
`ARMED_ROBBERY` only post from ships that were directly attacked or robbed,
and a hunted pirate would have to pick a fight within a home station's own
comms+LOS range for this to matter — but it's a real inconsistency between
the shipped campaign framing and the actual start state, worth an explicit
decision (accept as-is / give the player a distinct IFF tag / scope the
relay pass to something narrower than plain IFF overlap) before the M52
patrol milestone leans on it further.

### Test results

Every test file section 4 named, plus the new ones, run individually
green: `test_standing_rules`, `test_standing_e2e` (9 scenarios, up from
6), `test_hail_protocol`, `test_sandbox_hostility`, `test_mine`,
`test_missile_ai`, `test_pirate_ambush`, `test_pirate_abort`,
`test_job_runner`, `test_honored_stop`, `test_docking_grant_lifecycle`,
`test_port_control_comms`, `test_cluster_loader` (new warrant_authority-
defaults case), `test_campaign_bootstrap`, `test_cluster_bubble`,
`test_missile_wreckage_despawn`, `test_classifiers_e2e`,
`test_patrol_challenge`, `test_ai_engage_tree`, `test_ai_duel`,
`test_ai_vs_legacy`, and the new `test_warrant_pull`. No pre-existing
failures were observed anywhere in this pass (none caused, none inherited).

### Build gate

`build.ps1` (background run, `test_logs/build_m52b.log`): full suite —
**92 `[TEST PASSED]` markers, 0 `[TEST FAILED]`, 0 `ASSERT FAILED`** —
followed by a clean Windows export and package
(`ProjectDeepSpace_Windows_v2026-07-20.102437.zip`). The only stderr
content was benign PowerShell-capture Unicode-BOM warnings from piping
Godot's console output, not a test or build failure.

One incidental side effect of running the full gate: `tactical_analysis/
data/perf_baseline*` files show as modified in `git status` — that's
`test_perf_baseline` regenerating its own timing CSV on every run,
unrelated to warrants. Left unstaged along with everything else per this
task's instructions.

### Open items for the calling session

1. **Militia-framing IFF gap** (step 9, above) — needs an explicit decision,
   not a code fix from this pass.
2. **Step 8 UI** — station-pull trigger is live; the visual panels
   (targeting-computer warrant detail, station WANTED list) are not built.
3. `clear_contact_hostile` (UNMARK) no longer clears the private
   `aggro_hits` stray-fire counter the way the old code did — deliberate,
   per the design doc's "confidence gates issuance, not the record"
   (aggro_hits feeds a different offense, `SUSTAINED_ASSAULT`, orthogonal to
   the `OPERATOR_FLAGGED` warrant UNMARK resolves). No test depended on the
   old coupling; noted here in case it surprises anyone.
