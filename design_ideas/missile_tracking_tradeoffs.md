# Missile Tracking and "Lost Lock" Behaviors

When a missile is fired, it relies on its internal active sensor (seeker) to track targets. Due to EW (Electronic Warfare), stealth maneuvers, or distance, the missile may occasionally lose its sensor lock (i.e., its active contacts array will no longer contain a valid target).

When a lock is lost, the missile controller must decide what to do. Below are different paradigms we can implement. In the future, these can be parameterized as part of ship/weapon configurations or passed to an AI optimizer.

## Approach A: Dumb-Fire / Fly Straight
**Behavior:** The missile locks its current heading and continues to burn its engine in a straight line until its fuel expires (15s) or it hits something organically.
* **Pros:** 
  * If it was already on a pursuit curve and the target simply went stealth (but didn't alter course), the missile's momentum and straight-line path might naturally intercept them or get close enough to re-acquire.
  * Very easy to dodge if you realize a missile is tracking you—simply jam it/go stealth and pull off to the side. 
  * Gives missiles a "dumb-fire rocket" fallback.
* **Cons:** 
  * If the target is distant and never acquired in the first place, the missile just fires off into deep space along the launcher's forward vector.

## Approach B: Seek Last Known Coordinate
**Behavior:** The launching ship passes the absolute coordinate `(x, y)` of the target at the moment of launch to the missile. If the missile has no active lock, it steers directly to that coordinate and detonates upon arrival.
* **Pros:** 
  * Missiles will reliably travel to the "engagement zone" where the target was last seen, giving their onboard sensors a chance to get close enough to re-acquire the lock mid-flight.
* **Cons:** 
  * Completely ignores the target's velocity. If the target is moving fast, the "last known coordinate" will be empty space by the time the missile gets there.
  * Results in missiles detonating on empty patches of space, which visually wastes laser warheads.

## Approach C: Dead Reckoning (Predicted Intercept)
**Behavior:** The missile receives the target's last known position and velocity. When lock is lost, the missile calculates where the target *should* be based on its last known velocity, and steers toward that predicted point.
* **Pros:** 
  * Highly lethal. The target must actively change their trajectory after going stealth; simply going dark while flying straight will still result in a hit.
* **Cons:**
  * Requires more complex prediction math in the fallback state.
  * Can make missiles feel overly "psychic" or oppressive to the player if their evasion relies purely on reducing signature rather than evasive flying.

## Approach D: Search Patterns
**Behavior:** When lock is lost, the missile flies to the last known position and begins a search pattern (e.g., spiraling outward or weaving).
* **Pros:** 
  * Maximizes the chance of the seeker sweeping over the target again.
  * Looks incredibly cool and advanced.
* **Cons:** 
  * Drains missile fuel quickly and requires complex steering logic.

---
### Config / Optimizer Ideas
In the future, we could have different *types* of missiles or AI loadouts:
- **Cheap Torpedoes:** Approach A
- **Hunter-Killers:** Approach D
- **Smart Missiles:** Approach C

AI controllers could evolve to select the best missile type based on the player's observed evasion tactics.
