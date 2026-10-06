class_name AIController
extends RefCounted
## Creature behavior. Clean finite-state machine:
## IDLE -> ROAM -> INVESTIGATE -> CHASE -> ATTACK -> FLEE.
## One decision per creature turn; cheap and deterministic.

static func act(a: Actor, game: GameSim, def: Dictionary) -> void:
	if not a.alive:
		return
	var profile := str(def.get("profile", "passive"))
	var map := game.current_map()
	var player := game.player
	if player == null or not player.alive or player.island_id != a.island_id:
		a.ai_state = "IDLE"
		_roam_step(a, game, map, def)
		return

	var dist := a.pos.distance_to(player.pos)
	var sight: float = def.get("sight", 6.0)
	var attack_range: float = def.get("attack_range", 1.0)
	var hp_ratio := float(a.body_hp()) / maxf(float(a.body_max()), 1.0)

	# Hurt creatures flee (except cornered hostile humanoids).
	if hp_ratio < 0.25 and profile != "hostile_humanoid":
		a.ai_state = "FLEE"
	elif profile == "hostile_humanoid" or profile == "predator":
		a.ai_state = "CHASE" if dist <= sight else "ROAM"
	elif profile == "territorial":
		var home_dist := a.pos.distance_to(a.wander_origin)
		a.ai_state = "CHASE" if (dist <= sight and home_dist <= float(def.get("territory", 8.0))) else "ROAM"
	else:
		# Passive: only flee if the player is adjacent.
		a.ai_state = "FLEE" if dist <= 2.0 else "ROAM"

	match a.ai_state:
		"FLEE":
			_step_away(a, game, map, player.pos, def)
		"CHASE":
			if dist <= attack_range:
				a.ai_state = "ATTACK"
				Combat.resolve_attack(a, player, game)
			else:
				_step_toward(a, game, map, player.pos, def)
		"ATTACK":
			Combat.resolve_attack(a, player, game)
		_:
			_roam_step(a, game, map, def)


static func _passable_for(a: Actor, map: WorldMap, p: Vector2i, def: Dictionary) -> bool:
	var swimmer := bool(def.get("swimmer", false))
	if Terrain.is_water(map.tile(p)):
		return swimmer
	if bool(def.get("water_only", false)):
		return false
	return map.is_clear_for_walk(p)


static func _step_toward(a: Actor, game: GameSim, map: WorldMap, target: Vector2i, def: Dictionary) -> void:
	var step := _greedy_step(a, map, target, def)
	if step != Vector2i(999, 999):
		var blocker := game.actor_at(step)
		if blocker == null or blocker == a:
			a.pos = step


static func _step_away(a: Actor, game: GameSim, map: WorldMap, threat: Vector2i, def: Dictionary) -> void:
	var away := a.pos + (a.pos - threat).sign()
	if away == a.pos:
		away = a.pos + Vector2i(1, 0)
	var step := _greedy_step(a, map, away, def)
	if step != Vector2i(999, 999):
		var blocker := game.actor_at(step)
		if blocker == null:
			a.pos = step


static func _roam_step(a: Actor, game: GameSim, map: WorldMap, def: Dictionary) -> void:
	# Pick a wander target near origin occasionally; step randomly otherwise.
	if a.ai_target == Vector2i(-1, -1) or a.pos.distance_to(a.ai_target) < 2.0:
		var radius := float(def.get("wander_radius", 6.0))
		var c := a.wander_origin if a.wander_origin != Vector2i(-1, -1) else a.pos
		var t := c + Vector2i(game.rng.randi_range(-int(radius), int(radius)), game.rng.randi_range(-int(radius), int(radius)))
		if map.is_clear_for_walk(t):
			a.ai_target = t
	var step := _greedy_step(a, map, a.ai_target, def)
	if step != Vector2i(999, 999):
		var blocker := game.actor_at(step)
		if blocker == null:
			a.pos = step


static func _greedy_step(a: Actor, map: WorldMap, target: Vector2i, def: Dictionary) -> Vector2i:
	## Greedy step toward target; try diagonals. Returns sentinel if stuck.
	var dirs: Array[Vector2i] = [
		Vector2i(signi(target.x - a.pos.x), 0), Vector2i(0, signi(target.y - a.pos.y)),
		Vector2i(signi(target.x - a.pos.x), signi(target.y - a.pos.y)),
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
	]
	for d: Vector2i in dirs:
		if d == Vector2i.ZERO:
			continue
		var p := a.pos + d
		if _passable_for(a, map, p, def):
			return p
	return Vector2i(999, 999)