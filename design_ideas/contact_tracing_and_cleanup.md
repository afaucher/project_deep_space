# Contact Tracing, Ghosts, and Cleanup

How sensor returns become tracked contacts, why stale "ghost" contacts appear, and the
options for cleaning them up. Companion to [`comms.md`](comms.md) (datalink relay /
freshest-wins fusion) and [`missile_tracking_tradeoffs.md`](missile_tracking_tradeoffs.md)
(the missile's own seeker-side lock loss). This doc is the *observer* side: what a ship
believes about everyone else, and how that belief decays.

---

## 1. Current understanding of contact tracing

The pipeline, host-side, per ship, every physics tick (`ship.gd`):

1. **Sweep** — `_run_sensor_sweep()` does a physics shape-query out to sensor range,
   filtered by arc and a line-of-sight raycast. Hits are dropped into **angular bins**
   (one wedge per `bin_idx`). Multiple objects in one bin **merge** into a single
   cross-section-weighted centroid blip under the `BLEND` policy — but the **default is now
   `NEAREST`** (keep the nearest object's clean signature, shadow the rest); see the
   signature-bleed subsection in §2. Position/velocity get noise added
   (`SENSOR_POS_NOISE`, `SENSOR_VELOCITY_NOISE`).
2. **Correlate** — each fresh bin is matched into the persistent `active_contacts`
   dictionary. Match is by `instance_id`-derived track id (`TRK-%03d` from
   `abs(instance_id) % 1000`) when available, else by nearest existing contact within
   `CONTACT_CORRELATION_RANGE` (2000 m). Matched → fuse (lerp toward the new reading,
   `CONTACT_FUSION_SMOOTHING`); unmatched → new track.
3. **Classify** — `classify_contact()` turns the fused signature into a label
   (UNIDENTIFIED VESSEL, ASTEROID, INCOMING ORDNANCE, …).
4. **Decay & dead-reckon** — every tick, each contact's `last_seen_timer` and
   `pos_timer` increment, and its position is **extrapolated** on its last known
   velocity (`pos += vel * delta`). When `last_seen_timer > CONTACT_TIMEOUT` (20 s) the
   track is finally dropped.
5. **Relay** — friendly ships in mutual comms range + LOS merge each other's
   `active_contacts` freshest-wins (see `comms.md`). This re-runs from scratch each
   tick, so a relayed contact propagates one hop per tick.

Key data each contact carries (all shipped to the client in the packet):
`pos`, `vel`, `resolution` (the bin_angle that last updated it), `last_seen_timer`,
`pos_timer`, `signature{...}`, `classification`, `instance_id`.

### Tuning constants (ship.gd)
| Const | Value | Meaning |
|---|---|---|
| `CONTACT_TIMEOUT` | 20.0 s | no detection before a track is dropped |
| `CONTACT_CORRELATION_RANGE` | 2000 m | max gap to fuse a blip into an existing track (no instance_id) |
| `CONTACT_FUSION_SMOOTHING` | 0.8 | lerp weight toward each new reading |
| `CONTACT_RESOLUTION_STALE_TIME` | 0.3 s | when a coarser bin may override position anyway |
| `SENSOR_POS_NOISE` / `SENSOR_VELOCITY_NOISE` | 0.005 / 0.05 | reported pos/vel jitter |

---

## 2. The ghost problem

"Too many sensor ghosts; hard to interpret." Four distinct mechanisms, which want
different fixes:

1. **Stale dead-reckoned tracks (the big one).** A contact seen once then lost keeps
   being extrapolated for a full 20 s, drifting on a noisy velocity. After a furball you
   get a cloud of phantoms gliding where nothing is.
2. **No uncertainty is drawn.** A contact measured *this frame* and one coasting on
   15 s-old data render identically — same opaque blip, same crisp label. The system has
   limited information but displays it as certainty. This is the root interpretability
   problem: the display lies about how stale a track is.
3. **Bin merge/un-merge popping.** Two ships in one angular bin collapse to one centroid;
   when they separate the blip splits and jumps. Its nastier cousin is **signature bleed**
   — the merge corrupts *identity*, not just position (see the dedicated subsection below).
4. **Position/angle noise** makes even *live* contacts swim, compounding #3.

### Already shipped: display-layer honesty (cheap, no logic change)
- **Age-fade on the map** — contacts dim with `last_seen_timer` via
  `Utils.contact_confidence()` + `Utils.fade_color()`, folded into
  `navigation_panel._get_contact_color()`. Bright = just seen, faint = coasting.
  Knobs: `Utils.CONTACT_FADE_FULL` (8 s to floor), `CONTACT_CONFIDENCE_FLOOR` (0.2).
- **Age readout in the contact list** — each row shows `Age: Ns` (whole seconds since
  last real detection) instead of dimming, so the list stays legible.

These make ghosts *look* like ghosts but don't remove them. Removal is the rest of this
doc. There's also a broader, unbuilt idea — *grades of sensor fusion* (raw bins → tracked
→ confidence-decay → ground-truth) as a switchable debug view — noted here as future work;
the age-fade is grade-2's first slice.

### Signature bleed: co-bearing identity corruption

A distinct, sharper failure than the stale-ghost cloud. **An enemy passes near an asteroid;
when they separate, *both* read as enemy.** It's a corruption of the merge, and it can
*stick*.

**Mechanism.** When two objects share an angular bin, the `BLEND` merge fuses them lossily
in three ways that conspire (`_run_sensor_sweep`):
- `heat` / `em_noise` take the **max** across the bin → the blip inherits the *enemy's* hot,
  emitting signature.
- `cross_section` is **summed** → comfortably over the vessel threshold.
- `instance_id` is taken from the object with the **largest** cross-section → an asteroid
  (big) outweighs a ship, so the merged blip is stamped with the *asteroid's* id.

That last point is the killer: the blip hard-correlates by id to the **asteroid's own
track**, and overwrites its stored signature with the hot blend → the asteroid is now an
`UNIDENTIFIED VESSEL`. (Confirmed in `test_signature_bleed`: under BLEND the asteroid track
reads CS 660 = 600 + 60, heat and EM both bled from the enemy.)

**Why it persists after separation.** The asteroid's track should self-heal once it gets a
clean cold read again, but two things delay that:
- The **resolution gate** (`bin_angle <= current_res or pos_timer > CONTACT_RESOLUTION_STALE_TIME`):
  if the corrupting read came from a fine sensor and the post-separation reads are coarser,
  the cold reads are *rejected* and the hot signature sticks until contact is lost.
- **Fine sensors mask the bug at close range.** The frigate's `omni_short_hi_res`
  (range 5000, 36000 bins) and forward `dir_high_res` (1° bins) resolve co-bearing objects
  *separately*, so each gets a clean per-id read and never bleeds. The bleed surfaces
  **beyond ~5 km on bearings the forward cone doesn't cover**, where only the coarse
  `omni_main` (TAU / 36 bins = 10°) resolves the pair — exactly the "at range, off to the
  side" geometry where it's observed.

**The fix — `DebugSettings.signature_merge` (top-bar Debug → "Co-bearing bin merge").**
The merge itself is *intended* (limited angular resolution genuinely can't separate two
things at one bearing), so the fix is "don't let a lossy merge corrupt a confident track,"
not "stop merging":

- **`BLEND` (old behavior):** max heat/EM, sum CS, largest object owns the id. Models a
  fat ambiguous return — and bleeds identity.
- **`NEAREST` (the fix, now default):** don't blend. Keep only the **nearest** object's clean signature +
  real id; farther objects are **shadowed** (their tracks dead-reckon, untouched). Neither
  identity is ever corrupted, so each snaps back the instant it's individually resolved, and
  the resolution-gate trap can't arise (there's no bad write to get stuck on). The blip also
  carries `shadowed = N` (count hidden behind it) for a future "+N" UI hint; nothing reads
  it yet.

What `NEAREST` trades:
- *Gives up* the "one fat ambiguous return" model and can **starve the farther object's
  refresh** while it's shadowed (fine up to the 20 s timeout; longer co-bearing lingers
  could blink it).
- *Gains* crisp, non-corrupting identities, simplicity (a selection rule in the bin loop,
  no new downstream state), and an emergent EW texture: **a hot ship can hide behind an
  asteroid** relative to a sensor and eat its own refreshes.

A considered-but-not-built alternative — the **position-only blob**: keep merging, but when
`count > 1` flag the blip ambiguous and let it update *position only*, never overwriting a
track's signature/classification (optionally surfacing a distinct `MULTIPLE CONTACTS`
label). It preserves the "I can't tell what's in there" ambiguity as a feature where
`NEAREST` instead asserts the near object cleanly. The two aren't exclusive — `NEAREST` for
the signature, still flag `shadowed` for the UI. Recommendation: **`NEAREST`**, for crisp
identities + the clutter-hiding behavior.

Locked in by `test_signature_bleed`, which stages a hot enemy just behind a nearer asteroid
on a shared coarse bin and asserts the asteroid stays `ASTEROID` under `NEAREST` (and would
fail under `BLEND`).

---

## 3. The despawn case specifically

A contact only becomes a *known-false* ghost (vs. honest fog) when the source entity is
genuinely gone. Today only one path truly removes an entity:

- **Missile detonates → `queue_free()`** (`missile_controller.detonate()`). The body
  vanishes; the host *knows* it's gone.
- **Missile out of fuel / shot down → `hulk()`**, NOT freed. It becomes an inert drifting
  body that is *legitimately still detectable*. Its contact is **not** a ghost — it's
  correct. (Hulks accumulating forever is a separate clutter problem; see §6.)
- **Ships dying → `hulk()`**, same as above: real persistent bodies.

So the cleanup question is narrow: **when a missile detonates, observers keep a
dead-reckoned ghost of it for up to 20 s, even though the host has perfect knowledge it's
gone.** That thrown-away knowledge is what the options below exploit.

The track id is deterministic from `instance_id`, so we can target the exact track
without a handle to the about-to-be-freed node:
`Ship.purge_despawned_contact(tree, instance_id, world_pos)`.

---

## 4. The cleanup options

Selectable live via the top-bar **Debug** menu → "Missile contact cleanup"
(`DebugSettings.missile_cleanup`).

### Option 0 — Off (20 s timeout)
Baseline / current shipped behavior. The ghost dead-reckons until `CONTACT_TIMEOUT`.
Honest about sensor fog in general, but wrong for the despawn case (we *know* it's gone).

### Option 1 — Purge all immediately
On despawn, erase the track from **every** ship's `active_contacts` in one pass.
- **Complexity:** trivial (~one loop).
- **Relay:** immune — no ship is left holding it, so freshest-wins has nothing to
  re-import. Purge is permanent.
- **Observed:** the blip winks out on every console at the instant of detonation.
- **Cost:** a small omniscience leak — a distant third party who'd lost LOS still sees the
  blip vanish, learning of a detonation it didn't witness. Negligible for missiles
  (detonations are ≤ 100 m from a target; anyone relevant saw it anyway). Would matter
  more for capital ships ("did the flagship really die or jump out?").

### Option 2 — Purge only if visible
On despawn, erase the track only from ships whose **active** sensors currently cover the
despawn point (range + arc + LOS — `Ship._can_sense_point()`). Out-of-range observers keep
coasting their stale track (they legitimately don't know yet).
- **Complexity:** moderate, and most of it is fighting the relay:
  - A "can I see this point now?" sensor test (active sensors only — a passive EM sensor
    detects emissions, so it can't confirm *empty* space).
  - A **tombstone** per purged track (`_contact_tombstones`, suppressed for
    `CONTACT_TIMEOUT`). Without it, a blind teammate relays the ghost straight back into
    the ship that just purged it. The relay loop skips tombstoned ids; tombstones decay
    in the contact-decay loop.
- **Observed:** consoles legitimately disagree — close ships drop it promptly, distant
  ships keep the phantom until it ages out. Faithful fog-of-war.
- **Tension:** the surviving phantom on distant consoles *is* exactly the ghost we set out
  to remove — Option 2 preserves it on purpose for observers who can't see. For small,
  fast, short-lived missiles, the observers who "shouldn't know" are the distant ones who
  barely matter, so the tombstone machinery buys correct fog mostly where it's least
  useful.

### Option 3 — Trace disproval (deferred — too complex to build now)
**Not a despawn action at all.** A continuous, per-frame test: if your sensors *actively
cover the region a stale track should occupy* and return nothing, you've *disproven* the
track on evidence, and drop it early — independent of any despawn event. Works for
anything that isn't where you think: detonated, destroyed off-sensor, evaded, mis-tracked.

The hard question: proving the *predicted point* empty is easy; proving the target
**isn't nearby either** is not. What you'd need to know:

1. **Reachability region, not a point.** Since last seen Δt ago, the true target lies in a
   region that grows by `v_err·Δt` (velocity error, linear) **plus `½·a_max·Δt²`
   (maneuver, quadratic)**. The quadratic maneuver term dominates and is why a track lost
   a few seconds ago could be far from where it's drawn. You must sweep the whole region
   empty, not just the center.
2. **`a_max`, which we don't store.** Reachability depends entirely on how hard the target
   can maneuver — classification-dependent:
   - **Asteroid** `a_max ≈ 0` → region barely grows → disproval is *trivially safe and
     powerful*. (Best first target for this feature.)
   - **Missile** maneuvers viciously → region balloons → disproval is *fragile* exactly
     for the things we most want to clean up.
3. **Coverage = detectability, not geometry.** "No return" only disproves a target *above
   threshold there*. Two holes: **LOS shadows** inside the region (coverage minus
   shadows), and **signature vs threshold** — a target that went cold / dropped below the
   noise floor (esp. passive EM or long range) could sit in the swept region undetected.
   This is a hard stealth coupling: disproval must **not** be able to "prove gone" a
   target that merely went quiet, or it hands the searcher free counter-stealth. The
   honest result of "covered it, saw nothing detectable" is *lost contact*, not
   *destroyed* (blip just disappears, no kill marker — reads correctly as "we lost it").
4. **Multiple sweeps.** Sensors sweep on a refresh interval; a fast target can cross a
   covered bin between sweeps. Confidence should build over consecutive empty sweeps.

**The elegant refinement — shrink, don't drop.** On *partial* coverage, don't delete the
track: carve the covered (and disproven) area out of its uncertainty region. "Not in the
covered slice → it's in the uncovered remainder." Over successive sweeps the region
collapses (drop) or you re-detect. This is real track-management (negative-information
existence updates) and matches the "limited information without false ghosts" goal better
than either a hard ghost or a hard vanish — but it needs a per-contact uncertainty region
as first-class state.

**Why deferred:** needs new per-contact state (`a_max` bound, uncertainty region), lives
in the decay loop (separate insertion point from Options 1/2), respects detection
thresholds, and is only safe-and-strong for low-`a_max` contacts. A reasonable first cut
would restrict it to asteroids/wreckage where `a_max ≈ 0` and the region is unambiguous.

---

## 5. How the options combine

They are **not** mutually exclusive — they act at different insertion points:

- Options 0/1/2 are **despawn-triggered** (event-driven, in `detonate()` / future death
  hooks). They use ground-truth "this entity is gone."
- Option 3 is **sensor-triggered** (continuous, in the decay loop). It uses evidence of
  absence and needs no event.

A mature system would run **both layers at once**: Option 1 (or 2) instantly clears
*despawned* entities the host has truth about, while Option 3 continuously prunes
*everything else* that sensor coverage can disprove (evaded targets, off-sensor kills,
mis-correlations) and *shrinks* the uncertainty of what it can't yet disprove. The
display-layer age-fade (§2) sits under all of them as the honesty backstop for whatever
remains. In short: **truth-purge (1/2) + evidence-purge (3) + honest fade — layered, not
chosen.**

The natural progression:
1. Age-fade + age readout *(shipped)* — stop the display from lying.
2. Option 1 default *(shipped, behind debug menu)* — kill despawn ghosts cheaply.
3. Option 2 *(shipped, behind debug menu)* — opt-in fog fidelity when wanted.
4. Generalize 1/2 to ship deaths (where the omniscience trade-off actually bites).
5. Option 3 for ballistic contacts, then maneuvering ones with the shrink-region model.

---

## 6. Current implementation status

- **`DebugSettings`** (autoload, `scripts/debug_settings.gd`) — registry-driven global
  debug knobs. Deliberately bypasses the host/client packet so a local menu toggle
  changes host behavior immediately (fine for the sandbox; not authoritative). New knobs
  = one entry in `OPTIONS`; the menu auto-builds.
- **Top-bar Debug menu** (`terminal_display._build_debug_menu()`) — radio items built from
  the registry, write straight to `DebugSettings`.
- **Options 1 & 2 wired** — `Ship.purge_despawned_contact()` + `Ship._can_sense_point()` +
  `_contact_tombstones` + relay-loop suppression, called from
  `missile_controller.detonate()`. Default = **Purge all immediately**.
- **Option 3** — menu item present but maps to no-op (falls back to timeout); design only.
- **Signature-bleed merge** (`DebugSettings.signature_merge`, see §2) — `BLEND` /
  `NEAREST` toggle in the bin-aggregation loop of `_run_sensor_sweep`. Default = **`NEAREST`**
  (no-bleed; keeps the nearest object's clean signature and shadows the rest); flip to
  `BLEND` for the old bleeding behavior. Regression: `scripts/tests/test_signature_bleed.gd`.

### Known caveat (Option 1/2)
`queue_free()` defers actual deletion to frame end, so a ship whose sensor sweep runs
*after* the purge but *in the same frame* can briefly re-detect the still-present body and
re-add the contact (correlation doesn't check tombstones, only the relay does). It then
dead-reckons normally until the 20 s timeout. Rare (sweeps are refresh-gated) and
self-limiting; if it matters, extend the tombstone check into the correlation loop.
