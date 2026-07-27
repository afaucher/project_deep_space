# Campaign playtest — 2026-07-26

First-run feedback on starting the campaign, plus menu/UI issues found along the
way. Companion to [2026-07-20-pirate_playtest.md](2026-07-20-pirate_playtest.md).

Ordered by severity, not by the order they were reported.

---

## ROOT CAUSE FOUND for A1 + A3 — *2026-07-27*

**One mechanism, exactly as this doc predicted they'd share.** Not a standing
value, not IFF: `challenge_leaf.gd`'s challenge-EXPIRY path never re-checked
comms range.

Comms reach is authored **shorter than sensor reach on purpose** — measured at
25,000 vs 35,000 by `test_patrol_id_read.gd` — because hearing a hull's
transponder is a piece of omniscience you close distance to earn. Inside that
band a reporting hull reads NEUTRAL; outside it reads UNREPORTED, correctly,
because you genuinely cannot hear it.

Issuing a challenge already gated on comms range. Expiring one did not. So:

1. Patrol closes, legitimately sends `DEMAND{IDENTIFY}` (**A3 is real, and the
   demand is not a bug** — it is the right response to a hull it can see and
   cannot identify)
2. **The player moves**, leaving comms range
3. The window lapses with the contact still UNREPORTED — because it is
   unhearable, not because it refused
4. `NO_ID` warrant posted → `compute_standing` reads HOSTILE →
   `acquire_target_leaf` engages → **A1: the home station opens fire**

*"If you move the station opens fire"* is the literal mechanism. The patrol
convicts you for not answering a question it can no longer hear the answer to.

**Fixed** by requiring the subject to still be inside comms range before a
NO_ID warrant may be posted; the challenge is voided rather than deferred, so it
can be re-issued when the contact returns. `test_patrol_id_read.gd` locks the
calibration down as a property.

**This invalidates the 3-second grace period as A3's fix** (below). A grace
period covers a few frames of relay lag; it does nothing for a hull sitting
outside comms range indefinitely — the grace would expire and the demand would
fire anyway. Still worth adding on its own merits, and the dedup is still a real
bug, but neither is the cause.

Note also: contacts read `UNIDENTIFIED VESSEL` even at 1,000 units with the
transponder received and standing resolving NEUTRAL. The classification string
never reflects identification — possibly A2's third colour source showing
through. **Not yet investigated.**

### Follow-up: the escalation ladder is missing its middle rung — *open*

The fix above makes the warrant *fair*. It does not make it *effective*: a hull
can now ignore an identify challenge simply by flying away, and nothing happens.
That is a hole, and it is the same hole from the other side.

`challenge_leaf` **always returns FAILURE** — it is pure side-effect and never
claims the tick, so the patrol lobs a `DEMAND{IDENTIFY}` as it passes and keeps
flying `FollowRoute`. It never closes. Meanwhile `Interdict` only pursues
contacts that are **already HOSTILE**:

```
Challenge (no movement) --> warrant --> HOSTILE --> Interdict (movement)
```

So closing happens AFTER the verdict rather than being how the verdict is
earned. **If a patrol is prepared to convict you, it should be trying to
intercept you.**

**Proposed:** a challenge drives an approach. The patrol closes to keep the
subject inside comms range while the challenge window runs; the NO_ID warrant
lands only if it has actually closed and still received nothing. Mirror
`Interdict`'s existing shape — assign a job, let `JobRunner` pick it up the same
tick — rather than inventing a second mechanism.

**Balance risk to design against, not discover:** patrols abandoning their
routes to chase every unidentified hull. Needs bounding — controlled space only,
a time/distance budget, and a way back to the route. Route abandonment is
exactly the kind of thing that looks fine in a unit test and wrecks a 3-hour
sim, so it wants an `economy_traffic`-scale check, not just a scenario test.

---

## A. Identity/standing cluster

**A1 and A3 probably share a cause; A2 probably does not.** Revised once the
colour rule was pinned down — an earlier draft grouped all three, on the
strength of Ironhold's grey contact being "wrong". It is not wrong.

- **A1 + A3** are both about how OTHER ships classify *the player*: a station
  firing, and a patrol demanding ID, are the two things you would expect if the
  player reads as `UNREPORTED`/hostile at spawn. M52's IFF changes are the
  obvious suspect.
- **A2** is about how *the player's UI* classifies Ironhold, and the tactical
  panel gets it right. That points at a rendering path that never consulted
  `Standing`, not at a bad standing value.

Still worth checking whether A2's enemies list is reading the same standing
computation A1 depends on — if it is, the grouping comes back. But do not
assume it; the two have different shapes.

### A1. A station OPENS FIRE if you move — *highest severity*

Starting the campaign and moving triggers station weapons. This should be
impossible against a neutral player at a friendly home station.

> "If you move the station opens fire!!! We definitely uncovered something when
> we disabled IFF."

### A2. Ironhold is classified inconsistently — enemy in one place, neutral in another

Ironhold appears **under the enemies list with a red outline/dot**, while its
**tactical contact renders grey**. Two views of the same entity disagreeing
means at least one classification path is wrong.

**The colour rule is not new — it is the existing `Standing` model.**
`scripts/combat/standing.gd` already defines exactly four states, and
`contacts_panel.gd`'s `_STANDING_COLORS` already maps them to exactly these
colours:

| Colour | Standing | Meaning | Precedence |
| --- | --- | --- | --- |
| **Red** | `HOSTILE` | Hand-marked enemy, or enemy flag (pirates) | 1 |
| **Yellow** | `UNREPORTED` | **No ID**, or an outstanding warrant | 2 |
| **Green** | `FRIENDLY` | Identified and allied | 3 |
| **Grey** | `NEUTRAL` | **Identified, no relationship** | 4 |

Evaluate top-down; only the first matching row applies. **Green vs grey is a
question of STANDING, not of identification** — both are identified, they
differ in relationship. Yellow is the unidentified case.

**Green is sticky, but scoped to the CONTACT TRACK, not to the entity.** The
rule is "while I have held this contact trace, I have seen IFF at some point" —
so a ship that identifies once and then goes quiet stays green for as long as
that track lives, rather than flickering back to yellow between squawks. But if
the track is dropped and later reacquired, the new track starts fresh and must
see IFF again.

That scoping matters and is worth stating explicitly, because it falls straight
out of the sensor model rather than being a UI convenience: `active_contacts`
entries already have a lifetime, already decay, and are already cleaned up
(`contact_tracing_and_cleanup.md`). "Seen IFF" is therefore a flag on the
track, and track death is what forgets it. A hull that goes dark, breaks
contact, and re-approaches from a new bearing is genuinely a new unknown — the
player has not been continuously watching it — and it *should* come back yellow.
Making green an entity-lifetime property instead would quietly defeat going
dark as a mechanic.

One genuine addition to the existing model: **warrants are a separate axis**
(`warrants.gd`) that does not appear in `Standing`. Folding "outstanding
warrant" onto `UNREPORTED`'s yellow overloads one colour with two unrelated
facts. That is acceptable — both mean "treat with caution" — but it is a
deliberate overload, not something the Standing enum already expresses, and the
row TEXT should distinguish them even though the colour does not.

### The actual defect in A2

**The grey tactical contact is CORRECT.** Ironhold is identified and neutral,
which is `NEUTRAL`, which is grey. **The enemies list showing it red is the
bug** — it is not deriving from `Standing`.

(An earlier draft of this document had this backwards, asserting grey was a
colour a station should never take. That followed from reading the rule as
"green = any ID", under which grey had no meaning for a vessel. With grey =
NEUTRAL the model is complete and the tactical panel is the surface already
doing it right.)

**Why the surfaces drifted, and the real fix.** There are at least three
independent colour sources today, and `contacts_panel.gd`'s own comment
documents the split as deliberate: *"standing.gd is phase-1, not ours to
touch... utils.gd's classification_color is shared with the nav/sensor panels
(also out of scope here), so this is its own small const."* Three renderers,
three sources of truth, each individually scoped out of unifying with the
others. That is precisely how two views of Ironhold came to disagree.

So the fix is not to recolour the enemies list. It is to extract ONE function —
standing in, colour out — and have tactical contacts, the nav panel, the sensor
panel, the target list and the enemies list all call it. Anything less leaves
the next surface free to drift.

### A3. `DEMAND IDENTIFY` from Patrol Alpha immediately on campaign start, repeatedly

Two distinct problems:

1. **No dedup.** The demand fires again and again rather than being suppressed
   while already outstanding.
2. **It may not be legitimate at all.** Either the patrol genuinely cannot see
   the player's ID (a bug), or there is a propagation delay between the player
   broadcasting and the patrol receiving.

**Decision:** add a **3-second grace period** — a ship must observe you inside a
port zone with no ID for 3 continuous seconds before it may hail a demand. That
covers the propagation case regardless of which it turns out to be, and it stops
a hair-trigger hail on the first frame of the campaign. Fix the dedup
separately; it is a bug either way.

**Investigate A1 and A3 together.** Both follow if the player is misclassified
at spawn, and A3's "is the hail even legitimate?" question is answered the
moment you know what standing the patrol actually reads on the player. The
3-second grace is worth adding regardless — it is right on its own merits — but
it should not be used to paper over a wrong standing.

---

## B. Weapons safety

Currently `space` (fire all) is live with no guard.

- **Disable fire-all when the ship has no weapons.** Trivial, and it is
  currently a no-op key that reads as broken rather than as "you are unarmed".
- **Add a safety switch to the weapons control section, DEFAULT ENGAGED.**
  Explicit, visible, player-controlled.
- **Do not fire unless the target is a flagged enemy.** Combined with the safety
  switch this is belt-and-braces, deliberately: accidental discharge at a
  neutral station is exactly the kind of "accident" that should be hard to have,
  especially given A1.

---

## C. UI / layout

### C1. Main menu ordering is misleading

The ship dropdown sits **above** the campaign button, implying it applies to the
campaign. It does not — the campaign is hardcoded to a cargo shuttle, and **the
ship selection is ONLY for the sandbox**.

Reorder so the grouping is unambiguous, and label the dropdown as sandbox-only
rather than relying on position alone to convey it.

### C2. Controls menu is far too small

Shoved into a corner and needlessly hard to read. Should occupy a **much larger
percentage of the screen**.

### C3. Hails section should visually match tactical contacts

Today it is hard to tell which row is which ship, which contact is *selected*,
and which rows are present for some other reason. The tactical contacts list
already solves this; the hails section should follow the same visual language
(and ideally the same colour rule as A2, so a ship looks the same in both).

### C4. Engineering log should be at least 2x taller

Expand vertically wherever the layout allows.

---

## D. Removals

### D1. `[ OPEN BROADCAST CHANNEL ]` button — dead UI, remove

**Verified 2026-07-26.** `comms_panel.gd:708`'s `_open_broadcast()` sets a chat
header, prints a single static `-- MONITORING OPEN FREQUENCIES --` line, clears
the response list and adds a DISCONNECT button. Nothing anywhere reads
`"BROADCAST"` as an `active_chat_contact`, and it never calls
`Hail.send_broadcast()` — which does exist in `hail.gd`. The button opens an
empty room.

Remove the button. Leave `Hail.send_broadcast()` alone: it is the comms
substrate and has other callers.

### D2. Port-rules summary in Engineering Diagnostics — remove

"Ironhold control · docking by permission · speed advisory 200" is rendered by
`engineering_panel.gd:416` via `PortRules.banner_summary(rules)`. It does not
belong in engineering diagnostics; the crossing banner already carries it.

Remove the call site only — `PortRules.banner_summary` stays, it is the
banner's own renderer and `test_port_rules.gd` covers it.

---

## E. Naming

Rename **"Missions" → "Contracts"** throughout the UI.

Worth checking whether the underlying `mission_log.gd` / `MissionCatalog`
identifiers should follow. Recommendation: **rename the player-facing strings
only for now**. `contract_feed.gd` already exists as a separate concept, so
renaming the code layer risks colliding two things that are not the same, and
that is a bigger decision than a label change.

---

## Suggested order

1. **A1 + A3 as one investigation** — find what standing other ships actually
   read on the player at spawn. A station shooting you is the worst bug here,
   and the patrol's demand is the same question asked more politely.
2. **A2's shared colour function** — extract standing→colour once and route
   every surface through it. This is small, it fixes the enemies list as a side
   effect, and C3 depends on it (the hails section should use the same colours).
3. **B** — small, and it independently mitigates A1's blast radius. Worth doing
   even before A1 is understood: a safety switch means a misclassification
   costs an awkward moment rather than a destroyed station.
4. **D**, **E**, **C1** — mechanical, low risk.
5. **C2**, **C4**, then **C3** — layout work; C3 last so it can consume the
   shared colour function from step 2.
