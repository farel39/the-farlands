extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Grid/Units/Unit
@onready var gui = $CanvasLayer/GUI

var all_units: Array = []
var selected_units: Array = []

var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
const DRAG_THRESHOLD := 8.0

func _ready() -> void:
	grid.generateGrid()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)
	_spawn_units()

func _spawn_units() -> void:
	all_units.append(unit)
	var unit_scene := preload("res://scenes/Unit.tscn")
	for i in 2:
		var u: Unit = unit_scene.instantiate()
		u.position = grid.gridToWorld(Vector2(i + 1, 0))
		$Grid/Units.add_child(u)
		all_units.append(u)


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
		gui.show_tree_panel(grid_pos, mouse_screen)
		return

	if not cell.navigable:
		return

	# Move command — apply to all selected units in formation
	if selected_units.is_empty():
		return
	var drafted := selected_units.filter(func(u): return u.drafted)
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
	var targets := selected_units if not selected_units.is_empty() else all_units
	for u in targets:
		u.queue_harvest(grid_pos)


func _process(_delta: float) -> void:
	pass
