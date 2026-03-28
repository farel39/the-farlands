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
var build_target: Vector2 = Vector2(-1, -1)
var gather_target: Vector2 = Vector2(-1, -1)
var gather_items: Dictionary = {}
var _dest: Vector2 = Vector2(-1, -1)        # grid coords, used for path visualiser
var _dest_world: Vector2 = Vector2(-1, -1)  # exact world destination

const GATHER_DURATION := 1.5  # seconds to stand at source before picking up
var _gather_timer: float = -1.0

var _build_timer: float = -1.0
var _build_duration: float = 1.0

var _tex_down: Texture2D = null
var _tex_side: Texture2D = null
var _tex_up: Texture2D = null
var _shadow: Sprite2D

var _walk_frames_side: Array = []
var _walk_frames_up: Array = []
var _walk_frames_down: Array = []
var _walk_frame_idx: int = 0
var _walk_frame_timer: float = 0.0
var _is_walking_side: bool = false
var _is_walking_up: bool = false
var _is_walking_down: bool = false
var _walk_flip_h: bool = false
var _walk_idle_frame_side: int = 34
var _walk_idle_frame_down: int = 0
var _walk_loop_start_up: int = 0
var _walk_loop_start_down: int = 0
var _walk_up_initial_frame: int = 0
var _walk_down_initial_frame: int = 0
var walk_fps_side: float = 24.0
var walk_fps_up: float = 24.0
var walk_fps_down: float = 24.0
var _bubble_text: String = ""
var _bubble_timer: float = 0.0
var _bubble_cooldown: float = 0.0
const BUBBLE_DURATION := 5.0
const BUBBLE_FADE_TIME := 1.0
const BUBBLE_COOLDOWN := 30.0

var _idle_speech_timer: float = 0.0
const IDLE_SPEECH_MIN := 60.0
const IDLE_SPEECH_MAX := 120.0

var task_queue: Array = []
var _arrive_callback: Callable

var _stuck_check_timer: float = 0.0
var _stuck_last_pos: Vector2 = Vector2.ZERO

var _flashlight: PointLight2D = null
var _glow: PointLight2D = null
var _flashlight_angle: float = PI * 0.5  # default facing down
var _move_dir: Vector2 = Vector2.DOWN
var sight_dir: Vector2 = Vector2.DOWN  # public: current cone direction (smoothed)
const STUCK_CHECK_INTERVAL := 0.5
const STUCK_MIN_MOVE := 4.0
var drafted: bool = false:
	set(value):
		drafted = value
		queue_redraw()
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	grid = get_tree().root.get_node("Main/Grid") as Grid
	pf = grid.get_node("Pathfinding")
	gui = get_tree().root.get_node("Main/CanvasLayer/GUI")
	_idle_speech_timer = randf_range(IDLE_SPEECH_MIN, IDLE_SPEECH_MAX)
	_shadow = Sprite2D.new()
	_shadow.centered = false
	_shadow.modulate = Color(0, 0, 0, 0.35)
	_shadow.z_index = -1
	add_child(_shadow)
	grid.shadow_sprites.append(_shadow)


func set_character_textures(down: Texture2D, side: Texture2D, up: Texture2D = null) -> void:
	_tex_down = down
	_tex_side = side
	_tex_up = up
	_apply_sprite(down, false)


func _apply_sprite(tex: Texture2D, flip_h: bool) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = flip_h
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(tex.get_height())
	sprite.scale = Vector2(s, s)
	var scaled_w := s * tex.get_width()
	# origin is bottom-centre (feet); sprite top-left is (-w/2, -cell_size)
	sprite.position = Vector2(-scaled_w * 0.5, -grid.cell_size)
	if _shadow:
		_shadow.texture = tex
		_shadow.flip_h = flip_h
		_shadow.scale = Vector2(s * 1.1, s * 0.18)
		_shadow.position = Vector2(-scaled_w * 0.55 + 2, -grid.cell_size * 0.18)

func _draw() -> void:
	if drafted:
		_draw_ground_ring(Color(1.0, 0.55, 0.0, 1.0))
		if not path.is_empty():
			_draw_path()
	if selected:
		_draw_corner_brackets(Color(1.0, 1.0, 1.0, 0.9))
	if _bubble_timer > 0.0 and not _bubble_text.is_empty():
		_draw_speech_bubble()


func _draw_ground_ring(col: Color) -> void:
	var cx := 0.0
	var cy := -grid.cell_size * 0.06
	var pulse := sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
	var rx := grid.cell_size * (0.28 + pulse * 0.04)
	var ry := grid.cell_size * (0.07 + pulse * 0.01)
	var steps := 36
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var a := float(i) / steps * TAU
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	# Faint fill
	var fill_pts := PackedVector2Array(pts)
	fill_pts.resize(steps)
	draw_colored_polygon(fill_pts, Color(col.r, col.g, col.b, 0.18))
	draw_polyline(pts, col, 2.0, true)


func _draw_corner_brackets(col: Color) -> void:
	var m := 6.0
	var ln := grid.cell_size * 0.18
	var w := 2.5
	var half := grid.cell_size * 0.5
	var x0 := -half + m;             var y0 := -float(grid.cell_size) + m
	var x1 :=  half - m;             var y1 := -m
	draw_line(Vector2(x0, y0), Vector2(x0 + ln, y0), col, w, true)
	draw_line(Vector2(x0, y0), Vector2(x0, y0 + ln), col, w, true)
	draw_line(Vector2(x1, y0), Vector2(x1 - ln, y0), col, w, true)
	draw_line(Vector2(x1, y0), Vector2(x1, y0 + ln), col, w, true)
	draw_line(Vector2(x0, y1), Vector2(x0 + ln, y1), col, w, true)
	draw_line(Vector2(x0, y1), Vector2(x0, y1 - ln), col, w, true)
	draw_line(Vector2(x1, y1), Vector2(x1 - ln, y1), col, w, true)
	draw_line(Vector2(x1, y1), Vector2(x1, y1 - ln), col, w, true)


func _draw_path() -> void:
	if _dest_world == Vector2(-1, -1):
		return
	var col := Color(1, 1, 1, 0.8)
	var dest_center := _dest_world - global_position
	var prev := Vector2.ZERO  # origin is feet
	for i in range(path.size() - 1):
		var lp := path[i] - global_position
		draw_line(prev, lp, col, 1.5, true)
		prev = lp
	draw_line(prev, dest_center, col, 1.5, true)
	draw_circle(dest_center, 7.0, Color(1, 1, 1, 0.2))
	draw_arc(dest_center, 7.0, 0.0, TAU, 24, col, 1.5, true)


func _draw_speech_bubble() -> void:
	var font := ThemeDB.fallback_font
	var font_size: int = grid.cell_size / 10
	var max_w: float = grid.cell_size * 1.8
	var pad := Vector2(grid.cell_size * 0.06, grid.cell_size * 0.04)
	var tail_h: float = grid.cell_size * 0.08
	var text_size := font.get_multiline_string_size(_bubble_text, HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, 4)
	var bw := text_size.x + pad.x * 2
	var bh := text_size.y + pad.y * 2
	var bx := -bw * 0.5
	var by := -float(grid.cell_size) - bh - tail_h - grid.cell_size * 0.05
	var alpha: float = clamp(_bubble_timer / BUBBLE_FADE_TIME, 0.0, 1.0)
	# Background
	draw_rect(Rect2(bx, by, bw, bh), Color(0.98, 0.96, 0.90, 0.95 * alpha), true)
	draw_rect(Rect2(bx, by, bw, bh), Color(0.3, 0.25, 0.2, alpha), false, 2.0)
	# Tail
	var cx := 0.0
	var tail_pts := PackedVector2Array([
		Vector2(cx - tail_h * 0.6, by + bh),
		Vector2(cx + tail_h * 0.6, by + bh),
		Vector2(cx, by + bh + tail_h),
	])
	draw_colored_polygon(tail_pts, Color(0.98, 0.96, 0.90, 0.95 * alpha))
	draw_polyline(PackedVector2Array([tail_pts[0], tail_pts[2], tail_pts[1]]), Color(0.3, 0.25, 0.2, alpha), 2.0)
	# Text
	draw_multiline_string(font, Vector2(bx + pad.x, by + pad.y + font.get_ascent(font_size)), _bubble_text, HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, 4, Color(0.15, 0.1, 0.05, alpha))

func show_speech(text: String, use_cooldown: bool = false) -> void:
	if use_cooldown and _bubble_cooldown > 0.0:
		return
	_bubble_text = text
	_bubble_timer = BUBBLE_DURATION
	if use_cooldown:
		_bubble_cooldown = BUBBLE_COOLDOWN
	queue_redraw()


func _tick_bubble(delta: float) -> void:
	if _bubble_cooldown > 0.0:
		_bubble_cooldown -= delta
	if _bubble_timer <= 0.0:
		return
	_bubble_timer -= delta
	if _bubble_timer <= 0.0:
		_bubble_timer = 0.0
		_bubble_text = ""
	queue_redraw()


func set_walk_frames_side(frames: Array) -> void:
	_walk_frames_side = frames
	_walk_frame_idx = 0
	_walk_frame_timer = 0.0


func set_walk_frames_up(frames: Array) -> void:
	_walk_frames_up = frames


func set_walk_frames_down(frames: Array) -> void:
	_walk_frames_down = frames
	if frames.size() > _walk_idle_frame_down:
		_apply_sprite(frames[_walk_idle_frame_down], false)


const SEPARATION_RADIUS := 72.0
const SEPARATION_FORCE := 80.0

func _setup_flashlight() -> void:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx := size / 2
	var cy := size / 2
	var half_angle := deg_to_rad(38.0)
	var max_r := float(size) * 0.5
	for x in size:
		for y in size:
			var dx := float(x - cx)
			var dy := float(y - cy)
			if dx <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var dist := sqrt(dx * dx + dy * dy)
			if dist > max_r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var angle := atan2(absf(dy), dx)
			if angle > half_angle:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Fade out within the glow circle (glow radius ~76.8px world, cone scale=4 -> ~20 tex px)
			const HOLE_R := 15.0
			const HOLE_FADE := 8.0
			var hole_alpha: float = clamp((dist - HOLE_R) / HOLE_FADE, 0.0, 1.0)
			var alpha: float = pow(1.0 - angle / half_angle, 0.6) * pow(1.0 - dist / max_r, 0.5) * hole_alpha
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	_flashlight = PointLight2D.new()
	_flashlight.texture = ImageTexture.create_from_image(img)
	_flashlight.color = Color(1.0, 0.92, 0.72)
	_flashlight.energy = 1.4
	_flashlight.texture_scale = 7.0
	_flashlight.blend_mode = PointLight2D.BLEND_MODE_MIX
	_flashlight.position = Vector2(0.0, -grid.cell_size * 0.5)
	add_child(_flashlight)
	# Ambient glow sized to match flashlight range so its falloff doesn't
	# create a visible dark ring inside the cone.
	var glow := PointLight2D.new()
	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(1, 1, 1, 1))
	glow_grad.set_color(1, Color(1, 1, 1, 0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 128
	glow_tex.height = 128
	glow.texture = glow_tex
	glow.color = Color(1.0, 0.93, 0.78)
	glow.energy = 0.7
	glow.texture_scale = 7.0
	glow.position = Vector2(0.0, -grid.cell_size * 0.5)
	add_child(glow)
	_glow = glow

const OBSTACLE_BOTTOM_CLEARANCE := 12.0

func _process(delta: float) -> void:
	if _flashlight == null and grid != null:
		_setup_flashlight()
	move(delta)
	_tick_separation(delta)
	_tick_obstacle_clearance()
	_tick_stuck_check(delta)
	_tick_walk_anim(delta)
	_tick_gather(delta)
	_tick_build(delta)
	_tick_bubble(delta)
	_tick_idle_speech(delta)
	if _flashlight:
		if not path.is_empty():
			_flashlight_angle = atan2(_move_dir.y, _move_dir.x)
		_flashlight.rotation = lerp_angle(_flashlight.rotation, _flashlight_angle, delta * 12.0)
		sight_dir = Vector2(cos(_flashlight.rotation), sin(_flashlight.rotation))
	# Y-sort: transition at tile midpoint — character stays behind an object until
	# their feet pass the centre of the tile below it, not just its bottom edge.
	z_index = int((position.y - grid.cell_size * 0.5) / grid.cell_size)
	if drafted:
		queue_redraw()


func _tick_separation(delta: float) -> void:
	var push := Vector2.ZERO
	for other in get_parent().get_children():
		if other == self or not other is Unit:
			continue
		var diff := position - (other as Unit).position
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.1:
			push += diff.normalized() * (1.0 - dist / SEPARATION_RADIUS) * SEPARATION_FORCE
	position += push * delta


func _tick_obstacle_clearance() -> void:
	# Keep feet at least OBSTACLE_BOTTOM_CLEARANCE pixels below any blocked tile
	# directly above. Edge margin of 40 px ensures lateral drift near a column
	# boundary never triggers a false push-down.
	var col := int(position.x / float(grid.cell_size))
	const EDGE_MARGIN := 40.0
	var tile_left := float(col * grid.cell_size)
	var tile_right := float((col + 1) * grid.cell_size)
	if position.x < tile_left + EDGE_MARGIN or position.x > tile_right - EDGE_MARGIN:
		return
	var start_row := int(position.y / float(grid.cell_size))
	for dy in range(1, 3):
		var row := start_row - dy
		if row < 0:
			break
		var tile := Vector2(col, row)
		if not grid.grid.has(tile):
			break
		if not grid.grid[tile].navigable:
			var tile_bottom := float((row + 1) * grid.cell_size)
			if position.y < tile_bottom + OBSTACLE_BOTTOM_CLEARANCE:
				position.y = tile_bottom + OBSTACLE_BOTTOM_CLEARANCE
			break


func _tick_stuck_check(delta: float) -> void:
	if path.is_empty():
		_stuck_check_timer = 0.0
		_stuck_last_pos = position
		return
	_stuck_check_timer += delta
	if _stuck_check_timer >= STUCK_CHECK_INTERVAL:
		_stuck_check_timer = 0.0
		if position.distance_to(_stuck_last_pos) < STUCK_MIN_MOVE:
			path.clear()
			_dest = Vector2(-1, -1)
			_dest_world = Vector2(-1, -1)
		_stuck_last_pos = position


func _tick_idle_speech(delta: float) -> void:
	if drafted or not path.is_empty() or is_busy():
		_idle_speech_timer = randf_range(IDLE_SPEECH_MIN, IDLE_SPEECH_MAX)
		return
	_idle_speech_timer -= delta
	if _idle_speech_timer <= 0.0:
		_idle_speech_timer = randf_range(IDLE_SPEECH_MIN, IDLE_SPEECH_MAX)
		became_idle.emit()


func _tick_walk_anim(delta: float) -> void:
	if not _is_walking_side and not _is_walking_up and not _is_walking_down:
		return
	var frames: Array
	var fps: float
	var loop_start: int
	if _is_walking_side:
		frames = _walk_frames_side
		fps = walk_fps_side
		loop_start = 0
	elif _is_walking_up:
		frames = _walk_frames_up
		fps = walk_fps_up
		loop_start = _walk_loop_start_up
	else:
		frames = _walk_frames_down
		fps = walk_fps_down
		loop_start = _walk_loop_start_down
	if frames.is_empty():
		return
	_walk_frame_timer += delta
	while _walk_frame_timer >= 1.0 / fps:
		_walk_frame_timer -= 1.0 / fps
		var next: int = _walk_frame_idx + 1
		if next >= frames.size():
			next = loop_start
		_walk_frame_idx = next
	_apply_sprite(frames[_walk_frame_idx], _walk_flip_h)


func _tick_gather(delta: float) -> void:
	if _gather_timer < 0.0:
		return
	_gather_timer -= delta
	if _gather_timer > 0.0:
		return
	_gather_timer = -1.0
	var actual: Dictionary = {}
	for item in gather_items:
		var available := _count_at_source(gather_target, item)
		var take: int = min(gather_items[item], available)
		if take > 0:
			actual[item] = take
	if not actual.is_empty():
		grid.take_from_inventory(gather_target, actual)
		for item in actual:
			data.inventory[item] = data.inventory.get(item, 0) + actual[item]
	gather_target = Vector2(-1, -1)
	gather_items = {}
	_start_next_task()


func _tick_build(delta: float) -> void:
	if _build_timer < 0.0:
		return
	_build_timer -= delta
	var t: float = 1.0 - clamp(_build_timer / _build_duration, 0.0, 1.0)
	grid.set_blueprint_progress(build_target, t)
	if _build_timer > 0.0:
		return
	_build_timer = -1.0
	var bt := build_target
	build_target = Vector2(-1, -1)
	grid.complete_blueprint(bt)
	_start_next_task()


func move(delta: float) -> void:
	if path.is_empty():
		return
	var remaining := data.speed * delta
	while remaining > 0.0 and not path.is_empty():
		var to_next := path[0] - position
		var dist := to_next.length()
		if _tex_down and _tex_side:
			var dir := to_next.normalized()
			_move_dir = dir
			if abs(dir.x) > abs(dir.y):
				if not _is_walking_side:
					_walk_frame_idx = 0
					_walk_frame_timer = 0.0
				_is_walking_side = true
				_is_walking_up = false
				_is_walking_down = false
				_walk_flip_h = dir.x < 0
				if _walk_frames_side.is_empty():
					_apply_sprite(_tex_side, dir.x < 0)
			elif dir.y < 0:
				if not _is_walking_up:
					var was_walking := _is_walking_side or _is_walking_down
					_walk_frame_idx = _walk_loop_start_up if was_walking else _walk_up_initial_frame
					_walk_frame_timer = 0.0
				_is_walking_side = false
				_is_walking_up = true
				_is_walking_down = false
				_walk_flip_h = false
				if _walk_frames_up.is_empty() and _tex_up:
					_apply_sprite(_tex_up, false)
			else:
				if not _is_walking_down:
					var was_walking := _is_walking_side or _is_walking_up
					_walk_frame_idx = _walk_loop_start_down if was_walking else _walk_down_initial_frame
					_walk_frame_timer = 0.0
				_is_walking_side = false
				_is_walking_up = false
				_is_walking_down = true
				_walk_flip_h = false
				if _walk_frames_down.is_empty():
					_apply_sprite(_tex_down, false)
		if dist <= remaining:
			position = path[0]
			path.remove_at(0)
			remaining -= dist
		else:
			position += to_next.normalized() * remaining
			remaining = 0.0
	if path.is_empty():
		if _is_walking_side:
			if _walk_frames_side.size() > _walk_idle_frame_side:
				_apply_sprite(_walk_frames_side[_walk_idle_frame_side], _walk_flip_h)
			_walk_frame_idx = 0
		elif _is_walking_up:
			if not _walk_frames_up.is_empty():
				_apply_sprite(_walk_frames_up[0], false)
			_walk_frame_idx = 0
		elif _is_walking_down:
			if _walk_frames_down.size() > _walk_idle_frame_down:
				_apply_sprite(_walk_frames_down[_walk_idle_frame_down], false)
			_walk_frame_idx = 0
		_is_walking_side = false
		_is_walking_up = false
		_is_walking_down = false
		queue_redraw()
		_dest = Vector2(-1, -1)
		_dest_world = Vector2(-1, -1)
		if _arrive_callback.is_valid():
			var cb := _arrive_callback
			_arrive_callback = Callable()
			cb.call()
		if gather_target != Vector2(-1, -1):
			_gather_timer = GATHER_DURATION
			return
		if harvest_target != Vector2(-1, -1):
			grid.harvest_tree(harvest_target)
			harvest_target = Vector2(-1, -1)
		if build_target != Vector2(-1, -1):
			var cost_total := 0
			if grid.blueprints.has(build_target):
				for v in grid.blueprints[build_target].def.cost.values():
					cost_total += v
			_build_duration = max(2.0, float(cost_total) * 0.8)
			_build_timer = _build_duration
			grid.start_blueprint_build(build_target)
			return
		_start_next_task()

# Drafted: move to an exact world position, routing via grid for obstacle avoidance.
# world_pos is the intended visual landing point (character feet).
func draft_move_to(world_pos: Vector2) -> void:
	harvest_target = Vector2(-1, -1)
	_dest_world = world_pos
	var nav_pos := grid.worldToNav(world_pos)
	if not grid.nav_grid.has(nav_pos) or not grid.nav_grid[nav_pos]:
		var best := Vector2(-1, -1)
		var best_d := INF
		for dx in range(-6, 7):
			for dy in range(-6, 7):
				var nc := nav_pos + Vector2(dx, dy)
				if grid.nav_grid.has(nc) and grid.nav_grid[nc]:
					var nc_center := grid.navToWorld(nc) + Vector2(Grid.NAV_CELL_SIZE * 0.5, Grid.NAV_CELL_SIZE * 0.5)
					var d := world_pos.distance_to(nc_center)
					if d < best_d:
						best_d = d
						best = nc
		if best == Vector2(-1, -1):
			return
		nav_pos = best
		# Clamp to nearest point inside the walkable tile rather than snapping to its center
		var tile_tl := grid.navToWorld(nav_pos)
		world_pos = Vector2(
			clamp(world_pos.x, tile_tl.x, tile_tl.x + Grid.NAV_CELL_SIZE),
			clamp(world_pos.y, tile_tl.y, tile_tl.y + Grid.NAV_CELL_SIZE)
		)
		_dest_world = world_pos
	var grid_pos := grid.worldToGrid(world_pos)
	path = _set_dest(grid_pos)
	# position IS feet — no offset needed
	if not path.is_empty():
		path.resize(path.size() - 1)
	path.append(world_pos)


# Drafted move with a callback on arrival (for inspection).
func draft_inspect_to(grid_pos: Vector2, callback: Callable) -> void:
	_arrive_callback = callback
	harvest_target = Vector2(-1, -1)
	_dest_world = grid.gridToWorld(grid_pos) + Vector2(grid.cell_size * 0.5, grid.cell_size)
	path = _set_dest(grid_pos)


# Undrafted walk: interrupts current task, re-queues it at the front,
# then resumes the queue automatically after arriving.
func interrupt_move_to(grid_pos: Vector2) -> void:
	if harvest_target != Vector2(-1, -1):
		task_queue.push_front({"type": "harvest", "pos": harvest_target})
		harvest_target = Vector2(-1, -1)
	path = _set_dest(grid_pos)


# Walk to grid_pos and call callback once upon arrival.
func inspect_move_to(grid_pos: Vector2, callback: Callable) -> void:
	_arrive_callback = callback
	interrupt_move_to(grid_pos)


# Queue a harvest task by tree grid position.
func queue_harvest(tree_pos: Vector2) -> void:
	task_queue.append({"type": "harvest", "pos": tree_pos})
	if path.is_empty() and not drafted:
		_start_next_task()


# Queue a build task by blueprint top-left grid position.
func queue_build(blueprint_pos: Vector2) -> void:
	task_queue.append({"type": "build", "pos": blueprint_pos})
	if path.is_empty() and not drafted:
		_start_next_task()


func set_drafted(value: bool) -> void:
	drafted = value
	if not path.is_empty():
		_dest = Vector2(-1, -1)
		path = PackedVector2Array([path[0]])
	# Cancel in-progress timers
	_gather_timer = -1.0
	if _build_timer >= 0.0:
		_build_timer = -1.0
		grid.cancel_blueprint_build(build_target)
	if not drafted:
		harvest_target = Vector2(-1, -1)
		build_target = Vector2(-1, -1)
		gather_target = Vector2(-1, -1)
		gather_items = {}
		_idle_speech_timer = randf_range(IDLE_SPEECH_MIN, IDLE_SPEECH_MAX)
		if path.is_empty():
			_start_next_task()


func _start_next_task() -> void:
	if drafted:
		return
	if task_queue.is_empty():
		became_idle.emit()
		return
	var unit_grid := get_grid_pos()

	var has_gather := false
	for t in task_queue:
		if t.type == "gather":
			has_gather = true
			break

	var task: Dictionary
	if has_gather:
		task = task_queue.pop_front()
	else:
		var best_idx := 0
		var best_dist := INF
		for i in task_queue.size():
			var d := unit_grid.distance_to(task_queue[i]["pos"])
			if d < best_dist:
				best_dist = d
				best_idx = i
		task = task_queue.pop_at(best_idx)

	match task.type:
		"harvest":
			var dest := _closest_adjacent(task.pos)
			if dest == Vector2(-1, -1):
				_start_next_task()
				return
			harvest_target = task.pos
			path = _set_dest(dest)

		"build":
			var missing := _plan_gather(task.pos)
			if not missing.is_empty():
				task_queue.push_front(task)
				for src_pos in missing:
					task_queue.push_front({"type": "gather", "pos": src_pos, "items": missing[src_pos]})
				_start_next_task()
				return
			var adj := grid.get_blueprint_adjacent(task.pos)
			if adj.is_empty():
				_start_next_task()
				return
			var best_dest: Vector2 = adj[0]
			for c in adj:
				if unit_grid.distance_to(c) < unit_grid.distance_to(best_dest):
					best_dest = c
			build_target = task.pos
			path = _set_dest(best_dest)

		"gather":
			var dest := _closest_adjacent_to_source(task.pos)
			if dest == Vector2(-1, -1):
				_start_next_task()
				return
			gather_target = task.pos
			gather_items = task.items
			path = _set_dest(dest)


func _plan_gather(blueprint_pos: Vector2) -> Dictionary:
	if not grid.blueprints.has(blueprint_pos):
		return {}
	var cost: Dictionary = grid.blueprints[blueprint_pos].def.cost
	var needed: Dictionary = {}
	for item in cost:
		var have: int = data.inventory.get(item, 0)
		var req: int = cost[item]
		if have < req:
			needed[item] = req - have
	if needed.is_empty():
		return {}
	var plan: Dictionary = {}
	var sources := grid.get_inventory_sources()
	for item in needed:
		var remaining: int = needed[item]
		for src in sources:
			if remaining <= 0:
				break
			if src.inv.has(item) and src.inv[item] > 0:
				var take: int = min(remaining, src.inv[item])
				if not plan.has(src.pos):
					plan[src.pos] = {}
				plan[src.pos][item] = plan[src.pos].get(item, 0) + take
				remaining -= take
	return plan


func _count_at_source(source_pos: Vector2, item: String) -> int:
	if source_pos == grid.crash_site_pos:
		return grid.ship_inventory.get(item, 0)
	if grid.crate_inventories.has(source_pos):
		return grid.crate_inventories[source_pos].get(item, 0)
	return 0


func _closest_adjacent(tree_root: Vector2) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	var unit_grid := get_grid_pos()
	for dx in range(-1, 4):
		for dy in range(-1, 4):
			if dx >= 0 and dx <= 2 and dy >= 0 and dy <= 2:
				continue
			var neighbor := tree_root + Vector2(dx, dy)
			if grid.grid.has(neighbor) and grid.grid[neighbor].navigable:
				var d := unit_grid.distance_to(neighbor)
				if d < best_dist:
					best_dist = d
					best = neighbor
	return best


func _closest_adjacent_to_source(source_pos: Vector2) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	var unit_grid := get_grid_pos()
	for dx in range(-2, 7):
		for dy in range(-2, 7):
			var c := source_pos + Vector2(dx, dy)
			if grid.grid.has(c) and grid.grid[c].navigable:
				var d := unit_grid.distance_to(c)
				if d < best_dist:
					best_dist = d
					best = c
	return best


func _set_dest(grid_pos: Vector2) -> PackedVector2Array:
	_dest = grid_pos
	_stuck_check_timer = 0.0
	_stuck_last_pos = position
	return _build_path(grid_pos)


func _build_path(grid_pos: Vector2) -> PackedVector2Array:
	# position is feet (bottom-centre); shift up to get tile centre for A*
	var char_center := position + Vector2(0.0, -grid.cell_size * 0.5)
	var from_nav := grid.worldToNav(char_center)
	# If center landed inside a blocked tile (character pressed against an obstacle edge),
	# snap to the nearest navigable tile so A* and LOS both start from a valid cell.
	if not grid.nav_grid.get(from_nav, true):
		var best := Vector2(-1, -1)
		var best_d := INF
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var nc := from_nav + Vector2(dx, dy)
				if grid.nav_grid.get(nc, true):
					var nc_world := grid.navToWorld(nc) + Vector2(Grid.NAV_CELL_SIZE * 0.5, Grid.NAV_CELL_SIZE * 0.5)
					var d := char_center.distance_to(nc_world)
					if d < best_d:
						best_d = d
						best = nc
		if best != Vector2(-1, -1):
			from_nav = best
			char_center = grid.navToWorld(from_nav) + Vector2(Grid.NAV_CELL_SIZE * 0.5, Grid.NAV_CELL_SIZE * 0.5)
	var dest_center := grid.gridToWorld(grid_pos) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	var to_nav := grid.worldToNav(dest_center)
	var nav_path := pf.getPath(from_nav, to_nav)
	var world_path := PackedVector2Array()
	world_path.append(char_center)
	for p in nav_path:
		world_path.append(grid.navToWorld(p) + Vector2(Grid.NAV_CELL_SIZE * 0.5, Grid.NAV_CELL_SIZE * 0.5))
	world_path = pf.smoothPath(world_path)
	world_path = pf.tightenPath(world_path)
	if not world_path.is_empty():
		world_path.remove_at(0)
	# Convert tile centres to feet positions (add half cell_size downward)
	var feet_path := PackedVector2Array()
	for wp in world_path:
		feet_path.append(wp + Vector2(0.0, grid.cell_size * 0.5))
	return feet_path


func is_busy() -> bool:
	return not task_queue.is_empty() \
		or harvest_target != Vector2(-1, -1) \
		or build_target != Vector2(-1, -1) \
		or gather_target != Vector2(-1, -1) \
		or _build_timer >= 0.0 \
		or _gather_timer >= 0.0


func get_grid_pos() -> Vector2:
	return grid.worldToGrid(position + Vector2(-grid.cell_size * 0.5, -grid.cell_size))
