# M46-M47 — Port zone visual language + NPC port compliance

Two milestones implementing `design_ideas/port_zones_and_channels.md` (read
that first — the level ladder, geometry, and enforcement stance live there).
Split deliberately: M46 is pure drawing/data (no behavior change, verifiable
by eye and by geometry tests), M47 changes AI behavior and grant lifetime
(touches steering and the docking tests).

## M46 — Zone geometry + drawing (no behavior change)

Scope:

1. **Schema**: `port_zone` gains optional `exclusion_radius: float` (absent/
   0.0 = no exclusion zone — Levels 0-2 author nothing). Default derivation:
   hull bounding radius × factor (constant, tune ~2-3x) computed once at
   `_ready` when the station has a port_zone but no authored value; story
   overlays can override via the existing `port_patch` merge.
2. **Exclusion disc drawing** (navigation_panel.gd): diagonal-hatched annulus
   from hull to `exclusion_radius`. Hatch as clipped line segments in world
   space, constant screen-width strokes (`/ map_zoom`), same conventions as
   every other draw in the file. Pick a hatch spacing in world units so the
   rhythm holds across zoom (like the M41 dash rhythm).
3. **Channel cutout**: when the player holds a grant at this station with an
   assigned slip, suppress hatching inside the channel polygon — a corridor
   from the exclusion boundary to the berth along the berth's approach
   heading (berth pos, `Vector2.RIGHT.rotated(berth heading)`), width sized
   to clear the capture cone with margin. Draw the channel edges with
   NavCorridor (already generic). Any-open grants (slip_id "") don't open a
   channel — no specific geometry to cut.
4. **Visibility**: draw control rings AND exclusion discs for every
   controlled station on screen (zoom-gated via `zone_boundary_visible`),
   emphasized for the zone the player is inside, dimmed otherwise. Replaces
   the inside-only rule in `_draw_zone_boundary`.
5. **Small stations**: authoring choice lands here — give Slag Bay/Coldreach
   assignable berths (grant allocator, thin ring optional) OR leave open;
   per-station data only, no new code. Homes stay Level 1 (nothing draws).
6. **Tests**: geometry-only — channel polygon derivation (given berth pose +
   exclusion radius, the cutout contains the approach axis and clears the
   capture cone), derived-radius fallback vs authored override, and a
   packet/serialization test if the exclusion radius rides the state packet.
   Drawing itself is verified by eye (headless can't assert pixels).

Explicitly NOT in M46: any AI change, any grant-lifetime change, any
enforcement. A shuttle crossing the stripes is expected and tolerated here.

## M47 — NPC compliance + grant lifetime

Scope:

1. **In-zone speed compliance** (cargo_run_leaf.gd, patrol leaves if
   applicable): inside a controlled zone, NPC cruise speed clamps to the
   zone's `speed_advisory` (NPCs treat the advisory as mandatory — the
   player's warn-only behavior is unchanged). The shuttle-taps-station-and-
   spins-it hazard dies here: impact velocity drops from ~700 u/s cruise to
   ≤200.
2. **Channel routing**: a granted NPC flies to the CHANNEL MOUTH (the point
   on the exclusion boundary along the assigned berth's approach axis), then
   down the channel to the approach point — replacing the current straight
   line to a point 2000u beside the berth. Ungranted NPCs hold outside the
   exclusion radius (they already hold-and-retry when the pool is full; the
   hold point moves outside the disc).
3. **Deceleration profile**: speed ramps down along the channel (e.g. linear
   from zone limit at the mouth to capture-friendly speed at the approach
   point) so the capture spring receives a slow ship instead of yanking a
   fast one.
4. **Grant lifetime**: grant expires on EXIT of the exclusion boundary after
   undock (replacing countdown expiry for the departure leg; the
   fulfilled-pause while DOCKED stays). Update `_update_docking_grant`.
5. **Tests**: extend test_campaign_dock_health (already the E2E harness for
   exactly this traffic) — assert max station spin over the traffic window
   stays near zero (it currently only checks the endpoint), and assert
   shuttle speed inside the zone never exceeds the limit + margin. A
   channel-routing unit test: granted shuttle's path enters via the mouth,
   never crosses the hatched region. Re-run the docking suite
   (test_docking_permission, test_docking_resilience, test_port_rules,
   test_docking_nav_aids) — grant-lifetime change touches their assumptions.
6. **Perf note**: channel-mouth math is per-docking-NPC per-tick, trivial;
   but don't add per-frame allocations in the leaf (see M45 findings for the
   cost of per-frame dict copies).

Deferred beyond M47 (parked, see the design note):

- Enforcement escalation for player violations (reputation, patrol response,
  denied grants).
- Level 4 major-port content (multiple lanes, tolls, weapons-safe rule
  handlers — PortRules' registry already accepts new keys one entry at a
  time).

## Order and risk

M46 first (visual-only, zero regression surface), M47 second. M47's risky
edge is the grant-lifetime change — the docking tests encode countdown
behavior in places; budget time to re-read `_update_docking_grant`'s
freeze/expiry rules before touching them. The cargo AI change should reuse
the healing branch added with the wedge fix (aborted capture → TRANSIT) —
channel routing must not break that recovery path.
