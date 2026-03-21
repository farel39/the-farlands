class_name Unit
extends Area2D

signal unitSelected(obj)

var grid: Grid
var pf: Pathfinder
var gui

var data: UnitData = UnitData.new()
var path: PackedVector2Array
var harvest_target: Vector2 = Vector2(-1, -1)

# Each task: { "move_to": Vector2, "harvest_target": Vector2 }
var task_queue: Array = []

func _ready() -> void:
	grid = get_parent().get_parent() as Grid
	pf = grid.get_node("Pathfinding")
	gui = grid.get_parent().get_node("CanvasLayer/GUI")

func _process(delta: float) -> void:
	move(delta)

func move(delta: float) -> void:
	if path.is_empty():
		return
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
	if path.is_empty():
		if harvest_target != Vector2(-1, -1):
			grid.harvest_tree(harvest_target)
			harvest_target = Vector2(-1, -1)
		_start_next_task()


# Immediately move to a grid position, clearing any queued tasks.
func move_to(grid_pos: Vector2) -> void:
	task_queue.clear()
	harvest_target = Vector2(-1, -1)
	path = _build_path(grid_pos)


# Add a harvest task to the back of the queue.
func queue_harvest(dest: Vector2, tree_pos: Vector2) -> void:
	task_queue.append({"move_to": dest, "harvest_target": tree_pos})
	if path.is_empty():
		_start_next_task()


func _start_next_task() -> void:
	if task_queue.is_empty():
		return
	var task: Dictionary = task_queue.pop_front()
	harvest_target = task["harvest_target"]
	path = _build_path(task["move_to"])


func _build_path(grid_pos: Vector2) -> PackedVector2Array:
	var from := pf.getIDGridPos(pf.getWorldID(position))
	var grid_path := pf.getPath(from, grid_pos)
	var world_path := PackedVector2Array()
	world_path.append(position)
	for p in grid_path:
		world_path.append(grid.gridToWorld(p))
	world_path = pf.smoothPath(world_path)
	if not world_path.is_empty():
		world_path.remove_at(0)
	return world_path


func get_grid_pos() -> Vector2:
	return grid.worldToGrid(position)
