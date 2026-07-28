# Duplication audit — 2026-07-27

A read-only sweep for duplicated logic, stringly-typed sets, and duplicated
constants, prompted by playtest A2 (one rule, five implementations). Nothing in
this document has been fixed unless it says so.

**Why this was commissioned.** A2 was not "someone forgot to reuse a function".
Every divergent copy carried a comment *justifying* itself — *"standing.gd is
phase-1, not ours to touch"*, *"utils.gd's classification_color is shared with
the nav/sensor panels (also out of scope here), so this is its own small const"*.
Individually conscientious; collectively a guarantee of drift. **That comment
shape is the signature to hunt for**, and it recurs below.

Findings are ranked by consequence, with **already-diverged cases first** —
those are bugs, not smells.

---

## 1. The A2 bucketing rule has a fifth copy, still live — CONFIRMED DIVERGENCE

The A2 fix reached `contacts_panel.gd`'s row placement (`Utils.contact_section`)
and its tab-cycle ordering. It did **not** reach `_update_contact_list`'s own
bucketing block (`contacts_panel.gd:189-225`), which still buckets on
classification alone.

Three consequences, all live:

1. **The counts contradict the list.** `classify_contact` returns
   `UNIDENTIFIED VESSEL` for any live vessel without IFF crypto — including a
   reporting NEUTRAL station. Its *row* files under "All Contacts" while its
   *count* increments "Enemies", so the panel renders **"Enemies (4)" above an
   empty Enemies section.** The literal A2 complaint, surviving inside the file
   that fixed A2.
2. **"Alerts" never gets a count.** The section is created from
   `Utils.CONTACT_SECTIONS` but the count block only writes Enemies/Ships/All
   Contacts, so its button reads `"Alerts (-)"` forever — on the section that
   holds CAUTION contacts and distress calls.
3. **Within-section rows are not distance-sorted** — they arrive as
   `enemies + ships + others`, so "All Contacts" gets neutrals-by-distance
   followed by wreckage-by-distance.

**Fix:** bucket into a Dictionary keyed by `Utils.contact_section(c)` (as the
tab-cycle path already does) and drive counts and order from that. Add the
assertion that would have caught it: a NEUTRAL-standing `UNIDENTIFIED VESSEL`
is not counted under Enemies. Contained to one function, low risk.

---

## 2. `_has_fresh_hostile` — duplicated between two leaves that MUST agree

`sos_response_leaf.gd:84-94` and `interdict_leaf.gd:217-226` carry identical
bodies. **They diverged once already** (2026-07-27) over whether a distress call
could be stale; the resolution was a hand-sync plus a comment saying the two
must agree. *The structure guaranteeing they agree is a comment.*

**Failure mode:** a patrol holds its yellow interdiction because the SOS looks
stale to one leaf while the other would still fly to it — an incident with no
response and no log line.

**Fix:** one static alongside `Standing.track_engageable_refusal`, which exists
for exactly this reason. `interdict_leaf`'s DISTRESS-CALL clause is deliberately
asymmetric — keep that at the call site.

---

## 3. `"TRK-%03d"` — 17 production sites, three incompatible resolution strategies

The instance-id → contact-key derivation is open-coded 17 times across
`ship.gd` (11), `threat_response_leaf.gd`, `challenge_leaf.gd`, `job_steps.gd`
and `comms_panel.gd`, plus 24 test occurrences. There is no helper.

Worse than the count: three *different* ways to answer "which contact is this
instance id?" — derive-and-lookup, linear scan on the stored `instance_id`
field (`job_steps.gd:321`), and scan the `ships` group re-deriving each key
(`challenge_leaf.gd:159`). They disagree whenever two instance ids are
congruent mod 1000.

**This derivation is also the primary key of `active_contacts`.** `abs(iid) %
1000` gives 1000 buckets against sequentially-allocated ids, so two ships 1000
apart in allocation order collapse into one track — fused sensor data, wrong
demand issuer, datalink self-report overwriting a real detection. The same
namespace is shared with a sequential `next_contact_id` counter, so `TRK-001`
may be either an anonymous sensor bin or a ship.

Collision is confirmed reachable by construction, not observed.

**Fix, in two separate commits — do not conflate them:**
- *Safe:* `static func Ship.track_id(iid)` replacing the 17 sites. Pure
  extraction. Per CLAUDE.md, migrate one file at a time and read that file's
  `.err.log` after each, rather than running a full gate.
- *Not safe:* widening the key space or unifying the three strategies. Touches
  the fusion hot path and the datalink format.

---

## 4. `PHYSICS_HZ := 60.0` hardcoded twice, against an explicit written policy

`job_steps.gd:43` and `standing.gd:366` each hardcode it, while `ship.gd:129`
documents the opposite decision in so many words — read
`Engine.physics_ticks_per_second` "in case that rate is ever tuned" — and does.

Values agree today, so nothing is broken now. But the *policies* have already
diverged: retune the tick rate and contact staleness rescales correctly while
**warrant expiries**, the **demand heartbeat cadence** and **victim blacklists**
silently halve or double. A 60s ASSAULT warrant becoming 120s of HOSTILE is a
gameplay change with no error anywhere. Cheap to fix; ranked high because the
failure is invisible.

---

## 5. `Utils._STANDING_TIERS` is keyed on bare literals — a booby trap on a scheduled rename

> **RESOLVED 2026-07-27.** The table was re-keyed onto `Standing.*` before the
> rename, and the rename then landed: `UNREPORTED` → `CAUTION`, with the
> `const CAUTION := UNREPORTED` alias deleted rather than kept. The booby trap
> this entry predicted did not fire — `_STANDING_TIERS` did not notice the
> rename at all, which is the entry's own argument, demonstrated.
>
> The alias was not harmless while it lasted: two names for one string caused
> the patrol re-hail loop and hid the Share-Name-off case, both the same day.
> The FRIENDLY coverage gap called out below is still open.

`utils.gd:110-115` keys the tier table on `"HOSTILE"`/`"UNREPORTED"`/etc. rather
than `Standing.*`. It is the **only** file outside `standing.gd` that spells
those literally; every other consumer is disciplined.

`standing.gd` states that renaming `UNREPORTED` → `CAUTION` is a *planned,
deferred commit*. When it lands, the lookup misses, `contact_tier` returns `""`,
and every non-reporting vessel falls through to `classification_color` → **RED**.
A2, reconstructed by a refactor the codebase has already scheduled.

Partly guarded: `test_contact_tier` routes HOSTILE/NEUTRAL/CAUTION through
`Standing.*`, so those renames fail the test. **FRIENDLY is not covered** — its
case sets `sos: true` and therefore resolves `TIER_SOS`, never exercising the
FRIENDLY row. Renaming `Standing.FRIENDLY` would grey out every friendly contact
with a green suite.

**Fix:** preload `Standing` in `utils.gd` and key on the constants (preloads are
constant expressions, and `standing.gd` has no dependency on `utils.gd`, so no
cycle). Add a FRIENDLY-without-SOS case.

---

## 6. Dead and write-only state

**Correction to the original brief:** `comms_panel._entry_nodes` is *not* dead —
`test_comms_panel_hails.gd` uses it as the panel's rendering assertion handle.
Awkward as a test seam, but a real consumer.

What is genuinely dead:

- **`manual_sensor_target` (`ship.gd`) — the strongest `wanted_names` match in
  the codebase.** `set_sensor_target` is a body consisting of one assignment
  nobody reads, called by `acquire_target_leaf` on every acquisition, by the
  drone controller, and by `terminal_display` **via RPC whenever the player
  selects a contact**. So clicking a contact fires a network RPC that does
  nothing. Adjacent `_high_res_target_idx` / `_high_res_target_timer` are
  declared and never referenced. Together: the corpse of a manual
  directional-sensor feature, wired to a live UI action so it looks alive.
  **Decide, don't leave it** — wire it to the `dir_high_res` sensor it was for,
  or delete the field, the RPC and its three call sites.
- `helm_panel.gd:16-17` — `thrust_slider`, `vel_gauge`: declared, never assigned.
- `wormhole.gd:12-13` — `landmark_name`, `nav_radius` ("used by later nav").

---

## 7. Partial re-implementations of `Standing.track_engageable`

Two consumers use the shared helper. Three re-implement subsets:
`fire_opportunity_leaf` (staleness + wreckage, **omits `complied_stop`**),
`interdict_leaf` (all three, inline), `flee_leaf` (wreckage only).

`fire_opportunity_leaf`'s omission is latent, not live — it runs downstream of
acquisition in a sequence, so acquisition's FAILURE short-circuits it.
`interdict_leaf`'s is the higher risk precisely *because* it is a complete copy:
it looks synced and will silently fall behind when a fourth condition is added.

---

## 8. `contact_age`'s `missing_default` is used inconsistently

`Ship.contact_age(c, missing_default := 999.0)`. Callers split between `999.0`
("maximally stale") and `0.0` ("perfectly fresh") — and **the permissive `0.0`
sits on the fire path**, reached by both `acquire_target_leaf` and the player's
console.

Not currently reachable: every production construction site stamps
`last_seen_at`, verified by inspection, and the packet deep-duplicates it. But
if it ever becomes reachable, a stampless contact reads *fresh* to fire control
and *stale* to interdiction — a target the AI shoots but will not demand a stop
from. The failure points the wrong way.

---

## 9. Duplicated constants

- **The SOS colour is duplicated inside `utils.gd` itself** (`:100` and `:162`),
  with a comment admitting it. The same emergency draws two different reds
  depending on whether the caller holds a full contact dict or a bare synthetic
  distress entry — i.e. **the colour changes as a distress call resolves into a
  real sensed contact.** Name it once.
- **`comms_panel.gd:10 SOS_FRESH_STALENESS := 3.0`** mirrors
  `Ship.FIRE_STALENESS_MAX`. Its comment justifies the copy as avoiding an
  import of `Ship` — *and the same file calls `Ship.contact_age` on the line
  that uses it*. Self-refuting justification; zero-risk deletion.
- **`ship_design_validator.gd LAYOUT_RAYMARCH_STEP` vs `ship.gd
  DAMAGE_RAYMARCH_STEP`**, with an explicit "MUST be kept in sync". The stated
  reason for the copy (no `Ship` instance) does not hold — it is a `const`,
  readable statically. If they drift, the validator passes designs whose damage
  propagation differs in play.
- **`ship.gd` references a constant that no longer exists** — a comment says it
  duplicates `navigation_panel.OUTLINE_FADE_START`, which has not existed since
  the v1.1 outline revision. The real contract is now an inequality and it *is*
  asserted by `test_sensor_dots`. Stale comment, not a divergence — but it
  would send someone restoring a coupling that was deliberately loosened.
- *Not* duplicates, flagged so they are not re-flagged: `CRUISE_SPEED` /
  `ARRIVAL_RADIUS` differ across three leaves because the behaviours differ.

---

## 10. Stringly-typed sets — verdict per set

| Set | Verdict |
|---|---|
| Contact classifications | **Stay strings, add `const`s on `Ship`.** They ride the datalink and the replication packet and are compared across module boundaries; an enum would need a wire mapping for no gain. But 30+ sites spell them literally, and `contacts_panel` introduces a seventh value `"UNKNOWN"` as a `.get` default no colour table handles. Also worth renaming `UNIDENTIFIED VESSEL` *in prose* — it means "not IFF-friendly", not "unknown". |
| Standing tiers | **Already correct**, except `utils.gd` (finding #5). |
| Flags | **Already correct** — zero bare literals outside `standing.gd`. Must stay strings; they ride the transponder wire. |
| Job step verbs | **`const` on `JobSteps`, not an enum** — the verb is a Dictionary key authored by directors, tests and sim runners. Note `Hail.VERB_*` / `RUNG_*` are already consted one module over; the job verbs are the outlier, in a field also called `"verb"`. A typo'd verb hits `push_error` + `ABORT`, and an unlabelled ABORT is the failure CLAUDE.md documents as reporting SUCCESS and silently clearing the slot. |
| Blackboard keys | **Mostly leave alone.** Eleven of fourteen are single-file, where a typo is a same-file bug. Only `target_id` / `target_pos` genuinely span modules (written by `acquire_target_leaf`, read by three others) — and there a typo fails *silently*, because `get_value` returns the default. Const those two. |
| Component `type` values | **Stay strings** — authored ship-design data and part of the serialization shape; a typo is caught by `test_ship_designs`. Separately: `ship.gd` has five near-identical "find the comms component and set a field" RPC setters — real duplication, independent of the string question. |
| Commodity classes | **Already exemplary** — consts, an `ALL` array, zero bare literals anywhere. The newest subsystem followed the convention; cite it as house style. |

---

## If you only do three things

1. **Fix `contacts_panel.gd:189-225`** — the only confirmed, currently
   player-visible divergence here, and it is the A2 contradiction still
   shipping in the file that fixed A2.
2. **Decide what `manual_sensor_target` is** — a player-triggered RPC writing a
   field nobody reads. Wire it or delete it.
3. **Extract `Ship.track_id(iid)`** across the 17 production sites — highest
   multiplicity in the codebase, and the three incompatible iid→contact
   strategies cannot be reconciled until the derivation has a name. Leave the
   `% 1000` collision as a separate, later decision.

Cheap runners-up, both self-refuting-comment cases: key `Utils._STANDING_TIERS`
on `Standing.*` (#5), and delete `comms_panel`'s `SOS_FRESH_STALENESS` (#9).
