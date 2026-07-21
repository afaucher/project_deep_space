# Hull Shape Consistency

## Current State
The game currently uses inconsistent rendering paths for ship hull outlines depending on the UI surface and the entity being viewed:

- **Nav Panel (Contacts):** Uses `ShipSilhouette.compute()`, which performs a detailed boolean union of all component rects, preserving all concave corners (L-shapes, U-shapes) for a highly accurate representation of the ship's grid.
- **Nav Panel (Own Ship):** Uses a `Geometry2D.convex_hull()` shrink-wrap of the component extremities.
- **Engineering Panel:** Previously used `ShipSilhouette.compute()`, but was temporarily changed to match the `convex_hull` of the Nav Panel to maintain visual consistency for the player's own ship.
- **Physics Engine:** Uses a `ConvexPolygonShape2D` based on the convex hull of the ship components (as Godot's 2D physics engine requires strictly convex shapes for stable collision).

## Proposed Unification

Ideally, we want ship hull outlines to be visually consistent across all surfaces (Nav Panel, Engineering, Contacts, and actual Physics collision boundaries).

### The Concavity Requirement
For ships with significant concavity (e.g., U-shaped freighters, hollow rings, or L-shaped defensive emplacements), it is extremely important that we use the tight-fitting, true shape of the ship, or a smoothed representation that preserves concavity, rather than a generic convex hull that draws a straight line over negative space.

### The Technical Path Forward
In order to safely move all rendering *and* physics over to the detailed concave shape (the true `ShipSilhouette`):

1. **Convex Decomposition:** We need to implement or utilize a convex decomposition algorithm (e.g., Godot's `Geometry2D.decompose_polygon_in_convex()`).
2. **Physics Hookup:** We must rewire the `ship.gd` physics generation path. Instead of creating a single `ConvexPolygonShape2D` from the convex hull, we must break the detailed concave polygon into multiple convex sub-polygons, and attach multiple `CollisionPolygon2D` or `ConvexPolygonShape2D` nodes to the ship's physics body.
3. **UI Unification:** Once physics supports true concave boundaries via decomposition, all UI panels (Nav Panel own ship, Nav Panel contacts, Engineering) can safely revert to drawing the detailed `ShipSilhouette`, achieving full consistency without breaking collision behavior.
