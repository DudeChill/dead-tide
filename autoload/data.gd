extends Node
## Loads and validates all data-driven content from res://data/.
## Exposes lookup helpers. Content lives in JSON so adding an item or recipe
## never requires touching engine code.

const DATA_FILES := {
	"items": "res://data/items.json",
	"recipes": "res://data/recipes.json",
	"creatures": "res://data/creatures.json",
	"structures": "res://data/structures.json",
	"balance": "res://data/balance.json",
}

var db: Dictionary = {}
var validation_errors: Array[String] = []


func _ready() -> void:
	_load_all()
	_validate()


func _load_all() -> void:
	for key: String in DATA_FILES:
		var path: String = DATA_FILES[key]
		var parsed: Variant = _read_json(path)
		if parsed == null:
			validation_errors.append("missing or invalid data file: %s" % path)
			db[key] = {}
		else:
			db[key] = parsed
	Events.log_msg.emit("data loaded: %s" % ", ".join(db.keys()), "info")


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed


func balance(key: String, fallback: Variant = null) -> Variant:
	var bal: Dictionary = db.get("balance", {})
	return bal.get(key, fallback)


func item(id: String) -> Dictionary:
	var items: Dictionary = db.get("items", {})
	return items.get(id, {})


func item_or_null(id: String) -> Variant:
	var items: Dictionary = db.get("items", {})
	return items.get(id)


func recipe(id: String) -> Dictionary:
	var recipes: Dictionary = db.get("recipes", {})
	return recipes.get(id, {})


func creature(id: String) -> Dictionary:
	var creatures: Dictionary = db.get("creatures", {})
	return creatures.get(id, {})


func structure(id: String) -> Dictionary:
	var structures: Dictionary = db.get("structures", {})
	return structures.get(id, {})


func _validate() -> void:
	var items: Dictionary = db.get("items", {})
	var recipes: Dictionary = db.get("recipes", {})
	for rid: String in recipes:
		var r: Dictionary = recipes[rid]
		var result: String = str(r.get("result", ""))
		if not items.has(result):
			validation_errors.append("recipe %s produces unknown item %s" % [rid, result])
		for ing: Variant in r.get("ingredients", []):
			var iid: String = str(ing.get("id", ""))
			if not items.has(iid):
				validation_errors.append("recipe %s needs unknown item %s" % [rid, iid])
	if validation_errors.is_empty():
		Events.log_msg.emit("data validation OK", "info")
	else:
		for e: String in validation_errors:
			Events.log_msg.emit("data validation: " + e, "error")