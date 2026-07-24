# M56 — Contact freshness: absolute frame-stamps, not per-frame accumulators

## Motivation

Surfaced from conversation, not a playtest report: `last_seen_timer` is
currently a delta-accumulated float, incremented by `delta` for EVERY
contact, on EVERY ship, EVERY physics frame (`ship.gd`'s `contact_decay`
block), reset to `0.0` whenever a fresh detection/relay/hail update lands,
and pruned once it exceeds `CONTACT_TIMEOUT` (20.0s). This write-every-frame
pattern has two real costs, one performance and one correctness:

1. **Perf**: it's an O(contacts) mutation every tick regardless of whether
   anything is actually reading most of those contacts this frame
   (`contact_decay` measured ~259us/frame in this session's steady-state
   breakdown — not the biggest cost in the tick, but real and structurally
   avoidable).
2. **Correctness/fragility**: the relay's echo-lock prevention
   (`relayed_age = external_contact.get("last_seen_timer", 0.0) + delta`,
   `datalink_relay` in `ship.gd`) exists ONLY because a manually-accumulated
   duration can't distinguish "genuinely fresher" from "an artifact of when
   I happened to check it" — it needs a `+delta` fudge specifically to
   guarantee a round-trip relayed copy always reads at least one tick staler
   than a fresh local reset. That fudge is itself fragile: it silently
   assumes relay runs every physics frame. The moment `datalink_relay` gets
   throttled to run less often (a real, already-scoped perf lever — see
   `implementation_plans/m45_physics_perf_investigation.md`'s deferred
   list), this math needs to become "time since THIS ship's last relay
   pass" instead of "this frame's delta," or it silently undercounts
   staleness and can reopen the exact echo-lock bug it was built to close.

Storing an absolute stamp instead of an accumulated duration eliminates
category 2 entirely (a real timestamp can never be ambiguous about how old
it is, regardless of how often anything gets checked) and gives category 1
a real but smaller win than it might first appear — see "Scope, honestly"
below before assuming this recovers most of `contact_decay`'s cost.

**Relation to the Mail Network vertical**
([../design_ideas/mail_network.md](../design_ideas/mail_network.md)): originally
thought to be a hard dependency, but the mail model was since simplified to a
**monotonic per-source log** — a mailbag is "source @ vN", the merge is just
`max(version)` per source, and the version is the source's OWN sequence number
carried unchanged through every hop. That design sidesteps "The multi-hop
timestamp question" below entirely (there is no re-stampable observation stamp
to get wrong), so the mail merge does NOT depend on this milestone. This stays a
**contacts**-scoped cleanup; the mail network only borrows the frame-stamp idiom
for age *display* (how stale a delivered registry reads), not for ordering.
Solve the multi-hop question here for contacts regardless — it's still real for
relayed sensor tracks.

## The design

Replace `last_seen_timer: float` (seconds since last update, accumulated) with
`last_seen_at: int` (an absolute `Engine.get_physics_frames()` reading, taken
at the moment of update). Staleness becomes `Engine.get_physics_frames() -
c["last_seen_at"]`, always computed on demand, never accumulated.

**Why frame count, not wall-clock or a running seconds-accumulator**: this is
already the established idiom in this codebase for exactly this kind of
thing — `PerfProbe`'s own frame-bucketing, and M45's frame-scoped caches
(`_los_cache_frame`, `_port_authority_cache_frame`,
`_get_reactor_power_rating_cached`'s frame key) all key off
`Engine.get_physics_frames()`. It's an integer (no float-accumulation
drift), it's free (Godot already maintains it, nothing new to increment
anywhere), and it's exactly deterministic under `--fixed-fps` — the same
property CLAUDE.md's determinism rules already require of combat-relevant
sim state.

**Consumer-facing constants stay in seconds** (`CONTACT_TIMEOUT := 20.0`,
`FIRE_STALENESS_MAX := 3.0`, etc. — no reason to force every call site to
learn a new unit) — comparisons convert via the physics tick rate:
`(Engine.get_physics_frames() - c["last_seen_at"]) / PHYSICS_TICKS_PER_SECOND
<= FIRE_STALENESS_MAX`, or equivalently pre-convert the threshold to frames
once (`FIRE_STALENESS_MAX_FRAMES`) and compare integers directly — cheaper
per-comparison, implementer's call which reads better at each call site.

**Freshest-wins comparisons become trivial and throttle-proof**: bigger
`last_seen_at` = fresher, full stop — no hop-cost fudge factor needed at
all, since a relayed copy's stamp already IS the real moment of the
underlying detection, not an approximation that degrades if checked less
often. This is what actually fixes the relay-throttle fragility this
milestone was motivated by.

## Scope, honestly: this does NOT by itself reclaim most of `contact_decay`'s cost

Read the current decay loop before assuming otherwise (`ship.gd`, the block
tagged `PerfProbe.begin("contact_decay")`) — it does FOUR things per
contact per frame, and `last_seen_timer` is only one:

1. `last_seen_timer` increment — what this milestone targets.
2. `pos_timer` increment — a SEPARATE staleness clock ("seconds since the
   last position update before a coarser-resolution bin is allowed to
   override position anyway," `CONTACT_RESOLUTION_STALE_TIME := 0.3`) —
   same accumulator pattern, same write-every-frame cost, NOT targeted by
   this milestone unless explicitly extended (see Non-goals).
3. `outline_dots` TTL aging — a per-contact sub-list, each dot aged the
   same delta-accumulated way.
4. **Dead-reckoning the contact's estimated position itself**
   (`c["pos"] += c["vel"] * delta`) — almost certainly the single most
   expensive line in this loop (a `Vector2` op plus a type check per
   contact), and it is NOT a pure staleness concern — it's live simulated
   state, not a timer.

If ONLY `last_seen_timer` converts, this loop still has to run every frame
for every contact anyway, for reasons 2-4 — so the realistic perf recovery
from this milestone ALONE is smaller than `contact_decay`'s full ~259us/frame
figure suggests. The correctness/robustness win (item 2 in Motivation) is
the primary reason to do this now; a full `contact_decay` perf win would
need items 2 and 4 redesigned the same way (store `(base_value, stamp)`,
derive current value lazily — the SAME pattern, applied further), which is
explicitly out of scope here (see Non-goals) so this milestone stays
reviewable and doesn't balloon.

## Sequencing — do not start until the in-flight SOS work lands

This touches the exact same functions (`ship.gd`'s decay loop and the
`datalink_relay` merge logic) that
`implementation_plans/m52_sos_passive_sync.md` is being implemented against
RIGHT NOW, in a separate work stream, as of this doc being written. Do not
begin this milestone until that one is merged and independently verified —
starting concurrently guarantees a collision in the same functions. Read
`m52_sos_passive_sync.md`'s own Findings section first once it exists; that
work will have JUST added `sos`/`sos_nature` to the relay's freshest-wins
merge block using `last_seen_timer`-based comparisons — this milestone
needs to convert those same new lines to the timestamp scheme too, not
leave them as a second, inconsistent freshness convention.

## Write sites to convert (ship.gd, current line numbers — will have moved by the time this executes; re-grep, don't trust these blindly)

Found by grepping `last_seen_timer` assignments directly, not from memory:

1. **The decay loop itself** (~line 2374): `c["last_seen_timer"] =
   c.get("last_seen_timer", 0.0) + delta` — becomes: nothing to increment;
   staleness is derived, not accumulated. The loop's remaining job for
   `last_seen_timer`'s purposes shrinks to "is `now - last_seen_at >
   CONTACT_TIMEOUT_FRAMES`? if so, prune" — still O(contacts) for the prune
   check itself (nothing avoids needing to LOOK at each contact to decide
   whether to remove it), but no per-contact WRITE anymore for this field.
2. **Contact correlation, fresh detection** (~line 2680): `c["last_seen_timer"]
   = 0.0` → `c["last_seen_at"] = Engine.get_physics_frames()`.
3. **New-contact creation sites** (dict literals with `"last_seen_timer":
   0.0` — at least 3 found: contact correlation's new-entry branch, and
   (as of this session) the SOS reconciliation's create-new-entry branch,
   post-`m52_sos_passive_sync.md`) → `"last_seen_at":
   Engine.get_physics_frames()`.
4. **Relay import (new entry)** (~line 3226): `imported["last_seen_timer"] =
   relayed_age` → needs the SENDER's own `last_seen_at` carried through the
   relayed dict (not recomputed locally) so multi-hop timestamps stay
   ground-truth accurate, not re-stamped-as-of-whoever-relayed-it-last. This
   is the one site that needs real thought, not a mechanical swap — see
   "The multi-hop timestamp question" below.
5. **Relay merge (existing entry, freshest-wins)** (~line 3245):
   `c["last_seen_timer"] = relayed_age` → same freshest-wins comparison,
   now `if external_contact["last_seen_at"] > c["last_seen_at"]:` (bigger
   frame number wins, no `+delta` needed).

## The multi-hop timestamp question (read this before implementing site 4/5 above)

With the current duration-based design, `relayed_age` is deliberately
INFLATED by one hop's worth of delta specifically so a relayed copy can
never look fresher than it really is. With absolute stamps, there's no
inflation needed — but that means the relayed `last_seen_at` MUST be the
value from the ORIGINAL detecting ship (or the ORIGINAL sender, for
self-report data), propagated unchanged through every hop, not overwritten
by whichever ship is currently relaying it. Get this wrong (e.g.,
accidentally re-stamping `last_seen_at` to "now" at each relay hop) and
EVERY relayed contact looks perfectly fresh forever, which is a worse bug
than anything this milestone is fixing — it would break `CONTACT_TIMEOUT`
pruning for every relayed contact silently. `active_contacts.duplicate(true)`
already preserves whatever `last_seen_at` was on the source dict when
copying an existing entry (relay already does this correctly for
`last_seen_timer` today, since `duplicate(true)` is a deep copy) — the risk
is specifically in the SELF-REPORT block (`ship.gd`'s "ground truth
self-report" for a directly-linked neighbor), which currently synthesizes
`"last_seen_timer": 0.0` fresh every tick because the self-report IS live,
real-time truth for a one-hop neighbor. That part should stay exactly
analogous — self-report gets `"last_seen_at": Engine.get_physics_frames()`
fresh every tick too, since it's still true, live data for a direct
neighbor. The distinction to get right: self-report synthesizes a NEW
timestamp (because it's regenerated from live truth every tick), while
relaying an EXISTING contact must PRESERVE whatever timestamp is already on
it (because that contact represents a specific past detection, not
something happening right now).

## Read sites to migrate (do not skip — test files force staleness directly)

27 files reference `last_seen_timer` (grepped this session, not estimated):
11 production files (`ship.gd`, `threat_response_leaf.gd`,
`sos_response_leaf.gd`, `interdict_leaf.gd`, `challenge_leaf.gd`,
`fire_opportunity_leaf.gd`, `acquire_target_leaf.gd`, `job_steps.gd`,
`contacts_panel.gd`, `comms_panel.gd`, `utils.gd`) and 16 test files. Two
migration options, pick one and apply consistently rather than mixing:

- **(a) Helper function**: `Ship.contact_age(c: Dictionary) -> float`
  (returns seconds, computed from `last_seen_at`), every read site calls
  this instead of `c.get("last_seen_timer", ...)`. Cleaner, makes "this is a
  derived value, not stored state" explicit at every call site, but touches
  every read site's syntax.
- **(b) Keep writing a derived `last_seen_timer` field too**, refreshed
  lazily (e.g., recomputed once per read via a getter-like wrapper, or
  refreshed during the same pruning pass that already has to look at every
  contact anyway) so existing read sites need ZERO changes. Less invasive,
  but reintroduces a cached/derived value that can itself go stale between
  refreshes if not disciplined about when it's recomputed — partially
  undermines the "no possible staleness ambiguity" goal that's the actual
  point of this milestone. Only worth it if (a)'s blast radius turns out
  larger in practice than this doc estimates.

Recommendation: (a). The whole point is removing an accumulator that can be
ambiguous about its own freshness; keeping a second one around for
compatibility is exactly the kind of thing that reintroduces the bug class
this milestone exists to close.

**Tests specifically need attention, not just mechanical translation**: at
least 4 test files (`test_sos_contact_attribute.gd`,
`test_patrol_interdiction.gd`, `test_hail_protocol.gd`, and others found by
the same grep) use `c["last_seen_timer"] = 9999.0` as a deliberate
"force this stale right now, skip waiting out the real 20s" shortcut
(CLAUDE.md's own documented test-speed convention). The equivalent under
the new scheme is `c["last_seen_at"] = Engine.get_physics_frames() -
CONTACT_TIMEOUT_FRAMES - 1` (or similar) — mechanically different but the
SAME intent; grep for `last_seen_timer.*=.*9999` (and similar large-number
force-stale patterns) specifically, since these are exactly the sites most
likely to be translated wrong by pattern-matching alone (a naive
find-replace of the field name would leave `= 9999.0` as a nonsensical
frame number rather than the intended "far in the past" semantics).

## Non-goals for this pass

- **`pos_timer`, `outline_dots` aging, and dead-reckoned position are NOT
  converted** — same accumulator pattern, same theoretical benefits, but
  each has its own subtleties (`pos_timer` gates a DIFFERENT resolution-
  quality tradeoff, not staleness/pruning; dead-reckoning is live
  simulation state, not a timer, and lazy position extrapolation needs its
  own correctness pass — e.g., confirming nothing depends on `pos` being
  updated exactly once per frame rather than in occasional larger jumps).
  Doing all four at once risks a much harder-to-review diff for a much
  larger and different set of correctness questions. A natural follow-up if
  this milestone's win justifies going further, not bundled here.
- **Not reclaiming `contact_decay`'s full measured cost** — see "Scope,
  honestly" above. This milestone's real deliverable is removing the relay-
  throttle fragility and the timer-vs-timestamp ambiguity, not a specific
  perf number. Measure what IS recovered, but don't calibrate success
  against `contact_decay`'s full ~259us/frame figure.
- **Not implementing relay throttling itself** — this milestone is what
  makes that SAFE to do later, not the throttling work itself.
- **Not touching `_contact_tombstones`' own separate `-= delta` decay** —
  same pattern, smaller/simpler, not in scope; note it as a trivial
  follow-up if this pattern proves out.

## Tests

- Every test that constructs a synthetic contact dict with
  `"last_seen_timer": 0.0` needs `"last_seen_at": Engine.get_physics_frames()`
  instead (or whatever the chosen helper/field name ends up being).
- Every "force stale" test site needs the frame-count equivalent, per the
  note above — verify each one still actually exercises what it originally
  intended (pruning, give-up conditions, etc.), not just that it compiles.
- New test: prove the multi-hop timestamp question above is handled
  correctly — a relayed contact's `last_seen_at` reflects the ORIGINAL
  detection time after 2+ hops, not "whenever it was last relayed," and
  `test_sos_relay_bridge.gd`'s existing hop-timing assertions (2-frame
  propagation across a 3-hop chain) still hold under the new scheme — this
  is the single most likely place for a subtle regression, since it's the
  one site this doc flags as needing real thought rather than a mechanical
  swap.
- New test: relay's freshest-wins comparison now correctly resolves an
  exact tie (two ships stamp the identical frame) — pick a explicit,
  documented tie-break rule (e.g., "keep local over incoming on exact tie")
  and assert it, since the old `+delta` scheme made exact ties structurally
  impossible and the new one doesn't.
- Full `build.ps1` gate green, with particular attention to anything
  reading `FIRE_STALENESS_MAX` (fire-control gating — a wrong staleness
  read here has real combat-outcome consequences, not just a stale UI
  badge) and `CONTACT_TIMEOUT` pruning behavior across the whole suite.

## Findings (executed)

_(to be filled in by whoever implements this — re-grep write/read sites
fresh rather than trusting this doc's line numbers, which will have moved;
pay special attention to the multi-hop timestamp question, since that's the
one place this doc identifies real design risk rather than mechanical
translation.)_
