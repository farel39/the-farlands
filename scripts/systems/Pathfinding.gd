class_name Pathfinder
extends Node2D

var aStar = AStar2D.new()
@onready var main = get_tree().root.get_node("Main")
@onready var grid: Grid = main.get_node("Grid")

const DIRECTIONS = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

func addPoints():
	var curID = 0
	for point in grid.grid:
		aStar.add_point(curID, grid.gridToWorld(point))
		curID += 1

func getPointID(gridPoint: Vector2)-> int:
	return aStar.get_closest_point(grid.gridToWorld(gridPoint))

func getWorldID(worldPoint: Vector2) -> int:
	return aStar.get_closest_point(worldPoint)

func getIDWorldPos(_id: int) -> Vector2:
	return aStar.get_point_position(_id)

func getIDGridPos(_id: int) -> Vector2:
	var worldPos = getIDWorldPos(_id)
	return grid.worldToGrid(worldPos)

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

func getPath(_pointA: Vector2, _pointB: Vector2):
	var aID = getPointID(_pointA)
	var bID = getPointID(_pointB)
	var worldPath = aStar.get_point_path(aID, bID)
	var gridPath: PackedVector2Array = []
	for point in worldPath:
		gridPath.append(grid.worldToGrid(point))
	return gridPath
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
