# Tooling note: Claude Code Godot skill choice (deferred)

Date: 2026-06-26. Status: **deferred — no action taken yet.**

We looked at the Claude Code plugin marketplace for a Godot skill to improve
GDScript/Godot assistance on this project.

## Key finding
There is **no genuine first-party** (Anthropic- or Godot-official) Godot skill.
Everything available is community-made. Some directory listings call themselves
"first-party" — they are not. Calibrate expectations: top repos sit at ~17-34
GitHub stars.

## Candidates (all MIT, Godot 4.x)
- **Randroids-Dojo/Godot-Claude-Skills** (~34★) — testing (GdUnit4), CI/CD,
  exports, automation, deployment. Standalone (no MCP).
  Install: `/plugin marketplace add Randroids-Dojo/Godot-Claude-Skills` then
  `/plugin install godot`.
- **alexmeckes/godot-claude-skills** (~17★) — GDScript patterns (signals, state
  machines, async, tweens), scene design, shaders. **Requires the `godot-mcp`
  server** driving a live editor.
- Also: fenixnix/Godot-Skills, htdt/godogen (broader game-dev bundle).

## Recommendation (if/when we adopt one)
**Randroids-Dojo** is the better fit for this project: we work entirely headless
via CLI (`build.ps1` / `test_runner.ps1`), so its testing/CI/export focus
matches our actual workflow. The alexmeckes one assumes a live editor via
`godot-mcp`, which doesn't fit how we work and adds an MCP + running-editor
requirement.

## Why deferred
- Installing a third-party skill injects instructions into the assistant's
  context — a trust/security decision that's the user's to make, not something
  to auto-pull.
- `/plugin` is an interactive terminal command; the user runs it, not the agent.
- Worth skimming the repo's skill contents first, since its text becomes
  guidance the assistant follows.

## Next step when revisited
Skim Randroids-Dojo skill contents → if acceptable, user runs the two `/plugin`
commands → assistant folds its testing/export conventions into the harness
workflow.
