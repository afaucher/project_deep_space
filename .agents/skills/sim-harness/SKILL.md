---
name: sim-harness
description: >
  Write, run and read the tactical/balance sims in tactical_analysis/sim_runners.
  Use when adding a new sim runner, changing an existing one, or interpreting a
  sim's CSV output. Covers the shared harness, the liveness contract that stops
  a broken sim reporting a confident wrong number, the four measurement
  conventions, and the failure modes that have each already cost real time.
---

# Sim Harness Skill

## These are instruments, not tests

A test asserts a known-correct answer and fails loudly when it breaks. A sim
**produces the numbers the game is balanced on** — haul throughput, catch
rates, frame budgets, per-station solvency. When a test breaks you get a red
line. When a sim breaks you get a plausible number that somebody acts on.

Every convention below exists because that already happened.

- **Key files**: `tactical_analysis/sim_runners/sim_harness.gd` (shared
  scaffolding), the runners beside it, results in
  `tactical_analysis/data/*.csv` (tracked on purpose).
- **Run**: `--run-tactical-sim <name>` (always with `--fixed-fps 60`).

---

## 1. Drive the cluster clock — use `SimHarness.Clock`

A `ClusterManager` in the scene tree ticks nothing unless `viewpoint_node` is a
live node, which no headless sim sets. **See CLAUDE.md's headless gotchas for
the full trap and the incident** — it is filed there rather than here because
it catches tests too, not just sims.

`SimHarness.Clock` owns the tick so no runner has to remember. Do not hand-roll
the loop.

## 2. Declare liveness, and report NO DATA rather than 0%

Every sim must name what has to be **non-zero** for its results to mean
anything — pirates spawned, deliveries made, contacts acquired, frames ticked
— and say so when it isn't met:

```gdscript
var live := SimHarness.liveness({
    "pirates spawned": guild.members.size(),
    "cycles resolved": resolved,
})
SimHarness.print_liveness(live)   # prints the NO DATA banner when dead
```

A `0%` and a `no data` look identical in a CSV and mean opposite things. The
liveness row is what separates "the mechanism ran and performed badly" from
"the mechanism never ran".

## 3. Four measurement conventions

**State budgets in TIME, never in ticks.** A tick count silently encodes
whatever cadence happened to be running. Four SOS assertions were pinned to
"within 1-2 ticks" — a contract phrased that way only because the datalink
relay happened to run every physics frame — and all four broke the moment it
didn't. The sharpest raced the per-frame sensor pipeline against
reconciliation. Derive budgets from the constant (`DATALINK_RELAY_HZ`), never
from a literal.

**Give discrete-event rates a long enough horizon.** Repair arrives as
occasional lumps, so one docking dent amortised over 30 sim-minutes reads as
catastrophic. Same code, same world, 30 vs 180 minutes: Refinery Prime's
REFINED self-repair went **−28.00 → −1.74 lots/hr**, and three of that run's
four worst verdicts evaporated. **180 sim-minutes is the shortest run whose
rates are worth quoting.** The tell is a magnitude far larger than any
authored rate. The converse also bites: short runs *under*-report chronic
problems, because cover-hours thresholds suppress a verdict until stock
actually draws down. Wrong in both directions, not merely noisy.

**Tally against AUTHORED rates, never measured ones.** A full bin blocks its
source, so a backed-up producer reads as a weak one. Measured cluster ORE
looked like −1.80/hr (a shortage) while authored supply was +1.5/hr healthy —
producers were pinned at capacity while the refinery starved. That is a
*distribution* failure wearing a *supply* failure's clothes, and reading the
measured column got the diagnosis exactly backwards.

**Label harness-compressed config distinctly from campaign-real config.** A
comparison harness may legitimately compress arrival windows or raise caps to
get a usable sample. Say so at the constant, say what still transfers (usually
ratios and splits, not absolute counts), and keep it identical across the arms
being compared.

## 4. Cheapest instrument that can answer the question

Never debug through a physics sim when arithmetic will do.

| Stage | Instrument | Answers | Cost |
|---|---|---|---|
| 0 | pen and paper | Does supply exceed demand? Does the tally close? | seconds |
| 1 | `economy_soak` | Does the mechanism run without erroring? | seconds for 30 game-days |
| 2 | a focused unit test | Is the geometry / selection / rule right? | ~12s |
| 3 | a full sim runner | Does it work with real hulls flying? | 20 min – 2 hr |

Stage 2 is easy to skip and shouldn't be: `test_pirate_targeting` screens hunt
geometry in seconds, leaving the expensive sim to answer only what geometry
can't — whether anything is actually caught.

**Know what your instrument cannot see.** `economy_soak` runs no ships, so
every consumer starves and every producer pins *regardless of how rates are
authored* — a well-margined cluster and a hopeless one produce identical
output. It validates mechanism, never balance.

## 5. Writing a new runner

```gdscript
const SimHarness = preload("res://tactical_analysis/sim_runners/sim_harness.gd")

func setup(main) -> void:
    my_director = MyDirector.new(CONFIG)
    manager = SimHarness.build_live_home_cluster(main, [my_director])
    SimHarness.spawn_planner_haulers(manager, NUM_HAULERS)
    clock = SimHarness.Clock.new(SETTLE_MINUTES, SIM_MINUTES)

func _physics_process(_delta: float) -> void:
    match clock.advance(manager):
        "measure_start": _zero_counters()   # discard the promotion transient
        "done": _finish()
```

- **Always keep a settle window.** Promotion produces a burst of collision
  damage and self-repair; sampled from frame zero it once reported a −0.15/hr
  sink as **−35.6/hr**. 3 minutes is ~1.5× the observed transient.
- **Append, don't overwrite** (`SimHarness.append_row`) so a parameter sweep
  builds one table across invocations. `store_line` buffers — the harness
  closes the file, because an unclosed CSV reads back as zero lines.
- **One arm per invocation** for sweeps. Rebuilding a live cluster mid-process
  risks static state bleeding between arms (`Standing`/`Hail` registries,
  steering's frame-scoped caches), and a contaminated comparison is worse than
  no comparison.
- **Derive the fleet's flags from the world.** An all-one-flag hauler fleet is
  categorically ineligible to lift eligibility-restricted commodities, and a
  sim that cannot carry the goods cannot answer its own question. This
  silently moved **zero** volatiles cluster-wide once.

## 6. Reading results

- Check the liveness line first. Then check measured against **authored**.
- Use attribution columns, never raw net flow: economy, guest repair, self
  repair and trade all move stock, and self-repair draws exactly the
  commodities an economy failure would drain — so a *navigation* problem is
  indistinguishable from an *economy* problem in a single column.
- `p95 == max` in a perf report means held monitor values dominated the tail;
  trust `TIME_PHYSICS_PROCESS` for "did a spike happen", never for averages.
- **A solo perf run right after a full gate is not trustworthy** — use the
  in-gate figure. When a number looks alarming, A/B it before believing the
  change caused it.
