# M52 follow-up — SOS becomes a real (relayable) contact

Design settled through conversation (calling session, 2026-07-23), after the
initial SOS work (battery-backup range, `sos`/`sos_nature`/`sos_name` as an
attribute on an *existing* contact, `heard_sos` as a separate NAV-layer
channel, `SOSResponseLeaf`, the nav-map pulsing-cross marker — all already
shipped). The user's insight: drop the "never manufacture a synthetic
contact" rule specifically for SOS, and design the SOS report to be a
legitimate, if low-information, contact — at which point the *existing*
datalink relay (which already relays `active_contacts` between linked ships)
carries it automatically, with no new relay code needed at all. This doc is
the follow-up build order; the earlier work stays in place except where noted
as replaced.

## Why dropping the rule is safe here (and wasn't in general)

The earlier objection (see the conversation, or `contract_feed.gd`'s M41
header) was about *fabricating a detection with no real basis* — a fake
entry with placeholder signature data that could (a) decay on the wrong
clock and (b) get corrupted by mis-correlating a later real detection into
it. Neither risk actually applies once the entry is built correctly:

- **Decay**: reuse `last_seen_timer`/`CONTACT_TIMEOUT` (the same clock every
  other contact already uses) instead of the separate `HEARD_SOS_TTL`. This
  requires the SOS to be a *repeating* signal (a heartbeat, refreshed by the
  sender for as long as the emergency continues), not a one-shot ping — same
  "a channel the issuer keeps asserting" model M52d already built for
  demands. A one-shot SOS naturally ages out and vanishes after
  `CONTACT_TIMEOUT` (20s) if never repeated, same as a real contact nobody's
  re-detected.
- **Correlation**: `ship.gd`'s correlate-tracks loop (~line 2555) does a
  **direct keyed lookup** (not proximity-fuzzy-matching) whenever the
  incoming detection already knows its own `instance_id` — which is exactly
  the case for a later real detection of the SAME ship the SOS contact
  represents (both key off `"TRK-%03d" % (abs(iid) % 1000)`). A later real
  detection lands on the SAME entry and correctly overwrites the placeholder
  signature/classification — no misattribution risk. The proximity-fuzzy
  path (the actual risk the M41 rule guards against) only fires for
  detections with UNKNOWN identity, which is irrelevant here.
- **Position accuracy**: `Ship.send_sos()` already snapshots the sender's
  REAL position at send time (`"pos": position`) — not fabricated. Combined
  with the heartbeat (fresh snapshot every refresh) and the SOS-prefers-
  live-contact fix already shipped (`sos_response_leaf.gd`), this is
  accurate enough to treat as a legitimate, if coarse, contact.

## Classification: "DISTRESS CALL"

`Ship.classify_contact()` derives its string purely from signature
(em/cs/density) — running an EMPTY signature through it would misclassify
(likely WRECKAGE or UNKNOWN ANOMALY, both wrong and confusing). A freshly
created SOS-only contact must instead get its classification assigned
directly: the literal string `"DISTRESS CALL"` (matches this codebase's
existing convention of bare string-literal classifications — `"WRECKAGE"`,
`"ASTEROID"`, etc. — not a shared const).

This classification is **deliberately excluded** from
`Standing._VESSEL_CLASSIFICATIONS` / `JobSteps._VESSEL_CLASSIFICATIONS`
(both already list only `["FRIENDLY VESSEL", "UNIDENTIFIED VESSEL"]`) — no
changes needed there, it just falls out of the existing allow-lists. This
means, for free:
- No standing gets computed for a pure distress-report contact (you don't
  have a faction judgment on a mayday call alone — same as wreckage/
  asteroids already have no standing).
- `AcquireTargetLeaf` never targets it (gates on `standing == HOSTILE`,
  which a classification with no standing can never satisfy).
- `SELECT_VICTIM` never picks it as prey (same `_VESSEL_CLASSIFICATIONS`
  gate, `job_steps.gd:635`).

Once/if a REAL detection later correlates onto the same key, the existing
correlate-update code (`c["classification"] = Ship.classify_contact(...)`,
runs on every correlate) naturally overwrites `"DISTRESS CALL"` with the
real classification derived from real signature data — the placeholder
self-heals the moment real sensor data exists, no special-casing needed.

## Build order

### 1. `Ship`: SOS becomes a heartbeat + creates/merges a real contact

- New ship-level state: `var sos_active: bool = false`, `var sos_nature:
  String = ""`, `var sos_heartbeat_timer: float = 0.0`.
- New RPC `set_sos_active(active: bool, nature: String)` (same `@rpc("any_peer",
  "call_local")` shape as `set_transponder_flag`/etc.) sets the state.
- In `_physics_process` (wherever the other periodic per-tick ship state
  updates live): while `sos_active`, accumulate `sos_heartbeat_timer` and
  call the existing `send_sos(sos_nature)` every ~6-7s (`CONTACT_TIMEOUT /
  3`, matching the established "refresh at timeout/3, ~3 missed beats of
  slack" ratio the demand heartbeat already uses — `HAIL_HEARTBEAT_TIMEOUT
  = 6.0` vs `DEMAND_REFRESH_FRAMES = 2.0s`). `send_sos()` itself gains a
  second parameter, `active: bool = true` (see the off-broadcast note
  below) — otherwise unchanged, still the "broadcast one SOS hail right
  now" primitive; the heartbeat is purely an additional periodic caller.

- Rewrite the `Hail.VERB_SOS` receive branch (`ship.gd`'s comms_inbox
  processing, currently ~line 2865-2887). Branches on the incoming hail's
  `active` field (see the off-broadcast note below the IFF gating note for
  the `active == false` branch — this covers `active == true`, the normal
  heartbeat/one-shot case):
  - Compute `sender_trk`.
  - If `active_contacts.has(sender_trk)`: refresh in place —
    `sc["sos"] = true`, `sc["sos_nature"]`, `sc["sos_name"]`,
    `sc["last_seen_timer"] = 0.0`. Do **NOT** touch `pos`/`vel`/
    `signature`/`classification` — if this entry has a real sensor/relay
    detection backing it, that data is already fresher and more accurate
    than the SOS snapshot (this is the SAME "prefer live contact" principle
    already shipped in `sos_response_leaf.gd`, just applied at the
    merge-in point instead of the consumer).
  - Else: create a new entry — `pos` = `hail.get("pos", position)`, `vel =
    Vector2.ZERO`, `resolution = TAU`, `pos_timer = 0.0`, `last_seen_timer =
    0.0`, `signature = {}`, `classification = "DISTRESS CALL"`, plus the
    sos/sos_nature/sos_name fields. (`instance_id` = `sender_iid`, so
    anything resolving the live node later — e.g. navigation_panel's
    `_bounds_radius_for`/`_is_simple_body`, both of which resolve via
    `instance_from_id` and don't care whether WE detected it — still works.)
  - **Remove** the old `heard_sos[sender_iid] = sos_copy` line and the
    M41-hazard-avoidance comment above it (superseded).
- **Remove** `heard_sos` entirely: the `var heard_sos: Dictionary` field,
  its decay loop (`HEARD_SOS_TTL` age-and-prune block in `_physics_process`,
  ~line 2889-2926 including the mirrored-attribute-clear code the last
  session's fix added — all superseded, since the attribute now lives and
  decays ON the contact itself via the normal mechanism), and the
  `HEARD_SOS_TTL` constant.
- Datalink relay (`ship.gd`'s existing peer loop, ~line 2950 on): **no
  changes**. It already relays `active_contacts` wholesale, freshest-wins,
  multi-hop, LOS + IFF gated — a "DISTRESS CALL" entry rides this for free
  the instant it's a normal dictionary in `active_contacts`.
  - IFF gating note (resolved, not a blocker): the existing relay requires
    `_iff_tags_overlap`. The player currently already carries `HOME_IFF`
    (a pre-existing, separately-tracked narrative inconsistency from
    `m52b_warrants.md`'s "Open items" — not this milestone's problem to
    fix), so the beacon-bridge key test scenario below works out of the box
    against the authored campaign's `HOME_IFF`-tagged beacons/patrols with
    zero relay-specific code. If cross-faction distress relay is wanted
    later, that's a deliberate, separate design call — don't build it here.

**Off-broadcast (user addendum, 2026-07-23, supersedes the original "going
active→inactive should NOT send a cancel hail" call):** turning SOS off is
NOT silent. The two contact shapes SOS can produce decay asymmetrically —
a synthetic `"DISTRESS CALL"` entry (nothing else backs it) self-clears
fine once the heartbeat stops, just decaying at the normal `CONTACT_TIMEOUT`
like any unrefreshed contact; but a REAL contact that got `sos`/`sos_nature`/
`sos_name` STAMPED onto it does NOT self-clear — a real contact keeps
refreshing via its own actual sensor detections forever, so those three
fields would stay stuck true/populated permanently once stamped, with
nothing in the original design ever writing them back. Fix: `send_sos`'s
payload gains an `"active": bool` field (default `true` for every heartbeat
send). On the `sos_active` true→false transition inside `set_sos_active`
(guarded by `sos_active` already being true, so redundant/repeated `false`
calls are harmless no-ops), send ONE final `send_sos(sos_nature, false)` —
same wire/range rules (battery floor etc.) as any other send, just flagged
off. Receiver-side (`VERB_SOS` branch), when the incoming `active` is
`false`:
- Matched entry classified `"DISTRESS CALL"` (synthetic, nothing else backs
  it) → `active_contacts.erase(sender_trk)` outright.
- Matched entry has `sos == true` stamped on a real contact → clear just
  `sos = false`, `sos_nature = ""`, `sos_name = ""`. Do **NOT** touch
  `pos`/`vel`/`signature`/`classification`/`last_seen_timer` — same
  non-clobber rule as the on-path merge.
- No matching entry → no-op.

This rides the EXISTING datalink relay with zero new relay-specific code,
same philosophy as the rest of this design: a ship that directly hears the
off broadcast updates (or erases) its own `active_contacts` entry, and that
naturally propagates on the next relay hop like any other contact mutation.

Both callers that flip `sos_active` false — the player's comms panel
CheckButton toggle-OFF (`comms_panel.gd`/`terminal_display.gd`) and
`threat_response_leaf.gd`'s three incident-resolved paths (track-lost,
overtaken-mid-flight, and the was-held/compelled_stop-lapse check) — MUST
route through `set_sos_active`, not a direct `actor.sos_active = false`
field write, or the off broadcast never fires. `threat_response_leaf.gd`'s
on-path (turning SOS on) also routes through `set_sos_active(true, nature)`
now rather than setting the three fields directly, so the heartbeat-priming
logic lives in exactly one place.

### 2. `threat_response_leaf.gd`: AI's SOS becomes heartbeat-driven too

Currently sends ONE `send_sos()` call per incident ("always broadcast SOS
once per incident, regardless of the comply-or-run call"). Under the old
90s `HEARD_SOS_TTL` a one-shot was fine; under the new model (contacts decay
at `CONTACT_TIMEOUT` = 20s) a one-shot would make a rescuer lose the
distress contact if the incident runs longer than 20s (very plausible — a
12s+ robbery hold alone eats more than half that budget). Replace the
one-shot call with `actor.sos_active = true; actor.sos_nature = nature` when
the incident starts (both the RUN branch and the initial comply-or-run
decision point), and clear `actor.sos_active = false` once genuinely
resolved (the RUN incident's own track-lost/overtaken cleanup paths, and —
symmetrically — once `compelled_stop` clears on its own heartbeat lapse,
meaning the hold/incident is over). The ship-level heartbeat (item 1) handles
the actual re-sending; this leaf only owns the on/off decision.

### 3. `sos_response_leaf.gd`: read `active_contacts` instead of `heard_sos`

Scan `actor.active_contacts` for `classification == "DISTRESS CALL"` (or
equivalently `sos == true` — either works since the classification is
exclusive to this case) instead of `actor.heard_sos`. Freshest-first pick
(lowest `last_seen_timer` instead of lowest `age`). The already-shipped
"prefer live contact" logic collapses away naturally — there's only one
data source now, and it's already the freshest available by construction
(a correlated real detection overwrites position on the same entry, an SOS
heartbeat only touches position on first creation). Arrival-radius/give-up
logic unchanged in spirit; "gone stale" is now just "no longer in
active_contacts" (pruned by the normal `CONTACT_TIMEOUT` sweep) instead of
a `heard_sos`-specific empty-check.

### 4. `comms_panel.gd`: SOS button becomes an actual toggle

Currently a plain one-shot `Button` (already de-emphasized/grouped with
Share Name/Share Location in the earlier pass). Change to a `CheckButton`
(matching Share Name/Share Location's own control type) wired to
`set_sos_active` instead of a single `sos_requested` fire-and-forget. The
nature-pick logic in `_on_sos_pressed` (UNDER_ATTACK if a fresh HOSTILE
contact exists, else DISABLED) stays the same, just evaluated at
toggle-ON time (re-evaluate on every toggle-ON press, not once — a player
toggling SOS off and back on later might have a different nature by then).

### 5. `terminal_display.gd`: wire the new toggle

Replace the `sos_requested` signal handler's one-shot RPC with a toggle
handler calling `set_sos_active`.

### 6. `utils.gd`: `classification_color("DISTRESS CALL")`

Add a case returning the same red used elsewhere for distress (matches
`navigation_panel.gd`'s existing `SOS_COLOR := Color(1.0, 0.25, 0.1, 0.95)` —
reuse that literal, this file doesn't currently import colors from
navigation_panel.gd, follow the same "local literal, not a cross-file
import" convention already used everywhere in this area).

### 7. `navigation_panel.gd`: delete the special-case SOS marker

Remove `_draw_sos_marker`, the `SOS_COLOR`/`SOS_MARKER_RADIUS_PX`/
`SOS_PULSE_PERIOD` consts (superseded by item 6's generic color), and the
whole `sos_calls: Dictionary = current_state.get("sos", {})` loop that
draws it. A `"DISTRESS CALL"`-classified contact now flows through the
SAME generic per-contact drawing path every other contact already uses
(`_get_contact_color` → `Utils.classification_color`, blip/label/off-screen-
arrow, all already generic). Verify by eye (or a targeted test if the
existing test suite has widget-level coverage here) that a contact with an
empty signature doesn't crash `_bounds_radius_for`/`_is_simple_body`/the
silhouette path — it shouldn't, since both resolve shape via
`instance_from_id(contact["instance_id"])` (the REAL live ship node, which
DOES have real components/bounding radius even though WE never sensor-
detected it), not from the contact's own (empty) signature.

### 8. `main.gd`: drop `packet["sos"]`

`_distribute_state()`'s `"sos": ship.heard_sos.duplicate(true)` line is
dead once `heard_sos` is gone and nothing reads the packet field anymore
(item 7 removes the last reader). Remove the field and its comment block.

## Tests to update/replace

- `test_sos_contact_attribute.gd` — rewrite: dead-comms-still-reaches-
  battery-range case is unaffected (keep); the "stamped on existing
  contact" case still applies (keep, same shape); the "no contact ->
  active_contacts untouched" case is now WRONG under the new design (SOS
  DOES create a contact when none exists) — replace with "no existing
  contact -> a NEW 'DISTRESS CALL'-classified entry is created, with empty
  signature and the sos fields set." Plus two NEW cases for the off-
  broadcast addendum: (a) `set_sos_active(false, ...)` erases a synthetic
  `"DISTRESS CALL"` entry outright; (b) it clears only `sos`/`sos_nature`/
  `sos_name` on a real, independently-detected contact, leaving the entry
  itself (and its classification) alone.
- `test_sos_prefers_live_contact.gd` — the underlying behavior (a real
  detection's position wins over the SOS snapshot) still holds, but the
  MECHANISM moves from `sos_response_leaf.gd`'s consumer-side check to the
  merge-in point (item 1's "don't touch pos on an existing entry" rule).
  Rewrite to assert on `active_contacts` directly (position stays at the
  real-detection value after an SOS arrives) rather than the leaf's
  commanded heading.
- `test_patrol_interdiction.gd` Phase 6 (SOS response) — update to use
  `sos_active`/`set_sos_active` instead of `send_sos()`, and check
  `active_contacts` for the `"DISTRESS CALL"` entry instead of `heard_sos`.
- `test_contacts_panel_sos.gd` / `test_weapons_panel_standing.gd`'s SOS
  cases — unaffected in spirit (both already read the `sos`/`sos_nature`
  attribute generically off whatever contact dict they're handed), but
  double check the "no live contact" scenario changes meaning: contacts_panel
  now legitimately shows a `"DISTRESS CALL"`-classified row for a ship
  nobody's sensor-detected, not just an SOS-annotated real contact — worth
  one added case confirming that classification renders sensibly (blank
  transponder name → falls back to `sos_name`? Check `contacts_panel.gd`'s
  existing `t_name`/`c_id` fallback chain, may want `sos_name` as a further
  fallback there so an unresolved distress contact's row shows a real name
  instead of the bare `TRK-xxx` id).
- Any hail-protocol test asserting on `heard_sos` directly needs updating to
  check `active_contacts` instead — grep thoroughly, do not assume the list
  above is exhaustive.

## The key test (this is what "should just work" is being held to)

A line of beacons ("bridge"), each within comms-link range of its
immediate neighbor, spanning a distance well beyond any single beacon's own
SOS/comms range. `set_sos_active(true, ...)` fired from a ship near the
MIDDLE beacon. A patrol stationed near ONE END (outside the sender's own
direct range) should end up with a `"DISTRESS CALL"` (or later-corrected
real) entry in its own `active_contacts` for the sender within a few hops'
worth of relay latency (one tick of relay latency per hop, per the existing
mechanism's own documented behavior), and `SOSResponseLeaf` should then
break off and close on it — with NO relay-specific code written to make
this happen, only the data-model change above.

## Findings (as-built)

Built precisely per this doc's numbered order (items 1–8), plus the
off-broadcast addendum the user added mid-build (see that section above,
inline with item 1) after the base data-model work was already done and
verified. No deviations from the classification/merge/create rules — the
"if genuine ambiguity, make the reasonable call" clause only came up for
two things, both noted below (heartbeat priming, test sensor isolation).

### Heartbeat interval

`SOS_HEARTBEAT_INTERVAL := CONTACT_TIMEOUT / 3.0` = **6.67s** (`ship.gd`,
near `HAIL_HEARTBEAT_TIMEOUT`), exactly the ratio the doc specified —
matches `HAIL_HEARTBEAT_TIMEOUT`'s own "timeout/3, ~3 missed beats of
slack" convention.

**Deviation (reasonable-call, not spec'd either way by the doc):**
`set_sos_active(true, ...)` primes `sos_heartbeat_timer = SOS_HEARTBEAT_
INTERVAL` at the moment of activation, so the FIRST `send_sos()` fires on
the very next `_physics_process` tick instead of only after a full 6.67s
of silence. Reasoning: the doc's heartbeat block reads naturally as "start
accumulating from 0", which would leave a distress call's very first
broadcast delayed by up to ~6.67s after a player/AI turns it on — a
noticeable, unnecessary gap for something the user expects to fire
immediately (an SOS toggle should feel like pressing a button, not
scheduling one). Threat_response_leaf.gd's on-path now routes through
`set_sos_active(true, nature)` (not a direct three-field write) so this
priming logic lives in exactly one place. Subsequent re-decisions on an
already-open incident (matching seq) never re-prime it — proven directly
in `test_demand_lifecycle.gd`'s S4 and `test_threat_response.gd`'s
broadcast-once case via a race-free synchronous check on
`sos_heartbeat_timer` (a re-prime would set it to EXACTLY
`SOS_HEARTBEAT_INTERVAL`, distinguishable from organic delta-accumulation).

### Off-broadcast addendum (user requirement, mid-build)

`send_sos(nature, active: bool = true)` gained the `active` field.
`set_sos_active`'s true→false transition (guarded by `sos_active` already
being true — redundant/repeated `false` calls are no-ops) sends ONE final
`send_sos(sos_nature, false)`. Receive-side (`VERB_SOS` branch): a
`"DISTRESS CALL"`-classified (synthetic) matched entry is erased outright;
a real contact with `sos == true` stamped on it has just `sos`/`sos_nature`/
`sos_name` cleared, `pos`/`vel`/`signature`/`classification`/
`last_seen_timer` untouched. Rides the existing relay with zero new relay
code, same as the rest of the design. All three of
`threat_response_leaf.gd`'s `sos_active = false` sites (track-lost,
overtaken-mid-flight, was-held/compelled_stop-lapse) and both the comms
panel's toggle-OFF and the on-path now route through `set_sos_active`
rather than a direct field write, so the off broadcast always fires where
it's supposed to.

### Test-isolation deviation: stripping sensors from SOS-only test receivers

**Genuine ambiguity resolved, not covered by the doc:** the doc's test
rewrites (and my first pass at them) placed "far" receivers 20–28k units
from the sender to keep them outside sensor range, mirroring the OLD
tests' distances. That assumption was wrong under the new build — a
Frigate's active sensors (`dir_high_res`/`omni_main`) reach 40000 units
with **no distance falloff**, so those "far" receivers were still getting
real sensor correlations within the test's own 2s windows, which
immediately overwrote the `"DISTRESS CALL"` placeholder (or, in the
force-stale decay checks, kept re-refreshing `last_seen_timer` right back
down every sensor sweep, making the forced staleness — and thus the prune
— unobservable). This surfaced as real, reproducible test failures on the
first run, not a hypothetical. Fix: strip sensor components entirely
(`ship_components.filter(func(c): return c["type"] != "sensors")`,
`test_comms_relay.gd`'s existing, established pattern) from every receiver
in a test that needs its `active_contacts` entries to be provably
SOS-only. Applied in `test_sos_contact_attribute.gd` (3 of 5 cases — the
2 cases that WANT a real correlation, "stamped on existing contact" and
its off-broadcast counterpart, keep full sensors and the existing "wait up
to 10s for correlation" idiom), `test_sos_prefers_live_contact.gd` (both
cases), `test_patrol_interdiction.gd` Phase 6 (the patrol), and
`test_hail_protocol.gd` Scenario H (the listener, which also let Scenario
H's decay-proof shrink from a 110s real-TTL-wait budget down to a direct
forced-staleness check, same shortcut the other rewrites use).

### Verification results

All run via `test_runner.ps1` (`--fixed-fps 60`, per CLAUDE.md) unless noted.

**Grep-gate:** zero remaining `heard_sos`/`HEARD_SOS_TTL`/`SOS_COLOR`/
`SOS_MARKER_RADIUS_PX`/`SOS_PULSE_PERIOD`/`_draw_sos_marker` references in
`scripts/` outside of historical comments explaining the OLD design (kept
per the task brief's "prefer clean removal... but comments okay" allowance)
and `contacts_panel.gd`'s own pre-existing, unrelated `_SOS_COLOR` local
const (not one of the deleted navigation_panel.gd consts).

**Named tests (doc's "Tests to update/replace" + explicitly requested extras),
individually, all PASS:**
- `test_sos_contact_attribute.gd` — PASS (rewritten: battery-range case kept;
  stamped-on-existing-contact kept + classification-non-clobber assertion
  added; "no contact" case replaced with "creates a new DISTRESS CALL
  entry"; 2 new off-broadcast cases added — synthetic erase, stamped-fields
  -only clear)
- `test_sos_prefers_live_contact.gd` — PASS (rewritten to assert directly on
  `active_contacts`, no leaf involved — the mechanism moved to the merge
  point)
- `test_patrol_interdiction.gd` (full file, all 6 phases) — PASS (2.58s) —
  Phase 6 rewritten for `sos_active`/`set_sos_active` + `active_contacts`
- `test_contacts_panel_sos.gd` — PASS (rewritten: added the unresolved-
  distress-contact case, `sos_name` fallback in the header)
- `test_weapons_panel_standing.gd` — PASS (unaffected in spirit, confirmed)
- `test_hail_protocol.gd` (full file, all 8 scenarios) — PASS — Scenario H
  rewritten for `active_contacts` + forced-staleness decay
- `test_demand_lifecycle.gd` (full file) — PASS (4.06s) — S4 rewritten to
  check `sos_active`/`sos_heartbeat_timer` directly instead of
  `heard_sos` age
- `test_honored_stop.gd` (full file) — PASS (6.37s) — 2 `heard_sos.has(...)`
  reads replaced with `_find_contact(...).get("sos", false)`
- `test_threat_response.gd` (full file) — PASS (1.28s) — SOS-broadcast-once
  case rewritten for the heartbeat model
- `test_pirate_ambush.gd` — PASS (3.22s, this run)
- `test_pirate_abort.gd` — PASS (1.28s)
- `test_pirate_guild.gd` — PASS (1.28s)
- `test_robbery_mechanics.gd` — PASS (1.84s)
- `test_comms_panel_hails.gd` — PASS (unrelated M52d test, already present;
  confirmed unaffected)
- `test_port_control_comms.gd` — PASS (unrelated to this milestone;
  confirmed unaffected since `port_control.gd` was mid-edit at task start)

**New test proving the relay key scenario — `test_sos_relay_bridge.gd`
(PASS):** a 4-ship chain, Sender(0,0) → Beacon1(20000,0) → Beacon2(42000,0)
→ Patrol(64000,0), same IFF tag, clear LOS, every ship but the sender with
sensors stripped (so nothing observed can be explained by real detection —
Beacon2/Patrol also sit beyond a Frigate's 40000-unit sensor range from the
sender regardless). Sender–Beacon1 = 20000 (within `SOS_BATTERY_RANGE`
30000, direct hail); Beacon1–Beacon2 and Beacon2–Patrol = 22000 each
(within comms-link range, so each relay hop holds); Sender–Beacon2 (42000)
and Sender–Patrol (64000) both exceed 30000, so neither could ever hear the
SOS directly. `set_sos_active(true, ...)` fired once. **Result: all 3 hops
(Beacon1 direct + 2 relay hops) resolved by physics frame 2** (i.e.
effectively the very first tick) — Godot processes each `_physics_process`
in scene-tree/spawn order within one frame, so Beacon1's freshly-created
`"DISTRESS CALL"` entry was already live by the time Beacon2's own
`_physics_process` ran its relay pull later THAT SAME frame, and likewise
Patrol pulling from Beacon2 — collapsing the "documented one-tick-of-
latency-per-hop" worst case into a single frame here. `SOSResponseLeaf`
was then ticked directly against the patrol (real leaf, no relay-specific
scaffolding) and correctly claimed the tick, committing
`sos_responding_to` to the sender's track id — learned purely through
relay, with zero relay-specific code written anywhere in this milestone.

**Full `build.ps1` gate:** ran clean — GDScript syntax validation passed,
all **104** launched test scenarios (the entire suite, parallel) **PASSED**,
zero `FAIL`/`ASSERT FAILED` anywhere in the log, including `test_pirate_
ambush` (3.22s) and `test_ai_duel` (12.82s), both called out in the task
brief as known-flaky — neither failed on this run. Build packaged
successfully (`ProjectDeepSpace_Windows_v2026-07-23.110851.zip`).

**Git status:** `tactical_analysis/data/*` perf-baseline churn from the
gate run was reverted (`git checkout -- tactical_analysis/data/`). Working
tree otherwise holds only this milestone's changes plus the pre-existing
untracked `contacts_dump.txt` (left alone, per instructions) and this doc
itself (still untracked from the earlier calling session — left uncommitted
along with everything else for the separate verification pass). No commits
were made.
