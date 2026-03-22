class_name Grid
extends TileMap

@export var width: int = 25
@export var height: int = 25
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var wood: int = 0

@export var show_debug: bool = false

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
			if show_debug:
				var rect = ReferenceRect.new()
				rect.position = gridToWorld(Vector2(x,y))
				rect.size = Vector2(cell_size, cell_size)
				rect.editor_only = false
				$Debug.add_child(rect)
				var label = Label.new()
				label.position = gridToWorld(Vector2(x, y))
				label.text = str(Vector2(x, y))
				$Debug.add_child(label)
	spawnTrees()


func spawnTrees() -> void:
	var tree_texture = load("res://art/tree.png")
	var placed: Array = []
	const MIN_DISTANCE = 3
	const MAX_TREES = 20

	var candidates: Array = []
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			candidates.append(Vector2(x, y))
	candidates.shuffle()

	for pos in candidates:
		if placed.size() >= MAX_TREES:
			break
		# Keep cells near the unit spawn (0,0) clear
		if pos.distance_to(Vector2(0, 0)) < MIN_DISTANCE:
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_DISTANCE:
				too_close = true
				break
		if too_close:
			continue

		placed.append(pos)
		var cell: CellData = grid[pos]
		cell.occupier = "Tree"
		cell.navigable = false

		var sprite := Sprite2D.new()
		sprite.texture = tree_texture
		sprite.position = gridToWorld(pos) + Vector2(cell_size / 2.0, cell_size / 2.0)
		add_child(sprite)
		tree_sprites[pos] = sprite


func gridToWorld(_pos: Vector2) -> Vector2:
	return _pos * cell_size

func worldToGrid(_pos: Vector2) -> Vector2:
	return floor(_pos / cell_size)

func refreshTile(_pos: Vector2) -> void:
	var data = grid[_pos]
	set_cell(LAYER_FLOOR, _pos, data.floorData.id, data.floorData.coords)
	set_cell(LAYER_BUILDING, _pos)


func harvest_tree(pos: Vector2) -> void:
	if not grid.has(pos) or grid[pos].occupier != "Tree":
		return
	wood += 1
	tree_sprites[pos].queue_free()
	tree_sprites.erase(pos)
	var cell: CellData = grid[pos]
	cell.occupier = null
	cell.navigable = true


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


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
