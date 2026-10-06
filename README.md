# DEAD TIDE

Isometric turn-based island survival roguelike. Built with Godot 4.7.

You wake on the shore of a procedurally generated tropical island. Gather,
craft, survive, build a raft, and sail to other islands in the archipelago.
The world advances only when you act — every decision is turn-based.

![genre](https://img.shields.io/badge/genre-survival%20roguelike-blue)

## Current features (v0.1 vertical slice)

- Procedural island generation (128×128 tiles) with layered noise: elevation,
  moisture, terrain (deep ocean → sand → grass → jungle → rock → mud)
- Deterministic seeds — the same seed always produces the same archipelago
- Guaranteed-starter resources: palms, fiber, stone, driftwood, shoreline raft materials
- Energy-based turn system (100 AP = 1 in-game minute); world advances only on your actions
- Body model: 6 parts with HP, bleeding, and penalties (leg injuries slow you, arm injuries weaken blows)
- Survival: health, hunger, thirst, stamina, fatigue, body temperature, pain
- 35+ data-driven items, weight/volume inventory with capacity
- Gathering, crafting (9 recipes), building (9 structures incl. rain collector, workbench, shelter)
- Food with spoilage, dirty/fresh water, cooking at campfires, fishing
- Day/night cycle with darkness and campfire light, weather (clear/cloudy/rain/storm)
- Creatures: crabs, boars, snakes, sharks, hostile survivors — FSM AI
- Turn-based combat: body-part hits, dodge, weapon durability, bleeding
- Points of interest with loot: shipwrecks, fishing boat wrecks, campsites, survivor shacks
- Raft building, boarding, sailing; island-to-island travel across the archipelago
- World map with discovered-island tracking
- Versioned save/load (JSON, 5 slots via F5/F9 + pause menu)
- Death screen with run statistics
- Debug panel (F1) and map reveal (F2) for development

## Controls

| Key | Action |
| --- | --- |
| WASD / arrows | Move (turn-based) |
| Numpad 1-9 | Diagonal movement |
| E | Interact / gather / context menus |
| G | Pick up items |
| I | Inventory |
| C | Crafting |
| B | Build |
| M | World map |
| F | Attack adjacent creature |
| SPACE | Wait |
| + / - | Zoom |
| F1 | Debug panel |
| F2 | Reveal map |
| F5 / F9 | Quick save / load |
| ESC | Pause menu |

## Requirements

- Linux x86-64 or Windows 10/11
- Godot 4.7+ only needed to build from source; releases ship standalone binaries

## Run

From a release archive:

```bash
tar xf dead-tide-linux.tar.gz && cd dead-tide-linux
./DeadTide.x86_64
```

On Windows: extract `dead-tide-win64.zip` and run `DeadTide.exe`.

From source:

```bash
godot --path .
```

Reproducible run with a fixed world seed:

```bash
godot --path . -- --seed=91837261
```

## Build

```bash
tools/build.sh            # validates, tests, exports Linux + Windows
tools/build.sh linux      # Linux only
tools/build.sh windows    # Windows only
```

Requires Godot 4.7 export templates in `~/.local/share/godot/export_templates/4.7.2.stable/`.

## Test

```bash
tools/test.sh   # headless smoke tests + 100-seed generation validation
```

## Project architecture

```text
autoload/    Events (signal bus), Data (JSON db), SaveManager
scripts/core/  pure simulation: Terrain, WorldMap, WorldGen, Actor,
               TurnManager, GameSim, Combat, Crafting, Building, AIController
scripts/render/ IsoRenderer (procedural isometric drawing), camera rig
scripts/ui/    HUD (meters, clock, panels, toasts)
scripts/tests/ SmokeRunner (headless CI)
data/          items.json, recipes.json, creatures.json, structures.json, balance.json
scenes/        main.tscn (boot scene)
tools/         run.sh, test.sh, build.sh
```

Simulation and presentation are fully separated: `scripts/core/` is pure data
and logic (no Node dependencies), the renderer reads it and draws primitives.
Adding an item = one JSON entry. See `docs/ARCHITECTURE.md`.

## Known limitations

- Swimming into deep water is impossible on foot (by design); sharks patrol open water
- Raft is a single vessel; modular raft expansion planned
- No audio yet; no character animation; placeholder visuals by design
- World map travel is instant (time passes) rather than day-by-day sailing

## Roadmap

See `docs/ROADMAP.md` (v0.2 deeper survival → v1.0 release-quality core).
