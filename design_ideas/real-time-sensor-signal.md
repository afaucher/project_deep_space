Right now there is no feedback on weapon hits.  We basically can't see the ship change, and the classifier sometimes lags, etc.

One way to to give the player visibility is in their sensor returns.  We want to make them responsive to ship behavior on emission side.  We covered this in the `responsive_heat_em.md` doc.

On the receiving side - enabling the player to see change over time is a way we can signal the player about what is happening.  This could look like EM spikes from weapon firings, or the whiteout signal of a reactor dying.  The spider chart is great, but it isn't a good way to see these over-time changes that define their own scales.

Overall this can be the 'what do we know about my target' area.

We might want relative velocity meters.  This can be very useful in combat.

We might also want acceleration for combat.

The classifier might have lines where it does or doesn't read something.  But changes over time, like heat dropping off can show a pattern that is its own type of classifier.  Giving the raw data as it is is a good way to get the player to see how the signals are actually working.  And it sets them up to 'spot patterns ahead of the computer'.



