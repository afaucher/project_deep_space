# Datalink relay: cost anatomy and the deferred optimization

Where the per-frame cost of the datalink relay actually comes from, what has
already been fixed, and the constraints any future optimization must respect.
Written after the M45 physics-tick investigation (see
`implementation_plans/m45_physics_perf_investigation.md` for the measurement
methodology and full attribution tables). The relay block itself lives in
`ship.gd`'s `_physics_process`, tagged `datalink_relay` by PerfProbe.

## What the relay does (and why it reruns every tick)

Friendly ships in mutual comms range and line-of-sight share `active_contacts`
via freshest-wins merge. There is **no persistent link graph**: every ship
rescans every tick. That's deliberate — multi-hop propagation falls out for
free (a contact relayed in this frame relays onward next frame, one tick of
latency per hop) instead of needing an explicitly modeled delay. Several
comms/relay tests depend on that timing (`test_comms_relay`,
`test_nav_comms_range_packet`). Any throttling scheme has to preserve or
deliberately re-spec it.

A link is capped by the WEAKER of the two ships' comms ranges (typical catalog
comms array: 30,000u), needs IFF overlap, and needs an unblocked raycast.
Transponder receive (no IFF, no LoS) piggybacks on the same distance-gated
loop.

## Cost anatomy, per ship per frame (~23-ship campaign start scene)

For EACH other ships-group member, in gate order:

1. distance check against OUR comms range — one `distance_to`, cheap.
   (Added post-M45: link_range = min(self, theirs) can never exceed self's
   range, so this prunes conservatively BEFORE step 2. Landed as `16a52be`;
   datalink_relay 4233 → 2631 us/frame, −38%, because a big share of the live
   group — traffic spread along the 200k trade lane — sits beyond own range
   and used to pay step 2 every frame just to be rejected by distance.)
2. `s.get_comms_range()` — scans the PEER's whole component list (worst on
   stations), calling `is_component_powered` per comms component.
3. min-range distance gate, IFF overlap check.
4. LOS raycast (`PhysicsRayQueryParameters2D`) — one per DIRECTED pair, so
   A→B and B→A each fire their own identical ray every frame.
5. `s.active_contacts.duplicate()` — a fresh shallow copy of the peer's whole
   contact table, per pair, per frame — plus the synthesized self-report entry
   and a merge loop over every contact in the copy.

Steps 4-5 only run for in-range friendly pairs — but the campaign start scene
is one dense comms bubble (everything live is near Ironhold), so almost every
surviving pair pays them. Dense populated neighborhoods (Ironhold now, the
Slag Bay trailer field in M43) are exactly where this bites; spread-out
traffic is cheap thanks to the distance gates.

## Measured state (post-M45, post-early-out)

- `datalink_relay`: ~2.6ms/frame avg — still the single largest tagged block
  (~16% of the 16.67ms tick; whole physics step now ~8.2ms avg / 9.6ms p95).
- Re-measure with `--run-test test_perf_baseline` (30s window, ranked table,
  archives `tactical_analysis/data/perf_baseline*.csv`).

## Candidate fixes for the remaining ~2.6ms (deferred, in rough order of value)

- **LOS once per unordered pair.** The A→B and B→A raycasts are identical
  (excluding endpoints differ, but the segment is the same). Computing each
  pair's LOS once per frame halves step 4. Needs a shared per-frame cache
  (e.g. keyed on the two instance ids, frame-scoped like the M45 reactor
  cache) since each ship's relay runs inside its own `_physics_process`.
- **LOS verdict cache over a few ticks.** Ship-to-ship geometry doesn't change
  enough frame-to-frame to need a fresh raycast at 60Hz. Cache the verdict for
  N ticks (staggered per pair, hash-based like the M45 sweep stagger — never
  `randf`). Worst case: a link forms/breaks up to N ticks late. Choose N so
  tests asserting relay timing still hold, or re-spec them consciously.
- **Merge without the full-table duplicate.** The `duplicate()` exists so the
  synthesized self-report can be added to the iteration set; iterating the
  peer's table directly plus handling the self-report separately avoids
  copying every contact dict entry per pair per frame.
- **Relay throttle** (every Nth tick, staggered) — biggest lever, but directly
  changes the one-tick-per-hop propagation contract; only with a deliberate
  re-spec of multi-hop latency and the tests that pin it.
- **Peer comms-range cache.** `get_comms_range()` could be frame-scoped-cached
  on the peer (same pattern as `_get_reactor_power_rating_cached`) so N
  linkers asking the same station each frame pay one scan total, not N.

## Guard rails for whoever lands this

- Run before/after with `test_perf_baseline` (same harness, numbers in the
  M45 findings + this doc) — no optimization lands without a before/after.
- `test_comms_relay` and `test_nav_comms_range_packet` pin relay semantics.
- Perf guard budgets must be calibrated INSIDE `build.ps1`'s parallel gate,
  not standalone — contention inflated p95 ~48% during M45.
