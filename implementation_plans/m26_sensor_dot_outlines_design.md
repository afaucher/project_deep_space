# M26 — Sensor-dot outlines (v2: the outline is measured, not given)

Status: DONE (2026-07-04); **DISABLED by default (2026-07-05)** — see fallback
note below. Depends on: M25. Design:
`design_ideas/ship_outline_rendering.md` — "Decided path", v2 section.

## Fallback (2026-07-05): off by default, silhouette for everyone

The dot sampler doesn't scale at close range: it's a per-frame ray-vs-AABB over
the target's components for every subtended bin, per sensor, per ship — a close
pass on a 34-component station spiked physics from ~1ms to 120+ms/frame and
stalled the sim (the frigate's 3600-bin short-range sensor is the worst case).
A bin-count cap (`MAX_DOT_BINS_PER_SAMPLE`) brought the peak to ~20ms, but the
approach still samples on EVERY contact (only asteroids skip, lacking rects) —
including friendlies whose dots the nav panel throws away in favour of the
silhouette. So for now the whole path is gated OFF behind
`DebugSettings.SensorDotOutlines` (default OFF): **every ship contact renders as
the authoritative cached `ShipSilhouette`**, friendly or not (asteroids still
get their rocky blob). The dot code is intact and re-enableable via the debug
menu; `test_sensor_dots` / `test_collision_perf` flip it ON to keep testing it.
Revisit needs a real fix (sample only dot-drawn contacts; decouple sample rate
from sensor bin count; cheaper coverage) before it goes back on by default.

Shipped: `scripts/sensors/silhouette_sampler.gd` (pure analytic slab test
with pinned contracts, nearest-entry sample, subtense-bin math),
`_sample_outline_dots` in the sweep's correlate-tracks path (refresh-tick
only, subtended bins only, target-local dots, 192-dot ring buffer, TTL
pruning on the contact-decay clock — sensors going dark cannot leave ghost
outlines), nav-panel `_dot_draw_list` seam + demotion rule (identified
friendlies keep v1 rects, hostiles get dots only, keyed off the SAME
classification strings the blip colors use), `test_sensor_dots.gd` (all 11
items). Executed across two agents (the first died at a session limit after
completing the implementation; a finisher verified/fixed the tests). Three
test-file-only fixes, none weakening assertions (verified): a phase-driver
dead-end, a missing sensor_heading term in the item-5 harness, and an
even-bin-count seam degeneracy (target sat exactly on a bin boundary for
8 bins — fixed by a half-bin heading offset). Avoidance clearance still
662u, unchanged through M25+M26.

## Goal

Replace v1's ground-truth leak with an honest mechanism: sensors raycast into
a close contact's actual component-rect silhouette per angular bin and return
surface points. Outline quality becomes a mechanical function of the sensor
fit — no authored "detail level" policy. Hostiles show you only the side your
rays have touched.

## Scope / deliverables

- `scripts/sensors/silhouette_sampler.gd` (new; pure static, no Node deps):
  - `ray_rect_hit(origin: Vector2, dir: Vector2, rect: Rect2)` → entry
    distance or −1 (analytic slab test — NOT physics raycasts; this is
    geometry math on dicts).
  - `sample(components: Array, sensor_pos_local: Vector2, bearing: float)` →
    nearest entry point across all rects, or null. Operates in the TARGET's
    local frame; caller transforms.
  - `subtense_bins(sensor, target_pos, target_radius)` → the bin index range
    covering the target's angular subtense (uses M25's bounding radius).
- Sweep integration (`ship.gd`): for contacts inside `OUTLINE_FADE_START` and
  the sensor's own range, on that sensor's refresh tick, sample ONLY the bins
  in subtense; append hits to `contact["outline_dots"]` as
  `{pos_local, stamp}` in target-local space (so a rotating target's dots ride
  the hull). Cap `MAX_DOTS := 192` per contact (ring-buffer overwrite oldest);
  prune dots older than `DOT_TTL := 1.5s` in the existing contact-decay pass.
- Nav panel: render dots (transformed by the contact's current estimated pose)
  in the outline pass; **demote v1 static outlines to own-ship + identified
  friendlies** (they datalink true layout); hostiles/unknowns get dots only.
- Perf guardrails by construction: sampling is per-refresh-tick (not
  per-frame), per-close-contact (a handful), per-subtended-bin (a 60u ship at
  3000u subtends ~23 bins of 3600, not 3600).

## Execution (Sonnet)

Hand the agent: this doc, design doc v2 section, `ship.gd` sweep +
contact-decay regions, `navigation_panel.gd` outline pass (from M25),
guardrails. Forbid: physics-space raycasts (`intersect_ray`) — the sampler is
analytic; touching sensor stats or bands; running dots for contacts beyond
outline range.

## Test plan (Fable) — `test_sensor_dots.gd`

Pure-math battery (the foundation — most of the confidence lives here):
1. **ray_rect_hit analytic cases.** Axis-aligned hit at exact known distance;
   diagonal hit at hand-computed distance; clean miss; origin inside rect
   (define: returns 0 or exit — pick and pin); ray parallel to a face,
   grazing exactly on the edge (pin the tie-break); rect behind origin → −1.
2. **Nearest-entry.** Two overlapping-depth rects along one bearing → sample
   returns the NEARER entry (you see the skin, not the spine).
3. **Dots lie on the hull.** Sensor at origin, frigate broadside at (3000, 0):
   every dot's distance to the nearest component-rect perimeter < 0.1u in
   target-local space, and every dot is strictly nearer than the target
   center along its ray (near-side property — the honesty invariant).
4. **Bin economy (perf gate).** Instrument the sampler call count: raycast
   invocations ≤ subtended-bin-count + 2 for a single sweep. A regression to
   all-bins sampling fails loudly here instead of as frame drops.
5. **Quality scales with the sensor.** Same scene, two sensors: the 8-bin
   collision sensor yields ≥1 dot; the 3600-bin fire-control sensor yields
   ≥15 dots; dot count monotonic in bin count across {8, 36, 720, 3600}. This
   IS the design thesis — sensor stats are the detail policy.
6. **Range honesty.** A sensor whose range < target distance contributes zero
   dots; a target beyond OUTLINE_FADE_START accrues zero dots from anyone.

Integration battery (headless scene, two ships):
7. **Accrual + saturation.** Approach to 2000u, run 5s: `outline_dots` grows,
   never exceeds MAX_DOTS, and stamps refresh (newest stamp advances).
8. **Decay.** Kill the sensors (power off), advance > DOT_TTL: dots prune to
   zero via the existing decay pass — no immortal ghost outlines.
9. **Rotation honesty.** Target rotates 180° over 3s: dots exist on the
   newly-illuminated side; dots on the now-hidden side age out. Assert via
   local-frame X-sign distribution before/after (dots are target-local, so
   the hidden side's population must stop refreshing).
10. **No-leak check.** Hostile contact's draw path contains ONLY dots (no
    static rect entries); own-ship/friendly path still gets v1 rects. Assert
    on the draw-list seam from M25, not on pixels.
11. **Endurance smoke.** 3 ships in mutual outline range, 30 simulated
    seconds: no script errors, dot arrays bounded, frame tick time sane
    (soft assert: no test timeout — the run itself is the perf canary).

Pass marker: `>>> [TEST PASSED] test_sensor_dots <<<`.

## Validation phase checklist

- Run `test_sensor_dots`, `test_ship_geometry`, then the full campaign suite
  (sweep + decay paths touched — same list as M25's checklist).
- Diff review: sampler has zero Node/physics dependencies (pure statics);
  sweep integration reads component fields via `.get()` with defaults (the
  frame-abort trap); MAX_DOTS/DOT_TTL are consts, not magic numbers.
- Manual acceptance (record): approach a hostile from one side — half an
  outline appears; orbit it — the outline completes. Approach a station with
  only the collision sensor powered — blobby but sufficient.
- Mark DONE + commit (`feat: M26 sensor-dot silhouette outlines`).
