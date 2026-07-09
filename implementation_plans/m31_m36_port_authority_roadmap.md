# M31–M36 — Port authority: zones, docking permission, and nav aids

Status: M31 (2026-07-05) + M32 (2026-07-08) + M33 (2026-07-08) SHIPPED; M34–M36 PLANNED. Goal: the player requests docking (**one press** of a
top-level control that auto-runs the port-control handshake, or a full chat with
the NPC if they'd rather) and receives a **grant** — permission to dock at a
**specific assigned slip**, valid for a **time limit** and only **while inside
the port zone** (it expires on timeout or on leaving the zone) — then later
**undocks on command** (the clamp drops and the berth eases them out; the same
control flips to "Undock" while docked). Plus the navigational aids to fly it —
three cases:

1. **Docking:** see your assigned slip and its approach lane (M34).
2. **Boundaries:** see the port-zone boundary you're crossing, under which local
   rules apply (M35).
3. **The road:** see the **buoy-road travel corridor** between hubs — the lit
   beacon-graph edges (and your active route) drawn as a lane to follow (M36).

## The Architecture of Permission (Roles & Layers)

To ensure emergent gameplay (like forceful boarding, hacking, or breaking clamps), the docking architecture is strictly separated into three layers. Permission is not a magical lock; it is a system of physical and social rules.

### 1. The Mechanical Layer (M19 - `DockingBay`)
The dumb physics layer. A `DockingBay` component simply grabs things that get too close and holds them using a physical spring (`K_SPRING`). 
- **Role**: Execute `capture()`, `hold()`, and `release()`.
- **Logic**: It can be configured to capture *any* ship, or *only a specific* ship (if a `slip_id` is passed down to it). 
- **Emergence (Future)**: Because it's a physical spring, it has a yield strength. If a docked ship fires its engines hard enough, the lock **snaps**. A large pirate ship with its own `DockingBay` can physically grapple another ship against its will.

### 2. The Systemic Layer (M32 - Port Authority Rules)
The traffic control rulebook. This lives on the station's main hull (via `ship.gd`) and manages the dumb mechanical bays.
- **Role**: Manage reservations, issue `DockingGrant`s, and enforce timeouts.
- **Logic**: It tells the Mechanical Layer who is allowed in. If a ship arrives without a grant in a controlled zone, the Systemic Layer tells the Mechanical Layer to keep its tractor beams off.
- **Absence**: A station/asteroid *without* a Port Authority (e.g., an open Slag Bay) simply doesn't run this layer. The Mechanical bays fall back to their default "grab anyone who wants to dock" behavior.

### 3. The Social Layer (M33 - Port Authority NPC)
The interface. This is the NPC you hail on the comms panel.
- **Role**: Judge the player (IFF, reputation, ship size) and interact with the Systemic Layer on their behalf.
- **Logic**: You ask the NPC for clearance. If they like you, *they* invoke the Systemic Layer to issue you a grant. 
- **Absence**: If a station has a Systemic Layer (it's locked down) but the NPC is dead or missing, you cannot get permission through normal channels. You would have to hack the Systemic Layer, or bypass it entirely by using forceful boarding (Mechanical Layer) to clamp onto them.


## Decisions (locked with the user)

- **Permission is a property of a *controlled* zone, not of docking.** A station
  that declares a port zone (Ironhold) requires a grant; an open outpost (a Slag
  Bay mining berth) has no zone and docks permissionless, exactly as today. So
  M32's gate is conditional: *no zone → old behavior untouched.*
- **A grant assigns ONE specific slip** — at a *full-service* port. Only that
  slip's bay captures the holder; the nav aid highlights that slip + its approach
  lane ("Cleared to berth 3, lane heading 040"). Smaller ports **degrade** this
  to "any open slip" (see Authority styles below).
- **Local rules (M35): boundary HUD + the permission rule + an in-zone speed
  *advisory* (warn, don't hard-enforce).** Rules live as data so weapons-safe /
  hard speed limits / etc. can be added later without new plumbing.

### Defaults (not asked — sensible, changeable)

- **Zone = a circle** (center = station position, one `radius`). Matches the
  bearing+range sim; an authored polygon can come later behind the same
  `contains()` interface.
- **Overlapping zones → nearest controlled station wins** for "which zone am I
  in" (rare; the beacon-road layout spaces hubs far apart).
- Grant duration, the speed-advisory limit, and lane length are tuning consts,
  pinned in tests within loose bands.

## Authority styles — how the process degrades by station

The full apparatus (automated control, assigned berth, lanes, zone rules) is the
*top* of a spectrum, not a universal tax. A controlled station's authority
declares a **`style`** that scales the whole experience; the mechanics
underneath (grant → gate → capture → undock) are identical, only the
*presentation, reliability, and formality* change. This keeps one code path and
lets a rusty outpost feel different from a core hub for free.

| Style | Who answers | Request UX | Slip | Nav aids / rules | Fiction |
|---|---|---|---|---|---|
| `OPEN` | nobody | — (no comms, no grant) | dock any berth, permissionless | none (no zone) | mining berth, Slag Bay |
| `MINIMAL` | a terse/flaky computer | one **"dock"** choice; **may stall** → "stand by…", re-request to retry | **any open slip** | zone optional; usually just `permission_required`, no speed advisory, no assigned lane | backwater autoport |
| `STAFFED` | **a person** (named dockmaster NPC) | a short conversation, informal; reliable but has personality | any-open or assigned (author's call) | zone + boundary HUD; lane only if a specific slip is named | small crewed station |
| `AUTOMATED` | "Ironhold Control" (impersonal system) | one-press instant clearance OR full menu | **specific assigned slip** | full: zone + assigned lane + speed advisory | core hub |

How each milestone reads `style` (no new milestone — it's a parameter):
- **M31/M32:** the grant/gate/undock mechanics don't care about style. A
  `MINIMAL`/`STAFFED` grant with slip = "any open" just means the gate accepts
  the first free bay instead of one specific `slip_id` (a null/`-1` slip = any).
- **M33 (the main consumer):** the authority NPC's name + `dialogue_path` +
  reliability come from `style`. `STAFFED` = a personal name and a
  conversational tree; `MINIMAL` = a single "dock" node with a **seeded stall
  chance** (deterministic in tests) that returns "stand by / no response",
  requiring a re-request; `AUTOMATED` = the instant one-press path. The
  one-press affordance still works for all (it just may need a retry at
  `MINIMAL`, and reads as a quick exchange at `STAFFED`).
- **M34:** an "any open slip" grant highlights the open slips and draws **no
  single lane** (nothing to line up on); a specific-slip grant draws the lane.
- **M35:** a station's `rules` dict simply carries fewer entries for lesser
  ports (a `MINIMAL` port may have only `permission_required`, no
  `speed_advisory`) — the data-driven ruleset degrades with zero new code.

## NPC / player parity — one dock pool, one issuance path

Docking is **one** substrate; players and NPCs are just two request sources into
it. The rule: **a single slip pool per station and a single
`issue_docking_grant` path**, and everyone goes through them. An NPC that takes
berth 3 removes it from the player's options and vice-versa — no NPC fast-lane,
no double-booking, no separate accounting to drift out of sync.

| Subsystem | NPC parity | Notes |
|---|---|---|
| Slip pool + `issue_docking_grant` | **SHARED** | one allocator; occupancy = live grants ∪ capturing/docked bays |
| Grant / gate / capture (M19/M32) | **SHARED** | both flow through the same `DockingBay` path |
| Undock (M32) | **SHARED mechanic**, AI-triggered | NPC behavior tree issues `undock` where the player presses the button |
| Zone membership + grant expiry (M31) | **SHARED** | an NPC's grant also lapses on timeout / zone-exit |
| Comms dialogue (M33) | **diverges** | NPCs skip the dialogue UI and call the SAME issuance directly — an AI "request docking" action IS the player's one-press fast-path |
| Nav aids / HUD (M34–M36) | **player-only** | lanes, slip highlights, banners, the speed number are visualization |
| Speed advisory (M35) | **player-only** for now | warn-only; if a *future* rule ENFORCES (weapons-safe w/ consequences), NPCs become subject too — leave the hook |

### Two allocation models (how "which bay" is decided)

The capture mechanic itself is unchanged from M19 — a `DockingBay` has a
`capture_radius`, `_try_capture()` grabs an eligible ship on entry, the servo
spring clamps it. What differs by port is *how a bay is chosen*:

- **Assigned (specific-slip, AUTOMATED).** Issuance **reserves** slip N in the
  pool; the grant carries `slip_id = N`; the bay gate lets **only bay N** capture
  the holder; the M34 lane guides you there. Reservation held (nobody else can
  take N) until you dock or the grant lapses. No races — your berth is kept.
- **Free-for-all (any-open, MINIMAL / optionally STAFFED).** Issuance reserves
  **nothing** — the grant is a permission flag (`slip_id = -1`); the gate lets
  **any FREE bay** capture the holder; you **pick by flying into an open bay's
  radius** and it clamps (the M34 aid highlights which bays are open so you have
  something to aim at). The slip is **claimed at capture** and freed on undock.
  Pool integrity holds at the *bay* level (a bay won't capture if it's already
  CAPTURING/DOCKED), not via reservation — so two holders racing the last bay is
  first-come, and the loser's gate simply finds no free bay and must wait/divert.
  Issuance still checks there's ≥1 free bay before clearing you (else "no
  berths"); it just doesn't hold one.

So: **assigned = reserved slot, no race, directed by a lane; any-open = sail into
whatever's lit, first-come.** A core hub feels orderly; a backwater is a scrum —
emergent, and it costs nothing extra because the proximity capture already
exists. What M32 actually *builds* here is small: the gate's two-branch check
(specific vs any-free) and the claim-at-capture / free-on-undock pool bookkeeping.

- A reserved slip (or a claimed one) returns to the pool the instant the grant
  lapses (timeout / zone-exit, M32) or the ship undocks — free for the next
  requester of either kind.

**NPC docking AI (the `cargo_run_leaf` change, promoted from a footnote):** at a
controlled station the leaf runs the SAME lifecycle as the player — request a
grant (call the shared issuance) → on grant, `wants_dock` → capture → do its
business → `undock`. At an OPEN station it keeps the old permissionless
`wants_dock`. That's the concrete parity: the NPC uses the player's
request→dock→undock flow, driven by the behavior tree instead of buttons. Verify
in-agent that a full station makes NPC haulers *wait or divert* (no grant) rather
than pile up at the capture radius.

## What this builds on (existing substrate — do not re-invent)

- **Docking (M19):** `scripts/docking/docking_bay.gd` — one `DockingBay` per
  authored berth (so multiple slips per station already exist), states
  EMPTY/CAPTURING/DOCKED, force-capture when a ship is `dockable` + `wants_dock`
  + within `capture_radius`. Eligibility is `_dockable_seeking(s)`. Berths are
  grown in `Ship._ready()` from `get_berths()`.
- **Comms:** `scripts/ui/comms_panel.gd` + `scripts/comms/comms_ledger.gd` +
  `NPCProfile` + the Dialogue Manager addon. NPCs are transponder-discovered,
  each with a `dialogue_path`; clicking hails them; dialogue mutations are
  server-authoritative (`design_ideas/story_driven_comms.md`). **Port control is
  just another NPC dialogue** whose outcome mutates docking state.
- **Spatial:** clusters, beacon roads, landmarks/transponders, simulation radius
  (`design_ideas/campaign_spatial_model.md`). Stations are landmarks. No gameplay
  "zone under local rules" exists yet — that's M31.
- **Nav:** `scripts/ui/navigation_panel.gd` (map, contacts, bounds ring). No
  slip/lane/zone rendering yet.

## Dependency order

```
M31 Port Zone (spatial substrate: contains() + enter/exit events)
  ├─► M32 Docking permission (grant model + conditional bay gate + expiry)
  │      ├─► M33 Port Control comms (NPC dialogue issues the grant)
  │      └─► M34 Docking nav aids (assigned slip + lane, from the grant)
  │             └─► M36 Buoy-road corridor (reuses M34's corridor helper)
  └─► M35 Zone boundary aid + local rules (boundary HUD + permission + speed advisory)
```

M31 first (everything leans on it). M32 next (the mechanical heart, testable
with programmatic grants — no NPC needed). M33/M34 both depend on M32; M35
depends on M31; M36 depends only on the existing beacon graph + M17 NavComputer
plus M34's shared corridor helper — it's **independent of the permission chain**
(M31–M33), so it can slot in whenever after M34 (or earlier if the corridor
helper is built standalone). M34/M35 are independent of each other.

## Execution model

Same loop as M21–M30: a Sonnet subagent implements one milestone from this doc,
Fable (main session) validates — re-runs the milestone's gates + regression,
diff-reviews for test-weakening, commits per milestone. Standing guardrails:
preload consts (not bare `class_name`) in new test files, never `--check-only`
for validation, one headless Godot instance at a time, tabs, `.get()` defaults
in hot paths, no test weakening, `var x: Array = arr.filter(...)`.

---

## M31 — Port Zone (the spatial substrate)

Goal: a controlled station owns a circular **authority zone**; any ship can ask
"am I in it?", and a ship crossing the boundary fires a single enter/exit event.
This is the substrate M32's expiry, M35's rules, and M35's boundary aid all use.

### Scope

- **Zone data on the station.** A controlled hull declares
  `port_zone := {"radius": float, "authority": String, "rules": Dictionary}`
  (empty `{}` = uncontrolled/open). Author it on the controlled station(s); a
  station with berths but no `port_zone` stays fully permissionless. Expose
  `get_port_zone()` and a pure `PortZone.contains(center, radius, point) -> bool`
  helper (a static in a small `scripts/port/port_zone.gd`, `class_name
  PortZone`) so tests can drive the geometry with fixtures.
- **Per-ship membership + edge events.** Each ship tracks the controlled zone it
  is currently inside (nearest one, or null). Recompute on a cheap cadence in
  `_physics_process` against controlled stations in the sim bubble (distance
  test only — do NOT ray/sample). On a transition, record an event
  (`{"type": "zone_enter"|"zone_exit", "authority": name}`) into the existing
  `transient_events` channel the terminal already consumes, and update
  `ship.current_port_zone`. Debounce with a small hysteresis band on the radius
  so a ship hovering the boundary doesn't thrash events.
- Cost note (we just paid for one of these): the check is one distance compare
  per controlled station per ship per tick — trivially bounded; there are a
  handful of controlled stations, not hundreds.

### Test plan (Fable) — `test_port_zone.gd`

1. **Geometry:** `PortZone.contains` true inside, false outside, true on the
   boundary-minus-epsilon; pure fixtures, no scene.
2. **Enter/exit fire once:** a ship flown across the radius sets
   `current_port_zone` and emits exactly one `zone_enter` then, on exit, exactly
   one `zone_exit` — not one per frame (proves the edge-detection + hysteresis).
3. **Open station = no zone:** a station with `port_zone == {}` never sets
   `current_port_zone` for a passing ship.
4. **Nearest wins:** with two overlapping controlled zones, the ship reports the
   nearer authority.
Regression: `test_docking`, `test_docking_multi`, `test_freighter_docking`,
`test_cargo_run` (zone tracking must not perturb existing docking/traffic).

### Shipped (2026-07-05)

`scripts/port/port_zone.gd` (`PortZone.contains`, pure static), `Ship.port_zone`
/ `get_port_zone()` / `current_port_zone` + `_update_port_zone_membership()` in
`_physics_process` (scans the `"ships"` group for controlled stations, nearest
containing zone wins, `PORT_ZONE_EXIT_MARGIN = 200.0` hysteresis, one
`zone_enter`/`zone_exit` into `transient_events` per transition, gated to
authority + alive). Ironhold zone on `medium_station.gd` (`radius 8000`,
authority "Ironhold Control", empty `rules` — M35 fills it). `test_port_zone`
(4 items) + the docking/traffic regression all green. Friction: teleporting a
`RigidBody2D` in the test needs `PhysicsServer2D.body_set_state` (a plain
`position =` gets snapped back by the physics server → the test hung with no
error). Note: membership scan is O(N²) across authority ships but each op is a
cheap dict check — revisit only if ship counts get large (cache the controlled
list).

---

## M32 — Docking permission model (grant + conditional gate + expiry)

Goal: in a controlled zone, a bay only captures a ship that holds a valid grant
— its assigned slip, or any free bay for an any-open grant; the grant dies on
timeout or on leaving the zone. Open stations are untouched. Grants are issued
programmatically here (a function the tests call now and M33's dialogue calls
later) — no NPC yet.

### Scope

- **`DockingGrant`** (a dict, or a tiny `class_name DockingGrant`):
  `{"authority": station_id, "holder": ship_id, "slip_id": int, "issued_at",
  "expiry_at", "zone_center": Vector2, "zone_radius": float}`. Held on the ship
  as `ship.docking_grant` (null = none).
- **Issuance = the single pool gate** (see "Two allocation models"):
  `Station.issue_docking_grant(ship) -> DockingGrant`. Both models first check
  the pool has room (≥1 free bay: not reserved by a live grant and no bay
  CAPTURING/DOCKED); if none → return null ("no berths"). Then, by the port's
  slip-assignment policy (its authority style): **assigned** ports pick + reserve
  a concrete free slip and stamp `slip_id = N`; **any-open** ports stamp
  `slip_id = -1` and reserve nothing (the bay is claimed at capture). Either way
  the *caller never picks* — that's what stops players and NPCs double-booking.
  Server-authoritative (host owns it). Used by tests now, by M33's
  dialogue/fast-path and the NPC docking AI later.
- **Bay gate (the conditional part):** extend `DockingBay._dockable_seeking(s)`
  so that **when the host station has a `port_zone`**, eligibility ALSO requires
  a valid `s.docking_grant` issued by this station, then branches on the grant:
  `slip_id >= 0` → **only that slip's bay** accepts; `slip_id == -1` (any-open) →
  **any free bay** accepts (claims the slip at capture — mark it taken so a
  concurrent holder can't also land here). **No `port_zone` → check unchanged**
  (old permissionless capture). Map each `DockingBay` to a stable `slip_id` (its
  index in `get_berths()`), set at creation in `Ship._ready()`.
- **Expiry (two ways):** a per-tick validity check on the holder clears
  `docking_grant` when `now > expiry_at` OR the holder is outside the grant's
  zone (reuse M31 `current_port_zone` / `PortZone.contains`). Emit a
  `grant_expired` transient event so the UI can say "clearance lapsed". Use `now`
  from an injected/sim clock, not `Time` directly, so tests are deterministic
  (pass the tick delta / a frame counter — mirror how existing sims advance).
- **Undock (player-initiated release).** Today the bay auto-releases after
  `dock_duration`; instead a DOCKED ship holds until it issues an `undock`
  command (`dock_duration` becomes a minimum hold before undock is allowed, so
  you can't pop mid-capture). On undock: **drop the servo spring FIRST** (so the
  pilot isn't fighting the clamp), then impart a gentle separation impulse along
  the berth's outward heading to clear the berth, then EMPTY. Add the `undock`
  command endpoint (RPC/input). The player triggers it via the context docking
  control (built in M33 — "Undock" when docked); NPC docking behaviors issue it
  after their business (the `cargo_run_leaf` calls `undock` instead of relying on
  the timer — small leaf change, resolve in-agent and note it). This makes
  docking round-trippable at OPEN stations with no grant/comms needed.
- **Tunables:** `GRANT_DURATION` (start ~120s), the separation-impulse strength,
  documented + pinned in tests.

### Test plan (Fable) — `test_docking_permission.gd`

1. **Controlled + no grant → no capture:** a `wants_dock` ship in a controlled
   station's capture radius is NOT captured (bay stays EMPTY) without a grant.
2. **Controlled + valid grant → docks:** issue a grant for the assigned slip →
   the ship captures, settles, and reaches DOCKED (reuse the M19 capture
   harness).
3. **Specific-slip:** grant assigned to slip 2 → bay 2 captures, bay 1 ignores
   the same ship even though it's in range.
4. **Timeout expiry:** advance the sim past `GRANT_DURATION` → grant cleared,
   subsequent capture blocked, `grant_expired` event emitted.
5. **Zone-exit expiry:** with an unexpired grant, move the holder outside the
   zone → grant cleared even though time remains.
6. **Open station unchanged:** a station with no `port_zone` captures a
   `wants_dock` ship with NO grant (proves the fallback path is intact).
7. **Undock round-trip:** a docked ship holds DOCKED past `dock_duration` (no
   auto-release) until an `undock` command; after undock the servo spring is
   released and a separation impulse leaves the ship clear of the berth and free
   to maneuver, bay back to EMPTY. Run at an OPEN station (no grant needed).
8. **Shared pool (cross-source):** an NPC holding a granted slip → the player's
   `issue_docking_grant` allocates a DIFFERENT slip; with every slip reserved or
   occupied, the next request (either source) returns null (full). Proves one
   pool, no double-booking, no NPC-vs-player fast-lane.
9. **Any-open capture + claim:** with a `slip_id = -1` grant, the ship is
   captured by whichever free bay it enters (reuses M19 proximity capture); that
   bay's slip is then marked taken so a second any-open holder flown at the same
   bay is NOT captured there and must take another free bay (or wait if none).
   Proves claim-at-capture and no double-landing.
Regression: `test_docking`, `test_docking_multi`, `test_freighter_docking`,
`test_cargo_run`, `test_patrol` — NPC haulers still dock (they'll need a grant
path at controlled stations; if the campaign's civilian dock is controlled,
either mark it open or have the cargo-run leaf request a grant — resolve in-agent
and note it).

### Shipped (initial 2026-07-08; completed 2026-07-08)

Landed as part of the "M19 Universal Docking Refactor + M32" commit, then
finished out. In `ship.gd`: `DockingGrant` dict, `issue_docking_grant(ship)`
(the single pool allocator — reserves a concrete slip for `slip_policy
"assigned"`, leaves `slip_id=""` for `"any_open"`, denies when full),
`_update_docking_grant()` per-tick expiry (`time_left` countdown OR zone-exit
via M31's `current_port_zone`, frozen once CAPTURING/DOCKED), `manual_undock` +
`request_undock()`. In `docking_bay.gd`: the conditional grant gate in
`_dockable_seeking` (open station unchanged; assigned → only the matching
`slip_id` bay; any-open → any free bay, claimed at capture), and
`release_with_push()` (drop servo + separation impulse).

Friction / fixes during completion (the refactor shipped red under a disabled
build gate — see below):
- **Build gate had been disabled** (`# exit 1` in `build.ps1`) — RESTORED, so
  red tests fail the build again.
- **Approach-capture cone bug:** `_try_capture`'s hemisphere gate was `> 0.866`
  (a 30° cone) contradicting its own "far side" comment; a legitimate ~31°
  approach was rejected. Corrected to `> 0.0` (true hemisphere).
- **MobileHome** had a `living_quarters_1`/`hull_port` overlap (validator error)
  — moved the quarters outboard.
- **Refactor renames:** `Ship._received_em_power`/`_total_received_em` moved to
  `Utils.get_directional_em_power`/`get_directional_em` (test callers updated);
  bays are now built per `docking_port` component with `has_servo` from the
  component (hand-made test bays must set rotation + has_servo).
- Test coverage was issuance-only; **`test_docking_permission` extended** to the
  full lifecycle: grant→DOCKED, undock round-trip (holds past `dock_duration`,
  `request_undock`→EMPTY), timeout expiry, zone-exit expiry, specific-slip gate,
  any-open gate. `EXPECTED_LAYOUT_WARNINGS` re-frozen for the docking-port-bearing
  stations + Mobile Home registered.
- NPC-at-controlled-station grant path: current campaign NPC docks are OPEN
  (`SmallStation`), so unaffected; the cargo-run leaf grant path is still owed
  when an NPC needs a *controlled* berth (carry to M33's NPC parity work).
- Watch-item: `build.ps1` runs tests in PARALLEL and a heavy sim (`test_missile_ai`)
  can false-timeout under starvation — passes standalone; not a real failure.

---

## M33 — Port Control comms (the dialogue that issues the grant)

Goal: the player-facing loop — hail port control, request docking, receive a
slip assignment. Wires the existing Dialogue Manager comms to M32's issuance.

### Scope

- **A port-control NPC per controlled station.** Surface it in `comms_panel`'s
  NPC list when the station's transponder is in range (same discovery path other
  NPCs use): name e.g. "Ironhold Control", faction = the authority, a
  `dialogue_path` to a new port-control dialogue resource.
- **The dialogue issues the grant.** A "request docking" branch runs a
  server-authoritative mutation that calls `Station.issue_docking_grant(player,
  open_slip)` — assigning the next open slip — and the reply reads back the slip
  + a lane heading ("Cleared to berth 3, approach heading 040"). If no slip is
  open → a "hold / no berths" branch, no grant. Denials for hostile IFF are a
  natural extension (note as a hook, out of scope unless trivial).
- Keep the dialogue content small — one request/grant/deny tree; this milestone
  is about the *wiring*, not writing a script.
- **Top-level "Request Docking" affordance (fast path + chat).** A context
  control (button + hotkey), shown when a controlled station is targeted/in
  range: **one press runs the whole handshake automagically** — hail port
  control → request → receive the grant → surface the clearance — with no manual
  dialogue navigation. The player can still open the full dialogue to chat
  instead (same NPC, same grant mutation). When the ship is DOCKED, the same
  control becomes **"Undock"** and calls M32's undock command. So one
  context-sensitive docking button covers request → undock, and the dialogue
  stays available for flavor/negotiation. The auto-path and the dialogue path
  hit the SAME server-authoritative issuance, so there's one code path to trust.

### Test plan (Fable) — `test_port_control_comms.gd`

1. **Grant mutation path:** invoke the port-control "request docking" mutation
   for a player ship at a controlled station → a valid `DockingGrant` is issued
   with an open slip assigned; the ship can then dock (feeds directly into M32's
   gate — assert DOCKED).
2. **Slip allocation:** two requesters get two DIFFERENT open slips; a third when
   the station is full gets the "no berths" outcome (no grant).
3. **Discovery:** the port-control NPC appears in the comms NPC list only when
   the station's transponder is in range, and disappears out of range.
4. **Fast-path parity:** the one-press "Request Docking" affordance yields the
   SAME grant (same slip, same expiry semantics) as walking the dialogue tree —
   both routes call the one issuance path.
5. **Context flip:** the docking control reads "Request Docking" when clear and
   "Undock" when DOCKED, and the "Undock" press drives M32's undock to EMPTY.
6. **Style degradation:** an `AUTOMATED` port grants on the first request; a
   `MINIMAL` port with a seeded stall returns "stand by / no grant" and a
   re-request then succeeds (deterministic seed, no flakiness); a `STAFFED` port
   surfaces a personal NPC name (not "…Control") and still yields a valid grant.
   Assert the grant/slip outcome per style — the shared mechanics underneath are
   identical.
Regression: M32 suite + `test_comms_relay` / `test_comms_chat` (dialogue/comms
plumbing intact).

### Shipped (2026-07-08)

`scripts/port/port_control.gd` (`PortControl`, pure static helpers): style
lookup (`get_style`/`get_controller_name` — AUTOMATED reads the zone
authority, STAFFED reads a personal `dockmaster_name`, MINIMAL reads
"`<authority> (auto)`"), the single `request_docking(station, ship)` entry
point both the dialogue mutation and the fast-path button call (wraps
`Station.issue_docking_grant`, unchanged from M32), and the MINIMAL "stall"
degradation as a deterministic per-station attempt counter (`
MINIMAL_STALL_ATTEMPTS`, not RNG — see "Friction" below). `Ship.
request_docking_via_control(ship)` (ship.gd) is a thin wrapper so a `.dialogue`
mutation can drive `PortControl.request_docking` via a plain object method
call. `port_zone["style"]` added as a new top-level key (Ironhold →
`AUTOMATED`, medium_station.gd); a port-control `NPCProfile` (PUBLIC tier) is
appended to the station's `available_npcs` in `_init()`, named via
`PortControl.get_controller_name`. `dialogue/port_control.dialogue`: one small
request/grant/deny/stall tree, branching on `station.get_port_zone()`'s style
for the greeting line, calling `station.request_docking_via_control(player)`
on "Request docking.". `scripts/ui/docking_control.gd` (`DockingControl`, a
`Button` subclass): the context-flip "Request Docking"/"Undock" control —
`_is_docked()` checks `docking_bay != null`; delegates fully to `PortControl`
so button and dialogue share one behavior. Wired into `terminal_display.gd`'s
top bar, resolving `target_station` from the nav/contacts selection each
frame via `instance_from_id` (same pattern `navigation_panel.gd` already
uses). `comms_panel.gd`: `get_active_transponder_data()` (ship.gd) now
includes `dialogue_path` + `tier` per broadcast NPC (was missing both — an NPC
button had nowhere to load a conversation from); `_start_dialogue`/
`_process_dialogue` thread `extra_game_states` (`[{"station":...,
"player":...}]`, resolved via `instance_from_id`/`_get_my_ship()`) into every
`DialogueManager.get_next_dialogue_line` call, so a `.dialogue` mutation can
address the hailed station and the local player ship by name. `test_port_control_comms.gd`
(32 assertions: a real DialogueManager traversal smoke check plus the 6 roadmap
scenarios) + the M32/M31/comms regression set all green (see Friction).

Friction / fixes during completion:
- **`slip_id` is a `String`, not an `int`** — the roadmap's "-1 = any-open"
  language (line 84, 128) predates M32's actual shipped shape (`""` = any-open,
  a concrete component id like `"dock_main"` = assigned); `PortControl` and the
  dialogue/test code follow the real shape, not the doc's.
- **DM compiler bug on chained bracket indexing**: `result["grant"]["slip_id"]`
  inside a `.dialogue` mutation/interpolation hits a typed-array coercion error
  in `DMExpressionParser._build_token_tree` (`Array[Dictionary]` assigned to an
  `Array[Array]`-typed local) and fails to compile. Worked around by flattening
  through two `do` assignments (`do grant = result["grant"]` then `do slip =
  grant["slip_id"]`) instead of one chained expression — no engine/addon file
  touched.
- **`.dialogue` files need a real import pass to load headlessly** — a bare
  `--run-test`/`--script` invocation errors "No loader found for resource" on a
  brand-new `.dialogue` file with no `.import` sidecar yet; a one-time
  `--headless --editor --quit-after 1` run generates it (same as any other
  Godot-imported asset). Also surfaced the actual dialogue compile error (the
  bracket-chaining bug above), which a bare load doesn't report as clearly.
- **`DialogueResponse` carries no `extra_game_states` field** — confirmed by
  reading `addons/dialogue_manager/dialogue_response.gd`; `comms_panel.gd`
  never needed one (it rebuilds `extra_game_states` fresh from
  `_dialogue_game_states()` on every `_process_dialogue` call, including from
  `_on_response_clicked`), but an early test draft assumed the field existed
  and silently dead-ended a scenario with no failure recorded — fixed by
  reusing the same `extra_game_states` array across both `get_next_dialogue_line`
  calls, matching the real UI code path.
- **GDScript lambda closures capture locals by VALUE at connect-time, not by
  reference** — an early test draft tried to capture a signal's emitted payload
  into an outer local via `signal.connect(func(o): outer = o)`; the reassignment
  never propagated out. Fixed by asserting on the button press's real side
  effect (`ship.docking_grant`) instead of a captured signal argument.
- **Full multiplayer-authority RPC wiring for the fast-path button is left as
  a follow-on, not built here**: `DockingControl`/`PortControl` call
  `Station.issue_docking_grant`/`Ship.request_undock` directly (matching how
  `test_docking_permission.gd` already calls `request_undock()` directly, and
  how `@rpc(..., "call_local")` methods work when called locally by the
  authority), the same way the existing helm/weapons panels call ship methods
  via `rpc_id(1, ...)` for cross-peer safety. `DockingControl` does NOT yet
  route through an `rpc_id` — fine for host/single-player (the only mode
  exercised by the M33 test plan), but a client peer's button press would need
  a new `@rpc` endpoint on `Ship` to be safe over the network. Flagged, not
  fixed — out of the M33 test plan's scope.
- `docking_bay.gd` (M32), `ship.gd`'s M32 grant machinery, and
  `medium_station.gd`'s pre-M33 fields were read but not modified beyond the
  additive `style` key and the `request_docking_via_control` wrapper (both
  additive, no existing behavior changed) — confirmed by the full M32/M31/comms
  regression suite staying green.

---

## M34 — Docking nav aids (assigned slip + lane)

Goal: fly the clearance. Show the assigned slip and its approach lane so lining
up is legible.

### Scope

- **Assigned-slip highlight** on the nav map: the granted slip's berth pose
  drawn distinctly (bright, authority-colored), other slips dimmed. Driven by
  `player.docking_grant.slip_id` → the bay's berth transform. **Any-open grant**
  (`slip_id` null/`-1`, the degraded style) → highlight ALL open slips equally
  and draw no single lane (nothing specific to line up on).
- **Docking lane:** a guide corridor from an approach waypoint to the berth,
  along the berth heading (`bay.rotation`) — a centerline + soft corridor edges,
  length = a `LANE_LENGTH` const. Build a **shared corridor helper**
  `scripts/nav/nav_corridor.gd` (`class_name NavCorridor`) — a pure static
  `corridor(path: PackedVector2Array, half_width: float) -> Dictionary`
  ({centerline, left_edge, right_edge}) — so the docking lane AND M36's
  buoy-road corridor draw the same way and it's unit-testable without rendering.
  The panel just draws what the helper returns.
- **Helm berth bug — DEFERRED** (user call). The heading-dial marker for the
  berth is out of scope for M34; the nav-map slip highlight + lane carry the
  approach. Revisit if the map alone doesn't make final line-up legible.
- No new state plumbing — the grant already rides the packet (M32 adds it).

### Test plan (Fable) — `test_docking_nav_aids.gd`

1. **Lane geometry:** the computed lane centerline starts at berth_pos and runs
   along berth_heading for `LANE_LENGTH`; corridor edges are parallel at the
   authored half-width. Pure fixtures.
2. **Assignment binding:** with a grant for slip 2, the highlighted berth pose
   equals bay 2's transform (not bay 1's).
3. **No grant → no aid:** without a grant, no slip is highlighted and no lane is
   drawn (the helper returns empty).
Manual: fly a clearance into Ironhold and confirm the lane reads clearly.

### Shipped (2026-07-08)

`scripts/nav/nav_corridor.gd` (`NavCorridor`, `RefCounted`, pure static
`corridor(path: PackedVector2Array, half_width: float) -> Dictionary` —
`{centerline, left_edge, right_edge}`, offset perpendicular to each segment by
`half_width` with a plain miter average at interior vertices; generic over any
polyline length so M36's buoy-road corridor can call the same helper later —
not built here). `scripts/ui/navigation_panel.gd`: pure/testable seams
`assigned_bay_for(bays, grant)` (matches `grant.slip_id` to a bay's `slip_id`,
`null` for no grant / any-open / no match), `open_bays_for(bays)` (all
`State.EMPTY` bays, for the any-open "highlight everything open" case),
`lane_path(berth_pos, berth_heading, length)` + `lane_corridor(...)` (composes
`lane_path` with `NavCorridor.corridor`), plus `_draw_docking_nav_aids()` /
`_draw_slip_marker()` / `_draw_lane()` wiring them into `_draw()` (world-space,
inside the panel's existing `draw_set_transform_matrix` block, `.../map_zoom`
constant-screen-width convention). `LANE_LENGTH = 1500.0`,
`LANE_HALF_WIDTH = 120.0`, gold `SLIP_HIGHLIGHT_COLOR`/dim
`SLIP_DIM_COLOR`/lane colors (a hue not already claimed by the classification
palette). `scripts/main.gd`'s `_distribute_state()` packet gained one field,
`"docking_grant": ship.docking_grant` (main.gd:415) — see "Packet vs.
instance_from_id" below for why this one field IS plumbed through the packet
while bay poses are NOT. `scripts/tests/test_docking_nav_aids.gd` (28
assertions covering all 3 roadmap scenarios plus a few defensive extras — a
mismatched slip_id, an empty bays list, a rotated heading, and a 3-point
`NavCorridor` path to prove it's genuinely generic) + the full regression set
green: `test_docking_permission`, `test_port_zone`, `test_docking_multi`,
`test_port_control_comms`, `test_comms_chat`, `test_comms_relay`, `test_nav`.

Deviations / friction:
- **Packet vs. `instance_from_id`: split the difference, deliberately.** The
  brief flagged this as a real decision, not a formality. `docking_grant` is a
  small value (authority/slip/time_left strings+floats) that
  `navigation_panel.gd` has NO other way to reach — unlike `docking_control.gd`
  (M33), the nav panel is never handed a live `player_ship`/`target_station`
  reference; it is 100% packet-driven (`update_data(packet)` is its only
  input, and `terminal_display.gd` already injects extra UI-only keys
  — `pinned_contacts`, `is_ship_oriented`, `selected_contact_id` — into that
  same packet before forwarding it). Adding `docking_grant` alongside those is
  the smallest change that fits the panel's existing architecture. Bay
  **poses**, by contrast, are live node transforms already resolvable in-process
  (host and every ship share one scene tree — the same fact M33 leaned on for
  `instance_from_id`/group lookups) and would be pure duplication to serialize
  every frame for every berth at every controlled station. So: `docking_grant`
  rides the packet (one small value, no other path in); the assigned
  `DockingBay` node is resolved live via `get_tree().get_nodes_in_group(
  "docking_bays")` filtered by parent (the same group `docking_bay.gd:64`
  already registers, `get_berths()` on `Ship` already reads the same way) once
  `_draw_docking_nav_aids()` has matched the grant's `authority` to a
  controlled station in the `"ships"` group. This is NOT the exact
  `instance_from_id` pattern (there is no contact/instance id for "which
  station issued this grant" to resolve from — the grant only carries the
  authority *name*), so the station lookup is a linear scan of `"ships"` by
  `get_port_zone().authority`, same cardinality/cost class as M31's own
  zone-membership scan (a handful of controlled stations, not hundreds).
- **The roadmap prose's "No new state plumbing — the grant already rides the
  packet (M32 adds it)" is wrong** — checked directly: M32/M33 never added
  `docking_grant` to `_distribute_state()`'s packet dict (grep confirmed no
  hit before this milestone). One field added here; noted so a future reader
  doesn't go looking for it in the M32 diff.
- **"`slip_id` null/`-1`" (scope bullet, line ~535) is the same stale doc
  language M33's Friction notes already flagged** — the real shipped shape is
  `slip_id: String`, `""` = any-open. `assigned_bay_for`/the test file follow
  the real shape.
- Helm berth-dial marker: confirmed still untouched, per the spec's explicit
  DEFERRED call — no changes to `helm_panel.gd`.
- No port-zone circle added to the nav map (that's M35's job, confirmed
  out of scope here) — `_draw_docking_nav_aids` draws only the slip
  markers + lane, nothing zone-boundary-shaped.

---

## M35 — Zone boundary aid + local rules

Goal: see the boundary you're crossing and what it means. Render the zone, HUD
the crossing, and enforce/surface the first local rules via an extensible set.

### Scope

- **Boundary render:** the port-zone circle on the nav map, authority-colored,
  drawn under contacts. LOD-suppress when tiny (like the outline work).
- **Crossing HUD:** on M31's `zone_enter` / `zone_exit` events, a transient
  banner — "Entering IRONHOLD CONTROL — docking by permission · speed advisory
  200" / "Leaving IRONHOLD CONTROL". Reads the zone's `rules` for the summary
  line so it's data-driven.
- **Ruleset as data.** `port_zone.rules` is a dict; M35 implements two entries
  and the framework to add more:
  - `docking_permission_required: true` — already enforced by M32; here it's
    just surfaced in the banner.
  - `speed_advisory: 200.0` — surfaced as a **numeric readout on the helm
    velocity control** (`helm_panel.gd`'s velocity slider/gauge gains a current-
    speed number). While in-zone and over the limit the number goes amber
    (advisory) and, on entering the zone, the banner names the limit; under the
    limit or outside the zone it reads normal. **Warn only — no thrust clamp.**
    The numeric readout stays on all the time (a plain speed number is useful
    everywhere); the zone just drives the amber advisory state + the limit line.
  - Leave a clear seam (a `rule → handler` dispatch) so `weapons_safe`, a hard
    speed limit, toll/fees, etc. drop in later without touching the crossing/HUD
    code.

### Test plan (Fable) — `test_port_rules.gd`

1. **Boundary geometry:** the rendered ring radius == the zone radius; pure.
2. **Crossing banner state:** entering sets a banner naming the authority + the
   rules summary; leaving clears it (test the state the HUD reads, not pixels).
3. **Speed advisory logic:** in-zone AND over-limit → advisory active; under
   limit → inactive; outside the zone → inactive regardless of speed (pure
   truth-table over the rule handler).
4. **Extensibility:** an unknown rule key is ignored gracefully (no crash), and
   adding a second known rule composes into the banner summary.
Regression: M31 suite + `test_nav` + the outline/silhouette suites (nav-panel
draw changes must not disturb existing seams).

---

## M36 — Buoy-road travel corridor (nav aid)

Goal: see the road. The lit beacon-graph edges rendered as a travel corridor on
the nav map, with the player's active route highlighted — so following the road
between hubs is legible instead of dead reckoning between blips. Independent of
the permission chain; leans on the existing beacon graph + M17 NavComputer +
M34's `NavCorridor` helper.

### Scope

- **Road network render:** draw the cluster's `beacon_edges`
  (`scripts/cluster/cluster_def.gd`) as corridor segments — the polyline through
  consecutive beacons fed to `NavCorridor.corridor(...)` at a
  `ROAD_CORRIDOR_HALF_WIDTH`, drawn *under* contacts in a calm road color. **Lit
  vs dark:** an edge whose endpoints are within comms range (their lit zones
  overlap — the same rule `cluster_validator.gd` `road_lit` and `NavComputer`
  already use) draws solid; a dark/severed edge draws dashed or is dropped. Reuse
  that lit classification — do NOT reinvent it.
- **Active-route highlight:** when the player has an engaged `NavComputer` route
  (M17), draw the on-route segments brightly (the lane you're actually flying) —
  distinct from the ambient road network. The route is already an ordered
  waypoint list; feed it through the same `NavCorridor` helper.
- **LOD:** the road spans ~200k units; simplify/suppress when zoomed far out
  (draw centerlines only) or far in (cull off-screen segments), same LOD instinct
  as the outline work. No per-frame graph rebuild — cache the corridor geometry
  per cluster and only recompute the highlighted route on route change.

### Test plan (Fable) — `test_road_corridor.gd`

1. **Corridor geometry:** beacons along an edge → `NavCorridor` centerline
   connects them in order and the two edges are parallel at half-width. Pure
   fixtures (shared with M34's helper — this is the reuse proof).
2. **Lit vs dark classification:** an edge with endpoints within comms range
   classifies lit (solid); an over-long edge (a dark gap) classifies dark —
   assert it matches `cluster_validator`'s `road_lit` verdict on the same
   fixture, so the map and the validator can't disagree.
3. **Active-route highlight:** given a `NavComputer` route over a subset of
   edges, exactly those segments flag on-route; off-route road segments don't.
Regression: `test_nav` (routing intact), `test_static_landmarks` / cluster suite
(beacon graph untouched), nav-panel draw suites.

### Validation-phase extras (all six)

- Manual acceptance after M35: fly toward Ironhold — watch the boundary appear,
  cross it and get the "entering control" banner, hail port control, get a slip,
  follow the highlighted lane in, dock; then let a grant lapse (loiter past the
  timer / leave the zone) and confirm it clears with a "clearance lapsed" cue.
- Manual acceptance after M36: from Ironhold, pick Drift Market, and confirm the
  seven-beacon road draws as a corridor with the active route lit brighter —
  flyable by eye without the autopilot.
- Mark each milestone DONE with a Shipped note; commit per milestone; record
  friction (grant plumbing, dialogue-mutation wiring, tuning consts) in the DONE
  notes.
