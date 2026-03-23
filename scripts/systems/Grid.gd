class_name Grid
extends TileMap

@export var width: int = 100
@export var height: int = 100
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var tree_lights: Array = []
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

	for pos in candidates:
		if placed.size() >= MAX_TREES:
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

		# --- Dirt patch (two-pass for rounded edges) ---
		var centre: Vector2 = pos + Vector2(1.0, 1.0)
		const DIRT_RADIUS := 3.8
		var local_dirt: Dictionary = {}

		for dx in range(-5, 6):
			for dy in range(-5, 6):
				var c := Vector2(centre.x + dx, centre.y + dy)
				if not grid.has(c) or water_tiles.has(c):
					continue
				var dist := Vector2(float(dx), float(dy)).length()
				var paint := false
				if dist <= 2.2:
					paint = true
				else:
					var prob := pow(max(0.0, 1.0 - (dist - 2.2) / (DIRT_RADIUS - 2.2)), 0.5)
					paint = rng.randf() < prob
				if paint:
					local_dirt[c] = true
					dirt_tiles[c] = true

		var dirt_tex := load("res://art/alien dirt.png")
		var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial
		for c in local_dirt:
			var mask := 0
			if local_dirt.has(c + Vector2(0, -1)): mask |= 1
			if local_dirt.has(c + Vector2(1,  0)): mask |= 2
			if local_dirt.has(c + Vector2(0,  1)): mask |= 4
			if local_dirt.has(c + Vector2(-1, 0)): mask |= 8
			if mask == 15:
				set_cell(LAYER_FLOOR, Vector2i(int(c.x), int(c.y)), 6, Vector2i(0, 0))
			else:
				var mat: ShaderMaterial = dirt_base_mat.duplicate()
				mat.set_shader_parameter("cardinal_mask", mask)
				var dirt_sprite := Sprite2D.new()
				dirt_sprite.texture = dirt_tex
				dirt_sprite.position = gridToWorld(c) + Vector2(cell_size * 0.5, cell_size * 0.5)
				dirt_sprite.material = mat
				add_child(dirt_sprite)

		# Mark all 9 cells as occupied
		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				grid[c].occupier = "Tree"
				grid[c].navigable = false
				_tree_root[c] = pos

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


func spawnRocks() -> void:
	var tex_light1 = load("res://art/rock-light-1.png")
	var tex_light2 = load("res://art/rock-light-2.png")
	var tex_dark = load("res://art/rock-dark-1.png")
	var tex_pebbles = load("res://art/pebbles.png")
	const MAX_CLUSTERS = 10
	const MIN_CLUSTER_DISTANCE = 7
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
			shadow.z_index = -1
			add_child(shadow)

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


func get_tree_root(pos: Vector2) -> Vector2:
	return _tree_root.get(pos, pos)


func set_tree_light_energy(energy: float) -> void:
	for light in tree_lights:
		light.energy = energy


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
