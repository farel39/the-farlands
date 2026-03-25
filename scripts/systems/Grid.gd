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

var reserved_cells: Dictionary = {}  # Vector2 → Unit, cells claimed as walk destinations

func reserve_cell(cell: Vector2, unit) -> void:
	reserved_cells[cell] = unit

func release_cell(cell: Vector2, unit) -> void:
	if reserved_cells.get(cell) == unit:
		reserved_cells.erase(cell)

func is_cell_reserved(cell: Vector2, exclude_unit) -> bool:
	return reserved_cells.has(cell) and reserved_cells[cell] != exclude_unit

var blueprint_mode: bool = false
var blueprints: Dictionary = {}   # top-left grid pos → {def, sprite}
var _bp_def: Dictionary = {}
var _bp_preview: Sprite2D = null

signal blueprint_placed(grid_pos: Vector2, def: Dictionary)

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
	if blueprint_mode:
		_handle_blueprint_input(event)
		return
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


# ── Blueprint mode ────────────────────────────────────────────────────────────

func enter_blueprint_mode(def: Dictionary) -> void:
	blueprint_mode = true
	_bp_def = def
	_bp_preview = Sprite2D.new()
	_bp_preview.texture = load(def.sprite) as Texture2D
	var size: Vector2i = def.size
	var s := float(size.x * cell_size) / float(_bp_preview.texture.get_width())
	_bp_preview.scale = Vector2(s, s)
	_bp_preview.modulate = Color(1, 1, 1, 0.5)
	_bp_preview.z_index = 10
	add_child(_bp_preview)


func exit_blueprint_mode() -> void:
	blueprint_mode = false
	_bp_def = {}
	if _bp_preview:
		_bp_preview.queue_free()
		_bp_preview = null


func _handle_blueprint_input(event: InputEvent) -> void:
	var grid_pos := worldToGrid(get_global_mouse_position())
	if event is InputEventMouseMotion and _bp_preview:
		var size: Vector2i = _bp_def.size
		_bp_preview.position = gridToWorld(grid_pos) + Vector2(size.x * cell_size * 0.5, size.y * cell_size * 0.5)
		_bp_preview.modulate = Color(1, 1, 1, 0.5) if _can_place_blueprint(grid_pos) else Color(1, 0.3, 0.3, 0.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_blueprint_at(grid_pos)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			exit_blueprint_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exit_blueprint_mode()
		get_viewport().set_input_as_handled()


func _can_place_blueprint(grid_pos: Vector2) -> bool:
	var size: Vector2i = _bp_def.size
	for dx in size.x:
		for dy in size.y:
			var c := grid_pos + Vector2(dx, dy)
			if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
				return false
	return true


func _place_blueprint_at(grid_pos: Vector2) -> void:
	if not _can_place_blueprint(grid_pos):
		return
	var def := _bp_def
	var size: Vector2i = def.size
	for dx in size.x:
		for dy in size.y:
			var c := grid_pos + Vector2(dx, dy)
			grid[c].occupier = "Blueprint"
			grid[c].navigable = false
	var tex := load(def.sprite) as Texture2D
	var bp_sprite := Sprite2D.new()
	bp_sprite.texture = tex
	var s := float(size.x * cell_size) / float(tex.get_width())
	bp_sprite.scale = Vector2(s, s)
	bp_sprite.position = gridToWorld(grid_pos) + Vector2(size.x * cell_size * 0.5, size.y * cell_size * 0.5)
	bp_sprite.modulate = Color(0.5, 0.8, 1.0, 0.5)
	bp_sprite.z_index = 2
	add_child(bp_sprite)
	blueprints[grid_pos] = {def = def, sprite = bp_sprite}
	blueprint_placed.emit(grid_pos, def)
	exit_blueprint_mode()


func complete_blueprint(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var bp: Dictionary = blueprints[grid_pos]
	var def: Dictionary = bp.def
	var size: Vector2i = def.size
	var sprite := bp.sprite as Sprite2D
	sprite.modulate = Color(1, 1, 1, 1)
	for dx in size.x:
		for dy in size.y:
			var c := grid_pos + Vector2(dx, dy)
			if grid.has(c):
				grid[c].occupier = def.occupier
				grid[c].navigable = def.navigable
	# Remove progress bar if present.
	cancel_blueprint_build(grid_pos)
	# Add shadow under the completed building (unless the def opts out).
	if def.get("shadow", true):
		var tex := sprite.texture
		var s := sprite.scale.x
		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.scale = Vector2(s * 1.1, s * 0.2)
		shadow.position = sprite.position + Vector2(size.x * cell_size * 0.06, size.y * cell_size * 0.72)
		shadow.modulate = Color(0, 0, 0, 0.35)
		shadow.z_index = sprite.z_index - 1
		add_child(shadow)
		shadow_sprites.append(shadow)
	blueprints.erase(grid_pos)


# Returns [{pos: Vector2, inv: Dictionary}] for ship + all non-empty crates.
func get_inventory_sources() -> Array:
	var sources: Array = []
	if not ship_inventory.is_empty():
		sources.append({"pos": crash_site_pos, "inv": ship_inventory})
	for pos in crate_inventories:
		var inv: Dictionary = crate_inventories[pos]
		if not inv.is_empty():
			sources.append({"pos": pos, "inv": inv})
	return sources


# Remove items from the inventory at source_pos (ship or crate).
# Takes as much as available for each item; doesn't error if short.
func take_from_inventory(source_pos: Vector2, items: Dictionary) -> void:
	var inv: Dictionary
	if source_pos == crash_site_pos:
		inv = ship_inventory
	elif crate_inventories.has(source_pos):
		inv = crate_inventories[source_pos]
	else:
		return
	for item in items:
		var amount: int = items[item]
		if inv.has(item):
			inv[item] = max(0, inv[item] - amount)
			if inv[item] == 0:
				inv.erase(item)


# Shows a progress bar above the blueprint while it's being built.
func start_blueprint_build(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var def: Dictionary = blueprints[grid_pos].def
	var size: Vector2i = def.size
	var bar_left := gridToWorld(grid_pos)
	var bar_w := float(size.x * cell_size)
	var bar_y := bar_left.y - 16.0

	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 10.0
	bar_bg.default_color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index = 20
	add_child(bar_bg)

	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 10.0
	bar_fill.default_color = Color(0.2, 0.85, 0.3, 1.0)
	bar_fill.z_index = 21
	add_child(bar_fill)

	blueprints[grid_pos]["bar_bg"]   = bar_bg
	blueprints[grid_pos]["bar_fill"] = bar_fill
	blueprints[grid_pos]["bar_x"]    = bar_left.x
	blueprints[grid_pos]["bar_y"]    = bar_y
	blueprints[grid_pos]["bar_w"]    = bar_w


func set_blueprint_progress(grid_pos: Vector2, t: float) -> void:
	if not blueprints.has(grid_pos) or not blueprints[grid_pos].has("bar_fill"):
		return
	var bp: Dictionary = blueprints[grid_pos]
	var fill := bp["bar_fill"] as Line2D
	fill.set_point_position(1, Vector2(float(bp["bar_x"]) + float(bp["bar_w"]) * t, float(bp["bar_y"])))


func cancel_blueprint_build(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var bp: Dictionary = blueprints[grid_pos]
	if bp.has("bar_bg"):
		(bp["bar_bg"] as Line2D).queue_free()
		bp.erase("bar_bg")
	if bp.has("bar_fill"):
		(bp["bar_fill"] as Line2D).queue_free()
		bp.erase("bar_fill")


func get_blueprint_adjacent(grid_pos: Vector2) -> Array:
	if not blueprints.has(grid_pos):
		return []
	var size: Vector2i = blueprints[grid_pos].def.size
	var result: Array = []
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue
			var c := grid_pos + Vector2(dx, dy)
			if grid.has(c) and grid[c].navigable:
				result.append(c)
	return result


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
