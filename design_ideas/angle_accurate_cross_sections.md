# Angle-Accurate Radar Cross-Sections

## The Concept
Currently, the radar `cross_section` of a ship is a static scalar value (calculated once as the minimum of the width or length of its bounding box). This means a ship presents the exact same radar signature regardless of its orientation relative to the sensor.

Making the cross-section **angle-accurate** would mean the radar signature dynamically changes based on the relative angle between the sensor and the target.

### The "Broadside" vs "Head-On" Profile
- A ship viewed head-on presents a very narrow silhouette (small cross-section). 
- A ship viewed from the side (broadside) presents its entire length to the radar waves (massive cross-section).

## Implementation (Engine Side)
Instead of just calling `get_signature()` which returns a static value, the sensor would pass its location: `get_signature(sensor_global_pos)`.

1. The target ship calculates the angle between its own forward vector and the incoming radar wave.
2. It mathematically projects its 2D physical bounding box (or its individual components) onto a 1D line perpendicular to that angle.
3. If the angle is 0° (head-on), the returned cross-section is exactly the ship's width.
4. If the angle is 90° (broadside), the returned cross-section is the ship's entire length.
5. Intermediate angles yield a cross-section between the two extremes.

## Gameplay Impact (Stealth & Tactics)
Players could actively use orientation to hide from radar:
- If a player knows an enemy sensor drone is sweeping them, they could point their nose directly at it to minimize their cross-section.
- This would actively reduce the range at which they can be locked onto, or make their radar blip smaller.
- If they drift sideways, they would "flare up" on the enemy radar, giving away their position from further away.

## Client UI Impact
The Nav Panel would still only receive a single float value for `cross_section` and draw a circle.
- The UI circle would dynamically grow and shrink as the enemy ship turns relative to the sensor.
- Because it remains a circle, the "fog of war" is preserved—you don't see their exact orientation, but you can infer they are maneuvering if their blip suddenly gets fatter or thinner.

## Secondary UI Effects
- **Cross-Section Oscillation Graph**: Since a spinning or rotating ship would constantly cycle between its minimum and maximum cross-section profiles, the reported value would oscillate. This oscillation could be graphed over time on the Engineering or Nav panels (just like Heat and EM), allowing skilled operators to infer the rotational speed and behavior of a target just by studying the sine wave of its radar return.
