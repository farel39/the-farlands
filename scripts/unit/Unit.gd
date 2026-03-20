class_name Unit
extends Area2D

signal unitSelected(obj)

var grid: Grid
var pf: Pathfinder
var gui

var data: UnitData = UnitData.new()

var path: Array[Vector2]
var pos: Vector2 :
	get:
		return pos
	set(value):
		pos = value

func _ready() -> void:
	grid = get_parent().get_parent() as Grid
	pf = grid.get_node("Pathfinding")
	gui = grid.get_parent().get_node("CanvasLayer/GUI")
	pos = grid.worldToGrid(position)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	move(delta)
	
func move(delta):
	if path.size()>0:
		if position.distance_to(grid.gridToWorld(path[0]))<5:
			position = grid.gridToWorld(path[0])
			pos = path[0]
			path.pop_front()
		else:
			position += (grid.gridToWorld(path[0]) - position).normalized()*data.speed * delta

#func _input(event):
	#if event is InputEventMouseButton and event.button_index ==MOUSE_BUTTON_LEFT:
		#if event.pressed:
			#var clicked = grid.worldToGrid(get_global_mouse_position())
			#path.assign(pf.getPath(pos, clicked))
