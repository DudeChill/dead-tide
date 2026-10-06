extends CanvasLayer
## HUD: meters, clock, weather, toasts, hints, and overlay panels
## (inventory, crafting, building, world map, pause, death).

var meters: VBoxContainer
var clock_label: Label
var toast_label: Label
var hint_label: Label
var panel: PanelContainer
var panel_title: Label
var panel_body: RichTextLabel
var panel_mode: String = ""     # "", "inventory", "crafting", "building", "map", "pause", "dead"
var game: GameSim = null

var bars: Dictionary = {}


func _ready() -> void:
	layer = 10
	_build_hud()


func _build_hud() -> void:
	# Meters (top-left).
	meters = VBoxContainer.new()
	meters.position = Vector2(12, 10)
	add_child(meters)
	for cfg: Array in [
		["hp", "Health", Color(0.85, 0.25, 0.2)],
		["hunger", "Hunger", Color(0.85, 0.6, 0.2)],
		["thirst", "Thirst", Color(0.25, 0.55, 0.85)],
		["stamina", "Stamina", Color(0.35, 0.75, 0.35)],
		["fatigue", "Fatigue", Color(0.6, 0.5, 0.75)],
	]:
		var row := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(cfg[1])
		lbl.add_theme_font_size_override("font_size", 11)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 10)
		bar.min_value = 0
		bar.max_value = 100
		bar.show_percentage = false
		bar.modulate = cfg[2]
		row.add_child(lbl)
		row.add_child(bar)
		meters.add_child(row)
		bars[str(cfg[0])] = {"bar": bar, "label": lbl}

	# Clock + weather (top-right).
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 14)
	clock_label.anchor_left = 1.0
	clock_label.anchor_right = 1.0
	clock_label.offset_left = -260
	clock_label.offset_top = 10
	clock_label.offset_right = -12
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	# Toasts (bottom center).
	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 13)
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.anchor_left = 0.0
	toast_label.anchor_right = 1.0
	toast_label.offset_top = -64
	toast_label.offset_bottom = -44
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate = Color(1, 1, 1, 0.95)
	add_child(toast_label)

	# Hints (bottom-left).
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color(1, 1, 1, 0.65)
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_top = -26
	hint_label.offset_bottom = -6
	hint_label.offset_left = 12
	hint_label.text = "WASD move · E gather/interact · G pick up · F attack · C craft · B build · I inventory · M map · SPACE wait"
	add_child(hint_label)

	# Overlay panel.
	panel = PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -220
	panel.offset_bottom = 220
	var vb := VBoxContainer.new()
	panel_title = Label.new()
	panel_title.add_theme_font_size_override("font_size", 18)
	panel_body = RichTextLabel.new()
	panel_body.bbcode_enabled = true
	panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var close_hint := Label.new()
	close_hint.text = "ESC / same key closes"
	close_hint.add_theme_font_size_override("font_size", 10)
	close_hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(panel_title)
	vb.add_child(panel_body)
	vb.add_child(close_hint)
	panel.add_child(vb)
	add_child(panel)


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	var p := game.player
	var hp_pct := 100.0 * p.body_hp() / maxf(float(p.body_max()), 1.0)
	(bars["hp"]["bar"] as ProgressBar).value = hp_pct
	(bars["hunger"]["bar"] as ProgressBar).value = p.hunger
	(bars["thirst"]["bar"] as ProgressBar).value = p.thirst
	(bars["stamina"]["bar"] as ProgressBar).value = p.stamina
	(bars["fatigue"]["bar"] as ProgressBar).value = p.fatigue
	(bars["hp"]["label"] as Label).text = "Health %d%%" % int(hp_pct)
	(bars["hunger"]["label"] as Label).text = "Hunger %d%%" % int(p.hunger)
	(bars["thirst"]["label"] as Label).text = "Thirst %d%%" % int(p.thirst)
	(bars["stamina"]["label"] as Label).text = "Stamina %d%%" % int(p.stamina)
	(bars["fatigue"]["label"] as Label).text = "Fatigue %d%%" % int(p.fatigue)

	var wname: String = {"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm"}.get(game.weather, game.weather)
	clock_label.text = "Day %d · %02d:%02d · %s%s" % [game.day(), game.hour(), game.clock_minutes % 60, wname, " 🌙" if game.is_night() else ""]


func show_toast(text: String) -> void:
	toast_label.text = text


func open_panel(mode: String, title: String, body_bbcode: String) -> void:
	panel_mode = mode
	panel_title.text = title
	panel_body.text = body_bbcode
	panel.visible = true


func close_panel() -> void:
	panel.visible = false
	panel_mode = ""


func is_panel_open(mode: String) -> bool:
	return panel.visible and panel_mode == mode


func any_panel_open() -> bool:
	return panel.visible