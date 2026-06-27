# M12 — Ship AI Behavior (Beehave) & Weapon Groups

Source design discussion: scaling AI from the single hardcoded drone controller to a
composable behavior library that covers combat posture, massed fire, and mission
roles (patrol / escort / stealth / hunt) across the whole ship catalog.

**Framework decision: committed to Beehave.** We already run a mature Beehave setup in
the sibling `team-dark` project — a shared leaf library wired into 8 enemy archetypes
(`scout`, `heavy`, `kamikaze`, `mortar`, `skittish`, `swarm`, …). That gives us a proven
composition model to copy rather than green-field a framework choice. See the
"Beehave integration" and "Why Beehave" sections below.

Sub-milestone labels are **M12a–M12f** (matching the M9a–f convention). They supersede
the informal "A1–A6" sketch from the design chat. Each letter stays attached to its
content, but the **execution order was revised after the spike** — see §10. In short:
the spike retired the Beehave risk, so the Beehave bring-up (M12b) was pulled *ahead* of
the weapon-groups capability (M12a) as a thin vertical slice, letting a real AI consumer
pull the `Ship` capability interface into existence before it is built on spec.

---

## 1. Problem statement

The current AI — [`scripts/ai_drone_controller.gd`](../scripts/ai_drone_controller.gd) —
is ~95 lines of imperative logic in one `_physics_process`:

- **One hardcoded weapon.** Fires `hp_fwd_missile` by literal id. Never touches the
  lasers or the port/starboard batteries the frigate actually carries.
- **One firing geometry.** Points its nose at the target. Nose-on structurally cannot
  bring a broadside to bear — the heaviest part of the ship's firepower is unreachable.
- **One defensive trigger.** Only evades when `ammo == 0`. Incoming fire while armed
  does nothing to its posture.
- **One target rule.** Nearest `"UNIDENTIFIED VESSEL"`. No notion of prey vs. threat,
  no disengage-from-stronger.
- **Not portable.** Hardwired to one hardpoint id, so it does nothing useful on a
  cargo shuttle, a destroyer, or any future hull.

A ship-vs-ship matchup sim (the deferred M9f) is meaningless until the AI can fight: a
TTK grid where both ships fire one forward weapon and ignore their broadsides measures
the AI's stupidity, not the hulls.

## 2. The capability layer already exists

The ship already exposes everything a competent AI needs; the controller just ignores it:

- `get_components_by_type("weapons")` → every weapon with `weapon_type`, `heading`
  (mount bearing), `arc_width`, `range`, `ammo`, `cooldown`, `damage`, `powered_on`.
- `WeaponBehavior.can_fire(ship, comp, contact_id)`
  ([`weapon_behavior.gd:6`](../scripts/components/weapon_behavior.gd)) already does the
  full arc + ammo + cooldown + power check for any weapon.
- `fire_weapon(weapon_id, target_pos, target_contact_id)`
  ([`ship.gd:1218`](../scripts/ships/ship.gd)) — host-authoritative fire path.
- `_process_point_defense()` ([`ship.gd:1239`](../scripts/ships/ship.gd)) — a *second,
  already-sophisticated* autonomous layer: prioritizes incoming ordnance
  (least-shot-at, then nearest) and concentrates ready lasers. PD is already
  ship-agnostic and reflexive.
- `apply_control_input(thrust, target_velocity, heading, steering_mode, linear_mode)` —
  the fly-by-wire intent the AI steers through (same pipe as the player helm).
- `set_sensor_target(contact_id)`, `active_contacts` (classifications:
  `"UNIDENTIFIED VESSEL"`, `"INCOMING ORDNANCE"`, friendly, …).

The architecture follows from this: **the ship owns capability, the behavior tree owns
decisions, and they meet at a small method interface.** That is exactly how team-dark's
leaves work — `fire_weapons.gd` is a thin adapter that calls `actor._fire_all_weapons()`
and knows nothing about the actor's loadout. Reasoning over components + `can_fire`
(never over hardpoint ids) is what makes one AI cover every hull.

---

## 3. Design pillars

1. **Capability / decision split.** New capability methods live on `Ship`; all
   decision logic lives in Beehave leaves/trees. Leaves call methods and read a
   blackboard; they never index `ship_components` directly.
2. **Weapon groups are first-class** (M12a). A broadside is wired as a *unit* so both
   the player and the AI reason about "can my port battery bear?" instead of five
   independent hardpoints.
3. **Massed fire is the heavy-ship win condition.** Firing a whole group *simultaneously*
   (one physics tick) is the mechanically-correct way to punch through point defense.
   This is the central advantage of bigger ships and a critical behavior, not a nicety.
4. **Portability across hulls.** Same leaves, same trees; per-class differences are
   *data* (weights, range bands, target preference), not code forks.
5. **Headless-testable.** Leaves are pure GDScript callable from the `--run-test`
   harness with a stub actor; archetype trees tick without rendering.

---

## 4. M12a — Weapon groups & massed fire (capability layer)

The foundation. No AI yet — this is a ship + player-UI feature that the AI later drives
through the same primitive. Independently valuable: it gives the **player a single-button
massed-fire control** (press "PORT" → the whole battery volleys), which is less frantic
than clicking five buttons and is the only way a player gets massed fire too.

### 4.1 Group schema

Add an optional `"group"` string to weapon component dicts. When absent, derive it from
`heading` so existing ships keep working:

| Derived group | Condition on `heading` |
|---|---|
| `"fwd"`  | `abs(heading) < PI/6` |
| `"port"` | `heading` near `-PI/2` |
| `"stbd"` | `heading` near `+PI/2` |
| `"aft"`  | `abs(heading)` near `PI` |
| `"other"`| fallback |

The frigate ([`frigate.gd:61`](../scripts/ships/frigate.gd)) then naturally yields
`fwd` (`hp_fwd_laser`, `hp_fwd_missile`), `port` (2 lasers + 3 tubes), `stbd` (2 lasers
+ 3 tubes). New ships can set `"group"` explicitly to override the derivation.

### 4.2 New `Ship` capability methods

```gdscript
# Cached { group_id: [weapon_ids] }, built from get_components_by_type("weapons").
func get_weapon_groups() -> Dictionary

# Massed fire: iterate the group, fire EVERY member whose can_fire() passes, in the
# SAME tick. Returns the count fired. This single-tick simultaneity is what saturates
# point defense -- a trickle (current AI: 1 missile/10s) gets swatted; a simultaneous
# volley overwhelms the defender's finite tracks-per-refresh.
func fire_group(group_id, target_pos, target_contact_id) -> int

# For UI + AI utility scoring without committing a shot.
# { ready: int, total: int, any_bears: bool, best_rel_angle: float }
func get_group_status(group_id, target_contact_id) -> Dictionary
```

`fire_group` reuses `fire_weapon` per member, so the host-authority guard, behavior
registry, and EM/heat pulses all stay intact. It is the **single source of truth** for
massed fire — the player button and the AI `fire_group` leaf both call it.

### 4.3 Why massed fire beats PD (and ties to existing data)

The missile-vs-PD sim already sweeps `volleys = [1,2,3,4,5,6,8,10,15]`
([`run_missile_vs_pd.gd:15`](../tactical_analysis/sim_runners/run_missile_vs_pd.gd)).
PD intercepts a bounded number of simultaneous tracks per refresh window
(`_process_point_defense` services ready lasers across prioritized targets). A single
launcher dribbling one round at a time is trivially intercepted; a synchronized N-round
volley exceeds the interceptor's capacity and leaks hits through. Heavy ships have *more
tubes per group*, so `fire_group` is precisely how a destroyer "shoots through" a
frigate's PD. M12a makes that mechanic reachable; M12f re-runs the sim with AI actually
exercising it.

### 4.4 Player UI integration

[`weapons_panel.gd`](../scripts/panels/weapons_panel.gd) already builds a per-weapon
FIRE button and computes a `can_fire`/status blocker chain. Add, above the per-weapon
grid, **one group button per group** ("FWD", "PORT", "STBD") that:

- shows readiness from `get_group_status` (e.g. `PORT  3/4 READY` / `OUT OF ARC`),
- emits a new `fire_group_requested(group_id)` signal,
- routes through a `request_fire_group` RPC mirroring the existing fire path.

Keep the individual buttons as a manual override. Single-button massed fire = press the
group, get the volley.

**Done when:** the player can fire a whole broadside with one button; `fire_group` fires
all in-arc ready members in one tick; a unit test asserts a frigate `fire_group("port")`
launches every ready port-battery weapon simultaneously and respects arc/ammo/cooldown.

---

## 5. Beehave integration (M12b)

### 5.1 Why Beehave (over pure-GDScript or LimboAI)

- **Proven in-house.** team-dark already composes 8 archetypes from one leaf library;
  we copy a working pattern instead of choosing blind.
- **Composability is the whole point** (the user's broadside-as-unit and
  archetype-curation asks are both composition problems). Beehave gives Selector /
  Sequence / SimpleParallel composites + Cooldown / Limiter / Repeater decorators, and
  parameterized leaves via `@export` — so a new archetype is a new tree wiring + stat
  block, not new code.
- **Honest tradeoff:** Beehave trees are normally scene-authored and lean on the
  SceneTree + Blackboard node, which is more friction in our headless `--run-test`
  harness than a plain GDScript scorer. Mitigation in §8. If headless ergonomics fight
  us hard in M12b, the fallback is a pure-GDScript selector behind the same leaf
  interface — but we try Beehave first because the composition payoff is real.

### 5.2 Wiring

- Vendor `addons/beehave` (copy from team-dark, update `.uid`s; enable the plugin).
- Each AI ship gets a `BeehaveTree` child whose `actor` is the ship and which carries a
  `Blackboard`. This *replaces* `AIDroneController` (spawned today in
  [`main.gd:179`](../scripts/main.gd)); `_spawn_ship` attaches the archetype tree
  instead.
- **Actor interface** the ship must expose for leaves (most already exist):
  `get_weapon_groups`, `fire_group`, `get_group_status`, `apply_control_input`,
  `set_sensor_target`, `active_contacts`, `position`/`rotation`/`linear_velocity`,
  `is_dead`, `is_multiplayer_authority`. AI + `fire_group` run host-side only.

### 5.3 Blackboard contents

`target` (contact id / pos / vel), `threats` (incoming-ordnance contacts), `self`
(per-group ammo, heat, hull health), `home`/`patrol_waypoints`, `protected` (escort
subject), and `target_filter` (the disposition predicate, §7).

---

## 6. Leaf library

Mirrors team-dark's structure (`scripts/ai/nodes/{actions,conditions}`), parameterized
via `@export`. Postures (Strike / Broadside / Standoff / Evade / Patrol / Escort /
Stealth) are **emergent from tree wiring**, not enum states in code.

**Conditions**
- `has_target`
- `group_can_bear` (param `group`) → wraps `get_group_status(...).any_bears`
- `under_fire` (incoming ordnance within threshold; reads same data as PD)
- `group_has_ammo` (param `group`)
- `should_disengage` (hull/health low, or no offensive ammo left)
- `target_in_range` (param band)

**Actions**
- `acquire_target` (param `target_filter`) → pick per disposition, `set_sensor_target`
- `orient_for_group` (param `group`) → set heading so the group bears: strike =
  `angle_to_target`; broadside = `angle_to_target ∓ PI/2` (choose port/stbd by which is
  the shorter turn); via `apply_control_input`
- `maintain_range` (params min/desired/max) → thrust logic generalized from the current
  controller's 5k/10k band
- `fire_group` (param `group`) → `ship.fire_group(...)` massed volley
- `fire_opportunity` → fire every group that currently bears (default offense)
- `evade` (incoming-aware: steer away with wobble; generalizes the out-of-ammo block)
- `patrol_waypoints` (param loop) · `flee` · `escort_station` (param `protected`) ·
  `hold_silent` (stealth: passive sensors only, hold fire, mind `em_signature`)

Spike in M12b: port `fire_weapons`, `maintain_distance`, `flee_player` from team-dark to
feel the headless ergonomics before building the full set.

---

## 7. Target disposition

**The world is binary for now: "friendly" (shared `iff_tags`) vs. everything else
("unidentified"). No neutral.** `classify_contact()` already works this way, and M12
does not add a neutral/IFF-beacon path (that stays M7, and M12 does not depend on it).

Default selection is therefore **nearest non-friendly** — same rule the current
controller uses, just generalized off the hardcoded weapon. Each archetype carries a
`target_filter` on the blackboard, but in v1 most resolve to that default. The
interesting variation comes from *what a ship does about* a contact, not fine-grained
target identification:

- **Civilian** — engages no one; its `target_filter` is empty and its tree flees any
  non-friendly contact (see §8). Defined purely by behavior, needs no special tag.
- **Combatants** (flock / pirate / destroyer) — engage nearest non-friendly, modulated
  by their disengage/range profile (§9).

Finer preference (e.g. a pirate *preferring* weak prey over an armed escort) needs a way
to tell ships apart that the binary classifier does not yet provide — **deferred**, not
v1. In the curated scenario the pirate-vs-civilian dynamic emerges from proximity + the
civilian fleeing, not from the pirate identifying a civilian.

---

## 8. M12d — Curated test archetypes

A self-contained sandbox "food chain" that doubles as the AI regression scenario: spawn
**1 civilian + 1 pirate + a light flock + a destroyer** and watch them interact. Each is
hull + team + `target_filter` + tree wiring — same leaves throughout.

| Archetype | Hull | Team | Targets | Posture (tree shape) |
|---|---|---|---|---|
| **Unknown Civilian** | Cargo Shuttle | non-friendly | none | `Selector[ enemy_near→flee, patrol_drift ]` — flees any non-friendly (= unidentified) contact; no fire leaf at all. Prey, defined purely by behavior. |
| **Light Attack Flock** | Light Attack Craft ×N | ENEMY | nearest player-team | `Selector[ has_target→(orient_for_group(fwd)+maintain_range(knife)+fire_opportunity), regroup ]` + flock cohesion. Massed via *numbers* (many small guns). |
| **Pirate (solo)** | Frigate / Light Attack | PIRATE (unique) | prefers civilians, avoids strong | `Selector[ should_disengage→evade, hunt(acquire(prefer_civilian)→close→fire_group), patrol ]`. Demonstrates preference + flee-from-stronger. |
| **Destroyer Hunter-Killer** | Destroyer | ENEMY | any combatant | `Selector[ should_disengage→evade, hunt_kill(acquire→maintain_range(standoff)→orient_for_group(broadside)→fire_group) ]`. The massed-fire flagship: single-tick broadside volley through PD. |

The destroyer is the headline demonstration of pillar #3; the flock is the
swarm-level contrast (massed by count, not per-ship volley). Wire all four into the
sandbox spawn UI (M10) so they are one-click playable.

**Civilian note:** the civilian needs no special faction machinery. With only "friendly"
IFF in the world, it simply spawns non-friendly (so it reads as unidentified to
everyone, including the player) and is defined *entirely by its flee tree*. "Civilian"
here means "unarmed-and-flees-anything-not-friendly," full stop — no neutral
classification, no IFF beacon, no signature heuristic. M12 does not touch M7.

---

## 9. AI profiles & per-instance variation

A profile is a set of named parameters (aggression, preferred-range band,
disengage-health, target-preference weights, fire discipline). Rather than authoring a
single shared constant per archetype, each parameter is **resolved once at spawn** as
three composable layers:

```
effective_param = derive(base, this_ship) ± jitter(seed)
```

- **base** — authored per archetype (the "pirate" defaults).
- **derive** — an *optional* function of the ship's own capability, so one profile
  scales across hulls without separate authoring:
  - `preferred_range = f(longest ready weapon-group range)` → a pirate on a frigate
    stands off; the same profile on an interceptor knife-fights.
  - `disengage_health = base − k·(threat_strength − own_strength)` from a relative-
    strength read (own remaining firepower vs. the target's estimated signature) → a
    weaker ship breaks off sooner. Emergent, not hand-tuned per hull.
- **jitter** — *per-instance* personality, e.g. `aggression × U(0.85, 1.15)`, **seeded
  from `owner_id`** (already unique per spawn, see `_spawn_ship` in
  [`main.gd:157`](../scripts/main.gd)). This is what makes one pirate in a group chase
  harder or break off earlier than its wingmen.

Resolved params are written to the blackboard at spawn; leaves read e.g.
`blackboard.disengage_health`, never a hardcoded constant.

**Determinism:** seeding jitter from `owner_id` keeps headless sims reproducible — the
same scenario spawns the same personalities, no free `randf` in the test harness. This
matters for the M12f engagement sim.

**Two axes of variety, composed:** the model above varies *how aggressively*
(parameter-level). Beehave's `selector_random` / `sequence_random` / `randomized_composite`
vary *which tactic* (tree-level). Personality lives in the numbers; unpredictability
lives in the branch.

This is the mechanism behind M12f — profiles are resolved per-instance, not per-class
constants — and is the answer to "can an individual pirate behave slightly differently
than the rest of the group": shared base, individual `derive` + seeded `jitter`.

---

## 10. Milestones

> **Execution order revised 2026-06-26.** The original draft put M12a (weapon groups)
> first on a "lowest-risk, no-framework" rationale. The spike retired the Beehave risk,
> so the order flipped to a **thin vertical slice first** (M12b before M12a): stand up
> the minimal real AI tree, let it pull the `Ship` capability interface into existence
> through a real consumer, *then* build the weapon-groups capability the broadside
> posture demands. The player massed-fire UI splits out as an independent track off the
> AI critical path.

- **M12b-spike — Beehave headless go/no-go gate. DONE (2026-06-26, git `fbfd06c`).**
  Vendored Beehave 2.9.2; `test_ai_beehave_spike` builds a `BeehaveTree` (MANUAL thread)
  in code, ticks it under `--headless --run-test`, and the leaf drives the ship via
  `apply_control_input`. Two autoloads added; existing suite unaffected. The global class
  cache is a **local artifact** (warm once via the Godot editor or `--import`),
  intentionally not committed — git cannot re-include a child of the ignored `.godot/`
  dir. Kept the spike as a permanent Beehave-headless smoke test.
- **M12b — Beehave bring-up + minimal engage tree. DONE (2026-06-26).** Replaced
  `ai_drone_controller` with a Beehave tree built in code by `scripts/ai/ai_tree_factory.gd`:
  `Selector[ Sequence[ acquire_target, steer_to_target, fire_opportunity ], idle ]`.
  `fire_opportunity` enumerates `get_components_by_type("weapons")` and fires every weapon
  that bears through `fire_weapon` — so the AI now uses its forward laser **and** missile
  (and any aligned battery) instead of one hardcoded `hp_fwd_missile` every 10s. Steering
  ported verbatim from the legacy range bands (posture-aware orientation is M12c). The
  legacy `AIDroneController` is **retained as a baseline opponent** (no longer attached by
  `_spawn_ship`) for the superiority regression below. `test_e2e_drone_vs_bouy` migrated
  to the tree; `test_ai_engage_tree` asserts the forward laser and missile both fire; and
  `test_ai_vs_legacy` pits the new AI against the legacy controller on identical hulls vs
  an identical buoy and requires the new AI to kill faster in every trial (measured: new
  2 frames via its hitscan laser vs legacy 165 frames waiting on a missile — 3/3, no
  variance). A true head-to-head *duel* test is deferred to M12a: two single-missile
  trickle frigates stalemate today because each ship's PD swats the other's lone missiles
  — exactly the gap massed fire closes. Suite green (15/16; `test_asteroid` is a
  pre-existing non-conforming legacy test, not a regression). Leaves all return
  SUCCESS/FAILURE (never RUNNING) so the Engage sequence runs steer **and** fire each tick.
- **M12a — Weapon groups & massed fire (capability) + player single-button group fire.**
  Now sequenced *after* the slice. Build `get_weapon_groups` / `fire_group` /
  `get_group_status` (§4) because the broadside posture (M12c) and the shoot-through-PD
  pillar demonstrably need them; give `fire_opportunity` group-aware metering (save a
  massed volley instead of dribbling the magazine). The player group-fire button (§4.4)
  is an independent sub-track that can land anytime — it is off the AI critical path.
  - **Capability layer DONE (2026-06-27).** `get_weapon_group_id` (explicit `group` field,
    else derived from mount bearing: fwd / aft / port / stbd), `get_weapon_groups`,
    `fire_group` (single-tick volley, returns count fired), and `get_group_status` landed
    on `Ship`. `test_weapon_groups` verifies the frigate buckets to fwd(2)/port(5)/stbd(5),
    a `fire_group("port")` fires the full 5-weapon broadside in one tick, and the
    out-of-arc starboard battery holds fire. **Volley metering DONE (2026-06-27):**
    `is_group_volley_ready(group, weapon_type)` holds a missile volley while any tube that
    could still fire (alive, powered, has ammo) is on cooldown, and never waits on a tube
    that is damaged / empty / disabled. `fire_opportunity` now fires lasers at will but
    looses missile tubes only as a synchronized per-group volley; `test_volley_metering`
    covers the wait/don't-wait cases. (At nose-on the forward group has one tube, so the
    hold only bites once a multi-tube broadside is brought to bear in M12c.) **Remaining
    for M12a:** the player group-fire button, and the duel test below.
  - **Verification deliverable: `test_ai_duel` (frigate vs frigate, head-to-head).** The
    real superiority test the project wants is a direct duel — new AI frigate vs legacy
    AI frigate, identical hulls, last one alive wins. It is parked off M12b because today
    two single-missile trickles stalemate: each ship's PD swats the other's lone missiles,
    so neither dies. **It needs M12a *and* M12c:** the frigate's saturating missile volley
    is its 3-tube *broadside*, so the new AI must both bring the broadside to bear
    (M12c orientation) and fire it as one group (`fire_group`, M12a) — at nose-on it has
    only the single forward tube and cannot mass. Land the duel test once both exist;
    `test_ai_vs_legacy` (the TTK-vs-buoy laser proxy) stands in until then.
- **M12c — Postures & threat reactivity.** `orient_for_group` (turn to bring a broadside
  to bear; strike vs. broadside), `maintain_range`, `evade`, `under_fire`. Where the
  destroyer starts fighting like a destroyer — bring a broadside to bear and `fire_group`
  through PD even while armed.
- **M12d — Disposition + curated archetypes + sandbox scenario.** `target_filter`; the
  four archetypes as trees; wire into the M10 spawn UI; the food-chain scenario.
- **M12e — Mission behaviors.** Patrol, escort (formation primitive ported from
  team-dark's flock), stealth-approach (EM management), picket. Groundwork for the
  mission-types design.
- **M12f — Per-instance AI profiles + matchup sim.** Implement the §9 resolution model
  (base / derive / seeded jitter) so individuals vary within a group; new headless
  `run_ai_engagement` sim (reuses the missile-vs-PD harness shape) measuring massed-volley
  shoot-through; **un-defer M9f** now that ships fight competently.

---

## 11. Dependencies

- **Requires:** M9c (ships exist), M10 (spawn UI to play them). M1/M1c
  (component+behavior model) — done.
- **Deliberately does NOT require M7.** The binary friendly/unidentified world is
  sufficient; the civilian is a behavior, not a classification. Richer target
  *preference* is deferred to whenever a finer classifier exists.
- **Unblocks:** M9f matchup sim (becomes meaningful only with competent AI).

## 12. Testing strategy

- **Leaf unit tests** — pure GDScript leaves driven with a stub actor + blackboard in
  `--run-test`; no tree, no rendering.
- **Tree tick tests** — build small trees in code (or load an archetype `.tscn`) and
  `tick()` headlessly; spawn archetype + dummy target, assert outcomes (target acquired,
  group fired in one tick, fled under fire).
- **Engagement sim** — `tactical_analysis/sim_runners/run_ai_engagement.gd` reusing the
  sharded missile-vs-PD harness (M9e): destroyer massed-volley vs. PD frigate; measure
  hit-leak rate vs. the current trickle baseline. This is the data that makes M9f honest.

## 13. Open questions / risks

- **Headless Beehave ergonomics** — validated early (M12b); pure-GDScript selector
  behind the same leaf interface is the fallback.
- **Target preference is coarse** — v1 selection is "nearest non-friendly"; a pirate
  preferring weak prey over an armed escort needs a finer classifier that does not exist
  yet. Deferred, not v1. (The civilian needs none of this — it is flee-only.)
- **Group derivation** for hulls whose weapons don't cluster cleanly by bearing — allow
  explicit `"group"` override (schema already supports it).
- **Formation/escort** needs a maintain-formation primitive (port team-dark's flock).
- **Multiplayer authority** — AI, `fire_group`, and `request_fire_group` all run
  host-side; reuse the existing `is_multiplayer_authority()` guards.
