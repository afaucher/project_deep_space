# M48 — Standings & flags (IFF v2): detailed design

> **Post-ship revision (standing is FOUR tiers, not five).** This doc
> describes M48 AS BUILT, which shipped a `SUSPICIOUS` tier. The model was
> revised afterward: "suspicious" has no shared meaning across roles (a
> patrol's "acting like a predator" vs a pirate's "prey that might be a
> trap"), so it does NOT belong on the shared contact record — it is each
> AI's own role-specific assessment (behavior-tree blackboard). Standing is
> now FRIENDLY / NEUTRAL / UNREPORTED / HOSTILE only. The shipped code below
> keeps a vestigial SUSPICIOUS tier pending the small simplification tracked
> as "M48 code delta" in the roadmap. Where this doc says a rule produces
> SUSPICIOUS (the wanted-name rule; the stray-fire dampening), read the
> roadmap's delta for the revised behavior. See
> [economy_and_piracy.md](../design_ideas/economy_and_piracy.md) for the
> four-tier model + the per-AI assessment layer.

Parent: [m48_m55_economy_piracy_roadmap.md](m48_m55_economy_piracy_roadmap.md);
vision + the full standing table live in
[economy_and_piracy.md](../design_ideas/economy_and_piracy.md). This doc pins
the implementation to files and rules. The deliverable: hostility becomes an
earned, per-observer judgment (standing) instead of "any non-IFF vessel is a
weapons target", with the pirate flag as the day-one known-enemy flag and the
migration lever for every existing combat scenario.

## New module: `scripts/combat/standing.gd`

Static rules module (preload-const convention, never bare class_name), plus
the small shared registries. No Node state; everything observer-side lives on
the observer ship's contact records.

```gdscript
const FRIENDLY := "FRIENDLY"; const NEUTRAL := "NEUTRAL"
const UNREPORTED := "UNREPORTED"; const SUSPICIOUS := "SUSPICIOUS"
const HOSTILE := "HOSTILE"

const FLAG_PIRATE := "JOLLY_ROGER"
const FLAG_DRIFT := "SOVEREIGN_DRIFT"     # home faction / militia
const FLAG_CIVILIAN := "DRIFT_CIVILIAN"   # mobile homes, independents
const SUSPICION_DECAY := 180.0            # s clean -> NEUTRAL
const STRAY_HITS_TO_HOSTILE := 3          # third-party/stray dampening
```

- `compute_standing(contact, transponder, observer) -> Dictionary`
  (`{"standing": String, "reason": String}`) — the pure resting-state rules,
  in precedence order:
  1. crypto: `_iff_tags_overlap(contact.signature.iff_tags, observer.iff_tags)`
     → FRIENDLY.
  2. sticky: existing HOSTILE on the track stays (never recomputed away).
  3. flag ∈ observer.known_enemy_flags → HOSTILE ("flying <flag>").
  4. existing SUSPICIOUS stays until its decay timer clears it.
  5. transponder present with name + flag → claimed name ∈ wanted names for
     any of observer.iff_tags → SUSPICIOUS ("claims a wanted name"), else
     NEUTRAL.
  6. no name+flag received for this track → UNREPORTED ("not reporting").
  Vessels only — ordnance/wreckage/asteroid contacts get standing "" (PD and
  classification flows are untouched).
- **Wanted names registry**: `static var wanted_names: Dictionary`
  (faction tag → Dictionary-as-set of names). `add_wanted(tags, name)` /
  `is_wanted(tags, name)`. Populated when a HOSTILE marking with a claimed
  name is shared/applied. Static process state — a `reset()` for tests.
- **Aggression event bus**: `static var aggression_events: Array` of
  `{seq, attacker_iid, victim_iid, pos}` with a monotonically increasing
  `seq`; take_damage appends (authority side); events pruned after ~2s.
  Observers consume events with `seq > their last_aggression_seq` during
  fusion. `reset()` for tests.

## Ship-side state (`scripts/ships/ship.gd`)

- New per-ship fields: `known_enemy_flags: Array = [FLAG_PIRATE]` (everyone
  hates the black flag by default), `authority_flags: Array` (field ships in
  M48, consumed by M49's DEMAND_SURRENDER rules), transponder flag: a
  `transponder_flag` field on comms components (normalized in `_ready` like
  the other transponder fields; setter `set_transponder_flag(flag)`), and
  `get_active_transponder_data()` includes `"flag"`.
- **Contact records** gain `"standing"`, `"standing_reason"`,
  `"suspicion_timer"`, `"aggro_hits"`. Standing is (re)computed in the two
  places classification is set today (correlate-update ~line 2141 and
  new-contact ~line 2151), passing the correlated transponder record
  (`active_transponders.get(contact.instance_id)` — note transponders are
  received in the SAME tick's datalink pass; one tick of lag on first sight
  is fine and realistic).
- **Attribution**: `take_damage(amount, pos, dir, type, attacker_id: int = -1)`
  — trailing optional param, all existing callers stay valid. When hit with
  a valid attacker_id (server side):
  - mark own track: if `active_contacts` has the attacker's TRK id
    (`"TRK-%03d" % (abs(attacker_id) % 1000)`, same derivation the sweep
    uses) → HOSTILE ("fired on us"), regardless of hit count — the victim
    flips on the first hit. Add the claimed name (if any) to wanted_names
    for own iff_tags.
  - append to the aggression bus for witnesses.
  No track on the attacker → no marking (you don't know who shot you; the
  dark sniper stays anonymous).
- **Witness consumption** (fusion tick, after correlate): for each new bus
  event: skip if attacker is self or victim is self (own hit already
  handled); need a live fresh track on the attacker (last_seen within
  FIRE_STALENESS_MAX) to "see" it; **assistance exemption**: if the VICTIM's
  track (if held) is already HOSTILE to me → ignore entirely; my own faction
  hit (victim shares my iff_tags) → HOSTILE immediately; otherwise
  **stray-fire dampening**: increment the attacker track's `aggro_hits` —
  SUSPICIOUS ("fired near <victim>") until `STRAY_HITS_TO_HOSTILE`, then
  HOSTILE ("sustained attack on <victim>").
- **Datalink share**: in the relay merge, when the peer's copy of a track
  carries a more-severe standing than mine (severity order NEUTRAL <
  UNREPORTED < SUSPICIOUS < HOSTILE), adopt it with reason
  `"datalink <peer name>: <reason>"`. HOSTILE adoption also feeds
  wanted_names. Standing rides the same per-contact dict, so this is a
  compare-and-copy inside the existing merge loop.
- **Decay**: in the contact decay loop, tick `suspicion_timer` on SUSPICIOUS
  tracks; past SUSPICION_DECAY with a reporting transponder → recompute from
  rest (NEUTRAL). HOSTILE never decays; track death forgets everything
  (already free).
- `mark_contact_hostile(c_id, reason := "flagged by operator")` — public
  API; the player button calls it; also the legitimate lever for tests that
  need immediate engagement without transponder plumbing (it IS the
  player-judgment mechanic, not a backdoor).
- Missiles: `missile_behavior.gd` copies the launcher's
  `known_enemy_flags` and passes `launcher_instance_id` for warhead
  attribution (`missile_controller.detonate` attributes to the launcher,
  not the missile).

## Consumers (the actual behavior change)

- `acquire_target_leaf`: `classification == "UNIDENTIFIED VESSEL"` →
  `contact.get("standing","") == HOSTILE`. Same staleness/range gates.
- `flee_leaf`: flee from nearest HOSTILE (was: nearest unidentified).
- `ai_drone_controller` (legacy, kept green by test_ai_vs_legacy): same swap.
- `missile_controller` acquisition: `classification in [UNIDENTIFIED
  VESSEL, INCOMING ORDNANCE]` → `standing == HOSTILE or classification ==
  "INCOMING ORDNANCE"` (ordnance interception unchanged; vessel retargeting
  now needs the launcher's judgment, which reaches the missile via its
  inherited known_enemy_flags and datalink standing share).
- Weapons manual fire, PD (keys on INCOMING ORDNANCE classification), and
  classify_contact itself: untouched.

## Flags in the world

- Sandbox (`main.gd` `_spawn_ship` / drone+buoy spawns): AI combat teams fly
  FLAG_PIRATE with `known_enemy_flags = [FLAG_PIRATE, FLAG_DRIFT]`; the
  player ship flies FLAG_DRIFT (transponder defaults on already). Crypto
  same-team overlap keeps teammates FRIENDLY regardless of flag; cross-team
  pirate flags make everyone mutually hostile — sandbox stays a warzone.
- Campaign (`home_cluster.gd`): stations/patrols/cargo fly FLAG_DRIFT
  (patrols also get `authority_flags = [FLAG_DRIFT]` consumers in M49);
  mobile homes fly FLAG_CIVILIAN.
- Flag visibility requires powered comms + transponder on (existing
  plumbing). A hull with no comms can't declare — that's the fiction
  working, not a bug; tests for such hulls use `mark_contact_hostile`.

## Test migration (the audit)

Combat scenarios that relied on auto-hostility get the pirate flag on the
aggressor side(s) (mutual engagement: both sides), or `mark_contact_hostile`
where transponders aren't in play (fabricated contacts, comms-less hulls).
Fabricated `active_contacts` entries in tests add `"standing": "HOSTILE"`.
Known blast radius (audit each): test_ai_duel, test_ai_vs_legacy,
test_ai_engage_tree, test_ai_disengage, test_ai_beehave_spike,
test_e2e_drone_vs_bouy, test_missile_ai, test_point_defense,
test_defence_pod, test_fire_staleness_gate, test_mine, test_patrol,
test_component_states (fake targets), test_volley_metering,
test_weapon_groups, test_asteroid_station, test_station_keeping,
plus tactical_analysis sim runners (perf_combat, run_missile_vs_pd,
run_time_to_kill, run_missile_jink_compare, run_pd_sensor_sweep) — a perf
sim where combat silently never starts would report a fantasy tick time.

## New tests

- `test_standing_rules` — pure-rules unit pass over compute_standing +
  wanted names + severity ordering (no physics).
- `test_standing_e2e` — live ships: (a) a dark stranger is tracked but NOT
  engaged; (b) pirate-flagged ship IS engaged; (c) attacker firing on a
  victim flips the victim's standing on first hit and a witnessing third
  ship goes SUSPICIOUS→HOSTILE per dampening; (d) assistance exemption: the
  witness does NOT flip on a ship engaging an already-HOSTILE target;
  (e) datalink share propagates HOSTILE to a linked friendly;
  (f) mark_contact_hostile works. Robust assertions (margins, no exact
  frames), seeded RNG assumed.

## UI (contacts panel)

- Row color keys on standing for vessel contacts (hostile red, suspicious
  orange, unreported dim yellow, neutral white, friendly green — falls back
  to classification colors for non-vessels).
- Selected-contact detail shows `standing (reason)`.
- A "MARK HOSTILE" button on the selected vessel contact →
  `mark_contact_hostile` on the player ship (server-authority path same as
  existing pin/select plumbing).

## Perf guardrails

Standing recompute happens only where classification is already computed
(correlate hits + new contacts + datalink merge), not per-contact-per-tick;
the aggression bus is event-driven and usually empty; wanted-names lookups
are dict hits. No new O(ships²) scans. `perf_combat` after migration is the
regression check (wall-clock avg must stay in the ~5–6ms band).

## Out of scope (lands later)

Challenge/comply and DEMAND_SURRENDER verbs (M49 — authority_flags is
fielded now but unread), loiter/intercept-geometry suspicion heuristics
(M49/M52 with patrol behavior), surrender state, controlled-space
enforcement, standing persistence across saves.
