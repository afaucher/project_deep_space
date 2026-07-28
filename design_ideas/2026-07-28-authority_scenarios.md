# Authority & enforcement — what the player actually sees

**Status: OBSERVATION ONLY. Nothing here is a decision.** Written 2026-07-28
from playtest reports that police action reads as confusing noise. Every "today"
entry was traced in code, not recalled. The "should" column is deliberately
absent — the overnight economy/pirate sims had not finished when this was
written, and this is tuning, not a known-correct behaviour we failed to build.

The prompting report: *"it's very confusing as a player when a station or patrol
is enforcing a police action"*, and the suspicion that patrol RESPONSE behaviour
had been conflated with what the PLAYER SEES.

That suspicion turned out to be half right, in a more useful way. The code does
not conflate them — there is a dedicated field, `authority_flags`, whose whole
job is that separation. It is simply **authored on patrols only** (see
`home_cluster.gd`'s `_patrol()`; stations, haulers and the player all default to
`[]` per `Ship.authority_flags`), and it is **never consulted on the gunfire
path at all**. So the exemption exists, almost nobody has it, and it does not
cover shooting.

---

## 1. How to read these: three fields, three different questions

Easy to blur, and they answer genuinely different things:

| Field | Question |
|---|---|
| `warrant_authority` | Whose warrants may I **act on** — and do mine count as official? |
| `authority_flags` | Whose demands do I **not resent**? |
| `known_enemy_flags` | Who do I hate **on sight**? (defaults to `[FLAG_PIRATE]`) |

`Standing.scoped_origin()` stamps a warrant with the issuer's flag only if that
flag is in the **issuer's own** `warrant_authority`; otherwise the origin is
`""`, and `Standing.warrant_enforceable_by()` makes a `""`-origin warrant
actionable by its issuer alone.

One property worth preserving deliberately: **the player's warrants are always
personal.** The player has no `warrant_authority`, so everything the player
files is origin-`""` — visible to others, actionable by nobody but the player.
Player grudges cannot deputize the cluster.

---

## 2. You are a bystander

| Scenario | What happens today |
|---|---|
| You are in port. A ship arrives flying the pirate flag; the station opens fire. | **Your ship files SUSTAINED_ASSAULT against the station on the 3rd hit, if you have not yet resolved the pirate as HOSTILE.** Never expires, HOSTILE, `RESPONSE_MAX`, `authorizes_force`. If you resolved the pirate first, nothing happens at all. See §5. |
| You are in port. The station demands **ID** of another ship. | One line in your engineering log. Nothing else — the witness rule fires only on STOP, because demanding *information* is never coercion (`comms_verbs.md`). |
| You are in port. The station demands a **STOP** of another ship. | You file ARMED_THREAT against the station. It turns yellow, moves from All Contacts to **Alerts** (adjacent to Enemies), on the map and helm dial too. 1800s, refreshed by every subsequent stop you witness. |
| A patrol stops a ship you already read as a pirate. | Nothing. The assistance exemption fires. |
| You watch an interdiction from outside comms range. | Nothing — the hail never reaches you. You may still watch it on sensors. |
| You watch several stops over half an hour. | The ARMED_THREAT warrant is re-posted under the same `event_key` each time, refreshing its timestamp. In a busy port the authority is **effectively permanently yellow**. |

## 3. You are the subject

| Scenario | What happens today |
|---|---|
| You are dark. A patrol demands you identify. | Banner on that patrol's row, ACKNOWLEDGE available. The patrol stays **grey** — IDENTIFY is not coercion. |
| You ignore it and stay in comms range. | After ~20s the patrol files NO_ID against you and (since 2026-07-27) never asks again. You are caution-tier *to them*; they remain grey *to you*. |
| You ignore it and leave comms range. | Challenge voided, no warrant. Silence we cannot hear is not evidence. |
| The patrol escalates to DEMAND(STOP). | **Now** you file ARMED_THREAT against it — yellow, Alerts. This is the first moment enforcement becomes visible to you as a threat. |
| You acknowledge. | Receipt only. Does not stop your ship. Sets the AI-side compliance grace. |
| You actually stop. | Banner reads "HELD — stopped for X". The honor rule means no leaf targets a compliant stopped ship. |
| You keep running. | Not much. Refusing a stop never escalates you to HOSTILE, and a patrol needs HOSTILE (plus the aggression cap) to fire. |
| You broadcast with Share Name off. | Caution-tier, reason "withholding name" (since 2026-07-27). Challengeable, and port control will refuse to berth you. |

## 4. Consequences

| Scenario | What happens today |
|---|---|
| You try to fire on a yellow patrol. | Refused — the console requires HOSTILE. You would have to MARK HOSTILE deliberately. |
| You try to fire on the station from §2 row 1. | **Allowed.** It is already HOSTILE to you. |
| A hauler witnesses the same police stop you did. | Same as you — haulers have no `authority_flags`. The whole civilian population reads its own police as caution-tier. |
| A patrol witnesses another home patrol's stop. | Nothing. Patrols are the one entity type that *does* carry `authority_flags: [FLAG_DRIFT]`. |

## 5. The pirate-in-port case, in detail

The sharpest report so far, and worth its own section because the failure is a
race with a permanent consequence.

`Ship`'s aggression-witness loop has an assistance exemption: skip the event if
the **victim's** track is already HOSTILE to us ("a patrol must not flip on the
player lawfully engaging a marked pirate"). For a transponding pirate that
exemption should always apply, since `known_enemy_flags` defaults to
`[FLAG_PIRATE]`.

It fails when the observer has not resolved the pirate **yet**:

1. The station resolves `JOLLY_ROGER` and opens fire immediately.
2. The player's own read depends on the pirate's transponder reaching *them*
   (datalink relay, per-ship phase offset) or their own sensors correlating it.
3. Every hit landing inside that gap is, from the player's point of view, their
   station shooting a stranger.
4. `STRAY_HITS_TO_HOSTILE` is **3**. A burst covers that easily.

Two properties turn a transient misread into a permanent state:

- `aggro_hits` **only ever increments** — no decay, no reset, for the life of
  the track.
- `SUSTAINED_ASSAULT` is `expires_after: -1` — **never expires** — and is
  HOSTILE-grade, `RESPONSE_MAX`, `authorizes_force: true`.

Net: the player's home station is red, permanently, filed under Enemies, and
the weapons console will now permit firing on it.

**The structural half:** `authority_flags` is read in exactly two places, both
on the DEMAND(STOP) branches. The aggression-witness loop never consults it. So
*"that is my own militia doing its job"* is **not expressible** when the
enforcement is gunfire rather than a hail. The only protection is winning the
relay race.

The police exemption was built for the *talking* half of enforcement and never
extended to the *shooting* half.

## 6. Jurisdiction — two authorities, one event

**There is no Meridian patrol today.** `home_cluster.gd`'s `_patrol()` hardcodes
`FLAG_DRIFT` into iff tags, flag, `authority_flags` and `warrant_authority`, and
only Patrol Alpha and Bravo exist. Meridian has three stations and two haulers —
economic presence, no enforcement hull. The rows below are what the machinery
*would* do the moment one is authored symmetrically
(`authority_flags: [MERIDIAN]`, `warrant_authority: [MERIDIAN]`).

| Both witness… | What happens |
|---|---|
| A pirate attacking a hauler | **Both act, independently.** Each files its own warrant under its own flag. Two official records for one event, neither enforceable by the other side. |
| The home patrol issuing DEMAND(STOP) | The Meridian patrol files ARMED_THREAT against the home patrol and reads it caution-tier — `SOVEREIGN_DRIFT` is not in its `authority_flags`. Symmetric in reverse. |
| The home patrol shooting a pirate | Nothing. Both read the pirate HOSTILE by default, so the assistance exemption covers it. |

| Scenario | What happens today |
|---|---|
| You file a warrant against anyone. | Origin `""` — yours alone to act on. Others may see it; nobody can enforce it. |
| A Meridian station files a warrant against you. | Enforceable by Meridian hulls only. Home patrols see it and cannot act. You read clean at home, wanted at Coldreach. |

**The loop this implies.** `InterdictLeaf` selects anyone the actor holds an
*enforceable* warrant against, with no guard for "the subject is itself an
authority". A Meridian patrol's ARMED_THREAT against a home patrol is
enforceable by Meridian — it posted it — so the Meridian patrol would move to
interdict the home patrol and DEMAND(STOP) at it, which makes the home patrol
file ARMED_THREAT right back.

Two police forces pulling each other over, indefinitely. It stays yellow
(`Engage` needs HOSTILE plus the aggression cap, so it cannot become a shooting
war unaided), but it is a stable loop consuming both patrols' attention — the
same class of self-driving feedback as the 2026-07-27 re-hail bug.

Worth noting: **no sim result about jurisdiction can be trusted until a Meridian
patrol exists**, because the seam is currently exercised only by stations that
never leave home.

---

## 7. Open questions — deliberately unanswered

- Should witnessing lawful enforcement affect the witness's standing toward the
  authority **at all**, or is the authority's own record the right carrier?
- If it should: is caution-tier the right weight, and is 1800s (refreshed) the
  right duration for something you see every few minutes in a working port?
- Should `authority_flags` cover gunfire, or does the shooting half want a
  different rule entirely (e.g. "an authority firing inside its own zone")?
- Should `aggro_hits` decay? Should SUSTAINED_ASSAULT be permanent when it was
  reached by attribution rather than by being shot at yourself?
- Who *should* carry `authority_flags` — everyone flying a flag whose authority
  they recognise? Is that a per-ship authored field, or derived from the flag?
- Should an authority be interdictable by another authority, or does rank/
  jurisdiction need to exist as a concept?
- Does the player ever get an authority flag, and if so how is it earned or lost?

## 8. What this document is not

It is not a plan, and the "today" column is not a bug list — several of these
behaviours may be exactly right, and the jurisdictional friction in §6 may be
desirable fiction rather than a defect. The one entry that looks unambiguously
wrong regardless of tuning is §5's permanent HOSTILE from a relay race, because
its consequence is unrecoverable and its cause is timing.
