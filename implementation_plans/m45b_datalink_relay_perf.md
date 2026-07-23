# M45b — Datalink relay perf: dedupe the symmetric LOS raycast

## Symptom / motivation

M45's attribution table (`implementation_plans/m45_physics_perf_investigation.md`)
convicted `datalink_relay` as the single largest tick cost — 36% pre-fix,
still ~24.5% (~4.08-4.13ms avg) after M45's other two fixes landed, stable
across every run regardless of what else was toggled. M45 explicitly
deferred fixing it ("bigger than the three pre-approved surgical patterns...
recommended next milestone"). Picking it up now, before M53a's world
expansion (2x cluster radius, more traffic) grows ship counts further — this
block is O(ships²), so it only gets worse as the roster grows.

Considered and ruled out first: parallelizing per-ship work (sensor sweep or
this block) across `WorkerThreadPool` threads. Godot's own docs state
"interacting with the active scene tree is NOT thread-safe," and this loop's
raycasts + `s.get_signature()`/`s.active_contacts` reads are exactly that;
forum reports confirm concurrent `intersect_ray` calls from worker threads
throw `"Condition 'space->locked' is true"` against the main physics step.
A safe version would need a snapshot/compute/apply restructure — much bigger
than this fix, for a smaller or comparable win. Not pursued this pass.

## Root cause (read from `ship.gd`'s `datalink_relay` block, ~line 3042-3213)

For every ship A, every physics frame: loop every other ship S in the
"ships" group (early-out on comms range/IFF first), then
`space_state.intersect_ray(A.position -> S.position)` to gate the relay on
line-of-sight.

LOS between A and S is a symmetric physical fact — same segment either
direction, and `exclude=[self]` on each end only removes that ship's own
collider from being counted as an obstacle, which doesn't change whether
something ELSE blocks the line between them. Ship S, processing its own turn
later in the SAME frame, redundantly recomputes the identical raycast in the
opposite direction. At ~23 mutually-linked ships in the campaign start,
that's 500+ raycasts/frame — roughly double what's structurally needed.

## Fix — frame-scoped shared LOS cache (same idiom already used twice in this file)

`ship.gd` already has this exact pattern for cross-ship, frame-scoped
caching:
- `_get_port_authorities()`'s `_port_authority_cache` / `_port_authority_cache_frame`
  (`static var`s, invalidated by `Engine.get_physics_frames()`, rebuilt
  lazily by whichever ship asks first that frame).
- M45's Fix A, `_get_reactor_power_rating_cached()` (same frame-keyed idea,
  per-ship rather than cross-ship).

Apply the cross-ship version to LOS:

- `static var _los_cache: Dictionary = {}` — key `"%d:%d" % [min(a_iid,
  b_iid), max(a_iid, b_iid)]` -> `bool` (LOS clear or not).
- `static var _los_cache_frame: int = -1`.
- New helper, e.g. `_has_los(other: Node) -> bool`: if
  `Engine.get_physics_frames() != _los_cache_frame`, clear `_los_cache` and
  update `_los_cache_frame` first. Compute the pair key from
  `get_instance_id()`/`other.get_instance_id()`. Return the cached bool if
  present; otherwise run the existing raycast exactly as today, store the
  result, return it.
- Replace the inline `space_state.intersect_ray(...)` block in
  `datalink_relay` with a call to `_has_los(s)`. No change to iteration
  order, early-out gates, or what's computed — only that the raycast itself
  runs once per unordered pair per frame instead of twice.

## Explicit non-goals (deferred, not this pass)

- **Multi-tick LOS reuse** (caching across MORE than one frame). M45's own
  "deferred" list floated this, but it would change the relay's documented
  one-tick-of-latency-per-hop propagation semantics that
  `test_sos_relay_bridge.gd` (verified this session: 2-physics-frame hop
  timing across a 3-hop chain) and other relay tests assert on directly.
  This fix is same-tick dedup ONLY — propagation timing must come out
  bit-for-bit unchanged, because nothing about WHEN a fact propagates
  changes, only that computing it costs one raycast instead of two.
- **Threading** — see above; ruled out this pass, revisit only if ship
  counts grow enough (post-M53a) that dedup alone doesn't recover enough
  headroom.
- **The rest of `datalink_relay`'s O(ships²) cost** — transponder lookup,
  warrant merge, contact merge dict work are NOT raycast-bound and aren't
  touched by this fix; the loop is inherently O(ships²) in its current shape
  (every ship pulls from every other ship's own state each tick). Reducing
  that further would need a genuinely different architecture (e.g. a shared
  per-tick broadcast buffer instead of N pull-loops) — out of scope for a
  surgical pass; note as a candidate for a FUTURE milestone if `datalink_relay`
  is still the top offender after this fix.

## Measurement plan

Same harness M45 built — do not build a new one. `test_perf_baseline.gd`
(real campaign scene, 1800 physics frames at `--fixed-fps 60`, `PerfProbe`
tag table + `Performance.TIME_PHYSICS_PROCESS` avg/p95/max), before and
after, several repeated standalone runs (M45's own numbers came from 5) to
account for run-to-run noise per CLAUDE.md's non-determinism caveat.

Confirm:
- `datalink_relay` `avg_us_per_frame` drops. Don't pre-assume a number —
  measure whether the raycast is most of the block's cost or whether the
  dict-merge work dominates; report whatever the harness actually shows.
- No OTHER `PerfProbe` tag regresses — this should be an isolated win in one
  block, touching nothing else's cost.
- `TIME_PHYSICS_PROCESS` avg/p95 both drop measurably.
- Full `build.ps1` gate stays green — pay particular attention to every
  relay-timing-sensitive test (`test_comms_relay.gd`, `test_sos_relay_bridge.gd`,
  `test_relay_contact_aging.gd`, and anything else asserting hop latency or
  multi-hop propagation): the dedup must change HOW MANY raycasts a fact
  costs to relay, never WHEN it arrives.

**Note on `tactical_analysis/data/perf_baseline*.csv`**: unlike incidental
test-run churn on these files (which the established workflow reverts before
committing unrelated changes), THIS milestone's whole point is to update
them — the post-fix numbers are part of the deliverable. Regenerate and
commit the fresh CSVs as the "latest recorded run," per M45's own precedent,
rather than reverting them.

## Tests

No new test is strictly required for correctness — this caches an existing
pure computation, it doesn't add new behavior. Consider one small direct
test on `_has_los` (same-frame calls return the identical answer a direct
raycast would; a second call for the same pair doesn't re-raycast — e.g. via
a call-count probe) if it can be written without over-engineering the
harness. Must NOT weaken, relax, or delete any existing relay-latency
assertion to make the numbers look better.

## Files likely touched

- `scripts/ships/ship.gd` — new `_los_cache`/`_los_cache_frame` statics +
  `_has_los()` helper; one call-site replacement inside `datalink_relay`.
- `tactical_analysis/data/perf_baseline.csv`,
  `tactical_analysis/data/perf_baseline_summary.csv` — regenerated,
  committed (see note above).
- Optionally a small new/extended test per the "Tests" section.

## Findings (as-built)

### Implementation

Landed exactly as designed, no deviation. `ship.gd` gained (immediately after
`_get_port_authorities()`, its cross-ship frame-cache sibling):

```gdscript
static var _los_cache: Dictionary = {}
static var _los_cache_frame: int = -1

func _has_los(other: Node) -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _los_cache_frame:
		_los_cache = {}
		_los_cache_frame = frame
	var a_iid := get_instance_id()
	var b_iid := other.get_instance_id()
	var key := "%d:%d" % [min(a_iid, b_iid), max(a_iid, b_iid)]
	if _los_cache.has(key):
		return _los_cache[key]
	var space_state = get_world_2d().direct_space_state
	var ray_query = PhysicsRayQueryParameters2D.create(position, other.position)
	ray_query.exclude = [self]
	var ray_res = space_state.intersect_ray(ray_query)
	var clear: bool = not (ray_res and ray_res.collider != other)
	_los_cache[key] = clear
	return clear
```

The `datalink_relay` call site's inline raycast (previously 5 lines: build
`PhysicsRayQueryParameters2D`, exclude self, `intersect_ray`, compare
`.collider`) collapsed to `if not _has_los(s): continue # Line of sight
blocked`, with the outer-scope `var space_state = ...` line removed (it had
no other reader in the block). No other line in `datalink_relay` changed —
early-out order, IFF/range gates, transponder read, warrant merge, and
contact merge logic are byte-identical to before.

### Before / after (standalone, `test_perf_baseline`, 1800-frame window, 5 runs each)

Measured by toggling only the `_has_los` call site on and off (via a
temporary revert/reapply of just that one edit) while leaving every other
uncommitted change in the working tree untouched, so the comparison isolates
this fix alone rather than conflating it with unrelated in-flight work.

| run | datalink_relay avg us/frame (before) | datalink_relay avg us/frame (after) |
|---|---|---|
| 1 | 1819.82 | 1786.57 |
| 2 | 1809.72 | 1792.41 |
| 3 | 1816.36 | 1802.11 |
| 4 | 1822.59 | 1801.34 |
| 5 | 1819.97 | 1799.43 |
| **mean** | **1817.69** | **1796.37** |

Delta: **-21.3us/frame, -1.2%**. Every other `PerfProbe` tag stayed flat
across the same before/after pair (checked side-by-side on run 1: e.g.
`heat_em_component_loop` 1039.35 -> 1041.93, `sensor_sweep` 180.41 -> 180.93,
`ai_tree_tick` 714.36 -> 709.66 -- all within run-to-run noise, confirming
the change is isolated to the raycast dedup and touches nothing else).

`Performance.TIME_PHYSICS_PROCESS`:

| run | avg ms (before) | avg ms (after) | p95 ms (before) | p95 ms (after) |
|---|---|---|---|---|
| 1 | 7.656 | 7.599 | 10.381 | 8.948 |
| 2 | 7.877 | 7.438 | 10.436 | 7.536 |
| 3 | 7.689 | 7.082 | 8.349 | 8.448 |
| 4 | 7.562 | 6.889 | 8.397 | 9.773 |
| 5 | 7.654 | 7.537 | 9.897 | 7.982 |
| **mean** | **7.688** | **7.309** | **9.492** | **8.537** |

Whole-tick avg dropped ~0.38ms (~4.9%) and p95 ~0.96ms (~10%) on the mean,
but the before/after per-run ranges genuinely overlap (before: 7.562-7.877ms
avg; after: 6.889-7.599ms avg) -- consistent with the datalink_relay tag's
own ~21us/frame delta being real but small next to run-to-run whole-tick
noise on this machine. Reported as directionally-consistent-but-noisy rather
than a clean win, per the plan's own instruction not to guess.

`build.ps1`'s in-gate parallel run (`test_perf_baseline`'s own regenerated,
checked-in numbers -- see below) landed within its usual contention-inflated
range: avg 8.179ms, p95 13.145ms, both comfortably under the 16.0/20.0ms
guard budgets with the same margin M45 left itself.

### Discrepancy worth flagging: the raycast is a MUCH smaller share of `datalink_relay` now than M45 measured

M45's original investigation convicted `datalink_relay` at **avg 6010us/frame
pre-fix** (36% of the tick) and **4080-4130us/frame** after M45's two
unrelated fixes landed (heat/EM cache + sensor stagger, neither of which
touches this block). This milestone's own pre-fix baseline measured
`datalink_relay` at only **~1810-1820us/frame** -- already less than half of
M45's own post-fix number, before this milestone's fix touched anything.

Root cause is NOT this fix regressing measurement; it's that meaningful
unrelated work landed in `ship.gd` and elsewhere between M45 and this
milestone (visible in `git log`: M52b warrant-relay folding, M48 standing
share, and the general churn of ~10 commits of gameplay work), which
apparently reduced this block's baseline cost independent of anything M45b
targeted. Same scene census both times (23 "ships" group members, confirmed
via the harness's own printed census line), so it isn't a smaller test
scene -- something about the current code path through `datalink_relay`
(or the raycast itself, given fewer relevant obstacles/pairs) is cheaper
than it was when M45 measured it.

Practical consequence for this fix: **the LOS raycast was never the
majority of the block's cost in the state this milestone actually shipped
against** -- deduping it saves ~1.2% of the block, not a dramatic fraction.
The plan doc's own "Measurement plan" explicitly anticipated this
possibility ("measure whether the raycast is most of the block's cost or
whether the dict-merge work dominates; report whatever the harness actually
shows") -- the answer, empirically, is that the dict-merge/transponder/
warrant work dominates `datalink_relay`'s current cost, not the raycast.
The fix is still correct and worth keeping (it is a strict, zero-risk
subset of the work the block was already doing, and gets cheaper still as
ship counts grow toward M53a's larger world), but it should not be sold as
a large win on its own in the current codebase -- the plan's own non-goal
#3 (the rest of `datalink_relay`'s O(ships^2) dict-merge cost, untouched
here) is now clearly the dominant remaining cost in this block, more so
than the plan anticipated.

### Regression suite

Full `build.ps1` gate: **105/105 tests passed** (includes syntax validation,
the full parallel test suite, and the Windows export/package step). No
`-Force` needed. Specifically confirmed for the relay-timing-sensitive
tests named in the plan:

- `test_comms_relay.gd` -- PASSED (9.88s), all 7 scenarios (including the
  blocked-LOS scenario, which exercises `_has_los` returning `false`).
- `test_sos_relay_bridge.gd` -- PASSED (9.46s); 3-hop SOS propagation still
  lands with the same monotonic hop-frame ordering assertion.
- `test_relay_contact_aging.gd` -- PASSED (10.82s); echo-lock aging/expiry
  timing unaffected.
- `test_perf_baseline.gd` -- PASSED (24.21s in-gate) with the new numbers
  above, comfortably inside the existing 16.0/20.0ms guard budgets (no
  budget re-calibration needed or done).
- `test_mine.gd` -- PASSED (12.16s); re-checked specifically since M45's own
  Findings flagged it as the test that caught the Fix B regression there --
  no similar interaction with this fix (LOS caching doesn't touch sensor
  timers).

### New test added

`scripts/tests/test_los_cache.gd` (new, per the plan's optional "Tests"
section) -- direct test of `_has_los()` rather than re-testing relay
behavior (already covered by the suite above). Two scenarios, both using
non-overlapping IFF tags on the two test ships so the real `datalink_relay`
loop never reaches its own `_has_los` call for that pair (isolates the test
from incidental relay traffic populating the cache first):

1. **Clear LOS**: `_has_los()` in both directions matches an independent,
   uncached raycast built the same way the pre-fix inline code was; asking
   from the second ship does not grow `Ship._los_cache` (proves the
   unordered-pair key is actually shared, not just symmetric by coincidence).
2. **Blocked LOS**: same correctness check with a blocking asteroid on the
   line.

Hit one GDScript trap while writing it, not previously documented in
CLAUDE.md: **`pass` is a reserved keyword** (the no-op statement) and cannot
be used as a variable name (`var pass := true` is a parse error: "Expected
variable name after 'var'"). Renamed to `ok_result`.

### Files created / modified

- `scripts/ships/ship.gd` -- `_los_cache`/`_los_cache_frame` statics +
  `_has_los()` helper (placed next to `_get_port_authorities()`); one
  call-site replacement inside `datalink_relay`.
- `scripts/tests/test_los_cache.gd` (new) -- direct `_has_los()` test.
- `tactical_analysis/data/perf_baseline.csv`,
  `tactical_analysis/data/perf_baseline_summary.csv` -- regenerated by the
  `build.ps1` in-gate run (checked in as the latest recorded run, per this
  milestone's own note above).
