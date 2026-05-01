class_name BuildingDefs


const DEFS: Dictionary = {
	"Fabricator": {
		"category": "Production",
		"sprite":   "res://art/structures/fabricator realistic.png",
		"cost":     {"Metal Scrap": 5, "Electronics": 2},
		"size":     Vector2i(2, 1),
		"navigable": false,
		"occupier": "Fabricator",
		"shadow":   false,
		# Source sprite is 2016x2124 (nearly square) but the footprint is 2x1
		# wide. Default fit-to-width scaling makes it 2.1 cells tall — too big.
		# Multiplier shrinks the rendered sprite without changing the grid
		# footprint. Bottom-anchored, so the wall's "footprint" still sits on
		# the floor; only the visible size changes.
		"sprite_scale": 0.65,
	},
	# All three wood-wall pieces share matching thicknesses where they meet —
	# the corner sprite uses non-uniform stretch scaling to fit a 3x3 footprint
	# exactly, and the H/V walls override their perpendicular scale to match
	# the corner's H-arm thickness (146px) and V-arm thickness (50px) per side.
	# Source corner is 1634x1207, H-wall is 1652x459, V-wall is 212x749.
	"Wood Wall (H)": {
		"category": "Structures",
		"sprite":   "res://art/structures/wood wall horizontal.png",
		"cost":     {"Driftwood Piece": 6},
		"size":     Vector2i(3, 1),
		"navigable": false,
		"occupier": "WoodWall",
		"shadow":   false,
		"max_hp":   60,
		# Thickness 1.37 → wall renders 384x146 (1.14 cells tall, ~14% above
		# its 1-cell footprint). Matches corner H-arm thickness for clean joins.
		"thickness": 1.37,
	},
	"Wood Wall (V)": {
		"category": "Structures",
		"sprite":   "res://art/structures/wood wall vertical.png",
		"cost":     {"Driftwood Piece": 6},
		"size":     Vector2i(1, 3),
		"navigable": false,
		"occupier": "WoodWall",
		"shadow":   false,
		"max_hp":   60,
		"scale_axis":    "height",
		# Thickness 0.46 → wall renders ~50x384 (~0.39 cells wide). Matches the
		# corner V-arm thickness so wall-to-corner joins are flush.
		"thickness":     0.46,
		# Right-anchored so the wall sits flush against the east edge of its
		# column — aligns horizontally with the SE corner's V-arm position.
		"sprite_anchor": "right",
	},
	# Corner piece — outer SE corner. Place at the SE corner cell of an
	# enclosure: H walls extend west, V walls extend north from the corner cell.
	# 3x3 footprint with cell_mask blocking only the L-shape (5 cells); the
	# inner 2x2 (top-left of footprint) stays navigable.
	"Wood Wall (Corner)": {
		"category": "Structures",
		"sprite":   "res://art/structures/wood wall corner.png",
		"cost":     {"Driftwood Piece": 4},
		"size":     Vector2i(3, 3),
		"navigable": false,
		"occupier": "WoodWall",
		"shadow":   false,
		"max_hp":   60,
		"scale_axis": "stretch",
		"cell_mask": [
			[false, false, true],
			[false, false, true],
			[true,  true,  true],
		],
	},
	# Stone walls — same architecture as wood, but tuned to match the stone
	# CORNER's thicknesses (124 H / 62 V) instead of the wood walls'. This keeps
	# stone-on-stone enclosures internally consistent. A mixed wood+stone
	# enclosure shows a small thickness step at material boundaries, which is
	# expected behavior — the materials read as visually distinct.
	"Stone Wall (H)": {
		"category": "Structures",
		"sprite":   "res://art/structures/stone wall horizontal.png",
		"cost":     {"Stone": 6},
		"size":     Vector2i(3, 1),
		"navigable": false,
		"occupier": "StoneWall",
		"shadow":   false,
		"max_hp":   200,
		# 0.94 → renders ~384x124, matching stone corner's H-arm thickness.
		"thickness": 0.94,
	},
	"Stone Wall (V)": {
		"category": "Structures",
		"sprite":   "res://art/structures/stone wall vertical.png",
		"cost":     {"Stone": 6},
		"size":     Vector2i(1, 3),
		"navigable": false,
		"occupier": "StoneWall",
		"shadow":   false,
		"max_hp":   200,
		"scale_axis":    "height",
		# 0.72 → renders ~62x384, matching stone corner's V-arm thickness.
		"thickness":     0.72,
		"sprite_anchor": "right",
	},
	"Stone Wall (Corner)": {
		"category": "Structures",
		"sprite":   "res://art/structures/stone wall corner.png",
		"cost":     {"Stone": 4},
		"size":     Vector2i(3, 3),
		"navigable": false,
		"occupier": "StoneWall",
		"shadow":   false,
		"max_hp":   200,
		"scale_axis": "stretch",
		"cell_mask": [
			[false, false, true],
			[false, false, true],
			[true,  true,  true],
		],
	},
	# ── Lighting ────────────────────────────────────────────────────────────
	# light_color / light_energy / light_texture_scale drive a PointLight2D
	# attached to the building sprite when it completes. A def with no light_*
	# keys is just a normal structure — the light spawn is gated on `light_color`
	# being present in Grid.complete_blueprint.
	"Campfire": {
		"category": "Lighting",
		"sprite":   "res://art/structures/campfire realistic.png",
		"cost":     {"Driftwood Piece": 4, "Fiber": 2},
		"size":     Vector2i(1, 1),
		"navigable": false,
		"occupier": "Campfire",
		"shadow":   false,
		"max_hp":   40,
		# Warm orange glow — bumped texture_scale so the light reaches well
		# past the fire ring instead of barely escaping the cell.
		"light_color":   Color(1.0, 0.65, 0.30),
		"light_energy":  1.20,
		"light_texture_scale": 7.0,
	},
	# Comm Relay Antenna — the run's win-condition structure. Right-click a
	# completed Antenna to start the channeling sequence; once the channel
	# completes, EVAC kicks off. The Comm Relay Module input is the key
	# fabricator-gated component that funnels the player through crafting.
	# Source sprite is 1624x2048 (~25% taller than wide). Default width-fit
	# scaling at 2x2 gives only 0.5 cells of vertical overflow — too short
	# to read as a tower. sprite_scale 1.1 bumps the antenna to ~2.78 cells
	# tall (0.8 cells of mast above the footprint) while keeping horizontal
	# overflow minimal so it still reads as a 2x2 building.
	"Comm Relay Antenna": {
		"category": "Comms",
		"sprite":   "res://art/structures/comm relay antenna realistic.png",
		"cost":     {"Comm Relay Module": 1, "Metal Scrap": 4, "Electronics": 1},
		"size":     Vector2i(2, 2),
		"navigable": false,
		"occupier": "CommRelay",
		"shadow":   false,
		"max_hp":   120,
		"sprite_scale": 1.1,
		# Soft cyan glow at the dish so the antenna pulls focus on the
		# battlefield — players should be able to spot it from across the
		# map when picking a relay site.
		"light_color":   Color(0.45, 0.85, 1.0),
		"light_energy":  1.05,
		"light_texture_scale": 5.0,
	},
	"Floodlight": {
		"category": "Lighting",
		"sprite":   "res://art/structures/floodlight realistic.png",
		"cost":     {"Metal Scrap": 6, "Electronics": 2, "Driftwood Piece": 2},
		"size":     Vector2i(2, 2),
		"navigable": false,
		"occupier": "Floodlight",
		"shadow":   false,
		"max_hp":   80,
		"scale_axis": "stretch",
		# Cold-white wide coverage — late-game / wave-prep tactical light.
		"light_color":   Color(0.85, 0.95, 1.0),
		"light_energy":  1.55,
		"light_texture_scale": 8.0,
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
