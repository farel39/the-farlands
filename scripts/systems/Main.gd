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
	#grid.spawnRedTrees()
	grid.spawnDriftwood()
	grid.spawnRocks()
	grid.spawnMonolith()
	grid.spawnCrabs()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)
	gui.inspect_requested.connect(_on_inspect_requested)
	grid.blueprint_placed.connect(_on_blueprint_placed)
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
		{
			"down": "res://art/characters/the engineer realistic downward.png",
			"side": "res://art/characters/the engineer realistic sideways.png",
			"up":   "res://art/characters/the engineer realistic facing up.png",
			"name": "Raya",
			"role": "Engineer",
			"lines": [
				"I can probably fix the ship... given enough scrap.",
				"Those alien trees are beautiful, but I wouldn't touch them.",
				"The hull integrity is worse than I thought.",
				"I've never seen metal corrode this fast. Must be the atmosphere.",
				"If I had my toolkit I could have us airborne in a week.",
			]
		},
		{
			"down": "res://art/characters/the medic realistic downward.png",
			"side": "res://art/characters/the medic realistic sideways.png",
			"up":   "res://art/characters/the medic realistic facing up.png",
			"name": "Mira",
			"role": "Medic",
			"lines": [
				"Everyone needs rest. Including you.",
				"I've been cataloguing the local fauna. Those crabs are fascinating.",
				"The air here is breathable but I'm detecting trace compounds I don't recognise.",
				"We need fresh water. The tide pools won't sustain us long.",
				"Strange egg on the shore this morning. I'm keeping it under observation.",
			]
		},
		{
			"down": "res://art/characters/the pilot realistic downward.png",
			"side": "res://art/characters/the pilot realistic sideways.png",
			"up":   "res://art/characters/the pilot realistic facing up.png",
			"name": "Dax",
			"role": "Pilot",
			"lines": [
				"I've crash-landed before, but never on a planet this... alive.",
				"No signal. Whatever is blocking comms is close.",
				"That monolith wasn't on any survey map. Someone's been here before us.",
				"I can navigate by the stars once I chart the constellations.",
				"The landing was rough but we're all breathing. That counts as a win.",
			]
		},
	]

	# Place units just below the crashed ship, spread out horizontally
	var base: Vector2 = grid.crash_site_pos
	if base == Vector2(-1, -1):
		base = Vector2(6, 4)  # fallback if ship didn't place
	var spawn_positions: Array = [
		base + Vector2(1, 5),
		base + Vector2(2, 5),
		base + Vector2(3, 5),
	]

	var unit_scene := preload("res://scenes/Unit.tscn")
	var units_to_setup: Array = [unit]
	unit.position = grid.gridToWorld(spawn_positions[0])

	for i in 2:
		var u: Unit = unit_scene.instantiate()
		u.position = grid.gridToWorld(spawn_positions[i + 1])
		$Grid/Units.add_child(u)
		units_to_setup.append(u)

	for i in units_to_setup.size():
		var u: Unit = units_to_setup[i]
		var c: Dictionary = chars[i]
		var down_tex := load(c["down"]) as Texture2D
		var side_tex := load(c["side"]) as Texture2D
		var up_tex   := load(c["up"])   as Texture2D
		u.set_character_textures(down_tex, side_tex, up_tex)
		u.data.name = c["name"]
		u.data.role = c["role"]
		u.data.portrait = down_tex
		u.data.dialog_lines = c["lines"]
		all_units.append(u)
		u.became_idle.connect(_assign_tasks)

	gui.register_units(all_units)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			for u in selected_units:
				u.set_drafted(not u.drafted)
			get_viewport().set_input_as_handled()
			return
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

	if cell.occupier == "CrashedShip":
		gui.show_inventory_panel("Crashed Ship", grid.ship_inventory, mouse_screen)
		return

	if cell.occupier == "SupplyCrate":
		var inv: Dictionary = grid.crate_inventories.get(grid_pos, {})
		gui.show_inventory_panel("Supply Crate", inv, mouse_screen)
		return

	if cell.occupier == "Monolith":
		gui.show_dialog(mouse_screen)
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
	var result: Array = []
	# Spiral outward from center to find enough unique navigable cells.
	for radius in range(0, 6):
		if result.size() >= count:
			break
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if result.size() >= count:
					break
				if abs(dx) != radius and abs(dy) != radius:
					continue  # only the ring at this radius
				var pos := center + Vector2(dx, dy)
				if grid.grid.has(pos) and grid.grid[pos].navigable and not result.has(pos):
					result.append(pos)
	return result


func _on_inspect_requested() -> void:
	if grid.monolith_pos == Vector2(-1, -1):
		return
	# Find closest unit (prefer idle, fall back to any)
	var candidates := all_units.filter(func(u): return not u.drafted and not u.is_busy())
	if candidates.is_empty():
		candidates = all_units.filter(func(u): return not u.drafted)
	if candidates.is_empty():
		return
	var monolith_centre := grid.monolith_pos + Vector2(1, 1)
	var closest: Unit = candidates[0]
	for u in candidates:
		if u.get_grid_pos().distance_to(monolith_centre) < closest.get_grid_pos().distance_to(monolith_centre):
			closest = u
	# Walk to an adjacent free cell next to the monolith
	var dest := Vector2(-1, -1)
	var best_dist := INF
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			if dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1:
				continue
			var c := grid.monolith_pos + Vector2(dx, dy)
			if grid.grid.has(c) and grid.grid[c].navigable:
				var d := closest.get_grid_pos().distance_to(c)
				if d < best_dist:
					best_dist = d
					dest = c
	if dest != Vector2(-1, -1):
		closest.inspect_move_to(dest, func():
			gui.show_monolith_dialog(get_viewport().get_mouse_position())
		)


func _on_cut_requested(grid_pos: Vector2) -> void:
	pending_tasks.append({"type": "harvest", "pos": grid_pos})
	_assign_tasks()


func _on_blueprint_placed(grid_pos: Vector2, _def: Dictionary) -> void:
	pending_tasks.append({"type": "build", "pos": grid_pos})
	_assign_tasks()


func _assign_tasks() -> void:
	while not pending_tasks.is_empty():
		var idle := all_units.filter(func(u): return not u.drafted and not u.is_busy())
		if idle.is_empty():
			break
		var task: Dictionary = pending_tasks[0]
		var closest: Unit = idle[0]
		for u in idle:
			if u.get_grid_pos().distance_to(task.pos) < closest.get_grid_pos().distance_to(task.pos):
				closest = u
		pending_tasks.remove_at(0)
		match task.type:
			"harvest": closest.queue_harvest(task.pos)
			"build":   closest.queue_build(task.pos)


func _process(delta: float) -> void:
	day_time = fmod(day_time + delta / DAY_DURATION, 1.0)
	var sky := _sky_color_at(day_time)
	canvas_modulate.color = sky
	# Lights fade in as the sky darkens (v is HSV brightness, 0=dark, 1=bright)
	var night_factor := 1.0 - sky.v
	grid.set_tree_light_energy(night_factor * 0.4)
	grid.set_red_tree_light_energy(night_factor * 0.9)
	grid.set_crab_light_energy(night_factor * 0.6)
	grid.set_shadow_opacity(sky.v)
