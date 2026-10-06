class_name TurnManager
extends RefCounted
## Energy-based turn scheduling. The world only advances when the player
## spends action points: after every player action, creatures act until the
## player regains enough energy to act again.

## Game-time model: 100 AP == 1 in-game minute.
const AP_PER_MINUTE := 100

var game: GameSim


func _init(p_game: GameSim) -> void:
	game = p_game


func player_action_cost(base_cost: int) -> int:
	## Applies leg injury penalty to movement-type costs.
	var player := game.player
	if player == null:
		return base_cost
	return int(round(base_cost / player.leg_penalty()))


func spend(cost: int) -> void:
	var player := game.player
	if player == null:
		return
	player.energy -= cost
	game.advance_clock(cost)
	_run_world()
	Events.turn_advanced.emit(game.turn_count)


func _run_world() -> void:
	var player := game.player
	if player == null:
		return
	var guard := 0
	while player.energy < 0 and guard < 5000:
		guard += 1
		var acted := false
		for a: Actor in game.actors:
			if not a.alive or a == player:
				continue
			while a.energy < 0 and player.energy < 0:
				# Creatures regenerate energy at their speed until they can act.
				a.energy += _creature_speed(a)
				if a.energy >= 0:
					acted = true
					game.run_creature_turn(a)
					break
			if player.energy >= 0:
				break
		if not acted and player.energy < 0:
			# Nothing else can act; grant the player passive regen.
			player.energy += _player_speed(player)
	# Survival meters tick with elapsed AP handled in advance_clock.


func _player_speed(player: Actor) -> int:
	## AP regenerated per world pulse. Base 100 AP/minute equivalent.
	var speed := 100
	if player.stamina < 20.0:
		speed = int(speed * 0.7)
	return speed


func _creature_speed(a: Actor) -> int:
	var def := Data.creature(a.species)
	return int(def.get("speed", 100))