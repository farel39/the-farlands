class_name Grid
extends TileMap

@export var width: int = 100
@export var height: int = 100
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var tree_lights: Array = []
var red_tree_lights: Array = []
var shadow_sprites: Array = []
var _tree_root: Dictionary = {}  # maps any tree cell → its root (top-left) pos
var wood: int = 0

var water_tiles: Dictionary = {}  # Vector2 → WaterTile node or true
var dirt_tiles: Dictionary = {}   # Vector2 → true  (all cells that are alien dirt)

const _WATER_TILE_SCENE = preload("res://scenes/WaterTile.tscn")

# Placement mode state
var placement_mode: bool = false
var placement_info: Dictionary = {}
var _preview_pos: Vector2 = Vector2(-999, -999)

const LAYER_FLOOR = 0
const LAYER_BUILDING = 1
const LAYER_PREVIEW = 2


func generateGrid():
	for x in width:
		for y in height:
			grid[Vector2(x,y)] = CellData.new(Vector2(x, y))
			grid[Vector2(x,y)].floorData = preload("res://data/floors/sand.tres")
			refreshTile(Vector2(x,y))


func toggle_debug() -> void:
	$Debug.visible = not $Debug.visible


func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))   # center: fully lit
	gradient.set_color(1, Color(1, 1, 1, 0))   # edge: transparent (replaces default white opaque)
	gradient.add_point(0.4, Color(1, 1, 1, 0.5))
	gradient.add_point(0.75, Color(1, 1, 1, 0.1))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex



func spawnTrees() -> void:
	var tree_texture = load("res://art/shore tree alien.png")
	var light_texture := _make_light_texture()
	var placed: Array = []
	const MIN_DISTANCE = 5
	const MAX_TREES = 8

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Pick a biome centre somewhere in the dry half, away from spawn and water.
	const BIOME_RADIUS := 18.0
	var shore_y: int = height / 2
	var biome_centre := Vector2(
		rng.randi_range(int(BIOME_RADIUS) + 2, width  - int(BIOME_RADIUS) - 3),
		rng.randi_range(int(BIOME_RADIUS) + 2, shore_y - int(BIOME_RADIUS) - 3)
	)
	# Nudge away from player spawn
	if biome_centre.distance_to(Vector2(0, 0)) < BIOME_RADIUS:
		biome_centre = Vector2(width * 0.6, shore_y * 0.4)

	var candidates: Array = []
	for x in range(0, width - 2):
		for y in range(0, height - 2):
			var p := Vector2(x, y)
			if p.distance_to(biome_centre) <= BIOME_RADIUS:
				candidates.append(p)
	candidates.shuffle()

	# PASS 1: select placements, collect all dirt into dirt_tiles, mark tree footprints
	var tree_data: Array = []  # Array of {pos, local_dirt}

	for pos in candidates:
		if tree_data.size() >= MAX_TREES:
			break
		if pos.distance_to(Vector2(0, 0)) < MIN_DISTANCE:
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_DISTANCE:
				too_close = true
				break
		if too_close:
			continue

		# Check all 9 cells are free and dry (no water overlay)
		var can_place := true
		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
					can_place = false
					break
			if not can_place:
				break
		if not can_place:
			continue

		placed.append(pos)

		var centre: Vector2 = pos + Vector2(1.0, 1.0)
		const DIRT_RADIUS := 6.5
		var local_dirt: Dictionary = {}

		for dx in range(-8, 9):
			for dy in range(-8, 9):
				var c := Vector2(centre.x + dx, centre.y + dy)
				if not grid.has(c) or water_tiles.has(c) or grid[c].occupier != null:
					continue
				var dist := Vector2(float(dx), float(dy)).length()
				var paint := false
				if dist <= 3.0:
					paint = true
				else:
					var prob := pow(max(0.0, 1.0 - (dist - 3.0) / (DIRT_RADIUS - 3.0)), 0.5)
					paint = rng.randf() < prob
				if paint:
					local_dirt[c] = true
					dirt_tiles[c] = true

		# Mark footprint occupied immediately so later trees' dirt avoids it
		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				grid[c].occupier = "Tree"
				grid[c].navigable = false
				_tree_root[c] = pos

		tree_data.append({pos = pos, local_dirt = local_dirt})

	# PASS 2: render all dirt using the complete global dirt_tiles for correct masks.
	# Use Sprite2D for every tile (no set_cell) so z-ordering is consistent.
	var dirt_tex := load("res://art/alien dirt.png")
	var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial

	for c in dirt_tiles:
		var mask := 0
		if dirt_tiles.has(c + Vector2(0, -1)): mask |= 1
		if dirt_tiles.has(c + Vector2(1,  0)): mask |= 2
		if dirt_tiles.has(c + Vector2(0,  1)): mask |= 4
		if dirt_tiles.has(c + Vector2(-1, 0)): mask |= 8
		var diag := 0
		if dirt_tiles.has(c + Vector2( 1, -1)): diag |= 1  # NE
		if dirt_tiles.has(c + Vector2( 1,  1)): diag |= 2  # SE
		if dirt_tiles.has(c + Vector2(-1,  1)): diag |= 4  # SW
		if dirt_tiles.has(c + Vector2(-1, -1)): diag |= 8  # NW
		var dirt_sprite := Sprite2D.new()
		dirt_sprite.texture = dirt_tex
		dirt_sprite.position = gridToWorld(c) + Vector2(cell_size * 0.5, cell_size * 0.5)
		if mask < 15 or diag < 15:
			var mat: ShaderMaterial = dirt_base_mat.duplicate()
			mat.set_shader_parameter("cardinal_mask", mask)
			mat.set_shader_parameter("diag_mask", diag)
			dirt_sprite.material = mat
		add_child(dirt_sprite)

	# PASS 3: spawn tree sprites, lights, and lily pads
	var lily_tex := load("res://art/alien lily pad plant.png")

	for td in tree_data:
		var pos: Vector2 = td.pos
		var local_dirt: Dictionary = td.local_dirt

		var sprite := Sprite2D.new()
		sprite.texture = tree_texture
		sprite.position = gridToWorld(pos) + Vector2(cell_size * 1.5, cell_size * 1.5)
		add_child(sprite)

		var light := PointLight2D.new()
		light.texture = light_texture
		light.color = Color(0.3, 1.0, 0.7)  # bioluminescent cyan-green
		light.energy = 0.0
		light.texture_scale = 4.5
		sprite.add_child(light)
		tree_lights.append(light)

		tree_sprites[pos] = sprite

		# Scatter lily pad plants across the dirt patch
		var lily_candidates: Array = local_dirt.keys()
		lily_candidates.shuffle()
		var lily_count := rng.randi_range(4, 7)
		var lily_placed := 0
		for lc in lily_candidates:
			if lily_placed >= lily_count:
				break
			if not grid.has(lc) or grid[lc].occupier != null:
				continue
			var lily := Sprite2D.new()
			lily.texture = lily_tex
			lily.position = gridToWorld(lc) + Vector2(cell_size * 0.5, cell_size * 0.5)
			lily.scale = Vector2(0.25, 0.25)
			lily.z_index = 1
			add_child(lily)
			var lily_light := PointLight2D.new()
			lily_light.texture = light_texture
			lily_light.color = Color(0.3, 1.0, 0.7)
			lily_light.energy = 0.0
			lily_light.texture_scale = 4.5
			lily.add_child(lily_light)
			tree_lights.append(lily_light)
			grid[lc].occupier = "LilyPad"
			lily_placed += 1


func spawnCrashSite() -> void:
	var ship_tex  := load("res://art/crashed ship.png") as Texture2D
	var hull_tex  := load("res://art/crashed ship hull large.png") as Texture2D

	const SHIP_TILES := 4   # ship occupies a 4×4 footprint
	const HULL_TILES := 1   # hull fragment occupies a 1×1 footprint

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# --- Place the main crashed ship near player spawn ---
	# Try positions in a small area around (6, 4), away from the water edge
	var ship_pos := Vector2(-1, -1)
	var shore_y: int = height / 2
	for attempt in 40:
		var px: int = rng.randi_range(5, 14)
		var py: int = rng.randi_range(3, min(shore_y - SHIP_TILES - 1, 12))
		var ok := true
		for dx in SHIP_TILES:
			for dy in SHIP_TILES:
				var c := Vector2(px + dx, py + dy)
				if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
					ok = false
					break
			if not ok:
				break
		if ok:
			ship_pos = Vector2(px, py)
			break

	if ship_pos != Vector2(-1, -1):
		for dx in SHIP_TILES:
			for dy in SHIP_TILES:
				var c := ship_pos + Vector2(dx, dy)
				grid[c].occupier = "CrashedShip"
				grid[c].navigable = false

		var sp := gridToWorld(ship_pos) + Vector2(cell_size * SHIP_TILES * 0.5, cell_size * SHIP_TILES * 0.5)
		var s_scale := float(SHIP_TILES * cell_size) / float(ship_tex.get_width())

		var ship_shadow := Sprite2D.new()
		ship_shadow.texture = ship_tex
		ship_shadow.position = sp + Vector2(24, 28)
		ship_shadow.scale = Vector2(s_scale * 1.1, s_scale * 0.5)
		ship_shadow.modulate = Color(0, 0, 0, 0.35)
		add_child(ship_shadow)
		shadow_sprites.append(ship_shadow)

		var ship_sprite := Sprite2D.new()
		ship_sprite.texture = ship_tex
		ship_sprite.scale = Vector2(s_scale, s_scale)
		ship_sprite.position = sp
		add_child(ship_sprite)

	# --- Scatter 1–2 hull fragments near the ship ---
	var hull_count := rng.randi_range(1, 2)
	var hull_placed := 0
	if ship_pos != Vector2(-1, -1):
		for attempt in 60:
			if hull_placed >= hull_count:
				break
			var ox: int = rng.randi_range(-6, 6)
			var oy: int = rng.randi_range(-4, 4)
			var hp := ship_pos + Vector2(ox, oy)
			var ok := true
			for dx in HULL_TILES:
				for dy in HULL_TILES:
					var c := hp + Vector2(dx, dy)
					if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue

			for dx in HULL_TILES:
				for dy in HULL_TILES:
					var c := hp + Vector2(dx, dy)
					grid[c].occupier = "HullFragment"
					grid[c].navigable = false

			var hp_world := gridToWorld(hp) + Vector2(cell_size * HULL_TILES * 0.5, cell_size * HULL_TILES * 0.5)
			var h_scale := float(HULL_TILES * cell_size) / float(hull_tex.get_width())

			var hull_shadow := Sprite2D.new()
			hull_shadow.texture = hull_tex
			hull_shadow.position = hp_world + Vector2(18, 20)
			hull_shadow.scale = Vector2(h_scale * 1.1, h_scale * 0.5)
			hull_shadow.modulate = Color(0, 0, 0, 0.35)
			add_child(hull_shadow)
			shadow_sprites.append(hull_shadow)

			var hull_sprite := Sprite2D.new()
			hull_sprite.texture = hull_tex
			hull_sprite.scale = Vector2(h_scale, h_scale)
			hull_sprite.position = hp_world
			add_child(hull_sprite)

			hull_placed += 1


func spawnDriftwood() -> void:
	var textures: Array = [
		load("res://art/driftwood 1.png"),
		load("res://art/driftwood 2.png"),
		load("res://art/driftwood 3.png"),
		load("res://art/driftwood 4.png"),
		load("res://art/driftwood 5.png"),
	]

	const SHORE_BAND  := 6    # rows above waterline to scatter in
	const COUNT       := 8    # total pieces to attempt
	const MIN_DIST    := 10   # minimum grid distance between pieces
	const MAX_DIM_PX  := 192.0  # scale each piece so its longest side = 1.5 tiles

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = height / 2

	var candidates: Array = []
	for x in range(0, width):
		for y in range(0, shore_y):
			var c := Vector2(x, y)
			if not water_tiles.has(c) and not dirt_tiles.has(c):
				candidates.append(c)
	candidates.shuffle()

	var placed_cells: Array = []
	var placed := 0
	for cell in candidates:
		if placed >= COUNT:
			break
		if not grid.has(cell) or grid[cell].occupier != null or water_tiles.has(cell):
			continue
		var too_close := false
		for pc in placed_cells:
			if cell.distance_to(pc) < MIN_DIST:
				too_close = true
				break
		if too_close:
			continue

		var tex: Texture2D = textures[rng.randi() % textures.size()]
		var longest := float(max(tex.get_width(), tex.get_height()))
		var s := MAX_DIM_PX / longest

		var pos := gridToWorld(cell) + Vector2(cell_size * 0.5, cell_size * 0.5)

		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.scale = Vector2(s * 1.1, s * 0.55)
		shadow.position = pos + Vector2(14, 16)
		shadow.modulate = Color(0, 0, 0, 0.3)
		add_child(shadow)
		shadow_sprites.append(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2(s, s)
		sprite.position = pos
		add_child(sprite)

		grid[cell].occupier = "Driftwood"
		placed_cells.append(cell)
		placed += 1


func spawnRedTrees() -> void:
	const TREE_W     := 3
	const TREE_H     := 3
	const MAX_TREES  := 3
	const MIN_DIST        := 12
	const MIN_DIST_BLUE   := 25  # minimum distance from any blue tree
	const DIRT_RADIUS := 7.0
	const SAP_RADIUS := 5.0   # max grid distance from tree centre for saplings

	var tree_tex := load("res://art/red alien tree.png")
	var sap_textures: Array = [
		load("res://art/red alien tree sampling 1.png"),
		load("res://art/red alien tree sampling 2.png"),
		load("res://art/red alien tree sampling 3.png"),
	]
	var light_texture := _make_light_texture()
	var dirt_tex      := load("res://art/alien dirt.png")
	var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = height / 2

	# Top-left of a TREE_W×TREE_H footprint must fit entirely on dry land
	var candidates: Array = []
	for x in range(0, width - TREE_W):
		for y in range(0, shore_y - TREE_W):
			candidates.append(Vector2(x, y))
	candidates.shuffle()

	var placed: Array = []
	var tree_data: Array = []  # [{pos, local_dirt}]

	# Collect unique blue tree root positions from _tree_root
	var blue_roots: Dictionary = {}
	for root in _tree_root.values():
		blue_roots[root] = true
	var blue_positions: Array = blue_roots.keys()

	# PASS 1 — select placements, collect dirt, mark footprints
	for pos in candidates:
		if tree_data.size() >= MAX_TREES:
			break
		if pos.distance_to(Vector2(0, 0)) < 5:
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_DIST:
				too_close = true
				break
		if too_close:
			continue
		for bp in blue_positions:
			if pos.distance_to(bp) < MIN_DIST_BLUE:
				too_close = true
				break
		if too_close:
			continue

		var can_place := true
		for dx in TREE_W:
			for dy in TREE_H:
				var c: Vector2 = pos + Vector2(dx, dy)
				if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
					can_place = false
					break
			if not can_place:
				break
		if not can_place:
			continue

		placed.append(pos)

		# Dirt patch centred on tree trunk centre
		var centre: Vector2 = pos + Vector2(1, 1)
		var local_dirt: Dictionary = {}
		for dx in range(-8, 9):
			for dy in range(-8, 9):
				var c := Vector2(centre.x + dx, centre.y + dy)
				if not grid.has(c) or water_tiles.has(c) or grid[c].occupier != null:
					continue
				var dist := Vector2(float(dx), float(dy)).length()
				var paint := false
				if dist <= 3.0:
					paint = true
				else:
					var prob := pow(max(0.0, 1.0 - (dist - 3.0) / (DIRT_RADIUS - 3.0)), 0.5)
					paint = rng.randf() < prob
				if paint:
					local_dirt[c] = true
					dirt_tiles[c] = true

		# Mark footprint occupied immediately so later trees avoid it
		for dx in TREE_W:
			for dy in TREE_H:
				var c: Vector2 = pos + Vector2(dx, dy)
				grid[c].occupier = "RedTree"
				grid[c].navigable = false
				_tree_root[c] = pos

		tree_data.append({pos = pos, local_dirt = local_dirt})

	# PASS 2 — render dirt (uses complete dirt_tiles so masks are correct across all patches)
	for td in tree_data:
		var local_dirt: Dictionary = td.local_dirt
		for c in local_dirt:
			var mask := 0
			if dirt_tiles.has(c + Vector2(0, -1)): mask |= 1
			if dirt_tiles.has(c + Vector2(1,  0)): mask |= 2
			if dirt_tiles.has(c + Vector2(0,  1)): mask |= 4
			if dirt_tiles.has(c + Vector2(-1, 0)): mask |= 8
			var diag := 0
			if dirt_tiles.has(c + Vector2( 1, -1)): diag |= 1
			if dirt_tiles.has(c + Vector2( 1,  1)): diag |= 2
			if dirt_tiles.has(c + Vector2(-1,  1)): diag |= 4
			if dirt_tiles.has(c + Vector2(-1, -1)): diag |= 8
			var dirt_sprite := Sprite2D.new()
			dirt_sprite.texture = dirt_tex
			dirt_sprite.position = gridToWorld(c) + Vector2(cell_size * 0.5, cell_size * 0.5)
			if mask < 15 or diag < 15:
				var mat: ShaderMaterial = dirt_base_mat.duplicate()
				mat.set_shader_parameter("cardinal_mask", mask)
				mat.set_shader_parameter("diag_mask", diag)
				dirt_sprite.material = mat
			add_child(dirt_sprite)

	# PASS 3 — spawn tree sprites, lights, and saplings
	for td in tree_data:
		var pos: Vector2 = td.pos
		var local_dirt: Dictionary = td.local_dirt
		var centre: Vector2 = pos + Vector2(1, 1)

		var s := float(TREE_W * cell_size) / float(tree_tex.get_width())
		var sprite := Sprite2D.new()
		sprite.texture = tree_tex
		sprite.scale = Vector2(s, s)
		sprite.position = gridToWorld(pos) + Vector2(cell_size * 1.5, cell_size * 1.5)
		add_child(sprite)

		var light := PointLight2D.new()
		light.texture = light_texture
		light.color = Color(1.0, 0.35, 0.2)  # warm red-orange glow
		light.energy = 0.0
		light.texture_scale = 12.0
		sprite.add_child(light)
		red_tree_lights.append(light)

		tree_sprites[pos] = sprite

		# Saplings — placed close to the trunk within dirt patch
		var sap_candidates: Array = []
		for c in local_dirt.keys():
			if c.distance_to(centre) <= SAP_RADIUS and grid.has(c) and grid[c].occupier == null:
				sap_candidates.append(c)
		sap_candidates.shuffle()
		var sap_count := rng.randi_range(3, 6)
		var sap_placed := 0
		for sc in sap_candidates:
			if sap_placed >= sap_count:
				break
			if not grid.has(sc) or grid[sc].occupier != null:
				continue
			var sap_tex: Texture2D = sap_textures[rng.randi() % 3]
			var sap_s := float(cell_size) / float(sap_tex.get_width())
			var sap := Sprite2D.new()
			sap.texture = sap_tex
			sap.position = gridToWorld(sc) + Vector2(cell_size * 0.5, cell_size * 0.5)
			sap.scale = Vector2(sap_s, sap_s)
			add_child(sap)
			var sap_light := PointLight2D.new()
			sap_light.texture = light_texture
			sap_light.color = Color(1.0, 0.35, 0.2)
			sap_light.energy = 0.0
			sap_light.texture_scale = 5.0
			sap.add_child(sap_light)
			red_tree_lights.append(sap_light)
			grid[sc].occupier = "RedTreeSapling"
			sap_placed += 1


func spawnRocks() -> void:
	var tex_light1 = load("res://art/rock-light-1.png")
	var tex_light2 = load("res://art/rock-light-2.png")
	var tex_dark = load("res://art/rock-dark-1.png")
	var tex_pebbles = load("res://art/pebbles.png")
	const MAX_CLUSTERS = 25
	const MIN_CLUSTER_DISTANCE = 4
	const CLUSTER_RADIUS = 2

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Pick well-spaced cluster centers on dry land
	var candidates: Array = []
	for x in width:
		for y in height:
			candidates.append(Vector2(x, y))
	candidates.shuffle()

	var centers: Array = []
	for pos in candidates:
		if centers.size() >= MAX_CLUSTERS:
			break
		if not grid.has(pos) or grid[pos].occupier != null or water_tiles.has(pos):
			continue
		if pos.distance_to(Vector2(0, 0)) < 4:
			continue
		var too_close := false
		for c in centers:
			if pos.distance_to(c) < MIN_CLUSTER_DISTANCE:
				too_close = true
				break
		if too_close:
			continue
		centers.append(pos)

	# Scatter 2-3 rocks around each center using both textures
	for center in centers:
		var nearby: Array = []
		for dx in range(-CLUSTER_RADIUS, CLUSTER_RADIUS + 1):
			for dy in range(-CLUSTER_RADIUS, CLUSTER_RADIUS + 1):
				var c: Vector2 = center + Vector2(dx, dy)
				if grid.has(c) and grid[c].occupier == null and not water_tiles.has(c):
					nearby.append(c)
		nearby.shuffle()
		var count := rng.randi_range(2, 3)
		for i in min(count, nearby.size()):
			var cell: Vector2 = nearby[i]
			grid[cell].occupier = "Rock"
			grid[cell].navigable = false

			# Pick texture based on whether this cell is alien dirt
			var tex = tex_dark if dirt_tiles.has(cell) else (tex_light1 if rng.randi() % 2 == 0 else tex_light2)
			var center_pos := gridToWorld(cell) + Vector2(cell_size * 0.5, cell_size * 0.5)

			# Shadow: same texture, black tint, offset down-right, drawn first (behind rock)
			var shadow := Sprite2D.new()
			shadow.texture = tex
			shadow.position = center_pos + Vector2(12, 14)
			shadow.scale = Vector2(1.15, 0.6)  # squash vertically for top-down look
			shadow.modulate = Color(0, 0, 0, 0.35)
			add_child(shadow)
			shadow_sprites.append(shadow)

			# Rock sprite on top
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.position = center_pos
			sprite.z_index = 1
			add_child(sprite)

		# Scatter 0-1 pebble sprites loosely around the cluster — decorative only
		if rng.randf() > 0.3:
			continue
		var pebble_count := 1
		for _p in pebble_count:
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(0.3, float(CLUSTER_RADIUS) + 0.8)
			var offset := Vector2(cos(angle), sin(angle)) * dist * cell_size
			var pebble_cell := worldToGrid(gridToWorld(center) + offset)
			if not grid.has(pebble_cell) or water_tiles.has(pebble_cell):
				continue
			var pebble := Sprite2D.new()
			pebble.texture = tex_pebbles
			pebble.position = gridToWorld(pebble_cell) + Vector2(cell_size * 0.5, cell_size * 0.5)
			pebble.z_index = 0
			add_child(pebble)


func spawnTidePools() -> void:
	var pool_textures: Array = [
		load("res://art/tide pool 1 tile var 1.png"),
		load("res://art/tide pool 1 tile var 2.png"),
		load("res://art/tide pool 1 tile var 3.png"),
	]
	var rock_tex   = load("res://art/tide pool rock.png")
	var iron_tex   = load("res://art/iron ore.png")
	var copper_tex = load("res://art/copper ore.png")

	const POOL_SIZE       = 2
	const SHORE_BAND      = 6
	const SPRITE_SCALE    = 0.125
	const MIN_CLUSTER_DIST = 20

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = height / 2

	# All shore-band candidates, shuffled once and reused across cluster attempts
	var all_candidates: Array = []
	for x in range(0, width - POOL_SIZE):
		for y in range(shore_y - SHORE_BAND, shore_y):
			all_candidates.append(Vector2(x, y))
	all_candidates.shuffle()

	var S: float             = cell_size * 2.0
	var light_tex            := _make_light_texture()
	var ring_offsets: Array  = [
		Vector2(0,-S), Vector2(S,0), Vector2(0,S), Vector2(-S,0),
		Vector2(-S,-S), Vector2(S,-S), Vector2(-S,S), Vector2(S,S),
	]
	var extra_side_offsets: Array = [
		[Vector2(-S,-S*2), Vector2(0,-S*2), Vector2(S,-S*2)],
		[Vector2(S*2,-S),  Vector2(S*2,0),  Vector2(S*2,S) ],
		[Vector2(-S,S*2),  Vector2(0,S*2),  Vector2(S,S*2) ],
		[Vector2(-S*2,-S), Vector2(-S*2,0), Vector2(-S*2,S)],
	]
	var adj_offsets: Array = [Vector2(2,0), Vector2(-2,0), Vector2(0,2), Vector2(0,-2)]

	var placed_anchors: Array    = []   # grid positions of placed cluster anchors
	var global_footprints: Dictionary = {}  # all occupied pool cells across clusters

	var target_clusters: int = rng.randi_range(2, 3)

	for _cluster in range(target_clusters):
		# --- Find anchor far from existing clusters ---
		var anchor := Vector2(-1, -1)
		for candidate in all_candidates:
			var ok: bool = true
			# Must be free and not water
			for dx in POOL_SIZE:
				for dy in POOL_SIZE:
					var c: Vector2 = candidate + Vector2(dx, dy)
					if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c) or global_footprints.has(c):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			# Must be far enough from every other cluster
			for pa in placed_anchors:
				if candidate.distance_to(pa) < MIN_CLUSTER_DIST:
					ok = false
					break
			if ok:
				anchor = candidate
				break
		if anchor == Vector2(-1, -1):
			continue

		placed_anchors.append(anchor)

		# --- Grow cluster of 2–3 pools ---
		var pool_count: int    = rng.randi_range(2, 3)
		var pool_positions: Array = [anchor]
		var pool_footprints: Dictionary = {}
		for dx in POOL_SIZE:
			for dy in POOL_SIZE:
				pool_footprints[anchor + Vector2(dx, dy)] = true

		for _i in range(20):
			if pool_positions.size() >= pool_count:
				break
			var base: Vector2 = pool_positions[rng.randi() % pool_positions.size()]
			adj_offsets.shuffle()
			for off in adj_offsets:
				var off_vec: Vector2 = off
				var np: Vector2 = base + off_vec
				var ok: bool = true
				for dx in POOL_SIZE:
					for dy in POOL_SIZE:
						var c: Vector2 = np + Vector2(dx, dy)
						if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c) or pool_footprints.has(c) or global_footprints.has(c):
							ok = false
							break
					if not ok:
						break
				if ok:
					pool_positions.append(np)
					for dx in POOL_SIZE:
						for dy in POOL_SIZE:
							pool_footprints[np + Vector2(dx, dy)] = true
					break

		# Register footprints globally
		for k in pool_footprints:
			global_footprints[k] = true

		# Pool centres in world space
		var pool_centres: Dictionary = {}
		for pp in pool_positions:
			pool_centres[gridToWorld(pp) + Vector2(cell_size, cell_size)] = true

		# Wet-sand underlay: soft dark radial gradient centered on the cluster,
		# large enough to extend well past the rock ring so edges dissolve into sand.
		var cluster_centre: Vector2 = Vector2.ZERO
		for pp in pool_positions:
			cluster_centre += gridToWorld(pp) + Vector2(cell_size, cell_size)
		cluster_centre /= pool_positions.size()

		var wet_gradient := Gradient.new()
		wet_gradient.set_color(0, Color(0.18, 0.14, 0.10, 0.55))
		wet_gradient.set_color(1, Color(0.18, 0.14, 0.10, 0.0))
		var wet_tex := GradientTexture2D.new()
		wet_tex.gradient = wet_gradient
		wet_tex.fill = GradientTexture2D.FILL_RADIAL
		wet_tex.fill_from = Vector2(0.5, 0.5)
		wet_tex.fill_to  = Vector2(1.0, 0.5)
		wet_tex.width  = 256
		wet_tex.height = 256
		var wet_sprite := Sprite2D.new()
		wet_sprite.texture = wet_tex
		wet_sprite.position = cluster_centre
		wet_sprite.scale = Vector2(8.0, 8.0)   # ~1024px radius — well past the outer rock ring
		wet_sprite.z_index = 0
		add_child(wet_sprite)

		# Mark occupiers and spawn pool sprites — shuffle textures so each pool differs
		var shuffled_textures: Array = pool_textures.duplicate()
		shuffled_textures.shuffle()
		for pi in pool_positions.size():
			var pp: Vector2 = pool_positions[pi]
			for dx in POOL_SIZE:
				for dy in POOL_SIZE:
					var c: Vector2 = pp + Vector2(dx, dy)
					grid[c].occupier = "TidePool"
					grid[c].navigable = false
			var cp: Vector2 = gridToWorld(pp) + Vector2(cell_size, cell_size)
			var pool_sprite := Sprite2D.new()
			pool_sprite.texture = shuffled_textures[pi % 3]
			pool_sprite.position = cp
			pool_sprite.scale = Vector2(1.0, 1.0)  # 256px tex → 256px rendered (2 tiles)
			pool_sprite.z_index = 0
			add_child(pool_sprite)
			var light := PointLight2D.new()
			light.texture = light_tex
			light.color = Color(0.1, 0.85, 1.0)
			light.energy = 0.0
			light.texture_scale = 5.5
			pool_sprite.add_child(light)
			tree_lights.append(light)

		# Pass 1: collect rock positions (skip any that fall outside the map)
		var rock_positions: Dictionary = {}
		for pp in pool_positions:
			var cp: Vector2 = gridToWorld(pp) + Vector2(cell_size, cell_size)
			for ro in ring_offsets:
				var ro_vec: Vector2 = ro
				var rp: Vector2 = cp + ro_vec
				if not pool_centres.has(rp) and grid.has(worldToGrid(rp)):
					rock_positions[rp] = true
			for side_opts in extra_side_offsets:
				var opts: Array = side_opts
				var ext: Vector2 = opts[rng.randi() % 3]
				var ep: Vector2 = cp + ext
				if not pool_centres.has(ep) and grid.has(worldToGrid(ep)):
					rock_positions[ep] = true

		# Pass 2: spawn rocks — fade only on sand-facing sides
		var fade_shader := load("res://art/tide_pool_rock.gdshader") as Shader
		for rp_key in rock_positions:
			var rp: Vector2 = rp_key
			var mask: int = 0
			if pool_centres.has(rp+Vector2(0,-S)) or rock_positions.has(rp+Vector2(0,-S)): mask |= 1
			if pool_centres.has(rp+Vector2(S, 0)) or rock_positions.has(rp+Vector2(S, 0)): mask |= 2
			if pool_centres.has(rp+Vector2(0, S)) or rock_positions.has(rp+Vector2(0, S)): mask |= 4
			if pool_centres.has(rp+Vector2(-S,0)) or rock_positions.has(rp+Vector2(-S,0)): mask |= 8
			var rock_sprite := Sprite2D.new()
			rock_sprite.texture = rock_tex
			rock_sprite.position = rp
			rock_sprite.scale = Vector2(1.0, 1.0)  # 256px tex → 256px rendered (2 tiles)
			rock_sprite.z_index = 0
			var rock_mat := ShaderMaterial.new()
			rock_mat.shader = fade_shader
			rock_mat.set_shader_parameter("cardinal_mask", mask)
			rock_mat.set_shader_parameter("fade_width", 0.3)
			rock_sprite.material = rock_mat
			add_child(rock_sprite)
			var rock_gc: Vector2 = worldToGrid(rp)
			if grid.has(rock_gc):
				grid[rock_gc].occupier = "TidePoolRock"

		# Scatter iron and copper ore on a random subset of rock positions
		var ore_candidates: Array = rock_positions.keys()
		ore_candidates.shuffle()
		var ore_count: int = rng.randi_range(2, 3)
		var used_ore_cells: Dictionary = {}
		for i in min(ore_count * 2, ore_candidates.size()):
			if used_ore_cells.size() >= ore_count * 2:
				break
			var ore_pos: Vector2 = ore_candidates[i]
			var gc: Vector2 = worldToGrid(ore_pos)
			if not grid.has(gc) or water_tiles.has(gc) or used_ore_cells.has(gc):
				continue
			used_ore_cells[gc] = true
			var ore_tex: Texture2D = iron_tex if used_ore_cells.size() <= ore_count else copper_tex
			var ore_pos2: Vector2 = gridToWorld(gc) + Vector2(cell_size * 0.5, cell_size * 0.5)

			var ore_shadow := Sprite2D.new()
			ore_shadow.texture = ore_tex
			ore_shadow.position = ore_pos2 + Vector2(10, 12)
			ore_shadow.scale = Vector2(1.1, 0.55)
			ore_shadow.modulate = Color(0, 0, 0, 0.35)
			add_child(ore_shadow)
			shadow_sprites.append(ore_shadow)

			var ore_sprite := Sprite2D.new()
			ore_sprite.texture = ore_tex
			ore_sprite.position = ore_pos2
			ore_sprite.scale = Vector2(1.0, 1.0)
			add_child(ore_sprite)


func get_tree_root(pos: Vector2) -> Vector2:
	return _tree_root.get(pos, pos)


func set_tree_light_energy(energy: float) -> void:
	for light in tree_lights:
		light.energy = energy

func set_red_tree_light_energy(energy: float) -> void:
	for light in red_tree_lights:
		light.energy = energy

func set_shadow_opacity(sky_brightness: float) -> void:
	for s in shadow_sprites:
		s.modulate.a = 0.35 * sky_brightness


func gridToWorld(_pos: Vector2) -> Vector2:
	return _pos * cell_size

func worldToGrid(_pos: Vector2) -> Vector2:
	return floor(_pos / cell_size)

func refreshTile(_pos: Vector2) -> void:
	var data = grid[_pos]
	set_cell(LAYER_FLOOR, _pos, data.floorData.id, data.floorData.coords)
	set_cell(LAYER_BUILDING, _pos)


func harvest_tree(pos: Vector2) -> void:
	var root := get_tree_root(pos)
	if not tree_sprites.has(root):
		return
	wood += 1
	var sprite: Sprite2D = tree_sprites[root]
	for child in sprite.get_children():
		if child is PointLight2D:
			tree_lights.erase(child)
	sprite.queue_free()
	tree_sprites.erase(root)
	for dx in 3:
		for dy in 3:
			var c: Vector2 = root + Vector2(dx, dy)
			if grid.has(c):
				grid[c].occupier = null
				grid[c].navigable = true
			_tree_root.erase(c)


func enter_placement_mode(info: Dictionary) -> void:
	placement_mode = true
	placement_info = info

func exit_placement_mode() -> void:
	placement_mode = false
	placement_info = {}
	erase_cell(LAYER_PREVIEW, _preview_pos)
	_preview_pos = Vector2(-999, -999)


func _input(event: InputEvent) -> void:
	if not placement_mode:
		return

	var grid_pos = worldToGrid(get_global_mouse_position())

	if event is InputEventMouseMotion:
		_update_preview(grid_pos)

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_building(grid_pos)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			exit_placement_mode()
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exit_placement_mode()
		get_viewport().set_input_as_handled()


func _update_preview(grid_pos: Vector2) -> void:
	if grid_pos == _preview_pos:
		return
	erase_cell(LAYER_PREVIEW, _preview_pos)
	_preview_pos = grid_pos
	if grid.has(grid_pos):
		set_cell(LAYER_PREVIEW, grid_pos, placement_info.source_id, Vector2i(0, 0))


func _place_building(grid_pos: Vector2) -> void:
	if not grid.has(grid_pos):
		return
	var cell: CellData = grid[grid_pos]

	var layer: int = placement_info.get("layer", LAYER_BUILDING)

	if layer == LAYER_BUILDING:
		if cell.occupier != null:
			return
		set_cell(LAYER_BUILDING, grid_pos, placement_info.source_id, Vector2i(0, 0))
		cell.occupier = placement_info.name
		cell.navigable = placement_info.get("navigable", true)
	elif layer == LAYER_FLOOR:
		set_cell(LAYER_FLOOR, grid_pos, placement_info.source_id, Vector2i(0, 0))


## Place a water tile overlay at a grid cell. Replaces any existing water tile there.
## Returns the new WaterTile so callers can apply a custom material if needed.
func place_water_tile(pos: Vector2, variant: WaterTile.Variant = WaterTile.Variant.SHALLOW) -> WaterTile:
	erase_water_tile(pos)
	var tile: WaterTile = _WATER_TILE_SCENE.instantiate()
	tile.position = gridToWorld(pos)
	tile.variant = variant
	$Water.add_child(tile)
	water_tiles[pos] = tile
	return tile


## Remove the water tile overlay at a grid cell, if any.
func erase_water_tile(pos: Vector2) -> void:
	if water_tiles.has(pos):
		var entry = water_tiles[pos]
		if entry is Node:
			entry.queue_free()
		water_tiles.erase(pos)


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
