# M60d — Port control logs as pirate intelligence

> **This is a SLICE OF M60, not a new milestone.** `m57_m61_information_economy_roadmap.md`
> already defines M60 "The pirate information economy" with the same consumer —
> the guild learning where traffic is instead of being told. I wrote this as a
> standalone M63 before re-reading that section; the number is retired and the
> content folded in here.
>
> **What M60 already covers:** positioned hunt outcomes from the pirate's own
> sensors at a known `lane_pos`, per-lane backoff replacing the global
> `profitless_streak`, dens as infrastructure, loot-the-mailbag, and fixing
> cash-out as the keystone (a pirate that never cashes out never delivers its
> map — note the cash-out latch was fixed 2026-08-02).
>
> **What is genuinely new here:** the SOURCE. M60's channels are FIELD
> intelligence — what a pirate saw with its own sensors, or took off a victim.
> A port's arrival registry is INSTITUTIONAL intelligence, acquired by docking
> under a cover identity, and it is the one that makes the finite identity kit
> an economic asset rather than pure concealment.

## Why

Criterion (1) — *"takes and incidents surface reliably enough to trust in a long
run"* — is the single blocker on the three-systems goal, and it fails at the
ENCOUNTER stage. Pirates mostly go out and find nobody.

The arithmetic says they should not:

```
bounds                     1,000,000 x 1,000,000  = 1e12 u^2
pirate passive_em radius   45,000                 (armed_pinnace.gd)
hauler cruise              ~700 u/s
14 haulers, 900s hunt
rate = 2*r*v*N / A = 8.8e-4 /s   ->   P(sighting per hunt) ~ 0.79
```

Measured across the LANE_RUN A/B: **163 hunts found nobody, 3 found prey** —
under 2% where the model says 79%. A 40x miss is a wrong assumption, not a
tuning gap.

**The suspect assumption is uniformity.** Cargo does not fill the box; it flies
the lanes that pay. The pirate guild picks lanes from *public geometry only*.

## What the pirate can see today (verified, with sources)

| Claim | Source |
|---|---|
| Default targeting is `CROSSROADS` — sample random hub chords, keep the point where the most chords converge | `pirate_guild.gd` `hunt_strategy`, `_pick_hunt_point` |
| That score counts **station-pair LINES near a point**, not traffic | `pirate_guild.gd:804` `_chord_carriers` |
| The guild is constrained to members' nodes + "the records array's public geometry" | `pirate_guild.gd` header, the director honesty rule |
| Pirates already carry mailbags and already relay to each other | relay gate is `_iff_tags_overlap(iff_tags, s.iff_tags)` — **no flag/faction check** |
| Guild members share a crypto tag | `pirate_guild.gd:402` — `["PIRATE_GUILD", "PIRATE_GUILD_<record_id>"]` |
| Ports already keep a versioned arrival log with **no consumer** | `cluster_entity.gd:88` `docking_registry` / `registry_seq`; `ship.gd:1230` `record_docking_event` |
| Registry entries are `SourceLog` rows, same primitive as incidents | `ship.gd:1238`, cap `DOCKING_REGISTRY_CAP = 200` |

**So the transport is already built and running.** Two pirates in mutual comms
range with LOS relay mailbags today, exactly as patrols do — this milestone adds
no transport. The per-record `PIRATE_GUILD_<id>` tag also means rival bands can
be split into separate crypto sets under one FLAG_PIRATE, and they simply will
not share (D18).

What is missing is a *signal* and a *consumer*.

## The idea

**Port control logs are the economic signal the guild lacks, and they are
obtainable through a channel that respects the honesty rule.**

A single port's log says who visited, not where they went. **Two** ports' logs
correlate: the same hull at Ironhold and then Drift Market IS the
Ironhold↔Drift lane. Traffic volume falls out of the intersection — so the
intelligence is *compositional*, and a guild that has worked more ports hunts
better.

To read a port's board you must DOCK, and a pirate docks under a **cover
identity** — machinery that already exists, with a finite `identity_kit_size`
(default 3).

**DOCKING DOES NOT SPEND A PAPER.** A clean name docks as often as you like;
what BURNS a name is a WARRANT issued against it. So the cost sits on the
robbery, not on the intelligence run:

| how you rob | name cost | other cost |
|---|---|---|
| under **pirate colours** | none — no cover name is involved | HOSTILE on sight to everything in transponder range |
| under a **cover name** | that name is notarized into a warrant → burned | none until the news travels |
| **dark** (`NAME_WITHHELD`) | none — D7 refuses to notarize an unidentified subject | victims take you less seriously (`RUN_SPEED_RATIO_PIRATE_FLAG` 1.6 vs 1.3) |

That makes papers an economic asset rather than pure concealment (D17, D20
become load-bearing): the kit is not a budget of DOCKS, it is a budget of
IDENTITIES YOU MAY GET CAUGHT UNDER.

**Patrols already hold the counter**: docking denial for NO_ID hulls exists.
Deny the dock, deny the intelligence.

## Why this is not the omniscience mistake

M62 caught OVERDUE detection about to ship as an instant cluster-wide channel.
This is the opposite shape, and each property is load-bearing:

- **Earned** — you only know ports you (or a kin you met in radio range) visited.
- **Stale** — clamped to your delivered version, the same fog as incidents.
- **Partial** — no global view exists anywhere, including on the director.

The guild still reads only its members and public geometry. Its members simply
know more than they used to, because they went and looked.

## Scope (slices within M60)

- **M60d-1 — registry as a mail source.** `Mailbag.read_registry(cluster, bag)`,
  the sibling of `read_incidents`, clamped to delivered version. No new
  transport: `registry_seq` is already monotonic and `SourceLog`-shaped.
- **M60d-2 — docking syncs it.** `exchange_mail_on_dock` already merges version
  vectors; confirm the registry rides along once it is a versioned source.
  **Check the give-rule** (currently "same flag gives") so a cover-identity
  pirate does not hand a port its own intelligence back — the asymmetry is
  "receive freely, give deliberately" (D5) and a cover identity makes the giving
  side ambiguous in a way it has never been before.
- **M60d-3 — kin relay carries it.** Should fall out of M63a for free, since the
  relay merges whole mailbags. Assert it rather than assume it — that is exactly
  how M58's tier-1 shipped broken.
- **M60d-4 — the consumer.** Replace/augment `_chord_carriers` with a lane score
  derived from correlated registry sightings. Keep the geometric score as the
  fallback for a guild that has learned nothing yet, so a fresh campaign still
  functions.
- **M60d-5 — cash-out aggregation.** M60 already names this as its keystone;
  registry data is simply more cargo for that same channel. A returning member
  hands the guild what it saw. This also makes `returned_empty` productive: a hunt that took nothing
  still came back with port intelligence, which changes what the profitability
  governor is measuring.

## Measurement

`LaneProbe` (built 2026-08-03) is the instrument and already reports:

```
overlap    = sum  cargo_share(L) * pirate_share(L)
ceiling    = sum  cargo_share(L)^2            (if pirates matched cargo exactly)
efficiency = overlap / ceiling
```

**Acceptance: `efficiency` rises materially, on seed-matched pairs, with the
lane table showing pirate share moving onto the lanes cargo actually uses.**
Encounter rate and takes are downstream consequences to watch, not the primary
measure — the whole lesson of D38 was that measuring the end of a funnel and
calling it a property of the middle produces a wrong verdict.

## What would falsify the premise — check FIRST

**If `efficiency` already reads near 1.0, this slice is solving a problem that
does not exist**, and the encounter gap lies elsewhere (prey density,
detection radius, hunt duration, or lane length). Run the lane table before
building any of M63.

Prey density is a live alternative hypothesis and is cheap to test
independently: real prey is ~14 authored haulers plus `freighter_target: 2`
transients — about **16 moving cargo hulls** across 300,000-410,000u lanes. More
cargo is a one-variable experiment (`NUM_HAULERS`) that needs no new code.

## Interacts with

- **D17 / D20** — the identity kit becomes an economic asset; kit size becomes a
  real dial on how much intelligence a band can gather.
- **D18** — rival bands under one flag: separate crypto sets already do not
  share, so competing intelligence networks fall out.
- **D36** — cargo's mirror of this. Postings are globally readable, which is why
  urgent routes are never risked; both sides need the same fog for the loop to
  bite. **The mail network is the missing input for all three systems.**
- **D37 / M58** — going dark already defeats notarization; here it would defeat
  docking, so concealment costs intelligence on both sides of the law.
- **M62** — shares the "docking_registry is the missing reader" observation, for
  a different consumer.

---

## The better variant: PREDICT the lane instead of reconstructing it (2026-08-03)

Registry correlation is RETROSPECTIVE — it reconstructs where cargo went from
who docked where. A pirate can instead run the SAME economic reasoning cargo
runs and predict where cargo is about to go.

`RoutePlanner.best_route(cluster, from_pos, ship_flag, known_incidents)` is
static and already takes a FLAG. A pirate calls it with its COVER flag and gets
the lane a hauler of that flag would choose. `StationEconomy.get_posting` already
filters on `asker_flag`, so the cover identity decides what the pirate can see.
The predator reasons with the same function as the prey.

Why it beats registry correlation:

| | registry (M60d) | posting prediction |
|---|---|---|
| direction | retrospective — where cargo WENT | forward — where cargo WILL go |
| ports needed | TWO, to correlate a hull across them | ONE; a posting pair already implies a lane |
| new logic | correlation across logs | none — reuse `best_route` |
| staleness | inherent | inherent |

**HARD DEPENDENCY: M64 (price fog) MUST land first.** Postings are globally
readable today, so a pirate consulting them would be omniscient — the exact
failure M62 caught before it shipped. After M64 the pirate's economic picture is
clamped to its delivered version like everything else, and the honesty falls out
with no extra machinery.

**Risk to design for: this could work TOO well.** Pirate and cargo running the
identical argmax means every pirate sits on the single best lane, and multiple
pirates stack on the same one. A predator exactly as smart as its prey and never
wrong is not a predator, it is a tollbooth.

**Resolved by the pattern this codebase already uses twice: a WEIGHTED DRAW over
scored candidates instead of argmax.**

D24 records the identical failure on the patrol side — deterministic argmax made
a patrol lock onto one report and re-sweep the same point for its whole ~52
minute actionable life (52 sweeps off 2 incidents in one seed). The fix was one
weighted draw, and `RiskMap.pick_weighted` plus `PatrolResponseLeaf`'s candidate
list are both already built on it. Same reasoning applies here:

* it KEEPS the intent — a richer lane is chosen more often;
* it lets attention move as the picture ages, with no "this lane is stale" rule;
* **it makes two pirates diverge naturally** instead of both converging on the
  same coordinates, which is precisely the stacking problem above;
* it uses the global seeded RNG, so runs stay reproducible.

Small refactor this implies: `best_route` currently keeps only the argmax and
discards the scored list. Split out the scoring pass (`scored_routes()`), let
`best_route` be the argmax over it — unchanged for cargo — and let the pirate
draw weighted from the same list. One scoring rule, two selection policies, and
the difference between predator and prey becomes a POLICY rather than a separate
model of the world.

Note the weights should be over the pirate's HEARD picture (post-M64), so a
stale board naturally produces a stale-but-plausible choice.

**The staleness IS the gameplay.** A pirate acts on the price picture from its
last dock; cargo may have a fresher one and already moved on. The pirate sits
where the lane WAS good, which is a far better fiction than either omniscience
or blind geometry.

**Ordering:** M64 -> posting prediction. Registry correlation stays as a
complement (ground truth about who actually flew, useful for confirming a
prediction) but is no longer the primary plan.

## Weights are a PRIOR that outcomes update (2026-08-03)

The economic prediction is a guess about where cargo will be. What actually
happened on that lane is evidence, so the weight should move with it:

* a **take** on a lane raises its weight;
* **returning empty** from a lane lowers it.

M60 already specifies the second half — *"per-lane backoff replacing the global
`profitless_streak`: that lane is finished, try the other one, instead of the
guild is discouraged"*. This is that, with an economic prior in front of it and
a weighted draw behind it:

```
prior      = predicted richness from the HEARD board (post-M64)
posterior  = prior x learned per-lane multiplier (takes up, empties down)
selection  = weighted draw over posterior, never argmax
```

**This makes `returned_empty` productive.** It has been the dominant pirate
outcome all along (5-15 per run against 0-3 takes) and has meant nothing except
"discouraged". Under this it is a measurement: the lane was worse than the board
suggested. A hunt that takes nothing still comes home with information.

**It also fixes stacking without a rule for stacking.** Two pirates on one lane
means at least one returns empty, which lowers the weight, which spreads the
next draw. No coordination and no "reserve a lane" mechanic.

**And it is where the predator-prey oscillation finally comes from** — emergent
rather than scripted:

> pirates concentrate on a rich lane -> takes generate incidents -> couriers
> carry them -> cargo diverts (D36 measured this: 460-1614 decisions) -> pirates
> start returning empty -> per-lane weight decays -> pirates move on -> the lane
> quiets -> risk decays on `RISK_HALF_LIFE_FRAMES` -> cargo returns.

Every one of those links now exists or is planned, and the damping term is the
per-lane decay rather than anything hand-tuned. `RiskMap.RISK_HALF_LIFE_FRAMES`
sets how fast cargo forgets; the per-lane multiplier's decay sets how fast
pirates forget. **Those two constants are the oscillation's period**, which is a
far better dial than `hunt_seconds` (D20).

Open: the learning rate and whether the multiplier is per-BAND or per-guild.
Per-band composes with D18/M61 (rival crews under one flag would learn
separately, and a lane one band has worked out is not knowledge the other has),
which is the more interesting answer but needs the band split to exist first.

## The missing enforcement: a burned name must actually be refused (2026-08-03)

**Verified gap: `port_rules.gd` contains no warrant, standing or flag check at
all.** Docking permission is purely procedural — approach geometry and bay
availability. A notorious, warranted pirate can dock anywhere in the cluster
today, so "burning" an identity currently costs nothing.

Adding the check produces something better than a global burn:

**A NAME IS BURNED PORT BY PORT, AS THE NEWS REACHES EACH PORT.**

```
rob under a cover name -> victim records the incident -> courier carries it
  -> an own-flag station notarizes a warrant (D29) -> THAT station refuses
     that name from then on
  -> ports that have not heard still accept it
```

So a pirate keeps docking at Coldreach while Ironhold has already closed its
doors, and the frontier of "where am I still welcome" moves at courier speed.
It needs **no new state**: the same warrant, the same fog, the same clamped
read that M58 and D29 already built. The station consults `warrant_index` for
the claimed name at permission time — the same `Standing.subject_key` lookup
InterdictLeaf and AcquireTargetLeaf already use, so it cannot drift from them.

Two properties worth keeping:

* **Going dark still defeats it** (D7/D37) — an unidentified hull cannot be
  notarized, so it cannot be name-refused. Concealment keeps working, and keeps
  costing you the ability to be taken seriously.
* **The pirate must TRACK which ports still admit it**, which is exactly the
  sort of decaying, partial knowledge this network exists to hold. A guild that
  has not heard its own name is burned will fly into a refusal.

Sequencing note: this is what gives the identity economy teeth, and it is
independent of the targeting work — it can land before or after M64.
