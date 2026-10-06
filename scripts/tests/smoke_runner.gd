class_name SmokeRunner
extends RefCounted
## Automated smoke tests driven through the real game boot (autoloads active).
## Run with: godot --headless --path . -- --test
## Exits 0 on pass, 1 on failure. Prints PASS/FAIL lines.

var failures: Array[String] = []
var checks: int = 0


static func should_run() -> bool:
	return "--test" in OS.get_cmdline_user_args()


static func should_run_gen() -> bool:
	return "--testgen" in OS.get_cmdline_user_args()


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + label)
	else:
		failures.append(label)
		print("FAIL: " + label)


func run(controller: Node) -> int:
	failures.clear()
	print("=== DEAD TIDE SMOKE TESTS ===")

	# --- 1. Sim boot: reuse the game the controller already created.
	var game: GameSim = controller.game
	check(game != null, "game exists")
	check(game.player != null and game.player.alive, "player alive")
	var map: WorldMap = game.current_map()
	check(map.width == 128 and map.height == 128, "map 128x128")

	# --- 2. Movement changes position and spends turns.
	var start := game.player.pos
	var moved := 0
	for i: int in 6:
		if game.player_move(Vector2i(1, 0)):
			moved += 1
	check(moved >= 1, "player moved (%d/6 attempts)" % moved)
	check(game.player.pos != start, "position changed")
	check(game.clock_minutes > 6 * 60, "clock advanced")

	# --- 3. Gathering a palm yields resources.
	var palm_pos := Vector2i(-1, -1)
	for p: Vector2i in map.features.keys():
		if str(map.features[p].get("kind")) == "palm":
			palm_pos = p
			break
	check(palm_pos.x >= 0, "palm exists on map")
	if palm_pos.x >= 0:
		game.player.pos = palm_pos
		var before := game.player.count_item("log") + game.player.count_item("palm_leaf") + game.player.count_item("coconut")
		# Harvest until destroyed (60 hp / axe power 45 -> 2 hits max, hand 15 -> 4).
		var attempts := 0
		while map.feature(palm_pos).get("kind", "") == "palm" and attempts < 6:
			game.player_gather()
			attempts += 1
		var after := game.player.count_item("log") + game.player.count_item("palm_leaf") + game.player.count_item("coconut")
		check(after > before or map.ground_items.size() > 0, "palm yielded resources")

	# --- 4. Crafting: grant materials, craft cordage then stone knife.
	game.player.add_item("plant_fiber", 6)
	game.player.add_item("stone", 3)
	game.player.add_item("stick", 2)
	check(Crafting.can_craft(game, "cordage")["ok"], "cordage craftable")
	check(Crafting.craft(game, "cordage"), "cordage crafted")
	check(Crafting.craft(game, "stone_knife"), "stone knife crafted")
	check(game.player.count_item("stone_knife") == 1, "stone knife in inventory")
	check(game.stats["items_crafted"] >= 2, "craft stat incremented")

	# --- 5. Food + water consumption.
	game.player.add_item("coconut", 1)
	var hunger_before := game.player.hunger
	check(game.player_eat_or_drink("coconut"), "coconut consumed")
	check(game.player.hunger > hunger_before or game.player.thirst > 0.0, "eating restored meters")

	# --- 6. Building a campfire.
	game.player.add_item("stone", 6)
	game.player.add_item("stick", 6)
	var built := false
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Building.build(game, "campfire", game.player.pos + d):
			built = true
			break
	check(built, "campfire built")

	# --- 7. Save / load roundtrip.
	var seed_before := game.world_seed
	var pos_before := game.player.pos
	var minute_before := game.clock_minutes
	check(SaveManager.save_game(game, 9), "save succeeded")
	var loaded := SaveManager.load_game(9)
	check(loaded != null, "load succeeded")
	if loaded != null:
		check(loaded.world_seed == seed_before, "seed roundtrip")
		check(loaded.player.pos == pos_before, "position roundtrip")
		check(loaded.clock_minutes == minute_before, "clock roundtrip")
		check(loaded.player.count_item("stone_knife") == 1, "inventory roundtrip")
		check(loaded.current_map().serialize()["tiles_b64"] == map.serialize()["tiles_b64"], "terrain roundtrip")

	# --- 8. Creature exists and combat resolution kills eventually.
	var creature: Actor = null
	for a: Actor in loaded.actors if loaded != null else game.actors:
		if a.kind == "creature" and a.alive:
			creature = a
			break
	check(creature != null, "creature spawned")
	if creature != null:
		# Force adjacent, then attack repeatedly with boosted damage-free hands.
		loaded.player.pos = creature.pos + Vector2i(0, -1)
		var guard := 0
		while creature.alive and guard < 30:
			Combat.resolve_attack(loaded.player, creature, loaded)
			guard += 1
		check(not creature.alive, "creature died in combat")
		check(loaded.stats["creatures_killed"] >= 1, "kill counted")

	# --- 9. Raft build + board.
	loaded.player.capacity_weight = 200.0  # test harness: bypass carry limits
	loaded.player.capacity_volume = 400.0
	loaded.player.add_item("log", 6)
	loaded.player.add_item("cordage", 6)
	loaded.player.add_item("palm_leaf", 2)
	var raft_built := false
	var shoreline := Vector2i(-1, -1)
	var lmap: WorldMap = loaded.current_map()
	for y: int in lmap.height:
		for x: int in lmap.width:
			if lmap.tile(Vector2i(x, y)) == Terrain.T.SHALLOW:
				var near_land := false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					if lmap.is_clear_for_walk(Vector2i(x, y) + d):
						near_land = true
						break
				if near_land:
					shoreline = Vector2i(x, y)
					break
		if shoreline.x >= 0:
			break
	check(shoreline.x >= 0, "shallow shoreline exists")
	if shoreline.x >= 0:
		var rb_check := Building.can_build(loaded, "raft", shoreline)
		print("RAFT can_build: ok=%s reason=%s tile=%d" % [str(rb_check["ok"]), str(rb_check["reason"]), lmap.tile(shoreline)])
		Building.build(loaded, "raft", shoreline)
		raft_built = loaded.rafts.size() > 0
		check(raft_built, "raft built")
		if raft_built:
			# Teleport near raft, board, move into ocean, disembark impossible mid-sea.
			var rid: int = loaded.rafts.keys()[0]
			loaded.player.pos = shoreline + Vector2i(0, 1)
			check(loaded.board_raft(rid), "boarded raft")
			check(loaded.player_raft_id == rid, "aboard raft")
			# Sail into ocean: move north until deep water reached.
			var reached_deep := false
			for i: int in 40:
				if not loaded.player_move(Vector2i(0, -1)):
					break
				if loaded.current_map().tile(loaded.player.pos) == Terrain.T.DEEP_OCEAN:
					reached_deep = true
					break
			check(reached_deep, "raft sails to deep ocean")
			loaded.player_wait()

	# --- 9b. Island travel + fishing + POI loot.
	if raft_built:
		var sail_ok := loaded.travel_to(1)
		check(sail_ok, "traveled to island 1")
		if sail_ok:
			check(loaded.current_island_id == 1, "current island switched")
			check(bool(loaded.islands[1]["discovered"]), "island 1 discovered")
			check(loaded.stats["islands_discovered"] >= 2, "discovery stat incremented")
			check(loaded.current_map().tile(loaded.player.pos) == Terrain.T.SHALLOW, "arrived on shallow shore")
			# Fish beside the shore.
			var fish_ok := loaded.player_fish()
			check(fish_ok, "fishing action resolves")
			check(loaded.player.skills.get("fishing", 0.0) > 0.0, "fishing xp gained")
			# POI loot exists somewhere on wreck islands; verify a container works.
			var container_found := false
			var poi_count := 0
			for pos: Vector2i in loaded.current_map().structures:
				var s: Dictionary = loaded.current_map().structures[pos]
				if bool(s.get("container", false)) and (s.get("items", []) as Array).size() > 0:
					container_found = true
					break
			check(container_found, "loot container exists on new island")

	# --- 10. Reproducibility: same seed -> same terrain.
	var seed_used: int = int(controller.world_seed)
	var sim_a := GameSim.new()
	sim_a.new_game(seed_used)
	var sim_b := GameSim.new()
	sim_b.new_game(seed_used)
	check(sim_a.current_map().serialize()["tiles_b64"] == sim_b.current_map().serialize()["tiles_b64"], "seed reproducibility")

	print("=== %d checks, %d failures ===" % [checks, failures.size()])
	for f: String in failures:
		print("FAILED: " + f)
	return 0 if failures.is_empty() else 1


static func run_generation_validation(n: int) -> int:
	## Validates n worlds: spawn valid, land, shoreline, resources present.
	var bad: Array[String] = []
	var required_features: Array[String] = ["palm", "fiber_plant", "rock_outcrop", "driftwood"]
	for i: int in n:
		var seed_value := 100000 + i * 7919
		var map := WorldGen.generate_island(0, seed_value)
		var land := 0
		var shallow := 0
		for t: int in map.tiles:
			if not Terrain.is_water(t):
				land += 1
			elif t == Terrain.T.SHALLOW:
				shallow += 1
		if land < 300:
			bad.append("seed %d: only %d land tiles" % [seed_value, land])
		if shallow < 40:
			bad.append("seed %d: only %d shallow tiles" % [seed_value, shallow])
		var spawn: Vector2i = map.get_meta("spawn", Vector2i(-1, -1))
		if not map.is_clear_for_walk(spawn):
			bad.append("seed %d: spawn invalid" % seed_value)
		var counts: Dictionary = {}
		for kind: String in required_features:
			counts[kind] = 0
		for p: Vector2i in map.features:
			var k := str(map.features[p].get("kind"))
			if counts.has(k):
				counts[k] += 1
		for kind: String in required_features:
			if counts[kind] < 3:
				bad.append("seed %d: %s count %d < 3" % [seed_value, kind, counts[kind]])
	print("=== GENERATION VALIDATION: %d seeds, %d problems ===" % [n, bad.size()])
	for b: String in bad:
		print("GEN-FAIL: " + b)
	return 0 if bad.is_empty() else 1