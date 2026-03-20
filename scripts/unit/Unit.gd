class_name Unit
extends Area2D

signal unitSelected(obj)

var grid: Grid
var pf: Pathfinder
var gui

var data: UnitData = UnitData.new()
var path: PackedVector2Array

func _ready() -> void:
	grid = get_parent().get_parent() as Grid
	pf = grid.get_node("Pathfinding")
	gui = grid.get_parent().get_node("CanvasLayer/GUI")

func _process(delta: float) -> void:
	move(delta)

func move(delta: float) -> void:
	var remaining := data.speed * delta
	while remaining > 0.0 and not path.is_empty():
		var to_next := path[0] - position
		var dist := to_next.length()
		if dist <= remaining:
			position = path[0]
			path.remove_at(0)
			remaining -= dist
		else:
			position += to_next.normalized() * remaining
			remaining = 0.0

func get_grid_pos() -> Vector2:
	return grid.worldToGrid(position)
