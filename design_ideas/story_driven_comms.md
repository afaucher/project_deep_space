# Project Implementation Plan: Networked Dialogue & Identity Systems

**Target Engine:** Godot 4.4.1 (GDScript-heavy architecture) 

**Core Tool:** Dialogue Manager (Nathan Hoad) 

---

## 1. Project Objectives & Architectural Scope

The objective of this project plan is to integrate the `Dialogue Manager` plugin into *Project Deep Space* to support tactile, submarine-esque communication loops across independent player-controlled ships. The system must cleanly manage the mechanical tension between deep-space isolation, unknown sensor blips, and networked, server-authoritative story progression.

### System Design Rules:

* 
**Decentralized UI Execution:** The actual display of dialog text, character portraits, and UI interactions runs strictly client-side on an individual player’s machine.


* 
**Server-Authoritative Impact:** Any structural changes to the world state (spending currency, dropping defense grids, updating faction standing) requested via a dialogue selection must be routed through server validation.


* 
**Hull-Locked Progression:** Every player's ship maintains its own individual ledger of contacts, encryption keys, and active radio routing paths.



---

## 2. Phased Development & Implementation Milestones

### Phase 1: Data Modeling & The Comms Ledger Architecture

The focus of this phase is establishing the underlying custom data models in Godot using data-driven Resources. This separates an entity's dialogue state from its physical spatial node.

* **Milestone 1.1: Implement `NPCProfile` & `CommComponent**`
* Create `NPCProfile.gd` as a custom resource to store identity data (name, faction affiliation, disposition trackers, and their target `.dialogue` asset path).


* Create `CommComponent.gd` as a spatial child node attachable to physical ship or station hulls. It will act as the radio transponder, containing an array of active `NPCProfile` blocks representing characters currently aboard that hull.




* **Milestone 1.2: Build the Persistent `CommsLedger**`
* Write a ledger resource attached to each player ship script to track recognized entities.


## NOTE - Lets think through this
* Implement lifecycle identity tiers for contacts: **Public** (always viewable station sub-frequencies), **Ephemeral** (intercepted pirate frequencies that wipe out when changing sectors), and **Vouched/Cryptographic** (hidden sub-channels locked behind progression keys).





### Phase 2: Interface Presentation & Dual-Balloon Architecture

Dialogue Manager parses text content into a "Dialogue Balloon". To capture both intense radio chatter and calm station trading without breaking immersion, two separate UI representations must be built.

* **Milestone 2.1: UI Type A – The Physical Comm Console Panel**
* Design a dedicated screen interface inside the ship layout. When interacted with, it queries the ship's sensor array for any `CommComponent` nodes inside physical radio range.


## NOTE - Maybe flip this - person first - ship as metadata

* Selecting a ship/station target lists all active `available_npcs` aboard. Selecting a profile triggers a comprehensive UI layout rendering nested conversational options, deep-space text readouts, and player choice forks.




## NOTE - I couldn't validate this design - it seemed reasonable?
### Phase 3: Network Layer & Server-Authoritative Mutations

Because `Dialogue Manager` is completely stateless, it relies on external code to execute mutations (`set` and `do` commands within `.dialogue` scripts). In a multi-ship environment, this requires a strictly managed RPC layer.

* **Milestone 3.1: Write the `NetworkCommHandler` Bridge**
* Equip each player hull with a `NetworkCommHandler` node to act as an RPC bridge.


* When a player confirms a selection inside a local `.dialogue` block that alters world state (e.g., `do StationAI.open_hangar()`), the client-side dialogue system calls `NetworkCommHandler.request_server_mutation()`.


* The server receives the request, runs validation checking if the player is in range and has the necessary resources/credentials, and fires the global world modification to all peers.




* **Milestone 3.2: Multi-Client Inbound Broadcast System**
* Configure the server-side AI script so that when specific triggers occur (e.g., an Ashen Scourge raider targets a player group), the server pushes a targeted RPC broadcast out to all player IDs within that spatial sector.


* Receiving clients capture the event hook and display the dialogue via their local, minimalist HUD Intercept Overlay.





---

## 3. Core Gameplay Mechanics Integration Scope

## NOTE - None of these are in scope yet.

To properly evaluate the success of the system, the project plan must natively support three signature gameplay mechanics:

### 1. Blind Calling & Transponder Spoofing

* 
**The Behavior:** If a target appears only as an unresolved sensor signature ("Unknown Contact Alpha"), players cannot directly choose an NPC from their console. They can only initiate an unencrypted, broad-spectrum outbound hail.


* 
**The Gameplay Loop:** The `.dialogue` script defaults to a generic baseline tree offering raw interactions ([State Identity], [Demand Cargo Drop], [Request Access]). Hostile factions or corporate stealth operatives can execute code mutations within the dialogue file to run spoofed transponder responses, lying about their true faction to ambush unsuspecting player captains.



### 2. The "Ladders & Referrals" Progression Network

* **The Behavior:** Hidden or specialized NPCs cannot be called or discovered initially. Players must navigate a social topology to gain secure routing keys or specific frequencies.


* **The Scenario Matrix:**
1. A player contacts public "Station Docking Control" via the local Comm Panel to ask about structural modifications.


2. A conditional script check evaluates if the player's hull type or wallet threshold qualifies.


3. If approved, Dialogue Manager executes an inline mutation (`do ledger.unlock_contact("Vance")`).


4. A new persistent entity resource packet (`Chief Mechanic Vance`) is injected directly into the player's personal ship ledger, providing direct sub-channel routing access for future visits.





### 3. Ship-to-Ship Data Beaming

* 
**The Behavior:** Because player ledgers are strictly client-side and locked to their independent hull, information asymmetry naturally arises.


* 
**The Gameplay Loop:** To coordinate tactics, a player who has unlocked a rare contact (such as a black-market broker or a high-tier mechanic) can physically target a friendly ally ship and choose a dedicated context action: [Beam Contact Data]. This initiates a secure peer-to-peer data serialization across the network, injecting the corresponding cryptographic routing profile straight into the ally’s local `CommsLedger`.



---

## 4. Testing, Validation, and Tooling Strategies

To guarantee stability without relying on a full multiplayer session setup for every minor code fix, the implementation will integrate directly into the existing project workflow:

* 
**Headless Test Suite Integration:** All data handlers, ledger serialization methods, and RPC validation hooks will be written as test cases inside `scripts/tests/*.gd`. This ensures the automated PowerShell test runner (`test_runner.ps1`) validates the networking and ledger pipelines on every development push.


* 
**Isolated Mutation Mocking:** Use `Dialogue Manager`'s native developer testing view to mock the game's global Autoload variables. This allows designers to verify branching conversation text choices and inline code mutations without spawning a physical ship inside space sectors.