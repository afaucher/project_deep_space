# Tactical Analysis Report

This report evaluates ship combat performance using parameter sweeps and multiple runs with jitter to chart how performance changes across various combat scenarios.

## 1. Missile vs Point Defense Saturation & Lethality

This section analyzes the penetration rate of missile broadsides against a defending ship's point defense grid, as well as the resulting lethality. The simulation sweeps across engagement ranges, attack axes (frontal vs broadside), and volley sizes to chart saturation thresholds. Jitter is applied to initial launch positions, velocity vectors, and the defender's orientation to provide a robust statistical mean.

### Results

{{MISSILE_VS_PD_TABLE}}

### Analysis
* Missiles launched in larger volleys tend to saturate the point defense grid, leading to non-linear increases in hit probability.
* Close range engagements give point defenses less time to track and fire, increasing the likelihood of a successful strike.

---

## 2. Time-To-Kill (TTK) & Damage Exchange

This section evaluates the time required to destroy an opponent in a direct firefight using primary energy weapons (Lasers). Ships spawn head-on and exchange fire until destruction or timeout.

### Results

{{TIME_TO_KILL_TABLE}}

### Analysis
* Identical ships engaging in a pure DPS race will result in high variance due to component hit RNG (e.g. hitting the reactor vs the hull).
* Draw states occur when both ships destroy each other simultaneously, or if weapons systems are mutually disabled before a killing blow can be struck.

---
*(Note: Additional sections will be appended here as new simulation runners are added to the suite).*
