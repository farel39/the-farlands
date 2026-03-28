class_name BuildingDefs


const DEFS: Dictionary = {
	"Fabricator": {
		"category": "Production",
		"sprite":   "res://art/buildings/fabricator realistic.png",
		"cost":     {"Metal Scrap": 5, "Electronics": 2},
		"size":     Vector2i(2, 1),
		"navigable": false,
		"occupier": "Fabricator",
		"shadow":   false,
	},
	"Wood Wall": {
		"category": "Structures",
		"sprite":   "res://art/buildings/woodwall.png",
		"cost":     {"Driftwood Piece": 3},
		"size":     Vector2i(1, 1),
		"navigable": false,
		"occupier": "WoodWall",
	},
	"Stone Wall": {
		"category": "Structures",
		"sprite":   "res://art/buildings/stonewall.png",
		"cost":     {"Iron Chunk": 2},
		"size":     Vector2i(1, 1),
		"navigable": false,
		"occupier": "StoneWall",
	},
}


static func get_categories() -> Array:
	var cats: Array = []
	for key in DEFS:
		var cat: String = DEFS[key].category
		if not cats.has(cat):
			cats.append(cat)
	return cats


static func get_by_category(cat: String) -> Dictionary:
	var result: Dictionary = {}
	for key in DEFS:
		if DEFS[key].category == cat:
			result[key] = DEFS[key]
	return result
