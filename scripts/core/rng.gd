class_name SimRng
extends RefCounted
## Deterministic RNG wrapper. State can be captured/restored for save games
## so a loaded world reproduces the exact same future random sequence.

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	# Godot's RandomNumberGenerator default seed is randomized; a zero seed
	# would leave it random, so map 0 to a fixed constant.
	rng.seed = seed_value if seed_value != 0 else 88675123


func seed_value() -> int:
	return int(rng.seed)


func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)


func randf() -> float:
	return rng.randf()


func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)


func chance(p: float) -> bool:
	return rng.randf() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


func state() -> int:
	return rng.get_state()


func set_state(s: int) -> void:
	rng.set_state(s)