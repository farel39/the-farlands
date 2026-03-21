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
			var grid_pos := grid.worldToGrid(get_global_mouse_position())
			if not grid.grid.has(grid_pos):
				return
			var mouse_screen := get_viewport().get_mouse_position()
			if grid_pos == grid.worldToGrid(unit.position):
				gui.show_unit_panel(unit, mouse_screen)
				get_viewport().set_input_as_handled()
				return
			var cell: CellData = grid.grid[grid_pos]
			if cell.occupier == "Tree":
				gui.show_tree_panel(grid_pos, mouse_screen)
			elif cell.navigable:
				if unit.drafted:
					unit.draft_move_to(grid_pos)
				else:
					unit.interrupt_move_to(grid_pos)
			else:
				return
			get_viewport().set_input_as_handled()


func _on_cut_requested(grid_pos: Vector2) -> void:
	unit.queue_harvest(grid_pos)


func _process(_delta: float) -> void:
	pass
