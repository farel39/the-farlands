extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Grid/Units/Unit
@onready var gui = $CanvasLayer/GUI
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var all_units: Array = []
var selected_units: Array = []
var pending_tasks: Array = []

const DAY_DURATION := 120.0  # seconds per full day
var day_time: float = 0.25   # start at midday (0=dawn, 0.25=day, 0.5=dusk, 0.75=night)

# Color keyframes: [time, color]
const SKY_COLORS: Array = [
	[0.00, Color(0.40, 0.30, 0.60)],  # dawn  - soft purple
	[0.25, Color(0.85, 0.90, 1.00)],  # day   - cool blue-white
	[0.50, Color(0.25, 0.20, 0.50)],  # dusk  - deep purple
	[0.75, Color(0.03, 0.03, 0.15)],  # night - dark indigo
	[1.00, Color(0.40, 0.30, 0.60)],  # dawn again
]

func _sky_color_at(t: float) -> Color:
	for i in range(SKY_COLORS.size() - 1):
		var a: Array = SKY_COLORS[i]
		var b: Array = SKY_COLORS[i + 1]
		if t <= b[0]:
			var f: float = (t - a[0]) / (b[0] - a[0])
			return (a[1] as Color).lerp(b[1], f)
	return SKY_COLORS[0][1]

var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
const DRAG_THRESHOLD := 8.0

func _ready() -> void:
	grid.generateGrid()
	_place_water()
	grid.spawnCrashSite()
	grid.spawnTidePools()
	grid.spawnTrees()
	grid.spawnRedTrees()
	grid.spawnDriftwood()
	grid.spawnRocks()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)
	$Grid/Units.z_index = 1
	_spawn_units()


func _place_water() -> void:
	# Bottom half of the map is water (y >= height / 2).
	# One ColorRect per row (not per tile) — 125 nodes instead of 31 250.
	var shore_y: int = grid.height / 2
	var water_rows := float(grid.height - shore_y - 1)

	var base_mat := load("res://data/materials/shallow_water.tres") as ShaderMaterial
	var shoreline_mat := load("res://data/materials/shoreline.tres") as ShaderMaterial
	var water_node: Node2D = grid.get_node("Water")
	var row_width: float = float(grid.width * grid.cell_size)

	# Mark every water cell in the grid dict so trees/rocks avoid them.
	for x in grid.width:
		for y in range(shore_y, grid.height):
			grid.water_tiles[Vector2(x, y)] = true

	# Create one ColorRect per row with a smoothstepped alpha gradient.
	for y in range(shore_y, grid.height):
		var depth := y - shore_y
		var mat: ShaderMaterial
		if depth == 0:
			mat = shoreline_mat.duplicate()
		else:
			var t := smoothstep(0.0, 1.0, float(depth - 1) / water_rows)
			mat = base_mat.duplicate()
			mat.set_shader_parameter("alpha", lerpf(0.08, 0.18, t))
		mat.set_shader_parameter("uv_tile_scale", float(grid.width))

		var rect := ColorRect.new()
		rect.size = Vector2(row_width, float(grid.cell_size))
		rect.position = Vector2(0.0, float(y * grid.cell_size))
		rect.material = mat
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		water_node.add_child(rect)

func _spawn_units() -> void:
	var chars: Array = [
		["res://art/the engineer downward.png", "res://art/the engineer sideway.png"],
		["res://art/the medic downward.png",    "res://art/the medic sideway.png"],
		["res://art/the pilot downward.png",    "res://art/the pilot sideway.png"],
	]

	var unit_scene := preload("res://scenes/Unit.tscn")
	var units_to_setup: Array = [unit]

	for i in 2:
		var u: Unit = unit_scene.instantiate()
		u.position = grid.gridToWorld(Vector2(i + 1, 0))
		$Grid/Units.add_child(u)
		units_to_setup.append(u)

	for i in units_to_setup.size():
		var u: Unit = units_to_setup[i]
		var down_tex := load(chars[i][0]) as Texture2D
		var side_tex := load(chars[i][1]) as Texture2D
		u.set_character_textures(down_tex, side_tex)
		all_units.append(u)
		u.became_idle.connect(_assign_tasks)


func _unhandled_input(event: InputEvent) -> void:
	if grid.placement_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = get_viewport().get_mouse_position()
			_dragging = false
		else:
			if _dragging:
				_finish_box_select()
				gui.hide_selection_box()
			else:
				_handle_click()
			_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse := get_viewport().get_mouse_position()
		if not _dragging and _press_pos.distance_to(mouse) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			gui.update_selection_box(_press_pos, mouse)
			get_viewport().set_input_as_handled()


func _handle_click() -> void:
	var grid_pos := grid.worldToGrid(get_global_mouse_position())
	var mouse_screen := get_viewport().get_mouse_position()
	if not grid.grid.has(grid_pos):
		return

	# Clicked on a unit?
	for u in all_units:
		if grid_pos == grid.worldToGrid(u.position):
			_set_selection([u])
			gui.show_unit_panel(u, mouse_screen)
			return

	var cell: CellData = grid.grid[grid_pos]
	if cell.occupier == "Tree":
		gui.show_tree_panel(grid.get_tree_root(grid_pos), mouse_screen)
		return

	if not cell.navigable:
		return

	# Move command — apply to all drafted units in formation
	var drafted := all_units.filter(func(u): return u.drafted)
	if drafted.is_empty():
		return
	var targets := _formation(grid_pos, drafted.size())
	for i in drafted.size():
		drafted[i].draft_move_to(targets[i])


func _finish_box_select() -> void:
	var box := Rect2(_press_pos, get_viewport().get_mouse_position() - _press_pos).abs()
	var canvas_xform := get_viewport().get_canvas_transform()
	var found: Array = []
	for u in all_units:
		var screen_pos: Vector2 = canvas_xform * u.global_position
		if box.has_point(screen_pos):
			found.append(u)
	_set_selection(found)
	if found.size() > 1:
		gui.show_group_panel(found, get_viewport().get_mouse_position())


func _set_selection(units: Array) -> void:
	for u in all_units:
		u.selected = false
	selected_units = units
	for u in selected_units:
		u.selected = true


func _formation(center: Vector2, count: int) -> Array:
	var dirs := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP,
				Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1),
				Vector2(2,0), Vector2(0,2), Vector2(-2,0), Vector2(0,-2)]
	var result: Array = []
	for d in dirs:
		if result.size() >= count:
			break
		var pos: Vector2 = center + d
		if grid.grid.has(pos) and grid.grid[pos].navigable:
			result.append(pos)
	while result.size() < count:
		result.append(center)
	return result


func _on_cut_requested(grid_pos: Vector2) -> void:
	pending_tasks.append(grid_pos)
	_assign_tasks()


func _assign_tasks() -> void:
	while not pending_tasks.is_empty():
		var idle := all_units.filter(func(u): return not u.drafted and not u.is_busy())
		if idle.is_empty():
			break
		var task: Vector2 = pending_tasks[0]
		var closest: Unit = idle[0]
		for u in idle:
			if u.get_grid_pos().distance_to(task) < closest.get_grid_pos().distance_to(task):
				closest = u
		pending_tasks.remove_at(0)
		closest.queue_harvest(task)


func _process(delta: float) -> void:
	day_time = fmod(day_time + delta / DAY_DURATION, 1.0)
	var sky := _sky_color_at(day_time)
	canvas_modulate.color = sky
	# Lights fade in as the sky darkens (v is HSV brightness, 0=dark, 1=bright)
	var night_factor := 1.0 - sky.v
	grid.set_tree_light_energy(night_factor * 0.4)
	grid.set_red_tree_light_energy(night_factor * 0.9)
	grid.set_shadow_opacity(sky.v)
