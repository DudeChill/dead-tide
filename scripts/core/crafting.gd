class_name Crafting
extends RefCounted
## Data-driven crafting. Recipes live in data/recipes.json:
## {"stone_axe": {"ingredients": [{"id":"stone","qty":3}], "tools": ["stone_knife"],
##   "skill": "fabrication", "skill_level": 0, "time_cost": 300,
##   "station": "", "result": "stone_axe", "result_qty": 1}}

static func can_craft(game: GameSim, recipe_id: String) -> Dictionary:
	## Returns {"ok": bool, "reason": String}.
	var recipe := Data.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "Unknown recipe."}
	var p := game.player
	# Ingredients.
	for ing: Dictionary in recipe.get("ingredients", []):
		if p.count_item(str(ing["id"])) < int(ing.get("qty", 1)):
			var def := Data.item(str(ing["id"]))
			return {"ok": false, "reason": "Need %d x %s" % [int(ing.get("qty", 1)), str(def.get("name", ing["id"]))]}
	# Tools.
	for tool_id: String in recipe.get("tools", []):
		if p.count_item(tool_id) <= 0:
			var tdef := Data.item(tool_id)
			return {"ok": false, "reason": "Requires tool: %s" % str(tdef.get("name", tool_id))}
	# Skill.
	var skill := str(recipe.get("skill", ""))
	if skill != "" and p.skill_level(skill) < int(recipe.get("skill_level", 0)):
		return {"ok": false, "reason": "Requires %s level %d" % [skill, int(recipe.get("skill_level", 0))]}
	# Station proximity.
	var station := str(recipe.get("station", ""))
	if station != "" and not _near_station(game, station):
		var sdef := Data.structure(station)
		return {"ok": false, "reason": "Requires a nearby %s" % str(sdef.get("name", station))}
	return {"ok": true, "reason": ""}


static func _near_station(game: GameSim, station: String) -> bool:
	var map := game.current_map()
	for d: Vector2i in game._adjacent_and_current(game.player.pos):
		if str(map.structure(d).get("kind")) == station:
			return true
	return false


static func craft(game: GameSim, recipe_id: String) -> bool:
	var check := can_craft(game, recipe_id)
	if not check["ok"]:
		Events.toast.emit(str(check["reason"]))
		return false
	var recipe := Data.recipe(recipe_id)
	var p := game.player
	# Consume ingredients.
	for ing: Dictionary in recipe.get("ingredients", []):
		p.remove_item(str(ing["id"]), int(ing.get("qty", 1)))
	# Produce.
	var result_id := str(recipe["result"])
	var qty := int(recipe.get("result_qty", 1))
	if not p.add_item(result_id, qty):
		# Drop at feet if inventory full.
		game.current_map().add_ground_item(p.pos, result_id, qty)
	var result_def := Data.item(result_id)
	Events.toast.emit("Crafted %s." % str(result_def.get("name", result_id)))
	Events.item_crafted.emit(result_id)
	game.stats["items_crafted"] += qty
	# Skill xp + time.
	var skill := str(recipe.get("skill", "fabrication"))
	if skill != "":
		p.add_skill_xp(skill, float(recipe.get("skill_xp", 8.0)))
	game.turn_manager.spend(game.turn_manager.player_action_cost(int(recipe.get("time_cost", 200))))
	return true


static func available_recipes() -> Array[String]:
	var out: Array[String] = []
	var recipes: Dictionary = Data.db.get("recipes", {})
	for rid: String in recipes:
		out.append(rid)
	out.sort()
	return out