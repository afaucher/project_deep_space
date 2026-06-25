# M2: Dynamic Per-Component Heat & EM — Design

Source doc: `design_ideas/responsive_heat_em.md`. Depends on M1/M1b (per-component
mass/power/thrust/torque/heat helpers) and M1c (`WeaponBehavior` registry).

## Where things actually stand today

M1b fixed the *steady-state* pooled-overwrite bugs for reactor and engine
heat/EM (each component now gets its own apportioned share instead of the
ship-wide aggregate stamped into every component of that type). What's left
is the *event-driven* half of `responsive_heat_em.md`'s four cases, plus one
real bug and one architectural inconsistency found while auditing the
current code:

1. **Combat heat is discarded every frame — unfixed bug.** `take_damage()`
   increments `comp["heat"]` on hit (`ship.gd:395`), but the heat/EM dispatch
   loop in `_physics_process` unconditionally **overwrites** `comp["heat"]`
   for every component every frame (`ship.gd:701-720`), including
   force-zeroing it for hull (`else: comp["heat"] = 0.0`). A laser hit's heat
   burst currently survives less than one physics tick.

2. **Weapon fire already has an EM pulse mechanic — it's just never read.**
   `LaserBehavior.execute_fire()` sets `comp["em_pulse"] = FIRE_EM_SPIKE`
   (50.0), and `LaserBehavior.tick()` decays it at 25.0/sec and folds it into
   `comp["em_emission"]`. That's a real, already-working transient spike +
   decay — but the ship-wide `em_signature` computation
   (`ship.gd:690-699`) only sums reactor/engine/sensor/passive contributions
   and never reads `weapons`-type `em_emission` at all. The pulse fires,
   decays, and is invisible to every sensor. `MissileBehavior` has no
   equivalent pulse (uses the base no-op `tick()`).

3. **Sensor heat is flat, not zero-effort but not meaningful either.**
   `comp["heat"] = b_heat + 5.0` for every active sensor (`ship.gd:712`) —
   each sensor does get its own assignment (not pooled), but the `5.0` is a
   constant unrelated to the sensor's own rating/size, so two very different
   sensors run equally hot. Sensor EM is already correctly per-component
   (`base_em_emission * sensor_power_ratio`). Only heat needs a real basis,
   and it's low priority compared to 1 and 2.

4. **Engine damage doesn't spike EM — it suppresses it.** The current
   formula is `comp.get("power_rating", 0.0) * health_ratio`: as
   `health_ratio` drops toward 0, emission drops toward 0. The design doc
   wants the opposite — a damaged engine running rough should spike, not go
   quiet. Needs a damage-proportional *addition*, not just the proportional
   baseline term.

5. **Reactor destruction has no whiteout pulse at all.** Nothing currently
   triggers on a reactor's health crossing 0 beyond the existing (M1b-fixed)
   overheat-damage drain.

## Decision: unify EM directionality across all emitters — IMPLEMENTED

Today there are two incompatible EM models live at once:

- Reactor/engine/passive are summed into one ship-wide scalar
  (`em_signature`), and the receiver applies a single ship-rotation rear-bias
  dipole to the whole blob (`ship.gd:881-884`) — no per-source direction.
- Active sensors are already fully directional: each sensor's own
  `em_emission` is added as a cone-falloff spike using its own
  `heading`/`arc_width`, layered on top of that scalar
  (`ship.gd:886-895`).
- Weapons emit no EM into detection at all (see finding #2 above).

**Decision: generalize the sensor-cone mechanism to every EM-emitting
component**, rather than keeping sensors special-cased forever.

`em_pattern` ended up **derived from `comp["type"]`, not an authored field**
on every component dict — it's purely a function of type (same call every
time for every reactor/engine/passive vs. every sensor/weapon), so adding a
literal `"em_pattern": "omni"` to ~25 component dict literals across
`ship.gd`/`missile.gd`/`sensor_drone.gd` would have been pure duplication.
Instead, `Ship._is_directional_emitter(comp)` answers it with one type
check:

```gdscript
func _is_directional_emitter(comp: Dictionary) -> bool:
	return comp["type"] == "sensors" or comp["type"] == "weapons"
```

`Ship._received_em_power(comp, target_rotation, angle_from_target)` applies
the rear-bias dipole for omni sources or the cone falloff (reusing the
component's own `heading`/`arc_width` — weapons already had these for
engagement-arc gating, no new fields needed) for directional ones.
`Ship._total_received_em(sig, angle_from_target)` sums that across
`sig.get("em_emitters", [])`. `get_signature()` now exposes `em_emitters` as
the concatenation of `reactor`/`engines`/`sensors`/`weapons` components,
replacing the `sensor_config`-only list. `_run_sensor_sweep`'s two duplicated
rear-bias/cone-spike blocks collapsed into one call to `_total_received_em`.

**Two bugs found and fixed along the way, beyond the planned scope:**
1. The pre-raycast block in `_run_sensor_sweep` computed an EM value that was
   never read by anything (no early-exit check used it) — pure dead code,
   removed.
2. More importantly: the directional/distance-falloff computation was
   previously used **only as a detection threshold gate**, never stored back
   into the signature. Once a target was detected, the classifier and any
   display code read the target's *raw, undirected* `em_noise` value — so
   direction affected *whether* you saw something, never *what value* you
   saw. Fixed by writing the actually-received (direction + distance
   falloff applied) value back into `sig["em_noise"]` before it flows into
   bin aggregation and `classify_contact()`. This is a real behavior change:
   off-axis or distant contacts now report a lower EM signature than before,
   which is what "directional EM" should have meant the whole time.

Also found: `s_heading` in the old sensor-only cone code used the target's
*local* sensor heading with no `+ collider.rotation` term — wrong unless the
target happened to be facing world-zero. `_received_em_power` computes
`target_rotation + comp.get("heading", 0.0)` correctly; this bug doesn't
recur in the unified path.

## Event-driven pulses (responsive_heat_em.md's four cases)

| Case | Status |
|---|---|
| Fire a laser → EM pulse | **Done.** `weapons` are in `em_emitters`; the pulse is directional for free via the weapon's `heading`/`arc_width`. `MissileBehavior` got the same `em_pulse`/decay mechanic (smaller magnitude, shorter decay — a launch flash, not a beam). |
| Fire a laser → waste heat | **Done.** `LaserBehavior.execute_fire()` adds to `comp["damage_heat"]` — the *same* accumulator/decay mechanism as a combat hit (see below), not a second parallel system. |
| Hit by laser → heat burst | **Done.** `take_damage()` writes to `comp["damage_heat"]`; `Ship._decay_damage_heat(comp, delta)` decays it once per frame and every dispatch-loop branch (including the former hull force-zero `else` branch) adds the decayed remainder instead of overwriting. |
| Damaged engine → EM spike | **Done, as an oscillation, not a flat addition** — see below. |
| Reactor destroyed → 1-2s whiteout | **Done.** `Ship._update_reactor_whiteout(comp, delta)` detects the health crossing from alive to dead via a per-component `_prev_health` field, fires a one-shot pulse scaled to that reactor's own `power_rating` (`REACTOR_WHITEOUT_MULTIPLIER := 5.0`), and decays it to zero over a fixed `REACTOR_WHITEOUT_DURATION := 1.5`s regardless of reactor size (a fixed per-second decay rate would make bigger reactors' pulses linger longer for no reason, so the decay rate itself is computed once at trigger time as `magnitude / DURATION`). |

Four of the five reuse one mechanical shape — *fire/trigger sets a
magnitude, decay logic ticks it down, the steady-state term adds rather than
overwrites*. The engine-damage case is the deliberate exception: a
continuous oscillation whose amplitude *and* frequency are driven by current
damage, with no discrete trigger event.

### Engine damage → EM spike, as oscillation not flat addition

A flat `(1.0 - health_ratio)` additive term was the first idea, but it just
makes "damaged" look like a *second, higher* constant — not a sign of
something behaving erratically. Instead: keep the existing
proportional-to-health baseline (still legitimately drops with damage), and
add a rectified, damage-scaled oscillation on top (`Ship._engine_damage_oscillation`):

```gdscript
const ENGINE_OSC_FREQ_BASE := 0.2   # Hz, lightly-damaged flicker rate (~5s period)
const ENGINE_OSC_FREQ_RANGE := 0.6  # Hz, added at 100% damage -> max 0.8Hz (~1.25s period)
const ENGINE_OSC_GAIN := 1.0        # crest height relative to power_rating at 100% damage

func _engine_damage_oscillation(comp: Dictionary, health_ratio: float, delta: float) -> float:
	var damage_ratio = 1.0 - health_ratio
	if damage_ratio <= 0.0:
		comp["em_osc_phase"] = 0.0
		return 0.0
	var osc_freq = ENGINE_OSC_FREQ_BASE + damage_ratio * ENGINE_OSC_FREQ_RANGE
	var phase = comp.get("em_osc_phase", 0.0) + TAU * osc_freq * delta
	comp["em_osc_phase"] = phase
	return absf(sin(phase)) * damage_ratio * comp.get("power_rating", 0.0) * ENGINE_OSC_GAIN
```

Three deliberate choices, one of them a correction from the original sketch:
- **Rectified (`absf(sin(...))`)**, not raw sine, so the term only ever adds
  on top of the already-lowered baseline — damage never makes the signature
  *quieter* than damage alone would.
- **Frequency stays under 1Hz even at 100% damage** (0.2Hz-0.8Hz), and rises
  with damage rather than just amplitude — a lightly-damaged engine pulses
  slowly (~5s), a badly-damaged one visibly faster (~1.25s). This is
  deliberately *player-visible*, not noise: most sensors refresh at or
  faster than 1Hz (`refresh_interval` ~0.1-1s on existing components), so a
  sub-1Hz wave is sampled densely enough to read as an actual rising/falling
  pulse, not aliased into random-looking jitter.
- **Phase is its own running accumulator (`comp["em_osc_phase"]`), not
  wall-clock time.** The original sketch used `Time.get_ticks_msec()`
  directly, which makes the phase at the moment of injury depend on how long
  the ship has existed — not reproducible, and impossible to unit test
  deterministically. Accumulating `TAU * osc_freq * delta` per frame instead
  means the stutter restarts cleanly from phase 0 whenever a fresh injury
  triggers it (the phase resets to 0 once health is no longer damaged, too),
  which is both the more sensible in-fiction behavior and what let
  `test_component_states.gd` assert exact phase-relative values (e.g. "near
  baseline at frame 1," "near peak at frame 24") instead of a wider
  statistical check.

## Heat model open questions — resolved

`responsive_heat_em.md` asked: does heat build up per-component, bleed
between components, and is the cap per-component or ship-wide?

- **No inter-component heat bleed.** Thermal conduction between adjacent
  components is real-world realism the current scope doesn't need — keep
  heat generation/dissipation purely ship-wide (`current_heat`/`max_heat`,
  already established pre-M1b), with per-component `heat` values feeding
  sensor signature only, not a second damage model.
- **Cap stays ship-wide.** The existing overheat behavior (ship-wide
  `current_heat >= max_heat` damages reactors, M1b-fixed dead-id-check) is
  the only heat-driven damage path and should remain the only one.
  Per-component `heat` is a *display/signature* quantity, not a second
  per-component thermal limit, until a concrete need for one shows up.

## Task breakdown — all done

1. ✅ Fixed the combat-heat overwrite bug: `damage_heat` accumulator,
   additive not overwritten, decaying each frame (`_decay_damage_heat`).
2. ✅ `em_pattern` ended up derived by type (`_is_directional_emitter`), not
   an authored field — see the directionality section above for why.
3. ✅ `em_emitters` added to `get_signature()`; the cone/rear-bias split in
   `_run_sensor_sweep` collapsed into one loop (`_total_received_em`) over
   it. Also fixed: dead pre-raycast EM computation, and `em_noise` not
   reflecting direction/distance falloff once a target was already detected.
4. ✅ `weapons`-type `em_emission` flows through the unified emitter list;
   `MissileBehavior` got its own fire pulse (`FIRE_EM_SPIKE := 30.0`,
   `EM_PULSE_DECAY := 15.0`/sec).
5. ✅ Laser fire waste heat added via the same `damage_heat` mechanism as a
   combat hit (`FIRE_HEAT_SPIKE := 15.0`), not a second decay system.
6. ✅ Engine damage-spike EM implemented as a rectified, damage-scaled
   oscillation (`_engine_damage_oscillation`) — see above.
7. ✅ Reactor-destroyed whiteout pulse (`_update_reactor_whiteout`),
   triggered by a per-component `_prev_health` health-crossing check.
8. ✅ Full regression suite green; `test_component_states.gd` extended with
   8 new tests: laser/hull damage-heat burst + decay (2 ships × 2 phases),
   engine oscillation near phase-start vs. near quarter-period peak, and
   reactor whiteout near-full-magnitude vs. fully-decayed.

**Done when:** EM/heat values visibly change over time per all four
`responsive_heat_em.md` triggers, every emitter (not just sensors) is
direction-aware, and `test_component_states.gd` covers the new behavior with
no ship-wide special-casing left for any single component type. — **met.**

## Follow-up: missile launchers are railgun-style (EM only, no heat)

`MissileBehavior.execute_fire()` already had no heat-adding line (only
`LaserBehavior` adds to `damage_heat`), so the railgun framing — an
electromagnetic launch pulse with no waste heat, unlike a laser's beam —
was already the actual behavior. Made it explicit: added a comment at the
call site, and three regression tests locking it in: laser fire adds heat,
missile fire does not, missile fire still produces its own EM pulse.
Without a test, a future "let's add fire heat to all weapons uniformly"
change could have silently erased this distinction.

## Follow-up: EM signature magnitude unit tests

Added direct unit tests of `Ship._received_em_power()` /
`Ship._total_received_em()` against hand-computed exact expected values
(not just qualitative thresholds), since these are pure functions on a
component dict + two angles with no physics/scene dependency:

- Omni emitter, bow-on (`relative_angle = 0`): exactly `em_emission * 1.0`.
- Omni emitter, tail-on (`relative_angle = PI`): exactly `em_emission * 1.5`
  (the rear-aspect bias's maximum).
- Directional emitter, on-axis: full strength, no falloff.
- Directional emitter, at half the half-arc off-axis: exactly 50% (linear
  falloff confirmed at a non-trivial point, not just the two endpoints).
- Directional emitter, outside the arc: exactly `0.0`, not a small tail.
- Combined emitter list: bow-on sums omni + on-axis directional
  (`100*1.0 + 100*1.0 = 200`); tail-on drops the directional term out of the
  sum entirely since its arc doesn't reach behind the ship
  (`100*1.5 + 0 = 150`), proving the per-emitter pattern selection composes
  correctly rather than just being correct in isolation.
