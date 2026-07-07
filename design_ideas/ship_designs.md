# Goal
Once done, commited and pushed with a clean repo our next task:

We drafted a range of ship designs.  Lets start thinking about how we configure ships today and what changes would we need to be able to scale up to build and validate this many ships.

We want to identify all the aspects of ship handling:
Turn speeds
Acceleration 
Top Speed

We want to look at ship performance in our tactical analysis setup:
Bigger ships should consistently win
Smaller ships should be able to avoid combat
Smaller ships should struggle to damage bigger ships
*NOTE* If we build this, we need to figure out how to make our sweeps more parallel.  They take >30m to run now.  Adding lots more cases make this impossible.

We want to try to establish component tiers with meaningful & consistent physical properties
PD lasers are smaller, short range with higher fire rates and lower damage
Capital ship missles are bigger, longer range and do more damage
We need to look at the relationship between size and attributes

Ex - a laser on a shuttle should be much smaller and weaker then a ship to ship laser on a larger ship
Should reactors be scaled?  Engines?

Lets try to build a 'spec chart' for components with baseline sizes at each tier and levels of spec progression between tiers.  Ideally we should be able to validate the designs against the spec chart for consistency.

Lets identify game mechanics and systems which don't exist yet
* Ex - space station docking

Lets build an implementation plan (md, in folder) that covers these questions.  Identifies milestones, focusing on what we can build with existing systems while thinking ahead.  Lets identify if specific systems are critical to make the ships different.

Lets also think through the current play experience - can the player switch their ship?  Basically a sandbox.  Pick your ship, spawn other ships between (friendly, enemy team, neutral (beacon), pirate (free for all)).

# designs

## cargo shuttle
present in high numbers for short hop in system cargo movement. From a traffic perspective, they travel back and forth between small and larger stations, ferrying refined resources or supplies.

unarmed
slow
moderate cargo capacity

## freighter
heavy cargo transport for between system long duration trips. They operate exclusively on major trade lanes, only traveling from large station to large station.

unarmed
very slow
extreme cargo capacity

## pinnance
midsized personal carrier for up to 30 passengers

unarmed
fast
no armor

## sensor bouy
a station keeping bouy that constantly scans and reports back to the nearest station or ship.  keeps a beacon on in most cases.  can relay comms.

can run dark/passive and be hard to find

slow
no armor
great sensors

## mine
basically a laser head with a sensor that looks for IFF

slow
no armor
short range sensors only - can be passive only
mines can be networked to share sensor data

single laser

## system defence pod
effectively an immoble ship, heavily armed with point defence and missles.

heavy armor
big sensors

## light attack craft
the work horse of small navies and pirates.  cheap, armed and fast.  mostly used for ship interception, customs enforcement and anti-priacy system defence.

single short range laser and light forward missle
effectively no armor


## frigate 
technically a warship it carries enough weapons to pose a significant threat to small groups of other warships.  they can also carry a small number of marines for ship boarding operations.  used for convoy escorts and system defence.  rarely used for long range operations.

2x3 missles broadside
1x1 forward missle
1x1 forward laser
2x2 broadside PD
light armor

## destroyer
considered a true warship, the destroyer is large enough to picket systems, fight off a number of threats and still run away fast enough from a large force to serve as early warning.  full compliment of marines for boarding operations.  fully capable of independent operations or acting as escort for a carrier

2x4 missles broadside
1x2 forward missle
1x1 forward laser
1x1 rear PD
2x2 broadside laser
moderate armor
reactor armor

## station
long term habitation station, effectively immoble.  holds 30-1k people depending on size.  may have 1+ docking positions for ships.  some may be armed with point defense.  always have their beacon active (except when narriatively needed).

heavy armor around the outside, none inside
potentially armed, potentially heavily

## astroid station
long term habbitation stations built into an existing asteroid, immobile.  with beacon off it might take you a while to find it on sensors.

extreme armor around the outside and inside
almost certainly armed with PD, missles, sensor bouys and bad tempers

## mining ship
a rugged industrial vessel designed to extract resources from the environment. Rather than parking at a station, the mining ship's docking mechanic works in reverse: it is equipped with a heavy-duty tractor beam (a modified docking bay) that captures asteroids against their will and reels them in for processing.

From a traffic perspective, mining ships operate on the fringe, traveling back and forth between asteroid fields and the smaller outposts/stations where they drop off raw ore.

unarmed
slow
equipped with specialized mining lasers and heavy cargo holds

## hab-ship (mobile home)
effectively a retrofitted, parked cargo ship used as a permanent house. The population of the Sovereign Drift includes many who live in these mobile homes spread out thinly across areas with mining activity. 

From a traffic perspective, they rarely travel. They mostly sit in deep space near asteroid belts, running basic station-keeping and obstacle avoidance routines to avoid drifting rocks. 

unarmed
extremely slow or immobile (station-keeping only)
heavy emphasis on living quarters instead of cargo

## Universal Docking (Ship-to-Ship)
The docking mechanic is not restricted to stations. Because any ship can technically mount a `DockingBay` module, any two ships can dock with each other in deep space. 

This enables incredibly dynamic traffic and interactions at all levels:
* **Hab-Ship Visitors:** The tiny, isolated mobile homes can receive visitors, mail, or Amazon-style cargo shuttle deliveries right in the middle of a dense asteroid field.
* **Mid-Space Exchange:** Two cargo ships can meet in deep space to exchange goods or refuel without needing to return to a station.
* **Piracy & Boarding:** "Docking" can be non-consensual if one ship mounts a heavy-duty capture bay and forces a link, perfectly facilitating pirate boarding actions or customs inspections by the Jovian Regional Authority.
