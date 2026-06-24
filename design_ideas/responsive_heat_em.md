Every one of our components can have impact on heat output and EM emissions.  Right now they only depend on if the system is powered.

The basic cases are:
* We fire a laser, there is an EM pulse afterwards or waste heat.
* We got hit by a laser, and took a burst of heat output.
* The engine is damaged, the EM output spikes.
* The reactor is destroyed - 1-2s 'whiteout' EM spike.

Lets treat them as dynamic elements.  We would want ~1x a sec refresh of the EM/Heat output of each component.  We should keep components in the same realm they are now


I think we have a good model for summing EM outputs already, and it is instantanious.  It is an input to our directional visibility on passive sensors so there is a natural break.

For heat, I am not sure where our management system is at.  How heat is summed up and how we think about dissipation.  For example, does the heat build up in components?  Does it bleed between?  Which components get cooled first?  Is it just uniform so if each component can dump 1 heat, they can overheat even though the heat dump for the whole ship has capacity?

