# M53b/M53c — The traffic guild, the shared director skeleton, and the registry

Follows M53a (world + peer state + pirate circulation, all landed). This is the
systemic half: commerce stops being a pair of hand-authored loops and becomes a
director-driven population that responds to demand — and the docking registry
that feeds it is deliberately built in the shape the Mail Network
([../design_ideas/mail_network.md](../design_ideas/mail_network.md)) will later
latency-gate.

Absorbs the deferred **M53a Slice C** (transient wormhole freighters): it was
always meant to be the "second consumer that proves the arrival skeleton", so
it belongs here, as one arrival type of a real traffic director rather than a
bespoke one-off.

## The sequencing insight (why extraction is NOT first)

The roadmap's instinct was right: you cannot safely extract a shared skeleton
from ONE consumer. `pirate_guild.gd` is currently the only director, so
factoring it now would invent hooks from a single example and bake pirate
assumptions into a "generic" base. Instead:

**build the second director concretely → let the real commonality show → then
extract.** Some deliberate duplication in Pass 2 is the price of a correct
abstraction in Pass 3, and both directors' test suites protect that refactor.

**Outcome (2026-07-24): the sequencing worked, and its answer was "don't."**
With Pass 2 landed the commonality could be measured rather than guessed, and
it came to ~25 identical lines — so Pass 3 is deferred to a third consumer
(see below). Worth noting the process succeeded even though the refactor
didn't happen: building concretely first is what turned an architectural
guess into a cheap measurement.

## Pass 1 — The docking registry (Mail phase 1)

Cheap, no behavior change, and it unblocks everything downstream reading the
right shape.

- Each station keeps an **append-only log of its own dock/undock events** with a
  **monotonic per-source sequence counter** — the mail model's source log
  (`"<station> Docking Registry @ vN"`), just not latency-gated yet. Entries
  carry at least `{subject_name, flag, event: DOCKED|DEPARTED, seq, stamp}`.
- Directors read it **globally** for now. Phase 3 of the mail vertical later
  gates *visibility*, not structure — which is the entire reason to build this
  shape before the demand read exists.
- **The hook must be the convergence point.** `port_control.request_docking()`
  is only the player/dialogue path — NPC AI calls `ship.gd`'s
  `issue_docking_grant()` directly (see port_control.gd's own comment), and a
  GRANT can go unfulfilled anyway. The honest "a dock happened" event is the
  **DockingBay state transition** (→ DOCKED for arrival, DOCKED → EMPTY for
  departure), which every path funnels through regardless of how permission was
  obtained. Hooking grant issuance instead would silently miss most traffic and
  make demand read near-zero — the single most likely way to get this pass wrong.
- Use the M56 frame-stamp idiom for the per-entry timestamp (age display), and
  keep the sequence counter as the ordering clock — two clocks, per the mail doc.
- Tests: an NPC dock and a player dock BOTH land in the right station's log;
  sequence numbers are monotonic per station; a departure records; the log is
  plain serializable data.

## Pass 2 — Traffic director (concrete) + transient freighters

A real second director in `scripts/directors/`, its own ledger, registered in
`ClusterManager.directors` (a plain array ticked in `tick(dt)` — the hook
already exists from M51). Deliberately allows duplication with pirate_guild.

- **Population floor + wormhole replenishment FIRST.** This is the depletion
  fix and should land before any demand scoring: authored traffic plus working
  piracy currently thins the world permanently when a hauler is killed.
  **Decided: maintain a TARGET POPULATION PER FLAG**, not merely replace losses
  — same mechanism, and it gives the story-phase arrival mix somewhere to plug
  in later.
- **Per-flag traffic (decided, M53a):** ONE traffic guild owns all non-pirate
  commerce (home + Meridian). The jurisdiction seam comes from the `flag`
  stamped on each spawned record, not from a director per sovereign.
- **Authored lanes stay (decided).** Cargo records 700–703 remain the peacetime
  baseline the director perturbs and replenishes — not deleted and regenerated.
  Demand is a refinement, not a teardown.
- **Transient freighters** (the absorbed Slice C) land here as one arrival type:
  spawned at the wormhole, run the beacon road end-to-end with a dock stop at
  each terminus, then EXIT_AT the wormhole. Reuses the M50 job runner
  (`test_visitor_itinerary` already proves it runs non-pirate itineraries).
  Through-traffic: they make the road busy and witnessed; they rebalance nothing.
- Tests: killed hauler replenished within the window; freighter lifecycle
  (arrives → two stops → departs → record retired); population cap respected;
  per-flag targets honored.

## Pass 3 — Extract the shared director skeleton [DEFERRED — measured, not deferred on vibes]

**Deferred 2026-07-24, after Pass 2 landed and the duplication could be
measured instead of predicted.** Two consumers is the MINIMUM needed to see
commonality, not enough to be confident of its shape. The measurement:

- **Byte-identical duplication is ~25 lines total** — `_find_record`,
  `_erase_record`, `_wormhole_pos`, and the `tick(dt)` → `_policy_pass`
  accumulator. That is the entire real cost of NOT extracting.
- **The rest diverged.** The check-in → OVERDUE state machines are only
  superficially similar: the pirate resolves takes / cash-in / profitless
  backoff, the traffic director resolves losses / per-flag replenishment.
  Arrival scheduling differs (lane-point + posture vs. flag template + road
  termini). Debug logging is a per-director `DebugSettings` key by design.
  Ledger shapes rhyme; they are not the same shape.

So the base class this pass envisioned would carry ~25 genuine lines plus a
set of hooks invented to paper over differences that are load-bearing — which
is precisely the failure mode the original Watch item named ("a hook with one
implementation is not a hook").

**Revisit trigger, not a calendar date:** extract when a THIRD director exists
(a peer-state navy, a salvage/insurer director, or the Mail-phase-3 relocation
turning directors into located subscribers — the last of which will rewrite the
check-in machinery anyway, so extracting before it would be wasted work). Until
then the 25 lines stay duplicated on purpose.

Original scope kept below for that conversation.

Extract (genuinely shared):
- ledger shape (members / arrivals / counters) and its serializable discipline
- policy-tick accumulation (`tick(dt, cluster)` → periodic `_policy_pass`)
- check-in → OVERDUE state machine (the director honesty rule: read only your
  OWN members' live nodes)
- arrival scheduling + eta rolls, record minting at a spawn point, record
  retirement (M51's death-gap fix)
- record-id allocation, `_find_record`/`_erase_record`, debug event/log toggle

Stays pirate-only (do NOT generalize):
- identity kits, `issued_names` never-reuse, laundering/RELIGHT
- lane/hazard/staging/exfil geometry, posture rolling
- the cash-in-near-wormhole heuristic and take/loot semantics

**Watch item:** over-abstraction is the main risk. Extract only what both
directors demonstrably share; a hook with one implementation is not a hook.

## Pass 4 — Demand-driven routing (M53c proper)

- **Per-station demand scores read from the Pass-1 registry** (start simple:
  dock count, decay-averaged). This is the read that must be registry-shaped so
  the mail vertical later gates visibility rather than restructuring.
- Policy tick assigns runs **per-trip instead of fixed loops**: hub↔hub down the
  road, periodic off-road runs to whichever outpost demand favors (the ambush
  habitat the piracy loop wants).
- **Story-phase hook as data**: the arrival table the director draws from is
  keyed by StoryState flags (peacetime mix now; militia formations and the
  weapons dealer are later *content*, not new systems).
- Tests: demand shift redirects runs; story-phase flag swaps the arrival table.

## Watch items

- **Perf.** More live traffic = more bubble population. Directors own HARD caps;
  `perf_combat`'s census is the watchdog (economy_and_piracy.md's known hazard).
  Re-run the perf baseline after Pass 2 raises population.
- **Duplicated world constants** bit this project twice in one session
  (`FoamPhysics.BOUNDARY`, then `navigation_panel.gd`'s `WORLD_HALF_EXTENT` /
  `FOAM_BOUNDARY` — the latter silently made four stations unreachable on the
  map through a fully green gate). Any new director-side geometry constant must
  REFERENCE its source, never copy it.
- **Determinism.** Directors draw only from the seeded global RNG (CLAUDE.md);
  arrival/eta rolls happen inside the policy pass so tests reproduce them.

## Explicitly not this milestone

- Latency-gating the registry / relocating directors to be located subscribers
  (Mail phases 2–3) — Pass 1 deliberately builds the shape, not the fog.
- Contracts/missions from director state (Mail phase 4, M54).
- Physical cargo manifests (M55) — the take and the delivery stay abstract.
