# Dynamic Ship-Projected Zones

## Core Concept
In Deep Space, "zones" (like port authority bounds, speed limits, or navigation corridors) are not abstract, disembodied regions of space. Instead, they are entirely driven by physical `Ship` entities projecting them via a `PortZone` parameter. 

This leads to a highly dynamic, emergent environment: **because zones are anchored to a physics body, the zone itself is a physical object that can be moved, bumped, or destroyed.**

## Emergent Behaviors
- **Kinetic Zone Shifting:** If a freighter collides with a zone buoy or a beacon, the beacon's physical position is shifted. Because the boundary is drawn relative to the beacon, the entire zone marking instantly shifts on the HUD. The "law" moves with the buoy.
- **Dynamic Corridors (The Beacon Bridge):** Instead of calculating a static navigation roadmap, each beacon projects a `PortZone` with a specific visual style (e.g. `visual_style = "corridor"`) and a `link_to` parameter pointing to its neighbor. The HUD rendering draws a glowing bridge from the beacon's actual physical position to the target beacon's physical position. If either beacon is knocked off course, the road physically bends to connect them in real-time.
- **Mobile Zones:** A large capital ship or a mobile habitation platform can project its own authority zone. The zone travels with the ship, meaning "no fire" zones or "speed limit" zones can dynamically carve paths through space as the ship moves.

## Visual Customization (Aesthetics as Data)
Since zones are just data attached to a ship, they can carry customized `visual_style` tags that inform the Navigation HUD how to render them:
- **Default / Clean:** A standard, authoritative ring with clear demarcations (e.g., standard Port Authority).
- **Casino / Commercial:** The zone boundary isn't a solid line, but rather a ring of holographic advertisements, glowing markers, or flashy UI elements trying to draw ships in.
- **Industrial / Mining:** Strict hazard stripes, jagged lines, or warning colors that indicate heavy machinery or hazardous operations inside.

By treating the aesthetic of the zone as a simple style tag, the environment can feel incredibly varied without needing complex rendering logic for every unique station. The station just declares `"visual_style": "casino"`, and the HUD handles the rest.
