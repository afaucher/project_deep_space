# Ship Layout Reference

## Coordinate Visualization Key

All coordinates: `Rect2(x, y, w, h)` → occupies `(x, y)` to `(x+w, y+h)`.
Forward = +X, Starboard = +Y.

---

## Frigate (MEDIUM Tier)

```
Hull frame: 4-segment box with center gap
  hull_fwd:  (15,-15) to (30, 15)   # 15×30 forward section
  hull_port: (-15,-15) to (15, -5)   # 30×10 port wall
  hull_stbd: (-15,  5) to (15, 15)   # 30×10 starboard wall
  hull_aft:  (-30,-15) to (-15, 15)  # 15×30 aft section

Center gap: x = -15 to 15, y = -5 to 5 (10-unit wide corridor)

Internals (in center gap):
  reactor_core:      (-15,-5) to (-5, 5)    # aft-center
  comms_array:       (  5,-5) to (10, 0)    # fwd-port
  omni_main:         ( -5,-5) to ( 0, 0)    # center-port
  omni_short_hi_res: (  0,-5) to ( 5, 0)    # center-port
  passive_em:        ( -5, 0) to ( 0, 5)    # center-stbd
  omni_collision:    (  0, 0) to ( 5, 5)    # center-stbd

External mounts:
  dir_high_res:      (30,-2.5) to (35, 2.5) # bow tip sensor
  engine_main:       (-35,-10) to (-30, 10)  # stern engine
  hp_fwd_laser:      (30,-7.5) to (35,-2.5) # bow laser
  hp_fwd_tube_1:     (30, 2.5) to (45, 7.5) # bow missile
  hp_port_laser:     (-5,-20)  to ( 0,-15)   # port broadside
  hp_stbd_laser:     (-5, 15)  to ( 0, 20)   # stbd broadside
```

---

## Destroyer (HEAVY Tier)

```
Hull frame: 4-segment box with center gap + armored reactor box
  hull_fwd:  (22,-22) to (44, 22)   # 22×44 forward section
  hull_port: (-22,-22) to (22, -6)   # 44×16 port wall
  hull_stbd: (-22,  6) to (22, 22)   # 44×16 starboard wall
  hull_aft:  (-44,-22) to (-22, 22)  # 22×44 aft section

Center gap: x = -22 to 22, y = -6 to 6 (12-unit wide corridor)

Reactor armor box (4 walls inside center gap):
  hull_core_top:  (-13, -9) to (13, -5)   # 26×4 top wall
  hull_core_bot:  (-13,  5) to (13,  9)   # 26×4 bottom wall
  hull_core_port: (-13, -5) to (-12, 5)   # 1×10 port wall
  hull_core_stbd: ( 12, -5) to ( 13, 5)   # 1×10 stbd wall

Box interior: (-12, -5) to (12, 5) = 24×10
  reactor_fwd: (  0,-5) to (12, 5)   # forward reactor
  reactor_aft: (-12,-5) to ( 0, 5)   # aft reactor

Sensors/comms (inside hull_fwd):
  omni_main:         (23,-5) to (28, 0)
  omni_short_hi_res: (28,-5) to (33, 0)
  passive_em:        (23, 0) to (28, 5)
  omni_collision:    (28, 0) to (33, 5)
  comms_array:       (33,-3) to (39, 3)
  dir_high_res:      (44,-2.5) to (49, 2.5)  # bow tip

Forward weapons (touching hull_fwd at x=44):
  hp_fwd_laser:  (44,-2.5) to (49, 2.5)   # center laser
  hp_fwd_tube_1: (44, 2.5) to (59, 7.5)   # stbd tube
  hp_fwd_tube_2: (44,-7.5) to (59,-2.5)   # port tube

Broadside tubes (hanging off hull at y = ±22):
  Port tubes:  top edge at y = -22 (touching hull_port)
    tube_1: (15,-37) to (20,-22)
    tube_2: ( 2,-37) to ( 7,-22)
    tube_3: (-11,-37) to (-6,-22)
    tube_4: (-22,-37) to (-17,-22)
  Stbd tubes: top edge at y = 22 (touching hull_stbd)
    (mirror of port)

Stern:
  engine_main: (-48,-10) to (-38, 10)   # 10×20 engine
  hp_aft_pd:   (-53,-2.5) to (-48, 2.5) # PD behind engine
```

---

## Light Attack Craft (LIGHT Tier)

```
Hull frame: 2-segment continuous hull
  hull_fwd: ( 2,-5) to (18, 5)   # 16×10
  hull_aft: (-14,-5) to ( 2, 5)   # 16×10 (touching at x=2)

Internals (inside hull overlap zone):
  reactor_core: (-6,-3) to (2, 3)   # inside hull_aft
  comms_array:  ( 2,-2) to (6, 2)   # at hull junction

External:
  omni_fwd_fc:    (18,-2.5) to (23, 2.5) # bow sensor
  hp_fwd_laser:   ( 8,-7.5) to (13,-2.5) # port laser
  hp_fwd_missile: ( 8, 2.5) to (18, 7.5) # stbd missile
  engine_main:    (-20,-5)  to (-14, 5)   # stern engine
```

---

## Cargo Shuttle (LIGHT Tier)

```
Hull frame: 2-segment
  hull_fwd: (15,-7.5) to (30, 7.5)  # 15×15 nose
  hull_bay: (-20,-9)  to (15, 9)     # 35×18 cargo hold (touching hull_fwd at x=15)

Internals:
  reactor_core: (-15,-4) to (-5, 4)  # inside hull_bay
  comms_array:  (  0,-2.5) to (5, 2.5) # inside hull_bay

External:
  omni_main:    (20,-2.5) to (25, 2.5) # bow sensor (touching hull_fwd)
  engine_main:  (-26,-8) to (-20, 8)   # stern engine (touching hull_bay)
```
