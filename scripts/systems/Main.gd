extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Grid/Units/Unit
@onready var gui = $CanvasLayer/GUI

func _ready() -> void:
	grid.generateGrid()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not grid.placement_mode:
			var grid_pos = grid.worldToGrid(get_global_mouse_position())
			if not grid.grid.has(grid_pos):
				return
			var cell: CellData = grid.grid[grid_pos]
			if cell.occupier == "Tree":
				gui.show_tree_panel(grid_pos, get_viewport().get_mouse_position())
			else:
				if not cell.navigable:
					return
				if unit.drafted:
					unit.draft_move_to(grid_pos)
				elif unit.task_queue.is_empty():
					unit.move_to(grid_pos)
				else:
					return
			get_viewport().set_input_as_handled()


func _on_cut_requested(grid_pos: Vector2) -> void:
	var target := _closest_adjacent(grid_pos)
	if target == Vector2(-1, -1):
		return
	unit.queue_harvest(target, grid_pos)


func _closest_adjacent(pos: Vector2) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	var unit_grid := grid.worldToGrid(unit.position)
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var neighbor: Vector2 = pos + dir
		if grid.grid.has(neighbor) and grid.grid[neighbor].navigable:
			var d := unit_grid.distance_to(neighbor)
			if d < best_dist:
				best_dist = d
				best = neighbor
	return best

func _process(_delta: float) -> void:
	pass
