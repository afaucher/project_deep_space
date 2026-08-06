# M55e — Boarding & inspection

**Status: SCOPED, not built.** For review before anything lands.

Unblocked by M55a (the manifest) and M55b (theft moves goods), both built
2026-08-05. The roadmap's one-liner was: *"the alongside-hold formalized:
patrols and the player read a surrendered ship's manifest and ask 'does this
look like stolen loot?' Needs M55a; nothing else needs it."*

It also answers **D33**, open since the patrol work: *a patrol's stop must do
something, and `HULK_PRIZE` is only the short-term answer.* And it is the second
half of criterion (4) — *"get meaningful engagements happening consistently —
stopping some pirates — then refine desired outcomes."* The 2026-08-05
re-baseline established the first half (20 HOSTILE-tier interdictions, 10
compliances, 9 guild losses agreeing across subsystems). What a stop *means* is
the unrefined part.

## What an inspection actually asks — and there are TWO questions

The roadmap phrased this as *"does this look like stolen loot?"*, which is a
question about **cargo provenance**. The cheap first cut answers a different
one — **who are you really** — and being clear about the difference is what
keeps the phases honest.

### M55e-1: the flag check (RECOMMENDED FIRST CUT)

**`iff_tags` is ground truth; the transponder is what can lie.** A pirate flying
a cover identity broadcasts a clean name while still carrying `PIRATE_GUILD` in
its own systems. An inspection reads what is aboard rather than what is
claimed — so it is a comparison against data that already exists, with no new
state anywhere:

    what you broadcast  vs  what is in your computers

Nearly free, and it lands on an existing mechanic rather than inventing one:
`colors_chance` is 0.5, so **half of all pirates are flying cover at any time**,
and inspection is the natural counter to exactly those. That also gives the
warrant a real subject — a hull unmasked this way can be booked under its true
identity instead of the cover name, which is precisely the correlation problem
`Ship.debug_label()` exists to work around.

Known and accepted limitation, stated up front: **a pirate that scrubs its own
flag defeats this entirely.** That is M65 (pirate identity kit) territory, and
it is a feature rather than a gap — it makes the arms race legible in both
directions: scrub your computers versus inspect harder. It is a good start
precisely because it will not hold up forever.

**Note what it does NOT answer.** The flag check asks *are you a pirate*, not
*is this cargo stolen*. A clean-flagged pirate carrying someone else's ore
passes it. So this is identity verification, not cargo provenance, and it does
not close the roadmap's original question.

### M55e-later: papers, for cargo provenance

When the flag check stops being enough (M65 will see to that), the provenance
version is: `serve_posting` issues a bill of lading `{station, commodity,
amount, seq}` when it hands over goods; `transfer_loot` moves the GOODS and not
the papers, because a station's signature cannot be forged. Inspection then
compares locally with no lookups:

    cargo you are holding  vs  cargo you can account for
    the difference is contraband

Cheap in its own right (one field on Ship, one write, one comparison), and it
has the right *shape* — M55b's rule is "theft moves goods but not the delivery
obligation", and this is that rule one level up.

Two alternatives considered and not recommended. **Per-lot provenance on the
manifest** complicates both the mixed hold (D60) and `transfer_loot`, and
verifying "you were never at Deepcut" drags in port control logs (M60d).
**Circumstantial** (a warship carrying ore is suspicious) is free but crude, and
useless against the very cover identities the flag check is aimed at.

## Phases

- **M55e-1 — the flag check.** Inspection reads `iff_tags` rather than the
  broadcast transponder, and reports whether the subject's real flag matches
  what it claims. No new state at all. Tests: a cover-flying pirate is unmasked;
  a colours-flying pirate was never hidden; an honest civilian passes; a hull
  that is merely *unidentified* (the CAUTION tier) passes, which is the case
  that decides whether patrols read as police or as harassment.

- **M55e-2 — the INSPECT step.** A verdict of CLEAN or UNACCOUNTED, plus the
  unaccounted volume. **Reuses `_hold_formation`** rather than inventing a third
  hold — D55 exists precisely so a new step cannot inherit a silent
  `deadband = 0.0`, and an inspection hold has the same heat profile as a
  robbery hold. Sequenced after `DEMAND_STOP` in `InterdictLeaf`, so it only
  runs against a subject that actually complied.

- **M55e-3 — consequence.** See the open decisions below. Deliberately its own
  phase: M55e-1 and -2 are mechanism and are safe to land and measure on their
  own, while the consequence is a policy choice that changes campaign behaviour.

- **M55e-4 — instrumentation.** Inspections started / clean / unaccounted,
  **split by tier**, in `EngagementProbe` alongside the existing counters.

## What the measurement already tells us to expect

Two numbers from the 2026-08-05 re-baseline should shape this before it is
built, not after.

**Most inspections will find nothing, and that has to be acceptable.** Of 32
interdictions, 12 were CAUTION-tier — hulls that failed an ID challenge, not
suspects — and CAUTION-tier subjects refuse overwhelmingly (7 of 8 in one run).
So the population reaching an inspection is mostly innocent. If a clean stop
costs the patrol time and heat with no payoff, patrols will read as harassment;
the counters must therefore keep clean and unaccounted separate rather than
folding both into a stop rate, which is exactly the conflation the per-tier
breakdown was added to fix.

**Cargo is not a reliable tell on its own.** D65 measured haulers laden **88%**
of the time, so "carrying something" is the normal state and carries almost no
information. The signal has to be the papers, not the cargo.

## Open decisions — for review, not to be drifted into

1. **What does an UNACCOUNTED verdict actually do?** This is D33. Candidates:
   post/upgrade a warrant (evidence, and the mail network already carries it);
   confiscate the cargo (needs a destination — the patrol's own hold? destroyed?
   and the patrol has flat 4-lot capacity like everything else); or escalate to
   `HULK_PRIZE`, which is today's answer to everything. My lean is **warrant
   first**: it is the cheapest, it feeds machinery that already exists and is
   proven to work (the 2026-08-05 runs notarized 5–10 warrants and reached 8 of
   13 stations), and it makes the *information* economy the consequence rather
   than adding a new one.

2. **Do stations check papers when buying?** If yes, stolen goods cannot be
   fenced in-cluster and the wormhole cash-out becomes the only sink — which is
   what M55b already assumes. If no, a fence economy becomes possible later.
   Recommend **no check for now**, matching M55b, and revisit with M60d.

3. **Does the player inspect too?** The roadmap says "patrols and the player".
   That needs a comms verb and UI, and is separable from the AI path.

4. **Does a clean inspection cost the patrol anything?** Reputationally, with
   the inspected party or its flag. Interesting, and firmly out of scope here.

## Explicitly not in this milestone

**Marines.** *"A warship's quarters bound how many boarders it can put across"*
belongs to the human-capacity sibling milestone, and every warship currently has
zero crew space. Reading a manifest across a hold needs no crew; putting people
aboard does. Keeping them apart also keeps this milestone free of the
catalog/mass work that M55c drags in.
