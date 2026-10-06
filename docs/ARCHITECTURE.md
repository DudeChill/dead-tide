# Architecture

## Separation of concerns

`scripts/core/` contains the whole simulation as pure GDScript classes
(`RefCounted`, no Node/SceneTree dependencies except the `Data` autoload for
content lookups). `scripts/render/` and `scripts/ui/` read simulation state
and draw primitives. Communication flows one way: input → controller →
`GameSim` API → state mutation → `Events` signals → renderer/HUD refresh.

## Turn system

Energy scheduling (`TurnManager`): every actor accumulates AP. The player
action subtracts its cost (move 100, gather 150, attack 100, …); the manager
then loops creatures — each regenerates AP at its species `speed` and acts
when ≥ 0 — until the player's energy is ≥ 0 again. 100 AP == 1 in-game
minute, so the clock, survival meters, weather, and structures all tick by
spent action points. Consequences:

- deterministic, seed-reproducible simulation
- idle cost is zero (nothing runs between player actions)
- save/load is exact

## World generation

`WorldGen.generate_island(island_id, seed, size, quality)`:

1. Simplex elevation + radial island mask (noisy edge)
2. Moisture noise → jungle/grass split, mud lowlands
3. Shoreline pass forcing sand beaches
4. Vegetation: palms, young palms, fiber plants, rock outcrops, driftwood, beach debris
5. Spawn selection: clear sand/grass tile adjacent to shallow water
6. Guarantee pass: minimum palm/fiber/stone/driftwood counts near spawn plus starter supply drops
7. Quality pass per island archetype (starter/rich/wreck/danger) placing POIs with rolled loot

The archipelago is fixed: four islands with distinct quality + difficulty.
Each island map is generated lazily-independent with a seed derived from the
world seed, so generation order never matters.

## Entities

`Actor` covers player and creatures: body-part map (head/torso/arms/legs with
hp, bleeding, injury), survival meters, weight/volume inventory with
timestamps, equipment, skills (xp → level via sqrt curve), and AI scratch
state. Creatures read `data/creatures.json` (profile: passive / territorial /
predator / hostile_humanoid).

## Combat

`Combat.resolve_attack` — weapon or fists, arm-injury multiplier, melee skill
bonus, stamina factor, accuracy vs dodge roll, weighted body-part hit,
bleeding above a damage threshold, durability loss. Death: head or torso
destroyed (or total ≤ 0).

## Crafting / building

Recipe and structure definitions live entirely in `data/recipes.json` /
`data/structures.json`: ingredients, tool requirements, skill gates,
stations (campfire/workbench proximity), time costs. `Crafting` / `Building`
validate → consume → produce → award xp → spend AP. Adding content is a JSON
edit; validation errors are logged at boot.

## Boats

A raft is a `rafts` entity (id, island, position, cargo) rather than a tile
structure. Boarding requires adjacency; sailing moves the raft on water
tiles; beaching lands on walkable shore. Island travel (`GameSim.travel_to`)
requires open ocean + non-storm weather, advances the clock by distance, and
places the raft at the arrival island's near-side shore. Modular components
(floats, deck, sail, rudder, motor) are future extension slots in the raft
dictionary.

## Save format

`SaveManager` writes `user://saves/slot_N.json`:

```json
{"save_version": 1, "world_seed": …, "islands": {"0": {"map": {…}, …}},
 "actors": […], "clock_minutes": …, "rng_state": …, …}
```

Terrain and fog bits are base64-packed arrays; features/items/structures use
`"x,y"` string keys; actors are flat dictionaries. `save_version` gates
future migrations. RNG state is saved so a loaded run continues the exact
same random sequence.

## Data format

All content JSON under `data/`, loaded and validated by the `Data` autoload
at boot (unknown ids in recipes/structures are logged as errors). Tuning
values (rates, costs, chances) live in `data/balance.json`.

## Rendering

`IsoRenderer._draw()` paints 64×32 diamonds from the player outward with
viewport culling and fog-of-war culling, then features/structures/items,
then actors, then a night-darkness overlay with campfire glows. No image
assets; every visual is a polygon/line so the project stays tiny and
license-clean.
