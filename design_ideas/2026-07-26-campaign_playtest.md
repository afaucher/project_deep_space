# Campaign playtest — 2026-07-26

First-run feedback on starting the campaign, plus menu/UI issues found along the
way. Companion to [2026-07-20-pirate_playtest.md](2026-07-20-pirate_playtest.md).

Ordered by severity, not by the order they were reported.

---

## STATUS: all nine items closed — *2026-07-27*

| Item | | Where |
| --- | --- | --- |
| A1 | station opens fire if you move | three independent layers, see below |
| A2 | inconsistent classification | one tier table drives colour AND section |
| A3 | repeated `DEMAND IDENTIFY` | same root cause as A1 |
| B | weapons safety | console interlock, all three control routes |
| C1 | menu ordering | declarative order list + sandbox-only labelling |
| C2 | controls menu too small | proportional anchors, was a `CenterContainer` |
| C3 | hails match tactical contacts | shared `Utils.contact_color` |
| C4 | engineering log height | floor doubled + expand-fill |
| D1 | dead broadcast button | removed |
| D2 | port rules in engineering | call site removed |
| E | "Missions" → "Contracts" | player-facing strings |

**A1 turned out to be three separate defects**, not one: the challenge convicted
hulls that had left comms range, `NO_ID` painted them red, and HOSTILE was
treated as a firing authorization. Each is independently sufficient to produce
the reported behaviour, and each is now guarded.

Two things found during the investigation are NOT in the original list and
remain open — the player never receives the police-stop exemption (see below),
and the escalation ladder still has no middle rung. Both are recorded in
TASKS.md.

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

### A1 part two: the aggression cap exists and never reaches the trigger — *open, verified 2026-07-27*

Why a NO_ID warrant gets you **shot** rather than intercepted. The
proportionality cap is authored and is enforced in exactly one place, which is
not the place that fires.

`standing.gd` defines two response tiers and a `response_class()` accessor:

| Tier | Offences |
| --- | --- |
| `RESPONSE_INTERCEPT` (1) | `NO_ID`, `ASSAULT`, `ARMED_THREAT`, `SPEED_VIOLATION`, `OPERATOR_FLAGGED` |
| `RESPONSE_MAX` (2) | `SUSTAINED_ASSAULT`, `ARMED_ROBBERY` |

**The only consumer is `interdict_leaf.gd:114`**, which reads it to decide
whether to skip the demand and go straight to force. Nothing else reads
`"response"` anywhere.

Meanwhile `compute_standing` returns **HOSTILE for any warrant**, tier ignored,
and `acquire_target_leaf` engages on `standing == HOSTILE` full stop. So the
mildest offence in the table — the one authored to mean *intercept* — is
indistinguishable at the targeting gate from armed robbery.

**This is the exact defect the warrant model was built to retire**, surviving one
layer lower. `warrants.md` opens by naming M48's failure as "a speeding
freighter and a serial killer get the same bit." Warrants fixed that in the
STANDING computation and left the trigger collapsing it back down.

**The intended model, stated 2026-07-27 — this answers the open question about
stations.**

> A station issues a warrant; a patrol interdicts if not complied with. NO_ID
> should self-resolve most of the time, once the ship lights its transponder.
> Docking permission should probably require it.

So a station **posting the warrant IS its enforcement action**. It has no
business shooting an unidentified hull, and it does not need an interdict path
of its own — delegation to a patrol is the design, not a gap in it. That makes
the targeting-gate fix simpler than feared: weapons only for `RESPONSE_MAX`, and
`RESPONSE_INTERCEPT` is a patrol's job, not a turret's.

**Enforcement is denial of service, not gunfire.** That is the part currently
missing, and it is what gives a capped response teeth without violence:

- **`NO_ID` self-resolves on ID.** Already authored (`self_resolves_on_id: true`)
  and the mechanism is described at length in `standing.gd` — the `sig:`-keyed
  warrant is deliberately unreachable by `name:` lookup once a transponder
  arrives, which IS the resolution. **Worth a test**: it is load-bearing for the
  whole model and currently proven only by the code comment.
- **Docking permission should require ID — unbuilt.** `Ship.issue_docking_grant`
  checks slip availability and grant idempotency and nothing else: no
  transponder check, no standing check. Requiring ID for a grant turns "go dark
  and squat in controlled space" into a choice with a real cost — you can be
  anonymous or you can dock, not both — and it is exactly the kind of pressure a
  station can apply on its own authority.

#### BUILT 2026-07-27

All three landed together, because they are one mechanism: capping the response
to `NO_ID` removes the (wrong) consequence, so the right consequence has to
arrive in the same change or "run dark" becomes free.

- **`Standing.authorizes_force(offense)`** — the cap itself, a new column on the
  offense table. `AcquireTargetLeaf` consults it before treating a HOSTILE
  contact as a weapons target. A contact HOSTILE with **no** matching warrant
  (a declared enemy flag, or the one-tick eager cache stamp) stays uncapped.
- **Identify to dock** — `Ship.issue_docking_grant` denies a hull that is not
  reporting a transponder, ahead of the idempotent-renewal branch so going dark
  also stops a held grant being renewed. `PortControl` surfaces a distinct
  `no_id` outcome so the player is told the real reason rather than "no berths".
- **Tests** — `test_aggression_cap` (the table, plus the leaf ticked directly
  against an identical contact so only the offense varies),
  `test_patrol_challenge` phases 4–5 (the comms-range regression guard, with a
  non-vacuity assertion that the subject is still SEEN, and the live NO_ID
  self-resolution), `test_docking_permission`'s identify-to-dock block.

**The plan above was wrong on one point, and it matters.** "Weapons only for
`RESPONSE_MAX`" would have broken self-defense: `ASSAULT` — *they fired on us* —
is `RESPONSE_INTERCEPT`, so a ship being shot at could not have shot back.
Response class turns out to encode **patience** (how long the demand ladder
runs), not **permission**, and the two genuinely cross: `ASSAULT` and `NO_ID`
share a response class and must differ on force. Hence a separate column rather
than a reinterpretation of the existing one. It defaults to `false`, so a future
offense whose author forgets it produces "my patrol won't shoot" — loud and
trivially diagnosed — rather than another silent civilian-shooting.

Scoped deliberately to **identity, not standing**: a berth is denied for running
dark, not for carrying a warrant. Denying port access to every hull that has
ever been in a fight is a much larger economic change (repair and cargo flow,
pirates included) and wants its own measured pass.

Still open: NO_ID's *effectiveness* now rests entirely on the docking denial,
since nothing shoots and nothing pursues. If that proves too weak in play, the
missing middle rung below is the fix, not a higher response class.

#### BUILT 2026-07-27 (second pass): the yellow tier

The flat-`HOSTILE` shape question above is now answered, because a design
decision made it load-bearing rather than merely tidy: **a ship demanding your
submission turns yellow, always — including a legitimate police action.** From
the receiving end you cannot tell police from a pirate in colours, and that
unresolvable ambiguity IS what yellow means. Escalating to red is the
observer's own threshold, which is where per-flag enforcement rules will live.

That fixes the playtest bug a second time, further upstream: a `NO_ID` hull is
never painted red at all, so nothing ever considers it a target. The aggression
cap became the backstop rather than the only line of defence.

- **`Standing.CAUTION`** — an ALIAS for the existing yellow tier, not a fifth
  tier. The four tiers are epistemic states (you know / reporting-and-clean /
  cannot resolve / determined enemy) and `UNREPORTED` was only ever one cause of
  the third. Same string, same severity, so the datalink and every colour
  consumer are untouched. The constant rename is deferred to its own commit.
- **An offense-table `standing` column** — the default yellow/red threshold.
  Kept separate from `authorizes_force` even though the two agree row for row
  today; they are the two halves of per-flag rules, and collapsing them would
  cost that axis.
- **Precedence, which was the trap.** A caution-grade warrant is HELD, not
  returned: returning early would let a minor warrant MASK the known-enemy-flag
  rule, so a pirate who had also picked up a `NO_ID` would read yellow. Caution
  loses to every more-severe rule and only beats `NEUTRAL`.
- **Interdiction follows the warrant; engagement follows the standing.** Making
  `NO_ID` caution-grade silently deleted the patrol's whole response to it,
  since `InterdictLeaf` gated on `HOSTILE`. It now demands a stop from anyone we
  hold an enforceable warrant against at any tier — so a silent hull is
  intercepted and hailed and never shot at. The warrant requirement is
  load-bearing: caution is also what an ordinary non-reporting contact reads,
  and gating on the tier alone would have every patrol demanding a stop from
  every unidentified ship in the cluster.
- **Response priority — red threats, then SOS, then yellow.** `Interdict`/
  `JobRunner` sit above `Engage` and `SOSResponse`, which was correct while a
  demand job was a red matter by definition. Caution-grade work would otherwise
  pre-empt a firefight and a distress call and hold the slot for the full 25s
  patience. The tree is NOT reordered (one assignment slot, one runner — moving
  the assigner changes nothing because the runner above `Engage` still executes
  it); instead yellow work is not started while outranked, and is abandoned if
  outranked mid-run. Its refusal memory is cleared on yielding: a demand broken
  off to go deal with a pirate was never pressed, and leaving the entry would
  retire that interdiction permanently.

### Also found: the player can never receive the police-stop exemption — *open, found 2026-07-27*

`authority_flags` is documented as "flags this observer considers a legitimate
interdiction authority (**home civilians trust the militia flag**)". It is
authored on exactly one entity template — the NPC traffic haulers
(`home_cluster.gd`) — and `main.gd`'s `_spawn_player_ship` never sets it, so the
player's list is empty.

So when a home patrol lawfully demands the player stop, `police_stop` evaluates
false and the player's ship posts an `ARMED_THREAT` warrant against the patrol.
The NPC haulers get this right; the one ship where it matters most does not.

The yellow tier dropped the severity considerably — a lawful stop now reads
CAUTION rather than HOSTILE, so the patrol no longer paints red — but the
player still treats lawful police differently from every NPC civilian, which is
wrong regardless of colour.

**Do not fix by handing the player `authority_flags = [FLAG_DRIFT]`.** The
intended resolution is to show the authority CLAIM that already rides every
hail and let the player judge it — see `design_ideas/comms_verbs.md`, "the
authority claim rides the hail". Hardcoding a trust list onto the player's hull
would settle the bug and forfeit the more interesting mechanic.

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

#### BUILT 2026-07-27 — and it was FOUR copies, not three

The prescription above was right; the count was low. Beyond the three colour
sources there was a fourth and fifth rule in `contacts_panel.gd` itself: the
**section bucketing** and the **tab-cycle ordering**, both keyed on
classification. So Ironhold filed under "Enemies" while being painted grey *in
the same panel* — the literal contradiction, sitting in one file.

**It was never one station.** `classify_contact()` returns `UNIDENTIFIED
VESSEL` for any live vessel with no IFF crypto handshake, including a fully
identified, reporting, NEUTRAL one. So every neutral station and civilian in
the cluster drew red on the nav map and filed under Enemies. Ironhold was just
the one that got noticed. That is why this outranked the remaining playtest
items once A1 was closed: the map was lying about the whole world.

**One tier resolution, two consumers.** `Utils.contact_tier()` maps a contact
to a tier; colour and section are both looked up from a single registry where
each tier declares them on the same row, so they cannot be separately
maintained and cannot drift. Section ORDER moved to `Utils.CONTACT_SECTIONS`
for the same reason — the panel's parallel section list is *how* the bucketing
drifted from the colouring. `test_contact_tier` asserts every tier resolves to
both a colour and a real section, so a future tier that defines one and forgets
the other fails in the gate rather than shipping.

A new **"Alerts"** section sits between Enemies and All Contacts, holding the
CAUTION tier and distress calls. Fixed in passing: an SOS from a friendly ship
used to file under All Contacts while being painted SOS-orange.

Still open, deliberately: `INCOMING ORDNANCE` carries no standing, so it stays
in All Contacts. Arguably the most urgent thing on the board and a candidate
for Alerts — but unchanged from before, so not a regression.

**C3 is now unblocked** — the hails section can consume `Utils.contact_color`.

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
