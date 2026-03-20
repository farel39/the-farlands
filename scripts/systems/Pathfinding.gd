class_name Pathfinder
extends Node2D

var aStar = AStar2D.new()
@onready var grid: Grid = get_parent() as Grid

const DIRECTIONS = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
]

func addPoints():
	var curID = 0
	for point in grid.grid:
		aStar.add_point(curID, grid.gridToWorld(point))
		curID += 1

func getPointID(gridPoint: Vector2) -> int:
	return aStar.get_closest_point(grid.gridToWorld(gridPoint))

func getWorldID(worldPoint: Vector2) -> int:
	return aStar.get_closest_point(worldPoint)

func getIDWorldPos(_id: int) -> Vector2:
	return aStar.get_point_position(_id)

func getIDGridPos(_id: int) -> Vector2:
	return grid.worldToGrid(getIDWorldPos(_id))

func connectPoint(_point: Vector2):
	var _pointID = getPointID(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		var neighborID = getPointID(neighbor)
		if grid.grid.has(neighbor) and grid.grid[neighbor].navigable:
			aStar.connect_points(_pointID, neighborID)

func disconnectPoint(_point: Vector2):
	var _pointID = getPointID(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		var neighborID = getPointID(neighbor)
		aStar.disconnect_points(_pointID, neighborID)

func connectAllPoints():
	for point in grid.grid:
		connectPoint(point)

func initialize():
	addPoints()
	connectAllPoints()
	for point in grid.grid:
		grid.grid[point].navChanged.connect(_on_nav_changed)

func _on_nav_changed(pos: Vector2) -> void:
	if grid.grid[pos].navigable:
		connectPoint(pos)
	else:
		disconnectPoint(pos)

func getPath(_pointA: Vector2, _pointB: Vector2) -> PackedVector2Array:
	var aID = getPointID(_pointA)
	var bID = getPointID(_pointB)
	var worldPath = aStar.get_point_path(aID, bID)
	var gridPath: PackedVector2Array = []
	for point in worldPath:
		gridPath.append(grid.worldToGrid(point))
	return gridPath

# Removes redundant waypoints by checking direct line-of-sight between points.
# Result: unit walks in straight lines at any angle, only bending around walls.
func smoothPath(world_path: PackedVector2Array) -> PackedVector2Array:
	if world_path.size() <= 2:
		return world_path

	var result := PackedVector2Array()
	result.append(world_path[0])

	var anchor := 0
	while anchor < world_path.size() - 1:
		var farthest := anchor + 1
		for look in range(anchor + 2, world_path.size()):
			if _hasLOS(world_path[anchor], world_path[look]):
				farthest = look
		result.append(world_path[farthest])
		anchor = farthest

	return result

func _hasLOS(a: Vector2, b: Vector2) -> bool:
	var half := Vector2(grid.cell_size, grid.cell_size) * 0.5
	var a_grid = grid.worldToGrid(a + half)
	var b_grid = grid.worldToGrid(b + half)
	for cell in _bresenham(a_grid, b_grid):
		if grid.grid.has(cell) and not grid.grid[cell].navigable:
			return false
	return true

func _bresenham(from: Vector2, to: Vector2) -> Array:
	var cells: Array = []
	var x0: int = int(from.x)
	var y0: int = int(from.y)
	var x1: int = int(to.x)
	var y1: int = int(to.y)
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		cells.append(Vector2(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return cells

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
