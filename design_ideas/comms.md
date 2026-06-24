Ship to ship comms should be a link between all friendly ships via point to point radio.

Ships connected to each other can share their contact lists as long as they have line of sight between ships.

Each ship should treat this data as additional sensor signals.

For example:
You saw them at W 10 seconds ago
Ship A saw them at X 5 seconds ago
Ship B saw them at Y 2 seconds ago

Optionally - there could be a small time delay for proxied signals.  For example - A can see B and B can see C.  Does C get A's signals instantly or delayed?  Leave this for later.

A key issue we need to resolve is how to track multiple conflicting sensor signals and meaningfully combine them to get a better idea of the true state of the world.

Right now I think we just overwrite the contact info when we get new data which results in side effects.  We have to be very careful how we handle this because the sensor environment is noisy today.

A very simple way to resolve this is to just take the freshest.

What are the pros and cons of this?

The complicated way to address this might be a timeseries of quantile estimators to get some sort of recency-weighted average and confidence interval.
