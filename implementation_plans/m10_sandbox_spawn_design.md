# M10 — Sandbox Spawn UI (friendly / enemy / pirate)

Parent: [m9_ship_catalog_design.md](m9_ship_catalog_design.md). Source: the
"sandbox" thread of `design_ideas/ship_designs.md`.

**Pulled forward from "deferred M10+" by explicit request:** this is the *test
instrument* for the whole catalog. Without it, trying each new ship means a code
edit every time. Building it now makes every M9c ship immediately playable the
moment it's authored — so it should land alongside / just before M9c.

**Subset, by decision:** teams are **friendly / enemy / pirate** only. **Neutral
is out of scope** — a neutral/beacon faction needs the IFF-beacon classification
path (M7) so it doesn't read as `UNIDENTIFIED`; that's a separate feature set.

## Why this is cheap now (the pieces already exist)

- **Hull/role already separated (M9a):** a spawned ship is just `<HullClass>.new()`
  + an `AIDroneController` child node. No per-ship spawn code.
- **Teams already modeled as `iff_tags`:** and the AI already targets any contact
  classified `"UNIDENTIFIED VESSEL"` — i.e. any vessel whose `iff_tags` don't
  overlap the observer's ([ai_drone_controller.gd:25](../scripts/ai_drone_controller.gd:25)).
  So team behavior falls straight out of tag assignment, no AI changes.
- **UI is code-built:** `main.tscn` only holds the menu + a `TerminalDisplay`
  Control; gameplay panels are constructed programmatically. The spawn panel is
  the same — no Godot-editor work, implementable headlessly.

## Team → `iff_tags` mapping (the whole mechanic)

The player's reference tags are read from the player ship (fallback
`["TEAM_PLAYER"]`).

| Team | `iff_tags` | Resulting behavior |
|------|-----------|--------------------|
| Friendly | player's tags (`TEAM_PLAYER`) | classified `FRIENDLY VESSEL` — AI never targets it; it fights *for* the player |
| Enemy | shared `["TEAM_ENEMY"]` | hostile to player + pirates; allied to other enemies |
| Pirate | **unique** `["PIRATE_<owner_id>"]` | shares with no one → hostile to everyone incl. other pirates (true FFA) |

The pirate tag MUST be unique per spawn — a shared `"PIRATE"` tag would make
pirates see each other as friendly, defeating FFA.

## Components to build

1. **`scripts/ship_catalog.gd`** (`class_name ShipCatalog`) — the single list of
   spawnable combat hulls:
   ```gdscript
   const SPAWNABLE := [
       { "name": "Frigate", "script": preload("res://scripts/ships/frigate.gd") },
       # M9c ships append here -> they auto-appear in the dropdown.
   ]
   ```
   This is the one place M9c registers a new ship. (Buoy/SensorDrone are
   non-combat — excluded for now, or a later second list.)

2. **Team enum + mapping helper** — `enum Team { FRIENDLY, ENEMY, PIRATE }` and a
   `static func iff_for(team, owner_id, player_tags) -> Array`. Put it on
   `ShipCatalog` or a small `SpawnDirector` — keep it static/testable.

3. **Spawn director in `main.gd`** — generalize the existing `_spawn_drone()` into
   `_spawn_ship(ship_script, team)`:
   - `var inst = ship_script.new()`
   - `owner_id = <next id>`; `iff_tags = ShipCatalog.iff_for(team, owner_id, player_tags)`
   - position near the player at a fixed test range (reuse `_spawn_drone`'s
     15000-unit offset)
   - attach `AIDroneController` as a child
   - `add_child(inst)`; `players[owner_id] = inst`
   - `_spawn_drone()` becomes a thin wrapper (or the F3 key routes through the
     director with team = ENEMY) so nothing regresses.

4. **Spawn panel** (code-built `Control`, e.g. `scripts/panels/spawn_panel.gd`) —
   added under `CanvasLayer` when a single-player/host session starts:
   - `OptionButton` populated from `ShipCatalog.SPAWNABLE` (ship class)
   - team selector: 3 buttons or an `OptionButton` (Friendly / Enemy / Pirate)
   - a **Spawn** button → calls `_spawn_ship(selected_script, selected_team)`
   - toggle visibility with a key (e.g. `F2`), or a small always-visible corner
     panel — pick whichever is least intrusive over the terminal UI.

## Done when

In a running single-player session, the player can pick a ship class + team from
the UI, click Spawn, and watch the ship appear and behave per team (friendly
fights alongside; enemy/pirate engage; pirates also fight each other) — with no
code edit to switch ships or teams.

## Forward link to M9b

Once `ShipCatalog` exists, `test_ship_designs.gd` should iterate
`ShipCatalog.SPAWNABLE` and run `ShipDesignValidator.validate()` on each, so
every spawnable ship is guaranteed spec-valid — not just the Frigate. (Add this
when the catalog has >1 entry, i.e. during M9c.)

## Deferred (not now)

- **Neutral / beacon team** → needs M7 (IFF beacons + a neutral classification
  bucket so it isn't auto-engaged as `UNIDENTIFIED`).
- Spawn-at-cursor, spawn-count, despawn / clear-all buttons — nice-to-haves.
- Multiplayer spawn replication — keep the current host-side spawn assumption
  (`_spawn_drone` is already host-only).

**Touches:** new `scripts/ship_catalog.gd`, new spawn-panel script,
`scripts/main.gd`.
