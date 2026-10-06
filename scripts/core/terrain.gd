class_name Terrain
extends RefCounted
## Terrain definitions. Pure data; no rendering concerns.

enum T {
	DEEP_OCEAN,
	OCEAN,
	SHALLOW,
	SAND,
	GRASS,
	JUNGLE,
	ROCK,
	MUD,
}


const DEF: Dictionary = {
	T.DEEP_OCEAN: {
		"name": "Deep Ocean", "color": Color(0.05, 0.16, 0.34),
		"passable": false, "swim": false, "boat": true,
	},
	T.OCEAN: {
		"name": "Ocean", "color": Color(0.10, 0.28, 0.48),
		"passable": false, "swim": false, "boat": true,
	},
	T.SHALLOW: {
		"name": "Shallow Water", "color": Color(0.30, 0.58, 0.68),
		"passable": false, "swim": true, "boat": true,
	},
	T.SAND: {
		"name": "Sand", "color": Color(0.85, 0.78, 0.55),
		"passable": true, "swim": false, "boat": false,
	},
	T.GRASS: {
		"name": "Grass", "color": Color(0.45, 0.66, 0.32),
		"passable": true, "swim": false, "boat": false,
	},
	T.JUNGLE: {
		"name": "Jungle", "color": Color(0.22, 0.46, 0.22),
		"passable": true, "swim": false, "boat": false,
	},
	T.ROCK: {
		"name": "Rock", "color": Color(0.52, 0.52, 0.54),
		"passable": true, "swim": false, "boat": false,
	},
	T.MUD: {
		"name": "Mud", "color": Color(0.42, 0.36, 0.28),
		"passable": true, "swim": false, "boat": false,
	},
}


static func def(t: int) -> Dictionary:
	return DEF.get(t, DEF[T.SAND])


static func name_of(t: int) -> String:
	return str(def(t).get("name", "?"))


static func color_of(t: int) -> Color:
	return def(t).get("color", Color.MAGENTA)


static func is_passable(t: int) -> bool:
	return bool(def(t).get("passable", false))


static func is_boat_ok(t: int) -> bool:
	return bool(def(t).get("boat", false))


static func is_water(t: int) -> bool:
	return t == T.DEEP_OCEAN or t == T.OCEAN or t == T.SHALLOW