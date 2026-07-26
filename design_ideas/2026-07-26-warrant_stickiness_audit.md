# Warrant stickiness — what M52b intended vs what the code does

Audit written 2026-07-26, triggered by a bug found while decimating the
datalink relay: a warrant became permanently unenforceable because the
observer learned the subject's name *after* posting it. That turned out to be
one symptom of a broader question — **how sticky is a warrant, actually?** —
so this walks the whole mechanism against [warrants.md](warrants.md).

**Verdict up front: the core model matches the intent. Standing really is
derived, not stored, and "enemy forever" really is retired.** Four things do
not match, one of which is a live gameplay hole, one of which is a hazard I
introduced and then fixed while writing this, and two of which are
unimplemented rather than wrong.

---

## What "stickiness" means here, precisely

There are **four** independent lifetimes in play, and conflating them is what
makes this hard to reason about. Ranked by how long they actually hold:

| # | Mechanism | Where it lives | How it ends |
|---|---|---|---|
| 1 | The **warrant record** | `Ship.warrants`, per observer | `expires` clock, or status → RESOLVED |
| 2 | The **warrant index** | `Ship.warrant_index` | Rebuilt from scratch every fusion tick |
| 3 | The **standing cache** | `contact["standing"]` | Overwritten on the next recompute |
| 4 | The **wanted registry** | `Standing.wanted_names`, process-global | `Standing.reset()` only — i.e. never, in play |

Only #1 is the designed source of truth. #2 is a derived index and correctly
disposable. #3 is a cache with one deliberate exception (below). #4 should not
exist any more.

---

## What matches the intent

**Standing is genuinely derived.** `compute_standing()` runs a five-rule
cascade — IFF overlap → warrant lookup → known-enemy flag → transponder
present → nothing received — and rule 2 is a plain `warrant_index` lookup.
There is no sticky HOSTILE bit left. Retiring it was migration step 3 in the
doc, and it landed.

**Proportionality landed as data, not a state machine.** `_OFFENSE_TABLE`
carries `response` and `expires_after` per offense, exactly the doc's
taxonomy. The expiry values transcribe faithfully: ASSAULT 60s ("short —
presumptively an accident"), ARMED_THREAT 1800s ("~30min"),
SUSTAINED_ASSAULT and ARMED_ROBBERY never.

**The issuing/enforcement gate is one gate.** `scoped_origin()` decides
whether a warrant carries a flag at issue time, `warrant_enforceable_by()`
decides whether a reader may act on it, and both consult
`warrant_authority`. The doc's "one grant covers both halves" is real.

**`build_warrant_index()` filters before the hot path**, so the per-contact
colour lookup stayed O(1) — the doc's "cheap per-contact colour lookup
survives unchanged" promise held.

**The eager HOSTILE stamp is a documented cache prime, not a relapse.**
`take_damage()` writes `atk_c["standing"] = HOSTILE` directly, which looks
like the sticky bit returning. It is not: `compute_standing` only re-runs when
a sensor bin updates that track, so without the stamp the flip would not be
visible until the next sweep. The warrant remains the source of truth and the
next recompute re-derives from it. **But see mismatch 1 — this stamp is
exactly what made the keying bug survivable long enough to be confusing.**

---

## Mismatch 1 — a warrant can become permanently unreachable *(was live; fixed)*

`subject_key()` files under `"name:<claimed>"` when a transponder name is
known and `"sig:<tags>|<cross_section>"` when it is not. Posting and lookup
read that name at **different moments**, and nothing forces them to agree.

The doc anticipated the ambiguity:

> Needs care for claimed-name vs signature identity (two observers may know
> the subject by different handles); v1 rule: key on claimed transponder name
> when present, else on track-signature match, and accept occasional
> duplicates over false merges.

**It budgeted for duplicate records. The actual failure is the opposite
shape: the SAME record becomes unreachable**, because the lookup asks for a
key nobody filed it under. The warrant is still in the index, unexpired and
enforceable, and no code path can ever find it again.

In gameplay terms: **fire while dark, then light your transponder, and the
victim's assault warrant against you stops applying.** Turning a transponder
*on* laundered an assault. That is squarely the "enemy forever" family of
bug the warrant model exists to prevent, running in reverse.

Found because the relay decimation widened the window from one frame to six:
`take_damage()` posted ASSAULT with an empty name because
`active_transponders` had not been populated yet, and the next recompute —
now holding the name — missed and overwrote the eager stamp with NEUTRAL. A
patrol then had no hostile contact and never interdicted.

**Fixed** in `compute_standing`: when the `name:` lookup misses, fall back to
the `sig:` key. Deliberately one-directional — see mismatch 2.

## Mismatch 2 — that fix nearly destroyed NO_ID *(caught in this audit)*

The fix above is wrong for exactly one offense, and it is the most common one.

`NO_ID` is filed under `sig:` **by definition** — the subject was not
reporting a name; that IS the offense. And the doc's resolution story for it
is:

> it resolves itself the moment the subject reports a transponder —
> `compute_standing` already flips them off `UNREPORTED` on its own, so
> there's no separate revocation path to build for it.

**The mechanism delivering that promise was the keying gap itself.** The
`name:` lookup missed the `sig:`-keyed NO_ID record, so the subject fell
through to NEUTRAL. An unconditional signature fallback would have converted
the cluster's most forgivable offense into a permanent HOSTILE brand with no
clock and no revocation path — worse than the bug being fixed.

This is worth dwelling on: **a designed behaviour was resting on an
accident.** Nothing in the code said "NO_ID self-resolves"; it emerged from
key-shape mismatch, and no test covered it, so the gate stayed green while I
broke it.

Now explicit: `_OFFENSE_TABLE` carries `self_resolves_on_id: true` for NO_ID
only, `Standing.self_resolves_on_id()` exposes it, and the signature fallback
skips those offenses. Covered by `test_warrant_identity_change.gd`, which
pins all three directions: assault survives squawking, NO_ID resolves on
squawking, and a name-keyed warrant is still unreachable by signature (going
dark still works, which is the designed UNREPORTED rule).

## Mismatch 3 — `wanted_names` is a global that is written but never read

`Standing.wanted_names` is `static var` process state: faction tag → set of
claimed names. `add_wanted()` is called from three places (`take_damage`, and
twice in the relay's standing share). **`is_wanted()` has zero call sites
outside its own definition.**

`compute_standing`'s own comment says the registry is "the PATROL's own
assessment... `is_wanted` is called by the patrol tree (M52), not by this
classifier." It is not called by the patrol tree either.

So it is dead state today — but it is a loaded one, for two reasons:

1. **It is ambient global truth**, precisely what the doc set out to replace:
   *"This gives the standing-replication machinery a fiction that explains who
   shares what with whom, instead of an ambient global truth."* A name added
   by any ship is visible to every ship sharing that faction tag, with no
   comms link, no line of sight, and no authority check. Everything the
   warrant model is careful about, this bypasses.
2. **It never clears.** No expiry, no resolution, no per-observer scoping.
   The one genuinely "enemy forever" structure left in the codebase.

Recommendation: **delete it, or wire it deliberately.** Leaving a global
hostility set that anything could start reading is the riskier option, and
the cost of deleting it is three `add_wanted` call sites.

## Mismatch 4 — revocation exists for exactly one offense

The doc's revocation story is an authority action:

> get arrested, pay the fine → the arresting authority sets status=RESOLVED
> with a fresh timestamp.

`Standing.resolve_warrant()` and `Ship.resolve_warrant_for()` both exist and
implement latest-timestamp-wins correctly. But the only caller is the
player's own un-MARK, resolving `OPERATOR_FLAGGED`. **No station, patrol, or
authority ever resolves anything.** So in play, every non-OPERATOR_FLAGGED
warrant ends only by its `expires` clock — or never, for
SUSTAINED_ASSAULT/ARMED_ROBBERY/NO_ID.

Practical consequence: `SUSTAINED_ASSAULT` and `ARMED_ROBBERY` are, today,
permanent and unclearable by any means. That is the doc's intent for the
*record* ("robbery never" expires), but the doc paired it with a revocation
path that would let a player settle it. Half the design shipped, and the half
that shipped is the punitive half.

## Also unimplemented (correctly flagged, just noting the state)

`SPEED_VIOLATION` has a constant and a table row and **no posting call
site**. Consistent with
[port_zones_and_channels.md](port_zones_and_channels.md)'s own status note
that the published-limit rule is "specified and unbuilt".

---

## What I would do next, in order

1. **Decide `wanted_names`' fate.** Deleting it is three call sites and
   removes the last ambient-global hostility structure. Keeping it means
   deciding who may read it and under what authority.
2. **Give an authority a way to resolve a warrant.** Without it, the model's
   forgiveness half is theoretical, and ARMED_ROBBERY is a life sentence.
3. **Write the self-resolution property down per offense** rather than
   letting it emerge. `self_resolves_on_id` is now one flag on one offense;
   if any other offense should end on a state change rather than a clock,
   it belongs in the same table.

## The general lesson

Two of the four mismatches share a root cause: **a designed behaviour was
resting on an implementation accident, with no test pinning it.** NO_ID's
self-resolution came from key-shape mismatch, and the assault-warrant
survival came from posting and lookup happening to read `active_transponders`
one frame apart. Both held for as long as the timing happened to hold, and
both changed the moment an unrelated perf change touched the relay's cadence.

Where a doc says a thing resolves itself, the code should say *why*, and a
test should hold it.
