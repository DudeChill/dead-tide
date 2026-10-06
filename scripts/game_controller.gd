extends Node2D
## Main game controller: owns the simulation, wires input to actions,
## drives the renderer/camera/HUD, and hosts debug shortcuts.

@onready var renderer: IsoRenderer = IsoRenderer.new()
@onready var camera: Camera2D = preload("res://scripts/render/camera_rig.gd").new()
@onready var hud: CanvasLayer = preload("res://scripts/ui/hud.gd").new()

var game: GameSim = null
var world_seed: int = 0
var build_index: int = 0
var rng_ui: SimRng = null
## Pending digit-menu actions for contextual interaction menus.
var menu_actions: Array = []


func _ready() -> void:
	# Seed from command line for reproducible runs: godot -- --seed 12345
	world_seed = int(Data.balance("default_seed", 91837261))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			world_seed = int(arg.split("=")[1])
	game = GameSim.new()
	game.new_game(world_seed)
	hud.game = game
	renderer.game = game
	add_child(renderer)
	add_child(camera)
	camera.make_current()
	camera.zoom = Vector2(1.0, 1.0)
	add_child(hud)
	Events.toast.connect(hud.show_toast)
	Events.player_died.connect(_on_player_died)
	hud.show_toast("You wake on the shore of an unknown island...")
	rng_ui = SimRng.new(world_seed)
	# Automated test entry points (headless CI).
	if SmokeRunner.should_run_gen():
		var gen_code := SmokeRunner.run_generation_validation(100)
		print("GEN_RESULT %d" % gen_code)
		get_tree().quit(gen_code)
		return
	if SmokeRunner.should_run():
		var runner := SmokeRunner.new()
		var code := runner.run(self)
		print("TEST_RESULT %d" % code)
		get_tree().quit(code)
		return


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	renderer.global_position = renderer.tile_to_screen(game.player.pos)
	camera.target = renderer
	_update_context_hint()


func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.player == null:
		return
	# Panels first.
	if event.is_action_pressed("ui_menu"):
		_toggle_panel("pause")
		return
	if hud.any_panel_open():
		if hud.is_panel_open("menu") and event is InputEventKey and event.pressed:
			_handle_menu_digit(event)
			return
		if hud.is_panel_open("crafting") and event is InputEventKey and event.pressed:
			_handle_craft_key(event)
			return
		if hud.is_panel_open("building") and event is InputEventKey and event.pressed:
			_handle_build_key(event)
			return
		if hud.is_panel_open("pause") and event is InputEventKey and event.pressed:
			_handle_pause_key(event)
			return
		return
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("crafting"):
		_toggle_crafting()
		return
	if event.is_action_pressed("build"):
		_toggle_building()
		return
	if event.is_action_pressed("world_map"):
		_toggle_map()
		return
	if event.is_action_pressed("pickup"):
		game.player_pickup()
		return
	if event.is_action_pressed("interact"):
		_do_interact()
		_mark_poi_discovery()
		return
	if event.is_action_pressed("attack"):
		_do_attack()
		return
	if event.is_action_pressed("wait"):
		game.player_wait()
		return
	if event.is_action_pressed("debug_reveal"):
		_debug_reveal()
		return
	if event.is_action_pressed("debug_save"):
		SaveManager.save_game(game, 1)
		return
	if event.is_action_pressed("debug_load"):
		var loaded := SaveManager.load_game(1)
		if loaded != null:
			game = loaded
			hud.game = game
			renderer.game = game
			hud.show_toast("Loaded.")
		return
	if event.is_action_pressed("zoom_in"):
		camera.zoom = (camera.zoom * 1.15).clamp(Vector2(0.5, 0.5), Vector2(2.5, 2.5))
		return
	if event.is_action_pressed("zoom_out"):
		camera.zoom = (camera.zoom / 1.15).clamp(Vector2(0.5, 0.5), Vector2(2.5, 2.5))
		return
	if event.is_action_pressed("debug_menu"):
		_toggle_debug_panel()
		return
	# Movement.
	for pair: Array in [
		["move_n", Vector2i(0, -1)], ["move_s", Vector2i(0, 1)],
		["move_w", Vector2i(-1, 0)], ["move_e", Vector2i(1, 0)],
		["move_ne", Vector2i(1, -1)], ["move_nw", Vector2i(-1, -1)],
		["move_se", Vector2i(1, 1)], ["move_sw", Vector2i(-1, 1)],
	]:
		if event.is_action_pressed(pair[0]):
			game.player_move(pair[1])
			return


func _toggle_inventory() -> void:
	if hud.is_panel_open("inventory"):
		hud.close_panel()
		return
	var p := game.player
	var lines: Array[String] = []
	lines.append("[b]Inventory[/b]  (%.1f/%.1f kg, %.1f/%.1f L)" % [p.total_weight(), p.capacity_weight, p.total_volume(), p.capacity_volume])
	for it: Dictionary in p.inventory:
		var def := Data.item(str(it["id"]))
		lines.append("%s x%d  (%.1f kg)  %s" % [str(def.get("name", it["id"])), int(it["qty"]), float(def.get("weight", 0)) * int(it["qty"]), _item_note(str(it["id"]))])
	var hand := str(p.equipped_item().get("id"))
	lines.append("\nEquipped: %s" % (Data.item(hand).get("name", "bare hands") if hand != "" else "bare hands"))
	lines.append("[i]Press F while beside a creature to attack with the held item.[/i]")
	hud.open_panel("inventory", "Inventory", "\n".join(lines))


func _item_note(item_id: String) -> String:
	var def := Data.item(item_id)
	match str(def.get("category")):
		"food":
			return "E eats it (in interact menu near you)."
		"water":
			return "Drinkable via interact menu."
		"tool", "weapon":
			return "Equip via interact menu."
	return ""


func _toggle_crafting() -> void:
	if hud.is_panel_open("crafting"):
		hud.close_panel()
		return
	var lines: Array[String] = []
	var idx := 1
	for rid: String in Crafting.available_recipes():
		var recipe := Data.recipe(rid)
		var check := Crafting.can_craft(game, rid)
		var mark := "[color=green]OK[/color]" if check["ok"] else "[color=red]--[/color]"
		var result_name := str(Data.item(str(recipe["result"])).get("name", rid))
		lines.append("%d) %s %s  [%s]" % [idx, mark, result_name, str(check["reason"])])
		idx += 1
	lines.append("\n[i]Press the recipe number to craft. Stations must be adjacent.[/i]")
	hud.open_panel("crafting", "Crafting", "\n".join(lines))


func _handle_craft_key(event: InputEvent) -> void:
	var idx := int(event.keycode) - int(KEY_1)
	var recipes := Crafting.available_recipes()
	if idx >= 0 and idx < recipes.size():
		if Crafting.craft(game, recipes[idx]):
			_toggle_crafting()
			_toggle_crafting()
		else:
			hud.show_toast(str(Crafting.can_craft(game, recipes[idx])["reason"]))


func _toggle_building() -> void:
	if hud.is_panel_open("building"):
		hud.close_panel()
		return
	var lines: Array[String] = []
	var idx := 1
	for sid: String in Building.STRUCTURE_ORDER:
		var def := Data.structure(sid)
		var parts: Array[String] = []
		for ing: Dictionary in def.get("ingredients", []):
			var have := game.player.count_item(str(ing["id"]))
			parts.append("%s %d/%d" % [str(Data.item(str(ing["id"])).get("name", ing["id"])), have, int(ing["qty"])])
		lines.append("%d) %s — %s" % [idx, str(def.get("name", sid)), ", ".join(parts)])
		idx += 1
	lines.append("\n[i]Press the number to place on your tile (or nearest free adjacent tile).[/i]")
	hud.open_panel("building", "Build", "\n".join(lines))


func _handle_build_key(event: InputEvent) -> void:
	var idx := int(event.keycode) - int(KEY_1)
	if idx < 0 or idx >= Building.STRUCTURE_ORDER.size():
		return
	var sid: String = Building.STRUCTURE_ORDER[idx]
	hud.close_panel()
	if str(Data.structure(sid).get("is_raft", false)):
		_build_raft_flow(sid)
		return
	# Place on player tile if valid, else nearest adjacent.
	var candidates: Array[Vector2i] = [game.player.pos]
	for d: Vector2i in game._dirs8():
		candidates.append(game.player.pos + d)
	for pos: Vector2i in candidates:
		if Building.can_build(game, sid, pos)["ok"]:
			Building.build(game, sid, pos)
			return
	hud.show_toast(str(Building.can_build(game, sid, game.player.pos)["reason"]))


func _build_raft_flow(sid: String) -> void:
	# Raft goes on the nearest shallow-water tile adjacent to walkable land.
	var map := game.current_map()
	var best := Vector2i(-1, -1)
	for pos: Vector2i in map.features.keys():
		pass  # features do not block raft placement search
	var found := false
	for y: int in range(maxi(game.player.pos.y - 12, 0), mini(game.player.pos.y + 12, map.height)):
		for x: int in range(maxi(game.player.pos.x - 12, 0), mini(game.player.pos.x + 12, map.width)):
			var p := Vector2i(x, y)
			if map.tile(p) != Terrain.T.SHALLOW:
				continue
			var near_land := false
			for d: Vector2i in game._dirs8():
				if map.is_clear_for_walk(p + d):
					near_land = true
					break
			if near_land and map.structure(p).is_empty():
				best = p
				found = true
				break
		if found:
			break
	if not found:
		hud.show_toast("No shoreline nearby for a raft.")
		return
	var check := Building.can_build(game, sid, best)
	if not check["ok"]:
		hud.show_toast(str(check["reason"]))
		return
	# Building.create raft entity (Building.build handles is_raft types).
	Building.build(game, sid, best)
	hud.show_toast("Raft built at the shoreline (%d, %d). Walk to it and press E to board." % [best.x, best.y])


func _toggle_map() -> void:
	if hud.is_panel_open("map"):
		hud.close_panel()
		return
	var lines: Array[String] = []
	lines.append("[b]Archipelago[/b] — discovered islands only")
	var origin: Vector2 = game.islands[game.current_island_id]["pos"]
	menu_actions = []
	var idx := 1
	var can_sail := game.player_raft_id != 0 and game.current_map().tile(game.player.pos) == Terrain.T.OCEAN and game.weather != "storm"
	for id: int in game.islands:
		var entry: Dictionary = game.islands[id]
		if not entry["discovered"]:
			continue
		var offset: Vector2 = entry["pos"] - origin
		var here := " (you are here)" if id == game.current_island_id else ""
		lines.append("• %s — %d km %s, %d km N%s" % [str(entry["name"]), int(absf(offset.x) / 10.0), "E" if offset.x >= 0 else "W", int(absf(offset.y) / 10.0), here])
		if can_sail and id != game.current_island_id:
			lines.append("  %d) Sail here" % idx)
			menu_actions.append({"type": "sail", "id": id})
			idx += 1
	if game.player_raft_id != 0:
		if game.current_map().tile(game.player.pos) == Terrain.T.SHALLOW:
			lines.append("\n[i]Sail into open ocean (move the raft onto deep water) to set a course.[/i]")
		elif game.weather == "storm":
			lines.append("\n[i]Storm at sea — no course can be set.[/i]")
	else:
		lines.append("\n[i]Sea travel becomes available once you build a raft.[/i]")
	if menu_actions.is_empty():
		hud.open_panel("map", "World Map", "\n".join(lines))
	else:
		lines.append("0) Close")
		hud.open_panel("menu", "World Map", "\n".join(lines))


func _mark_poi_discovery() -> void:
	var map := game.current_map()
	for pos: Vector2i in game._adjacent_and_current(game.player.pos):
		var s := map.structure(pos)
		if bool(s.get("poi", false)) and not s.get("discovered", false):
			s["discovered"] = true
			map.structures[pos] = s
			hud.show_toast("You discover: %s" % str(Data.structure(str(s["kind"])).get("name", s["kind"])))


func _toggle_panel(mode: String) -> void:
	if hud.panel_mode == mode and hud.any_panel_open():
		hud.close_panel()
		return
	match mode:
		"pause":
			hud.open_panel("pause", "Paused", "1) Resume\n2) Save game\n3) Load game\n4) New game\n5) Quit")
		_: pass


func _handle_pause_key(event: InputEvent) -> void:
	match int(event.keycode):
		KEY_1: hud.close_panel()
		KEY_2:
			SaveManager.save_game(game, 1)
			hud.show_toast("Game saved.")
		KEY_3:
			var loaded := SaveManager.load_game(1)
			if loaded != null:
				game = loaded
				hud.game = game
				renderer.game = game
				hud.close_panel()
				hud.show_toast("Game loaded.")
		KEY_4:
			game.new_game(int(Data.balance("default_seed", 91837261)) + randi() % 100000)
			hud.close_panel()
			hud.show_toast("New game.")
		KEY_5:
			get_tree().quit()
		_: pass


# ---------------------------------------------------------------- interactions

func _do_interact() -> void:
	if game.player_raft_id != 0:
		game.disembark()
		return
	var map := game.current_map()
	# 1) Raft nearby?
	for rid: int in game.rafts:
		var r: Dictionary = game.rafts[rid]
		var rpos := Vector2i(int(r["pos"][0]), int(r["pos"][1]))
		if game.player.pos.distance_to(rpos) <= 1.5:
			if game.board_raft(rid):
				return
	# 2) Structure here or adjacent.
	for p: Vector2i in game._adjacent_and_current(game.player.pos):
		var s := map.structure(p)
		if s.is_empty():
			continue
		match str(s.get("kind")):
			"campfire":
				_interact_campfire(s, p)
				return
			"storage_crate":
				_interact_crate(s)
				return
			"water_collector":
				_interact_collector(s)
				return
			"raft":
				for rid2: int in game.rafts:
					var rr: Dictionary = game.rafts[rid2]
					if Vector2i(int(rr["pos"][0]), int(rr["pos"][1])) == p:
						if game.board_raft(rid2):
							return
			"shelter":
				_interact_shelter()
				return
			_:
				pass
	# 3) Consume/equip from inventory via quick menu.
	_interact_inventory()
	return


func _interact_campfire(s: Dictionary, pos: Vector2i) -> void:
	var lines: Array[String] = []
	lines.append("1) Add fuel (1 stick → +1h)")
	lines.append("2) Cook (opens crafting)")
	lines.append("3) Extinguish")
	var fuel := float(s.get("fuel", 0))
	lines.append("Fuel: %.1fh %s" % [fuel, "(lit)" if fuel > 0 else "(out)"])
	lines.append("0) Cancel")
	menu_actions = [
		{"type": "campfire_fuel", "pos": pos},
		{"type": "open_crafting"},
		{"type": "campfire_out", "pos": pos},
	]
	hud.open_panel("menu", "Campfire", "\n".join(lines))


func _interact_crate(s: Dictionary) -> void:
	var items: Array = s.get("items", [])
	if items.is_empty():
		hud.show_toast("Crate is empty.")
		return
	var lines: Array[String] = []
	var idx := 1
	menu_actions = []
	for it: Dictionary in items:
		lines.append("%d) Take %s x%d" % [idx, str(Data.item(str(it["id"])).get("name", it["id"])), int(it["qty"])])
		menu_actions.append({"type": "crate_take", "index": idx - 1})
		idx += 1
	lines.append("0) Cancel")
	hud.open_panel("menu", "Storage Crate", "\n".join(lines))


func _interact_collector(s: Dictionary) -> void:
	var water := float(s.get("water", 0))
	if water < 1.0:
		hud.show_toast("Collector holds %.1f L. Wait for rain." % water)
		return
	if not game.player.remove_item("glass_bottle", 1):
		hud.show_toast("Need a glass bottle to bottle water.")
		return
	var bottles := int(minf(water, 5.0))
	if game.player.add_item("fresh_water", bottles):
		s["water"] = water - bottles
		hud.show_toast("Bottled %d fresh water." % bottles)
	else:
		game.player.add_item("glass_bottle", 1)
		hud.show_toast("No room for water.")


func _interact_shelter() -> void:
	var lines: Array[String] = []
	lines.append("1) Sleep until dawn")
	lines.append("2) Rest 1 hour")
	lines.append("0) Cancel")
	menu_actions = [
		{"type": "sleep"},
		{"type": "rest_hour"},
	]
	hud.open_panel("menu", "Shelter", "\n".join(lines))


func _sleep_until_dawn() -> void:
	var target_day_start := (game.day() + 1) * 1440
	var minutes_left := target_day_start - game.clock_minutes
	if minutes_left <= 0:
		minutes_left = 5
	game.advance_clock(minutes_left * 100)
	game.player.fatigue = 100.0
	game.player.stamina = 100.0
	hud.show_toast("You sleep until dawn.")


func _interact_inventory() -> void:
	var p := game.player
	var consumables: Array[String] = []
	var equippables: Array[String] = []
	for it: Dictionary in p.inventory:
		var id := str(it["id"])
		var def := Data.item(id)
		if str(def.get("category")) in ["food", "water", "medical"]:
			if not consumables.has(id):
				consumables.append(id)
		if def.has("slot") and id != str(p.equipped_item().get("id")):
			if not equippables.has(id):
				equippables.append(id)
	if consumables.is_empty() and equippables.is_empty():
		# Fall back to gather.
		game.player_gather()
		return
	var lines: Array[String] = []
	menu_actions = []
	var idx := 1
	# Fishing option when beside shallow water.
	var near_shallow := false
	for pos: Vector2i in game._adjacent_and_current(p.pos):
		if game.current_map().tile(pos) == Terrain.T.SHALLOW:
			near_shallow = true
			break
	if near_shallow:
		lines.append("%d) Fish" % idx)
		menu_actions.append({"type": "fish"})
		idx += 1
	for id: String in consumables:
		lines.append("%d) Consume %s" % [idx, str(Data.item(id).get("name", id))])
		menu_actions.append({"type": "consume", "id": id})
		idx += 1
	for id: String in equippables:
		lines.append("%d) Equip %s" % [idx, str(Data.item(id).get("name", id))])
		menu_actions.append({"type": "equip", "id": id})
		idx += 1
	lines.append("0) Cancel")
	hud.open_panel("menu", "Use / Equip", "\n".join(lines))


func _handle_menu_digit(event: InputEvent) -> void:
	var digit := int(event.keycode) - int(KEY_0)
	if digit < 0 or digit > 9:
		return
	if digit == 0:
		hud.close_panel()
		menu_actions = []
		return
	if digit > menu_actions.size():
		return
	var action: Dictionary = menu_actions[digit - 1]
	hud.close_panel()
	menu_actions = []
	match str(action.get("type")):
		"campfire_fuel":
			var pos: Vector2i = action["pos"]
			var s: Dictionary = game.current_map().structures.get(pos, {})
			if game.player.remove_item("stick", 1):
				s["fuel"] = minf(float(s.get("fuel", 0)) + 1.0, float(Data.structure("campfire").get("fuel_max", 6)))
				game.current_map().structures[pos] = s
				hud.show_toast("Fire fed.")
				game.player_wait()
			else:
				hud.show_toast("No sticks for fuel.")
		"open_crafting":
			_toggle_crafting()
		"campfire_out":
			var pos2: Vector2i = action["pos"]
			var s2: Dictionary = game.current_map().structures.get(pos2, {})
			s2["fuel"] = 0.0
			game.current_map().structures[pos2] = s2
			hud.show_toast("Fire extinguished.")
		"crate_take":
			_crate_take(int(action["index"]))
		"sleep":
			_sleep_until_dawn()
		"rest_hour":
			game.advance_clock(60 * 100)
			game.player.fatigue = clampf(game.player.fatigue + 20.0, 0.0, 100.0)
			hud.show_toast("You rest for an hour.")
		"consume":
			game.player_eat_or_drink(str(action["id"]))
		"equip":
			game.player_equip(str(action["id"]))
		"fish":
			game.player_fish()
		"sail":
			game.travel_to(int(action["id"]))
		"dbg":
			_debug_apply(str(action["op"]))
		_:
			pass


func _crate_take(index: int) -> void:
	# Find the crate the menu was opened from (nearest structure of kind crate).
	var map := game.current_map()
	var target := Vector2i(-1, -1)
	for pos: Vector2i in game._adjacent_and_current(game.player.pos):
		if str(map.structure(pos).get("kind")) == "storage_crate":
			target = pos
			break
	if target == Vector2i(-1, -1):
		return
	var s: Dictionary = map.structures[target]
	var items: Array = s.get("items", [])
	if index >= items.size():
		return
	var it: Dictionary = items[index]
	if game.player.add_item(str(it["id"]), int(it["qty"])):
		items.remove_at(index)
		hud.show_toast("Taken.")
	else:
		hud.show_toast("No room.")


func _do_attack() -> void:
	var target := game.actor_at(game.player.pos + Vector2i(0, -1))
	if target == null:
		target = game.actor_at(game.player.pos + Vector2i(0, 1))
	if target == null:
		target = game.actor_at(game.player.pos + Vector2i(1, 0))
	if target == null:
		target = game.actor_at(game.player.pos + Vector2i(-1, 0))
	if target == null:
		for d: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			target = game.actor_at(game.player.pos + d)
			if target != null:
				break
	if target == null:
		hud.show_toast("No creature in reach.")
		return
	game.player_attack(target)


func _update_context_hint() -> void:
	var p := game.player
	if p == null or not p.alive:
		return
	var map := game.current_map()
	var hint := ""
	for pos: Vector2i in game._adjacent_and_current(p.pos):
		var s := map.structure(pos)
		if not s.is_empty():
			hint = "E: " + str(Data.structure(str(s["kind"])).get("name", s["kind"]))
			break
	if hint == "" and not map.ground_items_at(p.pos).is_empty():
		hint = "G: pick up items"
	if hint == "":
		var has_feature := false
		for pos: Vector2i in game._adjacent_and_current(p.pos):
			if not map.feature(pos).is_empty():
				has_feature = true
				break
		if has_feature:
			hint = "E: gather"
	if game.player_raft_id != 0:
		hint = "Aboard raft — WASD sails, E disembarks at shore"
	hint_label_note(hint)


func hint_label_note(text: String) -> void:
	var labels := hud.get_children()
	for n: Node in labels:
		if n is Label and (n as Label).text.begins_with("WASD"):
			(n as Label).text = ("WASD move · E gather/interact · G pick up · F attack · C craft · B build · I inventory · M map · SPACE wait" if text == "" else text + "   (SPACE wait)")
			return


func _on_player_died(stats: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("[b]YOU DIED[/b]")
	lines.append("Cause: %s" % str(stats.get("cause_of_death", "unknown")))
	lines.append("Days survived: %d" % int(stats.get("days_survived", 0)))
	lines.append("Tiles traveled: %d" % int(stats.get("tiles_traveled", 0)))
	lines.append("Islands discovered: %d" % int(stats.get("islands_discovered", 1)))
	lines.append("Creatures killed: %d" % int(stats.get("creatures_killed", 0)))
	lines.append("Items crafted: %d" % int(stats.get("items_crafted", 0)))
	lines.append("\n[i]Press 4 in the pause menu (ESC) for a new game.[/i]")
	hud.open_panel("dead", "Dead Tide", "\n".join(lines))


# ---------------------------------------------------------------- debug

func _debug_reveal() -> void:
	var map := game.current_map()
	for y: int in map.height:
		for x: int in map.width:
			map.set_explored(Vector2i(x, y), true)
	hud.show_toast("Debug: map revealed.")


func _toggle_debug_panel() -> void:
	if hud.is_panel_open("menu") and menu_actions.size() > 0 and str(menu_actions[0].get("type")) == "dbg":
		hud.close_panel()
		menu_actions = []
		return
	var lines: Array[String] = []
	lines.append("[b]DEBUG[/b] (dev only)")
	lines.append("1) Heal full + stop bleeding")
	lines.append("2) Refill stamina/fatigue")
	lines.append("3) Give starter materials")
	lines.append("4) Spawn creature adjacent")
	lines.append("5) Skip to next dawn")
	lines.append("6) Teleport to shoreline")
	menu_actions = [
		{"type": "dbg", "op": "heal"}, {"type": "dbg", "op": "stamina"},
		{"type": "dbg", "op": "mats"}, {"type": "dbg", "op": "creature"},
		{"type": "dbg", "op": "dawn"}, {"type": "dbg", "op": "shore"},
	]
	hud.open_panel("menu", "Debug", "\n".join(lines))


func _debug_apply(op: String) -> void:
	var p := game.player
	match op:
		"heal":
			for part: String in p.body:
				p.body[part]["hp"] = int(p.body[part]["max"])
				p.body[part]["bleeding"] = false
			p.alive = true
			p.pain = 0.0
			hud.show_toast("Debug: healed.")
		"stamina":
			p.stamina = 100.0
			p.fatigue = 100.0
			hud.show_toast("Debug: rested.")
		"mats":
			p.capacity_weight = 500.0
			p.capacity_volume = 500.0
			for item: Array in [["stone", 10], ["stick", 10], ["plant_fiber", 10], ["cordage", 6], ["log", 8], ["palm_leaf", 8]]:
				p.add_item(str(item[0]), int(item[1]))
			hud.show_toast("Debug: materials granted.")
		"creature":
			var species: String = ["crab", "boar", "snake", "hostile_survivor"][rng_ui.randi_range(0, 3)]
			var def := Data.creature(species)
			var t := p.pos + Vector2i(1, 0)
			if game.current_map().is_clear_for_walk(t):
				game.actors.append(Actor.make_creature(species, def, t, game.current_island_id))
				hud.show_toast("Debug: spawned %s east of you." % str(def.get("name", species)))
		"dawn":
			var target := (game.day() + 1) * 1440 + 5 * 60
			game.advance_clock((target - game.clock_minutes) * 100)
			hud.show_toast("Debug: time skipped.")
		"shore":
			var map := game.current_map()
			for y: int in map.height:
				for x: int in map.width:
					if map.tile(Vector2i(x, y)) == Terrain.T.SHALLOW:
						for d: Vector2i in game._dirs8():
							if map.is_clear_for_walk(Vector2i(x, y) + d):
								p.pos = Vector2i(x, y) + d
								game._reveal_around(p.pos, game._view_radius())
								hud.show_toast("Debug: teleported to shore.")
								return
			hud.show_toast("Debug: no shore found.")
		_: pass