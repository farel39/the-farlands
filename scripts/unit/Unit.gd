class_name Unit
extends Area2D

signal unitSelected(obj)
signal became_idle

var grid: Grid
var pf: Pathfinder
var gui

var data: UnitData = UnitData.new()
var path: PackedVector2Array
var harvest_target: Vector2 = Vector2(-1, -1)

var _tex_down: Texture2D = null
var _tex_side: Texture2D = null
var task_queue: Array = []  # each entry: { "tree_pos": Vector2 }
var drafted: bool = false:
	set(value):
		drafted = value
		queue_redraw()
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	grid = get_parent().get_parent() as Grid
	pf = grid.get_node("Pathfinding")
	gui = grid.get_parent().get_node("CanvasLayer/GUI")


func set_character_textures(down: Texture2D, side: Texture2D) -> void:
	_tex_down = down
	_tex_side = side
	_apply_sprite(down, false)


func _apply_sprite(tex: Texture2D, flip_h: bool) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = flip_h
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(tex.get_width())
	sprite.scale = Vector2(s, s)

func _draw() -> void:
	if drafted:
		draw_rect(Rect2(0, 0, 128, 128), Color(1.0, 0.6, 0.0, 0.2), true)
		draw_rect(Rect2(0, 0, 128, 128), Color(1.0, 0.6, 0.0, 1.0), false, 2.0)
	if selected:
		draw_rect(Rect2(2, 2, 124, 124), Color(0.2, 0.8, 0.2, 1.0), false, 2.0)

func _process(delta: float) -> void:
	move(delta)

func move(delta: float) -> void:
	if path.is_empty():
		return
	var remaining := data.speed * delta
	while remaining > 0.0 and not path.is_empty():
		var to_next := path[0] - position
		var dist := to_next.length()
		if _tex_down and _tex_side:
			var dir := to_next.normalized()
			if abs(dir.x) > abs(dir.y):
				_apply_sprite(_tex_side, dir.x < 0)
			else:
				_apply_sprite(_tex_down, false)
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


# Drafted: move immediately, queue preserved but not resumed on arrival.
func draft_move_to(grid_pos: Vector2) -> void:
	harvest_target = Vector2(-1, -1)
	path = _build_path(grid_pos)


# Undrafted walk: interrupts current task, re-queues it at the front,
# then resumes the queue automatically after arriving.
func interrupt_move_to(grid_pos: Vector2) -> void:
	if harvest_target != Vector2(-1, -1):
		task_queue.push_front({"tree_pos": harvest_target})
		harvest_target = Vector2(-1, -1)
	path = _build_path(grid_pos)


# Queue a harvest task by tree grid position.
func queue_harvest(tree_pos: Vector2) -> void:
	task_queue.append({"tree_pos": tree_pos})
	if path.is_empty() and not drafted:
		_start_next_task()


func set_drafted(value: bool) -> void:
	drafted = value
	if not drafted:
		path = PackedVector2Array()
		harvest_target = Vector2(-1, -1)
		_start_next_task()


func _start_next_task() -> void:
	if drafted:
		return
	if task_queue.is_empty():
		became_idle.emit()
		return
	var unit_grid := grid.worldToGrid(position)
	var best_idx := 0
	var best_dist := INF
	for i in task_queue.size():
		var d := unit_grid.distance_to(task_queue[i]["tree_pos"])
		if d < best_dist:
			best_dist = d
			best_idx = i
	var task: Dictionary = task_queue.pop_at(best_idx)
	var tree_pos: Vector2 = task["tree_pos"]
	var dest := _closest_adjacent(tree_pos)
	if dest == Vector2(-1, -1):
		_start_next_task()
		return
	harvest_target = tree_pos
	path = _build_path(dest)


func _closest_adjacent(tree_root: Vector2) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	var unit_grid := grid.worldToGrid(position)
	# Scan all cells surrounding the 3x3 footprint
	for dx in range(-1, 4):
		for dy in range(-1, 4):
			if dx >= 0 and dx <= 2 and dy >= 0 and dy <= 2:
				continue  # skip the 3x3 interior
			var neighbor := tree_root + Vector2(dx, dy)
			if grid.grid.has(neighbor) and grid.grid[neighbor].navigable:
				var d := unit_grid.distance_to(neighbor)
				if d < best_dist:
					best_dist = d
					best = neighbor
	return best


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


func is_busy() -> bool:
	return not task_queue.is_empty() or harvest_target != Vector2(-1, -1)


func get_grid_pos() -> Vector2:
	return grid.worldToGrid(position)
