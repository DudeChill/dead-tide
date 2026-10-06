class_name WorldGen
extends RefCounted
## Procedural island generator. Layered: island mask -> elevation -> moisture
## -> terrain -> vegetation -> resources -> spawn point. Deterministic per seed.

const MAP_W := 128
const MAP_H := 128

# Feature definitions (kind -> def). Data-driven via Data autoload when present,
# but core generator keeps a local copy so tests run without the autoload.
const FEATURES: Dictionary = {
	"palm": {"hp": 60, "blocks": true, "yields": [
		{"id": "log", "qty": [1, 2]},
		{"id": "palm_leaf", "qty": [2, 4]},
		{"id": "coconut", "qty": [1, 3]},
	]},
	"young_palm": {"hp": 30, "blocks": true, "yields": [
		{"id": "stick", "qty": [1, 2]},
		{"id": "palm_leaf", "qty": [1, 2]},
	]},
	"fiber_plant": {"hp": 15, "blocks": false, "yields": [
		{"id": "plant_fiber", "qty": [1, 3]},
	]},
	"rock_outcrop": {"hp": 100, "blocks": true, "yields": [
		{"id": "stone", "qty": [2, 4]},
		{"id": "flint", "qty": [0, 1]},
	]},
	"driftwood": {"hp": 20, "blocks": false, "yields": [
		{"id": "driftwood", "qty": [1, 2]},
	]},
	"beach_debris": {"hp": 10, "blocks": false, "yields": [
		{"id": "plastic", "qty": [1, 2]},
		{"id": "cloth_scrap", "qty": [0, 1]},
		{"id": "rope", "qty": [0, 1]},
	]},
}


static func generate_island(island_id: int, seed_value: int, w: int = MAP_W, h: int = MAP_H, quality: String = "starter") -> WorldMap:
	var rng := SimRng.new(seed_value)
	var map := WorldMap.new()
	map.setup(w, h, island_id, seed_value)

	var elev := FastNoiseLite.new()
	elev.seed = seed_value
	elev.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev.frequency = 0.028
	elev.fractal_octaves = 4

	var moist := FastNoiseLite.new()
	moist.seed = seed_value + 1013
	moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moist.frequency = 0.045
	moist.fractal_octaves = 3

	var cx := w / 2.0
	var cy := h / 2.0
	var max_radius: float = min(w, h) * 0.42
	# Noisy island edge keeps coastlines organic.
	var edge := FastNoiseLite.new()
	edge.seed = seed_value + 77
	edge.frequency = 0.05
	edge.fractal_octaves = 2

	for y: int in h:
		for x: int in w:
			var p := Vector2i(x, y)
			var nx := (x - cx) / max_radius
			var ny := (y - cy) / max_radius
			var dist := sqrt(nx * nx + ny * ny)
			var falloff := clampf(1.0 - dist, -0.35, 1.0)
			var e := elev.get_noise_2d(x, y) * 0.5 + 0.5
			var land_value := falloff * 1.15 + e * 0.55 - 0.42
			var t: int
			if land_value < -0.06:
				t = Terrain.T.DEEP_OCEAN
			elif land_value < 0.03:
				t = Terrain.T.OCEAN
			elif land_value < 0.10:
				t = Terrain.T.SHALLOW
			elif land_value < 0.17:
				t = Terrain.T.SAND
			elif land_value > 0.62:
				t = Terrain.T.ROCK
			elif land_value < 0.24 and moist.get_noise_2d(x, y) > 0.25:
				t = Terrain.T.MUD
			else:
				t = Terrain.T.GRASS
			map.set_tile(p, t)

	# Jungle where moisture is high.
	for y: int in h:
		for x: int in w:
			var p := Vector2i(x, y)
			if map.tile(p) == Terrain.T.GRASS and moist.get_noise_2d(x, y) > 0.18:
				map.set_tile(p, Terrain.T.JUNGLE)

	# Shoreline smoothing: sand between land and water where missing.
	for y: int in h:
		for x: int in w:
			var p := Vector2i(x, y)
			if Terrain.is_water(map.tile(p)):
				continue
			var near_water := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if Terrain.is_water(map.tile(p + d)):
					near_water = true
					break
			if near_water and map.tile(p) != Terrain.T.MUD and map.tile(p) != Terrain.T.ROCK:
				map.set_tile(p, Terrain.T.SAND)

	_vegetation(map, rng)
	_beach_debris(map, rng)
	var spawn := _pick_spawn(map, rng)
	map.set_meta("spawn", spawn)
	_ensure_guarantees(map, rng, quality)
	return map


static func _vegetation(map: WorldMap, rng: SimRng) -> void:
	for y: int in map.height:
		for x: int in map.width:
			var p := Vector2i(x, y)
			var t := map.tile(p)
			match t:
				Terrain.T.JUNGLE:
					if rng.chance(0.10):
						map.add_feature(p, "palm", FEATURES["palm"])
					elif rng.chance(0.06):
						map.add_feature(p, "young_palm", FEATURES["young_palm"])
					elif rng.chance(0.10):
						map.add_feature(p, "fiber_plant", FEATURES["fiber_plant"])
				Terrain.T.GRASS:
					if rng.chance(0.02):
						map.add_feature(p, "palm", FEATURES["palm"])
					elif rng.chance(0.08):
						map.add_feature(p, "fiber_plant", FEATURES["fiber_plant"])
				Terrain.T.ROCK:
					if rng.chance(0.07):
						map.add_feature(p, "rock_outcrop", FEATURES["rock_outcrop"])
				Terrain.T.SAND:
					if rng.chance(0.012):
						map.add_feature(p, "driftwood", FEATURES["driftwood"])


static func _beach_debris(map: WorldMap, rng: SimRng) -> void:
	for y: int in map.height:
		for x: int in map.width:
			var p := Vector2i(x, y)
			if map.tile(p) == Terrain.T.SAND and not map.features.has(p) and rng.chance(0.02):
				map.add_feature(p, "beach_debris", FEATURES["beach_debris"])


static func _pick_spawn(map: WorldMap, rng: SimRng) -> Vector2i:
	# Spawn on a clear sand/grass tile adjacent to shallow water or clear grass,
	# not blocked by a feature.
	var candidates: Array[Vector2i] = []
	for y: int in map.height:
		for x: int in map.width:
			var p := Vector2i(x, y)
			var t := map.tile(p)
			if t != Terrain.T.SAND and t != Terrain.T.GRASS:
				continue
			if map.blocks_move(p):
				continue
			var near_shallow := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if map.tile(p + d) == Terrain.T.SHALLOW:
					near_shallow = true
					break
			if near_shallow:
				candidates.append(p)
	if candidates.is_empty():
		# Fallback: any clear land tile.
		return map.find_tile(rng, func(p: Vector2i) -> bool:
			return map.is_clear_for_walk(p))
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _ensure_guarantees(map: WorldMap, rng: SimRng, quality: String) -> void:
	# Guarantee starter resources: palms (wood/coconuts), fiber, stone.
	var spawn: Vector2i = map.get_meta("spawn")
	var min_r := 40 if quality == "starter" else 20

	_guarantee_feature_near(map, rng, "palm", spawn, min_r, 12)
	_guarantee_feature_near(map, rng, "fiber_plant", spawn, min_r, 10)
	_guarantee_feature_near(map, rng, "rock_outcrop", spawn, min_r + 10, 4)
	_guarantee_feature_near(map, rng, "driftwood", spawn, min_r, 6)
	# Deterministic starter supplies near spawn so the player can craft day one.
	_drop_near(map, rng, spawn, [
		{"id": "coconut", "qty": 2},
		{"id": "cloth_scrap", "qty": 1},
		{"id": "glass_bottle", "qty": 1},
	], 6)


static func _guarantee_feature_near(map: WorldMap, rng: SimRng, kind: String, around: Vector2i, radius: int, min_count: int) -> void:
	var count := 0
	for p: Vector2i in map.features.keys():
		if str(map.features[p].get("kind")) == kind and Vector2i(p).distance_to(around) <= float(radius):
			count += 1
	if count >= min_count:
		return
	var need := min_count - count
	var kind_def: Dictionary = FEATURES[kind]
	for _i: int in need * 6:
		if need <= 0:
			break
		var x := around.x + rng.randi_range(-radius, radius)
		var y := around.y + rng.randi_range(-radius, radius)
		var p := Vector2i(x, y)
		if not map.is_clear_for_walk(p):
			continue
		if not map.features.has(p):
			map.add_feature(p, kind, kind_def)
			need -= 1


static func _drop_near(map: WorldMap, rng: SimRng, around: Vector2i, items: Array, radius: int) -> void:
	for it: Dictionary in items:
		for _i: int in 20:
			var p := around + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
			if map.is_clear_for_walk(p):
				map.add_ground_item(p, str(it["id"]), int(it["qty"]))
				break