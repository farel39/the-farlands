class_name Grid
extends TileMap

@export var width: int = 100
@export var height: int = 100
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var tree_lights: Array = []
var red_tree_lights: Array = []
var crab_lights: Array = []
var shadow_sprites: Array = []
var tree_root: Dictionary = {}   # maps any tree cell → its root (top-left) pos
var wood: int = 0

var water_tiles: Dictionary = {}  # Vector2 → true
var dirt_tiles: Dictionary = {}   # Vector2 → true
var crash_site_pos: Vector2 = Vector2(-1, -1)
var monolith_pos: Vector2 = Vector2(-1, -1)
var ship_inventory: Dictionary = {}
var crate_inventories: Dictionary = {}

const _WATER_TILE_SCENE = preload("res://scenes/WaterTile.tscn")

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


# ── Spawn delegates ──────────────────────────────────────────────────────────

func spawnTrees() -> void:      WorldSpawner.spawn_trees(self)
func spawnRedTrees() -> void:   WorldSpawner.spawn_red_trees(self)
func spawnCrashSite() -> void:  WorldSpawner.spawn_crash_site(self)
func spawnDriftwood() -> void:  WorldSpawner.spawn_driftwood(self)
func spawnRocks() -> void:      WorldSpawner.spawn_rocks(self)
func spawnTidePools() -> void:  WorldSpawner.spawn_tide_pools(self)
func spawnMonolith() -> void:   WorldSpawner.spawn_monolith(self)
func spawnCrabs() -> void:      WorldSpawner.spawn_crabs(self)


# ── Tree / harvest ───────────────────────────────────────────────────────────

func get_tree_root(pos: Vector2) -> Vector2:
	return tree_root.get(pos, pos)


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
			tree_root.erase(c)


# ── Night cycle ───────────────────────────────────────────────────────────────

func set_tree_light_energy(energy: float) -> void:
	for light in tree_lights:
		light.energy = energy

func set_red_tree_light_energy(energy: float) -> void:
	for light in red_tree_lights:
		light.energy = energy

func set_crab_light_energy(energy: float) -> void:
	for light in crab_lights:
		light.energy = energy

func set_shadow_opacity(sky_brightness: float) -> void:
	for s in shadow_sprites:
		s.modulate.a = 0.35 * sky_brightness


# ── Tile / coordinate helpers ─────────────────────────────────────────────────

func gridToWorld(_pos: Vector2) -> Vector2:
	return _pos * cell_size

func worldToGrid(_pos: Vector2) -> Vector2:
	return floor(_pos / cell_size)

func refreshTile(_pos: Vector2) -> void:
	var data = grid[_pos]
	set_cell(LAYER_FLOOR, _pos, data.floorData.id, data.floorData.coords)
	set_cell(LAYER_BUILDING, _pos)


# ── Placement mode ────────────────────────────────────────────────────────────

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


# ── Water tiles ───────────────────────────────────────────────────────────────

func place_water_tile(pos: Vector2, variant: WaterTile.Variant = WaterTile.Variant.SHALLOW) -> WaterTile:
	erase_water_tile(pos)
	var tile: WaterTile = _WATER_TILE_SCENE.instantiate()
	tile.position = gridToWorld(pos)
	tile.variant = variant
	$Water.add_child(tile)
	water_tiles[pos] = tile
	return tile


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
