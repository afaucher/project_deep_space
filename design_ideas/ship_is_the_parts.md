There are a couple of things I expect us to want to do:
1. Build multiple ship designs with different loadouts
2. Configure individual components, like swap missles between laser heads and dazzlers (blind sensors).
3. Operate unconventional ships like sensor drones (that have no weapons), or ammo ships, or PD-only bouys.
4. Operate advanced configurations like dual-reactor, dual-engine, weaponless, etc.

To do these, the definition of Ship needs to be decoupled from 'ship-wide' in some cases and moved to 'from components'.

For example - a dual reactor ship probably doesn't need both at the same time, and we don't model power consumption specifically - but the ship would have 'power' if only a single reactor was live.  We can think of 'power' as a property that we sum from components, two different reactors were providing power, but now one is, and one is enough.

This is the same thing we do for EM profile and heat in reverse.

It also means we need to move 'ship baseline load' to 'component baseline load'.

There are a couple different parts to this:
1. The physical position of the component and its extents, hardpoint definitions
2. The configuration of the component (ex: powerful engine, high EM engine, etc.)
3. The current state of the component (ex: ammo remaining, powered-on, etc)
4. How those components contribute to the ship individually or together
5. The total volume of the component and relative dimensions (square, big, small, long, etc)

Existing example
In the player ship the directional sensor node is pinned to the box on the nose of the ship with a hardpoint aiming out.  That supports a single sensor.  However the central sensor node, which has the omnidirectional hardpoint, is centered on the ship.  Is a larger square box.  And it supports multiple sensors.

From the ship design perspective this raises a bunch of questions such as:
* What is the logic that determines how components can be configured and their physical space.
* What should users understand about how these things fit together.
* How do we design and build components that are logically consistent.

Another example:
A missile is also a ship.  It has an engine, a reactor a sensor and a laser.  How does the power, mass, acceleration, EM and heat behave relative to the larger versions in the player ship?  Does the relationship make sense?  How does it scale to larger units?

In some worlds - we might say something like 'missles are too small for reactors, so we use a big capacitor instead' which explains the power density difference.

The most straitforward way to address this I can see is for each component type, decide 'classes' of the component and for each class have a set of physical properties and performance characteristics.  Across this range it should make sense.  Like 'acceleration drops off a cliff as mass increases' - 'heat output per second scales with some exponent' etc.  In some cases there is a natural correlation - launchers for larger missles should be larger.

Another complimentary approach is to validate on the ship design side.  Each ship design has to meet a baseline set of performance metrics to be valid.  This would cover each component to its class as well.

So you could say, a small missle launcher needs to be 3x3x7 cells, but any larger and it gets more capacity of X per cell.
* The validator should validate the component is at least that dimension on some axis.



For the many to one or one to many - the easiest solution is to just avoid it for now.  Split the main 'sensor dome' into multiple parts.
