---
name: tactical-analysis
description: "Executes the tactical analysis engine to run combat simulation scenarios, collect data, and generate a markdown report."
---

# Tactical Analysis Engine Skill

Use this skill when the user wants to run a tactical analysis of the ship combat performance, sweep parameters, or generate a tactical report.

## Instructions

1.  **Execute the Orchestrator**
    Run the `tactical_analysis/run_analysis_suite.ps1` script to perform the simulation runs.
    ```bash
    cd c:\Users\alexa\.gemini\antigravity\scratch\project_deep_space
    .\tactical_analysis\run_analysis_suite.ps1
    ```

2.  **Verify Data Generation**
    Ensure that `tactical_analysis/data/` contains populated CSV files (e.g., `missile_vs_pd_results.csv`).

3.  **Present the Report**
    Once the run completes, the Python script will have automatically generated `tactical_analysis/reports/latest_report.md`.
    Read this markdown file using `view_file` and present a summary or the key insights to the user. Do not dump the entire markdown content, just link the file using markdown links so the user can click it:
    [Latest Report](file:///c:/Users/alexa/.gemini/antigravity/scratch/project_deep_space/tactical_analysis/reports/latest_report.md)

4.  **Handling A/B Testing Requests**
    If the user asks to measure the effect of a parameter (e.g., "what if PD range is doubled?"):
    - Edit the corresponding code in `project_deep_space/scripts/` (e.g. `point_defense.gd`).
    - Rerun the suite.
    - Compare the new `latest_report.md` data to previous runs.
