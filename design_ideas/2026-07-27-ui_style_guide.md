# UI style guide — the console's visual vocabulary

**Status:** written 2026-07-27 from a playtest audit of every panel. Part
inventory, part decision record. The enforcing code is
`scripts/ui/ui_style.gd`; this file is the *why*.

The console grew one panel at a time over ~50 milestones, and every panel
invented its own heading. Nothing was wrong in isolation. Side by side they
read as six different programs. This is the inventory of what actually
differed, the small vocabulary that replaces it, and — the part that matters
more — which differences are **real** and must survive.

---

## 1. What the audit found

Counts are from a grep across `scripts/ui/*.gd` before any change.

### Headings: three levels, no rules

| Text | File | Size | Colour | Align |
|---|---|---|---|---|
| TACTICAL CONTACTS | contacts_panel:112 | default | `GREEN` | center |
| ENGINEERING DIAGNOSTICS | engineering_panel:265 | **16** | `(0.8,0.6,0.2)` | **left** |
| WEAPONS CONTROL | weapons_panel:60 | default | `RED` | center |
| COMMS & TRANSPONDERS | comms_panel:124 | default | `CYAN` | center |
| *(helm)* | — | **none** | — | — |
| *(navigation)* | — | **none** | — | — |
| *(sensors)* | — | **none** | — | — |
| HAILS | comms_panel:223 | default | `ORANGE_RED` | center |
| CONTRACTS | comms_panel:257 | default | `(1,.75,.2)` | center |
| LOCAL CONTACTS | comms_panel:271 | default | `CYAN` | center |
| CHAT: … | comms_panel:310 | default | `CYAN` | center |
| TARGETING COMPUTER | weapons_panel:105 | default | `ORANGE` | center |
| ENGINEERING LOG | engineering_panel:375 | default | **none** | **left** |
| Enemies / Alerts / … | contacts_panel:142 | default | none | **fold buttons** |

Three levels of heading were in use — panel title, section header, list
section — with no styling that distinguished them. `HAILS` and
`COMMS & TRANSPONDERS` are a child and its parent, drawn identically apart
from hue. Four panels have a title; three don't.

### The accent colour is stated twice and disagrees with itself

Every panel is framed by `terminal_display.gd` with a `StyleBoxFlat` carrying
a border colour, and then titles itself with a *separately chosen* colour:

| Panel | Frame border | Title colour |
|---|---|---|
| Contacts | `(0.2,0.4,0.2)` | `GREEN` = `(0,1,0)` |
| Weapons | `DARK_RED` | `RED` |
| Engineering | `(0.6,0.4,0.1)` | `(0.8,0.6,0.2)` |
| Comms | `(0.2,0.6,0.8)` | `CYAN` |

Same intent, two literals, four times. Nothing keeps them in step.

### Font sizes: eight values, no ramp

`11, 12, 13, 14, 15, 16, 20, 28` — with 11 used exactly once (the safety
status line) and 14/15 used once or twice each. No two panels agree on what
"small text" means.

### Rows: two treatments for the same object

A vessel drawn in the tactical list and the same vessel in the hails list:

- contacts_panel:270 — `border_width_left = 4`, colour = `Utils.contact_color`
- comms_panel:614 — `set_border_width_all(1)`, colour = `Utils.contact_color`

The colour rule is correctly shared (that was playtest A2's fix). The *shape*
is not, so a ship reads as a left-tabbed row in one list and a boxed card in
the other.

### Padding

Outer panel frames are uniform (`terminal_display._add_margins`, 3px on all
four sides) — uniform, but too small to read as an inset, so text sat flush
against the frame. Inside, hail rows set a 4px content margin, contact rows
set none, and the engineering log sat against the panel edge. Meanwhile every
`CheckButton` carried its own internal padding, so "Broadcast Active" looked
indented and the ship name directly above it did not.

### Folding

`contacts_panel` builds every section as a toggle `Button` with a `(+)`/`(-)`
affordance. The comms panel's three sections — HAILS, CONTRACTS, LOCAL
CONTACTS — are plain labels that cannot fold, though they hold exactly the
same kind of content: an unbounded list.

---

## 2. The vocabulary

Four heading levels, one font ramp, one padding scale, one accent per panel,
one row shape, and no empty-state text.

### 2.1 Heading levels

| Level | Use | Style |
|---|---|---|
| **Panel title** | Names a whole console panel. Exactly one per panel. | `FONT_TITLE`, centered, panel accent, followed by a separator |
| **Section header** | A division inside a panel. | `FONT_BODY`, left, accent dimmed to 70% |
| **List section** | A section whose content is an unbounded list. | Section header **plus** a fold affordance |
| **Body / detail** | Everything else. | `FONT_DETAIL`, inherited colour |

The distinction that was missing: **a section holding a list folds; a section
holding a fixed readout does not.** That is a functional rule, not a
decorative one — folding exists so a long list can be gotten out of the way,
and a two-line readout has nothing to get out of the way.

### 2.2 Font ramp

```
FONT_DETAIL   14   list detail lines, log text, secondary readouts
FONT_BODY     15   section headers, default prose
FONT_TITLE    18   panel titles
FONT_READOUT  18   numerals meant to be read at a glance (helm gauges)
FONT_BANNER   22   transient full-width banners (zone crossing)
FONT_ALERT    30   the overheat warning
```

Canvas text — `draw_string` on a map, dial, chart or sensor scope — is its own
family, legitimately smaller because it overlays graphics and competes with
dozens of sibling labels for the same pixels:

```
FONT_CANVAS_TINY   12   chart legends, sensor bin labels, per-contact detail
FONT_CANVAS_SMALL  14   map contact labels, contract markers
FONT_CANVAS        16   compass ticks, scale bar, speed numeral
FONT_CANVAS_LARGE  18   world-coordinate readout, sensor module title
```

Old 11, and the canvas pair 9/10, are retired — 9 vs 10 was a distinction
nobody could see. `FONT_TITLE` and `FONT_READOUT` share a value and stay
separately named: they answer different questions and one may move alone.

**The ramp does not act alone.** Most labels in this codebase carry no size
override at all and render at the engine default. That default is now set
explicitly in `project.godot`:

```
[gui]
theme/default_font_size=18
```

Bump one without the other and the scale silently re-splits into two — a
themed label and an unthemed one beside it stop matching. They moved together
(+2 across the board) and must keep moving together.

### 2.3 Padding

```
FRAME_PAD_H  8   left/right inside a panel frame
FRAME_PAD_V  4   top/bottom inside a panel frame
INNER_PAD    6   a nested box (transponder block, chat pane, hail banner)
```

Panel frames previously carried a flat 3px on all four sides — enough to keep
a border off the glyphs, not enough to read as an inset. The visible
consequence: free-standing text (the engineering log, a ship name) sat flush
against the frame, while anything inside a control with its *own* padding —
every `CheckButton`, e.g. "Broadcast Active" — appeared correctly indented.
Two different left edges in the same column.

Horizontal is the one that matters, because it is what a reader's eye aligns
against; vertical stays tight because the console is dense on purpose. A
nested box adds `INNER_PAD` rather than another full `FRAME_PAD_H` — it is
already inside a frame that paid once.

Rows are exempt: `row_style` carries its own 4px content margin, which lands
them at 12px from the panel edge, deliberately inboard of the section headers
that label them.

### 2.4 Empty states

**There aren't any.** An empty list renders as nothing — no "(no vessels)",
no "(no active contracts)". The section header is already present saying what
would be there, and a placeholder line costs exactly as much vertical space as
a real entry while carrying none of the information.

### 2.5 Panel accent

One colour per panel, declared once in `UIStyle.PANELS`, used for **both** the
frame border and the title. The frame background stays per-panel (it carries
the same identity more quietly).

Accents are unchanged in spirit from what each panel already had — this is a
deduplication, not a re-skin.

**A panel is framed exactly once, by its container.** Every panel is a plain
`Control`; `terminal_display` wraps each in a `PanelContainer` and applies
`UIStyle.panel_frame()` there. A panel must not frame itself.

`weapons_panel` did, and it was the only one — it extended `PanelContainer`
and set its own stylebox *inside* the container that was already framing it.
Two nested frames means two backgrounds (the inner one lighter) and two border
rules offset by the padding, which is the recipe for a bevel: it was the only
panel on the console that looked 3D. At the old 3px frame margin the two
frames were nearly coincident and it read as a slightly odd edge; raising
padding to 8px pulled them apart and made it obvious.

### 2.6 Row shape

One helper, `UIStyle.row_style(color, selected)`:

- `border_width_left = 4`, in the entity's colour
- background `Utils.ROW_BG` / `ROW_BG_SELECTED`
- 4px content margin on all sides

The tactical list's treatment wins over the hails list's box, for a reason
worth recording: **the left tab scales and the box doesn't.** A column of
boxed cards spends a pixel of border on every edge of every row and reads as
a grid; a column of left-tabbed rows reads as one list with a colour gutter,
which is what both of these actually are. It also degrades better — twenty
tabbed rows still look like a list, twenty boxes look like noise.

---

### 2.7 Naming an entity

Not chrome, but the same class of problem, so it lives with it —
`Utils.entity_label()`:

```
TRK-068                                  nothing known but the return
TRK-815 "Ironhold" — SOVEREIGN_DRIFT     identified and flagged
TRK-402 [WRECKAGE]                       not a vessel; the class IS the news
```

Two defects behind this.

**The bracket lied.** Every row read `<name> [UNIDENTIFIED VESSEL]`. That
bracket is `classify_contact()`'s output, and classification has no notion of
identity — it returns `UNIDENTIFIED VESSEL` for anything powered without an IFF
crypto handshake, *including a station broadcasting its name and flag at you*.
So the label contradicted the name printed beside it, on every contact,
permanently. Where the contact is a vessel the **flag** is the useful
qualifier; where it isn't, the classification is the entire point and stays.

**The track id was the only shared identifier, and only some surfaces showed
it.** Tactical contacts said `Ironhold`, hails said `TRK-815 "Ironhold"`, the
targeting computer said `Target: TRK-815`. Three rows, one ship, no way to tell.
This is exactly the correlation problem CLAUDE.md documents for debug logs,
happening in the UI. Every label now leads with the track id.

That second change relaxed an M52 assertion in `test_contacts_panel_sos` which
required the track id to be *absent* once a caller's name was known. The
complaint behind that rule ("the row shows TRK-xxx instead of a real name") is
still satisfied — the name is right there. If leading with the name turns out
to matter more, flip that assertion; `entity_label` is the single place to
change.

**Also gone: `— dark`** for a flagless vessel in the hails list. The word
appeared nowhere else in the game, and a bare `TRK-068` already says we hold no
identity for it.

### 2.8 Fix the name, don't map around it

The wire constant `UNREPORTED` was reaching the player as *"Standing:
UNREPORTED -- demanding a stop of Patrol Alpha"* — a tier name naming a cause
that has nothing to do with transponders, because not-reporting had stopped
being the category and become one of several causes of the yellow tier.

The first fix was a display mapping, `Utils.standing_display()`, translating
the wire value to the tier name for the UI. It worked, and it was the wrong
shape: it left two names for one thing and put the honest one only on screen.

**Both are gone. The constant is `CAUTION` now** (2026-07-27), so the wire
value *is* what the player reads, and `standing_display()` — which the rename
made the identity function for every input — went with it.

Worth stating as a rule, because the alias was not free while it lasted. Two
names for one string caused two bugs in a single day: `ChallengeLeaf` read a
contact's caution standing (produced by a warrant the patrol had itself just
posted) as "still not reporting" and re-demanded identification forever; and a
hull broadcasting with Share Name off was invisible as a distinct case, because
"withholding its name" and "holding a warrant" collapsed into the same word.
Both readings were defensible — that is exactly what an alias buys you.

If a value ever again needs a different name on screen than on the wire, the
honest fix is the same one: **change the name.**

### 2.9 State, not inputs — counter-detection

Every tactical contact row carried `Our Emit: 57.3 | Det Limit: 38.2 km`. Two
raw inputs to a question neither of them asked out loud — *can that ship see
me?* — leaving the player to compare two numbers in their head, per contact,
continuously, forever.

It is now one two-word state on the one contact you're actually working, in
the targeting computer where the rest of the "what am I dealing with" readout
lives:

```
PASSIVE EXPOSED     PASSIVE CLEAR
```

Nothing else — no label prefix, no supporting figures, no third state. The
quantity is **counter-detection** (doctrine's word: the range at which an
adversary picks *you* up, as distinct from your own detection range on them),
and that name stays in the code and out of the UI. `PASSIVE` is the
load-bearing word on screen: this is the passive-EM gate only, and the line
says nothing about an active sensor lock.

Three things were deliberately cut, recorded here so they don't creep back:

- **The `Counter-detection:` prefix.** The panel has exactly one line about
  being seen. It does not need to introduce itself every frame.
- **The range figures.** They explained *why*, at the cost of turning a
  glanceable state into a sentence to be read.
- **A third state, `SILENT`.** `Utils.counter_detection` still distinguishes
  it and the distinction is real — under the passive noise floor a hull is
  invisible at *any* range, because inside the falloff reference distance
  there is no falloff at all, so it cannot be seen even at zero range. But
  that is a **prediction**, and this line answers about the contact in front
  of you *now*, where silent and merely-out-of-range are the same answer.
  `silent` stays on the returned dict for anything that wants to reason ahead.

That sub-floor case is still worth having in the model, because the old
per-row version got it wrong: it computed `emit * (10000/15)` unconditionally
— both constants hand-typed — and reported a confident "detectable to 6.0 km"
for a ship that was in fact undetectable at any range. Exactly backwards for a
stealth readout.

`Utils.counter_detection()` owns the rule and mirrors `ship.gd`'s passive-EM
gate. `test_counter_detection.gd` rebuilds that gate from `ship.gd`'s own
constants and demands the same verdict at every range — because a stealth
readout that has drifted from the sim is confidently wrong, and invisible
until it gets someone killed.

## 3. Differences that are real — do not unify these

The point of the exercise is not that everything should look the same.

- **Panel accent hue.** Weapons is red, engineering is amber, comms is blue.
  This is wayfinding on a dense screen — the player finds the panel by colour
  before reading a word of it. Keep.
- **Entity colour on a row.** `Utils.contact_color` is *semantic* — it encodes
  standing, and it must override panel accent. A hostile contact is red in a
  green-accented panel. That is the whole point of A2's fix.
- **The overheat banner and the zone banner** are deliberately louder than
  everything else (28pt and 20pt). They are interrupts, not content.
- **Helm's numerals.** The throttle/velocity readouts are instrument faces,
  read peripherally during flight. They stay at `FONT_READOUT`, larger than
  any body text.
- **The hail banner's red fill.** A demand landing on your ship is the one
  place a full-bleed alarm colour is earned.

## 4. Judgment calls made here, and how to reverse them

- **Every panel gets a title, including helm, navigation and sensors.** The
  playtest called out their absence directly. Navigation's rides the existing
  floating control strip rather than taking a title bar of its own — the map
  is the panel, and vertical space there is the most expensive on the console.
  If any of the three proves unwanted, it is one `UIStyle.panel_title()` call
  to delete; nothing depends on it.
- **The two modal overlays** (help, controls remap) had byte-identical frame
  code and now share `UIStyle.modal_frame()` under a neutral blue accent. They
  are not console panels and deliberately don't borrow a panel's hue.
- **The comms panel's three sections gained fold buttons.** They hold lists,
  so by §2.1 they fold. This makes the comms panel's structure legible at a
  glance for the first time, but it does add three clickable controls to a
  panel that had none.
- **Sizes 11/14/15 were rounded to the ramp**, which moves a handful of
  labels by 1–2px. Deliberate: an eight-value scale with single-use entries
  isn't a scale.

## 5. What this does NOT cover

Layout — which panel sits where, how much space each gets, the split ratios.
That is a separate and much larger question, and none of it is touched here.
This guide is only about how a component announces itself once it has a box
to live in.
