# M52c — Robbery mechanics: stop meaning stop, alongside meaning alongside

Sub-milestone from the 2026-07-20 pirate playtest (design_ideas/
2026-07-20-pirate_playtest.md). The player got stopped by pirates twice and
both encounters broke the fantasy:

- **Pirate 1 rammed the player and killed itself.**
- **Pirate 2 logged `INTERCEPT done` without ever stopping.**
- Expected instead: match speeds → come alongside (possibly dock) → 10+
  seconds visibly stealing cargo → undock → depart.

## Root causes (read from job_steps.gd, confirmed against the log)

Both bugs are the same missing concept: **the intercept steps have no
relative-velocity control and no standoff distance.**

- `step_intercept` (job_steps.gd) DONEs on `dist <= hail_range` — pure
  proximity. The pirate never decelerates; "intercept" is a drive-by.
- `step_intercept` and `step_demand_stop` both steer via
  `_cruise_toward(actor, victim_pos, ...)` — dead at the victim's CURRENT
  position, no lead, no standoff radius. Against an AI victim that
  complies (stops dead), the pirate arrives at a stationary point: fine.
  Against a moving PLAYER, it's a pursuit curve that terminates in the
  player's hull — the ramming death was structural, not bad luck.
- `step_take_alongside` holds station near a victim that is already
  STOPPED (`_hold_station` + in-range check against a compliant target).
  The "match speeds and lock on" behavior the playtest expected for the
  stop itself simply doesn't exist anywhere in the chain.

## Behaviors to build

1. **Standoff intercept.** INTERCEPT closes to a standoff point OFFSET
   from the victim (e.g. 300–500u abeam), never the victim's own position,
   and DONE requires BOTH inside-hail-range AND relative speed under a
   threshold — an intercept you can't collide out of and can't flyby
   through. This is the piracy-job twin of the docking approach problem
   the port work already solved once (keep-out cone, approach geometry) —
   steal the shape, not the code.
2. **Speed-match hold during the stop.** DEMAND_STOP against a still-moving
   victim should PACE it (match velocity at the standoff offset), not
   chase its position — the pirate flies formation while the demand
   clock runs. A victim that complies decelerates; the pace naturally
   becomes a stationary alongside. A victim that runs opens the gap and
   the existing outpaced/patience aborts fire unchanged.
3. **The visible robbery.** TAKE_ALONGSIDE gets its theater: hold_time
   raised to 10s+ (playtest ask), and the hold requires the alongside
   station actually kept (drift out of the envelope pauses the clock —
   already true — but the envelope tightens to genuinely-alongside, not
   600u "nearby"). Whether this becomes a REAL ship-to-ship dock
   (DockingBay-style capture between two ships) is this milestone's one
   open design call:
   - **Soft-dock (recommended first step):** formation-lock at a fixed
     offset — pirate zeroes relative velocity and holds the offset
     rigidly (same station-keeping the docking bay's capture spring
     approximates), no physics joint. Cheap, robust, reads correctly at
     game scale.
   - **Hard-dock:** an actual DockingBay-style capture between hulls.
     Real contact, real constraint — but ship-to-ship docking machinery
     (moving bay, mutual approach, undock push against a mobile partner)
     is new physics surface with M28-30-collision-era risk written all
     over it. Defer unless soft-dock reads badly in play.
4. **Autopilot dead stop (player-side).** A pirate/patrol stop is the
   first real reason the PLAYER needs a one-input "kill all velocity"
   (playtest: "a good reason to implement autopilot dead stop"). Helm
   gains a DEAD STOP autopilot mode (the M37 autopilot already owns
   velocity control; this is a new target-state, not new machinery).
   Complying with a stop becomes: press COMPLY, ship brakes itself.
   This also gives step 2's speed-match something stable to pace.

## Tests

- Intercept standoff: pirate vs a scripted straight-line mover — closes to
  standoff, relative speed under threshold at DONE, zero hull contact over
  the encounter (margin-based; collision damage = instant fail).
- Ramming regression: the exact playtest shape — victim holds course
  through the demand — pirate paces alongside, never collides, patience
  abort fires cleanly if no compliance.
- Robbery theater: complied victim → pirate closes to alongside envelope,
  10s hold accumulates only inside it, RELEASE + departure after.
- Dead stop: from cruise, engage DEAD STOP → velocity under threshold
  within expected braking time, holds against drift.

## Fiction parked here (from the playtest, not this milestone)

- **Pirates physically comm in.** The guild stops getting "filed reports"
  for free: check-ins require the member to reach comms range of a relay/
  contact. Full fiction — pirate CONTACTS embedded on stations; the
  pirate must physically reach them to report, and finding/removing these
  people literally tears down the pirate network's information layer.
  Player-facing counter-piracy content; needs the M53a traffic world
  first. Goes with the guild honesty rule (pirate_guild.gd's ledger) —
  the ledger's check-in mechanism is already shaped for this, it just
  currently pretends range is infinite.
