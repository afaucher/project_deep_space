# M65 — Pirate identity kit management

## Why this is its own milestone

Identity is currently a **decorative field**. Making it real changes pirate
behaviour, retires a posture when exhausted, and renegotiates a contract an
existing test pins — too much blast radius to fold into targeting work.

## What is actually true today (verified 2026-08-04)

| Claim | Source |
|---|---|
| A member's cover name is `kit[0]` and **nothing else in the kit is ever read** | `pirate_guild.gd` spawn path — `var cover_name: String = kit[0] if not kit.is_empty() else ""` |
| `relight_name` appears in **two comments and no code** | grep: only the `members`/`arrivals` shape comments |
| `_provision_kit()` mints a **fresh kit per arrival** | so papers are effectively **infinite** |
| Therefore `identity_kit_size` (default 3) **has no consequence whatsoever** | nothing consumes past index 0 |
| Nothing anywhere marks a name burned | `issued_names` only prevents RE-ISSUING the same string |
| Docking does not check warrants | `port_rules.gd` has no warrant/standing/flag reference at all |

So D17 and D20 ("the kit is the single currency for cover-running and
prize-taking"; "kit size as the real dial on pirate aggression") describe a
mechanic that does not exist yet.

**Already built (2026-08-04), and it is the reason this milestone now matters:**
`_roll_posture(has_clean_identity)` returns DARK_LURK when the kit is empty. A
false-flag cruise IS a cover identity, so with no paper there is nothing to
broadcast and the posture would be a false flag with no flag — strictly worse
than dark-lurk, which at least conceals. That gate is live and tested; it simply
never fires today, because papers never run out.

## The model

**A paper is burned by USE, not by getting caught.** You flew a lane
broadcasting that name; a port's arrival registry may hold it and anyone who
looked at you saw it. Waiting for a warrant would require the guild to LEARN it
is wanted — a mail question it has no channel for — whereas "I flew under this"
is first-hand knowledge the director honesty rule explicitly permits ("only its
own members").

```
band holds a finite stock of clean papers
  arrival draws one and burns it
  stock empty -> cover_name "" -> _roll_posture -> DARK_LURK
                                -> no false-flag cruise, no LANE_RUN
```

## The decision this forces — REPLENISHMENT

With no refresh, a band runs dry after `identity_kit_size` arrivals and every
pirate is dark-only for the rest of the campaign, silently retiring LANE_RUN and
half the tradecraft. With too fast a refresh, papers are free again and nothing
changes.

`paper_refresh_seconds` is therefore the real dial on **how much covert
operating a band can sustain**, and it wants a sweep rather than a guessed
constant. This is the milestone's central number and should not be picked by
whoever writes the code.

## Scope

- **M65a — a finite band stock.** `clean_papers` / `burned_papers` on the guild,
  seeded to `identity_kit_size`, drawn from at arrival.
  **Renegotiates `test_pirate_guild`'s "full identity kit aboard (N papers)"
  assertion** — that test currently pins the infinite-kit contract and caught an
  inline attempt to change it. Update it deliberately, do not delete it.
- **M65b — back-channel replenishment.** `_refresh_papers(dt)` from the policy
  tick, capped at `identity_kit_size`. Sweep the rate.
- **M65c — RELIGHT actually draws a paper.** The exfil tail already has
  `{"verb": "RELIGHT", "from_kit": true}` but no kit is consumed, so laundering
  is free. It should cost a paper, which makes escaping-under-a-new-name a real
  expense rather than a formality.
- **M65d — burned names refused at the dock.** `port_rules.gd` gains a
  `warrant_index` lookup on the claimed name, using the same
  `Standing.subject_key` path `InterdictLeaf` and `AcquireTargetLeaf` share so
  it cannot drift. **A name is then burned PORT BY PORT as the news reaches
  each port** — the pirate keeps docking at Coldreach while Ironhold has already
  closed its doors. No new state: same warrant, same fog, same clamped read.
- **M65e — the guild tracks where it is still welcome.** Which is a decaying,
  partial picture, and therefore M60d's business. A band that has not heard its
  own name is burned will fly into a refusal — a good failure, not a bug.

## Measurement

- papers spent per game-hour, and how often a band is dark-only for lack of one
- share of hunts by posture, before and after — LANE_RUN should become
  **occasional rather than default**, which is a behaviour change to watch for,
  not a regression
- dock refusals per game-hour once M65d lands

## Interacts with

- **D17 / D20** — this is what makes both real.
- **D39 / LANE_RUN** — the posture becomes conditional on having paper. Expect
  encounter volume to FALL when papers are scarce; that is the intended cost,
  and it must be weighed against D38's finding that lane-running is what raises
  encounters in the first place.
- **M60d** — the dock leg needs a clean paper to dock at all, and M65e's
  "where am I still welcome" is exactly the kind of stale partial knowledge that
  network carries.
- **D7 / D37** — going dark still defeats notarization, so a dark pirate burns
  no paper. Concealment stays a real defence and keeps costing credibility.
