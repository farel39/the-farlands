extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Grid/Units/Unit
@onready var gui = $CanvasLayer/GUI
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var all_units: Array = []
var selected_units: Array = []
var pending_tasks: Array = []

var _inspect_popup: Panel = null
var _inspect_btn: Button = null
var _inspect_pending: Callable

const DAY_DURATION := 120.0  # seconds per full day
var day_time: float = 0.25   # start at midday (0=dawn, 0.25=day, 0.5=dusk, 0.75=night)

# Color keyframes: [time, color]
const SKY_COLORS: Array = [
	[0.00, Color(0.40, 0.30, 0.60)],  # dawn  - soft purple
	[0.25, Color(0.85, 0.90, 1.00)],  # day   - cool blue-white
	[0.50, Color(0.25, 0.20, 0.50)],  # dusk  - deep purple
	[0.75, Color(0.03, 0.03, 0.15)],  # night - dark indigo
	[1.00, Color(0.40, 0.30, 0.60)],  # dawn again
]

func _sky_color_at(t: float) -> Color:
	for i in range(SKY_COLORS.size() - 1):
		var a: Array = SKY_COLORS[i]
		var b: Array = SKY_COLORS[i + 1]
		if t <= b[0]:
			var f: float = (t - a[0]) / (b[0] - a[0])
			return (a[1] as Color).lerp(b[1], f)
	return SKY_COLORS[0][1]

var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
const DRAG_THRESHOLD := 8.0

func _ready() -> void:
	grid.generateGrid()
	_place_water()
	grid.spawnCrashSite()
	grid.spawnTidePools()
	grid.spawnTrees()
	#grid.spawnRedTrees()
	grid.spawnDriftwood()
	grid.spawnRocks()
	grid.spawnMonolith()
	grid.spawnCrabs()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)
	gui.inspect_requested.connect(_on_inspect_requested)
	grid.blueprint_placed.connect(_on_blueprint_placed)
	$Grid/Units.z_index = 1
	_spawn_units()
	_setup_inspect_popup()


func _place_water() -> void:
	# Bottom half of the map is water (y >= height / 2).
	# One ColorRect per row (not per tile) — 125 nodes instead of 31 250.
	var shore_y: int = grid.height / 2
	var water_rows := float(grid.height - shore_y - 1)

	var base_mat := load("res://data/materials/shallow_water.tres") as ShaderMaterial
	var shoreline_mat := load("res://data/materials/shoreline.tres") as ShaderMaterial
	var water_node: Node2D = grid.get_node("Water")
	var row_width: float = float(grid.width * grid.cell_size)

	# Mark every water cell in the grid dict so trees/rocks avoid them.
	for x in grid.width:
		for y in range(shore_y, grid.height):
			grid.water_tiles[Vector2(x, y)] = true

	# Create one ColorRect per row with a smoothstepped alpha gradient.
	for y in range(shore_y, grid.height):
		var depth := y - shore_y
		var mat: ShaderMaterial
		if depth == 0:
			mat = shoreline_mat.duplicate()
		else:
			var t := smoothstep(0.0, 1.0, float(depth - 1) / water_rows)
			mat = base_mat.duplicate()
			mat.set_shader_parameter("alpha", lerpf(0.08, 0.18, t))
		mat.set_shader_parameter("uv_tile_scale", float(grid.width))

		var rect := ColorRect.new()
		rect.size = Vector2(row_width, float(grid.cell_size))
		rect.position = Vector2(0.0, float(y * grid.cell_size))
		rect.material = mat
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		water_node.add_child(rect)

func _spawn_units() -> void:
	var chars: Array = [
		{
			"down": "res://art/characters/the engineer realistic downward.png",
			"side": "res://art/characters/the engineer realistic sideways.png",
			"up":   "res://art/characters/the engineer realistic facing up.png",
			"name": "Raya",
			"role": "Engineer",
			"lines": [
				"I can probably fix the ship... given enough scrap.",
				"Those alien trees are beautiful, but I wouldn't touch them.",
				"The hull integrity is worse than I thought.",
				"I've never seen metal corrode this fast. Must be the atmosphere.",
				"If I had my toolkit I could have us airborne in a week.",
			],
			"inspect": {
				"rock": [
					"Unusual crystalline structure. Not from any geological survey I know.",
					"Dense. Could be useful as a building foundation.",
					"The mineral composition is unlike anything back home.",
				],
				"ship": [
					"Hull integrity at maybe thirty percent. We have our work cut out.",
					"The secondary thrusters are completely gone. That's going to be a problem.",
					"If I can salvage the power coupling we might actually get off this rock.",
				],
				"crate": [
					"Let's see what we're working with here.",
					"Standard emergency kit. Someone packed this well.",
					"These supplies could last us a while if we're careful.",
				],
				"monolith": [
					"These engravings aren't decorative. They're schematics.",
					"Whatever built this had engineering knowledge we don't.",
					"I can't place the alloy. It's not in any database I have.",
				],
			},
		},
		{
			"down": "res://art/characters/the medic realistic downward.png",
			"side": "res://art/characters/the medic realistic sideways.png",
			"up":   "res://art/characters/the medic realistic facing up.png",
			"name": "Mira",
			"role": "Medic",
			"lines": [
				"Everyone needs rest. Including you.",
				"I've been cataloguing the local fauna. Those crabs are fascinating.",
				"The air here is breathable but I'm detecting trace compounds I don't recognise.",
				"We need fresh water. The tide pools won't sustain us long.",
				"Strange egg on the shore this morning. I'm keeping it under observation.",
			],
			"inspect": {
				"rock": [
					"These formations remind me of calcium deposits. Fascinating.",
					"I wonder if there's anything medicinally useful in these.",
					"Rough terrain. Watch your footing out here.",
				],
				"ship": [
					"I've set up a small triage area near the wreckage.",
					"The crash could have been much worse. We were lucky.",
					"Still finding useful medical supplies buried in the debris.",
				],
				"crate": [
					"Medical supplies are lower than I'd like. We need to ration.",
					"I've catalogued everything in here. We're managing.",
					"A few things here I can use to patch everyone up.",
				],
				"monolith": [
					"There's something biological about these markings. Like growth patterns.",
					"I feel strange standing near it. That's not nothing.",
					"Whatever carved this was methodical. Almost clinical.",
				],
			},
		},
		{
			"down": "res://art/characters/the pilot realistic downward.png",
			"side": "res://art/characters/the pilot realistic sideways.png",
			"up":   "res://art/characters/the pilot realistic facing up.png",
			"name": "Dax",
			"role": "Pilot",
			"lines": [
				"I've crash-landed before, but never on a planet this... alive.",
				"No signal. Whatever is blocking comms is close.",
				"That monolith wasn't on any survey map. Someone's been here before us.",
				"I can navigate by the stars once I chart the constellations.",
				"The landing was rough but we're all breathing. That counts as a win.",
			],
			"inspect": {
				"rock": [
					"Good landmark. I'm mentally mapping this place.",
					"Solid formation. Nothing I haven't seen on a dozen other worlds.",
					"I'd mark this on a chart if I still had one.",
				],
				"ship": [
					"She was a good ship. We'll get her flying again.",
					"I've seen worse crash landings. Barely.",
					"The frame might be salvageable. The engines are a different story.",
				],
				"crate": [
					"Emergency drop. Someone planned ahead.",
					"Let's inventory this properly — no guessing what we have left.",
					"Good. Rations for at least a few days if we're smart about it.",
				],
				"monolith": [
					"This wasn't on any survey map. Someone's been here before us.",
					"The positioning is deliberate. It's meant to be found.",
					"I don't like this. Things that old don't just sit here waiting.",
				],
			},
		},
	]

	# Place units just below the crashed ship, spread out horizontally
	var base: Vector2 = grid.crash_site_pos
	if base == Vector2(-1, -1):
		base = Vector2(6, 4)  # fallback if ship didn't place
	var spawn_positions: Array = [
		base + Vector2(1, 5),
		base + Vector2(2, 5),
		base + Vector2(3, 5),
	]

	var unit_scene := preload("res://scenes/Unit.tscn")
	var units_to_setup: Array = [unit]
	unit.position = grid.gridToWorld(spawn_positions[0]) + Vector2(grid.cell_size * 0.5, grid.cell_size)

	for i in 2:
		var u: Unit = unit_scene.instantiate()
		u.position = grid.gridToWorld(spawn_positions[i + 1]) + Vector2(grid.cell_size * 0.5, grid.cell_size)
		$Grid/Units.add_child(u)
		units_to_setup.append(u)

	# Preload engineer walk frames
	var engineer_walk_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the engineer walking animation sideway frames/frame_%04d.png" % i
		engineer_walk_frames.append(load(frame_path) as Texture2D)
	var engineer_walk_up_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the engineer walking animation facing up frames/frame_%04d.png" % i
		engineer_walk_up_frames.append(load(frame_path) as Texture2D)
	var engineer_walk_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the engineer walking animation downward frames/frame_%04d.png" % i
		engineer_walk_down_frames.append(load(frame_path) as Texture2D)

	# Preload pilot walk frames
	var pilot_walk_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the pilot walking animation sideway frames/frame_%04d.png" % i
		pilot_walk_frames.append(load(frame_path) as Texture2D)
	var pilot_walk_up_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the pilot walking animation facing up frames/frame_%04d.png" % i
		pilot_walk_up_frames.append(load(frame_path) as Texture2D)
	var pilot_walk_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the pilot walking animation downward frames/frame_%04d.png" % i
		pilot_walk_down_frames.append(load(frame_path) as Texture2D)

	# Preload medic walk frames
	var medic_walk_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the medic walking animation sideway frames/frame_%04d.png" % i
		medic_walk_frames.append(load(frame_path) as Texture2D)
	var medic_walk_up_frames: Array = []
	for i in range(1, 39):
		var frame_path := "res://art/characters/the medic walking animation facing up frames/frame_%04d.png" % i
		medic_walk_up_frames.append(load(frame_path) as Texture2D)
	var medic_walk_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the medic walking animation downward frames/frame_%04d.png" % i
		medic_walk_down_frames.append(load(frame_path) as Texture2D)

	for i in units_to_setup.size():
		var u: Unit = units_to_setup[i]
		var c: Dictionary = chars[i]
		var down_tex := load(c["down"]) as Texture2D
		var side_tex := load(c["side"]) as Texture2D
		var up_tex   := load(c["up"])   as Texture2D
		u.set_character_textures(down_tex, side_tex, up_tex)
		u.data.name = c["name"]
		u.data.role = c["role"]
		u.data.portrait = down_tex
		u.data.dialog_lines = c["lines"]
		u.data.inspect_lines = c["inspect"]
		if c["name"] == "Raya":
			u.set_walk_frames_side(engineer_walk_frames)
			u.set_walk_frames_up(engineer_walk_up_frames)
			u.set_walk_frames_down(engineer_walk_down_frames)
			u._walk_loop_start_up = 16
			u._walk_loop_start_down = 29
		elif c["name"] == "Mira":
			u.set_walk_frames_side(medic_walk_frames)
			u.set_walk_frames_up(medic_walk_up_frames)
			u.set_walk_frames_down(medic_walk_down_frames)
			u._walk_idle_frame_side = 2
			u._walk_idle_frame_down = 3
			u._walk_loop_start_up = 15
			u._walk_loop_start_down = 10
			u._walk_up_initial_frame = 2
			u.walk_fps_side = 12.0
			u.walk_fps_up = 30.0
		elif c["name"] == "Dax":
			u.set_walk_frames_side(pilot_walk_frames)
			u.set_walk_frames_up(pilot_walk_up_frames)
			u.set_walk_frames_down(pilot_walk_down_frames)
			u._walk_idle_frame_side = 7
			u._walk_idle_frame_down = 16
			u._walk_loop_start_up = 13
			u._walk_loop_start_down = 17
			u.walk_fps_side = 12.0
			u.walk_fps_up = 12.0
			u.walk_fps_down = 12.0
		all_units.append(u)
		u.became_idle.connect(_assign_tasks)
		u.became_idle.connect(func(): _on_unit_idle(u))

	gui.register_units(all_units)

	# Centre camera on the unit group at startup
	var centroid := Vector2.ZERO
	for u in all_units:
		centroid += u.position + Vector2(0, -grid.cell_size * 0.5)
	centroid /= all_units.size()
	$Camera2D.center_on(centroid)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			for u in selected_units:
				u.set_drafted(not u.drafted)
			get_viewport().set_input_as_handled()
			return
	if _inspect_popup and _inspect_popup.visible:
		if event is InputEventMouseButton and event.pressed:
			_inspect_popup.visible = false
			if event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		gui.hide_unit_panel()
	if grid.placement_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = get_viewport().get_mouse_position()
			_dragging = false
		else:
			if _dragging:
				_finish_box_select()
				gui.hide_selection_box()
			else:
				_handle_click()
			_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse := get_viewport().get_mouse_position()
		if not _dragging and _press_pos.distance_to(mouse) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			gui.update_selection_box(_press_pos, mouse)
			get_viewport().set_input_as_handled()


func _handle_click() -> void:
	var grid_pos := grid.worldToGrid(get_global_mouse_position())
	var mouse_screen := get_viewport().get_mouse_position()
	if not grid.grid.has(grid_pos):
		_set_selection([])
		return

	# Clicked on a unit?
	var click_world := get_global_mouse_position()
	for u in all_units:
		var unit_center: Vector2 = u.position + Vector2(0, -grid.cell_size * 0.5)
		if click_world.distance_to(unit_center) < grid.cell_size * 0.55:
			_set_selection([u])
			gui.show_unit_panel(u, mouse_screen)
			return

	# Clicked anywhere else — deselect
	_set_selection([])

	var cell: CellData = grid.grid[grid_pos]
	if cell.occupier == "Tree":
		gui.show_tree_panel(grid.get_tree_root(grid_pos), mouse_screen)
		return

	if cell.occupier == "CrashedShip":
		gui.show_inventory_panel("Crashed Ship", grid.ship_inventory, mouse_screen)
		return

	if cell.occupier == "SupplyCrate":
		var inv: Dictionary = grid.crate_inventories.get(grid_pos, {})
		gui.show_inventory_panel("Supply Crate", inv, mouse_screen)
		return

	if not cell.navigable:
		return


func _finish_box_select() -> void:
	var box := Rect2(_press_pos, get_viewport().get_mouse_position() - _press_pos).abs()
	var canvas_xform := get_viewport().get_canvas_transform()
	var found: Array = []
	for u in all_units:
		var screen_pos: Vector2 = canvas_xform * u.global_position
		if box.has_point(screen_pos):
			found.append(u)
	_set_selection(found)
	if found.size() > 1:
		gui.show_group_panel(found, get_viewport().get_mouse_position())


func _set_selection(units: Array) -> void:
	for u in all_units:
		u.selected = false
	selected_units = units
	for u in selected_units:
		u.selected = true


func _formation(center: Vector2, count: int) -> Array:
	var result: Array = []
	# Spiral outward from center to find enough unique navigable cells.
	for radius in range(0, 6):
		if result.size() >= count:
			break
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if result.size() >= count:
					break
				if abs(dx) != radius and abs(dy) != radius:
					continue  # only the ring at this radius
				var pos := center + Vector2(dx, dy)
				if grid.grid.has(pos) and grid.grid[pos].navigable and not result.has(pos):
					result.append(pos)
	return result


# Returns world-space positions spread around a click point so units don't pile up.
# Slots are arranged in concentric rings; spacing ~60% of a cell.
func _world_formation(center: Vector2, count: int) -> Array:
	if count == 1:
		return [center]
	var spacing := grid.cell_size * 0.6
	var result: Array = [center]
	var ring := 1
	while result.size() < count:
		var slots := int(6 * ring)  # 6 slots per ring layer
		for i in slots:
			if result.size() >= count:
				break
			var angle := (TAU / slots) * i
			var offset := Vector2(cos(angle), sin(angle)) * spacing * ring
			result.append(center + offset)
		ring += 1
	return result


func _on_inspect_requested() -> void:
	if grid.monolith_pos == Vector2(-1, -1):
		return
	# Find closest unit (prefer idle, fall back to any)
	var candidates := all_units.filter(func(u): return not u.drafted and not u.is_busy())
	if candidates.is_empty():
		candidates = all_units.filter(func(u): return not u.drafted)
	if candidates.is_empty():
		return
	var monolith_centre := grid.monolith_pos + Vector2(1, 1)
	var closest: Unit = candidates[0]
	for u in candidates:
		if u.get_grid_pos().distance_to(monolith_centre) < closest.get_grid_pos().distance_to(monolith_centre):
			closest = u
	# Walk to an adjacent free cell next to the monolith
	var dest := Vector2(-1, -1)
	var best_dist := INF
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			if dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1:
				continue
			var c := grid.monolith_pos + Vector2(dx, dy)
			if grid.grid.has(c) and grid.grid[c].navigable:
				var d := closest.get_grid_pos().distance_to(c)
				if d < best_dist:
					best_dist = d
					dest = c
	var monolith_cb := func():
		gui.show_monolith_dialog(get_viewport().get_mouse_position())
	if _is_adjacent_to(closest.get_grid_pos(), grid.monolith_pos, Vector2i(2, 2)):
		monolith_cb.call()
	elif dest != Vector2(-1, -1):
		closest.inspect_move_to(dest, monolith_cb)


func _on_cut_requested(grid_pos: Vector2) -> void:
	pending_tasks.append({"type": "harvest", "pos": grid_pos})
	_assign_tasks()


func _on_blueprint_placed(grid_pos: Vector2, _def: Dictionary) -> void:
	pending_tasks.append({"type": "build", "pos": grid_pos})
	_assign_tasks()


func _assign_tasks() -> void:
	while not pending_tasks.is_empty():
		var idle := all_units.filter(func(u): return not u.drafted and not u.is_busy())
		if idle.is_empty():
			break
		var task: Dictionary = pending_tasks[0]
		var closest: Unit = idle[0]
		for u in idle:
			if u.get_grid_pos().distance_to(task.pos) < closest.get_grid_pos().distance_to(task.pos):
				closest = u
		pending_tasks.remove_at(0)
		match task.type:
			"harvest": closest.queue_harvest(task.pos)
			"build":   closest.queue_build(task.pos)


func _process(delta: float) -> void:
	day_time = fmod(day_time + delta / DAY_DURATION, 1.0)
	var sky := _sky_color_at(day_time)
	canvas_modulate.color = sky
	# Lights fade in as the sky darkens (v is HSV brightness, 0=dark, 1=bright)
	var night_factor := 1.0 - sky.v
	grid.set_tree_light_energy(night_factor * 0.4)
	grid.set_red_tree_light_energy(night_factor * 0.9)
	grid.set_crab_light_energy(night_factor * 0.6)
	grid.set_shadow_opacity(sky.v)


func _on_unit_idle(u: Unit) -> void:
	if u.data.dialog_lines.is_empty():
		return
	var line: String = u.data.dialog_lines[randi() % u.data.dialog_lines.size()]
	u.show_speech(line, true)


func _handle_right_click() -> void:
	var mouse_world := get_global_mouse_position()
	var drafted := all_units.filter(func(u): return u.drafted)

	# Physics query — detection follows collision shapes exactly
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = mouse_world
	pq.collide_with_bodies = true
	pq.collide_with_areas = false
	var hits := get_world_2d().direct_space_state.intersect_point(pq)
	for hit in hits:
		var body = hit.collider
		if not body.has_meta("occupier"):
			continue
		var occ: String = body.get_meta("occupier")
		match occ:
			"Rock", "TidePoolRock":
				if drafted.is_empty(): return
				var rock_grid: Vector2 = body.get_meta("grid_pos")
				var best := _best_unit(drafted, rock_grid)
				var dest := _find_adjacent_to(rock_grid, best)
				if dest == Vector2(-1, -1): return
				var u_ref := best
				_inspect_pending = func():
					u_ref.draft_move_to(grid.gridToWorld(dest) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85))
				_inspect_btn.text = "Mine"
				_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
				_inspect_popup.visible = true
				return
			"CrashedShip", "HullFragment":
				if drafted.is_empty(): return
				_show_inspect_popup(drafted, grid.crash_site_pos, Vector2i(4, 4), "ship")
				return
			"SupplyCrate":
				if drafted.is_empty(): return
				_show_inspect_popup(drafted, body.get_meta("grid_pos"), Vector2i(1, 1), "crate")
				return
			"Monolith":
				if drafted.is_empty(): return
				_show_inspect_popup(drafted, grid.monolith_pos, Vector2i(2, 2), "monolith")
				return

	# No physics hit — move drafted units to navigable ground
	var grid_pos := grid.worldToGrid(mouse_world)
	if not grid.grid.has(grid_pos):
		return
	if grid.grid[grid_pos].navigable:
		var targets := _world_formation(mouse_world, drafted.size())
		for i in drafted.size():
			drafted[i].draft_move_to(targets[i])


func _best_unit(drafted: Array, anchor: Vector2) -> Unit:
	var best: Unit = null
	for u in selected_units:
		if u.drafted:
			best = u
			break
	if best == null:
		best = drafted[0]
		for u in drafted:
			if u.get_grid_pos().distance_to(anchor) < best.get_grid_pos().distance_to(anchor):
				best = u
	return best


func _show_inspect_popup(drafted: Array, anchor: Vector2, anchor_size: Vector2i, inspect_key: String) -> void:
	var best := _best_unit(drafted, anchor)
	var dest := _find_adjacent_to(anchor, best, anchor_size)
	if dest == Vector2(-1, -1):
		return
	var u_ref := best
	var key := inspect_key
	var speech_cb := func():
		if u_ref.data.inspect_lines.has(key):
			var lines: Array = u_ref.data.inspect_lines[key]
			if not lines.is_empty():
				u_ref.show_speech(lines[randi() % lines.size()])
	# If already within 1 tile of the object, skip walking.
	if _is_adjacent_to(best.get_grid_pos(), anchor, anchor_size):
		_inspect_pending = speech_cb
	else:
		_inspect_pending = func():
			u_ref.draft_inspect_to(dest, speech_cb)
	_inspect_btn.text = "Inspect"
	_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
	_inspect_popup.visible = true


func _setup_inspect_popup() -> void:
	_inspect_popup = Panel.new()
	_inspect_popup.visible = false
	_inspect_popup.custom_minimum_size = Vector2(110, 36)
	var btn := Button.new()
	btn.text = "Inspect"
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	btn.pressed.connect(func():
		_inspect_popup.visible = false
		if _inspect_pending.is_valid():
			_inspect_pending.call()
			_inspect_pending = Callable()
	)
	_inspect_popup.add_child(btn)
	_inspect_btn = btn
	$CanvasLayer.add_child(_inspect_popup)
	_setup_debug_button()


func _setup_debug_button() -> void:
	var overlay := _CollisionOverlay.new(grid)
	overlay.z_index = 100
	grid.add_child(overlay)

	var btn := Button.new()
	btn.text = "Show Collision"
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -160
	btn.offset_right = -8
	btn.offset_top = 8
	btn.offset_bottom = 40
	btn.pressed.connect(func():
		overlay.visible = not overlay.visible
		btn.text = "Hide Collision" if overlay.visible else "Show Collision"
	)
	overlay.visible = false
	$CanvasLayer.add_child(btn)

	var nav_overlay := _NavOverlay.new(grid)
	nav_overlay.z_index = 99
	grid.add_child(nav_overlay)

	var nav_btn := Button.new()
	nav_btn.text = "Show Navigable"
	nav_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	nav_btn.offset_left = -160
	nav_btn.offset_right = -8
	nav_btn.offset_top = 48
	nav_btn.offset_bottom = 80
	nav_btn.pressed.connect(func():
		nav_overlay.visible = not nav_overlay.visible
		nav_btn.text = "Hide Navigable" if nav_overlay.visible else "Show Navigable"
	)
	nav_overlay.visible = false
	$CanvasLayer.add_child(nav_btn)


class _CollisionOverlay extends Node2D:
	var _grid: Grid
	func _init(g: Grid) -> void:
		_grid = g
	func _draw() -> void:
		for child in _grid.get_children():
			if not child is StaticBody2D:
				continue
			for shape in child.get_children():
				if not shape is CollisionPolygon2D:
					continue
				var poly: PackedVector2Array = (shape as CollisionPolygon2D).polygon
				if poly.is_empty():
					continue
				var world_poly := PackedVector2Array()
				for pt in poly:
					world_poly.append((child as StaticBody2D).position + pt)
				draw_polyline(world_poly + PackedVector2Array([world_poly[0]]), Color(0, 1, 0, 0.9), 2.0, true)
	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()


class _NavOverlay extends Node2D:
	var _grid: Grid
	func _init(g: Grid) -> void:
		_grid = g
	func _draw() -> void:
		var ns := float(Grid.NAV_CELL_SIZE)
		for nc in _grid.nav_grid:
			if _grid.nav_grid[nc]:
				continue  # skip navigable cells — only draw blocked ones
			draw_rect(Rect2(_grid.navToWorld(nc), Vector2(ns, ns)), Color(1, 0, 0, 0.35))
	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()


func _is_adjacent_to(unit_grid: Vector2, anchor: Vector2, size: Vector2i = Vector2i(1, 1)) -> bool:
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue  # interior
			if unit_grid == anchor + Vector2(dx, dy):
				return true
	return false


func _find_adjacent_to(anchor: Vector2, unit: Unit, size: Vector2i = Vector2i(1, 1)) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	var ref := unit.get_grid_pos()
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue  # skip interior cells
			var c := anchor + Vector2(dx, dy)
			if grid.grid.has(c) and grid.grid[c].navigable:
				var d := ref.distance_to(c)
				if d < best_dist:
					best_dist = d
					best = c
	return best
