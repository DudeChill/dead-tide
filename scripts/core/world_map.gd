class_name WorldMap
extends RefCounted
## Grid-based island map. Pure simulation data: terrain ids, map features,
## ground items, and built structures. Coordinates are grid cells (Vector2i).

var width: int = 128
var height: int = 128
var island_id: int = 0
var island_name: String = ""
var seed_value: int = 0
## PackedInt32Array of Terrain.T values, row-major.
var tiles: PackedInt32Array = PackedInt32Array()
## Map features, e.g. palm trees, rock outcrops, driftwood.
## pos -> {"kind": String, "hp": int, "max_hp": int, "yields": Array}
var features: Dictionary = {}
## Ground items. pos -> Array of {"id": String, "qty": int}
var ground_items: Dictionary = {}
## Built structures. pos -> {"kind": String, "fuel": float, ...}
var structures: Dictionary = {}
## Explored fog bits, one per tile (true = seen).
var explored: PackedByteArray = PackedByteArray()


func setup(w: int, h: int, p_island_id: int, p_seed: int) -> void:
	width = w
	height = h
	island_id = p_island_id
	seed_value = p_seed
	tiles.resize(w * h)
	tiles.fill(Terrain.T.DEEP_OCEAN)
	explored.resize(w * h)
	explored.fill(0)


func idx(p: Vector2i) -> int:
	return p.y * width + p.x


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func tile(p: Vector2i) -> int:
	if not in_bounds(p):
		return Terrain.T.DEEP_OCEAN
	return tiles[idx(p)]


func set_tile(p: Vector2i, t: int) -> void:
	if in_bounds(p):
		tiles[idx(p)] = t


func passable(p: Vector2i) -> bool:
	return in_bounds(p) and Terrain.is_passable(tile(p))


func explored_bit(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	return explored[idx(p)] == 1


func set_explored(p: Vector2i, v: bool) -> void:
	if in_bounds(p):
		explored[idx(p)] = 1 if v else 0


func feature(p: Vector2i) -> Dictionary:
	return features.get(p, {})


func add_feature(p: Vector2i, kind: String, def: Dictionary) -> void:
	features[p] = {
		"kind": kind,
		"hp": int(def.get("hp", 100)),
		"max_hp": int(def.get("hp", 100)),
		"yields": def.get("yields", []),
		"blocks": bool(def.get("blocks", false)),
	}


func remove_feature(p: Vector2i) -> void:
	features.erase(p)


func blocks_move(p: Vector2i) -> bool:
	## Features can block movement (trees, boulders).
	var f := feature(p)
	return bool(f.get("blocks", false))


func is_clear_for_walk(p: Vector2i) -> bool:
	return passable(p) and not blocks_move(p)


func add_ground_item(p: Vector2i, item_id: String, qty: int) -> void:
	var arr: Array = ground_items.get(p, [])
	arr.append({"id": item_id, "qty": qty})
	ground_items[p] = arr


func ground_items_at(p: Vector2i) -> Array:
	return ground_items.get(p, [])


func take_ground_items(p: Vector2i) -> Array:
	var arr: Array = ground_items.get(p, [])
	ground_items.erase(p)
	return arr


func remove_ground_item(p: Vector2i, item_id: String, qty: int) -> void:
	var arr: Array = ground_items.get(p, [])
	for i: int in arr.size():
		var it: Dictionary = arr[i]
		if str(it.get("id")) == item_id and int(it.get("qty")) >= qty:
			arr.remove_at(i)
			if arr.is_empty():
				ground_items.erase(p)
			return
	# Fallback: remove first matching stack partially.
	for i: int in arr.size():
		if str(arr[i].get("id")) == item_id:
			arr.remove_at(i)
			if arr.is_empty():
				ground_items.erase(p)
			return


func structure(p: Vector2i) -> Dictionary:
	return structures.get(p, {})


func set_structure(p: Vector2i, kind: String, extra: Dictionary = {}) -> void:
	var d := {"kind": kind}
	d.merge(extra, true)
	structures[p] = d


func remove_structure(p: Vector2i) -> void:
	structures.erase(p)


## Finds a random land tile passing `filter`, or Vector2i(-1,-1).
func find_tile(rng: SimRng, filter: Callable, tries: int = 4000) -> Vector2i:
	for _i: int in tries:
		var x := rng.randi_range(2, width - 3)
		var y := rng.randi_range(2, height - 3)
		var p := Vector2i(x, y)
		if filter.call(p):
			return p
	return Vector2i(-1, -1)


func all_positions_with_feature_kind(kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in features.keys():
		if str(features[p].get("kind")) == kind:
			out.append(p)
	return out


# ---------------------------------------------------------------- serialization

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


static func _pos(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func serialize() -> Dictionary:
	var features_data: Dictionary = {}
	for p: Vector2i in features:
		features_data[_key(p)] = features[p]
	var items_data: Dictionary = {}
	for p: Vector2i in ground_items:
		items_data[_key(p)] = ground_items[p]
	var structures_data: Dictionary = {}
	for p: Vector2i in structures:
		structures_data[_key(p)] = structures[p]
	return {
		"width": width, "height": height, "island_id": island_id,
		"island_name": island_name, "seed": seed_value,
		"tiles_b64": Marshalls.raw_to_base64(tiles.to_byte_array()),
		"explored_b64": Marshalls.raw_to_base64(explored),
		"features": features_data,
		"ground_items": items_data,
		"structures": structures_data,
		"spawn": [get_meta("spawn", Vector2i(width / 2, height / 2)).x, get_meta("spawn", Vector2i(width / 2, height / 2)).y],
	}


static func deserialize(d: Dictionary) -> WorldMap:
	var map := WorldMap.new()
	map.width = int(d.get("width", 128))
	map.height = int(d.get("height", 128))
	map.island_id = int(d.get("island_id", 0))
	map.island_name = str(d.get("island_name", ""))
	map.seed_value = int(d.get("seed", 0))
	map.tiles = PackedInt32Array(Marshalls.base64_to_raw(str(d.get("tiles_b64", ""))).to_int32_array())
	map.explored = PackedByteArray(Marshalls.base64_to_raw(str(d.get("explored_b64", ""))))
	var features_data: Dictionary = d.get("features", {})
	for key: String in features_data:
		map.features[_pos(key)] = features_data[key]
	var items_data: Dictionary = d.get("ground_items", {})
	for key: String in items_data:
		map.ground_items[_pos(key)] = items_data[key]
	var structures_data: Dictionary = d.get("structures", {})
	for key: String in structures_data:
		map.structures[_pos(key)] = structures_data[key]
	var spawn_arr: Array = d.get("spawn", [map.width / 2, map.height / 2])
	map.set_meta("spawn", Vector2i(int(spawn_arr[0]), int(spawn_arr[1])))
	return map