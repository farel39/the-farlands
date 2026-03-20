class_name Pathfinder
extends Node2D

var aStar = AStar2D.new()
@onready var grid: Grid = get_parent() as Grid

const DIRECTIONS = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
]

# Internal: includes disabled points, used for graph operations on specific cells.
func _pid(gridPoint: Vector2) -> int:
	return aStar.get_closest_point(grid.gridToWorld(gridPoint), true)

# Public: excludes disabled (wall) points, used for navigation queries.
func getPointID(gridPoint: Vector2) -> int:
	return aStar.get_closest_point(grid.gridToWorld(gridPoint))

func getWorldID(worldPoint: Vector2) -> int:
	return aStar.get_closest_point(worldPoint)

func getIDWorldPos(_id: int) -> Vector2:
	return aStar.get_point_position(_id)

func getIDGridPos(_id: int) -> Vector2:
	return grid.worldToGrid(getIDWorldPos(_id))

func addPoints():
	var curID = 0
	for point in grid.grid:
		aStar.add_point(curID, grid.gridToWorld(point))
		curID += 1

func connectPoint(_point: Vector2):
	var _pointID = _pid(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		if not grid.grid.has(neighbor) or not grid.grid[neighbor].navigable:
			continue
		# Diagonal moves must not cut through a walled corner
		if direction.x != 0 and direction.y != 0:
			var c1 = _point + Vector2(direction.x, 0)
			var c2 = _point + Vector2(0, direction.y)
			if (grid.grid.has(c1) and not grid.grid[c1].navigable) or \
			   (grid.grid.has(c2) and not grid.grid[c2].navigable):
				continue
		aStar.connect_points(_pointID, _pid(neighbor))

func disconnectPoint(_point: Vector2):
	var _pointID = _pid(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		if grid.grid.has(neighbor):
			aStar.disconnect_points(_pointID, _pid(neighbor))

func connectAllPoints():
	for point in grid.grid:
		connectPoint(point)

func initialize():
	addPoints()
	connectAllPoints()
	for point in grid.grid:
		grid.grid[point].navChanged.connect(_on_nav_changed)

func _on_nav_changed(pos: Vector2) -> void:
	var pid := _pid(pos)
	if grid.grid[pos].navigable:
		aStar.set_point_disabled(pid, false)
		connectPoint(pos)
	else:
		disconnectPoint(pos)
		aStar.set_point_disabled(pid, true)
	_refresh_corner_diagonals(pos)

func _refresh_corner_diagonals(pos: Vector2) -> void:
	var pairs := [
		[pos + Vector2(-1, 0), pos + Vector2(0, -1)],
		[pos + Vector2(-1, 0), pos + Vector2(0,  1)],
		[pos + Vector2( 1, 0), pos + Vector2(0, -1)],
		[pos + Vector2( 1, 0), pos + Vector2(0,  1)],
	]
	for pair in pairs:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		if not (grid.grid.has(a) and grid.grid.has(b)):
			continue
		var aID := _pid(a)
		var bID := _pid(b)
		var all_clear: bool = grid.grid[a].navigable and grid.grid[b].navigable and grid.grid[pos].navigable
		if all_clear:
			aStar.connect_points(aID, bID)
		else:
			aStar.disconnect_points(aID, bID)

func getPath(_pointA: Vector2, _pointB: Vector2) -> PackedVector2Array:
	var aID = getPointID(_pointA)
	var bID = getPointID(_pointB)
	var worldPath = aStar.get_point_path(aID, bID)
	var gridPath: PackedVector2Array = []
	for point in worldPath:
		gridPath.append(grid.worldToGrid(point))
	return gridPath

# Removes redundant waypoints by checking direct line-of-sight between points.
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
	for cell in _supercover(a_grid, b_grid):
		if grid.grid.has(cell) and not grid.grid[cell].navigable:
			return false
	return true

# Supercover DDA: visits every cell the line passes through.
func _supercover(from: Vector2, to: Vector2) -> Array:
	var cells: Array = []
	var x: int = int(from.x)
	var y: int = int(from.y)
	var x1: int = int(to.x)
	var y1: int = int(to.y)
	var dx: int = x1 - x
	var dy: int = y1 - y
	var nx: int = abs(dx)
	var ny: int = abs(dy)
	var sign_x: int = 1 if dx > 0 else -1
	var sign_y: int = 1 if dy > 0 else -1

	cells.append(Vector2(x, y))
	var ix: int = 0
	var iy: int = 0
	while ix < nx or iy < ny:
		var t1: int = (1 + 2 * ix) * ny
		var t2: int = (1 + 2 * iy) * nx
		if t1 == t2:
			cells.append(Vector2(x + sign_x, y))
			cells.append(Vector2(x, y + sign_y))
			x += sign_x
			y += sign_y
			ix += 1
			iy += 1
		elif t1 < t2:
			x += sign_x
			ix += 1
		else:
			y += sign_y
			iy += 1
		cells.append(Vector2(x, y))
	return cells

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
