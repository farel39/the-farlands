extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Grid/Units/Unit

func _ready() -> void:
	grid.generateGrid()
	pathfinding.initialize()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not grid.placement_mode:
			var grid_pos = grid.worldToGrid(get_global_mouse_position())
			if grid.grid.has(grid_pos):
				unit.path.assign(pathfinding.getPath(unit.pos, grid_pos))
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	pass
