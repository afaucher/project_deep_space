# M1: Component Architecture — Detailed Design

Parent plan: [design_ideas_implementation_plan.md](design_ideas_implementation_plan.md). Source doc: `design_ideas/ship_is_the_parts.md`.

## Decision: sensor dome is 1:1, split into individual boxes (Option 2)

Today there are **two physical sensor boxes** (`hp_sensor_fwd`, `hp_sensor_omni`) hosting **five logical sensors** (`dir_high_res`, plus `omni_main` / `omni_short_hi_res` / `passive_em` / `omni_collision` all crammed into the one omni box). The mapping is resolved by a fallback guess in `ship.gd`:

```gdscript
var parent_comp_id = sensor.get("parent", "hp_sensor_fwd" if sensor["id"] == "dir_high_res" else "hp_sensor_omni")
```

[ship.gd:685](scripts/ships/ship.gd:685)

This is the many-to-one case `ship_is_the_parts.md` explicitly flags and says to avoid for now by splitting the dome. We're taking that option, for two reasons:

1. **Precedent already exists in the codebase.** Weapons are already 1:1 — every entry in the `weapons` dict (`hp_fwd_laser`, `hp_port_tube_1`, etc.) has a matching `ship_components` entry with the *same id*. Splitting sensors the same way makes sensors consistent with weapons instead of being the one subsystem with bespoke fallback logic.
2. **Composite (Option 1: one box, many sensors) only earns its complexity when a box needs to host sensors that aren't independently destructible/targetable** — e.g. a sensor drone pod where you genuinely want shared armor. We don't have that case yet. Defer it; revisit if/when a ship design needs a real shared housing.

**Consequence of going 1:1:** once a physical component and a logical sensor are the same thing, there's no reason to keep them as two separate dictionaries joined by a guessed id. We collapse `sensor_hardware` into `ship_components` entirely — one component, one dictionary, no `parent` field, no fallback.

We are **not** doing the equivalent merge for weapons in M1 — that's a larger, separately-scoped change (`fire_weapon`, `weapons_panel.gd`) and isn't what's blocking the sensor dome problem. Note it as a future cleanup, out of scope here.

---

## Current state: three parallel structures

| Structure | Keyed by | Holds |
|---|---|---|
| `ship_components` (Array) | hardpoint id | physical: `rect`, `health`, `max_health`, `density`, `heat`, `em_emission`, `switchable`, `powered_on` |
| `weapons` (Dict) | hardpoint id (matches `ship_components`) | gameplay: `ammo`, `cooldown`, `range`, `damage`, `heading`, `arc_width`, `mount_pos` |
| `sensor_hardware` (Array) | sensor id (**does not** match `ship_components`) | gameplay: `range`, `arc_width`, `num_bins`, `refresh_interval`, `timer`, `heading`, `active`, `em_emission` (base) |

Sensors are the odd one out: `sensor_hardware` ids (`omni_main`, `dir_high_res`, ...) don't correspond to `ship_components` ids (`hp_sensor_fwd`, `hp_sensor_omni`), so the join has to be guessed.

**Bug found while tracing this:** the per-frame component heat/EM update loop ([ship.gd:661-679](scripts/ships/ship.gd:661)) sets `comp["em_emission"]` and `comp["heat"]` identically for *every* `"sensors"`-type component to the same pooled `sensor_em` value, rather than each sensor contributing its own base value. This is a second symptom of the same many-to-one problem and gets fixed for free by the merge below (each sensor component carries and emits its own base `em_emission`). Full dynamic per-component heat/EM (event-driven spikes) is still M2's job — this fix is just "stop overwriting five components with one shared number."

---

## Target schema

Single source of truth per sensor: one entry in `ship_components`, type `"sensors"`, carrying the union of old physical + logical fields. No `parent`, no `sensor_hardware` array.

```gdscript
{
    "id": "omni_main",                 # was a ship_components box id AND a sensor_hardware id; now just one id
    "type": "sensors",
    "rect": Rect2(-5, -5, 5, 5),       # physical hardpoint box (new, subdivided — see layout below)
    "health": 40.0, "max_health": 40.0,
    "density": 20.0,
    "switchable": true, "powered_on": true,
    "heat": 0.0,
    "base_em_emission": 10.0,          # authored constant — what this sensor emits at full power, never overwritten
    "em_emission": 10.0,               # live value the per-frame loop recomputes each tick; starts equal to base
    # --- sensor sweep fields, unchanged from old sensor_hardware ---
    "sensor_type": "active",           # renamed from "type" to avoid clashing with the component "type" key
    "active": true,
    "range": 40000.0, "arc_width": TAU, "num_bins": 36,
    "refresh_interval": 2.0, "timer": 0.0, "heading": 0.0
}
```

Note the rename: the old `sensor_hardware` entries used `"type"` for active/passive_em, which collides with the component-level `"type"` (hull/reactor/engines/sensors/weapons). Renaming to `"sensor_type"` removes the ambiguity now that both live in one dict.

`base_em_emission`/`em_emission` is the same *constant-vs-live* split the schema already uses for `max_health`/`health` — not a new pattern, just applying the existing one to EM. Without it, the per-frame loop has nowhere to read the authored baseline from once it starts writing the live value every tick (this is also why the weapon schema below needs the same field once `LaserBehavior` starts pulsing EM on fire — see the behavior-architecture section). Per-sensor baseline values, carried over unchanged from the old `sensor_hardware` list: `dir_high_res` 20.0, `omni_main` 10.0, `omni_short_hi_res` 5.0, `passive_em` 0.0 (passive, doesn't emit), `omni_collision` 0.0.

`heading` (center angle, relative to ship forward) and `arc_width` (cone width centered on that heading) are carried over unchanged from `sensor_hardware` — they already exist today (`SENSOR_HEADING = rotation + sensor["heading"]`, [ship.gd:821](scripts/ships/ship.gd:821)) and aren't new. Listed explicitly per sensor below so the split layout is unambiguous.

### Physical layout for the player frigate

Old boxes: `hp_sensor_fwd` (nose, 5×5) hosted `dir_high_res` only; `hp_sensor_omni` (center, 10×10) hosted the other four pooled at 100 HP.

New boxes — `dir_high_res` keeps the nose footprint; the omni dome is subdivided into four 5×5 quadrants. Total HP pool is preserved (150 old → 150 new) so overall sensor survivability doesn't shift, just distributed per sensor's importance:

| id | rect | max_health | heading | arc_width |
|---|---|---|---|---|
| `dir_high_res` | `Rect2(30, -2.5, 5, 5)` | 50.0 (unchanged) | `0.0` | `PI / 6.0` (30°, forward cone) |
| `omni_main` | `Rect2(-5, -5, 5, 5)` | 40.0 | `0.0` | `TAU` (full circle) |
| `omni_short_hi_res` | `Rect2(0, -5, 5, 5)` | 20.0 | `0.0` | `TAU` |
| `passive_em` | `Rect2(-5, 0, 5, 5)` | 20.0 | `0.0` | `TAU` |
| `omni_collision` | `Rect2(0, 0, 5, 5)` | 20.0 | `0.0` | `TAU` |

These are starting numbers for balance, not load-bearing — easy to retune once it's playtested. `heading`/`arc_width` are unchanged from the old `sensor_hardware` values; only `rect` and `max_health` are new (the box split).

### Hardpoint origin — sweeps and fire control should originate from the component, not ship-center

Today `_run_sensor_sweep` always queries from dead ship-center (`query.transform = Transform2D(0, position)`, [ship.gd:815](scripts/ships/ship.gd:815)), and the passive-EM rear-aspect/ray calcs in the same function do the same ([ship.gd:834-874](scripts/ships/ship.gd:834)). No sensor field currently expresses "where on the hull this sensor actually sits." That was a reasonable simplification while all sensors shared two boxes near the center; it stops being accurate once each sensor has its own real position (nose vs. four dome quadrants), and it's the same hardpoint-origin question the doc raises for weapons.

Weapons already have an origin field for this (`mount_pos`), but it's worth noting *why* we shouldn't just copy that pattern onto sensors: checking the actual values, every weapon's `mount_pos` is numerically identical to its `rect.position` (e.g. `hp_fwd_laser`: `mount_pos = Vector2(30, -7.5)`, `rect = Rect2(30, -7.5, 5, 5)`) — it's the same coordinate entered twice and hand-kept in sync. That duplication is already a latent bug: `fire_weapon` reads `mount_pos` ([ship.gd:1052](scripts/ships/ship.gd:1052)) while the point-defense aim loop reads `rect.position` directly ([ship.gd:1164](scripts/ships/ship.gd:1164)) — two fields, one intended value, two independent readers that could silently drift apart if either is edited without the other.

For sensors, the consistent fix is to **derive the origin from `rect`** instead of storing a second redundant field. Checking *every* weapon hardpoint's `mount_pos` against its `rect.position` shows they're identical in all 12 cases (`hp_fwd_laser`: `mount_pos = Vector2(30, -7.5)` = `rect.position`; same for the other 11) — this isn't coincidence, it's an existing unwritten convention: **mount point = `rect.position`** (the box's ship-local top-left corner), not its center. So the derivation should match that, not introduce a different rule:

```gdscript
func get_component_origin(comp: Dictionary) -> Vector2:
    return comp["rect"].position  # ship-local mount point — matches the existing mount_pos convention exactly
```

and change the sweep/ray origins in `_run_sensor_sweep` from `position` to `position + get_component_origin(sensor).rotated(rotation)`. No new stored field, no chance of drift, and zero numeric change to weapon behavior once weapons adopt the same helper (see below).

This is correctness-for-the-future more than a gameplay-significant change today: frigate sensor offsets (≤30 units) are negligible against sensor ranges (5,000-80,000 units). It matters once ship sizes vary more (larger ships, off-center sensor pods on drones) and it removes the inconsistency between "sensors sweep from ship-center" and "weapons fire from their hardpoint."

We initially scoped weapons out of M1 as a separate follow-up. Reconsidering: the weapon-side fix is the same merge, the same origin derivation, and resolves a real bug (see below) — doing it alongside sensors is cheaper than doing it twice. Folded into M1 below.

---

## Generalizing the merge to weapons

Same shape as the sensor problem, with one extra wrinkle. `weapons` (Dict, keyed by hardpoint id) and `ship_components` (Array, type `"weapons"`) are **already 1:1 by id** — but they're still two structures manually kept in sync, and that sync has already drifted in *behavior*, not just data:

- `fire_weapon()` computes hit/damage origin and missile spawn point from `weapon_data["mount_pos"]` ([ship.gd:1052,1101](scripts/ships/ship.gd:1052)).
- `_process_point_defense()` computes aim angle and the laser-beam visual `start_pos` from `weapon["rect"].position` instead ([ship.gd:1164,1174](scripts/ships/ship.gd:1164)).

These happen to agree today only because `mount_pos` was always hand-entered equal to `rect.position`. They are two independent fields read by two independent code paths — the first time someone edits a hardpoint's `rect` without remembering to edit its `mount_pos` (or vice versa), player-fired shots and PD-fired shots will silently originate from different points on the hull. Merging removes the possibility entirely: there's one `rect`, one derived origin, read by both.

### Target schema (merged weapon component)

```gdscript
{
    "id": "hp_fwd_laser",
    "type": "weapons",
    "rect": Rect2(30, -7.5, 5, 5),
    "health": 150.0, "max_health": 150.0,
    "density": 20.0,
    "switchable": true, "powered_on": true,
    "heat": 0.0,
    "base_em_emission": 0.0, "em_emission": 0.0,  # laser idles at 0 EM; LaserBehavior.tick() adds the firing pulse on top
    # --- weapon fields, unchanged from old `weapons` dict ---
    "weapon_type": "laser",            # renamed from "type" — same collision-avoidance reason as sensors
    "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0,
    "range": 4000.0, "damage": 500.0,
    "heading": 0.0, "arc_width": PI / 3.0
    # "mount_pos" dropped — origin is get_component_origin(comp) == rect.position
}
```

Same rename pattern as sensors (`"type"` → `"weapon_type"` for the gameplay discriminator, since component-level `"type"` already means hull/reactor/engines/sensors/weapons) and the same field-elimination (`mount_pos` dropped in favor of the derived origin). `base_em_emission` is added here for the same reason as sensors — see the behavior-architecture section below. No `base_heat` yet: nothing reads it (no behavior pulses weapon heat today), so adding it now would be a dead field; add it when M2 actually needs a heat pulse on some component type.

### Code changes in `ship.gd`

- **Delete** the `weapons` Dict var ([ship.gd:29-44](scripts/ships/ship.gd:29)); add `get_components_by_type("weapons")` callers wherever code iterated `weapons.keys()`.
- `_physics_process` cooldown loop ([ship.gd:504-510](scripts/ships/ship.gd:504)): `for w in weapons.keys(): weapons[w]["cooldown"]...` → `for w in get_components_by_type("weapons"): w["cooldown"]...`.
- `fire_weapon()` ([ship.gd:995-1129](scripts/ships/ship.gd:995)): replace every `weapons[weapon_id][...]` lookup with a single `var weapon_data = get_component(weapon_id)` (new helper, single-id lookup — see interface audit below) at the top of the function; replace `weapon_data["mount_pos"]` at lines 1052 and 1101 with `get_component_origin(weapon_data)`.
- `_process_point_defense()` ([ship.gd:1131-1186](scripts/ships/ship.gd:1131)): `for w_id in weapons: if weapons[w_id]["type"]==...` → `for w in get_components_by_type("weapons"): if w["weapon_type"]==...`; replace the `weapon["rect"].position` reads at lines 1164 and 1174 with `get_component_origin(weapon)` — now identical to what `fire_weapon` uses, closing the gap described above.
- `get_signature()` ([ship.gd:319-333](scripts/ships/ship.gd:319)) doesn't currently expose `weapons` at all (only `main.gd` does, for the UI/network state — see below), so no change needed there.

### Other call sites

| File | Line | Change |
|---|---|---|
| [main.gd:231](scripts/main.gd:231) | `"weapons": ship.weapons.duplicate(true)` | `ship.get_components_by_type("weapons")` |
| [weapons_panel.gd:100-104](scripts/weapons_panel.gd:100) | `for w_id in weapons.keys(): ... weapons[w_id]["ammo"]` | iterate the array from `main.gd`'s state payload instead of a keyed dict; index by `w["id"]`/`w["ammo"]` |
| [navigation_panel.gd:239-244](scripts/navigation_panel.gd:239) | `var weapons = current_state.get("weapons", {}); for w_id in weapons:` | same array-instead-of-dict iteration update |

No test files reference weapon ids or `ammo`/`cooldown` fields directly (`test_point_defense.gd`, `test_damage_propagation.gd` checked — clean), so the weapon merge carries less regression risk than the sensor merge did.

**Done when:** no references to the standalone `weapons` Dict or `mount_pos` remain in `scripts/`, `fire_weapon` and `_process_point_defense` derive their origin from the same `get_component_origin()` call, and `test_point_defense.gd` plus the full PD/weapons-adjacent suite still pass.

---

## Full component interface

Three new helpers fall out of doing the sensor and weapon merges together — they're the actual "interface" `ship_components` now needs, since every caller below reduces to one of these four operations:

```gdscript
func get_components_by_type(type: String) -> Array:
    return ship_components.filter(func(c): return c["type"] == type)

func get_component(comp_id: String) -> Dictionary:
    for c in ship_components:
        if c["id"] == comp_id:
            return c
    return {}

func get_component_origin(comp: Dictionary) -> Vector2:
    return comp["rect"].position

# already exists, kept as-is:
func is_component_powered(comp_id: String) -> bool: ...
func get_component_health_ratio(comp_id: String) -> float: ...
```

`get_component()` is new but not net-new behavior — it formalizes a lookup that already happens ad hoc today (`ship_components.filter(func(c): return c["id"] == w_id)[0]` in the PD loop, [ship.gd:1162](scripts/ships/ship.gd:1162); `weapons[weapon_id]` in `fire_weapon`). After the merge it's the one way any caller fetches a full component dict by id, for any type.

### Audit — every function touching component data today

This is the complete list found by tracing every read of `ship_components`, `weapons`, and `sensor_hardware` across `scripts/`. Anything not in this table doesn't touch component data and is unaffected by M1.

| Function | Structure(s) today | Type-agnostic? | M1 change |
|---|---|---|---|
| `get_sys_health(sys_type)` [ship.gd:98](scripts/ships/ship.gd:98) | `ship_components` | yes | none — already dispatches on `c["type"]` |
| `get_sys_max_health(sys_type)` [ship.gd:141](scripts/ships/ship.gd:141) | `ship_components` | yes | none |
| `is_component_powered(comp_id)` [ship.gd:148](scripts/ships/ship.gd:148) | `ship_components` | yes | none |
| `get_component_health_ratio(comp_id)` [ship.gd:154](scripts/ships/ship.gd:154) | `ship_components` | yes | none |
| `set_component_power(component_id, active)` [ship.gd:983](scripts/ships/ship.gd:983) | `ship_components` | yes | none |
| `take_damage()` volumetric raymarch + bbox cache [ship.gd:187-294](scripts/ships/ship.gd:187) | `ship_components` (`rect`, `health`, `density`) | yes | none |
| `hulk()` [ship.gd:304](scripts/ships/ship.gd:304) | `ship_components` | yes | none |
| per-frame heat/EM dispatch loop [ship.gd:640-679](scripts/ships/ship.gd:640) | `ship_components`, reads `sensor_hardware` for `sensor_em` | no (type-dispatched) | fix the pooled-overwrite bug (sensor section above); otherwise unchanged |
| `em_noise` getter [ship.gd:171-176](scripts/ships/ship.gd:171) | `sensor_hardware` | sensor-only | swap to `get_components_by_type("sensors")` |
| `_run_sensor_sweep()` [ship.gd:808](scripts/ships/ship.gd:808) | `sensor_hardware` entry | sensor-only | origin derivation + `sensor_type` rename |
| sweep dispatch/timer loop [ship.gd:684-703](scripts/ships/ship.gd:684) | `sensor_hardware`, `parent` fallback | sensor-only | drop `parent`, iterate `get_components_by_type("sensors")` |
| EM summation [ship.gd:652-657](scripts/ships/ship.gd:652) | `sensor_hardware` | sensor-only | same swap |
| `set_sensor_state()` / `set_all_sensors_state()` [ship.gd:474-495](scripts/ships/ship.gd:474) | `sensor_hardware` | sensor-only | same swap |
| `set_sensor_target()` [ship.gd:496](scripts/ships/ship.gd:496) | neither (just sets `manual_sensor_target`) | n/a | none |
| `get_signature()` [ship.gd:319-333](scripts/ships/ship.gd:319) | `sensor_hardware` via `sensor_config` | sensor-only | swap to `get_components_by_type("sensors")` |
| `_physics_process` cooldown loop [ship.gd:504-510](scripts/ships/ship.gd:504) | `weapons` | weapon-only | swap to `get_components_by_type("weapons")` |
| `fire_weapon()` [ship.gd:995-1129](scripts/ships/ship.gd:995) | `weapons` | weapon-only | `get_component(weapon_id)`, `weapon_type` rename, `get_component_origin()` |
| `_process_point_defense()` [ship.gd:1131-1186](scripts/ships/ship.gd:1131) | `weapons` + `ship_components` (currently both!) | weapon-only | collapses to one structure; closes the `mount_pos`/`rect.position` divergence |
| `engineering_panel.gd` component list/health display [eng-panel:94-117,325-326](scripts/engineering_panel.gd:94) | `ship_components` (via network state dict) | yes | none — already generic |
| `missile_controller.gd:94` | `sensor_hardware` | sensor-only | swap to `get_components_by_type("sensors")` |
| `weapons_panel.gd:100-104` | `weapons` | weapon-only | iterate array, index by `["id"]`/`["ammo"]` |
| `navigation_panel.gd:239-244` | `weapons` (via network state dict) | weapon-only | iterate array instead of dict |
| `main.gd:229,231` | `ship.sensor_hardware`, `ship.weapons` | both | both swap to `get_components_by_type(...)` |
| `tests/test_sensor_stealth.gd:54,101` | `sensor_hardware` | sensor-only | swap to `get_components_by_type("sensors")` |
| `tests/test_component_states.gd:169-211` | `ship_components` ids `hp_sensor_fwd`/`hp_sensor_omni` | sensor-only | update ids to new split sensor ids |
| `tests/test_damage_propagation.gd:76` | `ship_components` id `hp_sensor_fwd` | sensor-only | update id to `dir_high_res` |

Everything in the "type-agnostic / none" rows is the proof the interface generalizes cleanly: those functions already operate purely through `c["type"]`, `c["id"]`, or `c["rect"]` and don't care whether the component is a sensor, a weapon, a reactor, or a hull plate. The work in M1 is entirely in the rows that *aren't* agnostic yet — collapsing the two type-specific side-structures (`sensor_hardware`, `weapons`) into the same generic shape everything else already uses.

### Missile

`missile.gd` already does this correctly for its one sensor (`sensor_nose` + `seeker` joined via explicit `"parent"`) — it just collapses to one merged entry instead of two:

```gdscript
ship_components = [
    {"id": "seeker", "type": "sensors", "rect": Rect2(5, -2, 5, 4), "health": 10.0, "max_health": 10.0,
     "density": 0.2, "heat": 0.0, "em_emission": 10.0,
     "sensor_type": "active", "active": true, "heading": 0.0, "arc_width": PI / 1.5,
     "range": 30000.0, "resolution": 5.0, "timer": 0.0, "refresh_interval": 0.1, "num_bins": 60},
    {"id": "warhead", "type": "hull", ...},
    {"id": "hull_body", "type": "hull", ...},
    {"id": "engine_main", "type": "engines", ...}
]
```

No more separate `sensor_hardware` array in `missile.gd` either.

### Sensor Drone

`scripts/ships/sensor_drone.gd` wasn't in the original audit — it has the same problem as the frigate, just smaller: one physical box (`hp_sensor_omni`) hosting one logical sensor (`omni_main`), joined by the same `parent`-fallback default (`sensor.get("parent", ... else "hp_sensor_omni")` resolves to `hp_sensor_omni` for anything that isn't `dir_high_res`, which is exactly what happens here since the drone's only sensor is `omni_main`). Since it's already 1:1, the fix is a straight merge, no box-splitting needed:

```gdscript
ship_components = [
    {"id": "hull_center", "type": "hull", "rect": Rect2(-10, -10, 20, 20), "health": 200.0, "max_health": 200.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
    {"id": "reactor_core", "type": "reactor", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 0.9, "heat": 0.0, "em_emission": 0.0},
    {"id": "omni_main", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 50.0, "max_health": 50.0, "density": 0.4,
     "heat": 0.0, "base_em_emission": 50.0, "em_emission": 50.0,
     "sensor_type": "active", "active": true, "heading": 0.0, "arc_width": TAU,
     "range": 40000.0, "resolution": 10.0, "timer": 0.0, "refresh_interval": 1.0, "num_bins": 36}
]
```

(`refresh_interval`/`num_bins` weren't set in the original `sensor_hardware` entry — it was missing those fields entirely, which would have hit `sensor["num_bins"]`/`sensor["refresh_interval"]` key errors in `_run_sensor_sweep` the moment this drone's sensor actually ran a sweep. Filling in reasonable values, matching `omni_main`'s frigate equivalent, is a bugfix that falls out of the merge — worth a quick check of whether `SensorDrone` has ever actually been exercised by a test or scene, since this suggests it may not have been.)

`weapons = {}` ([sensor_drone.gd:5](scripts/ships/sensor_drone.gd:5)) is simply deleted — once the `weapons` Dict no longer exists as a concept, "no weapons" is just the absence of any `"weapons"`-type entry in `ship_components`, which is already true here.

---

## Code changes in `ship.gd`

- **Delete** the `sensor_hardware` var ([ship.gd:376-446](scripts/ships/ship.gd:376)).
- **Delete** the `parent`/fallback line ([ship.gd:685](scripts/ships/ship.gd:685)) — `is_component_powered(sensor["id"])` and `get_component_health_ratio(sensor["id"])` now resolve directly since the sensor *is* the component.
- Add a small helper to avoid repeating `for c in ship_components: if c["type"] == "sensors"` everywhere:
  ```gdscript
  func get_components_by_type(type: String) -> Array:
      return ship_components.filter(func(c): return c["type"] == type)
  ```
- Update every `for s in sensor_hardware:` loop to `for s in get_components_by_type("sensors"):`:
  - sweep timer/dispatch loop ([ship.gd:684-703](scripts/ships/ship.gd:684))
  - EM summation loop ([ship.gd:655-657](scripts/ships/ship.gd:655))
  - `set_sensor_state`, `set_all_sensors_state` ([ship.gd:474-495](scripts/ships/ship.gd:474))
  - `get_signature()` sensor_config field ([ship.gd:330-331](scripts/ships/ship.gd:330))
- `_run_sensor_sweep(sensor: Dictionary, ...)` keeps its signature — it already takes a generic dict, and now that dict is the merged component entry. Two internal changes: the `"type"` → `"sensor_type"` field rename ([ship.gd:836,862,891](scripts/ships/ship.gd:836)), and swapping the sweep/ray origin from ship-center `position` to `position + get_component_origin(sensor).rotated(rotation)` at every origin use in the function ([ship.gd:815,834,840,856,874](scripts/ships/ship.gd:815)) per the hardpoint-origin section above.
- Fix the heat/EM overwrite bug while touching this code ([ship.gd:671-673](scripts/ships/ship.gd:671)): compute each sensor's own `em_emission` contribution (`base_em_emission * sensor_power_ratio`) instead of writing the ship-wide pooled `sensor_em` into every component.

## Other call sites to update

| File | Line | Change |
|---|---|---|
| [main.gd:229](scripts/main.gd:229) | `"sensor_config": ship.sensor_hardware.duplicate(true)` | `ship.get_components_by_type("sensors")` |
| [missile_controller.gd:94](scripts/missile_controller.gd:94) | `for s in ship.sensor_hardware:` | `for s in ship.get_components_by_type("sensors"):` |
| [tests/test_sensor_stealth.gd:54,101](scripts/tests/test_sensor_stealth.gd:54) | `for s in ship_a.sensor_hardware:` | same helper swap |
| [tests/test_component_states.gd:169-211](scripts/tests/test_component_states.gd:169) | `_set_component("hp_sensor_fwd"/"hp_sensor_omni", ...)` | update ids to one of the five new sensor ids (e.g. `dir_high_res`, `omni_main`) since those box ids no longer exist |
| [tests/test_damage_propagation.gd:76](scripts/tests/test_damage_propagation.gd:76) | `if c["id"] == "hp_sensor_fwd":` | same id update to `dir_high_res` |
| [ship.gd:174](scripts/ships/ship.gd:174) | `em_noise` getter: `for s in sensor_hardware: if s.get("active", true): noise += 5.0` | `for s in get_components_by_type("sensors"): if s.get("active", true): noise += 5.0` |

`engineering_panel.gd`, `navigation_panel.gd`, `sensor_module_ui.gd` already iterate `ship_components` generically by type rather than hardcoding old sensor ids, so they need no changes — confirmed by grep, worth a smoke-test pass after the migration regardless.

---

## Behavior architecture: where does weapon-variety logic live?

Everything above is the *data* shape. It doesn't answer where the *logic* for "lots of additional weapon variety" goes, and today the answer is "all of it, inline, in `Ship`": `fire_weapon()` already branches `if w_type == "laser": ... elif w_type == "missile": ...` for targeting rules, hit resolution, and projectile spawning ([ship.gd:1055-1129](scripts/ships/ship.gd:1055)); `_process_point_defense()` separately hardcodes laser-only PD logic; the per-frame loop branches on component `type` for heat/EM. Every new weapon class adds another `elif` to multiple functions in an already-1200-line file. That's the thing to fix before, not after, weapon variety grows.

**Decision: keep `ship_components` as pure data (per the schema above), move per-class logic into stateless behavior objects, one script per weapon class, looked up through a registry keyed by `weapon_type`.** `Ship` stops knowing what a laser or a railgun *does*; it knows how to ask "whoever handles `weapon_type` X" to do it.

**Decided: the behavior owns *all* preconditions, not just class-specific ones — `Ship` doesn't check ammo/cooldown itself.** The alternative (Ship owns the generic ammo/cooldown gate, behaviors only add extras) was rejected: it puts firing logic in two places, and it can't express a weapon class that doesn't use ammo/cooldown the same way (a capacitor weapon checking charge instead of ammo, a railgun needing a charge-up phase before `cooldown <= 0` is even the right test). `can_fire()` is the single source of truth for "can this fire right now," full stop. The base class still provides the common ammo/cooldown check as a default so most behaviors don't repeat it:

```gdscript
# scripts/components/weapon_behavior.gd
class_name WeaponBehavior

func can_fire(ship: Ship, comp: Dictionary, target_contact_id: String) -> bool:
    return comp["ammo"] > 0 and comp["cooldown"] <= 0.0

func execute_fire(ship: Ship, comp: Dictionary, target_pos: Vector2, target_contact_id: String) -> void:
    pass # override per class

func tick(ship: Ship, comp: Dictionary, delta: float) -> void:
    pass # override per class — heat/EM lifecycle, charge-up, etc.

func _consume_default(comp: Dictionary) -> void:
    comp["ammo"] -= 1
    comp["cooldown"] = comp["cooldown_max"]
```

`_consume_default()` exists so "behavior owns it" doesn't mean every class reimplements identical ammo-decrement/cooldown-reset boilerplate — most `execute_fire()` overrides just call it, the way they'd call `super.can_fire()` for the common precondition. A class with genuinely different resource semantics (capacitor charge instead of ammo) overrides both and ignores `_consume_default()` entirely.

```gdscript
# scripts/components/weapons/laser_behavior.gd
class_name LaserBehavior
extends WeaponBehavior

const FIRE_EM_SPIKE := 50.0
const EM_PULSE_DECAY := 25.0 # per second

func can_fire(ship, comp, target_contact_id) -> bool:
    return super.can_fire(ship, comp, target_contact_id) and ship.active_contacts.has(target_contact_id)

func execute_fire(ship, comp, target_pos, target_contact_id) -> void:
    # the existing hitscan body from fire_weapon's "laser" branch moves here unchanged
    _consume_default(comp)
    comp["em_pulse"] = FIRE_EM_SPIKE

func tick(ship, comp, delta) -> void:
    comp["em_pulse"] = max(0.0, comp.get("em_pulse", 0.0) - EM_PULSE_DECAY * delta)
    comp["em_emission"] = comp["base_em_emission"] + comp["em_pulse"]
```

A stateless registry resolves `weapon_type` to its behavior singleton — no per-instance allocation, because all runtime state (`em_pulse`, `cooldown`, `ammo`) already lives in the component dict, not the behavior object:

```gdscript
# scripts/components/weapon_behavior_registry.gd
const BEHAVIORS = {
    "laser": preload("res://scripts/components/weapons/laser_behavior.gd"),
    "missile": preload("res://scripts/components/weapons/missile_behavior.gd"),
}
static var _instances := {}

static func get_behavior(weapon_type: String) -> WeaponBehavior:
    if not _instances.has(weapon_type):
        _instances[weapon_type] = BEHAVIORS[weapon_type].new()
    return _instances[weapon_type]
```

`Ship.fire_weapon()` shrinks to: validate authority/ownership → `get_component(weapon_id)` → `if not behavior.can_fire(self, comp, target_contact_id): return` → `behavior.execute_fire(self, comp, target_pos, target_contact_id)`. `Ship` no longer touches `ammo`/`cooldown` directly anywhere in this path — that's entirely the behavior's job now.

**PD eligibility stays hardcoded for now, by choice.** `_process_point_defense()`'s `ready_lasers` filter keeps checking `w["weapon_type"] == "laser"` directly in `Ship` — we're deliberately not adding a `is_pd_capable()` interface hook until a second PD-capable weapon class actually exists; speculative interface surface for a case we don't have yet isn't worth it. What *does* change: once PD has picked a candidate weapon and target, it calls that weapon's `behavior.can_fire(self, comp, c_id)` / `behavior.execute_fire(self, comp, body.position, c_id)` instead of re-implementing hit application inline — PD already has a contact id (`for c_id in active_contacts:`) and a target body, so it can reuse exactly the same call `fire_weapon()` makes. That still removes the duplicate hit-resolution code (and the `mount_pos`/`rect.position` divergence) between the two call paths; it just doesn't generalize *which* weapons PD considers firing in the first place. Revisit `is_pd_capable()` when a second PD weapon class shows up.

The per-frame loop replaces its `elif comp["type"] == "weapons": comp["heat"] = ...` branch with `WeaponBehaviorRegistry.get_behavior(comp["weapon_type"]).tick(self, comp, delta)`.

**Rule of thumb for what goes where** (the same lesson as the `mount_pos`/`rect.position` duplication earlier in this doc): *runtime state* that differs per instance and needs to be saved/networked/inspected (`em_pulse`, `cooldown`, `ammo`) lives in the component dict. *Class-level constants and logic* that's the same for every laser on every ship (`FIRE_EM_SPIKE`, the targeting/hit-resolution algorithm) lives once in the behavior script. Don't let a tunable constant leak into every component instance's dict — that's exactly the duplication this whole document has been removing.

**This generalizes to the rest of M2 for free.** `responsive_heat_em.md`'s cases — reactor whiteout on death, engine EM spike when damaged, heat burst on taking a hit — are the same "lifecycle pulse on `comp[...]`, decayed in `tick()`" pattern, just triggered by different events (death, damage, impact) instead of firing. M2 becomes "add a `ReactorBehavior`/`EngineBehavior`/`HullBehavior` with a `tick()` that manages its own pulse fields," not a second rewrite of `Ship`'s update loop. Sensors don't need this layer yet — all five sensor classes share one sweep algorithm (`_run_sensor_sweep`) and differ only by data (range, arc, bins), which the M1 schema above already covers; introduce `SensorBehavior` only if a sensor class needs genuinely different sweep logic, not just different numbers.

**Answering "will it all live in the Ship class?": no, but not everything moves either.** `Ship` keeps: physics integration (forces/torque on the `RigidBody2D`), the generic `ship_components` data and the M1 accessor interface (`get_component`, `get_components_by_type`, `get_component_origin`, `is_component_powered`, ...), contact/target list management, and the per-frame loop that *drives* behaviors. What moves out: anything that branches on `weapon_type` (or, later, `sensor_type`/component class) to decide *what a class of component does*. `Ship` is the chassis; behavior scripts are the parts catalog.

**Migration is additive and low-risk to start.** Step one is a pure refactor with no behavior change: cut the existing `if w_type == "laser": ...` / `elif w_type == "missile": ...` bodies out of `fire_weapon()` verbatim into `LaserBehavior.execute_fire()` / `MissileBehavior.execute_fire()`, same for the PD loop's laser-only logic into `LaserBehavior.can_fire()`. The lifecycle-EM feature (and every future weapon class) is then the first thing built *on top of* the new structure rather than bolted into `Ship`.

---

## Scope boundary for M1 (what's *not* in this pass)

`ship_is_the_parts.md` also calls for component-driven **mass** and **power-rating** (today `mass`, `reactor_power_rating`, `engine_power_rating` are flat ship-level vars, not summed from components — confirmed: `mass = 100.0` is hardcoded in `_ready()`, and component `density` is only used for damage ablation, never for mass). That's real future work for the "dual reactor" / "ship design validator" parts of the doc, but it's a separable change from the sensor-dome fix and isn't needed to unblock M2 (dynamic heat/EM) or M3-M6. Treat it as **M1b**, scoped later, once the sensor merge has proven the pattern out.

**M1b is done — see the section below.** `mass` ended up derived from `rect` area × `density` (no authored field), and `density` itself got unified to one shared scale across all ship classes as part of that.

The behavior-architecture layer above is **M1c**: it doesn't block the sensor/weapon data merge (steps 1-8 below work today with the existing inline `elif` dispatch, just on the merged schema), but it should land before M2 or before any new weapon class is added — otherwise M2's event-driven heat/EM and the next weapon type both get built against the dispatch style we already know doesn't scale.

## Migration steps (ordered)

1. Add the three new generic helpers (`get_components_by_type`, `get_component`, `get_component_origin`) to `ship.gd`.
2. Rewrite `Ship.ship_components` sensor entries per the sensor layout table; delete `sensor_hardware`.
3. Update every sensor call site in the interface audit table (sensor rows).
4. Fix the per-sensor EM/heat overwrite bug as part of the heat/EM loop rewrite.
5. Rewrite `Missile.ship_components` to the merged `seeker` entry; delete its `sensor_hardware`.
6. Rewrite `SensorDrone.ship_components` to the merged `omni_main` entry (filling in the missing `refresh_interval`/`num_bins` fields per the Sensor Drone section); delete its `sensor_hardware` and `weapons = {}`.
7. Fold `weapons` fields into the matching `ship_components` weapon entries; delete the `weapons` Dict.
8. Update every weapon call site in the interface audit table (weapon rows), including `_process_point_defense`'s switch to `get_component_origin()` (this is the line that fixes the `mount_pos`/`rect.position` divergence).
9. Run the full regression surface: `test_component_states.gd`, `test_damage_propagation.gd`, `test_sensor_stealth.gd`, `test_missile_ai.gd`, `test_classifiers.gd`, `test_classifiers_e2e.gd`, `test_point_defense.gd`, `test_e2e_drone_vs_bouy.gd`.
10. **(M1c)** Add `WeaponBehavior`/`WeaponBehaviorRegistry` under `scripts/components/`; lift the existing laser/missile `elif` bodies into `LaserBehavior`/`MissileBehavior` verbatim, with `_consume_default()` replacing the inline ammo/cooldown mutation (no behavior change otherwise). Re-run the same regression suite to confirm the lift was behavior-preserving.

**Done when:** no references to `sensor_hardware`, `weapons` (the Dict), `parent`, or `mount_pos` remain in `scripts/`; `fire_weapon` and `_process_point_defense` read weapon origin through the same `get_component_origin()` call and delegate firing to `WeaponBehavior`; and the full regression suite above passes.

---

## M1b: component-driven mass and power rating

`reactor_power_rating`/`engine_power_rating`/`mass` were flat ship-level vars, not summed from `ship_components` — the same "ship-wide constant standing in for a component property" pattern M1 already fixed for sensors (`base_em_emission`) and M1c fixed for weapon EM pulses. Tracing the per-frame heat/EM loop turned up the identical *pooled-overwrite* bug M1 found and fixed for sensors, just not yet fixed for `reactor`/`engines`: `comp["em_emission"] = reactor_power_rating` wrote the **ship-wide** total into *every* component of type `"reactor"`, and the same for `"engines"` — invisible with exactly one of each, but wrong the moment a ship has two.

It also turned up two bugs unrelated to mass/power but found while tracing the same code:

- **Missile has zero `"reactor"`-type components.** `take_damage()`'s death check is `get_sys_health("reactor") <= 0.0 or get_sys_health("hull") <= 0.0` — with no reactor component, `get_sys_health("reactor")` is permanently `0.0`, so *any* hit at all instantly hulks a missile regardless of damage dealt. `test_point_defense.gd` doesn't catch this because it only asserts "eventually dead," not "took exactly one hit." Fixed by giving `Missile` a tiny `reactor_core` component (5 HP) standing in for "too small for a full reactor, uses a capacitor instead" (`ship_is_the_parts.md`'s own suggested explanation) — missiles now need that capacitor (or full hull loss) destroyed to die, which means they may survive more PD hits than they effectively did before. Approved as an intentional behavior change, not just a refactor.
- **Dead overheat-damage check**: `if c["id"] == "reactor":` never matched anything (the actual id is `reactor_core`; no component has id `"reactor"`) — overheating never actually damaged the reactor. Fixed to check `c["type"] == "reactor"`.

### Decision: mass is static, derived from `rect` area × `density` (no authored field)

Two axes were decided here, both resolved by discussion rather than left as authored data:

**Static vs. dynamic.** Static (compute once, at `_ready()`) vs. dynamic (recompute every frame so destroyed/unpowered components reduce mass, simulating jettisoned debris). Went with **static** — nothing in `ship_is_the_parts.md`'s motivating examples (dual reactor, dual engine) asks for mass to react to damage, only power. Dynamic mass is a real future option if "venting/jettisoned debris" ever becomes a desired mechanic, but it's a gameplay feature, not implied by this milestone.

**Authored `mass` field vs. derived from `density`.** First pass authored a `mass` literal per component (proportional to `max_health` share, tuned to reproduce today's flat totals exactly). Reconsidered: `density` already exists per component and already means "how much material is here" — it drives the damage-ablation absorption rate in `take_damage()`. Reusing it for mass instead of inventing a parallel field is more architecturally honest, *if* the scale problem can be solved without changing ablation behavior.

The scale problem: today's `density` values were tuned purely for ablation feel — flat `20.0` across every Frigate component regardless of type, varied `0.2`-`0.9` per component on Missile/SensorDrone. `rect.size.x * rect.size.y * density` for Frigate's `hull_fwd` alone comes out to `450 * 20 = 9000`, dwarfing the ship's current total mass of `100`. Resolution: **introduce one shared scale constant** (`MASS_SCALE = 100.0 / 55500.0`, calibrated so Frigate's own loadout — area `2775` × density `20.0` — reproduces its existing mass of `100.0` exactly) rather than touching `density`'s ablation role at all:

```gdscript
const MASS_SCALE := 100.0 / 55500.0

func get_ship_mass() -> float:
    for c in ship_components:
        var area = c["rect"].size.x * c["rect"].size.y
        total += area * c["density"] * MASS_SCALE
    return total
```

**Density is also unified to the same `20.0` scale across ship classes**, not just Frigate — Missile and SensorDrone's per-component density variation (`0.2`-`0.9`) wasn't meaningful (nothing depended on one missile component being denser than another), so both were flattened to `20.0` too. Consequence: mass is no longer preserved exactly for those two ships — Missile drops from `20.0` to `~5.98`, SensorDrone from `200.0` to `~16.2` (smaller craft, same "stuff," less of it). SensorDrone's drop is free (its `max_thrust` is already `0.0` — no thrust tuning depends on its mass). Missile's drop is **not** free: `max_thrust` was retuned from `10000.0` to `2991.0` (`10000 * 5.98/20`) to keep the exact same `thrust/mass` ratio, preserving today's acceleration feel. `max_torque`/`max_omega` were left untouched since rotational dynamics key off `inertia`, a separate hand-tuned constant unaffected by this change.

One accepted tradeoff: flattening Missile's density to `20.0` (a ~34x jump from its previous ~`0.58` average) also raises its ablation absorption cap (`effective_density * step_size * 50`) above a typical hit's damage, so a single hit now resolves entirely against whichever component the ray touches first, rather than spreading across 2-3 of Missile's tiny components as it does today. Accepted deliberately — at Missile's scale, every component is small enough that losing any one of them is comparable to losing the missile outright, so which specific component absorbs the hit doesn't meaningfully change the PD-vs-missile balance already tuned earlier in this milestone.

### Decision: power rating sums across components by type, weighted by health

```gdscript
func get_total_power_rating(sys_type: String) -> float:
    for c in ship_components:
        if c["type"] == sys_type and is_component_powered(c["id"]):
            total += c.get("power_rating", 0.0) * get_component_health_ratio(c["id"])
    return total
```

This is the literal "sum from components" framing `ship_is_the_parts.md` uses for the dual-reactor case ("two different reactors were providing power, but now one is, and one is enough") — losing one reactor/engine degrades the total instead of being unnoticed.

`get_power_ratio(sys_type)` (= `get_total_power_rating(sys_type) / get_max_power_rating(sys_type)`, or `0` if no components of that type exist) generalizes the old hardcoded single-id checks — `is_component_powered("engine_main")` / `get_component_health_ratio("engine_main"/"reactor_core")` — to thrust/torque/heat-dissipation gating. For a ship with exactly one component of a type (every ship today), it's numerically identical to the old single-id check; the generalization only matters once a ship has two. Per-component `em_emission` in the dispatch loop now uses each component's own `power_rating * get_component_health_ratio(...)` instead of the pooled ship-wide value, closing the bug above.

**Open question, still pending:** whether `get_power_ratio` stays in this form. It exists only because `max_thrust`/`max_torque`/`max_omega`/`heat_dissipation_rate` are still flat ship-level design constants tuned assuming "fully healthy, fully powered" = `1.0`, so `get_total_power_rating(type)` (an absolute, already-derived value) has to be normalized back down to a 0-1 fraction before it can scale them. If `power_rating` ever became a physically-derived absolute the way `mass` now is, those four constants could plausibly be replaced by direct component sums and `get_power_ratio` would have nothing left to normalize against. Not pursued in this pass — flagged for a future milestone if/when `power_rating` gets the same treatment `density`/mass just did.

**Done when (M1b):** `reactor_power_rating`/`engine_power_rating` ship-level vars no longer exist; `mass` is derived from `rect` area × `density` × `MASS_SCALE` (no authored `mass` field anywhere); thrust/torque availability and heat dissipation are derived from `ship_components` via `get_power_ratio()`; `density` is unified to the same `20.0` scale across Frigate/TargetDrone/Missile/SensorDrone; the per-component EM pooled-overwrite bug is fixed for `reactor`/`engines` the same way M1 fixed it for `sensors`; and the full regression suite (10 tests, including `test_helm_input.gd`/`test_inertial_flight.gd`) passes.
