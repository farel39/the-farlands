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
				var from = pathfinding.getIDGridPos(pathfinding.getWorldID(unit.position))
				var grid_path = pathfinding.getPath(from, grid_pos)

				var world_path := PackedVector2Array()
				for p in grid_path:
					world_path.append(grid.gridToWorld(p))

				world_path = pathfinding.smoothPath(world_path)

				# Skip the first waypoint — unit is already at/near it
				if world_path.size() > 0 and unit.position.distance_to(world_path[0]) < grid.cell_size * 0.5:
					world_path.remove_at(0)

				unit.path = world_path
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	pass
