# Hulk revival: the contract a salvage mechanic must honor

Status: design note, no implementation. Written alongside the lean-hulk-tick
perf work (see `git log` around the combat perf investigation) so the
invariant that work relies on is recorded where a future salvage/revival
milestone will find it.

## The invariant

**While `is_dead` is true, every component is unpowered.**

This is enforced today by exactly two doors:

- `hulk()` forces `powered_on = false` on every component on entry.
- `set_component_power` refuses dead ships.

(Repairs also refuse hulks today — M40's "never heal a hulk" — but that rule
is about healing, not power; revival will relax it. See below.)

Two performance paths in `Ship._physics_process` are **exact reductions** of
the live simulation under this invariant, keyed on `is_dead` per tick:

- The lean hulk heat/EM branch (skips the rating/sys-health scans, which are
  provably zero when nothing is powered; keeps damage-heat decay, the
  reactor whiteout pulse, the damaged-engine EM stutter, weapon fire-pulse
  decay, and passive cooling).
- The steering-block thrust/torque shortcut and the sensor-sweep efficiency
  shortcut (both short-circuit to the 0.0 the scans would compute).

Because these key on `is_dead` **every tick** and cache nothing, a ship whose
`is_dead` flips back to false resumes the FULL live simulation on the very
next physics tick with no cleanup required. Revival is therefore cheap and
safe -- as long as the invariant holds right up to the flip.

## What revival must look like

An explicit, atomic transition -- the mirror of the death check:

```
func un_hulk() -> bool:   # sketch, not implemented
    if not is_dead: return false
    # inverse of take_damage()/overheat's death rule:
    if is_sys_destroyed("reactor") or is_sys_destroyed("hull"): return false
    is_dead = false
    log_event(ENG_LOG_SEVERITY_CRIT, "Reactor restart -- systems returning")
    # optional: EM flare (reuse the reactor-whiteout shape) so observers see
    # the derelict light back up -- WRECKAGE reclassifying to VESSEL on the
    # contacts panel is the whole dramatic payoff of a salvage mechanic.
    return true
```

Power stays OFF through the transition; the engineer (player or AI) turns
components back on afterward through the normal `set_component_power` path,
which works again the moment `is_dead` is false.

## The one forbidden design

**Do not stage a revival as "power components on first, then declare it
alive."** Powering anything while `is_dead` is still true violates the
invariant: the lean heat/EM path would run a powered, EM-emitting reactor
through code that assumes all contributions are zero -- the hulk would emit
nothing, classify as WRECKAGE while functionally live, and the bug would be
silent. Keep `set_component_power`'s dead-gate exactly as it is and make
`un_hulk()` the only door back.

## Everything else a revival milestone touches

- **Repairs**: M40's `begin_repairs` refusal on hulks becomes the salvage
  gateway instead -- repairing a hulk's reactor/hull to >0 health is what
  makes `un_hulk()`'s precondition pass. Healing while dead is fine under
  the invariant (the lean path reads health only for decay/stutter shapes,
  never power).
- **Missile despawn**: dead missiles despawn after `WRECKAGE_LINGER`
  (missile_controller.gd). If missiles are ever salvage targets (unlikely),
  the linger clock must pause while a salvage claim is active.
- **AI**: a reviving hulk re-enters threat space -- acquire/disengage logic
  currently trusts WRECKAGE classification to mean "permanently inert."
  The EM-based classifier handles the sensor side for free (powered reactor
  -> EM-loud -> VESSEL), but AI memory of "that contact is dead" (if any is
  ever added) must be invalidated by the reclassification, not by contact id.
- **Eng log / story**: `hulk()` logs "Catastrophic failure" once via
  `_eng_was_hulk_logged`; `un_hulk()` must reset that latch so a second
  death logs again.
- **Docking/berths**: a hulk revived inside a station's bay or port zone
  re-enters grant/zone logic on the next tick (those blocks are also gated
  on `not is_dead`) -- no special handling expected, but worth a test.

## Test to write when this lands

Kill a frigate (reactor intact, hull intact -- e.g. sensor/weapon attrition
death is impossible today, so cook it via overheat then cool it), repair it
above the death threshold, `un_hulk()`, and assert: EM signature climbs back
above `ACTIVE_EM_THRESHOLD`, an observing ship's contact reclassifies
WRECKAGE -> VESSEL, thrust works, and a second `hulk()` logs a second
catastrophic-failure line.
