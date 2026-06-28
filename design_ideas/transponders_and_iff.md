# Transponders, Beacons, and IFF

This document outlines the conceptual differences and synergies between the physical sensor tracking (IFF) and the active radio broadcasting (Transponders) systems in Project Deep Space.

## 1. Sensors & IFF (Physical Reality & Secure Identity)

*   **How it works:** Sensors actively (radar/lidar) or passively (heat/EM) detect physical objects in space. Once you get a high-resolution lock on a contact, your combat computer attempts a secure cryptographic handshake (IFF).
*   **Truthful:** IFF is cryptographically hard to spoof. If a ship has your faction's crypto tags, they are verified friendly. If they don't, they are unknown or hostile.
*   **Limitation:** You must physically detect the ship with sensors first. If a ship is running "cold and dark" (low heat, no EM emissions), you won't see them on sensors until they are very close.

## 2. Transponders (Radio Broadcast & Public Claims)

*   **How it works:** An active, omnidirectional radio broadcast sent via the ship's `comms` component over open frequencies. It tells anyone listening: *"Here is who I am, and here is where I am."*
*   **Configurable & Public:** Any ship within comms range with powered comms can receive this signal. The broadcasting ship can choose what data to include (Name, Location) or turn the transponder off entirely ("running dark").
*   **The Flag:** *Future expansion.* In the future, transponders will be complemented with the "Flag" the ship is sailing under (e.g., civilian, corporate, specific pirate faction, military). This is a public declaration of allegiance, which may or may not match their secure IFF tag.

## 3. Complementary Synergy

The beauty of the system comes from how these two layers interact:

*   **Beyond Visual Range (BVR):** A transponder signal can be picked up from 100km away (Comms range), while physical sensors might only reach 40km. A pilot can pick up a distress beacon (SOS) and follow it long before they can physically see the ship on sensors.
*   **Sensor Correlation:** If your sensors detect an unknown physical contact at `(X, Y)`, and your comms array receives a transponder broadcast claiming to be *"Cargo Hauler Bob"* from `(X, Y)`, your combat UI will merge them: the blip becomes labeled as "Cargo Hauler Bob".
*   **Deception & Piracy:** A pirate ship might broadcast a fake transponder ("Help, I'm a stranded civilian!") to lure you in, while hiding their exact location. This forces you to close in and search. Once you find them and resolve their physical ship, your computer's secure IFF handshake will fail, revealing them as hostile!
*   **Surrender & Compliance:** A ship signaling surrender might light up their location and broadcast their name to ensure they aren't accidentally fired upon, proving compliance to authorities.
