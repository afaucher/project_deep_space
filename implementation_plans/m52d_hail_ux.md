# M52d — Hail lifecycle + comms panel restructure

Sub-milestone from the 2026-07-20 pirate playtest (design_ideas/
2026-07-20-pirate_playtest.md). The M49 hail protocol works on the wire;
the playtest showed the PLAYER-FACING half is missing: no alert when
hailed, unclear compliance affordance, demands that never expire, and a
hails panel with no legible structure.

## 1. Demand lifecycle (data bug first — the rest is UI on top of it)

Playtest: "The first demand never went away, it was still there when the
second pirate got me."

Confirmed in ship.gd: `pending_demand` is set on receipt and cleared ONLY
by `comply_with_stop()` or overwritten by a newer demand. Nothing clears
it when the issuer dies, leaves, or loses interest. Fix at the data layer
(the compelled_stop block right below it is the template — it already
auto-releases on a dead/out-of-range issuer via `lost_issuer_timer`):

- **Issuer-gone expiry:** same present-check compelled_stop uses (alive
  AND in comms-link range); issuer absent past a short timeout → clear
  `pending_demand`.
- **Issuer-lost-interest:** the pirate's own job already aborts (patience/
  outpaced/witness) — on abort, the pirate should SAY so: send RELEASE
  (the verb exists, take_alongside already sends it on completion). A
  received RELEASE addressed to us clears a matching pending_demand.
  Long-term the playtest wants hails to be PERSISTED BY the issuing ship
  (a live channel, not a fire-and-forget datagram) — the RELEASE-on-abort
  discipline is the cheap v1 of that; a real channel model is future work.

## 2. Incoming-hail alert

A DEMAND addressed to you gets a sound and/or visual alert (playtest ask;
today it lands silently in a list you may not be looking at). The
transient_events plumbing terminal_display already consumes for banners
is the delivery path — a DEMAND(STOP) at minimum flashes the hails panel
header and pings once. (Godot audio exists in-project; keep the cue short
and distinct. Visual alone is acceptable v1 if no asset fits.)

## 3. COMPLY affordance

Playtest: "The comply button appeared but it wasn't clear what it actually
did. Do I stop? Do I press the button? Is the button just for fun?"

The mechanical truth (M49): compliance is BEHAVIORAL — comply_with_stop()
declares it (broadcasts COMPLY, forces transponder on, sets
compelled_stop), but a complied ship that then moves reads as bolted
(complied_stop clears on observed speed). The button is real AND stopping
is real, and nothing tells the player either. Fix is presentation plus
one hook into M52c:

- Button label/tooltip states the contract: "COMPLY — declare compliance
  and hold station. Moving again voids it."
- Pressing COMPLY engages M52c's DEAD STOP autopilot automatically (one
  press = declare + actually stop) — the two-milestone seam, wire
  whichever lands second to the other.
- While compelled_stop is active, the panel shows the held state
  explicitly ("HELD — complying with <ship>") instead of leaving the
  player to infer it.

## 4. Hails panel restructure — sort by VESSEL, not by message

Playtest observation: the panel mixes a selected-vessel readout, outgoing
demand buttons, and inbound demand lines with no shared structure. The
insight worth keeping verbatim: "they are actually all just vessels with
different reasons to be in the list."

New structure — ONE list of vessel entries, a vessel appearing if ANY of:
  - it's the currently selected contact,
  - we have sent it a hail (so it can be tracked/cancelled),
  - it has hailed us.

Per entry:
  - **Header: track/ship name + flag** (e.g. `TRK-042 "Rust Bucket" —
    JOLLY_ROGER`). Omit `[TO YOU]` — being in the list under that vessel
    already says so.
  - Under it, that vessel's hail traffic (theirs to us, ours to them) and
    the applicable ACTIONS as consistent buttons — same style, same
    casing (today: "DEMAND ID" / "DEMAND STOP" / "Request Docking" mix
    caps and prose and don't read as buttons). A pirate's DEMAND(STOP)
    entry can sit right above your own DEMAND STOP button aimed back at
    it — symmetrical, legible.

Shape: `[vessel -> [hails to/from], ...]` (the playtest's own notation).
comms_panel.gd already receives selected contact id and last_hails; the
restructure is a rebuild of its list-building, not new data plumbing —
plus one addition: locally remember hails WE sent (sender side currently
fires and forgets) so the "vessels we hailed" bucket exists.

## Tests

- Demand expiry: issuer dies → pending_demand clears within timeout;
  issuer leaves comms range → same; second demand still overwrites first
  (existing behavior pinned).
- RELEASE-on-abort: pirate job aborts DEMAND_STOP → victim's
  pending_demand clears without compliance.
- COMPLY one-press: comply_with_stop + dead-stop engaged together;
  compelled_stop shows held state; moving voids it (existing behavioral
  check still passes).
- Panel structure is data-driven enough to test headless: given
  (selected, sent-hails, received-hails) fixtures, the entry list groups
  by vessel with the right actions enabled (same widget-level pattern as
  test_weapons_panel_standing.gd / test_controls_menu_ui.gd).
