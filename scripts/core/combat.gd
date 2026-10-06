class_name Combat
extends RefCounted
## Turn-based combat resolution. Deterministic given sim RNG state.

static func resolve_attack(attacker: Actor, defender: Actor, game: GameSim) -> void:
	if attacker == null or defender == null or not defender.alive:
		return
	var weapon_id := str(attacker.equipped_item().get("id"))
	var weapon := Data.item(weapon_id)
	var is_player := attacker == game.player
	var dmg_base := 3.0  # bare hands
	if not weapon.is_empty():
		dmg_base = float(weapon.get("damage", 3.0))

	# Arm injuries reduce damage; melee skill adds.
	var dmg := dmg_base * attacker.arm_penalty()
	dmg *= 1.0 + 0.12 * attacker.skill_level("melee")
	# Stamina: low stamina weakens blows.
	dmg *= 0.6 + 0.4 * clampf(attacker.stamina / 100.0, 0.0, 1.0)

	# Accuracy: base 78%, weapon accuracy modifier, defender dodge.
	var accuracy := float(weapon.get("accuracy", 78)) if not weapon.is_empty() else 78.0
	var dodge := 8.0
	if defender.kind == "creature":
		dodge = float(Data.creature(defender.species).get("dodge", 8.0))
	if attacker.stamina < 30.0:
		accuracy -= 12.0
	var roll := game.rng.randf_range(0.0, 100.0)
	if roll > accuracy + dodge:
		_notify_miss(attacker, defender, is_player)
		attacker.stamina = maxf(attacker.stamina - 5.0, 0.0)
		if is_player:
			attacker.add_skill_xp("melee", 1.0)
		return

	# Body part hit: torso most likely, head rare but lethal.
	var part := _pick_body_part(game)
	var part_def: Dictionary = defender.body.get(part, {})
	var armor := float(weapon.get("armor_pen", 0.0))
	var dmg_final := int(round(dmg * game.rng.randf_range(0.85, 1.15) * (1.0 - armor)))
	dmg_final = maxi(dmg_final, 1)
	var max_hp := int(part_def.get("max", 1))

	Events.log_msg.emit("%s hits %s %s for %d" % [_name(attacker), _name(defender), part, dmg_final], "info")
	game._damage_part(defender, part, dmg_final)

	# Pain spike on hit.
	defender.pain = clampf(defender.pain + dmg_final * 0.4, 0.0, 100.0)
	attacker.stamina = maxf(attacker.stamina - 8.0, 0.0)

	# Weapon durability loss.
	if is_player and not weapon.is_empty() and weapon.has("durability"):
		var hand: Dictionary = attacker.equipment["hand"]
		var dur := float(hand.get("durability", 100.0)) - float(weapon.get("durability_loss", 1.5))
		if dur <= 0.0:
			attacker.equipment["hand"] = {}
			Events.toast.emit("Your %s breaks!" % str(weapon.get("name", "weapon")))
		else:
			hand["durability"] = dur
			attacker.equipment["hand"] = hand

	if is_player:
		attacker.add_skill_xp("melee", 3.0)
	if defender.is_dead():
		defender.alive = false
		Events.entity_died.emit(defender.id, defender.kind)
		if defender == game.player:
			game._kill_player("killed by " + _name(attacker))
		else:
			game.on_creature_died(defender)


static func _pick_body_part(game: GameSim) -> String:
	var roll := game.rng.randf()
	if roll < 0.40:
		return "torso"
	elif roll < 0.62:
		return "l_leg" if roll < 0.51 else "r_leg"
	elif roll < 0.85:
		return "l_arm" if roll < 0.735 else "r_arm"
	return "head"


static func _name(a: Actor) -> String:
	if a.kind == "player":
		return "You"
	var def := Data.creature(a.species)
	return str(def.get("name", a.species))


static func _notify_miss(attacker: Actor, defender: Actor, is_player: bool) -> void:
	var verb := "miss" if is_player else "swings at you and misses"
	Events.toast.emit("%s %s." % [_name(attacker).capitalize() if not is_player else "You", verb])