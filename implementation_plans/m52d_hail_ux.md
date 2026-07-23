# M52d — Hail lifecycle + comms panel restructure

Sub-milestone from the 2026-07-20 pirate playtest (design_ideas/
2026-07-20-pirate_playtest.md). The M49 hail protocol works on the wire;
the playtest showed the PLAYER-FACING half is missing: no alert when
hailed, unclear compliance affordance, demands that never expire, and a
hails panel with no legible structure.

## 1. Demand lifecycle (data bug first — the rest is UI on top of it)

Playtest: "The first demand never went away, it was still there when the
second pirate got me."

Confirmed in ship.gd: `pending_demand` is set on receipt and cleared ONLY
by acknowledging or being overwritten by a newer demand. Nothing clears
it when the issuer dies, leaves, or loses interest.

Design (revised in review — the RELEASE-on-abort contract is dropped):
**a demand is a channel the issuer keeps asserting, not a datagram plus a
release contract.** The sender re-sends while it cares; the receiver
times the demand out when the channel goes quiet. This is the playtest's
"hails persisted by the issuing ship" model built directly, and it's the
same decay idiom everything else here uses (contacts' last_seen_timer,
compelled_stop's lost_issuer_timer, heard_sos TTL) — state maintained by
continuous observation, never cleared by an edge event someone can
forget to send.

- **Sender:** DEMAND_STOP re-sends the demand on a cadence (~2s) with the
  SAME seq while the step is active — a refresh, not a new demand. The
  victim's last_decided_seq dedup means a refresh never re-triggers the
  comply-or-run decision or a fresh SOS; the M52d hail alert must
  likewise fire on first receipt only, not on refreshes.
- **Receiver:** pending_demand tracks time-since-last-heard; a matching
  refresh (same sender + seq) resets it; past ~6s (a few missed beats)
  the demand clears. ONE mechanism covers issuer death, out-of-comms,
  job abort, and lost interest — no per-cause cleanup code, no abort
  path that can silently miss its release call.
- **The RELEASE verb is REMOVED entirely** (user decision, final form of
  this design). "Release" was only ever "stop the demand" — under the
  channel model that's expressed by stopping the heartbeat, so the verb
  is redundant. This closes a gap the verb was papering over: the HOLD
  (compelled_stop) had the same staleness bug the demand did —
  lost_issuer_timer only fires on a dead/out-of-range issuer, so a
  present-but-silent pirate held you forever. Presence was the wrong
  signal; channel-liveness is the right one, for both states:
  - The heartbeat runs through the WHOLE encounter: DEMAND_STOP and
    TAKE_ALONGSIDE both refresh (the pirate still wants the hold while
    robbing).
  - Receiver routing by seq: refresh matching compelled_stop.demand_seq
    → reset the hold's freshness; matching pending_demand.seq → reset
    the pending demand's; a NEW seq → new demand, re-alert.
  - Channel quiet past the window → pending_demand AND compelled_stop
    both lapse. lost_issuer_timer's presence check is subsumed and
    removed.
  - VERB_RELEASE, send_release, and all handling/send sites deleted.
    Bystanders un-flagging a released ship's complied_stop (the one job
    overheard-RELEASE did) is already covered behaviorally; the future
    patrol-releases-a-suspect flow is warrant resolution + stop
    demanding, not a comms verb (M52's scope).
- The latency trade is the fiction working FOR us: a robber doesn't hand
  you a receipt — you sit tight a few seconds after they leave, until
  you're sure it's over.

## 2. Incoming-hail alert

A DEMAND addressed to you gets a sound and/or visual alert (playtest ask;
today it lands silently in a list you may not be looking at). The
transient_events plumbing terminal_display already consumes for banners
is the delivery path — a DEMAND(STOP) at minimum flashes the hails panel
header and pings once. (Godot audio exists in-project; keep the cue short
and distinct. Visual alone is acceptable v1 if no asset fits.)

## 3. ACKNOWLEDGE affordance (verb renamed from COMPLY — user decision)

Playtest: "The comply button appeared but it wasn't clear what it actually
did. Do I stop? Do I press the button? Is the button just for fun?"

**Rename: COMPLY → ACKNOWLEDGE.** The declaration verb means "I heard
you" — acknowledgment of receipt — which is what pressing the button
actually does and what the verb should mean for ANY hail rung, not just
STOP. Compliance itself stays BEHAVIORAL (the M49 mechanical truth): you
have to genuinely stop, and a declared-then-moving ship still reads as
bolted. The rename makes the split honest — the button says "message
received," your velocity says whether you're complying.

Scope of the rename:
- `Hail.VERB_COMPLY` → `VERB_ACKNOWLEDGE` (wire verb + the broadcast
  string), `comply_with_stop()` → `acknowledge_stop()`, UI button text
  ACKNOWLEDGE. Tests asserting on the old names update in the same pass.
- The behavioral contact field `complied_stop` KEEPS its name: it tracks
  actual compliance (declared AND holding station — the honor rule and
  take_alongside read it as "is behaviorally complying"), which is
  exactly what it says. Acknowledgment is the declaration; compliance is
  the observed state; the two names now describe two genuinely different
  things instead of one name straddling both.

Presentation on top of the rename:
- Button label/tooltip states the contract: "ACKNOWLEDGE — confirm
  receipt and hold station. Moving again voids compliance."
- Pressing ACKNOWLEDGE engages a dead stop automatically (one press =
  declare + actually stop). M52c owns the full DEAD STOP autopilot mode;
  landing M52d first means: wire to the existing M37 autopilot's stop
  capability if one is trivially available, else declare-only with the
  seam left marked for M52c.
- While compelled_stop is active, the panel shows the held state
  explicitly ("HELD — acknowledged <ship>'s stop") instead of leaving the
  player to infer it.

## 4. Hails panel restructure — sort by VESSEL, not by message

Playtest observation: the panel mixes a selected-vessel readout, outgoing
demand buttons, and inbound demand lines with no shared structure. The
insight worth keeping verbatim: "they are actually all just vessels with
different reasons to be in the list."

New structure — ONE list of vessel entries, a vessel appearing if ANY of:
  - it's the currently selected contact,
  - we have sent it a hail (so it can be tracked/cancelled),
  - it has hailed us.

Per entry:
  - **Header: track/ship name + flag** (e.g. `TRK-042 "Rust Bucket" —
    JOLLY_ROGER`). Omit `[TO YOU]` — being in the list under that vessel
    already says so.
  - Under it, that vessel's hail traffic (theirs to us, ours to them) and
    the applicable ACTIONS as consistent buttons — same style, same
    casing (today: "DEMAND ID" / "DEMAND STOP" / "Request Docking" mix
    caps and prose and don't read as buttons). A pirate's DEMAND(STOP)
    entry can sit right above your own DEMAND STOP button aimed back at
    it — symmetrical, legible.

Shape: `[vessel -> [hails to/from], ...]` (the playtest's own notation).
comms_panel.gd already receives selected contact id and last_hails; the
restructure is a rebuild of its list-building, not new data plumbing —
plus one addition: locally remember hails WE sent (sender side currently
fires and forgets) so the "vessels we hailed" bucket exists.

## Findings (as-built)

Implemented by a subagent (two runs — the first hit the session's monthly
spend limit mid-way through item 4's widget test and was resumed on a
different model; the second hit it again during its own post-build
regression pass). The calling session took over verification directly
from there: full diff review against this doc's final (heartbeat, no
RELEASE, ACKNOWLEDGE) design, every touched/added test file re-run
individually, then the full `build.ps1` gate.

**All four items built as designed, no deviations from the final spec**:
- Item 1: `Ship.HAIL_HEARTBEAT_TIMEOUT` (6s) replaces `lost_issuer_timer`
  for BOTH `pending_demand` and `compelled_stop`. `Hail.send()` gained a
  `seq_override` param so a refresh re-asserts under the ORIGINAL seq;
  `DEMAND_STOP` refreshes every ~2s while active, `TAKE_ALONGSIDE`
  refreshes the whole time it holds a victim (stashing the seq on the JOB
  dict, not step-scratch, so it survives the step transition).
  `VERB_RELEASE`/`send_release` are fully deleted (grep-gate confirmed:
  zero references anywhere in scripts/).
- Item 2: incoming-hail alert wired through the existing transient_events
  banner path, plus a one-shot duplicated-and-loop-disabled copy of the
  alarm sample (no new audio asset) and a HAILS-header flash tween.
- Item 3: `VERB_COMPLY`→`VERB_ACKNOWLEDGE`, `comply_with_stop()`→
  `acknowledge_stop()` (grep-gate confirmed clean). `complied_stop` field
  name intentionally kept. One-press declare+brake needed no new
  autopilot: `compelled_stop`'s existing ship-level throttle override
  already forces zero target-velocity every tick it's set (pre-existing
  code, unrelated to M52d) — `acknowledge_stop()` setting it was already
  sufficient, confirmed by reading that block directly.
- Item 4: `CommsPanel.build_vessel_entries()` is a pure function (packet
  data → display dicts) driving the vessel-grouped list; `sent_hails`
  ring buffer added for the sender-side "vessels we hailed" bucket. New
  `test_comms_panel_hails.gd` drives the real Control headlessly (same
  pattern as `test_weapons_panel_standing.gd`), covering qualification
  rules, header format, button routing, and the ACKNOWLEDGE/HELD banner
  states. `PortControl.button_text()` also picked up the caps-consistency
  fix ("REQUEST DOCKING"/"UNDOCK") per the playtest's explicit ask.

**Verification-pass fix (calling session):** one stale doc comment in
`test_hail_protocol.gd`'s header still listed "RELEASE" as covered
elsewhere after the verb was removed — corrected.

**Pre-existing bug found, NOT caused by M52d, NOT fixed here.**
`test_pirate_ambush` fails at Phase 4/5: the job never reaches
RELIGHT/EXIT_AT (stuck at `current=8`, the `AWAIT{track_quiet}` step) within
either the test's 60s outer window or the step's own 60s internal timeout.
Confirmed via `git stash` that this reproduces IDENTICALLY (same failure
lines, same stuck step) on the exact pre-M52d commit — this is not a
regression from anything in this milestone, and physics-jitter flakiness
was ruled out by getting the same result three times running (twice on
the M52d branch, once stashed back to clean HEAD). Likely root cause
(not confirmed, not investigated further — out of scope for M52d):
`_track_quiet_holds()` (job_steps.gd) requires the pirate itself to hold
NO fresh contact within `clear_range=5000` while dark; the test's
`exfil_pos` is only ~9000 units from the victim's spawn point along the
same lane axis, and a cargo shuttle's own post-robbery movement plausibly
closes that gap well inside 5000 before the pirate's sensors lose it —
a geometry/behavior issue in the M50-era test fixture (or the AWAIT
condition itself), unrelated to demand/hold lifecycle. Flagged as a
separate follow-up (spawned as its own task) rather than fixed here,
since it touches a different subsystem (exfil/relight geometry, not
comms) and warrants its own investigation.

**Test results:** every M52d-touched/added test file passes individually
— `test_demand_lifecycle` (new, 5 scenarios, 30 assertions),
`test_comms_panel_hails` (new), `test_hail_protocol`, `test_honored_stop`,
`test_port_control_comms`. Full `build.ps1` gate: **94 `[TEST PASSED]`,
1 `[TEST FAILED]` (`test_pirate_ambush`, pre-existing per above)** — gate
aborted before the export/package step per its own "stop on first
failure" design; re-running it will show the identical single failure
until that bug is separately fixed, independent of M52d's own
correctness.

## Tests

- Demand heartbeat/expiry: refreshes stop (kill the pirate / move it out
  of comms range / let its job abort — all three through the ONE timeout
  path) → pending_demand clears within the window; while refreshes keep
  arriving it never expires; a refresh does NOT re-trigger the
  comply-or-run decision, a fresh SOS, or the hail alert; a genuinely
  new demand (new seq) still overwrites and re-alerts.
- Hold lapse on quiet channel: an acknowledged/held victim whose robber
  finishes and departs (or dies, or goes silent while still present) is
  freed within the timeout window; while TAKE_ALONGSIDE keeps
  refreshing, the hold never lapses mid-robbery. No live reference to
  VERB_RELEASE/send_release remains (grep gate).
- ACKNOWLEDGE one-press: acknowledge_stop declares + brakes together;
  compelled_stop shows held state; moving voids it (existing behavioral
  check still passes). Rename regression: no live reference to
  VERB_COMPLY/comply_with_stop remains (grep gate), and the honor rule
  still holds fire on an acknowledged-and-holding ship.
- Panel structure is data-driven enough to test headless: given
  (selected, sent-hails, received-hails) fixtures, the entry list groups
  by vessel with the right actions enabled (same widget-level pattern as
  test_weapons_panel_standing.gd / test_controls_menu_ui.gd).
