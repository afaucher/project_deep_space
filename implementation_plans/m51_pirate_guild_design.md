# M51 — Pirate guild director: detailed design

Parent: [m48_m55_economy_piracy_roadmap.md](m48_m55_economy_piracy_roadmap.md);
the director pattern (ledger + policy tick, the director honesty rule) is in
[jobs_and_itineraries.md](../design_ideas/jobs_and_itineraries.md) §3 — read
it first. Deliverable: the piracy loop becomes self-sustaining — kill the
pirate and a replacement "trader" comes through the wormhole minutes later
under a fresh cover identity; success breeds more pirates (bounded), losses
thin them (floored at 1). No player-facing surface except a debug toggle —
the guild is an invisible hand.

## Grounding facts (verified against source)

- `ClusterManager` (scripts/cluster/cluster_manager.gd): `records: Array`
  of ClusterEntity; `tick(dt)` dead-reckons dormant movers then
  `_reconcile()`s liveness; `_promote(rec)` builds `rec.hull_script.new()`,
  applies `rec.name` → ship_name, `rec.iff_tags`, `rec.transponder_flag`
  (AFTER add_child), then `_attach_ai(rec, node)` which switches on
  `rec.behavior` (route/cargo keys today). `_demote(rec)` reads state back
  and frees. Tests drive `tick()` manually for determinism (viewpoint_node
  null).
- **The cluster layer has NO concept of death.** Nothing notices a live
  ship became a hulk (`is_dead == true`; hulks are never freed, so
  `rec.is_live()` stays true). If a hulk's record ever demoted and
  re-promoted, `_promote` would resurrect a fresh, alive hull. M51 fixes
  this where it bites (LOST pirates' records are removed); the general
  traffic case is filed as a separate follow-up task.
- Wormhole: a record with `kind == ClusterEntity.Kind.WORMHOLE` ("Nexus
  Wormhole", home_cluster.gd id 500). Cargo lanes: TRAFFIC records whose
  `behavior` carries `{"route": [a, b], "cargo": true}` — public knowledge
  a guild plausibly has (they watch the lanes). The director derives BOTH
  from `records` at tick time instead of carrying authored copies.
- M50 surface: `build_pirate()` (ai_tree_factory), `assign_job(job)` +
  `loot_takes` (ship.gd), the canonical hunt job shape
  (implementation_plans/m50_pirate_tree_design.md), pirate hulls
  `pirate_ore_shuttle.gd` / `armed_pinnace.gd`.
- Debug knobs: append ONE entry to the `DebugSettings` autoload's
  `OPTIONS` registry; read with `DebugSettings.get_choice(key)` (CLAUDE.md).

## New: `scripts/directors/pirate_guild.gd`

RefCounted (preload-const convention, standing.gd-style header). Owned by
and ticked from ClusterManager:

- `ClusterManager` gains `var directors: Array = []` and, at the end of
  `tick(dt)`: `for d in directors: d.tick(dt, self)`. That's the ENTIRE
  cluster-manager surface for directors (plus the `_attach_ai` branch
  below). Campaign bootstrap (wherever home_cluster's ClusterManager is
  wired — follow the existing load path) appends a configured PirateGuild;
  the sandbox gets none.
- Construction: `PirateGuild.new(config: Dictionary)`. Config is DATA (the
  M54 story-phase lever), with defaults:

```gdscript
{
  "policy_period": 10.0,        # s between policy passes (dt-accumulated)
  "presumed_lost_delay": 45.0,  # OVERDUE -> resolved, s
  "arrival_window": [120.0, 300.0],  # eta roll, s
  "base_cap": 1, "max_cap": 3,       # floor of 1 pirate, bounded growth
  "takes_per_cap_raise": 2,     # take_streak needed to raise the cap
  "losses_per_cap_cut": 2,      # loss_streak needed to cut it
  "cashin_radius": 8000.0,      # "vanished near the wormhole" = cashed out
  "hull_mix": [pirate_ore_shuttle, armed_pinnace],  # scripts, alternated
  "name_pool": ["Fair Trader", "Slow Light", ...],  # cover + relight names
}
```

  Tests pass a FAST config (period 0.5, delay 2.0, window [4, 8]) — config
  is data, so this is legitimate tuning, not a test backdoor.

## The ledger (plain serializable state on the guild)

- `members: Dictionary` — record_id → `{state, cover_name, relight_name,
  last_seen_pos, last_loot_takes, overdue_since}` with states
  `SCHEDULED | ACTIVE | OVERDUE | LOST | CASHED_OUT` (resolved members are
  kept for the ledger's history; they hold no record refs).
- `arrivals: Array` — `[{eta_remaining, cover_name, relight_name, hull_idx}]`.
- Totals: `takes_total, losses, take_streak, loss_streak, cap`.
- Nothing here references live nodes across ticks — record ids and plain
  values only (serializable for saves later).

## The policy tick

`tick(dt, cluster)` accumulates dt; every `policy_period`:

1. **Check-ins** (the honesty rule made mechanical — the director reads
   only its OWN members' state, the fiction of a radio report): for each
   ACTIVE member, find its record. Live and not dead → refresh
   `last_seen_pos` / `last_loot_takes` (read off the live node). Dead,
   record gone, or node gone → `OVERDUE` with `overdue_since` stamped
   (once — don't re-stamp).
2. **Resolve overdue** past `presumed_lost_delay`: vanished (NOT observed
   dead) with `last_seen_pos` within `cashin_radius` of the wormhole →
   `CASHED_OUT`: `takes_total += last_loot_takes`, `take_streak += 1`,
   `loss_streak = 0`. Anything else (observed dead, or vanished elsewhere)
   → `LOST`: `losses += 1`, `loss_streak += 1`, `take_streak = 0`, and
   **erase the member's ClusterEntity from `cluster.records`** (the hulk
   node stays in the world as ordinary wreckage; the record must go or the
   cluster will eventually resurrect it — the death gap above).
3. **Cap adjust**: `take_streak >= takes_per_cap_raise` → `cap += 1`
   (clamped to max_cap), reset take_streak; `loss_streak >=
   losses_per_cap_cut` → `cap -= 1` (clamped to base_cap), reset
   loss_streak.
4. **Floor**: while `active_count + overdue_count + arrivals.size() < cap`
   → schedule an arrival: `eta_remaining = randf_range(window[0],
   window[1])` (global seeded RNG — determinism under the test seed),
   cover + relight names drawn from `name_pool` avoiding names in use by
   ACTIVE/SCHEDULED members, hull alternating through `hull_mix`.
5. **Spawn due arrivals** (`eta_remaining -= policy_period`, spawn at
   <= 0): build a ClusterEntity — kind TRAFFIC, `name = cover_name`,
   `hull_script = hull`, `transponder_flag = Standing.FLAG_CIVILIAN`,
   `iff_tags = ["PIRATE_GUILD_<n>"]` (unique per member — pirates are not
   crypto-friends of each other in v1), `pos` = wormhole pos (+ small
   seeded scatter), `behavior = {"pirate": true, "job": <hunt job>}`.
   Member goes ACTIVE keyed on the record id.

**Hunt-job assembly** (the M50 canonical shape, parameterized from records):
staging point = a seeded point off the beacon road (offset perpendicular
from the wormhole→lane direction, well outside comms range of stations);
`lane_pos` = a seeded point along a randomly-chosen cargo lane's route
segment; exfil = another off-road dark point; exit = the wormhole pos;
RELIGHT uses `relight_name` + FLAG_CIVILIAN. Same abort topology as M50's
test job (third_party → exfil from INTERCEPT onward; victim_lost → hunt).
Assembled as pure data in the guild — `_attach_ai` just delivers it.

## ClusterManager `_attach_ai` branch

Before the route/cargo checks: `if behavior.get("pirate", false):
node.add_child(AITreeFactory.build_pirate());
node.assign_job(behavior.get("job", {}).duplicate(true)); return`. The
duplicate matters — a demote/promote cycle must hand the fresh node a
clean copy, not the half-run job the previous body mutated. (Job progress
does NOT survive demotion in v1 — a re-promoted pirate starts its hunt
over; acceptable, the record keeps its position, and a full fix is
director/M53 territory.)

## Debug surface

One `DebugSettings.OPTIONS` entry (e.g. `pirate_guild_log`: off/on). When
on, the guild prints one line per policy pass: counts by state, cap,
streaks, pending etas. That's the whole player-facing footprint of M51.

## Tests — `test_pirate_guild` (manual `cluster.tick()` drive, fast config)

- (a) **Bootstrap floor**: fresh guild, empty roster → one arrival
  scheduled → after its eta, exactly one ACTIVE pirate record exists at
  the wormhole, carrying build_pirate + an assigned hunt job (promote it
  and check the tree/job).
- (b) **Replacement on kill**: hulk the active pirate (call `take_damage`
  to destruction or `hulk()` directly) → OVERDUE → LOST after the delay →
  its record is GONE from cluster.records (no-resurrection assertion:
  tick past demote/promote boundaries, count pirate hulls, must stay 0
  until the replacement) → a replacement arrival lands within the window
  under a DIFFERENT cover name; `losses == 1`.
- (c) **Cash-out**: walk an ACTIVE member's node to the wormhole
  (teleport per CLAUDE.md's body_set_state + wake rules, or drive
  last_seen_pos via a scripted exit), set `loot_takes = 1`, free the node
  → CASHED_OUT after the delay, `takes_total == 1`, take_streak bumped,
  NOT counted as a loss.
- (d) **Streaks move the cap both ways, bounded**: scripted sequences of
  cash-outs then losses; cap climbs to max_cap and never past, falls to
  base_cap and never below; floor keeps the roster at cap throughout.
- (e) **Determinism**: two fresh guilds with the same config, same seed
  (`seed(N)` before each), same scripted event sequence → identical
  arrival etas and cover names.
- Full build.ps1 gate green; perf_combat band unaffected (the guild is one
  O(members) pass every 10s).

## Out of scope (lands later)

Patrol/SOS interdiction (M52). Trade/traffic directors + CargoRun
migration (M53). Story-phase config-table swaps + player consequences of
"held" (M54). Physical cargo/economy (M55). Fixing the death gap for
non-pirate traffic (filed as a separate task). Pirates operating in force
/ crypto-linked pirate wings (arrival-mix option, later).
