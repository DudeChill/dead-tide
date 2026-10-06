# Devlog

## Session 1 — overnight vertical slice

- Bootstrapped Godot 4.7 project: input map, autoloads (Events bus, Data db,
  SaveManager), main scene.
- Core simulation written as pure classes: terrain defs, WorldMap grid,
  layered island generation with starter-resource guarantees, energy turn
  system (100 AP = 1 minute), actors with 6-part body model, survival meters,
  data-driven items/recipes/creatures/structures, crafting, building, FSM
  creature AI, body-part combat, weather, day/night.
- Isometric procedural renderer (64×32 diamonds, features, entities, night
  overlay), camera follow + zoom, HUD with meters/clock/toasts, contextual
  interaction menus (campfire, crates, collector, shelter, quick use/equip),
  build menu with live ingredient counts, world map with sail commands.
- Raft: built at shoreline as entity, boardable, sails to open ocean,
  island-to-island travel with arrival shore selection; storm-blocked.
- POIs with loot containers (shipwreck, fishing boat, campsite, shack),
  food spoilage, fishing with skill chance.
- Save/load (versioned JSON, base64 terrain, RNG state) — full roundtrip
  verified including terrain identity.
- Headless test harness: 30+ smoke checks through the real game boot
  (`-- --test`) and 100-seed generation validation (`-- --testgen`). All green.
- Live-verified on a real X display: movement advancing the clock, gather,
  crafting menu, build menu, pause menu.

### Decisions
- Pure-data simulation separate from presentation (testable headless).
- JSON content over custom Resources: zero tooling, trivially diffable.
- Energy turns instead of strict initiative: simpler, deterministic, saves
  exact RNG state.
- Raft as entity, not tile structure: keeps boarding/sailing clean and leaves
  room for modular raft expansion.
- Procedural placeholder art only: no asset licensing risk, coherent look.

### Bugs found and fixed during the session
- Double-added tile offsets in ambient-temperature loop (Actor + Vector2i).
- Coroutines in interaction menus → replaced with digit-menu state machine
  (headless-safe, no hidden async).
- Raft build bypassing `Building.build` → raft creation centralized there.
- POI flags not persisted on structures → merged into structure dicts.
- `PackedByteArray.to_byte_array()` misuse in serialization.
- Camera script not attached when built in code.
