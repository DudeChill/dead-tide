# AGENT STATE

## Current milestone
Release engineering: exports (Windows/Linux), GitHub publish.

## Completed
- Full v0.1 vertical slice per TODO.md DONE section.
- Tests green: `godot --headless --path . -- --test` (smoke, exit 0) and
  `-- --testgen` (100 seeds, 0 problems).
- Visual verification on X display :98 (movement/turns/menus render + respond).
- Export templates 4.7.2.stable installed at
  ~/.local/share/godot/export_templates/4.7.2.stable/ (linux + windows).

## Key architectural decisions
- Simulation (scripts/core, pure RefCounted classes) vs presentation
  (scripts/render, scripts/ui). Data autoload = JSON content + balance.
- TurnManager: energy model, 100 AP = 1 minute; world ticks by spent AP.
- Raft = entity in GameSim.rafts, not a tile structure.
- Digit-key context menus via controller menu_actions state machine (no
  coroutines — headless safe).
- Save: user://saves/slot_N.json, save_version 1, base64 terrain, RNG state.

## Gotchas
- After adding a new class_name script, run `godot --headless --path . -e --quit`
  once or dependent scripts fail with "not declared in scope".
- npm/npx not needed; godot binary at ~/.local/bin/godot (4.7.2.stable).
- Windows export from Linux works via export templates (no wine needed).

## Next task
1. tools/build.sh + export_presets.cfg
2. Verify exported binaries headlessly
3. gh repo create + push + release with archives
