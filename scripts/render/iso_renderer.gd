class_name IsoRenderer
extends Node2D
## Draws the current island as isometric diamonds plus features, structures,
## items, and entities. All visuals are procedural primitives; no art assets.

const TILE_W := 64
const TILE_H := 32

var game: GameSim = null


func tile_to_screen(p: Vector2i) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W / 2.0, (p.x + p.y) * TILE_H / 2.0)


func screen_to_tile(screen: Vector2) -> Vector2i:
	# Inverse of tile_to_screen (rounded).
	var fx := screen.x / (TILE_W / 2.0)
	var fy := screen.y / (TILE_H / 2.0)
	return Vector2i(int(round((fy + fx) / 2.0)), int(round((fy - fx) / 2.0)))


func _draw() -> void:
	if game == null or game.player == null:
		return
	var map := game.current_map()
	var center := game.player.pos
	var view := _view_radius_tiles()
	var origin := tile_to_screen(center)

	for y: int in range(maxi(center.y - view.y, 0), mini(center.y + view.y + 1, map.height)):
		for x: int in range(maxi(center.x - view.x, 0), mini(center.x + view.x + 1, map.width)):
			var p := Vector2i(x, y)
			if not map.explored_bit(p):
				continue
			var screen := tile_to_screen(p) - origin
			_draw_tile(p, map, screen)
	# Second pass for tall features so south tiles overlap correctly.
	for y: int in range(maxi(center.y - view.y, 0), mini(center.y + view.y + 1, map.height)):
		for x: int in range(maxi(center.x - view.x, 0), mini(center.x + view.x + 1, map.width)):
			var p := Vector2i(x, y)
			if not map.explored_bit(p):
				continue
			var screen := tile_to_screen(p) - origin
			_draw_feature(p, map, screen)
			_draw_structure(p, map, screen)
			_draw_ground_items(p, map, screen)
	# Entities on top.
	for a: Actor in game.actors_on_current_island():
		if a.pos.distance_to(center) > float(view.x + view.y):
			continue
		if not map.explored_bit(a.pos) and a != game.player:
			continue
		_draw_actor(a, tile_to_screen(a.pos) - origin)
	# Rafts (entities on water).
	for rid: int in game.rafts:
		var r: Dictionary = game.rafts[rid]
		if int(r.get("island_id")) != game.current_island_id:
			continue
		var rpos := Vector2i(int(r["pos"][0]), int(r["pos"][1]))
		var rs := tile_to_screen(rpos) - origin
		_diamond(rs, Color(0.72, 0.55, 0.30))
		draw_rect(Rect2(rs + Vector2(-14, -4), Vector2(28, 8)), Color(0.55, 0.40, 0.20), false, 2.0)
	_draw_night_overlay()


func _view_radius_tiles() -> Vector2i:
	var z := absf(get_viewport_transform().get_scale().x) if get_viewport() != null else 1.0
	var zoom := 1.0
	var cam := get_viewport().get_camera_2d() if get_viewport() != null else null
	if cam != null:
		zoom = cam.zoom.x
	# Number of tiles that fit half the viewport.
	var half_w := 1280.0 / (TILE_W * zoom)
	var half_h := 720.0 / (TILE_H * zoom)
	return Vector2i(int(half_w / 1.0) + 3, int(half_h / 1.0) + 3)


func _diamond(center: Vector2, color: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -TILE_H / 2.0),
		center + Vector2(TILE_W / 2.0, 0),
		center + Vector2(0, TILE_H / 2.0),
		center + Vector2(-TILE_W / 2.0, 0),
	])
	draw_colored_polygon(pts, color)


func _shade(c: Color, p: Vector2i) -> Color:
	var alt := ((p.x + p.y) % 2) == 0
	var v := 1.0 if alt else 0.94
	return Color(c.r * v, c.g * v, c.b * v)


func _draw_tile(p: Vector2i, map: WorldMap, screen: Vector2) -> void:
	var t := map.tile(p)
	var c := Terrain.color_of(t)
	_diamond(screen, _shade(c, p))
	if t == Terrain.T.SHALLOW or t == Terrain.T.OCEAN:
		draw_line(screen + Vector2(-10, 0), screen + Vector2(10, 0), Color(1, 1, 1, 0.10), 1.5)


func _draw_feature(p: Vector2i, map: WorldMap, screen: Vector2) -> void:
	var f := map.feature(p)
	if f.is_empty():
		return
	var kind := str(f.get("kind"))
	match kind:
		"palm", "young_palm":
			var h := 26.0 if kind == "palm" else 14.0
			draw_line(screen + Vector2(0, 2), screen + Vector2(0, -h), Color(0.45, 0.30, 0.15), 4.0)
			for i: int in 5:
				var ang := TAU * i / 5.0
				var dir := Vector2(cos(ang), sin(ang) * 0.5)
				draw_line(screen + Vector2(0, -h), screen + Vector2(0, -h) + dir * 11.0, Color(0.25, 0.60, 0.22), 3.0)
		"fiber_plant":
			for i: int in 3:
				var off := Vector2((i - 1) * 4.0, 0)
				draw_line(screen + off + Vector2(0, 4), screen + off + Vector2(0, -7), Color(0.35, 0.62, 0.28), 2.0)
		"rock_outcrop":
			var pts := PackedVector2Array([
				screen + Vector2(0, -14), screen + Vector2(11, 2), screen + Vector2(0, 8), screen + Vector2(-11, 2),
			])
			draw_colored_polygon(pts, Color(0.45, 0.45, 0.47))
		"driftwood":
			draw_line(screen + Vector2(-9, 5), screen + Vector2(10, -3), Color(0.55, 0.42, 0.28), 3.5)
		"beach_debris":
			draw_circle(screen + Vector2(2, -2), 3.0, Color(0.9, 0.9, 0.85, 0.8))


func _draw_structure(p: Vector2i, map: WorldMap, screen: Vector2) -> void:
	var s := map.structure(p)
	if s.is_empty():
		return
	var kind := str(s.get("kind"))
	match kind:
		"campfire":
			var lit := float(s.get("fuel", 0)) > 0
			draw_circle(screen + Vector2(0, 2), 8.0, Color(0.25, 0.2, 0.18))
			if lit:
				var flame := PackedVector2Array([
					screen + Vector2(0, -14), screen + Vector2(5, 0), screen + Vector2(-5, 0),
				])
				draw_colored_polygon(flame, Color(0.98, 0.55, 0.12))
		"shelter":
			var roof := PackedVector2Array([
				screen + Vector2(0, -20), screen + Vector2(16, 2), screen + Vector2(-16, 2),
			])
			draw_colored_polygon(roof, Color(0.52, 0.38, 0.20))
		"storage_crate":
			draw_rect(Rect2(screen + Vector2(-9, -12), Vector2(18, 14)), Color(0.55, 0.40, 0.22), true)
			draw_rect(Rect2(screen + Vector2(-9, -12), Vector2(18, 14)), Color(0.3, 0.2, 0.1), false, 1.5)
		"water_collector":
			draw_rect(Rect2(screen + Vector2(-8, -14), Vector2(16, 16)), Color(0.35, 0.55, 0.62), true)
			draw_rect(Rect2(screen + Vector2(-8, -14), Vector2(16, 16)), Color(0.15, 0.3, 0.35), false, 1.5)
		"workbench":
			draw_rect(Rect2(screen + Vector2(-11, -10), Vector2(22, 10)), Color(0.6, 0.55, 0.45), true)
		"wall":
			draw_rect(Rect2(screen + Vector2(-10, -16), Vector2(20, 18)), Color(0.4, 0.3, 0.2), true)
		"floor":
			_diamond(screen, Color(0.55, 0.45, 0.32, 0.6))
		"door":
			draw_rect(Rect2(screen + Vector2(-6, -14), Vector2(12, 16)), Color(0.5, 0.38, 0.22), true)
		"shipwreck":
			for i: int in 4:
				var xx := (i - 1.5) * 7.0
				draw_line(screen + Vector2(xx, -2), screen + Vector2(xx * 0.4, -18), Color(0.42, 0.30, 0.18), 3.0)
			draw_line(screen + Vector2(-12, -4), screen + Vector2(12, -4), Color(0.35, 0.25, 0.15), 2.5)
		"fishing_boat_wreck":
			var hull := PackedVector2Array([
				screen + Vector2(-16, 2), screen + Vector2(16, 2), screen + Vector2(10, -8), screen + Vector2(-10, -8),
			])
			draw_colored_polygon(hull, Color(0.48, 0.35, 0.20))
		"campsite_remains":
			draw_arc(screen + Vector2(0, 0), 7.0, 0, TAU, 12, Color(0.5, 0.45, 0.4), 2.0)
			draw_line(screen + Vector2(-6, 4), screen + Vector2(6, -2), Color(0.45, 0.32, 0.18), 2.5)
		"survivor_shack":
			draw_rect(Rect2(screen + Vector2(-12, -12), Vector2(24, 14)), Color(0.45, 0.34, 0.20), true)
			draw_line(screen + Vector2(-14, -12), screen + Vector2(0, -22), Color(0.35, 0.25, 0.15), 2.5)
			draw_line(screen + Vector2(14, -12), screen + Vector2(0, -22), Color(0.35, 0.25, 0.15), 2.5)


func _draw_ground_items(p: Vector2i, map: WorldMap, screen: Vector2) -> void:
	var items := map.ground_items_at(p)
	if items.is_empty():
		return
	var c := Color(0.95, 0.85, 0.3)
	var pts := PackedVector2Array([
		screen + Vector2(0, -4), screen + Vector2(4, 0), screen + Vector2(0, 4), screen + Vector2(-4, 0),
	])
	draw_colored_polygon(pts, c)


func _draw_actor(a: Actor, screen: Vector2) -> void:
	# Soft shadow ellipse.
	draw_arc(screen + Vector2(0, 4), 7.0, 0, TAU, 16, Color(0, 0, 0, 0.35), 4.0)
	var body_color := Color.WHITE
	var outline := Color(0.1, 0.1, 0.1)
	if a.kind == "player":
		body_color = Color(0.96, 0.96, 0.98)
	else:
		match a.species:
			"crab": body_color = Color(0.82, 0.40, 0.16)
			"boar": body_color = Color(0.29, 0.18, 0.11)
			"snake": body_color = Color(0.25, 0.49, 0.23)
			"shark": body_color = Color(0.35, 0.42, 0.49)
			"hostile_survivor": body_color = Color(0.63, 0.19, 0.19)
			_: body_color = Color(0.6, 0.6, 0.6)
	draw_circle(screen + Vector2(0, -6), 6.0, body_color)
	draw_arc(screen + Vector2(0, -6), 6.0, 0, TAU, 16, outline, 1.5)
	if a == game.player:
		# Direction tick showing identity.
		draw_circle(screen + Vector2(0, -16), 2.0, Color(1, 0.9, 0.3))
	if a.any_bleeding():
		draw_circle(screen + Vector2(6, -12), 1.5, Color(0.8, 0.1, 0.1))


func _draw_night_overlay() -> void:
	if game == null:
		return
	var h := game.hour()
	var darkness := 0.0
	if game.is_night():
		# Full dark 21:00-03:00, ramping edges.
		var ramp := 1.0
		if h < 3:
			ramp = clampf((h - 1.0) / 2.0, 0.0, 1.0)
		elif h >= 21:
			ramp = clampf((h - 19.0) / 2.0, 0.0, 1.0)
		darkness = 0.55 * ramp
	elif h < 6:
		darkness = 0.25 * (1.0 - (h - 5.0))
	elif h >= 18:
		darkness = 0.25 * clampf((h - 18.0) / 1.5, 0.0, 1.0)
	if darkness <= 0.01:
		return
	var vp_size := Vector2(4000, 2000)
	var color := Color(0.02, 0.03, 0.10, darkness)
	draw_rect(Rect2(-vp_size / 2.0, vp_size), color)
	# Campfire glow.
	var map := game.current_map()
	if map != null and game.player != null:
		var origin := tile_to_screen(game.player.pos)
		for pos: Vector2i in map.structures:
			var s: Dictionary = map.structures[pos]
			if str(s.get("kind")) == "campfire" and float(s.get("fuel", 0)) > 0:
				var pos_screen := tile_to_screen(pos) - origin
				draw_circle(pos_screen + Vector2(0, -6), 60.0, Color(1.0, 0.6, 0.2, 0.10))
				draw_circle(pos_screen + Vector2(0, -6), 28.0, Color(1.0, 0.7, 0.3, 0.14))