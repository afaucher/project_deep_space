I did a playtest with the pirates and had some feedback.

I had to add a ship debug mode to show them on the nav screen to find the pirate.  Generally we don't have enough traffic for pirates to have a good target selection.  We need enough traffic on the lanes.  Lets scope out an economic expansion:
* Lets 2x the radius of the cluster to give us more room
* Lets move the wormhole near the center station
* Lets create 2 more mining colonies with trade routes back to the center.  Lets make them flagged under something else.  Our peer state in this cluster.
* Lets have freighters emerge from the wormhold periodically, bounce down and back the becon road with a stop on either end and leaves

Pirates should bounce between available trade routes.  They should either sit dark or patrol themselves making themselves look like another freighter.  They should NOT always enter the route in the same spot.

I got a pirate to stop me and the behavior was pretty weird:
* The 1st pirate bounced off me and killed itself
* The 2nd pirate never actually stopped but did log an intercept

What I was expecting was matching speeds and then docking.  Then 10 seconds+ to steal cargo, undock and depart.

We might need to refine ship to ship docking to make this work.

The incoming hail needs a sound and/or visual alert.

The comply button appeared but it wasn't clear what it actually did.  Do I stop?  Do I press the button?  Is the button just for fun?

The first demand never went away, it was still there when the second pirate got me.
* Long term we want the hail to be persistant from the other ship.  A ship leaving the area should stop the hail.  The ship losing interest in me should stop the hail.

The Hails UI is hard to visually follow.  We have:
HAILS
No vessel selected / Selected...
DEMAND ID DEMAND STOP Request Docking
DEMAND(STOP) - flag:JOLLY ROGER [TO YOU]

They are all visually inconsistent and there isn't a logical structure to the information.

I see distinct sets:
1. The selected vessel and outgoing requests
2. Hail requests from each vessel.

But they are actually all just vessels with different reasons to be in the list.  Lets sort by vessel and include:
* The selected vessel
* Any vessels we have sent hail requests too (so we can cancel/track)
* Any vessels which have hailed us

The header should be the track/ship name and the flag.

We can list them all together and under each the appropriate actions.  You could for example get a demand stop from a pirate and send back - demand stop.  lets omit "[TO YOU]" as it should be redundant.

Lets make the demands and request docking consistent style buttons with similar style text.  Right now they don't look like buttons and mix CAPS and non-CAPS.

Together we have [ship -> [hails to/from],...]

In the future, we want the pirate guild to not 'file reports' but actually have to comm in from each ship.  This would force pirates to interact in normal space more.  Full fiction would be there is pirate contacts on various stations and the pirate literally has to reach them to report in.  Finding and removing these people literally tears down the pirate network.

Pirate/patrol stops are a good reason to implement autopilot dead stop.  Or we need to have pirate ships match speeds and lock on for the duration of the stop.

