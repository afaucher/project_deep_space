# M52 — SOS becomes passively-synced live state, not an event

## Motivation: two bugs, one root cause

This session's SOS redesign (`implementation_plans/m52_sos_as_contact.md`) made SOS
a real `active_contacts` entry, kept alive by a heartbeat while active and
explicitly cleared by a one-shot "off" broadcast when deactivated. Working
through the off-broadcast's actual guarantees surfaced two real gaps:

1. **Relay never propagates the off-state to an already-known entry.** The
   relay merge's "already-has-entry" branch (`ship.gd`'s `datalink_relay`)
   only ever refreshes `pos`/`vel`/`last_seen_timer`/`resolution` (if
   fresher) and `standing` (if more severe) — it never touches
   `sos`/`sos_nature`/`sos_name`/`classification`. A brand-new import copies
   the whole dict, so a FIRST-ever relay hop gets accurate sos state, but
   once a downstream ship already has a local copy (near-certain within a
   few ticks of the original broadcast, given ~2-frame relay propagation),
   later relay ticks carrying an upstream clear never reach it. That ship's
   copy is stuck until it directly hears the sender's own off-hail, which
   requires direct comms range at that exact moment — not just relay
   linkage.
2. **A real correlated detection self-heals `classification` but never
   clears stale `sos` fields.** This self-heal is deliberate and already
   relied on by `sos_response_leaf.gd`'s give-up condition. But nothing in
   the sensor-correlation path touches `sos`/`sos_nature`/`sos_name` — those
   are written ONLY by hail handling. Worse: a live, continuously-detected
   contact never decays (`last_seen_timer` resets to 0 every sweep), so a
   stale `sos: true` picked up via relay before you left range, still
   sitting there when you fly back into SENSOR range, can persist
   INDEFINITELY once your own presence keeps the contact permanently fresh
   — worse than "stale for up to 20s," genuinely stuck.

**Root cause of both: SOS is event/snapshot-based** (a hail verb fired at
discrete on/off/heartbeat moments, its effects written once and left to be
explicitly overwritten later) **while everything else that reliably "just
stays synced" — name, flag, position, velocity via the relay's self-report —
is live, re-read fresh every tick, never snapshotted.** Patching the two bugs
above (make relay merge also carry sos with freshest-wins; make correlation
also clear stale sos fields) would work, but it's patching a model that's
structurally prone to this class of bug. The better fix removes the model.

## The insight

Two mechanisms already solve "stays synced, no possible staleness" for other
per-ship data. Put SOS on both instead of inventing a third, event-based one:

1. **Direct range, any audience (friend or stranger):**
   `Ship.get_active_transponder_data()` is already read FRESH every physics
   frame by `datalink_relay`'s per-candidate loop, deliberately NOT gated by
   IFF or LOS ("omnidirectional radio, no IFF or LoS required" — the
   existing header comment on that step). Name and flag never go stale
   because nobody snapshots them.
2. **One-hop friendly relay:** the same loop's "self-report" block already
   rebuilds a ground-truth entry from the linked neighbor's LIVE
   `position`/`linear_velocity`/`get_signature()` every single tick — never
   a snapshot.
3. **Multi-hop:** the existing freshest-wins merge (already used for
   pos/vel/resolution) propagates whatever's current at each hop, one tick
   of latency per hop, self-correcting continuously as long as it's
   extended to carry the new fields too.

## Design

### Ship-level state (simplified, not just fixed)

- `sos_active: bool`, `sos_nature: String` remain plain live fields — same
  names, same meaning, but now nothing else about them (no timer, no
  broadcast call) needs to exist.
- `set_sos_active(active: bool, nature: String = "")` RPC: now JUST writes
  the two fields. No priming, no broadcast dispatch, no heartbeat timer.
- **Removed:** `sos_heartbeat_timer`, `SOS_HEARTBEAT_INTERVAL`, the periodic
  re-send block in `_physics_process`, `Hail.VERB_SOS`'s wire-delivery path
  for SOS purposes, and the explicit "off broadcast"
  (`send_sos(nature, false)`) — there's no discrete off-event to send
  because there's no discrete off-event model at all anymore. `Hail
  .NATURE_UNDER_ATTACK`/`NATURE_DISABLED` stay; `sos_nature` is still
  meaningful metadata, just carried as live state instead of a wire payload.

### Reconciliation — where create/merge/clear logic moves

Currently lives in the `comms_inbox`/`Hail.VERB_SOS` branch (event-
triggered, runs once per hail received). Moves into `datalink_relay`'s
existing per-candidate-ship loop (continuously re-evaluated, once per
candidate ship per tick, for anyone still in range):

1. **Port the `SOS_BATTERY_RANGE` floor exactly as `hail.gd`'s `_dispatch`
   currently implements it** (read that function before touching this —
   it's the ground truth for the semantics, not this doc's paraphrase):
   - MY OWN receiving range is never floored — `hail.gd`'s own comment is
     explicit: "Receivers still need a working radio of their own to hear
     anything, SOS included — this only relaxes the SENDER's requirement."
     The EXISTING outer `if self_comms_range > 0.0:` gate and the EXISTING
     `if dist > self_comms_range: continue` early-out in `datalink_relay`
     both remain correct, unchanged — `min(self_comms_range, ANYTHING)`
     can never exceed `self_comms_range` regardless of how boosted the
     other side is.
   - The CANDIDATE's (`s`'s) effective range for SOS purposes specifically
     is `max(s.get_comms_range(), SOS_BATTERY_RANGE) if s.sos_active else
     s.get_comms_range()`. This must be checked SEPARATELY from, and
     BEFORE, the existing `if their_comms_range <= 0.0: continue` early-out
     — that early-out is correct for ordinary transponder/relay purposes
     (both radios must work) but would incorrectly skip a dead-comms,
     actively-broadcasting-SOS ship, exactly the case the floor exists for.
2. **Not IFF-gated**, matching `hail.gd`'s `_dispatch` (loops every "ships"
   member, no IFF filter at all) — sits alongside the transponder read
   (also IFF-independent), before the `_iff_tags_overlap` check that gates
   the friendly-only relay/warrant logic below it.
3. Per candidate `s` within the SOS-specific effective range: reconcile
   `active_contacts[sender_trk]` this tick —
   - `s.sos_active == true`: create-if-absent (synthetic `"DISTRESS CALL"`
     entry, same shape as today's create branch), or merge-onto-existing
     (stamp `sos`/`sos_nature`/`sos_name` only — same non-clobber rule as
     today: never touch `pos`/`vel`/`classification`/`signature` on a real
     contact). `last_seen_timer` resets to 0 every tick the sender is
     actively broadcasting and in range — strictly tighter than the old
     ~6.67s heartbeat gap, since there's no periodic-resend latency at all
     now.
   - `s.sos_active == false` (or `s` has moved out of even the floored
     range): if the local entry is purely synthetic (`classification ==
     "DISTRESS CALL"`), erase it. If it's a real contact with `sos: true`
     stamped, clear just `sos`/`sos_nature`/`sos_name` back to
     false/empty. Every tick, not just at an explicit off moment — this is
     what makes the flying-back-in-range bug impossible: reconciliation
     re-derives from current truth regardless of what sensor correlation
     independently did to `classification` in the same tick.

### Self-report + relay (multi-hop, friendly-linked)

- Add `sos`/`sos_nature` to the self-report dict already rebuilt fresh every
  tick for direct friendly neighbors: `"sos": s.sos_active, "sos_nature":
  s.sos_nature if s.sos_active else ""`.
- Extend the relay merge's existing "already-has-entry" branch — currently
  `if relayed_age < c.get("last_seen_timer", 0.0): c["pos"] = ...; c["vel"]
  = ...` — to also carry `sos`/`sos_nature` inside that SAME freshest-wins
  gate. This is the one actual behavioral change to the relay's own merge
  logic; everything else in this doc is fields added to already-rebuilt-
  every-tick data, or logic moved rather than newly invented. This directly
  closes bug #1 above: a fresher relay tick now carries sos state onward
  the same way it already carries pos/vel, at every hop, indefinitely.

### Notification / hails-log UX (preserve what the event model gave for free)

Passive sync loses the natural "this was a discrete moment" a hail event
provided — worth preserving deliberately, not silently dropping. Computed
LOCALLY, no wire message needed: each ship remembers, per source track,
whether it counted that source as "in active distress" as of LAST tick's
reconciliation. On a rising edge (false → true this tick), append one entry
to `last_hails` ("heard X's distress call"), same as a first-receipt hail
does today. Falling edges need no log entry — silence isn't a notable event
the way a new alarm is.

## What's explicitly preserved (regression-proofing this redesign)

- The `SOS_BATTERY_RANGE` floor (a fully dead-comms sender still reaches
  30000 units) — ported precisely from `hail.gd`'s current logic, not
  dropped or approximated.
- Never overwrite a real contact's `pos`/`vel`/`classification`/`signature`
  from sos reconciliation — same non-clobber rule as the current design.
- Multi-hop relay propagation stays one-tick-of-latency-per-hop —
  `test_sos_relay_bridge.gd`'s own proof (2-frame propagation across a
  3-hop chain, measured this session) should still hold, and arguably gets
  MORE robust, not less: it's now literally the same mechanism ordinary
  contact freshness already uses, no separate hail-relay code path to
  reason about independently.
- `sos_response_leaf.gd`'s `classification == "DISTRESS CALL"` targeting
  and give-up logic — untouched; it only reads `active_contacts`, and this
  redesign changes HOW that field gets maintained, not its shape or the
  leaf's contract with it.
- UI (`contacts_panel.gd`/`weapons_panel.gd` SOS badges) — untouched, same
  `sos`/`sos_nature`/`sos_name` fields in the same place.

## Net effect

Fixes both bugs found this session **by construction**, not by patching:
there's no discrete off-event to fail to deliver, and no stale-flag-after-
correlation, because reconciliation re-derives the correct sos state from
current live truth every single tick regardless of what any other subsystem
did in that same tick. It is also simpler than what it replaces — fewer
moving parts (no timer, no heartbeat-interval tuning, no separate on/off
wire messages, no `Hail.VERB_SOS` receive branch).

## Tests to rewrite

Every SOS test currently asserts heartbeat-timer-priming behavior
(`sos_heartbeat_timer == SOS_HEARTBEAT_INTERVAL`, etc.) that no longer
exists after this change — needs equivalent assertions on the new
reconciliation OUTCOME instead (same behavior under test, different
mechanism): `test_sos_contact_attribute.gd`, `test_sos_prefers_live_contact
.gd`, `test_sos_relay_bridge.gd`, `test_hail_protocol.gd` Scenario H,
`test_patrol_interdiction.gd` Phase 6, `test_demand_lifecycle.gd`'s S4 (its
"no re-trigger" check specifically reads `sos_heartbeat_timer`, which is
gone — needs a different observable), `test_threat_response.gd`'s SOS
broadcast-once check, `test_contacts_panel_sos.gd`. Grep the whole repo for
`sos_heartbeat_timer`/`SOS_HEARTBEAT_INTERVAL`/`VERB_SOS` (SOS-specific
uses) to find anything this list missed.

**Key new test**: the battery-floor + dead-comms + passive-sync case
together — a sender with comms FULLY DESTROYED, `sos_active = true`, within
`SOS_BATTERY_RANGE` but beyond any real comms range: receiver picks up sos
state despite zero comms power on the sender (floor survived the redesign).
Paired with a "kill it mid-broadcast" sub-case — sender's `sos_active`
flips false, or the sender itself dies — receiver's contact reconciles
(clears or erases) within 1-2 ticks, no dependency on ever having directly
heard an explicit off-message, and no scenario where flying back into
sensor range afterward could re-stick a stale badge.

## Findings (executed)

Implemented as designed, with one gap the doc didn't anticipate (dead senders,
below) and two test-rewrite assumptions that turned out wrong on the first
attempt — both caught by actually running the tests, not by re-reading the
plan harder. Full suite: 107/107 passed (`test_asteroid.gd` excluded, same as
`build.ps1`'s own exclusion), zero regressions outside the SOS-specific files.

### Reading `hail.gd`'s `_dispatch` (ground truth, lines 95-137)

Confirmed exactly what the doc's paraphrase said, no surprises: `is_sos` gates
a single `sender_range = max(sender_range, SOS_BATTERY_RANGE)` floor applied
ONLY to the sender's side before the receive loop; the receive loop's own
`their_range <= 0.0: continue` (i.e. MY side, from a receiver's perspective)
is never floored, comment-for-comment matching "receivers always need a
working radio, SOS included." This ported directly into
`datalink_relay`'s per-candidate loop as `sos_effective_range = max(
their_comms_range, Hail.SOS_BATTERY_RANGE) if s.sos_active else
their_comms_range`, gated by the existing `self_comms_range` (never floored)
on my own side. No deviation from the doc here.

### Mechanism changes (`scripts/ships/ship.gd`)

- **Removed**: `SOS_HEARTBEAT_INTERVAL` const, `sos_heartbeat_timer` var, the
  periodic re-send block in `_physics_process`, the `Hail.VERB_SOS` branch in
  the `comms_inbox` match statement, `send_sos()` (the RPC that built and
  dispatched the wire hail), and `_nearest_fresh_hostile_pos()` (only ever
  called from `send_sos()`'s UNDER_ATTACK "threat" field, which nothing
  downstream actually read — dead the moment `send_sos()` goes).
  `Hail.VERB_SOS`/`NATURE_UNDER_ATTACK`/`NATURE_DISABLED` stay in `hail.gd`,
  untouched, exactly as the doc said (`hail.gd` was read-only ground truth for
  this milestone, never a target for edits).
- **`set_sos_active`** is now two lines: `sos_active = active; sos_nature =
  nature`. No priming, no dispatch.
- **New `_reconcile_sos_contact(s, sos_in_range)`**, called once per candidate
  from `datalink_relay`'s existing loop, positioned per the doc: the
  SOS-specific range check happens right after `their_comms_range =
  s.get_comms_range()` is read but BEFORE the `their_comms_range <= 0.0:
  continue` early-out, not gated by IFF, sitting just above the transponder
  read. Create/merge-non-clobber/erase/clear-fields-only logic matches the old
  `VERB_SOS` branch's shape exactly (same dict literal for a new entry, same
  three-field-only clear for a real contact).
- **Self-report dict** (the one-hop "ground truth" entry a friendly link
  synthesizes for itself) gained `"sos": s.sos_active, "sos_nature":
  s.sos_nature if s.sos_active else ""`.
- **The relay's freshest-wins "already-has-entry" merge** gained `c["sos"] =
  external_contact.get("sos", false); c["sos_nature"] =
  external_contact.get("sos_nature", "")` inside the same `relayed_age <
  c.get("last_seen_timer", 0.0)` gate pos/vel already use — this is the one
  line-for-line change to the relay's own merge logic the doc called out.
  `sos_name` was deliberately left OUT of this extension, matching the doc's
  literal scope ("sos/sos_nature" only) — a brand-new import still carries
  `sos_name` for free (it's `external_contact.duplicate(true)`, the whole
  dict), so the only place this is even observable is a claimed-name change
  arriving mid-relay-chain on an ALREADY-known downstream entry, which stays
  sticky at whatever name it first saw. Pre-existing behavior, not a
  regression — the old design's relay merge didn't touch `sos_name` either
  (it didn't touch `sos` anything, that was bug #1).
- **Rising-edge notification**: implemented WITHOUT the extra per-track "was
  this counted as active last tick" dictionary the doc describes — the
  `active_contacts` entry's own `sos` field, read BEFORE this call's write,
  already serves as that memory (`was_active := active_contacts.get(trk,
  {}).get("sos", false)`), so a separate structure would just be duplicating
  data already sitting there. Deliberate simplification, see the caveat
  below.

### A gap the doc didn't cover: dead senders

The doc's own new-test spec says "the sender's `sos_active` flipping false
**(or dying)**" should clear the receiver's contact within 1-2 ticks. The
existing `datalink_relay` loop's very first line is `if s == self or
s.is_dead: continue` — a dead candidate never reaches ANY of the per-candidate
logic, including the new SOS check. Left as originally placed, a sender that
dies mid-broadcast (`hulk()` sets `is_dead = true` but never itself touches
`sos_active`) would leave its last-known `sos: true` entry un-reconciled
forever, decaying only on the ordinary ~20s `CONTACT_TIMEOUT` clock — not the
"1-2 ticks" the doc's own test spec promises, and a real (if narrower) echo of
the exact bug this milestone exists to close. Caught this by writing the
"kill it mid-broadcast" test from the doc's own spec and reasoning through
what `is_dead` actually does before assuming it clears itself.

Fix: moved the `dist > self_comms_range` check before the dead check, then
special-cased a dead candidate to call `_reconcile_sos_contact(s, false)`
(forcing the clear/erase branch) before its own `continue` — still gated by
`self_comms_range` like everything else (a wreck out of range decays
normally, no different from anything else going quiet), but a dead wreck
still in range gets its stale SOS badge cleared same-tick instead of orphaned.
Covered by `test_sos_passive_reconciliation.gd`'s
`_test_battery_floor_then_death_clears_within_ticks`.

### Verifying "what's explicitly preserved" — actually checked, not assumed

- **`SOS_BATTERY_RANGE` floor**: `test_sos_contact_attribute.gd`'s existing
  `_test_sos_reaches_battery_range_with_dead_comms` plus
  `test_sos_passive_reconciliation.gd`'s two battery-floor sub-tests all pass
  — a fully dead-comms sender still reaches a receiver at
  `SOS_BATTERY_RANGE - 2000`.
- **Non-clobber rule** (never touch `pos`/`vel`/`classification`/`signature`
  from SOS reconciliation): `test_sos_prefers_live_contact.gd` (both
  sub-tests), `test_sos_contact_attribute.gd`'s stamped-onto-existing test,
  and `test_sos_passive_reconciliation.gd`'s fly-back-into-range test (which
  specifically re-checks `classification` survived an off-and-back-on cycle
  unchanged) all pass.
- **Multi-hop, one-tick-of-latency-per-hop**: `test_sos_relay_bridge.gd`
  passes unmodified in its actual assertions (only comments touched — it
  already used `set_sos_active` exclusively, never `send_sos`, so nothing
  about it depended on the removed mechanism). Measured hop timing this run:
  `Beacon1=2, Beacon2=2, Patrol=2` (physics frames since activation) — all
  three hops landing in the SAME tick, not sequentially staggered. This is
  NOT a violation of the one-tick-per-hop ceiling: each hop still requires its
  own `age + delta` pass through the freshest-wins gate (unchanged code), it's
  just that Godot processes ships in scene-tree order within a single
  `_physics_process` sweep, so a chain added Sender→Beacon1→Beacon2→Patrol can
  cascade a fresh import through all three hops inside one frame purely from
  processing order — a pre-existing property of the relay (same as it always
  was for pos/vel), not something this milestone changed. The doc predicted
  "arguably gets MORE robust, not less" — this is consistent with that, if
  faster than the plan's own language implied.
- **`sos_response_leaf.gd`'s contract**: file untouched except a stale
  comment reference; the leaf only reads `active_contacts`, and this
  redesign changes how that field is maintained, not its shape.
  `test_sos_relay_bridge.gd`'s leaf-tick assertion and all of
  `test_patrol_interdiction.gd`'s Phase 6 (adopt/stale/later-different-SOS)
  pass.
- **UI badge fields**: `contacts_panel.gd`/`weapons_panel.gd` untouched
  except comments; `test_contacts_panel_sos.gd` needed ZERO code changes
  (pure fixture-driven, no ship.gd/hail.gd dependency at all) and still
  passes.

### Test rewrites — what actually changed, and two wrong first guesses

- `test_sos_contact_attribute.gd` / `test_sos_prefers_live_contact.gd`: the
  only real change was swapping direct `sender.send_sos(nature)` calls (no
  longer exists) for `sender.set_sos_active(true, nature)`; the off-path
  sub-tests already used `set_sos_active` and needed no logic changes, just
  comment updates (no more "off broadcast" to describe).
- `test_hail_protocol.gd` Scenario H: Phase 2 used to force `last_seen_timer`
  to 9999 and wait for the ordinary `CONTACT_TIMEOUT` prune. Under passive
  sync that's pointless — at 2000u range the listener is continuously
  SOS-reconciled every tick while the caller keeps broadcasting, so any
  forced staleness gets reset back to 0 on the very next tick regardless.
  Rewrote to call `set_sos_active(false, "")` and confirm the entry is erased
  within a handful of ticks instead — a materially FASTER and more direct
  proof than the thing it replaced.
- `test_patrol_interdiction.gd` Phase 6: removed the manual
  `last_seen_timer = 9999.0` staleness hack for the same reason — reconciled
  erasure now happens on `sos_active` going false regardless of what any
  timer says.
- `test_demand_lifecycle.gd` S4 and `test_threat_response.gd`'s
  broadcast-once test both used to assert `sos_heartbeat_timer ==/!=
  SOS_HEARTBEAT_INTERVAL` as a race-free proxy for "did the decision body
  run again." Since `set_sos_active(true, nature)` is now an idempotent field
  write, re-calling it with the same arguments is genuinely unobservable —
  there is no substitute timer artifact. For each test I worked out what the
  SECOND `leaf.tick()` call actually does by tracing `threat_response_leaf.gd`
  rather than assuming:
  - **`test_threat_response.gd`**: first guess was "the second tick re-enters
    the demand-decision code and hits the `last_decided_seq` gate, returning
    FAILURE." Wrong, and the test run caught it immediately — this scenario's
    victim COMPLIES (`will_run == false`), and complying calls
    `engage_dead_stop()` SYNCHRONOUSLY within the first tick, which sets
    `compelled_stop` and clears `pending_demand` right there. The second tick
    therefore short-circuits at the leaf's very TOP branch (`if not
    actor.compelled_stop.is_empty(): ... return SUCCESS`), never reaching the
    demand-decision code — let alone the seq gate — at all. Fixed the
    assertion to expect `SUCCESS` plus `bb.get_value("was_held")`, which
    directly proves the held branch fired instead of a fresh decision.
  - **`test_demand_lifecycle.gd` S4**: re-traced the same way and found the
    OPPOSITE outcome for that scenario (`will_run == true`, since the pirate
    sits stationary at demand time so `threat_capability` reads ~0) — the
    second tick takes the "active RUN incident" branch via
    `blackboard.has_value("threat_issuer_iid")`, which ALSO never reaches the
    demand-decision code. On reflection, the original `sos_heartbeat_timer`
    check in THIS test was never actually proving the `last_decided_seq` gate
    specifically either — it was incidentally true because the RUN branch
    structurally never touches SOS, regardless of any gate. Simplified to
    asserting `sos_active`/`sos_nature` stay unchanged across the refresh,
    and left the real "no re-alert/no re-decision" proof to the pre-existing
    `hail_events`/`last_hails`/`last_decided_seq` assertions in that test,
    which are unrelated to SOS and untouched by this migration.
- `test_contacts_panel_sos.gd`: doc listed it defensively; turned out to need
  no changes at all (hand-built fixture dicts, no ship.gd/hail.gd machinery in
  the loop).
- New: `test_sos_passive_reconciliation.gd` — the doc's "key new test," four
  sub-tests: battery-floor-then-`set_sos_active(false)`-clears,
  battery-floor-then-`hulk()`-clears (the dead-sender fix above), the
  fly-back-into-range repro of bug #2 (teleport pattern borrowed from
  `test_relay_contact_aging.gd`'s `body_set_state` + `sleeping = false`
  wake-safe idiom, since a settled/sleeping RigidBody2D's collision geometry
  doesn't follow a plain `.position =` write — CLAUDE.md's documented
  gotcha), and the rising-edge `last_hails` notification (one entry on
  false→true, no spam while staying true, silent on the falling edge, a
  fresh entry on a later distinct incident).

### Honest notes

- The rising-edge notification's "read the entry's own prior `sos` value"
  approach has one theoretical same-tick race the doc's literal
  "remembers... as of last tick" design doesn't: if a DIFFERENT friendly
  candidate's relay merge (processed earlier in the SAME tick's ship
  iteration) already wrote `sos: true` onto this exact track before the
  direct sender itself gets processed later in that same tick's loop, the
  direct-reconciliation call would read `was_active == true` and skip
  logging — a missed (not spurious) notification, purely cosmetic, that
  depends on scene-tree iteration order coinciding with a multi-hop AND
  direct link existing simultaneously on the very first tick of a new
  incident. Did not chase a fix for this; it doesn't affect `active_contacts`
  correctness, only a possible missed console line in a narrow, unlikely
  ordering case.
- `build.ps1` itself was not run to completion — it also does a full
  `--export-release` + zip packaging pass, and this machine has no Windows
  export templates installed (`build.ps1` would have tried downloading a
  large `.tpz` from GitHub first). Ran `build.ps1`'s own test section
  directly instead (same parallel `test_runner.ps1` invocation over every
  `scripts/tests/*.gd` file except `test_asteroid.gd`, same exclusion
  `build.ps1` uses) — 107/107 passed. `build.ps1`'s syntax-validation step
  (`--check-only`) was skipped deliberately per CLAUDE.md's own warning that
  it false-positives on autoload identifiers; the full test run is the
  authoritative check regardless, and every test that loads `ship.gd` (all
  107, transitively) is a stronger validation than a parse-only pass.
