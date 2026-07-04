# M27 — Catalog expansion (the five unbuilt ships)

Status: PLANNED. Depends on: M21 (parts), M22 (builders), M23 (mechanized
checks). M24 optional; M25/M26 make the payoff visible but are not
dependencies. Design: `design_ideas/hull_shape_grammar.md` §2/§8 phase E;
concepts: `design_ideas/ship_designs.md`.

## Goal

Author the five specced-but-unbuilt ships — freighter, pinnace, mine, system
defence pod, asteroid station — each IN the grammar (builders + parts). This
is the proof the grammar works: five genuinely different silhouettes at ~30
lines each, machine-validated.

## Pre-step (before any authoring)

Extend `design_ideas/ship_parameter_table.md` with target rows (mass, accel,
max_speed, signature posture) for all five. Targets first, authoring to
targets, validation against targets — same discipline as M9c.

## The five ships — shape, tier, and the decisions already made

| Ship | Archetype (grammar) | Tier | Key decisions |
|------|--------------------|------|---------------|
| Freighter | spine + cargo pods | HEAVY | unarmed; `dockable = true`; mass ~300, accel ~8–12, speed ~400; huge inertia from outboard pods is the *intended* handling |
| Pinnace | tapered dart | LIGHT | unarmed, unarmored, fast (speed ~2000, accel ~80); carries `living_quarters` (30 pax) |
| Mine | 5-rect plus | DRONE | needs a tiny station-keeping engine (DRONE tier requires engines; "slow" per concept — DRONE handling band 0–200 fits); single laser + passive_em + a small always-on active short sensor to satisfy PD-coherence ("run dark" mode is future work, noted not built) |
| Defence pod | ring (hollow square) | STRUCTURE | STRUCTURE requires living_quarters + cargo_bay + rcs, no engines → give it a small crew pod + stores bay (grounded: crew of 2–4); heavy PD + missiles all-around; the ring hole is flavor |
| Asteroid station | cluster (irregular dense blob) | STRUCTURE | rock shell = hull comps at density ≥ 300 (past the >250 asteroid classifier line); beacon/transponder OFF by default; modules embedded in rock |

Band housekeeping (small `component_spec.gd` additions, flagged not snuck in):
`living_quarters`/`cargo_bay` currently have STRUCTURE-only band entries — add
LIGHT (pinnace) and HEAVY (freighter) rows so those components are banded, not
band-skipped.

## Execution (Sonnet — suggest one agent per ship, sequential)

Hand each agent: this doc, the parameter-table targets, grammar doc, the
builders/parts APIs, `ship_design_validator.gd`, one comparable existing ship,
guardrails. Forbid: raw-rect authoring where a builder exists (the point is to
exercise the grammar — friction encountered is *signal*, report it, don't
bypass it); touching existing ships; band edits beyond the two rows above.
Register each in `ShipCatalog.SPAWNABLE`.

## Test plan (Fable)

Structural gates (extend `test_ship_designs.gd` — automatic via catalog
enumeration, plus per-ship target asserts):
1. Every new ship: validator `ok == true`; layout-warning set enumerated in
   `EXPECTED_LAYOUT_WARNINGS` (M23 ratchet) and reviewed — a clean grammar
   authoring should need FEW entries; a long list means the builders or the
   design are wrong.
2. Parameter-table conformance: derived mass within ±10% of target; derived
   accel within band; max_speed/max_omega inside the tier's handling band.
3. Grammar usage proof: each ship's file contains no raw hull-wall boilerplate
   where `frame`/`arm`/`mirror_*` apply (validation-phase diff review, not a
   runtime test).

Role smoke tests (new, one per ship where behavior is the point):
4. **`test_freighter_docking`** — freighter approaches a medium station berth,
   gets captured, settles, releases (reuse `test_docking` harness). Watch:
   berth clearance — freighter bounding radius is large; if the capture pose
   collides, the fix is a per-ship berth offset (station berth pos +
   `get_bounding_radius()`-aware standoff), not a tolerance bump. Assert no
   collision impulse during capture (linear_velocity spike check).
5. **`test_mine`** — hostile LAC drifts through the mine's laser range → mine
   fires, LAC takes damage; friendly-IFF ship passes unharmed; the mine never
   pursues (position stationary within station-keeping tolerance).
6. **`test_defence_pod`** — 6-missile salvo inbound: pod's PD intercepts a
   majority (loose gate: ≥3 killed before impact — this is a smoke test, not
   a balance sweep); pod never moves.
7. **`test_asteroid_station` (the marquee).** Cold-and-dark (active sensors
   powered off, reactor low/off posture): an observing frigate's
   `classify_contact` reads it as **ASTEROID**. Power the sensors on: within
   the classification/decay window it re-reads as a powered contact. This one
   test exercises the entire signature model end-to-end — density, EM posture,
   classification — and IS the archetype's acceptance criterion.
8. **Pinnace** — no dedicated test beyond structural gates + a spawn smoke
   (60 frames, no errors): it's an unarmed fast hull; its interesting behavior
   (passenger runs) is campaign wiring, out of scope here.

Balance promotion (per the M24 rule — only new ROLES sweep):
- Mine and defence pod are new roles → ONE bounded tactical scenario each
  (existing sim-runner infra), loose gates, results to
  `tactical_analysis/data/`. Freighter/pinnace are civilians — no sweeps.
- Sims run SEQUENTIALLY (headless Godot single-instance rule), and only in the
  validation phase, not by the authoring agents.

## Validation phase checklist

- Run: `test_ship_designs` (now covering all five), the four role smokes,
  `test_parts_catalog`, `test_hull_builders`, `test_layout_checks`,
  `test_ship_variants`, `test_ship_geometry` (+`test_sensor_dots` if M26
  landed) — new geometry flows into the AABB/radius oracles automatically.
- Campaign suite if any shared file was touched.
- Grammar friction report reviewed: anything the builders couldn't express
  goes into `hull_shape_grammar.md` open decisions — that's the feedback loop
  the grammar needs to mature.
- Stretch (record if done, separate commit): wire the freighter onto the
  Ironhold↔Drift Market lane, seed a small minefield near Slag Bay —
  `test_campaign_bootstrap` + `test_cargo_run` green.
- Mark DONE + commit (`feat: M27 catalog expansion -- freighter, pinnace, mine, defence pod, asteroid station`).
