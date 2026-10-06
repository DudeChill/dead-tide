# Overnight Report — DEAD TIDE v0.1.0

## Build status: COMPLETE (vertical slice + archipelago travel)

Published: https://github.com/DudeChill/dead-tide — release `v0.1.0` with
Windows 10/11 and Linux x86-64 archives.

## Working (all verified by automated headless tests or live X-display run)

- Boot, main menu flow (pause → new/save/load/quit), seed CLI (`-- --seed=N`)
- Procedural island generation, 128×128, layered noise, fog of war
- Starter guarantees: palms/fiber/stone/driftwood near spawn + supply drops
  (100-seed validation: 0 problems)
- Energy turn system: world advances only on player actions; clock at
  100 AP/minute; day/night with darkness + campfire glow
- Movement incl. diagonals, swimming into shallow water (stamina cost)
- Gathering with tool-dependent speed; yields to inventory or ground
- Weight/volume inventory with capacity; pickup; ground items
- Crafting (9 recipes) with tools/skill/station gates; skill xp → levels
- Building 9 structures with placement validation; campfire fuel; rain
  collector filling in rain; storage crates with loot; shelter sleeping
- Survival meters (health/hunger/thirst/stamina/fatigue/temperature/pain),
  starvation/dehydration/cold damage, dirty-water and spoiled-food sickness
- Food spoilage by item age
- Fishing beside shallow water (skill-scaled chance)
- Creatures: crab, boar, snake, shark (water-only), hostile survivor; FSM AI
  (IDLE/ROAM/CHASE/ATTACK/FLEE); per-island difficulty spawns
- Turn-based combat: accuracy vs dodge, weighted body parts, bleeding,
  durability, death handling, loot drops, kill stats
- POIs (shipwreck, fishing boat wreck, campsite, survivor shack) with rolled
  loot containers and discovery toasts
- Raft: build at shoreline (ingredient-checked), board, sail, beach/disembark
- Archipelago travel from open ocean to any discovered island (storm-blocked),
  arrival at the near-side shore, on-arrival creature population
- Versioned save/load (5 slots, F5/F9 + pause menu) with full roundtrip
  verification including terrain identity and RNG state
- Death screen with cause/days/traveled/islands/kills/crafts
- Debug: F1 panel (heal, rest, materials, spawn creature, time skip, shore
  teleport), F2 reveal, F5/F9
- HUD: 5 meters, clock/weather, toasts, context hints, panels for inventory/
  crafting/building/map/pause/death; zoom +/-

## Verified in a real windowed session (X display :98)

Movement advanced the clock and meters, gather/craft/build/pause menus all
render and respond, night overlay and ocean backdrop draw correctly.

## Partially working / simplifications

- World travel is instant (time passes) rather than day-by-day sailing legs
- Raft is single-vessel; modular components (sail/rudder/motor) are data slots
- No audio (omitted deliberately per priority order)
- Windows exe built with Godot export templates on Linux; valid PE32+ x86_64,
  but not executed under Windows on this machine (no wine) — Linux export of
  the same project passes the full smoke suite headlessly

## Tests

- `tools/test.sh`:
  - smoke: 30 checks, 0 failures (`TEST_RESULT 0`), run against both the dev
    project and the exported Linux binary
  - generation validation: 100 seeds, 0 problems (`GEN_RESULT 0`)

## Build instructions

```bash
tools/build.sh          # validate → test → export Linux + Windows into builds/
tools/test.sh           # headless tests
tools/run.sh            # dev run;  godot --path . -- --seed=91837261 for fixed seed
```

Requires Godot 4.7.2 + export templates in
`~/.local/share/godot/export_templates/4.7.2.stable/`.

## Files

- `project.godot`, `export_presets.cfg` — config, input map, both targets
- `autoload/` — Events (signal bus), Data (JSON db + validation), SaveManager
- `scripts/core/` — Terrain, WorldMap, WorldGen, Actor, TurnManager, GameSim,
  Combat, Crafting, Building, AIController (pure simulation)
- `scripts/render/` — IsoRenderer, camera rig; `scripts/ui/` — HUD
- `scripts/tests/` — SmokeRunner; `tools/` — run/test/build
- `data/` — items, recipes, creatures, structures, balance (JSON)
- `docs/` — ARCHITECTURE, DEVLOG, ROADMAP, AGENT_STATE; `TODO.md`, `README.md`

## Architecture summary

Pure-data simulation separated from presentation; input → GameSim API →
state → Events signals → renderer/HUD. Deterministic seeds + saved RNG state
make every run reproducible. Content is JSON; tuning is centralized in
`data/balance.json`.

## Next actions (highest value)

1. Windows smoke pass under wine or a Windows box
2. v0.2 survival depth: infection, clothing warmth, sleep tiers (see docs/ROADMAP.md)
3. Audio pass (waves/rain/footsteps/UI)
4. Modular raft parts + day-by-day voyages
