class_name Grid
extends TileMap

@export var width: int = 25
@export var height: int = 25
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var tree_lights: Array = []
var _tree_root: Dictionary = {}  # maps any tree cell → its root (top-left) pos
var wood: int = 0

var water_tiles: Dictionary = {}  # Vector2 → WaterTile node

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
			var rect = ReferenceRect.new()
			rect.position = gridToWorld(Vector2(x,y))
			rect.size = Vector2(cell_size, cell_size)
			rect.editor_only = false
			$Debug.add_child(rect)
			var label = Label.new()
			label.position = gridToWorld(Vector2(x, y))
			label.text = str(Vector2(x, y))
			$Debug.add_child(label)
	$Debug.visible = false
	spawnTrees()


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
	const MAX_TREES = 20

	var candidates: Array = []
	for x in range(0, width - 2):
		for y in range(0, height - 2):
			candidates.append(Vector2(x, y))
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

		# Check all 9 cells are free
		var can_place := true
		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				if not grid.has(c) or grid[c].occupier != null:
					can_place = false
					break
			if not can_place:
				break
		if not can_place:
			continue

		placed.append(pos)

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
func place_water_tile(pos: Vector2, variant: WaterTile.Variant = WaterTile.Variant.SHALLOW) -> void:
	erase_water_tile(pos)
	var tile: WaterTile = _WATER_TILE_SCENE.instantiate()
	tile.position = gridToWorld(pos)
	tile.variant = variant
	$Water.add_child(tile)
	water_tiles[pos] = tile


## Remove the water tile overlay at a grid cell, if any.
func erase_water_tile(pos: Vector2) -> void:
	if water_tiles.has(pos):
		water_tiles[pos].queue_free()
		water_tiles.erase(pos)


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
