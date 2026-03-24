class_name Crab
extends Node2D

var grid: Grid

var _tex_down: Texture2D
var _tex_side: Texture2D
var _sprite: Sprite2D

# Wander state
var _idle_timer: float = 0.0
var _idle_duration: float = 0.0
var _path: Array = []   # Array of world Vector2
const SPEED: float = 60.0  # pixels per second

# Shore band: y range to stay within
var shore_y_min: int = 0
var shore_y_max: int = 0

var _rng := RandomNumberGenerator.new()


func setup(down: Texture2D, side: Texture2D, g: Grid) -> void:
	grid = g
	_tex_down = down
	_tex_side = side
	_rng.randomize()
	_idle_duration = _rng.randf_range(0.5, 2.5)
	_apply_sprite(down, false)


func _apply_sprite(tex: Texture2D, flip: bool) -> void:
	_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		return
	_sprite.texture = tex
	_sprite.flip_h = flip
	var s := float(grid.cell_size) / float(tex.get_width())
	_sprite.scale = Vector2(s, s)


func _process(delta: float) -> void:
	if not _path.is_empty():
		_walk(delta)
	else:
		_idle_timer += delta
		if _idle_timer >= _idle_duration:
			_idle_timer = 0.0
			_idle_duration = _rng.randf_range(0.8, 3.5)
			_pick_new_target()


func _walk(delta: float) -> void:
	var remaining := SPEED * delta
	while remaining > 0.0 and not _path.is_empty():
		var to_next: Vector2 = _path[0] - position
		var dist := to_next.length()
		# Update facing direction
		var dir := to_next.normalized()
		if abs(dir.x) > abs(dir.y):
			_apply_sprite(_tex_side, dir.x > 0)
		else:
			_apply_sprite(_tex_down, false)
		if dist <= remaining:
			position = _path[0]
			_path.pop_front()
			remaining -= dist
		else:
			position += dir * remaining
			remaining = 0.0


func _pick_new_target() -> void:
	# Wander to a random sand tile within a few tiles of current position
	var cur := grid.worldToGrid(position)
	const WANDER_RADIUS := 5
	var candidates: Array = []
	for dx in range(-WANDER_RADIUS, WANDER_RADIUS + 1):
		for dy in range(-WANDER_RADIUS, WANDER_RADIUS + 1):
			var c := cur + Vector2(dx, dy)
			if not grid.grid.has(c):
				continue
			if grid.water_tiles.has(c):
				continue
			if grid.dirt_tiles.has(c):
				continue
			# Stay within shore band
			if c.y < shore_y_min or c.y > shore_y_max:
				continue
			candidates.append(c)
	if candidates.is_empty():
		return
	var target: Vector2 = candidates[_rng.randi() % candidates.size()]
	# Build a simple straight-line path (no pathfinder — crabs just roam freely)
	_path = [grid.gridToWorld(target)]
