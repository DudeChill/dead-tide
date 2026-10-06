class_name Actor
extends RefCounted
## Any moving entity: player or creature. Pure simulation data.

const BODY_PARTS: Array[String] = ["head", "torso", "l_arm", "r_arm", "l_leg", "r_leg"]

static var _next_id: int = 1

var id: int = 0
var kind: String = "creature"   # "player" | "creature"
var species: String = ""        # creature id from data/creatures.json
var pos: Vector2i = Vector2i.ZERO
var island_id: int = 0
var energy: int = 0             # accumulated action points; act when >= 0
var alive: bool = true
var on_raft_id: int = 0         # 0 = not aboard

# Body model: part -> {"hp": int, "max": int, "bleeding": bool, "injury": int}
var body: Dictionary = {}
# Survival meters (0..100).
var hunger: float = 100.0
var thirst: float = 100.0
var fatigue: float = 100.0
var stamina: float = 100.0
var temperature: float = 37.0   # body temperature, deg C
var pain: float = 0.0

# Inventory: Array of {"id": String, "qty": int, "durability": float}
var inventory: Array = []
var capacity_weight: float = 25.0
var capacity_volume: float = 30.0

# Equipment slots: {"hand": item_dict_or_empty, "body": ...}
var equipment: Dictionary = {"hand": {}, "body": {}}

# Skills: name -> xp (float). Levels derived.
var skills: Dictionary = {"survival": 0.0, "fabrication": 0.0, "cooking": 0.0,
	"fishing": 0.0, "melee": 0.0, "swimming": 0.0, "mechanics": 0.0}

# AI state for creatures.
var ai_state: String = "IDLE"
var ai_target: Vector2i = Vector2i(-1, -1)
var wander_origin: Vector2i = Vector2i(-1, -1)


static func next_id() -> int:
	_next_id += 1
	return _next_id


static func make_player(pos: Vector2i, island_id: int) -> Actor:
	var a := Actor.new()
	a.id = next_id()
	a.kind = "player"
	a.pos = pos
	a.island_id = island_id
	a.energy = 0
	a.capacity_weight = 30.0
	a.capacity_volume = 35.0
	_init_body(a, 100.0)
	return a


static func make_creature(species: String, def: Dictionary, pos: Vector2i, island_id: int) -> Actor:
	var a := Actor.new()
	a.id = next_id()
	a.kind = "creature"
	a.species = species
	a.pos = pos
	a.island_id = island_id
	a.energy = 0
	a.capacity_weight = 10.0
	a.capacity_volume = 10.0
	_init_body(a, float(def.get("hp", 20)))
	a.wander_origin = pos
	return a


static func _init_body(a: Actor, total_hp: float) -> void:
	# Torso takes the largest share; head is lethal-fast.
	var shares := {"head": 0.25, "torso": 0.45, "l_arm": 0.16, "r_arm": 0.16,
		"l_leg": 0.18, "r_leg": 0.18}
	a.body = {}
	for part: String in BODY_PARTS:
		var hp := int(round(total_hp * shares[part]))
		a.body[part] = {"hp": hp, "max": hp, "bleeding": false, "injury": 0}


func body_hp() -> int:
	var total := 0
	for part: String in body:
		total += int(body[part].get("hp", 0))
	return total


func body_max() -> int:
	var total := 0
	for part: String in body:
		total += int(body[part].get("max", 0))
	return total


func is_dead() -> bool:
	# Death when torso or head destroyed, or total hp <= 0.
	if not alive:
		return true
	if body_hp() <= 0:
		return true
	if int(body.get("torso", {}).get("hp", 1)) <= 0:
		return true
	if int(body.get("head", {}).get("hp", 1)) <= 0:
		return true
	return false


func leg_penalty() -> float:
	## Returns movement multiplier 0.5..1.0 based on leg injuries.
	var mult := 1.0
	for part: String in ["l_leg", "r_leg"]:
		var part_data: Dictionary = body.get(part, {})
		var max_hp := float(part_data.get("max", 1))
		var hp := float(part_data.get("hp", max_hp))
		if max_hp > 0 and hp < max_hp:
			mult *= 0.5 + 0.5 * (hp / max_hp)
	return clampf(mult, 0.35, 1.0)


func arm_penalty() -> float:
	var mult := 1.0
	for part: String in ["l_arm", "r_arm"]:
		var part_data: Dictionary = body.get(part, {})
		var max_hp := float(part_data.get("max", 1))
		var hp := float(part_data.get("hp", max_hp))
		if max_hp > 0 and hp < max_hp:
			mult *= 0.5 + 0.5 * (hp / max_hp)
	return clampf(mult, 0.4, 1.0)


func any_bleeding() -> bool:
	for part: String in body:
		if bool(body[part].get("bleeding", false)):
			return true
	return false


func skill_level(skill: String) -> int:
	var xp := float(skills.get(skill, 0.0))
	return int(sqrt(xp) / 5.0)


func add_skill_xp(skill: String, xp: float) -> void:
	skills[skill] = float(skills.get(skill, 0.0)) + xp


func total_weight() -> float:
	var w := 0.0
	for it: Dictionary in inventory:
		var def := Data.item(str(it.get("id")))
		w += float(def.get("weight", 0)) * float(it.get("qty", 1))
	return w


func total_volume() -> float:
	var v := 0.0
	for it: Dictionary in inventory:
		var def := Data.item(str(it.get("id")))
		v += float(def.get("volume", 0)) * float(it.get("qty", 1))
	return v


func count_item(item_id: String) -> int:
	var n := 0
	for it: Dictionary in inventory:
		if str(it.get("id")) == item_id:
			n += int(it.get("qty", 0))
	return n


func add_item(item_id: String, qty: int) -> bool:
	## Weight/volume constrained add. Returns false if it does not fit.
	var def := Data.item(item_id)
	if def.is_empty():
		return false
	var w := float(def.get("weight", 0)) * qty
	var v := float(def.get("volume", 0)) * qty
	if total_weight() + w > capacity_weight or total_volume() + v > capacity_volume:
		return false
	for it: Dictionary in inventory:
		if str(it.get("id")) == item_id and not bool(def.get("stack_unique", false)):
			it["qty"] = int(it.get("qty", 0)) + qty
			Events.inventory_changed.emit()
			return true
	inventory.append({"id": item_id, "qty": qty, "durability": float(def.get("durability", 100.0))})
	Events.inventory_changed.emit()
	return true


func remove_item(item_id: String, qty: int) -> bool:
	var remaining := qty
	for i: int in range(inventory.size() - 1, -1, -1):
		var it: Dictionary = inventory[i]
		if str(it.get("id")) != item_id:
			continue
		var have := int(it.get("qty", 0))
		var take := mini(have, remaining)
		it["qty"] = have - take
		remaining -= take
		if int(it["qty"]) <= 0:
			inventory.remove_at(i)
		if remaining <= 0:
			Events.inventory_changed.emit()
			return true
	return remaining <= 0


func equipped_item() -> Dictionary:
	return equipment.get("hand", {})


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "species": species, "pos": [pos.x, pos.y],
		"island_id": island_id, "energy": energy, "alive": alive,
		"on_raft_id": on_raft_id,
		"body": body, "hunger": hunger, "thirst": thirst, "fatigue": fatigue,
		"stamina": stamina, "temperature": temperature, "pain": pain,
		"inventory": inventory, "capacity_weight": capacity_weight,
		"capacity_volume": capacity_volume, "equipment": equipment,
		"skills": skills, "ai_state": ai_state, "ai_target": [ai_target.x, ai_target.y],
		"wander_origin": [wander_origin.x, wander_origin.y],
	}


static func from_dict(d: Dictionary) -> Actor:
	var a := Actor.new()
	a.id = int(d.get("id", 0))
	a.kind = str(d.get("kind", "creature"))
	a.species = str(d.get("species", ""))
	a.pos = Vector2i(int(d["pos"][0]), int(d["pos"][1]))
	a.island_id = int(d.get("island_id", 0))
	a.energy = int(d.get("energy", 0))
	a.alive = bool(d.get("alive", true))
	a.on_raft_id = int(d.get("on_raft_id", 0))
	a.body = d.get("body", {})
	a.hunger = float(d.get("hunger", 100.0))
	a.thirst = float(d.get("thirst", 100.0))
	a.fatigue = float(d.get("fatigue", 100.0))
	a.stamina = float(d.get("stamina", 100.0))
	a.temperature = float(d.get("temperature", 37.0))
	a.pain = float(d.get("pain", 0.0))
	a.inventory = d.get("inventory", [])
	a.capacity_weight = float(d.get("capacity_weight", 25.0))
	a.capacity_volume = float(d.get("capacity_volume", 30.0))
	a.equipment = d.get("equipment", {"hand": {}, "body": {}})
	a.skills = d.get("skills", {})
	a.ai_state = str(d.get("ai_state", "IDLE"))
	var tgt: Array = d.get("ai_target", [-1, -1])
	a.ai_target = Vector2i(int(tgt[0]), int(tgt[1]))
	var wo: Array = d.get("wander_origin", [-1, -1])
	a.wander_origin = Vector2i(int(wo[0]), int(wo[1]))
	if a.id > _next_id:
		_next_id = a.id
	return a