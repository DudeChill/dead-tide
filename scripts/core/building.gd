class_name Building
extends RefCounted
## Tile-based construction. Structures live in data/structures.json:
## {"campfire": {"name": "Campfire", "ingredients": [...], "placement": "land",
##   "fuel_max": 4.0, "container": false}}

## Build menu order (raft last — the goal of the loop).
const STRUCTURE_ORDER: Array[String] = [
	"campfire", "shelter", "storage_crate", "water_collector",
	"workbench", "wall", "floor", "door", "raft",
]

static func can_build(game: GameSim, structure_id: String, pos: Vector2i) -> Dictionary:
	var def := Data.structure(structure_id)
	if def.is_empty():
		return {"ok": false, "reason": "Unknown structure."}
	var map := game.current_map()
	if not map.in_bounds(pos):
		return {"ok": false, "reason": "Out of bounds."}
	if map.structure(pos).get("kind", "") != "":
		return {"ok": false, "reason": "Tile occupied."}
	if map.blocks_move(pos):
		return {"ok": false, "reason": "Blocked by terrain feature."}
	var placement := str(def.get("placement", "land"))
	var t := map.tile(pos)
	match placement:
		"land":
			if not Terrain.is_passable(t):
				return {"ok": false, "reason": "Must build on land."}
		"water":
			if not Terrain.is_boat_ok(t):
				return {"ok": false, "reason": "Must build on water."}
		"shallow":
			if t != Terrain.T.SHALLOW:
				return {"ok": false, "reason": "Must build in shallow water."}
		"shallow_water_adjacent":
			if t != Terrain.T.SHALLOW:
				return {"ok": false, "reason": "Raft must be built in shallow water at the shoreline."}
			var has_land := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				if map.is_clear_for_walk(pos + d):
					has_land = true
					break
			if not has_land:
				return {"ok": false, "reason": "Raft must touch walkable shore."}
	# Ingredients.
	var p := game.player
	for ing: Dictionary in def.get("ingredients", []):
		if p.count_item(str(ing["id"])) < int(ing.get("qty", 1)):
			var idef := Data.item(str(ing["id"]))
			return {"ok": false, "reason": "Need %d x %s" % [int(ing.get("qty", 1)), str(idef.get("name", ing["id"]))]}
	return {"ok": true, "reason": ""}


static func build(game: GameSim, structure_id: String, pos: Vector2i) -> bool:
	var check := can_build(game, structure_id, pos)
	if not check["ok"]:
		Events.toast.emit(str(check["reason"]))
		return false
	var def := Data.structure(structure_id)
	var p := game.player
	for ing: Dictionary in def.get("ingredients", []):
		p.remove_item(str(ing["id"]), int(ing.get("qty", 1)))
	var extra: Dictionary = {}
	if bool(def.get("container", false)):
		extra["items"] = []
	if structure_id == "campfire":
		extra["fuel"] = 2.0
	if structure_id == "water_collector":
		extra["water"] = 0.0
	if bool(def.get("is_raft", false)):
		# Rafts are entities, not tile structures.
		game.build_raft_at(pos)
		Events.toast.emit("Built %s." % str(def.get("name", structure_id)))
		Events.structure_built.emit(structure_id, pos)
		game.player.add_skill_xp("fabrication", 15.0)
		game.turn_manager.spend(game.turn_manager.player_action_cost(int(def.get("time_cost", 300))))
		return true
	game.current_map().set_structure(pos, structure_id, extra)
	Events.toast.emit("Built %s." % str(def.get("name", structure_id)))
	Events.structure_built.emit(structure_id, pos)
	p.add_skill_xp("fabrication", 6.0)
	game.turn_manager.spend(game.turn_manager.player_action_cost(int(def.get("time_cost", 300))))
	return true