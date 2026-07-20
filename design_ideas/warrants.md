# Warrants — observed offenses replace "enemy forever"

Design rescope of the M48 standing/MARK-HOSTILE machinery, written up as
sub-milestone M52b (roadmap: m48_m55_economy_piracy_roadmap.md). This
REPLACES the three parked playtest notes in economy_and_piracy.md ("no
retraction verb", "invisible state flips", "escalation ladder") — all
three fall out of the warrant model for free.

## The problem with sticky HOSTILE

M48's standing is a single per-observer verdict: once HOSTILE, hostile
forever, with no record of WHY, no expiry, no revocation path, and no
proportionality — a speeding freighter and a serial killer get the same
bit. Playtest hits so far: collisions marked beacons (and the player)
enemy with no way back; state flips are invisible; and the wreck-firing
bug was sticky-HOSTILE outliving its target's death. Each got a local
patch; the warrant model fixes the class.

## Core model

A **warrant** is a record of a concrete observed offense:

```
{
  offense:    "ASSAULT" | "SUSTAINED_ASSAULT" | "ARMED_THREAT"
              | "ARMED_ROBBERY" | "NO_ID" | "SPEED_VIOLATION"
              | "OPERATOR_FLAGGED" | ...,
  subject:    claimed transponder name + observed signature snapshot
              (what the observer could actually see -- honesty rule),
  issuer:     ship/station id + its flag (the ORIGIN authority),
  origin_flag: the issuer's flag at issue time,
  timestamp:  issue time,
  expires:    time limit for minor offenses (speeding decays; robbery never),
  status:     OPEN | RESOLVED,
  resolved_at: timestamp of the status change (latest-timestamp wins),
  event_key:  dedup key -- see below,
}
```

Standing then becomes a *derived* view: your disposition toward a contact
is a function of the warrants you hold that match it, filtered through
your own policy — not a stored verdict.

### Response levels (proportionality)

Every offense maps to one of two response classes, and both classes run
the SAME behavior shape — challenge, demand stop, stand down if they
comply, fire if they refuse or run — differing only in how much patience
is extended before firing:

- **INTERCEPT**: normal patience. The default for anything that could
  plausibly be a mistake or a minor infraction.
- **MAX**: short patience. Reserved for offenses that are no longer
  plausibly accidental. Still challenges and still stands down on
  compliance — MAX is not "shoot without warning," it's "don't wait
  around for a second refusal."

This *is* the escalation ladder the M52 notes asked for — marked →
challenged → fire-on-refusal — expressed as data per offense (which class,
which patience) rather than a global state machine. Enforcement is also
authority-scoped: a military patrol ignores civil infractions (leaves
speeding to civil defense) but acts on piracy; port control is the
reverse. "Which classes do I enforce" is a per-tree policy list, same
shape as the ROE parameter jobs already carry.

### Offense taxonomy v1

| Offense | Trigger | Response | Expiry |
|---|---|---|---|
| `ASSAULT` | single hit -- own-faction instant witness, or a stray hit before the attribution gate trips | INTERCEPT | short -- presumptively an accident until proven otherwise |
| `SUSTAINED_ASSAULT` | `aggro_hits` crosses `STRAY_HITS_TO_HOSTILE` (standing.gd) -- no longer plausibly an accident | MAX | never |
| `ARMED_THREAT` | non-authority STOP demand issued/witnessed | INTERCEPT | ~30min, superseded by `ARMED_ROBBERY` if the job lands |
| `ARMED_ROBBERY` | pirate job takes loot | MAX | never |
| `NO_ID` | witnessed inside a mandatory-ID zone (port zone or, later, the beacon corridor) while the observer's own read on the contact is `UNREPORTED` | INTERCEPT | self-resolving -- see below |
| `SPEED_VIOLATION` | port zone speed limit | INTERCEPT | short |
| `OPERATOR_FLAGGED` | player MARK | n/a -- player's own manual judgment, no AI-executed response class |

A single accidental hit and an armed demand sit at the same INTERCEPT
tier deliberately: neither has earned MAX's shortened patience yet.
`NO_ID` needs no bespoke detection or revocation: "mandatory-ID zone" is
one more entry in the port zone's existing rule → handler registry
(`PortRules.rule_summary_handlers()`, e.g. `mandatory_id: true`) so port
zones can opt in with zero new plumbing, and it resolves itself the
moment the subject reports a transponder -- `compute_standing` already
flips them off `UNREPORTED` on its own (standing.gd rule 4), so there's
no separate revocation path to build for it.

Deferred, not in v1: `PIRACY_FLAG` (flying pirate colors stays the
existing zero-cost flag rule in `compute_standing`, not a per-sighting
warrant), `IGNORED_CHALLENGE` (nothing produces it yet), `MURDER`
(nothing distinguishes it from `ASSAULT` yet).

### Time limits and revocation

- Minor warrants expire on their own clock (`expires`); expiry is local
  arithmetic, no comms needed.
- Revocation is a STATUS UPDATE to the same record: get arrested, pay the
  fine → the arresting authority sets status=RESOLVED with a fresh
  timestamp. Latest-timestamp-wins is the merge rule, so the resolution
  propagates over the same comms network the warrant did and overrides
  stale OPEN copies as it spreads.
- This naturally enables (but we don't build yet) "prove I did my time":
  the subject can CARRY its own RESOLVED copy and present it over comms.
  Run to the far side of the cluster after paying your fine and the locals
  may know the crime but see the resolution too.

### Propagation, visibility, dedup

- Warrants ride the existing datalink/comms relay like contacts do —
  literally the same link, gated the same way (comms range on both
  sides, line of sight, IFF-tag overlap), re-evaluated live every tick,
  not a persistent membership: lose the link and relay just stops until
  it reforms. **Not on the network → you can't see it.** A pirate under
  a fresh cover doesn't know what's held against its old name — but a
  station may publish a WANTED list (possibly only bounty-carrying
  entries, possibly only if you ask port control), and reading your own
  old ID on it is exactly the intended experience.
- **Only authorized warrants ride the network.** The relay propagates a
  warrant only if it has a non-empty `origin_flag`. Personal-origin
  warrants (unauthorized witness, player MARK) never leave the issuing
  ship, live link or not — otherwise "MARK HOSTILE becomes local" would
  stop being true the moment a stranger sharing your IFF tag drifts into
  radio range and line of sight.
- **On-request pull, for when you're not on the network.** The player
  doesn't share IFF with home stations by default, so the live relay
  above never fires just by flying near or docking at one — visiting a
  station needs its own explicit query, not the ambient link. Docking (or
  hailing port control) lets you ASK for the station's warrant list; the
  answer copies matching records into your OWN local `warrants` store,
  same latest-timestamp/`event_key` merge rule the live relay uses, and
  preserves the station's `origin_flag` rather than rewriting it to
  yours. This is a one-time pull, not a subscription — walk away and you
  stop getting updates until you ask again. Same shared entry point
  pattern as docking requests (`PortControl.request_docking`) so the
  dialogue path and any fast-path UI button can't diverge on outcome.
- **Dedup:** two patrols watching the same robbery must converge on ONE
  record. `event_key = (offense, subject-identity-as-observed, coarse
  time bucket, coarse location bucket)` — same key → same warrant, merge
  by latest-timestamp/highest-status. Needs care for claimed-name vs
  signature identity (two observers may know the subject by different
  handles); v1 rule: key on claimed transponder name when present, else
  on track-signature match, and accept occasional duplicates over false
  merges.

### Authority chain and belief

Seeing a warrant is not believing it. Every warrant carries its
`origin_flag`, and every reader applies its own trust policy:

- **Enforcement and issuing share one gate.** A ship enforces a warrant
  only if `warrant_authority.has(origin_flag)` — the SAME field that
  gates whether it can ISSUE under that flag (Issuing authority, below).
  Stations/patrols default `warrant_authority` to their own flag, so "a
  home patrol enforces home warrants" falls out with no separate rule;
  it's just the general check applied to a ship that happens to already
  hold its own flag's authority. Pirates fly false colors but their true
  allegiance (their own `warrant_authority`) decides what they act on.
  One grant — accepting a hunt-pirate mission — covers both halves at
  once: "your calls count as ours" (issue) and "you may act with our
  authority" (enforce).
- "You killed someone in the next country over and nobody here cares" —
  cross-flag warrants are visible (intel!) but unenforced unless policy
  says otherwise.
- A warrant you hold but aren't authorized to enforce is still
  information, not noise — the same rule as a warrant an ENEMY holds
  about you: it tells you what an authority would do if it saw this
  contact, useful for avoidance even when it isn't yours to act on. A
  station's pulled-in WANTED list before you're deputized is exactly
  this case: you can flag a listed vessel and steer clear of it, you just
  can't fire on the strength of it alone.
- The PLAYER always exercises judgment manually: their warrant list is
  advisory UI, and acting on it is their call.

### Issuing authority — flying a flag isn't authority to warrant under it

`origin_flag` as defined above ("the issuer's flag at issue time") is
exactly as permissive as it sounds: any ship flying a flag could mint a
warrant that every other same-flag ship treats as authoritative, purely
by witnessing something. That's too loose — a random trader flying home
colors shouldn't be able to single-handedly generate network-enforced
dogma off one sighting.

Add a field distinct from the two that already exist on `Ship`
(`iff_tags` — identity, who I claim to be; `authority_flags` — trust,
which OTHER flags I personally recognize as lawful when THEY act on ME,
today's police-stop exemption): **`warrant_authority: Array`** — the
flag(s) THIS ship is personally deputized to issue *enforceable*
warrants for. Stations and patrol/military ships default to their own
flag (they ARE the authority). Everyone else — traders, civilians, and
the player/militia at campaign start — defaults to empty. A hunt-pirate
mission grant adds an entry, for the mission's duration or permanently
on joining the defense force.

This gate applies uniformly to every warrant-posting call site (the
aggression bus, hail-demand witnessing, MARK), not just the player's
manual MARK: when a ship posts a warrant, `origin_flag` is only set to
its own flag if that flag is in its own `warrant_authority`. Otherwise
the warrant is still created — a witnessed account is still worth
recording — but scoped personal: `origin_flag: ""`, `issuer` still
identifies the witness. A personal-origin warrant is enforceable only by
its own issuer (this is exactly what today's private per-observer
contact-standing flip already amounts to); to anyone else it's pure
information, the same non-enforcement rule the doc already applies to
cross-flag warrants ("an ENEMY's warrant about you is pure information"),
now applied to same-flag-but-undeputized witnesses too. This is also
WHY station/patrol-sourced WANTED lists (Future, below) are meaningfully
different from "any random ship's grudge" — they're the ones actually
authorized to make it official.

### MARK HOSTILE becomes local, and earned lists

The targeting-computer MARK control stops being a network verdict and
becomes an entry in YOUR OWN warrant list (offense: "OPERATOR_FLAGGED",
origin: you, expiring or not as you choose) — the player starts with no
`warrant_authority` entries, so this is the general personal-origin rule
above, not a special case. That list is empty at campaign start — shared
lists are something you EARN: sign a bounty mission and receive that
issuer's warrants (and, per the section above, the standing to ISSUE
under their flag while deputized); join a local defense force and get
theirs over IFF. This gives the standing-replication machinery a fiction
that explains who shares what with whom, instead of an ambient global
truth.

### Future (explicitly not now)

- Bounty cash-in: warrants with bounties are claimable ("I killed him,
  pay up" — nobody pays for killing speeding-ticket guy). The on-request
  station pull (Propagation, above) is now in v1 scope; bounty amounts
  and the cash-in flow itself are still future.
- Prove-resolved presentation flow (the data shape supports it already).
- **The beacon road as a controlled corridor.** The road may become a
  port-zone-like jurisdiction authoring the same `mandatory_id` rule port
  zones use for `NO_ID` above -- no separate LOITERING offense needed,
  transiting dark (or just sitting there) inside the corridor's zone
  while `UNREPORTED` is already the whole offense. Compounds M52a's road
  tradecraft: the road already has beacon witnesses, traffic, and
  patrols; mandatory IDs would make it formally hostile ground for
  anyone with something to hide, not just observably risky. The zone
  geometry itself (corridor-shaped, not station-radius) is the only new
  work -- the offense and enforcement machinery are already v1.

## Campaign framing: the militia

Leaning decision to design against: the player is part of a SMALL MILITIA,
separate from the home-system authority. Everything flies the same home
flag, but the stations and the beacon road do NOT share IFF or comms with
the militia by default — the player starts with no warrant feed, earns
one via bounty work, and may later (story) join the actual defence force
or see the militia recruited wholesale. This makes the empty-list start
state canon rather than a gap.

## Migration sketch (M52b scope, refine at execution)

1. Warrant record + local store + expiry (pure data, no behavior change).
2. `warrant_authority` field + origin-scoping rule (personal vs flag),
   defaulted on stations/patrols vs everyone else.
3. Aggression bus posts warrants instead of (then alongside, then instead
   of) mark_contact_hostile; standing becomes the derived view; sticky
   HOSTILE retired. The wreck gate stays — a warrant names a subject, and
   a hulk stops being one.
4. Relay propagation + latest-timestamp merge + dedup keys.
5. On-request station pull (`PortControl.request_warrant_list`, same
   shared-entry-point shape as `request_docking`) for the no-live-link
   case.
6. Response classes (INTERCEPT/MAX) + per-tree enforcement policy (patrol
   vs civil), keyed on the same `warrant_authority` gate as issuing.
7. UI: warrant list panel (replaces the standing readout's guts), WANTED
   list at stations, MARK-as-local-warrant.
8. Militia framing lands with the campaign start-state (no feeds, no
   `warrant_authority`).

## Design questions, settled

**Confidence gates issuance, not the record.** `aggro_hits` stays exactly
what it is today: private, per-observer scratch on the witnessing ship's
own contact record, counted only from hits that ship personally saw.
Crossing `STRAY_HITS_TO_HOSTILE` is what POSTS the `SUSTAINED_ASSAULT`
warrant (status OPEN, no confidence field on the record) -- the same call
site as today's flip-to-HOSTILE, just posting instead of mutating a
sticky bit. The warrant record itself stays the simple shape above, with
no merge-semantics burden on `event_key` dedup. Known v1 gap: two
different observers each seeing 2 stray hits (below either one's own
threshold) never issues a warrant even though 4 total hits happened
across witnesses -- cross-observer aggregation is lost. Acceptable for
v1; the alternative (confidence living on the shared record, incremented
by merging witness reports) adds real complexity for a rare case.

**The cheap per-contact color lookup survives unchanged.** Today
`compute_standing()` runs once per contact per fusion tick (not per UI
paint) and caches the result string onto `contact["standing"]`; the UI
(contacts_panel.gd) just does a dict lookup on that cached string --
O(1) per contact per frame. That architecture doesn't change. Maintain a
per-observer warrant index -- `Dictionary` keyed by claimed-name-or-
signature (same key shape `event_key` dedup already uses, and the same
shape `Standing.wanted_names` already uses) -- mapping to the worst open
warrant matching that subject. `compute_standing`'s replacement does one
dict lookup against that index instead of reading a sticky bit, reduces
the matched warrant's response class down to one of the existing four
shared tiers, and caches it onto `contact["standing"]` exactly as now.
UI is untouched; only the standing computation's INPUT changes, from
"sticky bit + rule cascade" to "warrant-index lookup + reduce."
