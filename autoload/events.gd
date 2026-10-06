extends Node
## Global signal bus. Systems communicate through these signals instead of
## referencing each other directly.

signal log_msg(text: String, level: String)
signal world_regenerated
signal turn_advanced(turn: int)
signal player_moved(pos: Vector2i)
signal meters_changed
signal inventory_changed
signal item_picked_up(item_id: String)
signal item_crafted(item_id: String)
signal structure_built(kind: String, pos: Vector2i)
signal entity_damaged(entity_id: int, amount: int)
signal entity_died(entity_id: int, kind: String)
signal weather_changed(weather: String)
signal day_changed(day: int)
signal player_died(stats: Dictionary)
signal toast(text: String)
signal map_changed