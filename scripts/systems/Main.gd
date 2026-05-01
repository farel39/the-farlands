extends Node2D

@onready var grid: Grid = $Grid
@onready var pathfinding: Pathfinder = $Grid/Pathfinding
@onready var unit: Unit = $Units/Unit
@onready var gui = $CanvasLayer/GUI
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var all_units: Array = []
var selected_units: Array = []
# When true, _set_selection auto-drafts every newly selected unit so the
# player doesn't have to click "Draft" or "Draft All" first. Toggled from
# the GUI checkbox above the minimap. Previously drafted units are NOT
# undrafted on selection change — auto-draft is additive, since RTS
# muscle memory expects drafted state to persist independently of the
# current selection rect.
var auto_draft: bool = false
# Per-run stat snapshot, frozen on Victory/Defeat for the summary panel.
# Every gameplay subsystem with an interesting outcome (kills, harvests,
# crafts, downs, revives, choice events) bumps these counters via the
# record_* helpers below — keeps tracking centralized and the summary
# panel a one-stop read.
# Ecosystem-disturbance counter. Every action that takes from / disrupts the
# alien biome bumps this; the wave generator reads it (alongside a base time
# ramp) to decide spawn density + creature variety. Drives the "be careful
# what you do — every action affects the run" rubric: the more you harvest,
# mine, and build, the harder the waves you'll have to defend against.
# Looting already-dead salvage (crates / ship debris) and killing enemies
# don't add threat — they're "free" actions.
var threat_level: float = 0.0
# True once a unit has actually crafted a Comm Relay Module at a Fabricator
# this run. The quest panel uses this (not "is there a module in
# inventory?") so debug shortcuts like Free Mats can't auto-progress the
# objective list. Stays true even after the module is consumed for the
# antenna build, so step 2 of the objective stays checked.
var relay_module_crafted: bool = false
const THREAT_HARVEST: float = 1.0       # tree chop
const THREAT_MINE_ROCK: float = 1.5     # plain rock
const THREAT_MINE_ORE: float = 2.5      # rare metal — more disruptive
const THREAT_BUILD: float = 1.0         # placing a built structure
# Slow background growth so a fully-passive player still sees waves over
# time. Without this, hiding in a corner = no waves ever.
const THREAT_BASELINE_PER_SEC: float = 0.04


var run_stats: Dictionary = {
	"waves_completed": 0,
	"kills":           0,
	"trees_harvested": 0,
	"rocks_mined":     0,
	"items_crafted":   0,
	"buildings_built": 0,
	"downed_count":    0,
	"revived_count":   0,
	"run_time":        0.0,
	"decisions":       [],  # Array of "Event Name → Choice picked" strings
}
var pending_tasks: Array = []

var _fog_mat: ShaderMaterial = null
var _fog_layer: CanvasLayer = null
var _explored_img: Image = null
var _explored_tex: ImageTexture = null
# Cone texture is 256px at texture_scale=7 → reach = 128*7 = 896 world px
const FOG_SIGHT_RADIUS := 860.0  # world px — matches visual cone reach

var _inspect_popup: Panel = null
var _loot_btn: Button = null
var _loot_pending: Callable
var _bright_mode: bool = false
var _visible_cells: Dictionary = {}     # Vector2i → true, current frame's lit cells
var show_creatures: bool = false
var _inspect_btn: Button = null
var _inspect_pending: Callable

const DAY_DURATION := 120.0  # seconds per full day
var day_time: float = 0.5    # start mid-cycle (maps to ~0.71, deep night)

# Color keyframes: [time, color]
const SKY_COLORS: Array = [
	[0.00, Color(0.40, 0.30, 0.60)],  # dawn  - soft purple
	[0.25, Color(0.58, 0.63, 0.75)],  # day   - muted cool blue
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
	var dirt_layer := Node2D.new()
	dirt_layer.name = "DirtLayer"
	add_child(dirt_layer)
	grid.dirt_layer = dirt_layer
	var sprite_layer := Node2D.new()
	sprite_layer.name = "SpriteLayer"
	add_child(sprite_layer)
	grid.sprite_layer = sprite_layer
	grid.spawnTrees()
	grid.spawnDriftwood()
	grid.spawnRocks()
	grid.spawnMonolith()
	grid.spawnCrabs()
	_setup_entity_visibility()
	pathfinding.initialize()
	gui.cut_requested.connect(_on_cut_requested)
	gui.inspect_requested.connect(_on_inspect_requested)
	grid.blueprint_placed.connect(_on_blueprint_placed)
	$Units.z_index = 1
	_spawn_units()
	_setup_inspect_popup()
	_setup_fog()
	_explore_crash_site()
	_setup_ambient_light()
	_setup_wave_manager()
	_setup_harvest_highlight()
	# Apply any save-data queued by the menu (Pause → Load, Main Menu →
	# Continue, etc.). Runs AFTER all systems are wired so apply_run_data
	# can talk to the wave_manager / grid / units freely. No-op when
	# queued_load_slot is the sentinel -1 (fresh run).
	_apply_pending_load()


# World-space overlay that pulses outlines on harvestable / mineable objects
# while the player is in Harvest or Mine command mode. Visibility-gated so it
# only marks what the units can currently see.
const _HARVEST_HIGHLIGHT_SCRIPT := preload("res://scripts/ui/HarvestHighlight.gd")
var _harvest_highlight: Node2D = null

func _setup_harvest_highlight() -> void:
	_harvest_highlight = Node2D.new()
	_harvest_highlight.set_script(_HARVEST_HIGHLIGHT_SCRIPT)
	add_child(_harvest_highlight)
	_harvest_highlight.call("setup", grid, self, gui)


const WAVE_MANAGER_SCRIPT := preload("res://scripts/systems/WaveManager.gd")
const EVENT_MANAGER_SCRIPT := preload("res://scripts/systems/EventManager.gd")
var wave_manager: Node = null
var event_manager: Node = null

func _setup_wave_manager() -> void:
	wave_manager = WAVE_MANAGER_SCRIPT.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	# Hook the GUI to wave events.
	wave_manager.banner_message.connect(gui.show_wave_banner)
	wave_manager.state_changed.connect(gui.on_wave_state_changed)
	# WaveManager loads creature textures on demand from CreatureDefs based on
	# the per-wave roster, so only the scene needs to be passed here.
	var crab_scene := load("res://scenes/Crab.tscn") as PackedScene
	wave_manager.start(grid, self, crab_scene)
	# Random-event director — sits on top of the wave loop, fires events
	# during peace + evac. Uses the same crab scene + creature def lookups
	# as WaveManager for consistency.
	event_manager = EVENT_MANAGER_SCRIPT.new()
	event_manager.name = "EventManager"
	add_child(event_manager)
	if event_manager.has_signal("event_announced"):
		event_manager.event_announced.connect(gui.show_event_banner)
	event_manager.start(grid, self, wave_manager, crab_scene)


func _setup_ambient_light() -> void:
	# Forces ALL TileMap quadrants into "lit mode" permanently so that when
	# PointLight2D nodes (tree lights, unit flashlight) appear, there is no
	# visible rectangle boundary between lit and unlit quadrants.
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 8
	tex.height = 8
	var ambient := PointLight2D.new()
	ambient.texture = tex
	ambient.energy = 0.001
	ambient.texture_scale = float(grid.width * grid.cell_size) / 4.0
	ambient.position = Vector2(grid.width, grid.height) * grid.cell_size * 0.5
	add_child(ambient)


func _setup_fog() -> void:
	_fog_layer = CanvasLayer.new()
	_fog_layer.layer = 2
	add_child(_fog_layer)
	var fog_layer := _fog_layer
	var fog_rect := ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://art/shaders/fog_of_war.gdshader")
	fog_rect.material = _fog_mat
	fog_layer.add_child(fog_rect)
	# Exploration texture: one pixel per grid cell, R=1 means explored
	_explored_img = Image.create(grid.width, grid.height, false, Image.FORMAT_R8)
	_explored_tex = ImageTexture.create_from_image(_explored_img)
	_fog_mat.set_shader_parameter("explored_tex", _explored_tex)
	_fog_mat.set_shader_parameter("world_size",
		Vector2(grid.width * grid.cell_size, grid.height * grid.cell_size))

func _setup_entity_visibility() -> void:
	for crab in grid.crabs:
		var sprite: Sprite2D = crab.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
		for child in crab.get_children():
			if child is PointLight2D:
				child.visible = false
				break


func _update_entity_visibility() -> void:
	var cs := float(grid.cell_size)
	for crab in grid.crabs:
		if not is_instance_valid(crab):
			continue
		var cell := Vector2i(int(crab.global_position.x / cs), int(crab.global_position.y / cs))
		var visible: bool = show_creatures or _visible_cells.has(cell)
		var sprite: Sprite2D = crab.get_node_or_null("Sprite2D")
		var crab_light: PointLight2D = null
		for child in crab.get_children():
			if child is PointLight2D:
				crab_light = child
				break
		if sprite:
			sprite.visible = visible
		if crab_light:
			crab_light.visible = visible


func _explore_crash_site() -> void:
	if grid.crash_site_pos == Vector2(-1, -1):
		return
	const SHIP_TILES := 4
	var sx := int(grid.crash_site_pos.x)
	var sy := int(grid.crash_site_pos.y)
	for cx in range(sx - 1, sx + SHIP_TILES + 1):
		for cy in range(sy - 1, sy + SHIP_TILES + 1):
			if cx < 0 or cx >= grid.width or cy < 0 or cy >= grid.height:
				continue
			_explored_img.set_pixel(cx, cy, Color.WHITE)
	_explored_tex.update(_explored_img)

func _update_fog() -> void:
	if _fog_mat == null:
		return
	var canvas_tf := get_viewport().get_canvas_transform()
	var vp_size := get_viewport().get_visible_rect().size
	var cs := float(grid.cell_size)
	var explored_dirty := false
	const CONE_HALF_ANGLE := 0.663
	var sight_cells := int(FOG_SIGHT_RADIUS / cs) + 1
	_visible_cells.clear()
	for u in all_units:
		var gx := int(u.global_position.x / cs)
		var gy := int(u.global_position.y / cs)
		for dx in range(-sight_cells, sight_cells + 1):
			for dy in range(-sight_cells, sight_cells + 1):
				var cx := gx + dx
				var cy := gy + dy
				if cx < 0 or cx >= grid.width or cy < 0 or cy >= grid.height:
					continue
				# 1-tile ambient area around the character (grid coords)
				var in_circle: bool = abs(dx) <= 1 and abs(dy) <= 1
				var in_cone := false
				if not in_circle:
					var x0 := float(cx) * cs
					var y0 := float(cy) * cs
					# Check center + 4 corners so edge cells aren't missed
					var samples: Array = [
						Vector2(x0 + 0.5 * cs, y0 + 0.5 * cs),
						Vector2(x0,        y0),
						Vector2(x0 + cs,   y0),
						Vector2(x0,        y0 + cs),
						Vector2(x0 + cs,   y0 + cs),
					]
					for pt: Vector2 in samples:
						if in_cone:
							break
						var dist := pt.distance_to(u.global_position)
						if dist <= FOG_SIGHT_RADIUS and dist > 0.0:
							var to_cell: Vector2 = (pt - u.global_position) / dist
							var angle := acos(clamp(to_cell.dot(u.sight_dir), -1.0, 1.0))
							if angle <= CONE_HALF_ANGLE:
								in_cone = true
				if in_circle or in_cone:
					_visible_cells[Vector2i(cx, cy)] = true
					if _explored_img.get_pixel(cx, cy).r < 0.5:
						_explored_img.set_pixel(cx, cy, Color.WHITE)
						explored_dirty = true
	# Player-built light sources (campfires, floodlights) also illuminate
	# their surrounding cells — same fog-of-war behavior as a unit standing
	# there with their flashlight on. Combined with Unit._can_see's matching
	# check, this means enemies wandering into the lit perimeter become
	# both visible on the map AND auto-engaged in Defend stance.
	for entry in grid.get_building_lights():
		var lp: Vector2 = entry.world_pos
		var lr: float = float(entry.radius)
		var lr_cells: int = int(lr / cs) + 1
		var lcx: int = int(lp.x / cs)
		var lcy: int = int(lp.y / cs)
		for ldx in range(-lr_cells, lr_cells + 1):
			for ldy in range(-lr_cells, lr_cells + 1):
				var lcell_x: int = lcx + ldx
				var lcell_y: int = lcy + ldy
				if lcell_x < 0 or lcell_x >= grid.width or lcell_y < 0 or lcell_y >= grid.height:
					continue
				var pt := Vector2(float(lcell_x) * cs + cs * 0.5, float(lcell_y) * cs + cs * 0.5)
				if pt.distance_to(lp) > lr:
					continue
				_visible_cells[Vector2i(lcell_x, lcell_y)] = true
				if _explored_img.get_pixel(lcell_x, lcell_y).r < 0.5:
					_explored_img.set_pixel(lcell_x, lcell_y, Color.WHITE)
					explored_dirty = true
	if explored_dirty:
		_explored_tex.update(_explored_img)
	var tf_inv := canvas_tf.affine_inverse()
	_fog_mat.set_shader_parameter("viewport_size", vp_size)
	_fog_mat.set_shader_parameter("itf_origin", tf_inv.origin)
	_fog_mat.set_shader_parameter("itf_x", tf_inv.x)
	_fog_mat.set_shader_parameter("itf_y", tf_inv.y)


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
			"downed": "res://art/characters/the engineer downed.png",
			"name": "Dax",
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
			"downed": "res://art/characters/the medic downed.png",
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
			"downed": "res://art/characters/the pilot downed.png",
			"name": "Raya",
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
		$Units.add_child(u)
		units_to_setup.append(u)

	# Preload engineer attack frames
	var engineer_attack_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the engineer attacking animation sideway frames/frame_%04d.png" % i
		engineer_attack_frames.append(load(frame_path) as Texture2D)
	var engineer_attack_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the engineer attacking animation downward frames/frame_%04d.png" % i
		engineer_attack_down_frames.append(load(frame_path) as Texture2D)
	var engineer_attack_up_frames: Array = []
	for i in range(1, 31):
		var frame_path := "res://art/characters/the engineer attacking animation facing up frames/frame_%03d.png" % i
		engineer_attack_up_frames.append(load(frame_path) as Texture2D)

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
	for i in range(1, 32):
		var frame_path := "res://art/characters/the engineer walking animation downward frames/frame_%03d.png" % i
		if ResourceLoader.exists(frame_path):
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

	# Preload medic attack frames (pistol)
	var medic_attack_side_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the medic attacking animation sideway frames/frame_%04d.png" % i
		medic_attack_side_frames.append(load(frame_path) as Texture2D)
	var medic_attack_up_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the medic attacking animation facing up frames/frame_%03d.png" % i
		medic_attack_up_frames.append(load(frame_path) as Texture2D)
	var medic_attack_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the medic attacking animation downward frames/frame_%03d.png" % i
		if ResourceLoader.exists(frame_path):
			medic_attack_down_frames.append(load(frame_path) as Texture2D)

	# Preload pilot attack frames (pistol)
	var pilot_attack_side_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the pilot attacking animation sideway frames/frame_%04d.png" % i
		pilot_attack_side_frames.append(load(frame_path) as Texture2D)
	var pilot_attack_up_frames: Array = []
	for i in range(1, 31):
		var frame_path := "res://art/characters/the pilot attacking animation facing up frames/frame_%03d.png" % i
		pilot_attack_up_frames.append(load(frame_path) as Texture2D)
	var pilot_attack_down_frames: Array = []
	for i in range(1, 49):
		var frame_path := "res://art/characters/the pilot attacking animation downward frames/frame_%03d.png" % i
		if ResourceLoader.exists(frame_path):
			pilot_attack_down_frames.append(load(frame_path) as Texture2D)

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
		if c.has("downed"):
			u.set_downed_texture(load(c["downed"]) as Texture2D)
		u.data.name = c["name"]
		u.data.role = c["role"]
		u.data.portrait = down_tex
		u.data.dialog_lines = c["lines"]
		u.data.inspect_lines = c["inspect"]
		# One injector per survivor at start — enough for one revive each before
		# the team needs to find / craft more. Crashed-ship loot can pad this.
		u.data.inventory["Revival Injector"] = int(u.data.inventory.get("Revival Injector", 0)) + 1
		if c["name"] == "Dax":
			# Walk-down source frames are 480x848 — bigger than the cell. This
			# offset makes the sprite render taller than cell_size so the body
			# matches the attack-down silhouette instead of looking shrunken.
			# Must be set BEFORE set_walk_frames_down (which applies the idle frame).
			u.walk_down_top_offset = 200
			u.walk_down_y_nudge = 60   # shift sprite down so feet sit on tile
			u.walk_fps_down = 16.0     # slower stride than the side/up walk loops
			# Idle facing-down pose = the FIRST frame of the walk-down animation
			# (index 0 → frame_001.png). Default is already 0; setting it
			# explicitly keeps the intent obvious if the default ever changes.
			u._walk_idle_frame_down = 0
			u._walk_down_initial_frame = 0
			u.set_walk_frames_side(engineer_walk_frames)
			u.set_walk_frames_up(engineer_walk_up_frames)
			u.set_walk_frames_down(engineer_walk_down_frames)
			u.set_attack_frames_side(engineer_attack_frames)
			u.set_attack_frames_down(engineer_attack_down_frames)
			u.set_attack_frames_up(engineer_attack_up_frames)
			u._walk_loop_start_up = 16
			u._walk_loop_start_down = 22
			# Force-apply the idle frame at the very end of the engineer's
			# setup so nothing earlier (set_character_textures' default
			# tex_down apply, etc.) leaves a stale sprite on screen.
			if not engineer_walk_down_frames.is_empty():
				u._apply_sprite_walk_down(engineer_walk_down_frames[0])
		elif c["name"] == "Mira":
			# Medic auto-heals by default — players can toggle off in the
			# char-inventory or by setting heal priority OFF in the Work tab.
			u.auto_heal_enabled = true
			u.set_walk_frames_side(medic_walk_frames)
			u.set_walk_frames_up(medic_walk_up_frames)
			u.set_walk_frames_down(medic_walk_down_frames)
			u.set_attack_frames_side(medic_attack_side_frames)
			u.set_attack_frames_up(medic_attack_up_frames)
			u.set_attack_frames_down(medic_attack_down_frames)
			u.idle_side_tex = medic_attack_side_frames[0]
			u._walk_idle_frame_side = 2
			u._walk_idle_frame_down = 3
			u._walk_loop_start_up = 15
			u._walk_loop_start_down = 10
			u._walk_up_initial_frame = 2
			u.walk_fps_side = 12.0
			u.walk_fps_up = 30.0
			# Pistol attack tuning (side/up sprites are 720x1280)
			u.attack_side_px_per_cell = 1280
			u.attack_side_feet_y = 1264   # walk-side feet sit ~4% above tile bottom
			u.attack_side_x_nudge = 50    # source-px forward (pistol pose leans into the shot)
			u.attack_up_px_per_cell = 1280
			u.attack_up_feet_y = 1278
			# Down-attack frames are 480x848; walk-down is 480x688. Setting the
			# offset to 848-688 = 160 makes both directions use the same scale
			# factor, so the medic body renders at identical size whether
			# attacking or walking down. Total sprite height = 1.23 cells (the
			# extra 0.23 cells is the gun pose extending above the body).
			u.attack_down_top_offset = 160
			# Medic's shooting-down pose sits a touch high on the canvas; nudge
			# the rendered sprite down so feet land on the tile cleanly.
			u.attack_down_y_nudge = 50
			# Combat stats — pistol (ranged). Nerfed from prior values
			# (6 dmg / 1.0s / 5 tiles / 8 aggro) since ranged stacking on
			# two characters trivialized waves. Still useful for softening
			# crabs as they close, just not auto-deletes them.
			u.data.attack_damage = 5
			u.data.attack_range_tiles = 4.0
			u.data.attack_cooldown = 1.4
			u.data.aggro_range_tiles = 6.0
			u.data.attack_hit_ratio = 0.3
			# Chained shots skip the holster→draw intro frames
			u.attack_chain_start_side = 24
			u.attack_chain_start_up = 6
			u.attack_chain_start_down = 10
		elif c["name"] == "Raya":
			u.set_walk_frames_side(pilot_walk_frames)
			u.set_walk_frames_up(pilot_walk_up_frames)
			u.set_walk_frames_down(pilot_walk_down_frames)
			u.set_attack_frames_side(pilot_attack_side_frames)
			u.set_attack_frames_up(pilot_attack_up_frames)
			u.set_attack_frames_down(pilot_attack_down_frames)
			# Side-idle pose = the first frame of the side attack animation
			# (gun holstered / at-ease). Without this, the post-attack idle
			# fell back to a walk-side frame that still shows her aiming, so
			# she'd freeze in firing pose after killing the last enemy.
			# Same trick the medic uses.
			u.idle_side_tex = pilot_attack_side_frames[0]
			# Pilot attack-down sprite is 720x1280; walk-down is 480x773. To match
			# body sizes (so the pilot doesn't suddenly shrink when firing down),
			# offset = 1280 - 773 = 507 worth of "above the cell" — but since the
			# actual body fills more than 773 source-px of attack-down, use a
			# smaller offset (~120) that lines up the visible body height.
			u.attack_down_top_offset = 120
			u._walk_idle_frame_side = 7
			u._walk_idle_frame_down = 16
			u._walk_loop_start_up = 13
			u._walk_loop_start_down = 17
			u.walk_fps_side = 12.0
			u.walk_fps_up = 12.0
			u.walk_fps_down = 12.0
			# Pistol attack tuning (sprites are 720x1280; walk-up tex is 720x1180)
			u.attack_side_px_per_cell = 1230   # smaller = bigger sprite (~4% larger than walk-side scale)
			u.attack_side_feet_y = 1295        # adjusted so feet still match walk-side after the scale change
			u.attack_side_x_nudge = 106        # source-px forward (matches walk-side body x-center)
			u.attack_up_px_per_cell = 1180
			u.attack_up_feet_y = 1229
			# Combat stats — pistol (ranged). Same nerf as Mira so the team's
			# two ranged characters can't trivialize waves by stacking.
			u.data.attack_damage = 5
			u.data.attack_range_tiles = 4.0
			u.data.attack_cooldown = 1.4
			u.data.aggro_range_tiles = 6.0
			u.data.attack_hit_ratio = 0.3
			# Chained shots skip the holster→draw intro frames
			u.attack_chain_start_side = 16
			u.attack_chain_start_up = 6
			u.attack_chain_start_down = 16

		# Role-based default priorities so the game has sensible behavior on
		# first run. Players can re-tune each cell from the Work panel.
		match c.get("role", ""):
			"Engineer":
				u.data.work_priorities = {
					"combat":  UnitData.Priority.MED,
					"heal":    UnitData.Priority.LOW,
					"repair":  UnitData.Priority.HIGH,
					"build":   UnitData.Priority.HIGH,
					"harvest": UnitData.Priority.HIGH,
					"mine":    UnitData.Priority.HIGH,
					"gather":  UnitData.Priority.MED,
				}
			"Medic":
				u.data.work_priorities = {
					"combat":  UnitData.Priority.MED,
					"heal":    UnitData.Priority.HIGH,
					"repair":  UnitData.Priority.MED,
					"build":   UnitData.Priority.MED,
					"harvest": UnitData.Priority.LOW,
					"mine":    UnitData.Priority.LOW,
					"gather":  UnitData.Priority.HIGH,
				}
			"Pilot":
				u.data.work_priorities = {
					"combat":  UnitData.Priority.HIGH,
					"heal":    UnitData.Priority.LOW,
					"repair":  UnitData.Priority.MED,
					"build":   UnitData.Priority.MED,
					"harvest": UnitData.Priority.MED,
					"mine":    UnitData.Priority.MED,
					"gather":  UnitData.Priority.HIGH,
				}
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


var _pause_menu: Node = null

func _open_pause_menu() -> void:
	if _pause_menu and is_instance_valid(_pause_menu):
		return
	_pause_menu = load("res://scenes/PauseMenu.tscn").instantiate()
	# Add to the existing CanvasLayer so it sits above the in-game GUI.
	$CanvasLayer.add_child(_pause_menu)
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Don't grab Esc while a placement/blueprint mode is active — Grid handles that.
			if grid.placement_mode or grid.blueprint_mode:
				return
			_open_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_A:
			if selected_units.size() == 1 and (selected_units[0] as Unit).drafted:
				(selected_units[0] as Unit).trigger_attack()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			for u in selected_units:
				# Skip downed teammates — they need to be revived before
				# they can take orders again.
				if u.is_downed:
					continue
				u.set_drafted(not u.drafted)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F:
			_fog_layer.visible = not _fog_layer.visible
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
	# Command-mode hijack: while an order is active, left-click dispatches the
	# order to the clicked target and right-click exits the mode entirely.
	# This must run before the regular click handlers so selection / move
	# commands don't fire underneath.
	if gui.command_mode != "":
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				gui.exit_command_mode()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_handle_command_click(gui.command_mode)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		gui.hide_unit_panel()
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
	# Shift-click extends or toggles the existing selection instead of
	# replacing it. Held-shift on empty terrain also leaves the selection
	# alone — accidentally missing a click shouldn't dump your multi-select.
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	if not grid.grid.has(grid_pos):
		if not shift_held:
			_set_selection([])
		return

	# Clicked on a unit?
	var click_world := get_global_mouse_position()
	for u in all_units:
		var unit_center: Vector2 = u.position + Vector2(0, -grid.cell_size * 0.5)
		if click_world.distance_to(unit_center) < grid.cell_size * 0.55:
			if shift_held:
				var current: Array = selected_units.duplicate()
				if current.has(u):
					current.erase(u)
				else:
					current.append(u)
				_set_selection(current)
				# Don't pop the unit panel during multi-select buildup —
				# panel is for inspecting a single unit, which conflicts
				# with the "growing the selection" intent.
			else:
				_set_selection([u])
				gui.show_unit_panel(u, mouse_screen)
			return

	# Clicked empty terrain — clear selection (unless shift held, see above).
	if not shift_held:
		_set_selection([])

	var cell: CellData = grid.grid[grid_pos]
	if cell.occupier == "Tree":
		gui.show_tree_panel(grid.get_tree_root(grid_pos), mouse_screen)
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
	# Shift-drag adds to the existing selection instead of replacing — same
	# semantics as shift-click on a portrait or world unit. Plain drag still
	# replaces, even if the box is empty (so an intentional miss clears).
	if Input.is_key_pressed(KEY_SHIFT):
		var combined: Array = selected_units.duplicate()
		for u in found:
			if not combined.has(u):
				combined.append(u)
		_set_selection(combined)
		if combined.size() > 1:
			gui.show_group_panel(combined, get_viewport().get_mouse_position())
	else:
		_set_selection(found)
		if found.size() > 1:
			gui.show_group_panel(found, get_viewport().get_mouse_position())


func _set_selection(units: Array) -> void:
	for u in all_units:
		u.selected = false
	selected_units = units
	for u in selected_units:
		u.selected = true
	# Auto-draft hook — when the player has the toggle on (checkbox
	# above the minimap), the drafted set follows the selection set
	# Dota-style: anyone selected becomes drafted, anyone NOT selected
	# becomes undrafted. set_drafted is called only when state actually
	# changes so we don't restart pathing on units that were already in
	# the right state.
	if auto_draft:
		var sel_lookup: Dictionary = {}
		for s in selected_units:
			sel_lookup[s] = true
		for u in all_units:
			if not is_instance_valid(u):
				continue
			if not u.has_method("set_drafted"):
				continue
			var should_be_drafted: bool = sel_lookup.has(u)
			if should_be_drafted and not u.drafted:
				u.set_drafted(true)
			elif not should_be_drafted and u.drafted:
				u.set_drafted(false)


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
	# Mark the tree's root so the harvest indicator pins to the same anchor
	# the worker will actually walk to.
	var root: Vector2 = grid.get_tree_root(grid_pos)
	pending_tasks.append({"type": "harvest", "pos": root})
	grid.set_task_marker(root, "harvest")
	_assign_tasks()


# ── Run stat recording helpers ─────────────────────────────────────────────
# Called from gameplay subsystems whenever something stat-worthy happens.
# Centralized so the summary panel reads a single dict and so future
# additions (achievements, etc.) only need one hook.
func record_kill() -> void:
	run_stats.kills += 1


func record_tree_harvested() -> void:
	run_stats.trees_harvested += 1
	threat_level += THREAT_HARVEST


# Called when a single rock is mined (Stone-yielding rock from world spawn).
func record_rock_mined() -> void:
	run_stats.rocks_mined += 1
	threat_level += THREAT_MINE_ROCK


# Called when an Ore deposit is mined — heavier disturbance than a regular
# rock, mirroring the "rare metals attract attention" theme.
func record_ore_mined() -> void:
	run_stats.rocks_mined += 1
	threat_level += THREAT_MINE_ORE


func record_item_crafted() -> void:
	run_stats.items_crafted += 1


func record_building_built() -> void:
	run_stats.buildings_built += 1
	threat_level += THREAT_BUILD


func record_downed() -> void:
	run_stats.downed_count += 1


func record_revived() -> void:
	run_stats.revived_count += 1


func record_wave_completed() -> void:
	run_stats.waves_completed += 1


# Logged decisions render as a short bullet list on the summary panel so the
# player can see the choices that shaped this run.
func record_decision(event_name: String, choice: String) -> void:
	run_stats.decisions.append("%s → %s" % [event_name, choice])


# Returns { item_name: deficit } for a blueprint — what the team still needs
# before construction can start. Empty dict means the build can dispatch right
# now (paid blueprint or all costs covered). Powers both _can_build_now and
# the GUI shortage toast on a manual Build click.
func _missing_materials_for(bp_pos: Vector2) -> Dictionary:
	if not grid.blueprints.has(bp_pos):
		return {}
	var bp: Dictionary = grid.blueprints[bp_pos]
	if bp.has("spent_cost"):
		return {}
	var cost: Dictionary = bp.def.cost
	var missing: Dictionary = {}
	for item in cost:
		var team_total: int = 0
		for u in all_units:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.is_dead() or unit_node.is_downed:
				continue
			team_total += int(unit_node.data.inventory.get(item, 0))
		var deficit: int = int(cost[item]) - team_total
		if deficit > 0:
			missing[item] = deficit
	return missing


# True iff a build task at `bp_pos` is dispatchable right now: blueprint exists,
# and either it's already paid (mid-build handoff) or the team's combined
# inventory covers every cost item. Used by _assign_tasks to defer builds the
# team can't afford yet.
# Cancel any queued / active task whose target sits on or under `click_cell`.
# Resolves the click into every possible anchor (tree root, building anchor,
# rock / ore / driftwood single cell, downed unit at the world position) so
# the player can click anywhere on a marked object — including canopy, wall
# footprints, or downed bodies — and the cancel hits.
#
# Effects:
#   • Removes matching pending_tasks entries
#   • Tells any unit currently working on the target to stop
#   • Clears the visual task marker on the anchor
#   • Wipes saved harvest / mine progress so the next worker doesn't resume
func _cancel_tasks_at_cell(click_cell: Vector2, mouse_world: Vector2) -> void:
	var anchors: Dictionary = {}  # set of anchor cells touched

	# Tree root (3x3 footprint).
	if grid.tree_root.has(click_cell):
		anchors[grid.get_tree_root(click_cell)] = true
	# Building anchor (walls / fabricator / lighting / blueprints).
	if grid.cell_to_building.has(click_cell):
		anchors[grid.cell_to_building[click_cell]] = true
	# Blueprint anchor (cell-mask aware).
	var bp_anchor: Vector2 = grid.blueprint_at_cell(click_cell)
	if bp_anchor != Vector2(-1, -1):
		anchors[bp_anchor] = true
	# Single-cell harvestables.
	if grid.grid.has(click_cell):
		var occ: Variant = grid.grid[click_cell].occupier
		if occ == "Rock" or occ == "Ore" or occ == "Driftwood":
			anchors[click_cell] = true
	# Downed unit at the click — cancels a queued revive.
	var downed: Unit = _downed_unit_at_world(mouse_world)
	if downed != null:
		anchors[downed.get_grid_pos()] = true

	if anchors.is_empty():
		return

	# Drop matching entries from pending_tasks.
	pending_tasks = pending_tasks.filter(func(t):
		# Build/repair/demolish/harvest/mine all key by anchor in `pos`.
		if anchors.has(t.pos):
			return false
		# Revive task carries a target_unit reference — match its grid pos.
		if t.type == "revive":
			var rt = t.get("target_unit")
			if rt != null and is_instance_valid(rt) and anchors.has(rt.get_grid_pos()):
				return false
		return true
	)

	# Abort any unit currently mid-task on a matching target.
	for u in all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if anchors.has(unit_node.harvest_target):
			grid.tree_harvest_progress.erase(unit_node.harvest_target)
			grid.hide_harvest_bar(unit_node.harvest_target)
			unit_node.harvest_target = Vector2(-1, -1)
			unit_node._harvest_timer = -1.0
			unit_node._stop_work_loop()
			unit_node.path.clear()
		if anchors.has(unit_node.mine_target):
			grid.rock_mine_progress.erase(unit_node.mine_target)
			grid.hide_mine_bar(unit_node.mine_target)
			unit_node.mine_target = Vector2(-1, -1)
			unit_node._mine_timer = -1.0
			unit_node._stop_work_loop()
			unit_node.path.clear()
		if anchors.has(unit_node.repair_target):
			unit_node.repair_target = Vector2(-1, -1)
			unit_node._repair_timer = -1.0
			unit_node.path.clear()
		if anchors.has(unit_node.demolish_target):
			unit_node.demolish_target = Vector2(-1, -1)
			unit_node._demolish_timer = -1.0
			unit_node.path.clear()
		if anchors.has(unit_node.build_target):
			# Cancel mode releases the worker but leaves the blueprint
			# standing — Cancel is a "stop working on this" order, not a
			# "tear it down" order. To tear down + refund, use right-
			# click on the blueprint (or the Demolish order, which is
			# the destructive variant). Already-spent cost stays banked
			# in the blueprint's spent_cost dict, so the next build
			# attempt skips re-deducting materials.
			unit_node.build_target = Vector2(-1, -1)
			unit_node._build_timer = -1.0
			unit_node._stop_work_loop()
			unit_node.path.clear()
		if unit_node.revive_target != null and is_instance_valid(unit_node.revive_target):
			if anchors.has(unit_node.revive_target.get_grid_pos()):
				unit_node.revive_target = null
				unit_node.path.clear()

	# Clear visual markers on every touched anchor.
	for a in anchors.keys():
		grid.clear_task_marker(a)


func _can_build_now(bp_pos: Vector2) -> bool:
	if not grid.blueprints.has(bp_pos):
		return false
	return _missing_materials_for(bp_pos).is_empty()


# Public hook: anything that grows the team's inventory (harvest, mine, loot
# drop, refund) calls this so deferred build tasks get a fresh look. Cheap
# enough to call freely — _assign_tasks short-circuits when nothing changed.
func notify_inventory_changed() -> void:
	_assign_tasks()
	# Refresh open UI panels that display per-item have/need counts (Construct
	# catalog, Fabricator craft list) so the readouts stay live as material
	# pools shift in the background.
	if gui != null and gui.has_method("on_inventory_changed"):
		gui.on_inventory_changed()


# Floating world-space message at `world_pos`. Reuses the LootToast
# component (no icon, custom color) so right-click feedback messages
# anchor to the clicked object instead of the top-of-screen banner.
# Used for regrowing-tree warnings and similar one-off prompts.
const _LOOT_TOAST_SCRIPT: Script = preload("res://scripts/ui/LootToast.gd")
func _spawn_world_toast(world_pos: Vector2, text: String, color: Color = Color(1.0, 0.95, 0.55)) -> void:
	var t := Node2D.new()
	t.set_script(_LOOT_TOAST_SCRIPT)
	add_child(t)
	t.position = world_pos
	t.setup(null, text, color)


# ── Save / Load ──────────────────────────────────────────────────────────────
#
# Snapshot the current run into a Dictionary that JSON.stringify can flatten.
# Pause Menu → Save calls this and forwards the result to
# SaveManager.write_run_data. The matching apply_run_data restores from the
# same shape.
#
# Scope (kept tight on purpose): unit state, run-level counters, completed
# buildings, fabricator queues, comm-relay channel progress. Procedural
# world (trees, rocks, ambient creatures) and live-wave state are NOT
# saved — they regenerate fresh on load. Wave state always resumes in
# PEACE so we don't have to serialise mid-wave spawn queues.
func serialize_run() -> Dictionary:
	var d: Dictionary = {}
	d["main"] = {
		"threat_level": float(threat_level),
		"relay_module_crafted": bool(relay_module_crafted),
		"day_time": float(day_time),
		"run_stats": run_stats.duplicate(true),
	}
	d["wave"] = {
		"wave_num": int(wave_manager.wave_num) if wave_manager != null and "wave_num" in wave_manager else 0,
	}
	# Units — save by name so apply_run_data can match against the
	# fixed Dax/Mira/Raya roster regardless of array order.
	var units_arr: Array = []
	for u in all_units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		units_arr.append({
			"name": String(unit.data.name),
			"pos_x": unit.position.x,
			"pos_y": unit.position.y,
			"health": float(unit.data.health),
			"max_health": float(unit.data.max_health),
			"attack_damage": int(unit.data.attack_damage),
			"attack_range_tiles": float(unit.data.attack_range_tiles),
			"attack_cooldown": float(unit.data.attack_cooldown),
			"speed": float(unit.data.speed),
			"drafted": bool(unit.drafted),
			"is_downed": bool(unit.is_downed),
			"evacuated": bool(unit.evacuated),
			"auto_heal_enabled": bool(unit.auto_heal_enabled),
			"inventory": unit.data.inventory.duplicate(true),
			"equipped": unit.data.equipped.duplicate(true),
			"work_priorities": unit.data.work_priorities.duplicate(true),
		})
	d["units"] = units_arr
	# Buildings, fabricators, comm relays — keyed by anchor cell coords.
	# Skipping in-flight blueprints in this MVP.
	var bld_arr: Array = []
	for anchor in grid.buildings.keys():
		var b: Dictionary = grid.buildings[anchor]
		var key: String = _building_def_key(b.def)
		if key == "":
			continue
		var apos: Vector2 = anchor
		bld_arr.append({
			"x": int(apos.x), "y": int(apos.y),
			"def_key": key,
			"hp": int(b.hp),
		})
	d["buildings"] = bld_arr
	var fab_arr: Array = []
	for anchor in grid.fabricators.keys():
		# Only persist fabricators whose anchor still maps to a real
		# building — skipping any orphaned entries.
		if not grid.buildings.has(anchor):
			continue
		var fab: Dictionary = grid.fabricators[anchor]
		var apos: Vector2 = anchor
		fab_arr.append({
			"x": int(apos.x), "y": int(apos.y),
			"queue": (fab.get("queue", []) as Array).duplicate(true),
			"progress": float(fab.get("progress", 0.0)),
		})
	d["fabricators"] = fab_arr
	var relay_arr: Array = []
	for anchor in grid.comm_relays.keys():
		if not grid.buildings.has(anchor):
			continue
		var relay: Dictionary = grid.comm_relays[anchor]
		var apos: Vector2 = anchor
		relay_arr.append({
			"x": int(apos.x), "y": int(apos.y),
			"progress": float(relay.get("progress", 0.0)),
			"completed": bool(relay.get("completed", false)),
		})
	d["comm_relays"] = relay_arr
	return d


# Reverse-lookup the BuildingDefs key for a def Dictionary (matches by
# identity since the def reference is the same object). Returns empty
# string for unknown defs so callers can skip safely.
func _building_def_key(def: Dictionary) -> String:
	for k in BuildingDefs.DEFS:
		if BuildingDefs.DEFS[k] == def:
			return k
	return ""


# Inverse of serialize_run — overwrites the freshly-spawned scene state
# with whatever was on disk. Order matters:
#   1. Run counters (threat, day_time, run_stats, relay_flag) so any
#      tick that fires later this frame sees the right values.
#   2. Units — find by name and overwrite. The chars roster in
#      _spawn_units is fixed (Dax/Mira/Raya), so name matching is safe.
#   3. Buildings + fabricators + relays. Buildings first so the
#      fabricator/relay state can attach to existing anchors.
func apply_run_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var version: int = int(data.get("version", 0))
	if version != SaveManager.SAVE_FORMAT_VERSION:
		push_warning("Save format mismatch (got %d, want %d) — skipping load." % [version, SaveManager.SAVE_FORMAT_VERSION])
		return
	# 1) Run-level state.
	var main_data: Dictionary = data.get("main", {})
	threat_level = float(main_data.get("threat_level", 0.0))
	relay_module_crafted = bool(main_data.get("relay_module_crafted", false))
	day_time = float(main_data.get("day_time", 0.5))
	var saved_stats: Dictionary = main_data.get("run_stats", {})
	for k in saved_stats.keys():
		run_stats[k] = saved_stats[k]
	# Wave number (state always resumes as PEACE in this MVP).
	if wave_manager != null and "wave_num" in wave_manager:
		wave_manager.wave_num = int(data.get("wave", {}).get("wave_num", 0))
	# 2) Units — match by name, restore each field. data.role and
	# textures are already correct from _spawn_units; we only overwrite
	# stats / state / inventory.
	var units_data: Array = data.get("units", [])
	var by_name: Dictionary = {}
	for u in all_units:
		if is_instance_valid(u):
			by_name[String((u as Unit).data.name)] = u
	for ud_v: Variant in units_data:
		var ud: Dictionary = ud_v as Dictionary
		var unit: Unit = by_name.get(String(ud.get("name", "")), null) as Unit
		if unit == null:
			continue
		unit.position = Vector2(float(ud.get("pos_x", 0.0)), float(ud.get("pos_y", 0.0)))
		unit.data.health = float(ud.get("health", unit.data.health))
		unit.data.max_health = float(ud.get("max_health", unit.data.max_health))
		unit.data.attack_damage = int(ud.get("attack_damage", unit.data.attack_damage))
		unit.data.attack_range_tiles = float(ud.get("attack_range_tiles", unit.data.attack_range_tiles))
		unit.data.attack_cooldown = float(ud.get("attack_cooldown", unit.data.attack_cooldown))
		unit.data.speed = float(ud.get("speed", unit.data.speed))
		unit.drafted = bool(ud.get("drafted", false))
		unit.evacuated = bool(ud.get("evacuated", false))
		unit.auto_heal_enabled = bool(ud.get("auto_heal_enabled", false))
		unit.data.inventory = (ud.get("inventory", {}) as Dictionary).duplicate(true)
		unit.data.equipped = (ud.get("equipped", {}) as Dictionary).duplicate(true)
		var saved_priorities: Dictionary = ud.get("work_priorities", {}) as Dictionary
		for pk in saved_priorities.keys():
			unit.data.work_priorities[pk] = saved_priorities[pk]
		# Apply downed state through the proper channel so sprites and
		# the flashlight/glow get reconfigured. Calling _enter_downed
		# directly mirrors what take_damage does on HP→0.
		if bool(ud.get("is_downed", false)):
			if unit.has_method("_enter_downed"):
				unit._enter_downed()
		# Evacuated units should hide their visual + drop their colliders
		# the way evacuate() handles it.
		if unit.evacuated and unit.has_method("evacuate"):
			unit.evacuate()
	# 3) Buildings — restore each via the Grid helper.
	for b_v: Variant in data.get("buildings", []):
		var b: Dictionary = b_v as Dictionary
		var pos: Vector2 = Vector2(int(b.get("x", 0)), int(b.get("y", 0)))
		grid.restore_building(pos, String(b.get("def_key", "")), int(b.get("hp", -1)))
	# 4) Fabricator queues + progress.
	for f_v: Variant in data.get("fabricators", []):
		var f: Dictionary = f_v as Dictionary
		var pos: Vector2 = Vector2(int(f.get("x", 0)), int(f.get("y", 0)))
		if grid.fabricators.has(pos):
			grid.fabricators[pos].queue = (f.get("queue", []) as Array).duplicate(true)
			grid.fabricators[pos].progress = float(f.get("progress", 0.0))
	# 5) Comm-relay channel progress.
	for r_v: Variant in data.get("comm_relays", []):
		var r: Dictionary = r_v as Dictionary
		var pos: Vector2 = Vector2(int(r.get("x", 0)), int(r.get("y", 0)))
		if grid.comm_relays.has(pos):
			grid.comm_relays[pos].progress = float(r.get("progress", 0.0))
			grid.comm_relays[pos].completed = bool(r.get("completed", false))
	# Re-apply run_stats AFTER everything else. Both restore_building
	# (calls record_building_built) and _enter_downed (calls record_downed)
	# bump counters during load — overwriting at the end keeps the saved
	# values authoritative.
	for k in saved_stats.keys():
		run_stats[k] = saved_stats[k]
	# Refresh the HUD now that inventories / equipped slots changed.
	notify_inventory_changed()
	if gui != null and gui.has_method("show_wave_banner"):
		gui.show_wave_banner("Save loaded — survivors restored", 4.0)


# Pull the save dict that the menu queued (if any) and apply it. Always
# resets queued_load_slot to -1 afterwards so a future "New Game" doesn't
# inadvertently re-trigger a load.
func _apply_pending_load() -> void:
	var slot: int = SaveManager.queued_load_slot
	SaveManager.queued_load_slot = -1
	if slot < 0:
		return
	var data: Dictionary = SaveManager.read_run_data(slot)
	if data.is_empty():
		return
	apply_run_data(data)


# Pull a multi-item dict from the team's combined inventory. Returns true on
# success (every item fully covered); on failure, no inventory is modified.
# Used by the fabricator queue — committing a craft is all-or-nothing so the
# player doesn't get half-charged for a recipe they can't afford.
func pull_shared_resources(items: Dictionary) -> bool:
	# First pass: confirm the team has every item in sufficient quantity.
	for item_name in items.keys():
		var needed: int = int(items[item_name])
		var team_total: int = 0
		for u in all_units:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.is_dead() or unit_node.is_downed:
				continue
			team_total += int(unit_node.data.inventory.get(item_name, 0))
		if team_total < needed:
			return false
	# Second pass: actually deduct, distributed across donors.
	for item_name in items.keys():
		var remaining: int = int(items[item_name])
		for u in all_units:
			if remaining <= 0:
				break
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.is_dead() or unit_node.is_downed:
				continue
			var inv: Dictionary = unit_node.data.inventory
			var have: int = int(inv.get(item_name, 0))
			if have <= 0:
				continue
			var take: int = min(have, remaining)
			var new_count: int = have - take
			if new_count <= 0:
				inv.erase(item_name)
			else:
				inv[item_name] = new_count
			remaining -= take
	return true


# Dispatch a single click in command-mode. Routes to the right pending_tasks
# entry based on the active mode and what the click landed on. No-ops cleanly
# (silently) on a click that doesn't match the mode — e.g., clicking grass in
# Repair mode does nothing rather than crashing.
func _handle_command_click(mode: String) -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	var click_cell: Vector2 = grid.worldToGrid(mouse_world)
	if not grid.grid.has(click_cell):
		return
	match mode:
		"repair":
			if not grid.cell_to_building.has(click_cell):
				return
			var anchor: Vector2 = grid.cell_to_building[click_cell]
			if not grid.buildings.has(anchor):
				return
			var b: Dictionary = grid.buildings[anchor]
			if int(b.hp) >= int(b.max_hp):
				return  # already at full HP, nothing to do
			# Avoid duplicate tasks for the same anchor.
			for t in pending_tasks:
				if t.type == "repair" and t.pos == anchor:
					return
			pending_tasks.append({"type": "repair", "pos": anchor})
			grid.set_task_marker(anchor, "repair")
			_assign_tasks()
		"harvest":
			if not grid.tree_root.has(click_cell):
				return
			var root: Vector2 = grid.get_tree_root(click_cell)
			for t in pending_tasks:
				if t.type == "harvest" and t.pos == root:
					return
			pending_tasks.append({"type": "harvest", "pos": root})
			grid.set_task_marker(root, "harvest")
			_assign_tasks()
		"mine":
			if not grid.grid.has(click_cell):
				return
			var occ: Variant = grid.grid[click_cell].occupier
			if occ != "Rock" and occ != "Ore":
				return
			for t in pending_tasks:
				if t.type == "mine" and t.pos == click_cell:
					return
			pending_tasks.append({"type": "mine", "pos": click_cell})
			grid.set_task_marker(click_cell, "mine")
			_assign_tasks()
		"revive":
			# Click a downed body in the world to enqueue a revive task.
			# Picks up the closest downed unit at the click (matches the
			# right-click flow), then any free non-downed teammate with
			# heal-priority > OFF dispatches via _assign_tasks.
			var downed_target: Unit = _downed_unit_at_world(mouse_world)
			if downed_target == null:
				return
			# Dedupe — same target already queued.
			for t in pending_tasks:
				if t.type == "revive" and t.get("target_unit") == downed_target:
					return
			pending_tasks.append({
				"type": "revive",
				"pos": downed_target.get_grid_pos(),
				"target_unit": downed_target,
			})
			_assign_tasks()
		"cancel":
			# Cancel any queued / in-progress task whose target sits on or
			# under the clicked cell. Resolves the cell to every possible
			# anchor (tree root, building anchor, downed unit, raw cell)
			# and wipes the matching pending_tasks entries + aborts any
			# unit currently working on them + clears the task marker.
			_cancel_tasks_at_cell(click_cell, mouse_world)
		"build":
			# Manual nudge for a blueprint that didn't get auto-built (usually
			# because materials were short at placement time). Resolves the
			# clicked cell to its blueprint anchor, dedupes against existing
			# pending build tasks, then dispatches.
			var bp_anchor: Vector2 = grid.blueprint_at_cell(click_cell)
			if bp_anchor == Vector2(-1, -1):
				return
			# Surface the deficit to the player even if we still queue the task
			# — the build will fire automatically once mats arrive (harvest /
			# mine / loot drop / refund), but the toast tells them what to go
			# get instead of leaving them guessing why nothing happens.
			var missing: Dictionary = _missing_materials_for(bp_anchor)
			if not missing.is_empty() and gui != null and gui.has_method("notify_shortage"):
				var bp_world: Vector2 = grid.gridToWorld(bp_anchor) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
				gui.notify_shortage(bp_world, missing)
			grid.set_task_marker(bp_anchor, "build")
			for t in pending_tasks:
				if t.type == "build" and t.pos == bp_anchor:
					_assign_tasks()
					return
			pending_tasks.append({"type": "build", "pos": bp_anchor})
			_assign_tasks()
		"demolish":
			# A click on an unbuilt blueprint cancels it instantly and refunds
			# whatever materials were committed. No worker needed — the player
			# is just changing their mind about the placement.
			var bp_anchor: Vector2 = grid.blueprint_at_cell(click_cell)
			if bp_anchor != Vector2(-1, -1):
				_cancel_blueprint_with_refund(bp_anchor)
				return
			if not grid.cell_to_building.has(click_cell):
				return
			var dem_anchor: Vector2 = grid.cell_to_building[click_cell]
			if not grid.buildings.has(dem_anchor):
				return
			for t in pending_tasks:
				if t.type == "demolish" and t.pos == dem_anchor:
					return
			pending_tasks.append({"type": "demolish", "pos": dem_anchor})
			# Demolish overrides any pending repair on the same wall — the
			# marker swaps to the red "X" so the player sees the change.
			grid.set_task_marker(dem_anchor, "demolish")
			_assign_tasks()


func _on_blueprint_placed(grid_pos: Vector2, _def: Dictionary) -> void:
	pending_tasks.append({"type": "build", "pos": grid_pos})
	grid.set_task_marker(grid_pos, "build")
	_assign_tasks()


func _assign_tasks() -> void:
	# Tracks build tasks we've already pushed to the back of the queue this
	# round so a queue full of "needs more materials" builds doesn't spin
	# forever. Once we've cycled past a deferred task without dispatching, we
	# stop trying — they'll be retried next time _assign_tasks is called.
	var deferred_seen: Dictionary = {}
	while not pending_tasks.is_empty():
		var task: Dictionary = pending_tasks[0]
		# Stale build task (blueprint canceled / completed by another worker
		# while this task waited) — drop it and try the next.
		if task.type == "build" and not grid.blueprints.has(task.pos):
			pending_tasks.remove_at(0)
			continue
		# Build task without enough materials — push to the back so other
		# tasks (harvest, repair, etc.) can run in front of it. The hooks in
		# notify_inventory_changed() retry the whole queue once new mats land.
		if task.type == "build" and not _can_build_now(task.pos):
			var key: String = "build:%s" % str(task.pos)
			if deferred_seen.has(key):
				break  # cycled back to a task we already deferred this round
			deferred_seen[key] = true
			pending_tasks.remove_at(0)
			pending_tasks.append(task)
			continue
		# Revive task — drop if the target is gone (already revived elsewhere
		# or evac'd / dead before we got to it). Otherwise dispatch with the
		# heal priority key so medics naturally get first crack.
		if task.type == "revive":
			var rev_target = task.get("target_unit")
			if rev_target == null or not is_instance_valid(rev_target) or not rev_target.is_downed:
				pending_tasks.remove_at(0)
				continue
		var task_type: String = task.type
		# Demolish piggybacks on the "build" priority — same idea (a colonist
		# who builds is also the one who tears things down). Revive uses the
		# heal priority — medics naturally get first crack at it.
		var priority_key: String = task_type
		if task_type == "demolish":
			priority_key = "build"
		elif task_type == "revive":
			priority_key = "heal"
		# Filter to idle, undrafted, alive units that haven't disabled this
		# work type. Priority-OFF units refuse the task entirely.
		var eligible: Array = all_units.filter(func(u: Unit) -> bool:
			if not is_instance_valid(u) or u.is_dead():
				return false
			# Downed teammates can't take work — they need revival first.
			if u.is_downed or u.evacuated:
				return false
			if u.drafted or u.is_busy():
				return false
			var pri: int = int(u.data.work_priorities.get(priority_key, UnitData.Priority.MED))
			return pri > UnitData.Priority.OFF
		)
		if eligible.is_empty():
			break
		# Highest priority level wins. Within the same level, the closest unit
		# to the task takes it.
		var top_pri: int = -1
		for u in eligible:
			var pri: int = int((u as Unit).data.work_priorities.get(priority_key, UnitData.Priority.MED))
			if pri > top_pri:
				top_pri = pri
		var candidates: Array = eligible.filter(func(u: Unit) -> bool:
			return int(u.data.work_priorities.get(priority_key, UnitData.Priority.MED)) == top_pri
		)
		var closest: Unit = candidates[0]
		for u in candidates:
			if u.get_grid_pos().distance_to(task.pos) < closest.get_grid_pos().distance_to(task.pos):
				closest = u
		pending_tasks.remove_at(0)
		match task.type:
			"harvest":  closest.queue_harvest(task.pos)
			"build":    closest.queue_build(task.pos)
			"repair":   closest.queue_repair(task.pos)
			"demolish": closest.queue_demolish(task.pos)
			"mine":     closest.queue_mine(task.pos)
			"revive":
				# Pass the actual Unit reference (positions can shift slightly
				# but the body's grid cell is stable; we still need the Unit
				# pointer for queue_revive's path + arrival logic).
				var rt = task.get("target_unit")
				if rt != null and is_instance_valid(rt):
					closest.queue_revive(rt)


func toggle_brightness() -> void:
	_bright_mode = not _bright_mode
	if _bright_mode:
		canvas_modulate.color = Color(1, 1, 1)
		if _fog_layer:
			_fog_layer.visible = false
	else:
		if _fog_layer:
			_fog_layer.visible = true


func _process(_delta: float) -> void:
	# Run timer only counts pre-victory/defeat — once the run ends the
	# summary panel freezes the elapsed time alongside the other stats.
	# Threat baseline also pauses on game end so the bar stops creeping.
	if wave_manager != null and "state" in wave_manager:
		var st: int = int(wave_manager.state)
		if st != 3 and st != 4:  # not VICTORY / DEFEAT
			run_stats.run_time += _delta
			threat_level += THREAT_BASELINE_PER_SEC * _delta
	if gui.followed_unit != null:
		$Camera2D.position = gui.followed_unit.position
	#day_time = fmod(day_time + delta / DAY_DURATION, 1.0)
	# Remap to cycle only between "almost night" (0.58) and "deep night" (0.85)
	var sky := _sky_color_at(0.74 + day_time * 0.08)
	# Player-facing global brightness multiplier (Settings → Brightness).
	# 1.0 = no change, <1.0 dims the world, >1.0 brightens it. Applied to
	# both the day/night sky tint and the debug bright-mode override so the
	# slider works regardless of which path is driving canvas_modulate.
	var bright_mul: float = SaveManager.get_global_brightness()
	if _bright_mode:
		canvas_modulate.color = Color(bright_mul, bright_mul, bright_mul)
	else:
		canvas_modulate.color = Color(sky.r * bright_mul, sky.g * bright_mul, sky.b * bright_mul, sky.a)
	# Lights fade in as the sky darkens (v is HSV brightness, 0=dark, 1=bright)
	var night_factor := 1.0 - sky.v
	grid.set_tree_light_energy(night_factor * 0.8)
	grid.set_red_tree_light_energy(night_factor * 0.9)
	grid.set_crab_light_energy(night_factor * 0.6)
	grid.set_shadow_opacity(sky.v)
	_update_fog()
	_update_entity_visibility()


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
			"Tree":
				# Drafted units → popup so right-click during tactical
				# movement doesn't silently re-task them. Undrafted →
				# auto-queue through the harvest-priority scheduler.
				var tree_root_cell: Vector2 = body.get_meta("grid_pos")
				for t in pending_tasks:
					if t.type == "harvest" and t.pos == tree_root_cell:
						return
				if drafted.is_empty():
					pending_tasks.append({"type": "harvest", "pos": tree_root_cell})
					grid.set_task_marker(tree_root_cell, "harvest")
					_assign_tasks()
					return
				var t_best := _best_unit(drafted, tree_root_cell)
				var u_tree := t_best
				_inspect_pending = func():
					u_tree.queue_harvest(tree_root_cell)
					grid.set_task_marker(tree_root_cell, "harvest")
				_inspect_btn.text = "Harvest"
				_loot_btn.visible = false
				_inspect_popup.custom_minimum_size = Vector2(110, 36)
				_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
				_inspect_popup.visible = true
				return
			"Rock", "Ore":
				# Drafted units → confirmation popup so a right-click in the
				# middle of tactical movement doesn't silently yank the unit
				# off into mining. Undrafted (worker-mode) → auto-queue via
				# the priority dispatcher.
				var rock_grid: Vector2 = body.get_meta("grid_pos")
				for t in pending_tasks:
					if t.type == "mine" and t.pos == rock_grid:
						return
				if drafted.is_empty():
					pending_tasks.append({"type": "mine", "pos": rock_grid})
					grid.set_task_marker(rock_grid, "mine")
					_assign_tasks()
					return
				var best_miner := _best_unit(drafted, rock_grid)
				var u_ref := best_miner
				_inspect_pending = func():
					u_ref.queue_mine(rock_grid)
					grid.set_task_marker(rock_grid, "mine")
				_inspect_btn.text = "Mine"
				_loot_btn.visible = false
				_inspect_popup.custom_minimum_size = Vector2(110, 36)
				_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
				_inspect_popup.visible = true
				return
			"Driftwood":
				# Same drafted-vs-worker split as rocks: popup when drafted,
				# auto-queue otherwise. (Auto-queue uses the harvest-priority
				# scheduler so any free worker walks over.)
				var dw_cell: Vector2 = body.get_meta("grid_pos")
				if drafted.is_empty():
					var dw_best_w: Unit = null
					var dw_best_d_w: float = INF
					for u in all_units:
						if not is_instance_valid(u): continue
						var un: Unit = u as Unit
						if un.is_dead() or un.is_downed or un.evacuated: continue
						var d: float = un.get_grid_pos().distance_to(dw_cell)
						if d < dw_best_d_w:
							dw_best_d_w = d
							dw_best_w = un
					if dw_best_w == null:
						return
					var dest_w: Vector2 = _find_adjacent_to(dw_cell, dw_best_w)
					if dest_w == Vector2(-1, -1):
						return
					var cb_w := func():
						var drops: Dictionary = grid.collect_driftwood(dw_cell)
						if drops.is_empty():
							return
						for item_name: String in drops.keys():
							dw_best_w.data.inventory[item_name] = int(dw_best_w.data.inventory.get(item_name, 0)) + int(drops[item_name])
						if gui != null and gui.has_method("notify_loot_batch"):
							var dw_world: Vector2 = grid.gridToWorld(dw_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
							gui.notify_loot_batch(dw_world, drops)
						notify_inventory_changed()
					dw_best_w.inspect_move_to(dest_w, cb_w)
					return
				var dw_best := _best_unit(drafted, dw_cell)
				var dw_dest := _find_adjacent_to(dw_cell, dw_best)
				if dw_dest == Vector2(-1, -1):
					return
				var u_dw := dw_best
				var cell_ref := dw_cell
				_inspect_pending = func():
					var pickup_cb := func():
						var drops: Dictionary = grid.collect_driftwood(cell_ref)
						if drops.is_empty():
							return
						for item_name: String in drops.keys():
							u_dw.data.inventory[item_name] = int(u_dw.data.inventory.get(item_name, 0)) + int(drops[item_name])
						if gui != null and gui.has_method("notify_loot_batch"):
							var dw_world: Vector2 = grid.gridToWorld(cell_ref) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
							gui.notify_loot_batch(dw_world, drops)
						notify_inventory_changed()
					u_dw.draft_inspect_to(dw_dest, pickup_cb)
				_inspect_btn.text = "Collect"
				_loot_btn.visible = false
				_inspect_popup.custom_minimum_size = Vector2(110, 36)
				_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
				_inspect_popup.visible = true
				return
			"CrashedShip", "HullFragment":
				if drafted.is_empty(): return
				_show_inspect_popup(drafted, grid.crash_site_pos, Vector2i(4, 4), "ship")
				var best_ship := _best_unit(drafted, grid.crash_site_pos)
				var dest_ship := _find_adjacent_to(grid.crash_site_pos, best_ship, Vector2i(4, 4))
				if dest_ship != Vector2(-1, -1) or _is_adjacent_to(best_ship.get_grid_pos(), grid.crash_site_pos, Vector2i(4, 4)):
					var u_ship := best_ship
					_loot_pending = func():
						var cb := func():
							gui.show_char_inv_panel(u_ship)
							gui.show_loot_panel("Crashed Ship", grid.ship_inventory, grid.crash_site_pos)
						if _is_adjacent_to(u_ship.get_grid_pos(), grid.crash_site_pos, Vector2i(4, 4)):
							cb.call()
						else:
							u_ship.draft_inspect_to(dest_ship, cb)
					_loot_btn.visible = true
					_inspect_popup.custom_minimum_size = Vector2(220, 36)
				return
			"SupplyCrate":
				if drafted.is_empty(): return
				var crate_pos: Vector2 = body.get_meta("grid_pos")
				_show_inspect_popup(drafted, crate_pos, Vector2i(1, 1), "crate")
				var best_crate := _best_unit(drafted, crate_pos)
				var dest_crate := _find_adjacent_to(crate_pos, best_crate, Vector2i(1, 1))
				if dest_crate != Vector2(-1, -1) or _is_adjacent_to(best_crate.get_grid_pos(), crate_pos, Vector2i(1, 1)):
					var u_crate := best_crate
					var cp := crate_pos
					_loot_pending = func():
						var cb := func():
							gui.show_char_inv_panel(u_crate)
							if grid.crate_inventories.has(cp):
								gui.show_loot_panel("Supply Crate", grid.crate_inventories[cp], cp)
						if _is_adjacent_to(u_crate.get_grid_pos(), cp, Vector2i(1, 1)):
							cb.call()
						else:
							u_crate.draft_inspect_to(dest_crate, cb)
					_loot_btn.visible = true
					_inspect_popup.custom_minimum_size = Vector2(220, 36)
				return
			"Monolith":
				if drafted.is_empty(): return
				_show_inspect_popup(drafted, grid.monolith_pos, Vector2i(2, 2), "monolith")
				return

	# Right-click on a downed teammate → dispatch the closest live unit to
	# revive them. Always works (regardless of draft state) since revival is
	# a critical action — the player shouldn't have to draft first to save
	# someone bleeding out next to them.
	var downed_target: Unit = _downed_unit_at_world(mouse_world)
	if downed_target != null:
		var rescuer: Unit = _closest_live_unit_to(downed_target)
		if rescuer != null:
			rescuer.queue_revive(downed_target)
		return

	# Right-click on a Fabricator → open its craft panel. Built structures
	# don't have collision bodies, so detect via the cell→building reverse
	# map. No drafted-unit requirement — crafting is a base operation, not
	# a unit task.
	var click_cell: Vector2 = grid.worldToGrid(mouse_world)
	if grid.cell_to_building.has(click_cell):
		var built_anchor: Vector2 = grid.cell_to_building[click_cell]
		if grid.fabricators.has(built_anchor):
			gui.show_craft_panel(built_anchor)
			return
		# Right-click on a built Comm Relay Antenna → show a confirmation
		# popup ("Channel" button) the same way harvest / mine work, so a
		# stray right-click doesn't accidentally pull a defender off the
		# front line. Clicking the button dispatches a teammate to channel
		# the relay — drafted units take priority; otherwise pick the
		# closest live, non-channeling unit on the team. Once they arrive
		# and stay adjacent for RELAY_CHANNEL_DURATION,
		# WaveManager.trigger_evac_from_relay() fires.
		if grid.comm_relays.has(built_anchor):
			var relay_state: Dictionary = grid.comm_relays[built_anchor]
			if relay_state.get("completed", false):
				return  # already used; the EVAC is on its way
			var anchor_world: Vector2 = grid.gridToWorld(built_anchor) + Vector2(grid.cell_size, grid.cell_size)
			# Prefer the closest drafted unit if any are drafted, else the
			# closest live teammate. Either way we filter out dead / downed /
			# already-channeling units.
			var pool: Array = drafted if not drafted.is_empty() else all_units
			var channeler: Unit = null
			var best_d: float = INF
			for u in pool:
				if not is_instance_valid(u):
					continue
				var unit_node: Unit = u as Unit
				if unit_node.is_dead() or unit_node.is_downed or unit_node.evacuated:
					continue
				if unit_node.relay_target != Vector2(-1, -1):
					continue
				var d: float = unit_node.global_position.distance_to(anchor_world)
				if d < best_d:
					best_d = d
					channeler = unit_node
			if channeler == null:
				return
			var u_ref: Unit = channeler
			var anchor_ref: Vector2 = built_anchor
			_inspect_pending = func():
				u_ref.queue_relay_channel(anchor_ref)
				gui.show_wave_banner("Calling for evac — defend the antenna!", 4.0)
			_inspect_btn.text = "Channel"
			_loot_btn.visible = false
			_inspect_popup.custom_minimum_size = Vector2(110, 36)
			_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
			_inspect_popup.visible = true
			return

	# Right-click on a construction blueprint → cancel it and refund the
	# committed materials to the closest live unit. Tiny popup confirms
	# the cancel (matches the harvest/mine pattern) so a stray click
	# during tactical movement doesn't wipe a half-built structure.
	# blueprint_at_cell returns (-1,-1) when the cell isn't a blueprint.
	var bp_anchor: Vector2 = grid.blueprint_at_cell(click_cell)
	if bp_anchor != Vector2(-1, -1):
		var anchor_to_cancel: Vector2 = bp_anchor
		_inspect_pending = func():
			_cancel_blueprint_with_refund(anchor_to_cancel)
		_inspect_btn.text = "Cancel"
		_loot_btn.visible = false
		_inspect_popup.custom_minimum_size = Vector2(110, 36)
		_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
		_inspect_popup.visible = true
		return

	# Right-click on a regrowing tree → tell the player it's not chop-ready.
	# The countdown is intentionally hidden so the player has to read the
	# sapling's visual size rather than watching a clock. Toast spawns at
	# the tree itself (in green for "growing") rather than the top-of-
	# screen banner so the message is grounded to the object the player
	# clicked.
	if not grid.regrowing_tree_at(click_cell).is_empty():
		var sapling_world: Vector2 = grid.gridToWorld(click_cell) + Vector2(grid.cell_size * 0.5, -grid.cell_size * 0.3)
		_spawn_world_toast(sapling_world, "Tree is still regrowing", Color(0.55, 1.0, 0.55))
		return

	# Right-click on a tree → harvest. Drafted units get a confirmation
	# popup so a stray click during tactical movement doesn't re-task them;
	# worker mode auto-queues via the harvest-priority scheduler.
	if grid.tree_root.has(click_cell):
		var tree_root: Vector2 = grid.get_tree_root(click_cell)
		for t in pending_tasks:
			if t.type == "harvest" and t.pos == tree_root:
				return
		if drafted.is_empty():
			pending_tasks.append({"type": "harvest", "pos": tree_root})
			grid.set_task_marker(tree_root, "harvest")
			_assign_tasks()
			return
		var t_best := _best_unit(drafted, tree_root)
		var u_tree := t_best
		_inspect_pending = func():
			u_tree.queue_harvest(tree_root)
			grid.set_task_marker(tree_root, "harvest")
		_inspect_btn.text = "Harvest"
		_loot_btn.visible = false
		_inspect_popup.custom_minimum_size = Vector2(110, 36)
		_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
		_inspect_popup.visible = true
		return

	# Right-click on a damaged wall → dispatch the closest drafted unit to
	# repair it. Walls are Sprite2D-based, no collider, so they're invisible
	# to the physics query above; check via the cell→building reverse map.
	if not drafted.is_empty():
		if grid.cell_to_building.has(click_cell):
			var anchor: Vector2 = grid.cell_to_building[click_cell]
			if grid.buildings.has(anchor):
				var b_state: Dictionary = grid.buildings[anchor]
				if int(b_state.hp) < int(b_state.max_hp):
					var best_repair: Unit = _best_unit(drafted, anchor) as Unit
					if best_repair != null:
						best_repair.queue_repair(anchor)
						grid.set_task_marker(anchor, "repair")
					return

	# Right-click on a crab → explicit attack target for all drafted units.
	# Crabs are Node2Ds with no collision shape, so the physics query above misses
	# them; check by distance to the cell-center anchor instead.
	if not drafted.is_empty():
		var crab_target: Node = _crab_at_world(mouse_world)
		if crab_target != null:
			for u_attack in drafted:
				(u_attack as Unit).attack_target(crab_target)
			return

	# No physics hit — move drafted units to navigable ground
	var grid_pos := grid.worldToGrid(mouse_world)
	if not grid.grid.has(grid_pos):
		return
	if grid.grid[grid_pos].navigable:
		var targets := _world_formation(mouse_world, drafted.size())
		for i in drafted.size():
			drafted[i].draft_move_to(targets[i])


func _crab_at_world(mouse_world: Vector2) -> Node:
	# Click radius: half a tile is forgiving but not so big it triggers on empty
	# beach cells next to a crab.
	var hit_radius: float = float(grid.cell_size) * 0.5
	var best: Node = null
	var best_d: float = hit_radius
	for c in grid.crabs:
		if not is_instance_valid(c):
			continue
		if c.has_method("is_dead") and c.is_dead():
			continue
		var center: Vector2 = c.global_position + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		var d: float = mouse_world.distance_to(center)
		if d < best_d:
			best_d = d
			best = c
	return best


# Closest downed Unit within a forgiving click radius around `mouse_world`.
# The lying body's visual centre sits a bit above the unit's feet anchor —
# offset accounts for that so the click target matches the rendered sprite.
func _downed_unit_at_world(mouse_world: Vector2) -> Unit:
	var hit_radius: float = float(grid.cell_size) * 0.7
	var best: Unit = null
	var best_d: float = hit_radius
	for u in all_units:
		if not is_instance_valid(u) or not u.is_downed:
			continue
		var center: Vector2 = u.global_position + Vector2(0.0, -float(grid.cell_size) * 0.4)
		var d: float = mouse_world.distance_to(center)
		if d < best_d:
			best_d = d
			best = u
	return best


# Tear down a blueprint that hasn't finished construction and refund any
# materials already committed to it. Drops a loot toast over the spot so
# the player sees the refund and knows it's done.
func _cancel_blueprint_with_refund(anchor: Vector2) -> void:
	# Drop the build task from any pending queue + clear any unit currently
	# en route or mid-build (so they don't keep ticking on a ghost target).
	pending_tasks = pending_tasks.filter(func(t): return not (t.type == "build" and t.pos == anchor))
	for u in all_units:
		if not is_instance_valid(u):
			continue
		if u.build_target == anchor:
			u.build_target = Vector2(-1, -1)
			u._build_timer = -1.0
			u._stop_work_loop()
	var refund: Dictionary = grid.cancel_blueprint(anchor)
	if refund.is_empty():
		return
	# Auto-deposit refund into the closest live, non-downed unit so the
	# materials immediately re-enter the team pool.
	var anchor_world: Vector2 = grid.gridToWorld(anchor) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	var recipient: Unit = null
	var best_d: float = INF
	for u in all_units:
		if not is_instance_valid(u) or u.is_dead() or u.is_downed:
			continue
		var d: float = u.global_position.distance_to(anchor_world)
		if d < best_d:
			best_d = d
			recipient = u
	if recipient != null:
		for item_name in refund.keys():
			recipient.data.inventory[item_name] = int(recipient.data.inventory.get(item_name, 0)) + int(refund[item_name])
	if gui != null and gui.has_method("notify_loot_batch"):
		gui.notify_loot_batch(anchor_world, refund)
	notify_inventory_changed()


# Closest still-standing teammate to dispatch toward `target`. Selected units
# get first pick (player intent — "use this guy"), then any other live unit.
func _closest_live_unit_to(target: Unit) -> Unit:
	var best: Unit = null
	var best_d: float = INF
	for u in selected_units:
		if u == target or u.is_downed:
			continue
		var d: float = u.global_position.distance_to(target.global_position)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		return best
	for u in all_units:
		if u == target or u.is_downed:
			continue
		var d: float = u.global_position.distance_to(target.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


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
	_loot_btn.visible = false
	_inspect_popup.custom_minimum_size = Vector2(110, 36)
	_inspect_popup.position = get_viewport().get_mouse_position() + Vector2(4, 4)
	_inspect_popup.visible = true


func _setup_inspect_popup() -> void:
	_inspect_popup = Panel.new()
	_inspect_popup.visible = false
	_inspect_popup.custom_minimum_size = Vector2(110, 36)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)

	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	inspect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_btn.pressed.connect(func():
		_inspect_popup.visible = false
		if _inspect_pending.is_valid():
			_inspect_pending.call()
			_inspect_pending = Callable()
	)
	hbox.add_child(inspect_btn)
	_inspect_btn = inspect_btn

	_loot_btn = Button.new()
	_loot_btn.text = "Loot"
	_loot_btn.visible = false
	_loot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_btn.pressed.connect(func():
		_inspect_popup.visible = false
		if _loot_pending.is_valid():
			_loot_pending.call()
			_loot_pending = Callable()
	)
	hbox.add_child(_loot_btn)

	_inspect_popup.add_child(hbox)
	$CanvasLayer.add_child(_inspect_popup)
	_setup_debug_button()


var _collision_overlay: Node2D = null
var _nav_overlay: Node2D = null

func _setup_debug_button() -> void:
	# Overlay nodes still get created here (they need to be children of the
	# grid so they render in the right layer). The toggle BUTTONS, however,
	# now live inside the GUI's Debug dropdown — keeping the top-right
	# corner clean. Public toggle methods below are what the dropdown calls.
	_collision_overlay = _CollisionOverlay.new(grid)
	_collision_overlay.z_index = 100
	_collision_overlay.visible = false
	grid.add_child(_collision_overlay)

	_nav_overlay = _NavOverlay.new(grid)
	_nav_overlay.z_index = 99
	_nav_overlay.visible = false
	grid.add_child(_nav_overlay)


# Called by GUI's Debug dropdown — returns the new visibility state so the
# button can update its own label (Show ↔ Hide).
func toggle_collision_overlay() -> bool:
	if _collision_overlay == null:
		return false
	_collision_overlay.visible = not _collision_overlay.visible
	return _collision_overlay.visible


func toggle_nav_overlay() -> bool:
	if _nav_overlay == null:
		return false
	_nav_overlay.visible = not _nav_overlay.visible
	return _nav_overlay.visible


func toggle_show_creatures() -> bool:
	show_creatures = not show_creatures
	return show_creatures


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
	var ref := unit.get_grid_pos()
	# Fast path: if the unit is already standing on a perimeter cell, return
	# that cell directly. Otherwise the closest-by-Euclidean pick can land
	# on a different ring tile (e.g., the diagonal next to where the unit
	# stands), which forces a one-cell shuffle for no reason.
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue
			if anchor + Vector2(dx, dy) == ref and grid.grid.has(ref) and grid.grid[ref].navigable:
				return ref
	var best := Vector2(-1, -1)
	var best_dist := INF
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
