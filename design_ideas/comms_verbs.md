# Comms verbs: why "surrender" is not on the wire

Design for M49's hail protocol (see
[m48_m55_economy_piracy_roadmap.md](../implementation_plans/m48_m55_economy_piracy_roadmap.md)).
Structured machine-to-machine comms verbs — comms-range-gated, riding the
existing transient_events/comms plumbing, NOT dialogue trees. This doc records
the differential that collapsed the original verb list (CHALLENGE,
DEMAND_SURRENDER, COMPLY, SOS) into the smaller set below, because the
reasoning is the spec: it says exactly what each message may and may not carry.

## The differential

The original list had CHALLENGE and DEMAND_SURRENDER as separate verbs. Run
every axis on which they might differ:

| Candidate difference | CHALLENGE | DEMAND_SURRENDER | Survives? |
|---|---|---|---|
| What's demanded | identify yourself | stop, submit | **Yes — but it's a parameter, not a verb** |
| Who may issue it | anyone (asking is free) | only force/authority makes it meaningful | No — receiver judges by flag either way (M48 authority_flags) |
| Witness reaction | never aggression | aggression unless authority flag | No — follows from *what's demanded*, not the verb |
| Comply window + escalation | timeout → assessment | timeout → engage/chase | No — same machinery, different issuer policy |
| What compliance looks like | relight, keep flying | stop, be at my mercy | **Yes — again keyed on what's demanded** |

Everything except "what's demanded" is receiver-side judgment M48 already
built. So it is ONE verb — DEMAND — with a rung. And "surrender" turns out
not to be on the wire at all: it is the *receiver's word* for complying with
a STOP demand from someone it fears. This is the SUSPICIOUS lesson again
(see [economy_and_piracy.md](economy_and_piracy.md)): the original verb name
conflated the wire message with the receiver's interpretation of it.

The same DEMAND(STOP) bytes are, depending on who's demanding:

- Trusted authority flag, you're clean → **customs inspection**. Stop, wait,
  resume on RELEASE. Routine.
- Trusted authority flag, you just shot a station → **arrest**. Same
  message. The dread is yours.
- Untrusted flag or dark contact → **robbery**. Surrender-or-run decision,
  SOS out.
- Pirate colors hoisted with the demand → **unambiguous robbery, credibly
  backed**. Weighs toward compliance.

The victim cannot tell an inspection from a robbery except by trusting the
flag — which means the spoofed-militia-flag trap has ZERO distinguishing
signal until the "inspection" turns into a taking. A two-verb protocol
(HEAVE_TO vs DEMAND_SURRENDER) would have leaked the issuer's intent in the
message type; the merged verb keeps false colors airtight.

## The verb set

Directives (addressed to a target):

- **`DEMAND {rung: IDENTIFY | STOP, target}`** — comply window; escalation on
  timeout is the ISSUER's own policy (patrol: assessment/shadow for IDENTIFY,
  engage for a refused STOP with basis; pirate: chase or abort), never
  protocol-mandated.
  - **IDENTIFY**: tell me who you are. Compliance is *behavioral* — relight
    the transponder, keep flying. No reply verb: the transponder IS the
    answer, read through normal sensor fusion.
  - **STOP**: cut thrust and hold station, at my mercy. Implies IDENTIFY —
    a ship that stops but stays dark has not complied. Compliance is the
    hard honored state (below), declared with an explicit COMPLY.
- **`COMPLY {in_reply_to}`** — explicit only for the STOP rung, because
  stopped-under-compulsion is a state every AI must honor and therefore must
  be *declared*, not inferred from velocity. `in_reply_to` names the demand
  it answers — required, because simultaneous demands happen (a pirate
  strikes on the lane just as the patrol arrives; a bare COMPLY would be
  ambiguous about who it's addressed to).
- **`RELEASE {target}`** — you may resume. Ends an inspection or a hold; the
  held ship also resumes if the issuer departs/dies (nobody stays parked
  forever waiting on a dead pirate's permission).

Broadcasts (undirected):

- **`SOS {nature: UNDER_ATTACK | DISABLED, pos, name, flag, threat?}`** —
  distress, surfaced as NAV-layer data (ContractFeed-style marker; never
  injected into sensor fusion — the M41 rule). The nature field exists
  because responders need it to choose posture: UNDER_ATTACK → intercept
  weapons-hot; DISABLED → rescue/tow, weapons cold. Details that matter:
  - Sendable on minimal power (distress beacon on battery) — a
    reactor-dead ship can still cry for help even though its transponder
    died with the reactor.
  - Carries name + flag (a distress call identifies the caller), so
    broadcasting SOS COUNTS AS REPORTING for standing — the burned-out ship
    reads NEUTRAL-in-distress, not a dark contact.
  - A pirate broadcasting a fake DISABLED SOS as bait is emergent gameplay,
    deliberately allowed — attribution catches up when it springs.
- **`MARK_HOSTILE report`** — the explicit broadcast form of the standing
  share that already rides the datalink (M48).

## The one rule that keys on the rung

Witness semantics, stated once: demanding *information* is never coercion —
even a pirate can hail you. Demanding *control* (the STOP rung) from an
issuer whose flag the witness does NOT hold as an authority is an aggression
event on the bus (M48), exactly like a witnessed shot. From a flag the
witness does trust, it's a police stop and no one flips.

## Stopped-under-compulsion (the honored state)

The ship state formerly called `surrendered`: cut thrust / brake to stop,
transponder forced on, COMPLY broadcast. Orthogonal to standing (a held
pirate is still HOSTILE — standing records judgment, the state gates
weapons). Hard AI honor rules, both directions: no leaf targets a compliant
stopped ship, whether it stopped for customs, arrest, or robbery — a patrol
shooting a trader stopped for inspection breaks the fiction exactly as hard
as executing a surrendered pirate. One state, one rule, enforceable in one
place. This must be bulletproof or the fiction collapses; it belongs in
tests from day one.

## What each AI does with the verbs (issuer policy, not protocol)

- **Patrol**: DEMAND(IDENTIFY) at UNREPORTED ships in controlled space,
  ~20s window; non-compliance feeds its own suspicion assessment
  (shadow/report — a blackboard verdict, never a standing). DEMAND(STOP)
  only with basis (HOSTILE standing, or customs policy); engage only on
  refusal or fire.
- **Pirate**: DEMAND(STOP) at selected prey, optionally hoisting colors for
  the compliance bonus; a witnessed non-authority STOP is what makes the
  crime visible.
- **Cargo/civilian**: on DEMAND(STOP) or attributed attack → comply-or-run
  by speed ratio vs the threat (baseline shuttles comply; fast hulls run;
  shown pirate colors weigh toward compliance); always SOS.
- **Player**: sends and receives all verbs on the comms panel. A STOP
  demand arriving from a dark contact on YOUR panel — issuer unknown, flag
  untrusted — is the fear moment the design wants.

## Scenario check (the list that drove the design)

| Scenario | On the wire | Outcome |
|---|---|---|
| Forgot transponder | patrol DEMAND(IDENTIFY) | relight, keep flying, NEUTRAL next tick |
| Confirmed pirate | patrol DEMAND(STOP) | comply → held, or refuse → engaged |
| Customs inspection | DEMAND(STOP), inspect, RELEASE | routine stop, resume |
| Battle fleet, unannounced | DEMAND(IDENTIFY), ignored | no standing change; patrol assessment shadows/reports |
| You (pirate) stop someone | DEMAND(STOP), untrusted flag | victim reads robbery: comply-or-run + SOS; witnesses post aggression |
| Enemy warship in your space | DEMAND(STOP) | refused; fight — same message, judged by flag |
| Threatened ship runs | SOS(UNDER_ATTACK) | patrol intercepts weapons-hot |
| Reactor burnout | SOS(DISABLED) | rescue response, weapons cold; SOS counts as reporting |

## Later: the authority claim rides the hail — *designed 2026-07-27, not built*

A `DEMAND(STOP)` turns its sender **yellow** on the receiver, always, including
a lawful police stop (see the yellow tier in
`design_ideas/2026-07-26-campaign_playtest.md`). That is correct — from the
receiving end you cannot tell a patrol from a pirate in colours, and that
unresolvable ambiguity is exactly what yellow means.

But yellow should not mean *illegible*. The refinement: **a demand also shows
who is claiming to make it**, so a patrol reads as caution AND as *the cops* —
"PATROL ALPHA · claims SOVEREIGN DRIFT authority · DEMANDS STOP". The colour
says "I cannot resolve this"; the row text says what is being asserted. The
player decides what to do about it.

**Most of this already exists.** `Hail._dispatch` already stamps
`hail["sender_flag"]` from the sender's live transponder, and the police-stop
exemption already reads it. What is missing is surfacing the claim in the hails
UI, and the player having any way to act on it.

**Claiming authority costs you your anonymity, which is what keeps it honest.**
`sender_flag` comes from `get_active_transponder_data()`, so a dark demand
carries no flag at all — "a dark demand has no flag, that's the fiction". To
claim to be police you must be squawking, which means you are identifiable and
can be held to it afterwards. The claim stays cheap talk in the sense this
codebase already means it ("flags are cheap talk except the pirate flag") — a
pirate CAN squawk a militia flag and demand your surrender — but doing so puts a
name on the act, and the victim's `ARMED_THREAT` warrant then names that
identity rather than an anonymous signature.

**This is the intended resolution of the `authority_flags` gap** (playtest notes,
found 2026-07-27): the player ship's `authority_flags` is empty while NPC
haulers carry `[FLAG_DRIFT]`, so a lawful patrol stop makes the PLAYER post an
`ARMED_THREAT` warrant that an NPC civilian would not. Rather than hardcoding a
trust list onto the player's hull, show the claim and let the player judge.

That lands on the asymmetry this codebase already uses twice — **NPCs comply
with a rule, the player gets a gauge and the freedom to be a menace** (the port
speed advisory, and the thermal self-throttle exemption at `ship.gd`'s
`_thermal_throttle_cap` call site). `authority_flags` stays as the machine rule
for NPCs; the player gets information instead.
