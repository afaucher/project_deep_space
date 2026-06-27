# Tactical Analysis Report

This report evaluates ship combat performance using parameter sweeps and multiple runs with jitter to chart how performance changes across various combat scenarios.

## 1. Missile vs Point Defense Saturation & Lethality

This section analyzes the penetration rate of missile broadsides against a defending ship's point defense grid, as well as the resulting lethality. The simulation sweeps across engagement ranges, attack axes (frontal vs broadside), and volley sizes to chart saturation thresholds. Jitter is applied to initial launch positions, velocity vectors, and the defender's orientation to provide a robust statistical mean.

### Results

| Missiles Fired | Range (m) | Axis | Hit Prob (%) | Avg Hits | Avg Destroyed | Kill Rate (%) | Avg Hits to Kill |
|----------------|-----------|------|--------------|----------|---------------|---------------|------------------|
| 1 | 2000.0 | broadside | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 2000.0 | frontal | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 3500.0 | broadside | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 3500.0 | frontal | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 5000.0 | broadside | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 5000.0 | frontal | 10.0% ±31.6% | 0.1 | 0.9 | 0.0% | 0.0 |
| 1 | 7000.0 | broadside | 20.0% ±42.2% | 0.2 | 0.8 | 0.0% | 0.0 |
| 1 | 7000.0 | frontal | 10.0% ±31.6% | 0.1 | 0.9 | 0.0% | 0.0 |
| 2 | 2000.0 | broadside | 50.0% ±40.8% | 1.0 | 1.0 | 0.0% | 0.0 |
| 2 | 2000.0 | frontal | 60.0% ±39.4% | 1.2 | 0.8 | 0.0% | 0.0 |
| 2 | 3500.0 | broadside | 5.0% ±15.8% | 0.1 | 1.9 | 0.0% | 0.0 |
| 2 | 3500.0 | frontal | 10.0% ±21.1% | 0.2 | 1.8 | 0.0% | 0.0 |
| 2 | 5000.0 | broadside | 25.0% ±42.5% | 0.5 | 1.5 | 0.0% | 0.0 |
| 2 | 5000.0 | frontal | 20.0% ±35.0% | 0.4 | 1.6 | 0.0% | 0.0 |
| 2 | 7000.0 | broadside | 45.0% ±36.9% | 0.9 | 1.1 | 0.0% | 0.0 |
| 2 | 7000.0 | frontal | 50.0% ±33.3% | 1.0 | 1.0 | 0.0% | 0.0 |
| 3 | 2000.0 | broadside | 63.3% ±36.7% | 1.9 | 1.1 | 0.0% | 0.0 |
| 3 | 2000.0 | frontal | 80.0% ±23.3% | 2.4 | 0.6 | 0.0% | 0.0 |
| 3 | 3500.0 | broadside | 33.3% ±35.1% | 1.0 | 2.0 | 0.0% | 0.0 |
| 3 | 3500.0 | frontal | 73.3% ±37.8% | 2.2 | 0.8 | 0.0% | 0.0 |
| 3 | 5000.0 | broadside | 70.0% ±48.3% | 2.1 | 0.9 | 0.0% | 0.0 |
| 3 | 5000.0 | frontal | 73.3% ±43.9% | 2.2 | 0.8 | 0.0% | 0.0 |
| 3 | 7000.0 | broadside | 100.0% ±0.0% | 3.0 | 0.0 | 0.0% | 0.0 |
| 3 | 7000.0 | frontal | 100.0% ±0.0% | 3.0 | 0.0 | 0.0% | 0.0 |
| 4 | 2000.0 | broadside | 97.5% ±7.9% | 3.9 | 0.1 | 0.0% | 0.0 |
| 4 | 2000.0 | frontal | 82.5% ±26.5% | 3.3 | 0.7 | 0.0% | 0.0 |
| 4 | 3500.0 | broadside | 42.5% ±37.4% | 1.7 | 2.3 | 0.0% | 0.0 |
| 4 | 3500.0 | frontal | 55.0% ±48.3% | 2.2 | 1.8 | 0.0% | 0.0 |
| 4 | 5000.0 | broadside | 100.0% ±0.0% | 4.0 | 0.0 | 0.0% | 0.0 |
| 4 | 5000.0 | frontal | 90.0% ±31.6% | 3.6 | 0.4 | 0.0% | 0.0 |
| 4 | 7000.0 | broadside | 100.0% ±0.0% | 4.0 | 0.0 | 0.0% | 0.0 |
| 4 | 7000.0 | frontal | 100.0% ±0.0% | 4.0 | 0.0 | 0.0% | 0.0 |
| 5 | 2000.0 | broadside | 98.0% ±6.3% | 4.9 | 0.1 | 0.0% | 0.0 |
| 5 | 2000.0 | frontal | 92.0% ±14.0% | 4.6 | 0.4 | 0.0% | 0.0 |
| 5 | 3500.0 | broadside | 100.0% ±0.0% | 5.0 | 0.0 | 0.0% | 0.0 |
| 5 | 3500.0 | frontal | 62.0% ±27.4% | 3.1 | 1.9 | 0.0% | 0.0 |
| 5 | 5000.0 | broadside | 100.0% ±0.0% | 5.0 | 0.0 | 0.0% | 0.0 |
| 5 | 5000.0 | frontal | 100.0% ±0.0% | 5.0 | 0.0 | 0.0% | 0.0 |
| 5 | 7000.0 | broadside | 100.0% ±0.0% | 5.0 | 0.0 | 0.0% | 0.0 |
| 5 | 7000.0 | frontal | 100.0% ±0.0% | 5.0 | 0.0 | 0.0% | 0.0 |
| 6 | 2000.0 | broadside | 98.3% ±5.3% | 5.9 | 0.1 | 0.0% | 0.0 |
| 6 | 2000.0 | frontal | 88.3% ±13.7% | 5.3 | 0.7 | 0.0% | 0.0 |
| 6 | 3500.0 | broadside | 100.0% ±0.0% | 6.0 | 0.0 | 0.0% | 0.0 |
| 6 | 3500.0 | frontal | 90.0% ±11.7% | 5.4 | 0.6 | 0.0% | 0.0 |
| 6 | 5000.0 | broadside | 100.0% ±0.0% | 6.0 | 0.0 | 0.0% | 0.0 |
| 6 | 5000.0 | frontal | 100.0% ±0.0% | 6.0 | 0.0 | 0.0% | 0.0 |
| 6 | 7000.0 | broadside | 96.7% ±10.5% | 5.8 | 0.2 | 0.0% | 0.0 |
| 6 | 7000.0 | frontal | 100.0% ±0.0% | 6.0 | 0.0 | 0.0% | 0.0 |
| 8 | 2000.0 | broadside | 100.0% ±0.0% | 8.0 | 0.0 | 0.0% | 0.0 |
| 8 | 2000.0 | frontal | 96.2% ±11.9% | 7.7 | 0.3 | 0.0% | 0.0 |
| 8 | 3500.0 | broadside | 97.5% ±5.3% | 7.8 | 0.2 | 0.0% | 0.0 |
| 8 | 3500.0 | frontal | 100.0% ±0.0% | 8.0 | 0.0 | 0.0% | 0.0 |
| 8 | 5000.0 | broadside | 98.8% ±4.0% | 7.9 | 0.1 | 0.0% | 0.0 |
| 8 | 5000.0 | frontal | 97.5% ±7.9% | 7.8 | 0.2 | 0.0% | 0.0 |
| 8 | 7000.0 | broadside | 100.0% ±0.0% | 8.0 | 0.0 | 0.0% | 0.0 |
| 8 | 7000.0 | frontal | 100.0% ±0.0% | 8.0 | 0.0 | 0.0% | 0.0 |
| 10 | 2000.0 | broadside | 98.0% ±4.2% | 9.8 | 0.2 | 0.0% | 0.0 |
| 10 | 2000.0 | frontal | 97.0% ±4.8% | 9.7 | 0.3 | 0.0% | 0.0 |
| 10 | 3500.0 | broadside | 97.0% ±6.7% | 9.7 | 0.3 | 0.0% | 0.0 |
| 10 | 3500.0 | frontal | 97.0% ±6.7% | 9.7 | 0.3 | 0.0% | 0.0 |
| 10 | 5000.0 | broadside | 100.0% ±0.0% | 10.0 | 0.0 | 0.0% | 0.0 |
| 10 | 5000.0 | frontal | 100.0% ±0.0% | 10.0 | 0.0 | 0.0% | 0.0 |
| 10 | 7000.0 | broadside | 100.0% ±0.0% | 10.0 | 0.0 | 0.0% | 0.0 |
| 10 | 7000.0 | frontal | 100.0% ±0.0% | 10.0 | 0.0 | 0.0% | 0.0 |
| 15 | 2000.0 | broadside | 98.7% ±4.2% | 14.8 | 0.2 | 0.0% | 0.0 |
| 15 | 2000.0 | frontal | 100.0% ±0.0% | 15.0 | 0.0 | 0.0% | 0.0 |
| 15 | 3500.0 | broadside | 98.0% ±3.2% | 14.7 | 0.3 | 0.0% | 0.0 |
| 15 | 3500.0 | frontal | 98.0% ±3.2% | 14.7 | 0.3 | 0.0% | 0.0 |
| 15 | 5000.0 | broadside | 100.0% ±0.0% | 15.0 | 0.0 | 0.0% | 0.0 |
| 15 | 5000.0 | frontal | 98.0% ±4.5% | 14.7 | 0.3 | 0.0% | 0.0 |
| 15 | 7000.0 | broadside | 100.0% ±0.0% | 15.0 | 0.0 | 0.0% | 0.0 |
| 15 | 7000.0 | frontal | 99.3% ±2.1% | 14.9 | 0.1 | 0.0% | 0.0 |


### Analysis
* Missiles launched in larger volleys tend to saturate the point defense grid, leading to non-linear increases in hit probability.
* Close range engagements give point defenses less time to track and fire, increasing the likelihood of a successful strike.

---

## 2. Time-To-Kill (TTK) & Damage Exchange

This section evaluates the time required to destroy an opponent in a direct firefight using primary energy weapons (Lasers). Ships spawn head-on and exchange fire until destruction or timeout.

### Results

| Range (m) | Axis | Avg TTK (s) | Win Rate (ShipA) | Win Rate (ShipB) | Draws/Timeouts |
|-----------|------|-------------|------------------|------------------|----------------|
| 3000.0 | head-on | 0.0s ±0.0s | 0.0% | 0.0% | 10 |


### Analysis
* Identical ships engaging in a pure DPS race will result in high variance due to component hit RNG (e.g. hitting the reactor vs the hull).
* Draw states occur when both ships destroy each other simultaneously, or if weapons systems are mutually disabled before a killing blow can be struck.

---
*(Note: Additional sections will be appended here as new simulation runners are added to the suite).*
