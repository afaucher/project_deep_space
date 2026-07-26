# Task dock

Open threads, one entry each. **Reference-driven**: the entry says what the
thread is and where the real detail lives — it is an index, not a second copy
of the design docs. If an entry starts growing prose, that prose belongs in
`design_ideas/` or `implementation_plans/` and the entry should shrink to a
pointer.

Conventions:
- **Decision** = blocked on a human call, not on work.
- **Ready** = scoped, nothing in the way.
- **Open** = known, unscoped.
- Dates are when the thread was opened or last moved.
- Delete an entry when it lands. Git remembers; this file should stay short.

Last swept: 2026-07-26.

---

## Decisions waiting on a human

### Pirates pick WHERE from geometry but never WHO — *2026-07-26, unscoped*
The milestone that made pirates better after the economy grew was **M53a
Slice D** ("pirate circulation", explicitly ordered *last, needs the enlarged
route set*), answering the 2026-07-20 playtest note *"we don't have enough
traffic for pirates to have a good target selection"*. It landed, then M53d
silently reverted it — the entry below is Slice D re-derived for emergent
traffic.

Slice D only ever improved **where** pirates hunt. Nothing improves **who**
they take: a pirate grabs whatever enters its lurk radius, with no notion that
one hull is worth more than another, even though the economy now has urgency,
postings and differentiated cargo.

**The posting board is fair game for pirates** — knowing a hub is desperate
for ore tells you which lane to sit on, and a market-reading guild is exactly
the emergent behaviour worth having. What is unresolved is the **information
economy** around it: who sees which postings, at what latency, at what cost,
and how that access is earned or bought. That is the same question the mail
network exists to answer, and settling it for pirates settles it generally.
Observables (hull class, which hub a ship just left, whether it rides heavy)
are the other half. Natural M53e or an M54 slice; not scoped anywhere today.
→ `implementation_plans/m53a_economic_expansion.md` Pass 4,
`design_ideas/2026-07-20-pirate_playtest.md`, `design_ideas/mail_network.md`

### Where pirates hunt now that lanes are emergent — *2026-07-26*
Three map-only targeting strategies are implemented and measured; the default
is `CROSSROADS`. Pick one (or ask for a blend) and the others can go.
Measured spread / hazard clearance over 200 assemblies: CHORD 83 cells,
APPROACH_RING 47, CROSSROADS 33, all 100% clear. The decisive metric — catch
rate against real haulers, and pirate survival near hub defences — has **not**
been measured; it needs `economy_traffic` with pirates enabled.
→ `PirateGuild.HuntStrategy`, `scripts/tests/test_pirate_targeting.gd`

### Authority-side warrant resolution is missing — *2026-07-26*
`resolve_warrant` works but the only caller is the player's own un-MARK, so
`SUSTAINED_ASSAULT` and `ARMED_ROBBERY` are permanent and unclearable by any
means in play. The doc's forgiveness half never shipped.
→ `design_ideas/2026-07-26-warrant_stickiness_audit.md`, mismatch 4

### Campaign playtest items are documented, none implemented — *2026-07-26*
Nine items across identity/standing, weapons safety, UI and naming. A1 (a
station opens fire on the player at campaign start) is the severe one.
→ `design_ideas/2026-07-26-campaign_playtest.md`

---

## Ready to pick up

### Drift Market is a pure sink and never gets served — *2026-07-26*
Zero deliveries of anything across a 3-hour sim. It only ever posts IMPORT, so
a round-trip-scoring planner with a profitability floor has no reason to fly
there. Agreed fix is a small REFINED→GOODS converter, blocked until the
refinery actually runs at rate (below).
→ `design_ideas/station_economy.md`, "Worked reference case"

### Per-hull cargo capacity from `cargo_bay` components — *2026-07-26*
`LOT_SIZE` is a flat 4.0 interim: a CargoShuttle and an Ore Barge lift the
same load. `ComponentSpec.CARGO_AREA_PER_UNIT` and the validator's capacity
maths already exist and nothing reads them at runtime. Blockers: CargoShuttle
authors no `cargo_bay` at all, and area-units need calibrating into lots.
Brings with it a **mid-tier freight hauler** (nothing exists between shuttle
and Freighter) and **per-trip travel cost**, which is what makes a big hull
economically worth owning.
→ `design_ideas/station_economy.md`, "Haul capacity is a property of the HULL"

### Regression test for SOS/relay clock coupling — *2026-07-26*
Four assertions were pinned to tick counts and broke when the relay stopped
running every frame. They now derive budgets from `DATALINK_RELAY_HZ`. Worth
one test that asserts the *contract* directly (state change reflected within
N ms) so the next cadence change has something to fail against.
→ `Ship._reconcile_sos_contact`, `Ship.DATALINK_RELAY_HZ`

---

## Open / unscoped

### Heat/EM is the top perf cost now — *2026-07-26*
`heat_em_component_loop` is 10.04% of tick, above `datalink_relay`'s 6.45%
after decimation. Known shape: ~11 component walks per ship per frame, one
literal duplicate `get_total_power_rating("reactor")` call, uncached
`get_total_rating`, string type dispatch, per-frame dict writes for unchanged
values. Analysed, not implemented.

### Station repair drain exceeds the cluster's entire trade surplus — *2026-07-26*
Self-repair burns ~7.6 lots/hr of REFINED+GOODS against a combined authored
margin of ~1.3/hr. Ironhold is the sharp case: only GOODS producer, 23%
margin, spends more than that patching itself, so GOODS reads UNSERVED
cluster-wide. This is a **navigation** finding, not an economy one — no rate
change fixes it.
→ `design_ideas/port_zones_and_channels.md`, "Rules and enforcement"
(published-limit rule specified, unbuilt)

### `SPEED_VIOLATION` has a constant, a table row, and no posting site
Consistent with the port-zones doc's own "specified and unbuilt" status.

### Economy sim runtime — *2026-07-26*
~2 real hours for 3 game-hours. The 15Hz relay cut `datalink_relay` from 18.1%
to 6.45%. Ideas not pursued: dropping the 15 beacons (all `Ship`-derived, full
pipeline each) at the cost of changed contact propagation; asteroid fields are
NOT droppable (rocks in a station approach were the 230× docking-damage
cause). The two-sim split was explicitly rejected.

---

## Recently closed (kept briefly for context, then delete)

- **Global `wanted_names` registry** — deleted 2026-07-26. Three writers, zero
  readers; the last ambient-global "enemy forever" structure.
- **Warrant unreachable after an identity change** — fixed 2026-07-26, with
  the `self_resolves_on_id` exception that keeps `NO_ID` self-resolving.
  → `scripts/tests/test_warrant_identity_change.gd`
- **Pirates stopped distributing across the cluster** — fixed 2026-07-26.
  Caused by M53d removing authored `route` arrays that hunt-point selection
  read. Strategy choice is still open (above).
