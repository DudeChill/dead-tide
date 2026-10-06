extends Node
## Save/load: JSON files under user://saves/, versioned format.

const SAVE_DIR := "user://saves"


func save_game(game: GameSim, slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
	var data := game.to_dict()
	data["saved_at"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Events.log_msg.emit("save failed: %s" % path, "error")
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	Events.log_msg.emit("game saved to %s" % path, "info")
	return true


func load_game(slot: int) -> GameSim:
	var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(path):
		Events.toast.emit("No save in slot %d." % slot)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		Events.log_msg.emit("corrupt save: %s" % path, "error")
		return null
	var d: Dictionary = parsed
	var version := int(d.get("save_version", 0))
	if version > GameSim.SAVE_VERSION:
		Events.log_msg.emit("save from newer version (%d)" % version, "error")
		return null
	var sim := GameSim.from_dict(d)
	Events.log_msg.emit("game loaded from %s" % path, "info")
	return sim


func has_save(slot: int) -> bool:
	return FileAccess.file_exists("%s/slot_%d.json" % [SAVE_DIR, slot])