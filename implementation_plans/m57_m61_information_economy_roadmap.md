# M57–M61 — The information economy

Where a decision is made, and what could physically have reached that place.

This roadmap turns the decisions in
[design_ideas/2026-08-01-patrol_director_and_reporting.md](../design_ideas/2026-08-01-patrol_director_and_reporting.md)
(§4c–§4f) into milestones. It is the **execution arm of the Mail Network
vertical** ([design_ideas/mail_network.md](../design_ideas/mail_network.md)),
not a competing direction — that doc's one-line principle, *"a director knows
only what has physically reached its location"*, is the whole thesis here.

The single design idea underneath all five milestones:

> Information is a physical object with a location. Every existing omniscience
> bug is the same bug — a decision reading a dictionary that its maker could not
> have travelled to.

---

## 0. Verified claims — the load-bearing facts this roadmap stands on

Everything below was checked against the tree on 2026-08-01, not recalled. Each
row is a claim the design depends on; if one stops being true, the milestone
resting on it needs rethinking, so they are written down to be re-checkable.

| # | Claim | Where | Verified |
|---|---|---|---|
| C1 | The cargo risk seam exists and is a deliberate stub: `_risk_estimate()` returns `0.0`, **one** call site | `route_planner.gd:295` (call), `:312` (def) | ✅ |
| C2 | Route re-planning happens **mid-flight**, from `actor.position`, against the **live cluster** | `route_planner_leaf.gd:81` | ✅ |
| C3 | Datalink relay is IFF-gated, mutual-range, LOS-gated, ~instant | `ship.gd:3914` `min(self_comms_range, their_comms_range)`, `:3915` range, `:3922` `_iff_tags_overlap`, `:2526` `DATALINK_RELAY_HZ := 15.0` | ✅ |
| C4 | Warrants already relay with monotonic merge (latest-wins, resolved-beats-open on tie) | `standing.gd:634` `merge_warrant` | ✅ |
| C5 | A personal-origin warrant (`origin_flag == ""`) **never** propagates — the civilian-report seal | `standing.gd:648–660` | ✅ |
| C6 | Warrant reads are O(1) per contact per fusion tick — why warrants must stay a *verdict* store | `standing.gd:173–181`, `warrant_index` | ✅ |
| C7 | A hunting pirate already observes prey+witness density at a known `lane_pos` from its **own** sensors | `job_steps.gd:915` `all_fresh_vessels` | ✅ |
| C8 | Two distinct hunt failures are already distinguished: *no prey here* vs *prey here, couldn't land it* | `job_steps.gd:891` (time budget) / `:898` (attempts) | ✅ |
| C9 | Pirate cash-out needs a 10s check-in inside an 8000u ring — crossed in ~11s at exit speed | `pirate_guild.gd:45` `policy_period`, `:52` `cashin_radius`, `:229` `vanished_near_wormhole` | ✅ |
| C10 | Guild learning is **global, no spatial axis** | `pirate_guild.gd:134–135` `profitless_streak` / `backoff_factor` | ✅ |
| C11 | `victim.looted` is **write-only** — set once, no reader outside tests | `job_steps.gd:1201` (sole write) | ✅ |
| C12 | *(corrected 2026-08-02)* `cargo_capacity` is **dead code** — assigned at `ship_design_validator.gd:162` and read by nothing, not even the validator that computes it (the next line tests `human_capacity`). The earlier wording "validation only" was too generous. Note the COMPONENT is fully live: it contributes mass via `ship.gd`'s `area * density` loop, plus health, collision and silhouette — so authoring a bay changes a hull's speed | `component_spec.gd:12`, `ship_design_validator.gd:162`, `ship.gd:1895` | ✅ |
| C13 | **The docking registry already lives on the station RECORD, not on a director**, and already survives promote/demote | `cluster_entity.gd:88` `docking_registry`; `test_registry_survives_demote.gd` | ✅ |
| C14 | The registry has **no consumer** — written on DOCKED, read only by its own tests | `docking_bay.gd:134–138` (write); readers: tests only | ✅ |
| C15 | `station_economy` walks all records **deliberately** — it is bookkeeping, not an observer | `station_economy.gd:75–79` + comment | ✅ |
| C16 | The mailbag model is already specified: `{source, version, confirmed_at}`, **both holder clocks merge as `max`**, order-independent and idempotent. Three clocks, not two — and the doc explicitly forbids collapsing `confirmed_at` into the log tail's entry stamp | `mail_network.md:128–168` | ✅ |
| C17 | "Content is global; **reads are clamped to your delivered version. That clamp IS the fog.**" Knowledge is a per-source **version vector of integers** — no content copying | `mail_network.md:117–123` | ✅ |
| C18 | The dock merge is **deliberately asymmetric** — *you receive freely, you give deliberately*; an automatic two-way merge would destroy the information economy | `mail_network.md:62–70` | ✅ |

**C13 is the most important row here.** "Put the map on the station, not the
director" is not new architecture to invent — the precedent is already built,
already on the `ClusterEntity` record, already tested against demotion, and its
own comment says it lives there because *"it would be unreadable exactly when
the mail fog needs it."* The incident log goes where the docking registry
already is. That collapses most of M57's risk.

**C14 is the cheapest win in the roadmap.** A signal is already being recorded
on every dock, at the right place, with the right lifetime, and nothing reads
it.

**Deliverable, M57:** `scripts/tests/test_information_assumptions.gd` pins the
rows this roadmap cannot survive losing — C1 (stub arity//call site), C3 (relay
gate shape), C5 (personal-origin seal), C6 (index lookup), C13 (registry lives
on the record). A future refactor that quietly moves the relay gate or
un-seals personal warrants should fail a test, not a playtest.

---

## M57 — Incidents: evidence as a thing with a place — **BUILT 2026-08-01**

**What it turned out to be.** M57 shrank twice against this plan, both times
because the thing it needed already existed. Recording that, because the same
surprise is likely in M58:

1. **The source-log substrate was already built, for one source.** The docking
   registry (M53b Pass 1b) already had a monotonic `registry_seq` *deliberately
   never rewound on trim* — "since that (not array length) is what makes a
   future 'do I have newer than you?' compare correct" — two clocks per entry
   with the frame stamp marked display-only, a `DOCKING_REGISTRY_CAP` with
   oldest-first eviction, plain serializable entries chosen so "a later pass can
   merge/serialize this across ships", and record-canonical storage with a
   single resolver. That is the whole mail model, written a milestone early and
   annotated with why. M57 extracted it to `scripts/mail/source_log.gd` and
   added a second user rather than designing anything.
2. **OVERDUE detection already existed.** `TrafficGuild._check_ins` →
   `_resolve_overdue` already notices its own haulers going quiet and stamps
   `overdue_since` once; `members` already carries `last_seen_pos`. The gap was
   never detection — it was that the conclusion became `losses += 1`, a
   scoreboard that says how many and never where. The change is emitting a
   positioned incident at the same point.

**Also worth keeping:** `Ship.record_incident()` needed **no special case** for
"a robbery happens in deep space where there is no station". The existing
`_resolve_cluster_record()` rule already does the right thing — a station writes
to its station record, a promoted hauler to its own record, a bare test ship
locally. The victim is a source, and a source always has somewhere to write.
That the resolver generalized untouched is the strongest evidence the pattern
was the right one.

Delivered:

- `scripts/mail/source_log.gd` — `append_entry` / `merge` / `has_news_for` /
  `high_water`. Merge is union-on-`seq`: idempotent, commutative, lossless.
- `scripts/mail/incident.gd` — kinds + `make()`. Kinds are deliberately NOT
  Standing's offense vocabulary: an offense is a legal judgement, a kind is what
  was observed, and `OVERDUE` is the case that proves it — nobody commits
  "overdue", a hull just stops reporting.
- `incident_log` / `incident_seq` on `ClusterEntity`; `record_incident()` /
  `get_incident_log()` / `get_incident_seq()` on `Ship`.
- Producers: robbery (victim-side, in `TAKE_ALONGSIDE`, naming the pirate off
  the victim's own transponder read so a cover identity records as the cover
  name), and OVERDUE (traffic guild, on its own log — it *concluded* this from
  its own members' silence, so it is honest with no transport built).
- `test_incident_log.gd` (28 assertions) and `test_information_assumptions.gd`
  (15) — the latter a **tripwire**: C1 failing is the *expected* signal when M59
  gives `_risk_estimate` a body, and the prompt to update §0 in the same commit.
- `record_docking_event` refactored onto `SourceLog`, behaviour identical,
  covered by the two pre-existing registry tests.

Deferred out of M57, deliberately: nothing consumes incidents yet. That is M59
(cargo + patrol) and M60 (pirate), exactly as the docking registry shipped one
milestone ahead of its own consumer.

### Original plan, as written before the above

Splits **verdict** from **evidence** (§4c) and gives evidence somewhere to live.

Warrants are NOT touched. They stay keyed, overwriting, O(1) (C6) — that shape
is correct for what reads them, and the overwrite is load-bearing.

- **Incident record**: `{id, kind, subject, pos, timestamp, reporter}` —
  immutable, one per occurrence, append-only, unioned by unique id (monotonic
  and order-independent, same property as C4's merge).
- **Lives on the `ClusterEntity` record**, beside `docking_registry` (C13). Not
  on a director — a map on a director is omniscience under a new name.
- **Bounded**: ring buffer or expiry. Not optional; an append-only log over a
  campaign is unbounded. Expiry half-life is also the damping term for the
  predator-prey oscillation in §4d, so it is a gameplay dial, not just hygiene.
- **OVERDUE detection in the traffic guild** — buildable *honestly today* with
  no transport, because haulers on authored lanes are the guild's own members.
  The only intelligence signal that survives a pirate killing the sole witness.
- **Wake the docking registry (C14)**: a consumer at last.
- Tests: union-merge is order-independent and idempotent; bound holds under
  flood; OVERDUE fires without a witness; `test_information_assumptions.gd`.

Ships with warrant semantics unchanged and every existing standing test green.

## M58 — Two tiers of transport — **BUILT 2026-08-01**

Delivered: `scripts/mail/mailbag.gd` (`{source_id -> {version, confirmed_at}}`,
`merge` / `sync_direct` / `deliver` / `read_incidents`); `mailbag` on
`ClusterEntity` with the usual `Ship` resolver + `source_id()`;
`Ship.exchange_mail_on_dock()` (receive freely, give own-flag-only) called from
DockingBay's DOCKED transition; `Ship.notarize_from()`; `test_mail_network.gd`
(36 assertions).

**Two scope calls, both deliberate.**

*Patrol check-in is deferred to M59.* The mechanism is already done — any dock
runs the exchange, a patrol's included — so what remains is purely *policy*:
patrols choosing to return to HQ on a schedule. That is a patrol-AI change and
belongs with the patrol director, not here.

*C2 stays open, as flagged above.* Nothing reads risk mid-flight yet.

**The bug worth remembering.** Adding `const Mailbag = preload(...)` to
`docking_bay.gd` re-entered the `ship.gd` ⇄ `docking_bay.gd` class cycle
(ship.gd already preloads DockingBay). It surfaces as `Could not resolve class
"Ship"` and **hangs the test rather than failing it** — the same
indistinguishable-from-a-timeout failure mode CLAUDE.md already records for a
different cause. The fix was better structure anyway: the mail *policy* moved
onto `Ship.exchange_mail_on_dock()`, and the bay just calls it. A docking bay is
a mechanism and should not hold faction policy.

**Also learned, cheaply:** the incident record gained a `signature` field during
this milestone. Without it `Standing.subject_key` falls back to the claimed name
alone, so a notarized warrant would be defeated by the pirate simply renaming
itself. The victim already observed the signature at robbery time — it just was
not being carried.

### Original plan, as written before the above

Implements §4f's rule, on the pipe that already exists (C3).

> News moves free and instantly between IFF kin in mutual comms range.
> Otherwise you must dock somewhere that holds it.

No middle tier — no trickle, no falloff. The binary is what makes distance mean
something.

- **Incidents as a third datalink payload**, beside contacts and warrants.
  Reuses the existing gate; no new range/LOS/crypto logic.
- **Notarization at the dock** — the missing half of C5. A civilian's sealed
  personal warrant is co-signed by an authority *on arrival*, becoming
  enforceable. Transport already exists; only the counter is missing.
- **Every ship carries a mailbag** — `{source, version, confirmed_at}` per source
  it has heard of, merged by `max` on both holder clocks (C16). A ship **only**
  advances on strictly newer data; it never wholesale-replaces what it knows.
  **Mid-flight re-plan reads the ship's own mailbag, not the live cluster** —
  this is what closes C2, and staleness arrives free, proportional to time out
  of touch.

  *(Supersedes an earlier "snapshot the station's map onto the job at dock"
  sketch, which was wrong in a specific way worth remembering: a wholesale
  snapshot means docking at a poorly-informed station ERASES what the ship
  knew — a hauler would forget the robbery it personally witnessed because it
  landed at a quiet outpost. `max` merge cannot do that. Snapshot also copies
  payloads per ship and cannot represent "I checked and nothing had changed".)*

- **Reads are clamped to your delivered version — that clamp IS the fog** (C17).
  Content stays global; a holder's knowledge is a **version vector of integers**.
  No per-ship content copies, no per-fact reconciliation, serializable and
  deterministic. This is the single most important implementation note in the
  milestone.
- **First-hand observation is just your own source advancing.** A ship is a
  source; witnessing an event increments the log it alone writes. "New
  information reaches you, or it happens to you" is then one mechanism, not two.
- **Honour the asymmetry: you receive freely, you give deliberately** (C18). An
  automatic two-way merge on dock would hand a port your fresher picture for
  free and destroy the information economy. Docking gets you the port's own logs
  *plus what it has heard* — contributing yours is a transaction.
- **The two tiers are the same operation.** Kin-relay and dock-merge differ only
  in *who* you may merge with and *how often*; both are per-source `max`. That
  collapses what §4f framed as two mechanisms into one.
- **Patrol check-in**: refresh at HQ; kin relay on station means a patrol *pair*
  syncs instantly while the pair as a whole stays stale.
- Tests: two stations disagree and stay disagreeing until a hull carries news
  between them; a ship out of range learns nothing; notarized report becomes
  enforceable, un-notarized does not.

### Transport and store are different layers (a false dilemma, retired)

An earlier draft of this section posed "warrants merge by `merge_warrant`,
incidents merge by union-on-seq — pick one" as an open decision. It is not one,
and the confusion is worth naming so it doesn't recur:

| Layer | Warrants | Incidents |
|---|---|---|
| **Store** — how a holder keeps it, and the conflict rule | keyed `(offense, subject)` dict; `merge_warrant` latest-wins | append-only log; union on `seq` |
| **Transport** — how it gets from A to B | radio relay to IFF kin (built, C3/C4) | **nothing yet** — that is this milestone |

These do not compete; they sit at different layers. A warrant arriving by
mailbag still lands in the warrant store under `merge_warrant`, and the O(1)
`warrant_index` (C6) is untouched either way. "Unify the transport" only ever
meant *don't build a second courier system*.

### What travels, and what is issued locally

The real question underneath was whether the **warrant** travels or only the
**incident**, with each authority issuing its own. Settled:

- **Incidents travel everywhere, to everyone.** They are evidence. A foreign
  hull's report of a robbery is useful to anyone routing through that lane.
- **Warrants travel among crypto-kin**, by radio today and by mailbag to kin out
  of radio range. Not because a verdict must propagate, but because a patrol in
  the field needs an O(1) "is this hull wanted" answer without carrying a case
  file.
- **Issuing** a warrant from an incident happens only at an authority, at its
  discretion, within its flag.

### Two gates on one arriving hull

The load-bearing distinction for the dock hook. A docking ship presents its
mailbag; the station applies **two different admission rules** to it:

| | Gate | Why |
|---|---|---|
| Record the **incident** | none — always | it is only information, and useful regardless of who carried it |
| Issue a **warrant** | the station's discretion, **own flag only** | this is an act of authority, not bookkeeping |

So a Meridian hauler limping into a Drift port gets its robbery filed — Drift's
own haulers start pricing that lane higher — and **no warrant issued**. The
world learns; Drift does not prosecute on Meridian's behalf.

This needs no new jurisdiction machinery. Jurisdiction here is already
personal/flag-scoped rather than territorial: `home_cluster.gd` describes "a
jurisdiction seam a home patrol's warrants can't reach and vice versa", pinned
by `test_jurisdiction_seam.gd`. A Drift station issuing a warrant only Drift can
enforce *is* that seam, reached through `scoped_origin` (C5).

### Phasing, and one honest scope correction

**Closing C2 is NOT part of this milestone, despite the bullet above.** The
mid-flight re-plan reads prices, which are a defensible market feed; the thing
that would make its omniscience harmful is the *risk* term, and
`_risk_estimate` is still an empty stub until M59. Building the mailbag read API
here and having M59 read risk *through it* achieves the same end without a
change to `RoutePlannerLeaf` that nothing yet justifies. Claiming C2 closed in
M58 would be claiming a fix for a problem that has not started happening.

- **M58a** — the `Mailbag` itself: `{source_id -> {version, confirmed_at}}`,
  merge = per-key `max` on both clocks. Stored on the record (same contract as
  the logs it indexes).
- **M58b** — the dock merge: the courier step. Receive freely; give by policy.
- **M58c** — the read API: resolve source_id → that source's log, clamped to the
  holder's delivered version. *That clamp is the fog* (C17).
- **M58d** — notarization: a station issues an own-flag warrant from a received
  incident.

## M59 — Risk-aware routing, and the patrol director — **BUILT 2026-08-02**

Delivered: `scripts/mail/risk_map.gd` (`lane_risk` / `hotspot`, shared);
`RoutePlanner._risk_estimate` given a body and `known_incidents` threaded
through `best_route`/`_score_pair`; `RoutePlannerLeaf` reading its own mailbag;
`scripts/ai/leaves/patrol_response_leaf.gd` wired into `build_patrol` ahead of
JobRunner; `test_risk_routing.gd` (7 sections). C1's tripwire updated in the
same commit, exactly as its header said it should be.

**The measurement that reshaped this milestone.** The open question was whether
a station's notarized warrant can reach a patrol. It can: patrol orbit is
`12000 * SCALE` = **24,000u**, and MediumStation and LightAttackCraft both carry
**30,000u** comms, so `link_range = min(both)` = 30,000u and a patrol on station
sits inside the relay. That does not solve the problem, it *relocates* it — the
patrol holds a valid warrant and never ENCOUNTERS the subject, because piracy
happens ~300,000u out on the lanes. **The warrant was never the missing piece;
a reason to leave the orbit was.** Hence a lane-response leaf rather than more
transport work.

**One map, two signs — literally one function.** `risk_map.gd` is consulted by
both sides (`lane_risk` subtracted from a route's payout, `hotspot` sought by a
patrol) specifically so they cannot drift apart. Two separate implementations
would eventually have a patrol sweeping somewhere cargo was never afraid of, and
the loop would stop closing without anything looking broken.

**Two choices worth not re-deriving:**

- *The sweep rides the `assignment` slot, never `default_job`.* JobRunner's
  two-slot model already means "an overriding mission pre-empts the standing
  duty, and the duty resumes". Overwriting `default_job` would destroy a
  patrol's authored route permanently — invisible in a test, ruinous an hour
  into a campaign.
- *The patrol is under the same fog as cargo.* It stays on station when it has
  heard nothing, even though the incident log is sitting right there on the
  record. Asserted, because "the director can see it" is exactly the failure
  this whole vertical exists to remove.

**The acceptance test is section [5]**, and it is the one that decides whether
risk-aware routing is a feature or a trap: identical danger, identical news,
only the destination's hunger changes — and the abandoned lane comes back.
Risk is priced, not absolute, so abandonment is not terminal.

*(Test-design note, since it cost a cycle: the first version of that test held
two assertions in tension — 2 incidents were required to beat a stock-10
destination's urgency while 3 had to lose to a stock-0 one, which are nearly the
same urgency. The constant was fine; the test was contradictory.)*

Still open, deliberately: nothing yet *verifies the three-way loop in motion*
(cargo flees → pirates follow → patrols follow → pirates leave → cargo returns).
That needs a long sim, not a unit test, and it is the natural first task of M60
once pirates have a positioned feed to react with.

### Original plan, as written before the above

The payoff milestone: the same map, read with opposite signs.

```
cargo_score  = payout - travel_cost - risk
patrol_score = go where cargo won't
```

- **`_risk_estimate()` gets a body** (C1) — one function, one call site, exactly
  as the stub's author intended. Cargo avoids dangerous lanes; because risk is
  subtracted from a payout, *avoid* and *price higher* are the same mechanism.
- **Patrol director** consuming the station inbox, then a **lane response job**.
- **Verify the self-correcting loop**: a lane cargo abandons should see its
  destination's urgency and payout rise until someone accepts the risk. Route
  abandonment must not be terminal. This is the milestone's real acceptance test.
- Sim: does the three-way loop (cargo flees → pirates follow → patrols follow →
  pirates leave → cargo returns) actually run, and at what period?

Explicitly NOT here: making patrols *good* at catching pirates. Tune enforcement
only once piracy functions, or you tune against a broken system.

## M60 — The pirate information economy

Closes the guild's learning loop and gives it a spatial axis (C10).

- **Fix cash-out (C9)** — filed as an accounting bug, but under this model it is
  an *information* failure: a pirate that never cashes out never delivers its
  positioned hunt outcome and never picks up a fresh map. This is the milestone's
  keystone, not a cleanup.
- **Positioned hunt outcomes** from the feed that already exists (C7, C8): prey
  density, witness density, and the two distinct failure modes, all from the
  pirate's own sensors at a known `lane_pos`. The guild stops needing to be told
  where traffic is.
- **Per-lane backoff** replacing the global `profitless_streak` — "that lane is
  finished, try the other one" instead of "the guild is discouraged".
- **Dens as infrastructure**: multiple dens = fresher news + shorter exfil.
  Buildable, losable, raidable.
- **Port control logs (M60d)** — a station's `docking_registry` is a versioned
  `SourceLog` with no consumer, and two ports' logs CORRELATE into a lane: the
  same hull at Ironhold then Drift Market IS that lane. Read by docking under a
  cover identity, which makes the finite identity kit an economic asset (D17,
  D20) and gives patrols a counter they already have (docking denial for NO_ID).
  Institutional intelligence, complementing the field intelligence above. Full
  slice in `m60d_port_control_logs.md`.
- **Loot the mailbag** — the snapshot M58 puts in a hauler's job is cargo, and
  `TAKE_ALONGSIDE` can take it. Gives pirates an opportunistic feed that is
  earned rather than granted; stolen news is stale and route-biased, so it is
  honest by construction; and it makes the *well-connected* hauler the valuable
  target. Note this needs no cargo manifest, so it does **not** wait on M55.

## M61 — Competing bands under one flag

Mostly a content and decision milestone: the isolation already works.

`iff_tags` is a set; the transponder flag is separate and public. Two crews
flying `FLAG_PIRATE` with disjoint tags **already cannot relay** (C3) — today's
single-band setup is the special case, not the default.

- Multiple bands: same colours, same lanes, no shared news, separate dens,
  indistinguishable from outside.
- **Decide: do rival bands read each other as hostile?** Without tag overlap they
  fall through to flag classification and both read `FLAG_PIRATE`. HOSTILE (bands
  fight) vs merely not-friendly is a real design choice with real consequences.
- **Decide: is stolen news attributable?** If it carries the victim's identity,
  holding it is *evidence* — a captured pirate's data becomes prosecutable, and
  patrols gain a reason to board rather than destroy.
- The same mechanism already explains Home vs Meridian patrols holding different
  beliefs about one event (§3, and `2026-07-28-authority_scenarios.md`). One
  rule, both cases — worth asserting in a test so it stays one rule.

---

## Updates to existing plans

- **`m48_m55_economy_piracy_roadmap.md` → "The Mail Network"**: point at this
  roadmap as the phased execution. The registry-first instinct is vindicated by
  C13/C14 — it is already on the record and already has no consumer.
- **M55 (physical cargo)**: add that the *mailbag* is loot too, and that it does
  not depend on manifests, so M60's loot-the-news lands earlier than M55.
- **`m52b_warrants.md`**: record that warrants stay a verdict store deliberately
  (C6), and that incidents are a **separate** record — the rejected alternative
  (position + counter on the warrant) is documented in §4c with its reason.
- **`m51_pirate_guild_design.md`**: the omniscience objection has a concrete
  honest feed now (C7/C8) — note it rather than leaving the objection open.
- **`m53c_demand_routing.md`**: C2 is a known limitation, closed by M58's
  snapshot; the `_risk_estimate` stub gets its body in M59.

## Order and risk

M57 is cheap and low-risk — C13 means the storage question is already answered,
and it ships a signal (OVERDUE) that needs no transport at all. M58 is the widest
blast radius: it changes what every planning decision can see, and the snapshot
change to C2 will move existing sim numbers, so expect to re-baseline. M59 is the
payoff and the first milestone a player would notice. M60 is self-contained and
could run in parallel with M59 — different files, different director. M61 is
content on top of a mechanism that already works.

Cut line: M57+M58 alone retire the omniscience objection and make the world
honest. Everything after that is making the honesty produce behaviour.
