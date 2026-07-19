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
  offense:    "SPEED_VIOLATION" | "IGNORED_CHALLENGE" | "ARMED_ROBBERY"
              | "PIRACY_FLAG" | "MURDER" | ...,
  subject:    claimed transponder name + observed signature snapshot
              (what the observer could actually see -- honesty rule),
  issuer:     ship/station id + its flag (the ORIGIN authority),
  origin_flag: the issuer's flag at issue time,
  timestamp:  issue time,
  expires:    time limit for minor offenses (speeding decays; murder never),
  status:     OPEN | RESOLVED,
  resolved_at: timestamp of the status change (latest-timestamp wins),
  event_key:  dedup key -- see below,
}
```

Standing then becomes a *derived* view: your disposition toward a contact
is a function of the warrants you hold that match it, filtered through
your own policy — not a stored verdict.

### Response levels (proportionality)

Each offense type carries a response class, and each AI's policy maps
class → behavior. A speed violation justifies an INTERCEPT (shadow,
demand stop, fine); PIRACY/MURDER justifies shoot-on-refusal or
shoot-on-sight. This *is* the escalation ladder the M52 notes asked for —
marked → challenged → fire-on-refusal — expressed as data per offense
rather than a global state machine. Enforcement is also authority-scoped:
a military patrol ignores civil infractions (leaves speeding to civil
defense) but acts on piracy; port control is the reverse. "Which classes
do I enforce" is a per-tree policy list, same shape as the ROE parameter
jobs already carry.

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

- Warrants ride the existing datalink/comms relay like contacts do:
  network members converge on a shared list. **Not on the network → you
  can't see it.** A pirate under a fresh cover doesn't know what's held
  against its old name — but a station may publish a WANTED list (possibly
  only bounty-carrying entries, possibly only if you ask port control),
  and reading your own old ID on it is exactly the intended experience.
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

- AI ships only ENFORCE warrants whose origin matches their own true
  flag's authority set (a home patrol enforces home warrants, ignores
  pirate-issued ones). Pirates fly false colors but their true allegiance
  decides what they act on.
- "You killed someone in the next country over and nobody here cares" —
  cross-flag warrants are visible (intel!) but unenforced unless policy
  says otherwise.
- A warrant an ENEMY holds about you is pure information: it tells you
  what they'll do when they see you. The player reads it; the AI's trust
  policy already handles it (wrong origin → no enforcement).
- The PLAYER always exercises judgment manually: their warrant list is
  advisory UI, and acting on it is their call.

### MARK HOSTILE becomes local, and earned lists

The targeting-computer MARK control stops being a network verdict and
becomes an entry in YOUR OWN warrant list (offense: "OPERATOR_FLAGGED",
origin: you, expiring or not as you choose). That list is empty at
campaign start — shared lists are something you EARN: sign a bounty
mission and receive that issuer's warrants; join a local defense force
and get theirs over IFF. This gives the standing-replication machinery a
fiction that explains who shares what with whom, instead of an ambient
global truth.

### Future (explicitly not now)

- Bounty cash-in: warrants with bounties are claimable ("I killed him,
  pay up" — nobody pays for killing speeding-ticket guy).
- Prove-resolved presentation flow (the data shape supports it already).
- Port control sharing warrant lists on request.

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
2. Aggression bus posts warrants instead of (then alongside, then instead
   of) mark_contact_hostile; standing becomes the derived view; sticky
   HOSTILE retired. The wreck gate stays — a warrant names a subject, and
   a hulk stops being one.
3. Relay propagation + latest-timestamp merge + dedup keys.
4. Response classes + per-tree enforcement policy (patrol vs civil).
5. UI: warrant list panel (replaces the standing readout's guts), WANTED
   list at stations, MARK-as-local-warrant.
6. Militia framing lands with the campaign start-state (no feeds).

Open questions to settle during the M52b design pass proper: exact
offense taxonomy v1; whether observer confidence (attribution gate from
M48) rides on the warrant or gates its issue; how the derived-standing
view keeps the cheap per-contact color lookup the UI relies on.
