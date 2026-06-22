# Tactical Analysis Report

This report evaluates ship combat performance using parameter sweeps and multiple runs with jitter to chart how performance changes across various combat scenarios.

## 1. Missile vs Point Defense Saturation & Lethality

This section analyzes the penetration rate of missile broadsides against a defending ship's point defense grid, as well as the resulting lethality. The simulation sweeps across engagement ranges, attack axes (frontal vs broadside), and volley sizes to chart saturation thresholds. Jitter is applied to initial launch positions, velocity vectors, and the defender's orientation to provide a robust statistical mean.

### Results

| Missiles Fired | Range (m) | Axis | Hit Prob (%) | Avg Hits | Avg Destroyed | Kill Rate (%) | Avg Hits to Kill |
|----------------|-----------|------|--------------|----------|---------------|---------------|------------------|
| 1 | 2000.0 | broadside | 40.0% ±51.6% | 0.4 | 0.6 | 0.0% | 0.0 |
| 1 | 2000.0 | frontal | 20.0% ±42.2% | 0.2 | 0.8 | 0.0% | 0.0 |
| 1 | 3500.0 | broadside | 40.0% ±51.6% | 0.4 | 0.6 | 0.0% | 0.0 |
| 1 | 3500.0 | frontal | 20.0% ±42.2% | 0.2 | 0.8 | 0.0% | 0.0 |
| 1 | 5000.0 | broadside | 20.0% ±42.2% | 0.2 | 0.8 | 0.0% | 0.0 |
| 1 | 5000.0 | frontal | 10.0% ±31.6% | 0.1 | 0.9 | 0.0% | 0.0 |
| 1 | 7000.0 | broadside | 0.0% ±0.0% | 0.0 | 1.0 | 0.0% | 0.0 |
| 1 | 7000.0 | frontal | 10.0% ±31.6% | 0.1 | 0.9 | 0.0% | 0.0 |
| 2 | 2000.0 | broadside | 70.0% ±25.8% | 1.4 | 0.6 | 0.0% | 0.0 |
| 2 | 2000.0 | frontal | 55.0% ±43.8% | 1.1 | 0.9 | 0.0% | 0.0 |
| 2 | 3500.0 | broadside | 60.0% ±31.6% | 1.2 | 0.8 | 0.0% | 0.0 |
| 2 | 3500.0 | frontal | 40.0% ±31.6% | 0.8 | 1.2 | 0.0% | 0.0 |
| 2 | 5000.0 | broadside | 15.0% ±33.7% | 0.3 | 1.7 | 0.0% | 0.0 |
| 2 | 5000.0 | frontal | 25.0% ±26.4% | 0.5 | 1.5 | 0.0% | 0.0 |
| 2 | 7000.0 | broadside | 25.0% ±26.4% | 0.5 | 1.5 | 0.0% | 0.0 |
| 2 | 7000.0 | frontal | 25.0% ±35.4% | 0.5 | 1.5 | 0.0% | 0.0 |
| 3 | 2000.0 | broadside | 76.7% ±27.4% | 2.3 | 0.7 | 0.0% | 0.0 |
| 3 | 2000.0 | frontal | 56.7% ±31.6% | 1.7 | 1.3 | 0.0% | 0.0 |
| 3 | 3500.0 | broadside | 66.7% ±35.1% | 2.0 | 1.0 | 0.0% | 0.0 |
| 3 | 3500.0 | frontal | 36.7% ±24.6% | 1.1 | 1.9 | 0.0% | 0.0 |
| 3 | 5000.0 | broadside | 40.0% ±26.3% | 1.2 | 1.8 | 0.0% | 0.0 |
| 3 | 5000.0 | frontal | 26.7% ±14.1% | 0.8 | 2.2 | 0.0% | 0.0 |
| 3 | 7000.0 | broadside | 26.7% ±14.1% | 0.8 | 2.2 | 0.0% | 0.0 |
| 3 | 7000.0 | frontal | 43.3% ±27.4% | 1.3 | 1.7 | 0.0% | 0.0 |
| 4 | 2000.0 | broadside | 50.0% ±20.4% | 2.0 | 2.0 | 0.0% | 0.0 |
| 4 | 2000.0 | frontal | 67.5% ±20.6% | 2.7 | 1.3 | 0.0% | 0.0 |
| 4 | 3500.0 | broadside | 70.0% ±25.8% | 2.8 | 1.2 | 0.0% | 0.0 |
| 4 | 3500.0 | frontal | 55.0% ±19.7% | 2.2 | 1.8 | 0.0% | 0.0 |
| 4 | 5000.0 | broadside | 57.5% ±16.9% | 2.3 | 1.7 | 0.0% | 0.0 |
| 4 | 5000.0 | frontal | 52.5% ±14.2% | 2.1 | 1.9 | 0.0% | 0.0 |
| 4 | 7000.0 | broadside | 32.5% ±23.7% | 1.3 | 2.7 | 0.0% | 0.0 |
| 4 | 7000.0 | frontal | 37.5% ±27.0% | 1.5 | 2.5 | 0.0% | 0.0 |
| 5 | 2000.0 | broadside | 72.0% ±28.6% | 3.6 | 1.4 | 0.0% | 0.0 |
| 5 | 2000.0 | frontal | 82.0% ±14.8% | 4.1 | 0.9 | 0.0% | 0.0 |
| 5 | 3500.0 | broadside | 84.0% ±12.6% | 4.2 | 0.8 | 0.0% | 0.0 |
| 5 | 3500.0 | frontal | 66.0% ±25.0% | 3.3 | 1.7 | 0.0% | 0.0 |
| 5 | 5000.0 | broadside | 56.0% ±18.4% | 2.8 | 2.2 | 0.0% | 0.0 |
| 5 | 5000.0 | frontal | 50.0% ±17.0% | 2.5 | 2.5 | 0.0% | 0.0 |
| 5 | 7000.0 | broadside | 50.0% ±25.4% | 2.5 | 2.5 | 0.0% | 0.0 |
| 5 | 7000.0 | frontal | 44.0% ±15.8% | 2.2 | 2.8 | 0.0% | 0.0 |
| 6 | 2000.0 | broadside | 80.0% ±17.2% | 4.8 | 1.2 | 0.0% | 0.0 |
| 6 | 2000.0 | frontal | 81.7% ±21.4% | 4.9 | 1.1 | 0.0% | 0.0 |
| 6 | 3500.0 | broadside | 80.0% ±17.2% | 4.8 | 1.2 | 0.0% | 0.0 |
| 6 | 3500.0 | frontal | 78.3% ±20.9% | 4.7 | 1.3 | 0.0% | 0.0 |
| 6 | 5000.0 | broadside | 58.3% ±16.2% | 3.5 | 2.5 | 0.0% | 0.0 |
| 6 | 5000.0 | frontal | 71.7% ±15.8% | 4.3 | 1.7 | 0.0% | 0.0 |
| 6 | 7000.0 | broadside | 41.7% ±28.6% | 2.5 | 3.5 | 0.0% | 0.0 |
| 6 | 7000.0 | frontal | 55.0% ±17.7% | 3.3 | 2.7 | 0.0% | 0.0 |
| 8 | 2000.0 | broadside | 78.8% ±18.7% | 6.3 | 1.7 | 0.0% | 0.0 |
| 8 | 2000.0 | frontal | 83.8% ±11.9% | 6.7 | 1.3 | 0.0% | 0.0 |
| 8 | 3500.0 | broadside | 86.2% ±9.2% | 6.9 | 1.1 | 0.0% | 0.0 |
| 8 | 3500.0 | frontal | 73.8% ±12.4% | 5.9 | 2.1 | 0.0% | 0.0 |
| 8 | 5000.0 | broadside | 65.0% ±16.5% | 5.2 | 2.8 | 0.0% | 0.0 |
| 8 | 5000.0 | frontal | 70.0% ±12.1% | 5.6 | 2.4 | 0.0% | 0.0 |
| 8 | 7000.0 | broadside | 78.8% ±13.2% | 6.3 | 1.7 | 0.0% | 0.0 |
| 8 | 7000.0 | frontal | 80.0% ±10.5% | 6.4 | 1.6 | 0.0% | 0.0 |
| 10 | 2000.0 | broadside | 84.0% ±12.6% | 8.4 | 1.6 | 0.0% | 0.0 |
| 10 | 2000.0 | frontal | 80.0% ±8.2% | 8.0 | 2.0 | 0.0% | 0.0 |
| 10 | 3500.0 | broadside | 88.0% ±9.2% | 8.8 | 1.2 | 0.0% | 0.0 |
| 10 | 3500.0 | frontal | 80.0% ±9.4% | 8.0 | 2.0 | 0.0% | 0.0 |
| 10 | 5000.0 | broadside | 74.0% ±11.7% | 7.4 | 2.6 | 0.0% | 0.0 |
| 10 | 5000.0 | frontal | 79.0% ±8.8% | 7.9 | 2.1 | 0.0% | 0.0 |
| 10 | 7000.0 | broadside | 75.0% ±15.1% | 7.5 | 2.5 | 0.0% | 0.0 |
| 10 | 7000.0 | frontal | 79.0% ±12.0% | 7.9 | 2.1 | 0.0% | 0.0 |
| 15 | 2000.0 | broadside | 92.7% ±5.8% | 13.9 | 1.1 | 0.0% | 0.0 |
| 15 | 2000.0 | frontal | 88.7% ±7.1% | 13.3 | 1.7 | 0.0% | 0.0 |
| 15 | 3500.0 | broadside | 94.0% ±4.9% | 14.1 | 0.9 | 0.0% | 0.0 |
| 15 | 3500.0 | frontal | 89.3% ±6.4% | 13.4 | 1.6 | 0.0% | 0.0 |
| 15 | 5000.0 | broadside | 80.0% ±11.8% | 12.0 | 3.0 | 0.0% | 0.0 |
| 15 | 5000.0 | frontal | 75.3% ±12.2% | 11.3 | 3.7 | 0.0% | 0.0 |
| 15 | 7000.0 | broadside | 72.7% ±15.9% | 10.9 | 4.1 | 0.0% | 0.0 |
| 15 | 7000.0 | frontal | 74.7% ±25.3% | 11.2 | 3.8 | 0.0% | 0.0 |


### Analysis
* Missiles launched in larger volleys tend to saturate the point defense grid, leading to non-linear increases in hit probability.
* Close range engagements give point defenses less time to track and fire, increasing the likelihood of a successful strike.

---

## 2. Time-To-Kill (TTK) & Damage Exchange

This section evaluates the time required to destroy an opponent in a direct firefight using primary energy weapons (Lasers). Ships spawn head-on and exchange fire until destruction or timeout.

### Results

| Range (m) | Axis | Avg TTK (s) | Win Rate (ShipA) | Win Rate (ShipB) | Draws/Timeouts |
|-----------|------|-------------|------------------|------------------|----------------|
| 3000.0 | head-on | 4.0s ±0.0s | 90.0% | 10.0% | 0 |


### Analysis
* Identical ships engaging in a pure DPS race will result in high variance due to component hit RNG (e.g. hitting the reactor vs the hull).
* Draw states occur when both ships destroy each other simultaneously, or if weapons systems are mutually disabled before a killing blow can be struck.

---
*(Note: Additional sections will be appended here as new simulation runners are added to the suite).*
