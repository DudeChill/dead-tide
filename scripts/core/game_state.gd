class_name GameSim
extends RefCounted
## Central simulation. Owns islands, actors, clock, weather, rafts, and the
## player. Pure data + logic; presentation reads state and emits via Events.

const SAVE_VERSION := 1

var world_seed: int = 0
var islands: Dictionary = {}   # island_id -> {"map": WorldMap, "pos": Vector2, "name": String, "discovered": bool, "difficulty": String}
var current_island_id: int = 0
var actors: Array[Actor] = []
var player: Actor = null
var turn_count: int = 0
var clock_minutes: int = 0     # minutes elapsed since day 1, 00:00
var weather: String = "clear"
var weather_left: int = 0      # minutes until next weather roll
var rng: SimRng = null
var rafts: Dictionary = {}     # raft_id -> raft data dict
var player_raft_id: int = 0
## aggregate stats for death screen
var stats: Dictionary = {"tiles_traveled": 0, "islands_discovered": 1,
	"creatures_killed": 0, "items_crafted": 0, "days_survived": 0,
	"cause_of_death": ""}
var events_log: Array[String] = []

var turn_manager: TurnManager = null


func _init() -> void:
	turn_manager = TurnManager.new(self)


func rng_for_world() -> SimRng:
	return rng


# ---------------------------------------------------------------- lifecycle

func new_game(seed_value: int) -> void:
	world_seed = seed_value
	rng = SimRng.new(seed_value * 7 + 13)
	islands.clear()
	actors.clear()
	rafts.clear()
	clock_minutes = 6 * 60  # wake at 06:00
	weather = "clear"
	weather_left = int(Data.balance("weather_min_minutes", 240))
	stats = {"tiles_traveled": 0, "islands_discovered": 1, "creatures_killed": 0,
		"items_crafted": 0, "days_survived": 0, "cause_of_death": ""}

	_archipelago()
	_spawn_player()
	_spawn_creatures(current_island_id, "starter")
	Events.world_regenerated.emit()
	Events.log_msg.emit("new game: seed %d" % world_seed, "info")


func _archipelago() -> void:
	# Deterministic island layout on a world map scale.
	var layout: Array = [
		{"id": 0, "name": "Shore of Arrival", "quality": "starter", "difficulty": "calm", "pos": Vector2(0, 0)},
		{"id": 1, "name": "Green Bounty", "quality": "rich", "difficulty": "mild", "pos": Vector2(240, 40)},
		{"id": 2, "name": "Shipwreck Shoals", "quality": "wreck", "difficulty": "mild", "pos": Vector2(-160, 160)},
		{"id": 3, "name": "Screaming Rocks", "quality": "danger", "difficulty": "hostile", "pos": Vector2(120, -220)},
	]
	for spec: Dictionary in layout:
		var seed_i: int = (world_seed * 2654435761 + spec["id"] * 97) & 0x7FFFFFFF
		var map := WorldGen.generate_island(spec["id"], seed_i, WorldGen.MAP_W, WorldGen.MAP_H, str(spec["quality"]))
		islands[int(spec["id"])] = {
			"map": map,
			"pos": spec["pos"],
			"name": str(spec["name"]),
			"discovered": spec["id"] == 0,
			"difficulty": str(spec["difficulty"]),
		}
	current_island_id = 0


func _spawn_player() -> void:
	var map := current_map()
	var spawn: Vector2i = map.get_meta("spawn", Vector2i(map.width / 2, map.height / 2))
	player = Actor.make_player(spawn, current_island_id)
	actors.append(player)
	_reveal_around(player.pos, 8)


func _spawn_creatures(island_id: int, difficulty: String) -> void:
	var map: WorldMap = islands[island_id]["map"]
	var counts: Dictionary = {
		"starter": {"crab": 6, "boar": 2, "snake": 2},
		"rich": {"crab": 4, "boar": 4, "snake": 3},
		"wreck": {"crab": 5, "snake": 3, "hostile_survivor": 2},
		"danger": {"boar": 3, "snake": 4, "hostile_survivor": 4},
	}
	var plan: Dictionary = counts.get(difficulty, counts["starter"])
	for species: String in plan:
		var def := Data.creature(species)
		if def.is_empty():
			continue
		for _i: int in int(plan[species]):
			var t := map.find_tile(rng, func(p: Vector2i) -> bool:
				return map.is_clear_for_walk(p) and p.distance_to(map.get_meta("spawn", player.pos)) > 15.0)
			if t.x < 0:
				continue
			var a := Actor.make_creature(species, def, t, island_id)
			actors.append(a)


# ---------------------------------------------------------------- helpers

func current_map() -> WorldMap:
	return islands[current_island_id]["map"]


func actor_at(pos: Vector2i) -> Actor:
	for a: Actor in actors:
		if a.alive and a.pos == pos:
			return a
	return null


func actors_on_current_island() -> Array[Actor]:
	var out: Array[Actor] = []
	for a: Actor in actors:
		if a.island_id == current_island_id and a.alive:
			out.append(a)
	return out


func raft_at(pos: Vector2i) -> Dictionary:
	for rid: int in rafts:
		var r: Dictionary = rafts[rid]
		if int(r.get("island_id")) == current_island_id and Vector2i(r["pos"][0], r["pos"][1]) == pos:
			return r
	return {}


func hour() -> int:
	return (clock_minutes / 60) % 24


func day() -> int:
	return clock_minutes / 1440 + 1


func is_night() -> bool:
	var h := hour()
	return h >= 19 or h < 5


# ---------------------------------------------------------------- clock + survival

func advance_clock(ap: int) -> void:
	## 100 AP == 1 minute. Survival meters tick only for the player.
	var minutes := int(ap / 100.0)
	var minutes_fraction := float(ap % 100) / 100.0
	var prev_day := day()
	_tick_minutes(minutes)
	_tick_minutes_fraction(minutes_fraction)
	if day() != prev_day:
		Events.day_changed.emit(day())
	stats["days_survived"] = day() - 1


func _tick_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	clock_minutes += minutes
	weather_left -= minutes
	if weather_left <= 0:
		_roll_weather()
	_tick_survival(float(minutes))
	_tick_structures(minutes)


func _tick_minutes_fraction(frac: float) -> void:
	if frac <= 0.0:
		return
	_tick_survival(frac)


func _roll_weather() -> void:
	var roll := rng.randf()
	var next_weather := "clear"
	if roll < 0.50:
		next_weather = "clear"
	elif roll < 0.75:
		next_weather = "cloudy"
	elif roll < 0.92:
		next_weather = "rain"
	else:
		next_weather = "storm"
	weather_left = int(Data.balance("weather_duration_minutes", 180)) + rng.randi_range(-60, 120)
	if next_weather != weather:
		weather = next_weather
		Events.weather_changed.emit(weather)


func _tick_survival(minutes: float) -> void:
	var p := player
	if p == null or not p.alive:
		return
	var bal_hunger: float = Data.balance("hunger_per_hour", 3.0)
	var bal_thirst: float = Data.balance("thirst_per_hour", 4.5)
	var bal_fatigue: float = Data.balance("fatigue_per_hour", 2.5)
	var h := minutes / 60.0
	p.hunger = clampf(p.hunger - bal_hunger * h, 0.0, 100.0)
	p.thirst = clampf(p.thirst - bal_thirst * h, 0.0, 100.0)
	p.fatigue = clampf(p.fatigue - bal_fatigue * h, 0.0, 100.0)
	# Stamina regen, slower when hungry or tired.
	var regen: float = Data.balance("stamina_regen_per_hour", 20.0)
	if p.hunger < 25.0 or p.thirst < 25.0:
		regen *= 0.5
	if p.fatigue < 20.0:
		regen *= 0.5
	if is_night() and weather != "clear":
		regen *= 0.9
	p.stamina = clampf(p.stamina + regen * h, 0.0, 100.0)
	# Bleeding drains hp; pain rises.
	if p.any_bleeding():
		var bleed_dmg := int(Data.balance("bleeding_hp_per_minute", 1)) * int(minutes)
		if bleed_dmg > 0:
			_damage_part(p, "torso", bleed_dmg, false)
		p.pain = clampf(p.pain + minutes * 0.2, 0.0, 100.0)
	p.pain = maxf(p.pain - minutes * 0.05, 0.0)
	# Starvation / dehydration damage.
	var dmg := 0
	if p.hunger <= 0.0:
		dmg += int(Data.balance("starvation_hp_per_hour", 8) * h)
	if p.thirst <= 0.0:
		dmg += int(Data.balance("dehydration_hp_per_hour", 12) * h)
	if dmg > 0:
		_damage_part(p, "torso", dmg, false)
	# Environment temperature effect.
	var ambient := _ambient_temperature()
	p.temperature += (37.0 + (ambient - 22.0) * 0.35 - p.temperature) * clampf(h * 0.8, 0.0, 1.0)
	if p.temperature < 33.0:
		_damage_part(p, "torso", int(Data.balance("cold_hp_per_hour", 6) * h), false)
	if p.is_dead():
		_kill_player("exposure and starvation" if dmg > 0 else "injuries")
	Events.meters_changed.emit()


func _ambient_temperature() -> float:
	var base := 27.0
	if is_night():
		base -= 8.0
	match weather:
		"rain": base -= 3.0
		"storm": base -= 5.0
		"cloudy": base -= 1.5
	# Warmth from nearby lit campfire or shelter.
	var p := player
	if p != null:
		for pos: Vector2i in _adjacent_and_current(p.pos):
			var s := current_map().structure(pos)
			if str(s.get("kind")) == "campfire" and float(s.get("fuel", 0)) > 0:
				base += 6.0
			if str(s.get("kind")) == "shelter":
				base += 2.5
	return base


func _adjacent_and_current(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for d: Vector2i in _dirs8():
		out.append(center + d)
	return out


func _dirs8() -> Array[Vector2i]:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _tick_structures(minutes: int) -> void:
	var map := current_map()
	for pos: Vector2i in map.structures.keys():
		var s: Dictionary = map.structures[pos]
		var kind := str(s.get("kind"))
		if kind == "campfire":
			var fuel := float(s.get("fuel", 0.0))
			if fuel > 0:
				fuel = maxf(fuel - minutes / 60.0, 0.0)
				s["fuel"] = fuel
		elif kind == "water_collector":
			if weather == "rain" or weather == "storm":
				s["water"] = float(s.get("water", 0.0)) + minutes * float(Data.balance("rain_collect_per_minute", 0.05))


func _damage_part(target: Actor, part: String, amount: int, allow_bleed: bool = true) -> void:
	var part_data: Dictionary = target.body.get(part, {})
	var hp := int(part_data.get("hp", 0)) - amount
	part_data["hp"] = maxi(hp, 0)
	if allow_bleed and amount >= int(Data.balance("bleed_threshold", 8)):
		part_data["bleeding"] = true
	target.body[part] = part_data
	Events.entity_damaged.emit(target.id, amount)
	if target.is_dead():
		target.alive = false
		Events.entity_died.emit(target.id, target.kind)
		if target == player:
			_kill_player("catastrophic injury")


func _kill_player(cause: String) -> void:
	if not player.alive:
		return
	player.alive = false
	stats["cause_of_death"] = cause
	stats["days_survived"] = day() - 1
	Events.player_died.emit(stats)


# ---------------------------------------------------------------- player actions

func player_move(dir: Vector2i) -> bool:
	if player == null or not player.alive:
		return false
	# Aboard a raft: move the raft.
	if player_raft_id != 0:
		return _move_raft(dir)
	var target := player.pos + dir
	var map := current_map()
	if not map.in_bounds(target):
		return false
	var occupant := actor_at(target)
	if occupant != null:
		return false
	if map.blocks_move(target):
		return false
	if not Terrain.is_passable(map.tile(target)):
		# Swimming: allowed into shallow water at stamina cost (and drowning risk
		# later). Deep water blocks on foot.
		if map.tile(target) == Terrain.T.SHALLOW:
			if player.stamina < 10.0:
				Events.toast.emit("Too exhausted to swim.")
				return false
			player.stamina = maxf(player.stamina - 15.0, 0.0)
			player.add_skill_xp("swimming", 2.0)
		else:
			return false
	var cost := turn_manager.player_action_cost(int(Data.balance("move_cost", 100)))
	var stamina_cost := 2.0 if Terrain.is_water(map.tile(target)) else 0.0
	player.stamina = maxf(player.stamina - stamina_cost, 0.0)
	player.pos = target
	stats["tiles_traveled"] += 1
	_reveal_around(target, _view_radius())
	Events.player_moved.emit(target)
	turn_manager.spend(cost)
	return true


func player_wait() -> void:
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("wait_cost", 100))))


func _view_radius() -> int:
	var base := 9
	if is_night():
		var has_light := false
		for it: Dictionary in player.inventory:
			if str(it.get("id")) == "flashlight":
				has_light = true
		base = 4 if not has_light else 7
	if weather == "storm":
		base = maxi(base - 2, 2)
	elif weather == "rain":
		base = maxi(base - 1, 2)
	return base


func _reveal_around(center: Vector2i, radius: int) -> void:
	var map := current_map()
	for y: int in range(maxi(center.y - radius, 0), mini(center.y + radius + 1, map.height)):
		for x: int in range(maxi(center.x - radius, 0), mini(center.x + radius + 1, map.width)):
			if Vector2i(x, y).distance_to(center) <= float(radius):
				map.set_explored(Vector2i(x, y), true)


func player_gather() -> bool:
	## Harvest a feature on the player's tile or an adjacent tile.
	var map := current_map()
	var candidates: Array[Vector2i] = _adjacent_and_current(player.pos)
	var target := Vector2i(-1, -1)
	var best_def: Dictionary = {}
	for p: Vector2i in candidates:
		var f := map.feature(p)
		if f.is_empty():
			continue
		# Prefer the tile the player stands on, else nearest.
		if target == Vector2i(-1, -1) or p == player.pos:
			target = p
			best_def = f
	if target == Vector2i(-1, -1):
		Events.toast.emit("Nothing to gather here.")
		return false
	var f := map.feature(target)
	var kind := str(f.get("kind"))
	var tool_power := _harvest_power(kind)
	var hp := int(f.get("hp", 10))
	hp -= tool_power
	if hp > 0:
		f["hp"] = hp
		map.features[target] = f
		Events.toast.emit("Working on %s (%d%% left)..." % [kind.replace("_", " "), int(100.0 * hp / float(f.get("max_hp", 100)))])
		turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("gather_cost", 150))))
		player.add_skill_xp("survival", 1.0)
		return true
	# Feature destroyed -> yields.
	map.remove_feature(target)
	var total_gathered := 0
	for y: Dictionary in f.get("yields", []):
		var qty_range: Array = y.get("qty", [1, 1])
		var qty := rng.randi_range(int(qty_range[0]), int(qty_range[1]))
		if qty <= 0:
			continue
		var item_id := str(y["id"])
		if player.add_item(item_id, qty):
			total_gathered += qty
		else:
			map.add_ground_item(target, item_id, qty)
			total_gathered += qty
	if total_gathered > 0:
		Events.toast.emit("Gathered %d item(s) from %s." % [total_gathered, kind.replace("_", " ")])
	player.add_skill_xp("survival", 3.0)
	Events.map_changed.emit()
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("gather_cost", 150))))
	return true


func _harvest_power(kind: String) -> int:
	## Tool-dependent harvest speed. Stone axe speeds wood; hammer speeds stone.
	var hand := player.equipped_item()
	var hand_id := str(hand.get("id"))
	var base := int(Data.balance("harvest_power_hand", 15))
	if kind in ["palm", "young_palm", "driftwood"]:
		if hand_id == "stone_axe":
			return int(Data.balance("harvest_power_axe", 45))
	elif kind == "rock_outcrop":
		if hand_id == "stone_axe":
			return int(Data.balance("harvest_power_axe", 45))
		if hand_id == "hammer":
			return int(Data.balance("harvest_power_hammer", 60))
	return base


func player_pickup() -> bool:
	var map := current_map()
	var items := map.ground_items_at(player.pos)
	if items.is_empty():
		Events.toast.emit("Nothing to pick up.")
		return false
	var picked := 0
	var leftovers: Array = []
	for it: Dictionary in items:
		if player.add_item(str(it["id"]), int(it["qty"])):
			picked += int(it["qty"])
			Events.item_picked_up.emit(str(it["id"]))
		else:
			leftovers.append(it)
	if leftovers.is_empty():
		map.ground_items.erase(player.pos)
	else:
		map.ground_items[player.pos] = leftovers
	if picked > 0:
		Events.toast.emit("Picked up %d item(s)." % picked)
		turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("pickup_cost", 50))))
		return true
	Events.toast.emit("Inventory full.")
	return false


func player_eat_or_drink(item_id: String) -> bool:
	var def := Data.item(item_id)
	if def.is_empty():
		return false
	if not player.remove_item(item_id, 1):
		return false
	var calories := float(def.get("calories", 0))
	var hydration := float(def.get("hydration", 0))
	player.hunger = clampf(player.hunger + calories * 0.1, 0.0, 100.0)
	player.thirst = clampf(player.thirst + hydration * 0.2, 0.0, 100.0)
	# Dirty water may cause illness (pain + hp risk).
	if bool(def.get("dirty", false)) and rng.chance(float(Data.balance("dirty_water_sickness_chance", 0.35))):
		player.pain = clampf(player.pain + 15.0, 0.0, 100.0)
		_damage_part(player, "torso", 6, false)
		Events.toast.emit("That water was foul. You feel sick.")
	if str(def.get("category")) == "medical":
		var heal := int(def.get("heal", 0))
		if heal > 0:
			_heal_player(heal)
		if bool(def.get("stops_bleeding", false)):
			for part: String in player.body:
				player.body[part]["bleeding"] = false
			player.pain = maxf(player.pain - 20.0, 0.0)
	Events.toast.emit("Consumed %s." % str(def.get("name", item_id)))
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("consume_cost", 50))))
	return true


func _heal_player(amount: int) -> void:
	# Heal the most damaged non-lethal part first.
	var order: Array[String] = ["l_leg", "r_leg", "l_arm", "r_arm", "torso", "head"]
	var remaining := amount
	for part: String in order:
		if remaining <= 0:
			break
		var part_data: Dictionary = player.body.get(part, {})
		var hp := int(part_data.get("hp", 0))
		var max_hp := int(part_data.get("max", 1))
		if hp < max_hp:
			var healed := mini(max_hp - hp, remaining)
			part_data["hp"] = hp + healed
			remaining -= healed
			player.body[part] = part_data


func player_equip(item_id: String) -> bool:
	if player.count_item(item_id) <= 0:
		return false
	var def := Data.item(item_id)
	var slot := str(def.get("slot", "hand"))
	player.equipment[slot] = {"id": item_id, "qty": 1, "durability": float(def.get("durability", 100.0))}
	Events.toast.emit("Equipped %s." % str(def.get("name", item_id)))
	Events.inventory_changed.emit()
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("equip_cost", 50))))
	return true


func player_unequip(slot: String) -> bool:
	if player.equipment.get(slot, {}).is_empty():
		return false
	player.equipment[slot] = {}
	Events.inventory_changed.emit()
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("equip_cost", 50))))
	return true


func player_attack(target: Actor) -> bool:
	if target == null or not target.alive:
		return false
	Combat.resolve_attack(player, target, self)
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("attack_cost", 100))))
	return true


func craft(recipe_id: String) -> bool:
	return Crafting.craft(self, recipe_id)


func build_structure(structure_id: String, pos: Vector2i) -> bool:
	return Building.build(self, structure_id, pos)


# ---------------------------------------------------------------- raft / boats

func build_raft_at(pos: Vector2i) -> int:
	var rid := Actor.next_id()
	rafts[rid] = {
		"id": rid, "island_id": current_island_id,
		"pos": [pos.x, pos.y], "components": {"float": 2, "deck": 2},
		"cargo": [], "name": "Raft #%d" % rid,
	}
	Events.structure_built.emit("raft", pos)
	return rid


func _move_raft(dir: Vector2i) -> bool:
	var r: Dictionary = rafts.get(player_raft_id, {})
	if r.is_empty():
		player_raft_id = 0
		return false
	var map := current_map()
	var pos := Vector2i(int(r["pos"][0]), int(r["pos"][1]))
	var target := pos + dir
	if not map.in_bounds(target):
		return false
	if not Terrain.is_boat_ok(map.tile(target)):
		# Beach the raft: if the target is walkable land, disembark there.
		if Terrain.is_passable(map.tile(target)):
			r["pos"] = [target.x, target.y]
			player_raft_id = 0
			player.pos = target
			Events.toast.emit("You beach the raft and step ashore.")
			_reveal_around(target, _view_radius())
			Events.player_moved.emit(target)
			turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("move_cost", 100))))
			return true
		return false
	r["pos"] = [target.x, target.y]
	player.pos = target
	stats["tiles_traveled"] += 1
	_reveal_around(target, _view_radius())
	Events.player_moved.emit(target)
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("boat_move_cost", 80))))
	return true


func board_raft(rid: int) -> bool:
	var r: Dictionary = rafts.get(rid, {})
	if r.is_empty():
		return false
	var rpos := Vector2i(int(r["pos"][0]), int(r["pos"][1]))
	if player.pos.distance_to(rpos) > 1.5:
		return false
	player_raft_id = rid
	player.pos = rpos
	Events.toast.emit("You climb aboard the raft.")
	Events.player_moved.emit(player.pos)
	turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("open_cost", 80))))
	return true


func disembark() -> bool:
	if player_raft_id == 0:
		return false
	var r: Dictionary = rafts[player_raft_id]
	var rpos := Vector2i(int(r["pos"][0]), int(r["pos"][1]))
	var map := current_map()
	for d: Vector2i in _dirs8():
		var t := rpos + d
		if map.is_clear_for_walk(t):
			player.pos = t
			player_raft_id = 0
			Events.toast.emit("You step off the raft.")
			Events.player_moved.emit(player.pos)
			turn_manager.spend(turn_manager.player_action_cost(int(Data.balance("move_cost", 100))))
			return true
	return false


# ---------------------------------------------------------------- creature turns

func run_creature_turn(a: Actor) -> void:
	if not a.alive:
		return
	var def := Data.creature(a.species)
	if def.is_empty():
		return
	a.energy -= int(Data.balance("creature_move_cost", 100))
	AIController.act(a, self, def)


func on_creature_died(a: Actor) -> void:
	if a.kind == "creature":
		stats["creatures_killed"] += 1
		# Drop loot on the ground.
		var map := current_map()
		for loot: Dictionary in Data.creature(a.species).get("loot", []):
			if rng.chance(float(loot.get("chance", 1.0))):
				map.add_ground_item(a.pos, str(loot["id"]), int(loot.get("qty", 1)))


# ---------------------------------------------------------------- save/load

func to_dict() -> Dictionary:
	var islands_data: Dictionary = {}
	for id: int in islands:
		var entry: Dictionary = islands[id]
		var map: WorldMap = entry["map"]
		islands_data[str(id)] = {
			"pos": [entry["pos"].x, entry["pos"].y],
			"name": entry["name"],
			"discovered": entry["discovered"],
			"difficulty": entry["difficulty"],
			"map": map.serialize(),
		}
	var rafts_data: Dictionary = {}
	for rid: int in rafts:
		rafts_data[str(rid)] = rafts[rid]
	var actors_data: Array = []
	for a: Actor in actors:
		actors_data.append(a.to_dict())
	return {
		"save_version": SAVE_VERSION,
		"world_seed": world_seed,
		"current_island_id": current_island_id,
		"actors": actors_data,
		"player_id": player.id if player != null else 0,
		"turn_count": turn_count,
		"clock_minutes": clock_minutes,
		"weather": weather,
		"weather_left": weather_left,
		"islands": islands_data,
		"rafts": rafts_data,
		"player_raft_id": player_raft_id,
		"stats": stats,
		"rng_state": rng.state(),
		"next_actor_id": Actor._next_id,
	}


static func from_dict(d: Dictionary) -> GameSim:
	var sim := GameSim.new()
	sim.world_seed = int(d.get("world_seed", 0))
	sim.current_island_id = int(d.get("current_island_id", 0))
	sim.turn_count = int(d.get("turn_count", 0))
	sim.clock_minutes = int(d.get("clock_minutes", 0))
	sim.weather = str(d.get("weather", "clear"))
	sim.weather_left = int(d.get("weather_left", 120))
	sim.stats = d.get("stats", sim.stats)
	sim.player_raft_id = int(d.get("player_raft_id", 0))
	var islands_data: Dictionary = d.get("islands", {})
	for id_str: String in islands_data:
		var entry: Dictionary = islands_data[id_str]
		var pos_arr: Array = entry["pos"]
		sim.islands[int(id_str)] = {
			"map": WorldMap.deserialize(entry["map"]),
			"pos": Vector2(int(pos_arr[0]), int(pos_arr[1])),
			"name": str(entry.get("name", "Island")),
			"discovered": bool(entry.get("discovered", false)),
			"difficulty": str(entry.get("difficulty", "mild")),
		}
	var rafts_data: Dictionary = d.get("rafts", {})
	for rid_str: String in rafts_data:
		sim.rafts[int(rid_str)] = rafts_data[rid_str]
	for ad: Dictionary in d.get("actors", []):
		var a := Actor.from_dict(ad)
		sim.actors.append(a)
		if a.id == int(d.get("player_id", 0)):
			sim.player = a
	sim.rng = SimRng.new(sim.world_seed)
	sim.rng.set_state(int(d.get("rng_state", 0)))
	Actor._next_id = int(d.get("next_actor_id", 1000))
	return sim