class_name Grid
extends TileMap

@export var width: int = 100
@export var height: int = 100
@export var cell_size: int = 128

var grid: Dictionary = {}
var tree_sprites: Dictionary = {}
var tree_lights_by_root: Dictionary = {}
var tree_lights: Array = []
var red_tree_lights: Array = []
var crab_lights: Array = []
var crabs: Array = []
var shadow_sprites: Array = []
var tree_root: Dictionary = {}   # maps any tree cell → its root (top-left) pos
# Rock cell → { sprite, shadow, body }. Populated by WorldSpawner.spawn_rocks
# so mine_rock() can free the right nodes when a rock is consumed.
var rock_nodes: Dictionary = {}
# Ore cell → { sprite, shadow, body, kind: "iron"|"copper" }. Populated by
# WorldSpawner.spawn_tide_pools so mine_at() can free the right nodes when
# an ore cell is mined and roll metal-heavy drops based on `kind`.
var ore_nodes: Dictionary = {}
# Driftwood pile cell → { sprite, shadow, body }. Populated by
# WorldSpawner.spawn_driftwood so collect_driftwood() can free the right
# nodes when a unit picks it up.
var driftwood_nodes: Dictionary = {}
# Persistent harvest/mine progress so an interrupted worker doesn't reset the
# job. Keyed by the tree's root cell (3x3 anchor) or the rock's cell.
# Value = elapsed seconds (0..duration). Cleared when the tree/rock is
# consumed. Active visual bars are tracked separately so they vanish when
# nobody's working but the saved progress survives.
var tree_harvest_progress: Dictionary = {}  # root → elapsed_sec
var rock_mine_progress: Dictionary = {}     # cell → elapsed_sec
var _harvest_bars: Dictionary = {}          # root → {bg, fill, bar_x, bar_y, bar_w}
var _mine_bars: Dictionary = {}             # cell → {bg, fill, bar_x, bar_y, bar_w}
# Visual indicators for queued/active tasks (harvest/mine/repair/demolish/
# build). Keyed by the target's anchor cell — one marker per anchor; calling
# set_task_marker on an existing anchor swaps the visual to the new type.
const _TASK_MARKER_SCRIPT: Script = preload("res://scripts/ui/TaskMarker.gd")
var task_markers: Dictionary = {}            # anchor → Node2D
# Fabricator anchor → { queue: [recipe_id], progress: float, bar_bg, bar_fill }.
# Populated when a Fabricator finishes building; the recipe queue is driven by
# GUI clicks and ticked in _tick_fabricators.
var fabricators: Dictionary = {}
# Comm Relay Antenna anchor → { channeler: Unit, progress: float, bar_bg, bar_fill }.
# Populated when a CommRelay structure finishes building. The channeler unit
# stands adjacent for the entire duration; progress freezes if the channeler
# leaves or goes down. On completion, WaveManager.trigger_evac_from_relay()
# fires.
var comm_relays: Dictionary = {}
const RELAY_CHANNEL_DURATION: float = 90.0  # seconds to call evac

# Light harassment spawn cadence during channeling — one creature every
# RELAY_HARASS_INTERVAL seconds while a channel is actively progressing.
# At 13s on a 90s channel this comes out to ~7 spawns total (alien crab /
# tide crawler / shore stalker), which is enough to make the channel feel
# like a defense moment without overwhelming a moderately walled relay.
const RELAY_HARASS_INTERVAL: float = 13.0
# Initial delay before the first harassment spawn so the player has a
# breather to set up the channeler. Tuned shorter than the interval so
# the first ping feels like an immediate response.
const RELAY_HARASS_INITIAL_DELAY: float = 8.0
# Preload to avoid relying on `class_name CraftRecipes` registration timing
# (same workaround as CreatureDefs in WaveManager).
const _CRAFT_RECIPES := preload("res://scripts/data/CraftRecipes.gd")
# Tree regrowth tracking. Each chopped tree leaves a sapling sprite that
# scales up from REGROW_START_SCALE to 1.0 over REGROW_DURATION; on completion
# the full tree (sprite, body, light, occupier cells) is restored.
var regrowing_trees: Dictionary = {}  # root → { elapsed: float, texture: Texture2D, sapling: Sprite2D }
const REGROW_DURATION: float = 90.0
const REGROW_START_SCALE: float = 0.25
var wood: int = 0

var water_tiles: Dictionary = {}  # Vector2 → true
var dirt_tiles: Dictionary = {}   # Vector2 → true
var dirt_layer: Node2D = null     # sibling node for dirt sprites (avoids TileMap batch interference)
var sprite_layer: Node2D = null   # sibling node for tree/lily/shadow sprites
var crash_site_pos: Vector2 = Vector2(-1, -1)
var monolith_pos: Vector2 = Vector2(-1, -1)
var ship_inventory: Dictionary = {}
var crate_inventories: Dictionary = {}

const NAV_CELL_SIZE: int = 128
var nav_grid: Dictionary = {}  # Vector2 nav_pos → bool (navigable)
signal nav_cell_changed(nav_pos: Vector2)

func navToWorld(_pos: Vector2) -> Vector2:
	return _pos * NAV_CELL_SIZE

func worldToNav(_pos: Vector2) -> Vector2:
	return floor(_pos / NAV_CELL_SIZE)

const _WATER_TILE_SCENE = preload("res://scenes/WaterTile.tscn")

var placement_mode: bool = false
var placement_info: Dictionary = {}
var _preview_pos: Vector2 = Vector2(-999, -999)

var reserved_cells: Dictionary = {}  # Vector2 → Unit, cells claimed as walk destinations

func reserve_cell(cell: Vector2, unit) -> void:
	reserved_cells[cell] = unit

func release_cell(cell: Vector2, unit) -> void:
	if reserved_cells.get(cell) == unit:
		reserved_cells.erase(cell)

func is_cell_reserved(cell: Vector2, exclude_unit) -> bool:
	return reserved_cells.has(cell) and reserved_cells[cell] != exclude_unit

var blueprint_mode: bool = false
# Bitfield orientation for the active placement preview:
#   bit 0 = flip_h, bit 1 = flip_v.
# Cycled via the R key while in blueprint mode (0 → 1 → 2 → 3 → 0).
# Persisted onto each placed blueprint / completed building so cell_mask
# lookup and sprite rendering match the variant the player chose.
var _bp_orientation: int = 0
var blueprints: Dictionary = {}   # top-left grid pos → {def, sprite, orientation}

# Completed buildings with destructible HP. Key is the anchor grid_pos (the
# top-left of the footprint passed to complete_blueprint). Value carries hp,
# sprite ref, and per-frame visual state (hit flash + HP bar fade).
var buildings: Dictionary = {}    # anchor grid_pos → building dict
# Reverse lookup so a crab attacking cell X can find the owning building.
var cell_to_building: Dictionary = {}  # cell grid_pos → anchor grid_pos
const _BUILDING_HIT_FLASH_DURATION := 0.18
const _BUILDING_HP_BAR_DURATION := 5.0
var _bp_def: Dictionary = {}
var _bp_preview: Sprite2D = null

signal blueprint_placed(grid_pos: Vector2, def: Dictionary)

const LAYER_FLOOR = 0
const LAYER_BUILDING = 1
const LAYER_PREVIEW = 2

const SOURCE_LILY_PLANT: int = 8
const SOURCE_LILY_TREE: int  = 9


func generateGrid():
	for x in width:
		for y in height:
			grid[Vector2(x,y)] = CellData.new(Vector2(x, y))
			grid[Vector2(x,y)].floorData = preload("res://data/floors/sand.tres")
			grid[Vector2(x,y)].navChanged.connect(_on_tile_nav_changed)
			refreshTile(Vector2(x,y))
	var ratio := cell_size / NAV_CELL_SIZE
	for x in width * ratio:
		for y in height * ratio:
			nav_grid[Vector2(x, y)] = true


func _on_tile_nav_changed(tile_pos: Vector2) -> void:
	var ratio := cell_size / NAV_CELL_SIZE
	var nav_origin := worldToNav(gridToWorld(tile_pos))
	var nav: bool = grid[tile_pos].navigable
	for dnx in ratio:
		for dny in ratio:
			var nc := nav_origin + Vector2(dnx, dny)
			if nav_grid.has(nc) and nav_grid[nc] != nav:
				nav_grid[nc] = nav
				nav_cell_changed.emit(nc)


func toggle_debug() -> void:
	$Debug.visible = not $Debug.visible


# ── Spawn delegates ──────────────────────────────────────────────────────────

func spawnTrees(spawn_visuals: bool = true) -> void: WorldSpawner.spawn_trees(self, spawn_visuals)
func spawnCrashSite() -> void:  WorldSpawner.spawn_crash_site(self)
func spawnDriftwood() -> void:  WorldSpawner.spawn_driftwood(self)
func spawnRocks() -> void:      WorldSpawner.spawn_rocks(self)
func spawnTidePools() -> void:  WorldSpawner.spawn_tide_pools(self)
func spawnMonolith() -> void:   WorldSpawner.spawn_monolith(self)
func spawnCrabs() -> void:      WorldSpawner.spawn_crabs(self)


# ── Tree / harvest ───────────────────────────────────────────────────────────

func get_tree_root(pos: Vector2) -> Vector2:
	return tree_root.get(pos, pos)


# Show a green progress bar above the tree's 3x3 footprint while a worker
# is actively chopping. Idempotent — calling it twice on the same tree just
# returns the existing bar. `t` is 0..1 fraction of completion.
func show_harvest_bar(root: Vector2) -> void:
	if _harvest_bars.has(root):
		return
	var bar_left: Vector2 = gridToWorld(root)
	var bar_w: float = float(3 * cell_size)
	var bar_y: float = bar_left.y - 16.0
	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 8.0
	bar_bg.default_color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index = 20
	add_child(bar_bg)
	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 8.0
	bar_fill.default_color = Color(0.55, 0.85, 0.4, 1.0)
	bar_fill.z_index = 21
	add_child(bar_fill)
	_harvest_bars[root] = {
		"bg": bar_bg, "fill": bar_fill,
		"bar_x": bar_left.x, "bar_y": bar_y, "bar_w": bar_w,
	}


func update_harvest_bar(root: Vector2, t: float) -> void:
	if not _harvest_bars.has(root):
		return
	var b: Dictionary = _harvest_bars[root]
	var fill := b["fill"] as Line2D
	fill.set_point_position(1, Vector2(float(b["bar_x"]) + float(b["bar_w"]) * clamp(t, 0.0, 1.0), float(b["bar_y"])))


func hide_harvest_bar(root: Vector2) -> void:
	if not _harvest_bars.has(root):
		return
	var b: Dictionary = _harvest_bars[root]
	if is_instance_valid(b["bg"]):
		(b["bg"] as Line2D).queue_free()
	if is_instance_valid(b["fill"]):
		(b["fill"] as Line2D).queue_free()
	_harvest_bars.erase(root)


# Mine progress bar — same shape as harvest, but sized for a single cell.
func show_mine_bar(cell: Vector2) -> void:
	if _mine_bars.has(cell):
		return
	var bar_left: Vector2 = gridToWorld(cell)
	var bar_w: float = float(cell_size)
	var bar_y: float = bar_left.y - 12.0
	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 6.0
	bar_bg.default_color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index = 20
	add_child(bar_bg)
	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 6.0
	bar_fill.default_color = Color(0.85, 0.7, 0.4, 1.0)
	bar_fill.z_index = 21
	add_child(bar_fill)
	_mine_bars[cell] = {
		"bg": bar_bg, "fill": bar_fill,
		"bar_x": bar_left.x, "bar_y": bar_y, "bar_w": bar_w,
	}


func update_mine_bar(cell: Vector2, t: float) -> void:
	if not _mine_bars.has(cell):
		return
	var b: Dictionary = _mine_bars[cell]
	var fill := b["fill"] as Line2D
	fill.set_point_position(1, Vector2(float(b["bar_x"]) + float(b["bar_w"]) * clamp(t, 0.0, 1.0), float(b["bar_y"])))


func hide_mine_bar(cell: Vector2) -> void:
	if not _mine_bars.has(cell):
		return
	var b: Dictionary = _mine_bars[cell]
	if is_instance_valid(b["bg"]):
		(b["bg"] as Line2D).queue_free()
	if is_instance_valid(b["fill"]):
		(b["fill"] as Line2D).queue_free()
	_mine_bars.erase(cell)


# Pin a task indicator above `anchor` showing what the player has queued there
# (harvest / mine / repair / demolish / build). Calling with a different type
# on the same anchor swaps the marker — useful e.g. when a queued repair gets
# overridden by a demolish command on the same wall.
func set_task_marker(anchor: Vector2, task_type: String, world_offset: Vector2 = Vector2(0, -8.0)) -> void:
	clear_task_marker(anchor)
	var m := Node2D.new()
	m.set_script(_TASK_MARKER_SCRIPT)
	add_child(m)
	# Anchor of trees/buildings is the top-left of the footprint, but the
	# marker should hover over the centre-top so it reads as "this object,"
	# not "the cell to the upper-left." Caller can adjust via world_offset.
	m.position = gridToWorld(anchor) + Vector2(cell_size * 0.5, 0.0) + world_offset
	m.z_index = 25
	m.call("setup", task_type)
	task_markers[anchor] = m


func clear_task_marker(anchor: Vector2) -> void:
	if not task_markers.has(anchor):
		return
	var m: Node2D = task_markers[anchor]
	if is_instance_valid(m):
		m.queue_free()
	task_markers.erase(anchor)


func harvest_tree(pos: Vector2) -> Dictionary:
	# Removes the tree at `pos` (or the tree containing `pos`) and returns a
	# drop dict { item_name: count }. The dict is rolled at chop-time so each
	# tree gives slightly different yields. Returns {} if the tree was already
	# gone (e.g., a duplicate harvest task fired).
	var root := get_tree_root(pos)
	if not tree_lights_by_root.has(root):
		return {}
	wood += 1  # legacy global counter (kept for any UI still reading it)
	var light = tree_lights_by_root[root]
	if light != null:
		tree_lights.erase(light)
		light.queue_free()
	tree_lights_by_root.erase(root)
	# Capture the felled tree's texture before freeing the sprite — we'll
	# reuse it as the sapling and again when the tree fully regrows so the
	# regrown tree visually matches the one that was chopped.
	var captured_tex: Texture2D = null
	if tree_sprites.has(root):
		var sprite = tree_sprites[root]
		if sprite is Sprite2D:
			captured_tex = (sprite as Sprite2D).texture
		if sprite is Node:
			sprite.queue_free()
		tree_sprites.erase(root)
	for dx in 3:
		for dy in 3:
			var c: Vector2 = root + Vector2(dx, dy)
			if grid.has(c):
				grid[c].occupier = null
				grid[c].navigable = true
			tree_root.erase(c)
	# Drop saved progress + tear down the visible bar — the tree is gone.
	tree_harvest_progress.erase(root)
	hide_harvest_bar(root)
	clear_task_marker(root)
	# Plant a sapling that grows back over time so chopped tiles aren't
	# permanently barren. Cells stay navigable during regrowth — the sapling
	# is purely visual until it matures.
	if captured_tex != null:
		_start_tree_regrow(root, captured_tex)
	# Roll drops. Driftwood is the primary; fiber and bioluminescent algae are
	# rarer chance drops so the player feels lucky now and then.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drops: Dictionary = {}
	drops["Driftwood Piece"] = rng.randi_range(2, 3)
	if rng.randf() < 0.35:
		drops["Fiber"] = rng.randi_range(1, 2)
	if rng.randf() < 0.15:
		drops["Bioluminescent Algae"] = 1
	# Stat hook for the run summary.
	var main_n: Node = get_parent()
	if main_n != null and main_n.has_method("record_tree_harvested"):
		main_n.record_tree_harvested()
	return drops


# Consume the rock at `cell`. Frees its sprite/shadow/body, opens the cell
# back up to navigation, and returns a rolled drop dict. Returns {} if the
# cell isn't a rock (already mined / never was).
func mine_rock(cell: Vector2) -> Dictionary:
	if not grid.has(cell) or grid[cell].occupier != "Rock":
		return {}
	var entry: Dictionary = rock_nodes.get(cell, {})
	if not entry.is_empty():
		var sprite = entry.get("sprite")
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
		var shadow = entry.get("shadow")
		if shadow != null and is_instance_valid(shadow):
			shadow_sprites.erase(shadow)
			shadow.queue_free()
		var body = entry.get("body")
		if body != null and is_instance_valid(body):
			body.queue_free()
		rock_nodes.erase(cell)
	grid[cell].occupier = null
	grid[cell].navigable = true
	# Clear saved mine progress + visual bar — the rock is consumed.
	rock_mine_progress.erase(cell)
	hide_mine_bar(cell)
	clear_task_marker(cell)
	# Drops: Stone is the bread-and-butter; the metals are nice surprises.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drops: Dictionary = {}
	drops["Stone"] = rng.randi_range(2, 3)
	if rng.randf() < 0.4:
		drops["Iron Chunk"] = rng.randi_range(1, 2)
	if rng.randf() < 0.2:
		drops["Copper Nugget"] = 1
	# 0.20 — middle ground between the original 0.10 (too rare, glass
	# was the bottleneck for Electronics) and 0.30 (made it trivially
	# common). At 20% an average rock cluster yields enough glass for
	# the first Fabricator without grinding a quarry.
	if rng.randf() < 0.2:
		drops["Sand Glass Shard"] = 1
	return drops


# Consume an ore deposit. Same shape as mine_rock, but the drop roll is
# metal-heavy: iron-kind ores yield iron primary + chance copper, copper-kind
# ores flip it. Returns {} if `cell` isn't an ore (already mined / never was).
func mine_ore(cell: Vector2) -> Dictionary:
	if not grid.has(cell) or grid[cell].occupier != "Ore":
		return {}
	var entry: Dictionary = ore_nodes.get(cell, {})
	var kind: String = entry.get("kind", "iron")
	if not entry.is_empty():
		var sprite = entry.get("sprite")
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
		var shadow = entry.get("shadow")
		if shadow != null and is_instance_valid(shadow):
			shadow_sprites.erase(shadow)
			shadow.queue_free()
		var body = entry.get("body")
		if body != null and is_instance_valid(body):
			body.queue_free()
		ore_nodes.erase(cell)
	grid[cell].occupier = null
	grid[cell].navigable = true
	rock_mine_progress.erase(cell)
	hide_mine_bar(cell)
	clear_task_marker(cell)
	# Drop roll: primary is the matching metal (3-4 chunks). Secondary chance
	# of the other metal + small chance of stone fragments.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drops: Dictionary = {}
	if kind == "iron":
		drops["Iron Chunk"] = rng.randi_range(3, 4)
		if rng.randf() < 0.25:
			drops["Copper Nugget"] = 1
	else:
		drops["Copper Nugget"] = rng.randi_range(3, 4)
		if rng.randf() < 0.25:
			drops["Iron Chunk"] = 1
	if rng.randf() < 0.4:
		drops["Stone"] = rng.randi_range(1, 2)
	return drops


# Unified mine entry-point. Dispatches to mine_rock or mine_ore based on
# what's at `cell`. Unit's _tick_mine calls this so it doesn't need to know
# the difference between rocks and ores.
func mine_at(cell: Vector2) -> Dictionary:
	if not grid.has(cell):
		return {}
	var occupier_kind: String = String(grid[cell].occupier)
	var drops: Dictionary = {}
	match occupier_kind:
		"Rock": drops = mine_rock(cell)
		"Ore":  drops = mine_ore(cell)
		_:      return {}
	# Stat + threat hooks — ore counts as heavier ecosystem disturbance
	# than a plain rock, so route through record_ore_mined when applicable.
	if not drops.is_empty():
		var main_n: Node = get_parent()
		if main_n != null:
			if occupier_kind == "Ore" and main_n.has_method("record_ore_mined"):
				main_n.record_ore_mined()
			elif main_n.has_method("record_rock_mined"):
				main_n.record_rock_mined()
	return drops


# Drop a supply pod at `cell` with random useful loot. Functions like a
# SupplyCrate (right-click → loot panel via the existing inspect popup
# flow) but uses the drop-pod art so the player reads it as "incident
# reward" rather than world clutter. Returns true on success.
func spawn_supply_pod(cell: Vector2) -> bool:
	if not grid.has(cell):
		return false
	if grid[cell].occupier != null or water_tiles.has(cell):
		return false
	# Roll loot — leans toward mid/late-game items the player will actually
	# need (electronics, medsupplies) plus ammo / rations.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = [
		["Metal Scrap", rng.randi_range(2, 5)],
		["Electronics", rng.randi_range(1, 2)],
		["Medical Supplies", rng.randi_range(1, 2)],
		["Bandages", rng.randi_range(2, 4)],
		["Rations", rng.randi_range(2, 4)],
		["Revival Injector", 1],
		["Fuel Canister", 1],
	]
	pool.shuffle()
	var inv: Dictionary = {}
	for entry in pool.slice(0, rng.randi_range(3, 5)):
		inv[entry[0]] = entry[1]
	# Sprite — falls back to the supply crate texture if the drop pod art
	# isn't on disk yet, so the event always lands.
	var pod_tex: Texture2D = load("res://art/structures/drop pod realistic.png") as Texture2D
	if pod_tex == null:
		pod_tex = load("res://art/crash_site/supply crate.png") as Texture2D
		if pod_tex == null:
			return false
	grid[cell].occupier = "SupplyCrate"
	grid[cell].navigable = false
	crate_inventories[cell] = inv
	var pod_world: Vector2 = gridToWorld(cell) + Vector2(cell_size * 0.5, cell_size * 0.5)
	var pod_scale: float = float(cell_size * 2) / float(pod_tex.get_width())
	var sp_layer: Node2D = sprite_layer if sprite_layer != null else self
	var shadow := Sprite2D.new()
	shadow.texture = pod_tex
	shadow.position = pod_world + Vector2(10, 14)
	shadow.scale = Vector2(pod_scale * 1.15, pod_scale * 0.5)
	shadow.modulate = Color(0, 0, 0, 0.4)
	sp_layer.add_child(shadow)
	shadow_sprites.append(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = pod_tex
	sprite.scale = Vector2(pod_scale, pod_scale)
	sprite.position = pod_world
	sprite.z_index = int(cell.y) + 1
	sp_layer.add_child(sprite)
	# Build collision body so right-click inspect physics query catches it,
	# matching the SupplyCrate convention. Tag with the SupplyCrate occupier
	# so existing right-click → loot panel handling works without changes.
	# WorldSpawner._alpha_image decompresses VRAM-compressed textures so
	# BitMap.create_from_image_alpha can read them. Without this, the
	# Tier-1 reimport breaks every collision-from-sprite path.
	var img: Image = WorldSpawner._alpha_image(pod_tex)
	var bm := BitMap.new()
	bm.create_from_image_alpha(img)
	var polys := bm.opaque_to_polygons(Rect2(Vector2.ZERO, img.get_size()), 2.0)
	if not polys.is_empty():
		var body := StaticBody2D.new()
		body.position = pod_world
		body.set_meta("occupier", "SupplyCrate")
		body.set_meta("grid_pos", cell)
		var origin := Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
		for poly: PackedVector2Array in polys:
			var cp := CollisionPolygon2D.new()
			var scaled := PackedVector2Array()
			for pt: Vector2 in poly:
				scaled.append((pt - origin) * pod_scale)
			cp.polygon = scaled
			body.add_child(cp)
		sp_layer.add_child(body)
	return true


# Pick up a driftwood pile. Frees its sprite/shadow/body, opens the cell back
# up to navigation, returns a small drop dict (always Driftwood Pieces).
# Returns {} if the cell isn't driftwood (already collected / never was).
func collect_driftwood(cell: Vector2) -> Dictionary:
	if not grid.has(cell) or grid[cell].occupier != "Driftwood":
		return {}
	var entry: Dictionary = driftwood_nodes.get(cell, {})
	if not entry.is_empty():
		var sprite = entry.get("sprite")
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
		var shadow = entry.get("shadow")
		if shadow != null and is_instance_valid(shadow):
			shadow_sprites.erase(shadow)
			shadow.queue_free()
		var body = entry.get("body")
		if body != null and is_instance_valid(body):
			body.queue_free()
		driftwood_nodes.erase(cell)
	grid[cell].occupier = null
	grid[cell].navigable = true
	# Beach loot — quick pickup, modest yield. No fancy chance drops; that's
	# what trees are for.
	var dw_rng := RandomNumberGenerator.new()
	dw_rng.randomize()
	return {"Driftwood Piece": dw_rng.randi_range(2, 3)}


# ── Night cycle ───────────────────────────────────────────────────────────────

func set_tree_light_energy(energy: float) -> void:
	for light in tree_lights:
		light.enabled = energy > 0.001
		light.energy = energy

func set_red_tree_light_energy(energy: float) -> void:
	for light in red_tree_lights:
		light.enabled = energy > 0.001
		light.energy = energy

func set_crab_light_energy(energy: float) -> void:
	# Lights are children of crabs; a dead/freed crab leaves a stale ref here.
	var alive: Array = []
	for light in crab_lights:
		if not is_instance_valid(light):
			continue
		light.enabled = energy > 0.001
		light.energy = energy
		alive.append(light)
	crab_lights = alive

func set_shadow_opacity(sky_brightness: float) -> void:
	for s in shadow_sprites:
		s.modulate.a = 0.35 * sky_brightness


# ── Tile / coordinate helpers ─────────────────────────────────────────────────

func gridToWorld(_pos: Vector2) -> Vector2:
	return _pos * cell_size

func worldToGrid(_pos: Vector2) -> Vector2:
	return floor(_pos / cell_size)

func refreshTile(_pos: Vector2) -> void:
	var data = grid[_pos]
	set_cell(LAYER_FLOOR, _pos, data.floorData.id, data.floorData.coords)
	set_cell(LAYER_BUILDING, _pos)


# ── Placement mode ────────────────────────────────────────────────────────────

func enter_placement_mode(info: Dictionary) -> void:
	placement_mode = true
	placement_info = info

func exit_placement_mode() -> void:
	placement_mode = false
	placement_info = {}
	erase_cell(LAYER_PREVIEW, _preview_pos)
	_preview_pos = Vector2(-999, -999)


func _input(event: InputEvent) -> void:
	if blueprint_mode:
		_handle_blueprint_input(event)
		return
	if not placement_mode:
		return

	var grid_pos = worldToGrid(get_global_mouse_position())

	if event is InputEventMouseMotion:
		_update_preview(grid_pos)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_building(grid_pos)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			exit_placement_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exit_placement_mode()
		get_viewport().set_input_as_handled()


func _update_preview(grid_pos: Vector2) -> void:
	if grid_pos == _preview_pos:
		return
	erase_cell(LAYER_PREVIEW, _preview_pos)
	_preview_pos = grid_pos
	if grid.has(grid_pos):
		set_cell(LAYER_PREVIEW, grid_pos, placement_info.source_id, Vector2i(0, 0))


func _place_building(grid_pos: Vector2) -> void:
	if not grid.has(grid_pos):
		return
	var cell: CellData = grid[grid_pos]
	var layer: int = placement_info.get("layer", LAYER_BUILDING)
	if layer == LAYER_BUILDING:
		if cell.occupier != null:
			return
		set_cell(LAYER_BUILDING, grid_pos, placement_info.source_id, Vector2i(0, 0))
		cell.occupier = placement_info.name
		cell.navigable = placement_info.get("navigable", true)
	elif layer == LAYER_FLOOR:
		set_cell(LAYER_FLOOR, grid_pos, placement_info.source_id, Vector2i(0, 0))


# ── Blueprint mode ────────────────────────────────────────────────────────────

func enter_blueprint_mode(def: Dictionary) -> void:
	# Tearing down any existing preview lets the player switch building types
	# from a still-open Construct panel without leaking ghost sprites.
	if blueprint_mode:
		exit_blueprint_mode()
	blueprint_mode = true
	_bp_def = def
	_bp_orientation = 0
	_bp_preview = Sprite2D.new()
	_bp_preview.texture = load(def.sprite) as Texture2D
	var size: Vector2i = def.size
	_bp_preview.scale = _compute_building_scale(def, _bp_preview.texture, size)
	_bp_preview.modulate = Color(1, 1, 1, 0.5)
	_bp_preview.z_index = 10
	add_child(_bp_preview)


# Compute scale (Vector2) for a building sprite. Modes (set via `scale_axis`):
#   "width"   (default) — sprite WIDTH fits footprint width; height scaled to
#                         match (uniform scale unless `thickness` overrides).
#   "height"            — sprite HEIGHT fits footprint height; width scaled
#                         to match (uniform unless `thickness` overrides).
#   "stretch"           — non-uniform: width AND height fit footprint
#                         independently. Sprite gets distorted to fill the
#                         footprint exactly. Use for L-shape pieces where the
#                         source aspect ratio doesn't match the cell grid.
# `sprite_scale` multiplies both axes. `thickness` < 1.0 squashes only the
# perpendicular axis (no effect when scale_axis = "stretch").
func _compute_building_scale(def: Dictionary, tex: Texture2D, size: Vector2i) -> Vector2:
	var scale_mult: float = float(def.get("sprite_scale", 1.0))
	var thickness: float = float(def.get("thickness", 1.0))
	var axis: String = def.get("scale_axis", "width")
	if axis == "stretch":
		var sx: float = float(size.x * cell_size) / float(tex.get_width()) * scale_mult
		var sy: float = float(size.y * cell_size) / float(tex.get_height()) * scale_mult
		return Vector2(sx, sy)
	var s_long: float
	if axis == "height":
		s_long = float(size.y * cell_size) / float(tex.get_height()) * scale_mult
	else:
		s_long = float(size.x * cell_size) / float(tex.get_width()) * scale_mult
	var s_short: float = s_long * thickness
	if axis == "height":
		return Vector2(s_short, s_long)  # x = thickness direction
	return Vector2(s_long, s_short)       # y = thickness direction


# Position a building sprite within its footprint. Default placement is
# bottom-anchored, horizontally centered (matches fabricator and other tall
# buildings whose top extends above the cell). Defs can override with a
# `sprite_anchor` field — e.g. "left", "right", "top", "bottom", or center —
# to flush the sprite against one edge of the cell. Used by 1x1 edge-anchored
# walls so a row of placements forms a continuous strip along the chosen edge.
func _place_building_sprite(sprite: Sprite2D, grid_pos: Vector2, size: Vector2i, anchor: String = "default") -> void:
	var scaled_w: float = sprite.scale.x * float(sprite.texture.get_width())
	var scaled_h: float = sprite.scale.y * float(sprite.texture.get_height())
	var cell: float = float(cell_size)
	var fp_x: float = grid_pos.x * cell
	var fp_y: float = grid_pos.y * cell
	var fp_w: float = float(size.x) * cell
	var fp_h: float = float(size.y) * cell
	var x: float
	var y: float
	# Horizontal anchor
	if anchor == "left":
		x = fp_x + scaled_w * 0.5
	elif anchor == "right":
		x = fp_x + fp_w - scaled_w * 0.5
	else:
		x = fp_x + fp_w * 0.5  # center (default for top/bottom/center/default)
	# Vertical anchor
	if anchor == "top":
		y = fp_y + scaled_h * 0.5
	elif anchor == "center":
		y = fp_y + fp_h * 0.5
	else:
		# bottom, left, right, default — all anchor the sprite to the
		# footprint's bottom edge (overflow goes upward, fabricator-style).
		y = fp_y + fp_h - scaled_h * 0.5
	sprite.position = Vector2(x, y)


func exit_blueprint_mode() -> void:
	blueprint_mode = false
	_bp_def = {}
	if _bp_preview:
		_bp_preview.queue_free()
		_bp_preview = null


func _handle_blueprint_input(event: InputEvent) -> void:
	var grid_pos := worldToGrid(get_global_mouse_position())
	if event is InputEventMouseMotion and _bp_preview:
		var size: Vector2i = _bp_def.size
		var anchor: String = _bp_def.get("sprite_anchor", "default")
		_place_building_sprite(_bp_preview, grid_pos, size, anchor)
		_bp_preview.flip_h = (_bp_orientation & 1) != 0
		_bp_preview.flip_v = (_bp_orientation & 2) != 0
		_bp_preview.modulate = Color(1, 1, 1, 0.5) if _can_place_blueprint(grid_pos) else Color(1, 0.3, 0.3, 0.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_blueprint_at(grid_pos)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			exit_blueprint_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			exit_blueprint_mode()
		elif event.keycode == KEY_R:
			# Plain defs cycle horizontal flip only (0 → 1 → 0) — left vs.
			# right facing, never upside-down. L-shaped corner pieces (the
			# only defs with a cell_mask) need all four orientations to
			# cover SE/SW/NE/NW corner positions, so they get the full
			# 4-step cycle.
			var corner: bool = _bp_def.has("cell_mask")
			var modulus: int = 4 if corner else 2
			_bp_orientation = (_bp_orientation + 1) % modulus
			if _bp_preview:
				_bp_preview.flip_h = (_bp_orientation & 1) != 0
				_bp_preview.flip_v = (_bp_orientation & 2) != 0
				_bp_preview.modulate = Color(1, 1, 1, 0.5) if _can_place_blueprint(grid_pos) else Color(1, 0.3, 0.3, 0.5)
			get_viewport().set_input_as_handled()
		get_viewport().set_input_as_handled()


# True iff the cell at footprint-local (dx, dy) should be treated as occupied.
# When a def supplies `cell_mask` (a 2D bool array indexed [dy][dx]), only cells
# marked true block placement / consume the tile. Defs without a mask use the
# full rectangular footprint (legacy behavior).
#
# `orientation` is a bitfield (bit 0 = flip_h, bit 1 = flip_v) that remaps the
# (dx, dy) lookup so a flipped corner's L-shape rotates correctly.
func _cell_in_footprint(def: Dictionary, dx: int, dy: int, orientation: int = 0) -> bool:
	var mask: Variant = def.get("cell_mask", null)
	if mask == null:
		return true
	var size: Vector2i = def.size
	var rx: int = dx
	var ry: int = dy
	if (orientation & 1) != 0:
		rx = (size.x - 1) - dx
	if (orientation & 2) != 0:
		ry = (size.y - 1) - dy
	if ry < 0 or ry >= mask.size():
		return true
	var row: Array = mask[ry]
	if rx < 0 or rx >= row.size():
		return true
	return bool(row[rx])


func _can_place_blueprint(grid_pos: Vector2) -> bool:
	var size: Vector2i = _bp_def.size
	for dx in size.x:
		for dy in size.y:
			if not _cell_in_footprint(_bp_def, dx, dy, _bp_orientation):
				continue
			var c := grid_pos + Vector2(dx, dy)
			if not grid.has(c) or grid[c].occupier != null or water_tiles.has(c):
				return false
	return true


func _place_blueprint_at(grid_pos: Vector2) -> void:
	if not _can_place_blueprint(grid_pos):
		return
	var def := _bp_def
	var size: Vector2i = def.size
	var orientation: int = _bp_orientation
	for dx in size.x:
		for dy in size.y:
			if not _cell_in_footprint(def, dx, dy, orientation):
				continue
			var c := grid_pos + Vector2(dx, dy)
			grid[c].occupier = "Blueprint"
			grid[c].navigable = false
	var tex := load(def.sprite) as Texture2D
	var bp_sprite := Sprite2D.new()
	bp_sprite.texture = tex
	bp_sprite.scale = _compute_building_scale(def, tex, size)
	bp_sprite.flip_h = (orientation & 1) != 0
	bp_sprite.flip_v = (orientation & 2) != 0
	var anchor: String = def.get("sprite_anchor", "default")
	_place_building_sprite(bp_sprite, grid_pos, size, anchor)
	bp_sprite.modulate = Color(0.5, 0.8, 1.0, 0.5)
	bp_sprite.z_index = 2
	add_child(bp_sprite)
	blueprints[grid_pos] = {def = def, sprite = bp_sprite, orientation = orientation}
	blueprint_placed.emit(grid_pos, def)
	exit_blueprint_mode()


func complete_blueprint(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var bp: Dictionary = blueprints[grid_pos]
	var def: Dictionary = bp.def
	var size: Vector2i = def.size
	var orientation: int = int(bp.get("orientation", 0))
	var sprite := bp.sprite as Sprite2D
	sprite.modulate = Color(1, 1, 1, 1)
	for dx in size.x:
		for dy in size.y:
			if not _cell_in_footprint(def, dx, dy, orientation):
				continue
			var c := grid_pos + Vector2(dx, dy)
			if grid.has(c):
				grid[c].occupier = def.occupier
				grid[c].navigable = def.navigable
	# Remove progress bar if present.
	cancel_blueprint_build(grid_pos)
	# Add shadow under the completed building (unless the def opts out).
	var shadow_node: Sprite2D = null
	if def.get("shadow", true):
		var tex := sprite.texture
		var s := sprite.scale.x
		shadow_node = Sprite2D.new()
		shadow_node.texture = tex
		shadow_node.scale = Vector2(s * 1.1, s * 0.2)
		shadow_node.position = sprite.position + Vector2(size.x * cell_size * 0.06, size.y * cell_size * 0.72)
		shadow_node.modulate = Color(0, 0, 0, 0.35)
		shadow_node.z_index = sprite.z_index - 1
		add_child(shadow_node)
		shadow_sprites.append(shadow_node)
	# Initialise fabricator state — empty queue + fresh progress bar slot. The
	# UI talks to this directly; the tick advances the front of the queue.
	if def.occupier == "Fabricator":
		fabricators[grid_pos] = {
			"queue": [],          # Array of recipe IDs (strings)
			"progress": 0.0,      # seconds elapsed on the front recipe
			"bar_bg": null,
			"bar_fill": null,
		}
	# Initialise Comm Relay state — idle until a unit starts channeling. The
	# channeler reference is what lets the tick freeze progress when they
	# move away or get downed.
	elif def.occupier == "CommRelay":
		comm_relays[grid_pos] = {
			"channeler": null,
			"progress":  0.0,
			"completed": false,
			"bar_bg":    null,
			"bar_fill":  null,
		}
	# Spawn a PointLight2D for light-emitting defs (Campfire / Floodlight).
	# Anchored to the building sprite's position so it tracks any future
	# repositioning, and stored on the buildings entry so _destroy_building
	# can free it. Defs without `light_color` skip this entirely.
	var light_node: PointLight2D = null
	if def.has("light_color"):
		light_node = PointLight2D.new()
		light_node.texture = _get_building_light_tex()
		light_node.color = def.get("light_color", Color(1, 1, 1))
		light_node.energy = float(def.get("light_energy", 1.0))
		light_node.texture_scale = float(def.get("light_texture_scale", 4.0))
		light_node.blend_mode = PointLight2D.BLEND_MODE_MIX
		# Centre the light on the footprint, slightly above the floor so the
		# glow reads as coming from the lamp body rather than the ground.
		light_node.position = gridToWorld(grid_pos) + Vector2(size.x * cell_size * 0.5, size.y * cell_size * 0.4)
		light_node.z_index = sprite.z_index + 1
		add_child(light_node)
	# Map every footprint cell back to the building anchor regardless of
	# whether the def is destructible — needed so right-click cell lookups
	# (Fabricator → craft panel, etc.) can find the building. Damage-related
	# code still gates on the buildings dict, which is only populated for
	# defs with max_hp below.
	for dx in size.x:
		for dy in size.y:
			if not _cell_in_footprint(def, dx, dy, orientation):
				continue
			cell_to_building[grid_pos + Vector2(dx, dy)] = grid_pos
	# Register the building so it can take damage and eventually be destroyed.
	# Defs without `max_hp` are treated as indestructible (e.g., the fabricator).
	if def.has("max_hp"):
		var max_hp: int = int(def.get("max_hp", 100))
		buildings[grid_pos] = {
			"def": def,
			"sprite": sprite,
			"shadow": shadow_node,
			"light": light_node,
			"hp": max_hp,
			"max_hp": max_hp,
			"hit_flash_t": 0.0,
			"hp_bar_t": 0.0,
			"orientation": orientation,
		}
	blueprints.erase(grid_pos)
	# Build's done — drop any "B" marker. (No-op if the build was finished
	# without going through the manual command path.)
	clear_task_marker(grid_pos)
	# Stat hook for the run summary.
	var main_b: Node = get_parent()
	if main_b != null and main_b.has_method("record_building_built"):
		main_b.record_building_built()


# Restore a fully-built building from save data — bypass the player's
# blueprint-mode flow entirely. Sets up the internal _bp_def state that
# _place_blueprint_at expects, places + completes the blueprint, then
# overwrites HP if the saved value was less than max (a damaged wall
# survives the save/load round-trip with its remaining HP intact).
# Returns true on success, false if the def is unknown.
# ── World serialization (save/load) ──────────────────────────────────────────
#
# Capture the full procedural world state into a JSON-friendly dict so
# the save system can restore exact tree / rock / ore / driftwood / crash
# site / monolith / dirt / ambient-creature placements on reload.
# Player-mutable state (regrowing trees, partial harvest/mine progress,
# crate inventories) is included alongside so the player resumes with
# everything they touched intact.
#
# Texture variants are stored as 0-based indices into the WorldSpawner
# *_TEXTURE_PATHS arrays — saves stay portable across asset shuffles
# only if those arrays don't get reordered (keep them append-only).
func serialize_world() -> Dictionary:
	var out: Dictionary = {}
	# Trees — root cells + texture index by matching the sprite's
	# texture resource_path against the registered tree texture paths.
	var trees_arr: Array = []
	for root in tree_sprites.keys():
		var sprite: Sprite2D = tree_sprites[root] as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var path: String = sprite.texture.resource_path
		var idx: int = WorldSpawner.TREE_TEXTURE_PATHS.find(path)
		if idx < 0:
			idx = 0
		trees_arr.append({"x": int((root as Vector2).x), "y": int((root as Vector2).y), "tex": idx})
	out["trees"] = trees_arr
	# Rocks.
	var rocks_arr: Array = []
	for cell in rock_nodes.keys():
		var entry: Dictionary = rock_nodes[cell]
		var s: Sprite2D = entry.get("sprite") as Sprite2D
		var path: String = ""
		if s != null and s.texture != null:
			path = s.texture.resource_path
		var idx: int = WorldSpawner.ROCK_TEXTURE_PATHS.find(path)
		if idx < 0:
			idx = 0
		rocks_arr.append({"x": int((cell as Vector2).x), "y": int((cell as Vector2).y), "tex": idx})
	out["rocks"] = rocks_arr
	# Ore veins — kind ("iron" / "copper") tracked on the entry.
	var ores_arr: Array = []
	for cell in ore_nodes.keys():
		var entry: Dictionary = ore_nodes[cell]
		ores_arr.append({
			"x": int((cell as Vector2).x), "y": int((cell as Vector2).y),
			"kind": String(entry.get("kind", "iron")),
		})
	out["ores"] = ores_arr
	# Driftwood piles — tex variant by sprite path.
	var dw_arr: Array = []
	for cell in driftwood_nodes.keys():
		var entry: Dictionary = driftwood_nodes[cell]
		var s: Sprite2D = entry.get("sprite") as Sprite2D
		var path: String = ""
		if s != null and s.texture != null:
			path = s.texture.resource_path
		var idx: int = WorldSpawner.DRIFTWOOD_TEXTURE_PATHS.find(path)
		if idx < 0:
			idx = 0
		dw_arr.append({"x": int((cell as Vector2).x), "y": int((cell as Vector2).y), "tex": idx})
	out["driftwood"] = dw_arr
	# Dirt biome — flat list of cells.
	var dirt_arr: Array = []
	for c in dirt_tiles.keys():
		dirt_arr.append([int((c as Vector2).x), int((c as Vector2).y)])
	out["dirt"] = dirt_arr
	# Crash site — ship anchor + hull cells + supply crates with their
	# current inventories. Hull / crate cells are read by walking the
	# main grid for occupier tags so we don't have to maintain a
	# separate registry.
	var hulls: Array = []
	var crates: Array = []
	for cell in grid.keys():
		var occ: Variant = grid[cell].occupier
		if occ == "HullFragment":
			hulls.append({"x": int((cell as Vector2).x), "y": int((cell as Vector2).y)})
		elif occ == "SupplyCrate":
			var inv: Dictionary = crate_inventories.get(cell, {}) as Dictionary
			crates.append({
				"x": int((cell as Vector2).x), "y": int((cell as Vector2).y),
				"inv": inv.duplicate(true),
			})
	out["crash_site"] = {
		"x": int(crash_site_pos.x), "y": int(crash_site_pos.y),
		"hulls": hulls,
		"crates": crates,
		"ship_inventory": ship_inventory.duplicate(true),
	}
	# Monolith — single-cell anchor.
	out["monolith"] = {"x": int(monolith_pos.x), "y": int(monolith_pos.y)}
	# Ambient creatures — live Crab nodes (peacetime only). Wave and
	# event-spawned aggressive creatures are filtered out because the
	# wave state resets to PEACE on load, and leaving stragglers behind
	# as wandering ambient would be confusing.
	var creatures_arr: Array = []
	for u in crabs:
		if not is_instance_valid(u):
			continue
		var crab: Crab = u as Crab
		if crab.aggressive:
			continue
		# Reverse-lookup the def_key from the textures since the Crab
		# class doesn't store it directly. Falls back to alien_crab.
		var def_key: String = "alien_crab"
		if crab._tex_down != null:
			var dpath: String = crab._tex_down.resource_path
			for k in CreatureDefs.DEFS:
				if String(CreatureDefs.DEFS[k].get("tex_down", "")) == dpath:
					def_key = k
					break
		creatures_arr.append({
			"def_key": def_key,
			"pos_x": crab.position.x,
			"pos_y": crab.position.y,
			"hp": int(crab.hp),
			"y_min": int(crab.shore_y_min),
			"y_max": int(crab.shore_y_max),
		})
	out["creatures"] = creatures_arr
	# Player-mutable progress dicts — keys are Vector2, flatten to
	# {x_y: float} so JSON round-trips cleanly.
	out["regrowing_trees"] = _serialize_regrowing_trees()
	out["harvest_progress"] = _serialize_progress_dict(tree_harvest_progress)
	out["mine_progress"] = _serialize_progress_dict(rock_mine_progress)
	return out


func _serialize_progress_dict(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		out.append({"x": int((k as Vector2).x), "y": int((k as Vector2).y), "t": float(d[k])})
	return out


func _serialize_regrowing_trees() -> Array:
	var out: Array = []
	for root in regrowing_trees.keys():
		var entry: Dictionary = regrowing_trees[root]
		var tex: Texture2D = entry.get("texture")
		var tex_path: String = tex.resource_path if tex != null else ""
		out.append({
			"x": int((root as Vector2).x),
			"y": int((root as Vector2).y),
			"elapsed": float(entry.get("elapsed", 0.0)),
			"tex": tex_path,
			"full_scale": float(entry.get("full_scale", 1.0)),
		})
	return out


# Inverse of serialize_world. Called by Main._ready when a save is
# being loaded — replaces every WorldSpawner.spawn_* call. Caller is
# responsible for ensuring grid cells are generated and water/sprite
# layers are set up before this fires (Main._ready does both).
func apply_world(data: Dictionary) -> void:
	# Dirt tiles dict must be populated BEFORE restore_dirt runs since
	# restore_dirt reads neighbours from the dict to compute the fade
	# shader masks. Also needed before restore_trees so tree placement
	# checks that already-dirt cells still flag correctly.
	for c_v: Variant in data.get("dirt", []):
		var arr: Array = c_v as Array
		dirt_tiles[Vector2(int(arr[0]), int(arr[1]))] = true
	# Crash site first — its 4x4 ship + hull cells + crates set
	# occupier = "CrashedShip" / "HullFragment" / "SupplyCrate" so
	# downstream restores skip those cells.
	var cs: Dictionary = data.get("crash_site", {})
	if not cs.is_empty():
		var ship_anchor: Vector2 = Vector2(int(cs.get("x", -1)), int(cs.get("y", -1)))
		WorldSpawner.restore_crash_site(self, ship_anchor, cs.get("hulls", []), cs.get("crates", []), cs.get("ship_inventory", {}))
	# Monolith.
	var m: Dictionary = data.get("monolith", {})
	var m_anchor: Vector2 = Vector2(int(m.get("x", -1)), int(m.get("y", -1)))
	if m_anchor != Vector2(-1, -1):
		WorldSpawner.restore_monolith(self, m_anchor)
	# Trees + dirt visuals — dirt sprites need the dirt_tiles dict
	# populated above.
	WorldSpawner.restore_dirt(self)
	WorldSpawner.restore_trees(self, data.get("trees", []))
	# Rocks / ores / driftwood.
	WorldSpawner.restore_rocks(self, data.get("rocks", []))
	WorldSpawner.restore_ores(self, data.get("ores", []))
	WorldSpawner.restore_driftwood(self, data.get("driftwood", []))
	# Ambient creatures.
	WorldSpawner.restore_ambient_creatures(self, data.get("creatures", []))
	# Player-mutable progress dicts — written directly back into the
	# Grid's tracking state. Regrowing trees re-create their sapling
	# sprite via the existing harvest_tree path's continuation logic
	# below.
	for entry_v: Variant in data.get("harvest_progress", []):
		var e: Dictionary = entry_v as Dictionary
		tree_harvest_progress[Vector2(int(e.x), int(e.y))] = float(e.get("t", 0.0))
	for entry_v: Variant in data.get("mine_progress", []):
		var e: Dictionary = entry_v as Dictionary
		rock_mine_progress[Vector2(int(e.x), int(e.y))] = float(e.get("t", 0.0))
	# Regrowing trees — push a fresh sapling sprite at the saved
	# elapsed time. Sapling visuals are derived from the saved texture
	# path so a regrowth interrupted at 80% reads as a near-full
	# sapling on reload.
	for entry_v: Variant in data.get("regrowing_trees", []):
		var e: Dictionary = entry_v as Dictionary
		var root: Vector2 = Vector2(int(e.x), int(e.y))
		var tex_path: String = String(e.get("tex", ""))
		var tex: Texture2D = load(tex_path) as Texture2D if tex_path != "" else null
		_restore_regrowing_tree(root, float(e.get("elapsed", 0.0)), tex, float(e.get("full_scale", 1.0)))


# Helper: spawn a sapling sprite for a tree mid-regrow, scaled to its
# current progress. Mirrors what harvest_tree does when it kicks off a
# regrowth, but starting from a saved elapsed time.
func _restore_regrowing_tree(root: Vector2, elapsed: float, texture: Texture2D, full_scale: float) -> void:
	if texture == null:
		return
	var sp: Node2D = sprite_layer if sprite_layer != null else self
	var centre_pos: Vector2 = gridToWorld(root) + Vector2(cell_size * 1.5, cell_size * 1.5)
	var sapling := Sprite2D.new()
	sapling.texture = texture
	sapling.position = centre_pos
	sapling.z_index = int(root.y) + 2
	# Tree-regrow logic in _tick_tree_regrowth lerps scale 0 → full_scale
	# over REGROW_DURATION seconds; replicate the same curve here.
	var t: float = clamp(elapsed / REGROW_DURATION, 0.0, 1.0)
	sapling.scale = Vector2(full_scale * t, full_scale * t)
	sp.add_child(sapling)
	regrowing_trees[root] = {
		"elapsed": elapsed,
		"texture": texture,
		"sapling": sapling,
		"full_scale": full_scale,
	}


func restore_building(grid_pos: Vector2, def_key: String, hp_value: int = -1) -> bool:
	if not BuildingDefs.DEFS.has(def_key):
		return false
	var def: Dictionary = BuildingDefs.DEFS[def_key]
	# Stash + restore _bp_def so we don't poison an in-flight player
	# blueprint placement (defensive — restore_building should only run
	# during scene _ready, but the stash is cheap and pre-empts subtle
	# bugs if it ever gets called mid-run).
	var prev_def: Variant = _bp_def
	var prev_orientation: int = _bp_orientation
	_bp_def = def
	_bp_orientation = 0
	_place_blueprint_at(grid_pos)
	_bp_def = prev_def
	_bp_orientation = prev_orientation
	# _place_blueprint_at can fail silently (cell occupied etc.) — guard
	# the completion call.
	if not blueprints.has(grid_pos):
		return false
	complete_blueprint(grid_pos)
	if hp_value > 0 and buildings.has(grid_pos):
		buildings[grid_pos].hp = min(hp_value, int(buildings[grid_pos].max_hp))
	return true


# Returns [{ world_pos, radius }] for every active light-emitting building
# (campfires, floodlights). Used by Unit._can_see and Main._update_fog so
# player-built light sources reveal enemies the same way unit flashlights
# do — if the lamp can shine on it, the team can react to it.
func get_building_lights() -> Array:
	var out: Array = []
	for anchor in buildings.keys():
		var b: Dictionary = buildings[anchor]
		var light = b.get("light")
		if light == null or not is_instance_valid(light):
			continue
		var tex: Texture2D = (light as PointLight2D).texture
		if tex == null:
			continue
		# Effective radius = half the rendered texture extent. The radial
		# gradient fades toward this edge, so beyond it the illumination
		# is effectively zero.
		var radius: float = float((light as PointLight2D).texture_scale) * float(tex.get_width()) * 0.5
		out.append({
			"world_pos": (light as PointLight2D).global_position,
			"radius":    radius,
		})
	return out


# Lazily-built radial gradient texture shared by every building light.
# 128x128 is plenty since PointLight2D scales it via texture_scale; building
# it once avoids per-spawn overhead.
var _building_light_tex: Texture2D = null

func _get_building_light_tex() -> Texture2D:
	if _building_light_tex != null:
		return _building_light_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_building_light_tex = tex
	return _building_light_tex


# ── Building damage / destruction ─────────────────────────────────────────────

# Called by anything attacking a wall cell. Damage pools across the whole
# building (not per-cell), so a 3-cell H wall has one shared HP track.
# Returns true if a wall was damaged at this cell.
func damage_wall_at(cell: Vector2, amount: int) -> bool:
	if not cell_to_building.has(cell):
		return false
	var anchor: Vector2 = cell_to_building[cell]
	if not buildings.has(anchor):
		return false
	var b: Dictionary = buildings[anchor]
	if b.hp <= 0:
		return false
	b.hp -= amount
	b.hit_flash_t = _BUILDING_HIT_FLASH_DURATION
	b.hp_bar_t = _BUILDING_HP_BAR_DURATION
	if b.hp <= 0:
		_destroy_building(anchor)
	queue_redraw()
	return true


# True iff this cell currently has a wall on it that's still alive.
func is_wall_at(cell: Vector2) -> bool:
	return cell_to_building.has(cell) and buildings.has(cell_to_building[cell])


# Damage a building by anchor (vs damage_wall_at which keys by cell). Used by
# the demolish task — the unit knows the anchor it was assigned, no need to
# resolve back through cell_to_building. Returns true if HP changed.
func damage_building(anchor: Vector2, amount: int) -> bool:
	if not buildings.has(anchor):
		return false
	var b: Dictionary = buildings[anchor]
	if b.hp <= 0:
		return false
	b.hp = max(0, int(b.hp) - amount)
	b.hit_flash_t = _BUILDING_HIT_FLASH_DURATION
	b.hp_bar_t = _BUILDING_HP_BAR_DURATION
	queue_redraw()
	if b.hp <= 0:
		_destroy_building(anchor)
	return true


# Restore HP to a building, capped at max_hp. Returns the actual amount healed
# (0 if already at full HP or anchor invalid). Triggers the HP-bar fade timer
# so the player sees the bar refilling.
func repair_wall_at(anchor: Vector2, amount: int) -> int:
	if not buildings.has(anchor):
		return 0
	var b: Dictionary = buildings[anchor]
	if b.hp >= b.max_hp:
		return 0
	var before: int = int(b.hp)
	b.hp = min(int(b.hp) + amount, int(b.max_hp))
	b.hp_bar_t = _BUILDING_HP_BAR_DURATION
	queue_redraw()
	return int(b.hp) - before


func _destroy_building(anchor: Vector2) -> void:
	if not buildings.has(anchor):
		return
	var b: Dictionary = buildings[anchor]
	var def: Dictionary = b.def
	var size: Vector2i = def.size
	var orientation: int = int(b.get("orientation", 0))
	# Free sprite + shadow + light (if any).
	if b.sprite != null and is_instance_valid(b.sprite):
		(b.sprite as Sprite2D).queue_free()
	if b.shadow != null and is_instance_valid(b.shadow):
		(b.shadow as Sprite2D).queue_free()
		shadow_sprites.erase(b.shadow)
	var light_ref = b.get("light")
	if light_ref != null and is_instance_valid(light_ref):
		(light_ref as PointLight2D).queue_free()
	# Reopen the cells: clear occupier, restore navigability. Honor the
	# stored orientation so flipped corner pieces clear the correct L-shape.
	for dx in size.x:
		for dy in size.y:
			if not _cell_in_footprint(def, dx, dy, orientation):
				continue
			var c: Vector2 = anchor + Vector2(dx, dy)
			if grid.has(c):
				grid[c].occupier = null
				grid[c].navigable = true
			cell_to_building.erase(c)
	buildings.erase(anchor)
	# Drop any repair / demolish marker — the building is gone either way.
	clear_task_marker(anchor)


func _tick_buildings(delta: float) -> void:
	if buildings.is_empty():
		return
	var any_redraw: bool = false
	for anchor in buildings:
		var b: Dictionary = buildings[anchor]
		if b.hit_flash_t > 0.0:
			b.hit_flash_t -= delta
			if is_instance_valid(b.sprite):
				if b.hit_flash_t <= 0.0:
					(b.sprite as Sprite2D).modulate = Color(1, 1, 1, 1)
				else:
					var k: float = clamp(b.hit_flash_t / _BUILDING_HIT_FLASH_DURATION, 0.0, 1.0)
					(b.sprite as Sprite2D).modulate = Color(1.0, lerp(1.0, 0.3, k), lerp(1.0, 0.3, k), 1.0)
		if b.hp_bar_t > 0.0:
			b.hp_bar_t -= delta
			any_redraw = true
	if any_redraw:
		queue_redraw()


# Returns [{pos: Vector2, inv: Dictionary}] for ship + all non-empty crates.
func get_inventory_sources() -> Array:
	var sources: Array = []
	if not ship_inventory.is_empty():
		sources.append({"pos": crash_site_pos, "inv": ship_inventory})
	for pos in crate_inventories:
		var inv: Dictionary = crate_inventories[pos]
		if not inv.is_empty():
			sources.append({"pos": pos, "inv": inv})
	return sources


# Remove items from the inventory at source_pos (ship or crate).
# Takes as much as available for each item; doesn't error if short.
func take_from_inventory(source_pos: Vector2, items: Dictionary) -> void:
	var inv: Dictionary
	if source_pos == crash_site_pos:
		inv = ship_inventory
	elif crate_inventories.has(source_pos):
		inv = crate_inventories[source_pos]
	else:
		return
	for item in items:
		var amount: int = items[item]
		if inv.has(item):
			inv[item] = max(0, inv[item] - amount)
			if inv[item] == 0:
				inv.erase(item)


# Shows a progress bar above the blueprint while it's being built.
func start_blueprint_build(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var def: Dictionary = blueprints[grid_pos].def
	var size: Vector2i = def.size
	var bar_left := gridToWorld(grid_pos)
	var bar_w := float(size.x * cell_size)
	var bar_y := bar_left.y - 16.0

	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 10.0
	bar_bg.default_color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index = 20
	add_child(bar_bg)

	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 10.0
	bar_fill.default_color = Color(0.2, 0.85, 0.3, 1.0)
	bar_fill.z_index = 21
	add_child(bar_fill)

	blueprints[grid_pos]["bar_bg"]   = bar_bg
	blueprints[grid_pos]["bar_fill"] = bar_fill
	blueprints[grid_pos]["bar_x"]    = bar_left.x
	blueprints[grid_pos]["bar_y"]    = bar_y
	blueprints[grid_pos]["bar_w"]    = bar_w


func set_blueprint_progress(grid_pos: Vector2, t: float) -> void:
	if not blueprints.has(grid_pos) or not blueprints[grid_pos].has("bar_fill"):
		return
	var bp: Dictionary = blueprints[grid_pos]
	var fill := bp["bar_fill"] as Line2D
	fill.set_point_position(1, Vector2(float(bp["bar_x"]) + float(bp["bar_w"]) * t, float(bp["bar_y"])))


func cancel_blueprint_build(grid_pos: Vector2) -> void:
	if not blueprints.has(grid_pos):
		return
	var bp: Dictionary = blueprints[grid_pos]
	if bp.has("bar_bg"):
		(bp["bar_bg"] as Line2D).queue_free()
		bp.erase("bar_bg")
	if bp.has("bar_fill"):
		(bp["bar_fill"] as Line2D).queue_free()
		bp.erase("bar_fill")


# Permanently remove a blueprint and return the materials that were committed
# to it (empty dict if the build hadn't paid yet). Caller is responsible for
# depositing the refund into a unit's inventory and showing UI feedback.
func cancel_blueprint(grid_pos: Vector2) -> Dictionary:
	if not blueprints.has(grid_pos):
		return {}
	var bp: Dictionary = blueprints[grid_pos]
	var refund: Dictionary = (bp.get("spent_cost", {}) as Dictionary).duplicate()
	cancel_blueprint_build(grid_pos)
	var sprite = bp.get("sprite")
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	blueprints.erase(grid_pos)
	clear_task_marker(grid_pos)
	return refund


# True iff `cell` lies inside any active blueprint's footprint. Returns the
# anchor (top-left) of that blueprint, or Vector2(-1,-1) if none.
func blueprint_at_cell(cell: Vector2) -> Vector2:
	for anchor in blueprints.keys():
		var bp: Dictionary = blueprints[anchor]
		var def: Dictionary = bp.def
		var size: Vector2i = def.size
		var orientation: int = int(bp.get("orientation", 0))
		for dx in size.x:
			for dy in size.y:
				if not _cell_in_footprint(def, dx, dy, orientation):
					continue
				if anchor + Vector2(dx, dy) == cell:
					return anchor
	return Vector2(-1, -1)


func get_blueprint_adjacent(grid_pos: Vector2) -> Array:
	if not blueprints.has(grid_pos):
		return []
	var size: Vector2i = blueprints[grid_pos].def.size
	var result: Array = []
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue
			var c := grid_pos + Vector2(dx, dy)
			if grid.has(c) and grid[c].navigable:
				result.append(c)
	return result


# ── Water tiles ───────────────────────────────────────────────────────────────

func place_water_tile(pos: Vector2, variant: WaterTile.Variant = WaterTile.Variant.SHALLOW) -> WaterTile:
	erase_water_tile(pos)
	var tile: WaterTile = _WATER_TILE_SCENE.instantiate()
	tile.position = gridToWorld(pos)
	tile.variant = variant
	$Water.add_child(tile)
	water_tiles[pos] = tile
	return tile


func erase_water_tile(pos: Vector2) -> void:
	if water_tiles.has(pos):
		var entry = water_tiles[pos]
		if entry is Node:
			entry.queue_free()
		water_tiles.erase(pos)


func _ready() -> void:
	# Ensure the lily pad tree tile is defined as 2x2 in the atlas.
	var src := tile_set.get_source(SOURCE_LILY_TREE) as TileSetAtlasSource
	if not src.has_tile(Vector2i(0, 0)):
		src.create_tile(Vector2i(0, 0), Vector2i(3, 3))
	elif src.get_tile_size_in_atlas(Vector2i(0, 0)) != Vector2i(3, 3):
		src.remove_tile(Vector2i(0, 0))
		src.create_tile(Vector2i(0, 0), Vector2i(3, 3))

func _process(delta: float) -> void:
	_tick_buildings(delta)
	_tick_fabricators(delta)
	_tick_comm_relays(delta)
	_tick_tree_regrowth(delta)


# Player kicks off a channel by right-clicking a Comm Relay Antenna. The
# Unit walks adjacent and assigns itself as the relay's channeler. The
# tick below advances progress while the channeler is still adjacent +
# alive + non-downed; on completion, WaveManager.trigger_evac_from_relay()
# fires and the relay is marked completed (one-shot).
func start_relay_channel(anchor: Vector2, channeler: Unit) -> bool:
	if not comm_relays.has(anchor):
		return false
	var relay: Dictionary = comm_relays[anchor]
	if relay.get("completed", false):
		return false
	# Replace any existing channeler — the new one took over.
	relay.channeler = channeler
	_show_relay_bar(anchor)
	_update_relay_bar(anchor, clamp(float(relay.progress) / RELAY_CHANNEL_DURATION, 0.0, 1.0))
	return true


# Releases the channeler slot without resetting progress. Called when the
# channeler moves / dies / goes down — the next worker can resume from
# wherever the bar was when the previous one quit.
func release_relay_channeler(anchor: Vector2, channeler: Unit) -> void:
	if not comm_relays.has(anchor):
		return
	var relay: Dictionary = comm_relays[anchor]
	if relay.get("channeler") == channeler:
		relay.channeler = null


func _tick_comm_relays(delta: float) -> void:
	if comm_relays.is_empty():
		return
	for anchor in comm_relays.keys():
		var relay: Dictionary = comm_relays[anchor]
		if relay.get("completed", false):
			continue
		var ch = relay.get("channeler")
		# No active channeler → freeze progress + hide bar (saved progress
		# stays in the dict so a later channeler picks up where we left off).
		if ch == null or not is_instance_valid(ch) or (ch as Unit).is_dead() or (ch as Unit).is_downed:
			if ch != null:
				relay.channeler = null
			_hide_relay_bar(anchor)
			continue
		# Channeler must stay adjacent — wandering off pauses progress.
		if not _channeler_adjacent_to_relay(ch as Unit, anchor):
			relay.channeler = null
			_hide_relay_bar(anchor)
			continue
		_show_relay_bar(anchor)
		relay.progress += delta
		var t: float = clamp(float(relay.progress) / RELAY_CHANNEL_DURATION, 0.0, 1.0)
		_update_relay_bar(anchor, t)
		# Light harassment ticker — spawns a single ambient-tier creature
		# (alien crab / tide crawler / shore stalker) at a random map edge
		# every RELAY_HARASS_INTERVAL seconds while the channel runs.
		# Initialised lazily so older saved relays without the field still
		# work; ticks down only while the channel is actively progressing
		# (paused branches above already `continue` past this code).
		var harass_t: float = float(relay.get("harass_t", RELAY_HARASS_INITIAL_DELAY))
		harass_t -= delta
		if harass_t <= 0.0:
			var main_h: Node = get_parent()
			if main_h != null and main_h.wave_manager != null and main_h.wave_manager.has_method("spawn_harassment_creature"):
				main_h.wave_manager.spawn_harassment_creature()
			harass_t = RELAY_HARASS_INTERVAL
		relay.harass_t = harass_t
		if relay.progress >= RELAY_CHANNEL_DURATION:
			relay.completed = true
			_hide_relay_bar(anchor)
			# Free the channeler unit's task target so they can move again.
			(ch as Unit).clear_relay_target()
			# Tell the wave manager to start the EVAC phase.
			var main_node: Node = get_parent()
			if main_node != null and main_node.wave_manager != null:
				if main_node.wave_manager.has_method("trigger_evac_from_relay"):
					main_node.wave_manager.trigger_evac_from_relay()


# A unit counts as "channeling" when their grid cell touches any cell of
# the antenna's 2x2 footprint (8-neighborhood including the cells inside
# the footprint, which the unit can't physically be on but the check is
# inclusive for safety).
func _channeler_adjacent_to_relay(unit_node: Unit, anchor: Vector2) -> bool:
	var ucell: Vector2 = unit_node.get_grid_pos()
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			if anchor + Vector2(dx, dy) == ucell:
				return true
	return false


# Cyan progress bar above the antenna while channeling. Reuses the same
# Line2D pattern as harvest / mine / fabricator bars.
func _show_relay_bar(anchor: Vector2) -> void:
	if not comm_relays.has(anchor):
		return
	var relay: Dictionary = comm_relays[anchor]
	if relay.bar_bg != null and is_instance_valid(relay.bar_bg):
		return
	var bar_left: Vector2 = gridToWorld(anchor)
	var bar_w: float = float(2 * cell_size)
	var bar_y: float = bar_left.y - 18.0
	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 10.0
	bar_bg.default_color = Color(0.05, 0.10, 0.15, 0.90)
	bar_bg.z_index = 22
	add_child(bar_bg)
	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 10.0
	bar_fill.default_color = Color(0.40, 0.85, 1.00, 1.0)
	bar_fill.z_index = 23
	add_child(bar_fill)
	relay.bar_bg = bar_bg
	relay.bar_fill = bar_fill
	relay["bar_x"] = bar_left.x
	relay["bar_y"] = bar_y
	relay["bar_w"] = bar_w


func _update_relay_bar(anchor: Vector2, t: float) -> void:
	if not comm_relays.has(anchor):
		return
	var relay: Dictionary = comm_relays[anchor]
	if relay.bar_fill == null or not is_instance_valid(relay.bar_fill):
		return
	(relay.bar_fill as Line2D).set_point_position(1, Vector2(float(relay.bar_x) + float(relay.bar_w) * t, float(relay.bar_y)))


func _hide_relay_bar(anchor: Vector2) -> void:
	if not comm_relays.has(anchor):
		return
	var relay: Dictionary = comm_relays[anchor]
	if relay.bar_bg != null and is_instance_valid(relay.bar_bg):
		(relay.bar_bg as Line2D).queue_free()
	if relay.bar_fill != null and is_instance_valid(relay.bar_fill):
		(relay.bar_fill as Line2D).queue_free()
	relay.bar_bg = null
	relay.bar_fill = null


# Plant a sapling at `root` using the chopped tree's texture. Cells stay
# open to navigation during regrowth — the sapling is purely visual until
# it matures, at which point WorldSpawner.spawn_one_tree restores everything.
func _start_tree_regrow(root: Vector2, texture: Texture2D) -> void:
	# If somehow already regrowing here (shouldn't happen — harvest_tree gates
	# on tree_lights_by_root), tear the old sapling down first.
	if regrowing_trees.has(root):
		var existing = regrowing_trees[root].get("sapling")
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
	var sp: Node2D = sprite_layer if sprite_layer != null else self
	var centre_pos: Vector2 = gridToWorld(root) + Vector2(cell_size * 1.5, cell_size * 1.5)
	# Full-grown scale matches WorldSpawner.spawn_one_tree (3 cells wide).
	var full_s: float = float(cell_size * 3) / float(texture.get_width())
	var sapling := Sprite2D.new()
	sapling.texture = texture
	sapling.position = centre_pos
	sapling.scale = Vector2(full_s * REGROW_START_SCALE, full_s * REGROW_START_SCALE)
	# Tint slightly desaturated + greener so saplings read as "young growth"
	# rather than a tiny full tree.
	sapling.modulate = Color(0.85, 1.0, 0.85, 0.95)
	sapling.z_index = int(root.y) + 2
	sp.add_child(sapling)
	regrowing_trees[root] = {
		"elapsed": 0.0,
		"texture": texture,
		"sapling": sapling,
		"full_scale": full_s,
	}


func _tick_tree_regrowth(delta: float) -> void:
	if regrowing_trees.is_empty():
		return
	var matured: Array = []
	for root in regrowing_trees.keys():
		var entry: Dictionary = regrowing_trees[root]
		entry.elapsed += delta
		var t: float = clamp(entry.elapsed / REGROW_DURATION, 0.0, 1.0)
		var s_factor: float = lerp(REGROW_START_SCALE, 1.0, t)
		var sapling = entry.get("sapling")
		if sapling != null and is_instance_valid(sapling):
			var full_s: float = float(entry.get("full_scale", 1.0))
			(sapling as Sprite2D).scale = Vector2(full_s * s_factor, full_s * s_factor)
			# Fade green tint back to neutral as it matures.
			(sapling as Sprite2D).modulate = Color(1, 1, 1).lerp(Color(0.85, 1.0, 0.85, 0.95), 1.0 - t)
		if entry.elapsed >= REGROW_DURATION:
			matured.append(root)
	for root in matured:
		_finish_tree_regrow(root)


# True iff `cell` is inside the 3x3 footprint of any tree currently in the
# regrowing dict. Used by Main's right-click handler so a click on a sapling
# can post a "still regrowing" banner instead of silently no-op'ing.
# Returns the regrowing tree's root cell on hit (Vector2(-1,-1) on miss) +
# the elapsed/total seconds so the UI can show progress.
func regrowing_tree_at(cell: Vector2) -> Dictionary:
	for root in regrowing_trees.keys():
		var entry: Dictionary = regrowing_trees[root]
		var dx: float = cell.x - root.x
		var dy: float = cell.y - root.y
		if dx >= 0.0 and dx < 3.0 and dy >= 0.0 and dy < 3.0:
			return {
				"root":     root,
				"elapsed":  float(entry.get("elapsed", 0.0)),
				"duration": REGROW_DURATION,
			}
	return {}


func _finish_tree_regrow(root: Vector2) -> void:
	if not regrowing_trees.has(root):
		return
	var entry: Dictionary = regrowing_trees[root]
	var sapling = entry.get("sapling")
	if sapling != null and is_instance_valid(sapling):
		sapling.queue_free()
	var tex = entry.get("texture")
	regrowing_trees.erase(root)
	if tex != null:
		WorldSpawner.spawn_one_tree(self, root, tex)


# Add a recipe to a fabricator's queue. Pulls the inputs from the team pool
# immediately (failure leaves inventories untouched and returns false). The
# queue is FIFO — the fabricator chews through it in order.
func queue_craft(anchor: Vector2, recipe_id: String) -> bool:
	if not fabricators.has(anchor):
		return false
	var recipe: Dictionary = _CRAFT_RECIPES.find(recipe_id)
	if recipe.is_empty():
		return false
	var main_node: Node = get_parent()
	if main_node == null or not main_node.has_method("pull_shared_resources"):
		return false
	var inputs: Dictionary = recipe.inputs
	if not main_node.pull_shared_resources(inputs):
		return false
	fabricators[anchor].queue.append(recipe_id)
	return true


# Cancel the entry at index `idx` in the fabricator's queue and refund its
# inputs to the closest live unit. Index 0 (the in-progress craft) refunds
# only the inputs spent — partial-progress time is forfeit.
func cancel_craft(anchor: Vector2, idx: int) -> bool:
	if not fabricators.has(anchor):
		return false
	var fab: Dictionary = fabricators[anchor]
	var queue: Array = fab.queue
	if idx < 0 or idx >= queue.size():
		return false
	var recipe_id: String = queue[idx]
	var recipe: Dictionary = _CRAFT_RECIPES.find(recipe_id)
	queue.remove_at(idx)
	if idx == 0:
		fab.progress = 0.0
		_hide_fabricator_bar(anchor)
	if recipe.is_empty():
		return true
	# Refund: deposit the recipe's inputs into the nearest live unit so the
	# cancellation isn't a stealth tax. Loot toast confirms the refund.
	_deposit_to_team(anchor, recipe.inputs)
	return true


func _tick_fabricators(delta: float) -> void:
	if fabricators.is_empty():
		return
	for anchor in fabricators.keys():
		var fab: Dictionary = fabricators[anchor]
		var queue: Array = fab.queue
		if queue.is_empty():
			# Queue drained — make sure no stale bar lingers.
			_hide_fabricator_bar(anchor)
			continue
		var recipe: Dictionary = _CRAFT_RECIPES.find(queue[0])
		if recipe.is_empty():
			queue.pop_front()
			continue
		var total: float = float(recipe.get("time", 1.0))
		# Ensure the progress bar exists once we have an active craft.
		_show_fabricator_bar(anchor)
		fab.progress += delta
		_update_fabricator_bar(anchor, clamp(fab.progress / total, 0.0, 1.0))
		if fab.progress >= total:
			# Recipe done — deposit output to team, drop the recipe from the
			# queue, reset progress for the next entry.
			_deposit_to_team(anchor, recipe.output)
			# Craft-complete chime, played at the fabricator's world centre
			# so the player can localize which fabricator just produced
			# something when several are running. _deposit_to_team also
			# fires the regular ITEM_PICKUP one-shot (via notify_loot_batch),
			# so the chime layers on top of the pickup sound for a clear
			# "thing finished" beat.
			var fab_world: Vector2 = (anchor as Vector2) * float(cell_size) + Vector2(cell_size, cell_size * 0.5)
			AudioManager.play_2d(Sounds.CRAFT_COMPLETE, fab_world)
			# Stat hook for the run summary.
			var main_n: Node = get_parent()
			if main_n != null and main_n.has_method("record_item_crafted"):
				main_n.record_item_crafted()
			# Quest-tracker hook: mark Comm Relay Module as crafted so the
			# objective panel only ticks step 2 from a real craft (not from
			# Free Mats / drops). Stays true even after the module is
			# consumed for the antenna build.
			if main_n != null and String(recipe.get("id", "")) == "make_comm_relay_module":
				main_n.relay_module_crafted = true
			queue.pop_front()
			fab.progress = 0.0
			if queue.is_empty():
				_hide_fabricator_bar(anchor)


# Drop a dict of items into the closest live unit's inventory and pop a loot
# toast above the fabricator. Used for both crafted output and refunds.
func _deposit_to_team(anchor: Vector2, items: Dictionary) -> void:
	if items.is_empty():
		return
	var main_node: Node = get_parent()
	if main_node == null:
		return
	var fab_world: Vector2 = gridToWorld(anchor) + Vector2(cell_size * 0.5, cell_size * 0.5)
	var recipient: Unit = null
	var best_d: float = INF
	for u in main_node.all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if unit_node.is_dead() or unit_node.is_downed or unit_node.evacuated:
			continue
		var d: float = unit_node.global_position.distance_to(fab_world)
		if d < best_d:
			best_d = d
			recipient = unit_node
	if recipient != null:
		for item_name: String in items.keys():
			# Overflow-aware deposit: if the closest unit is full, cascade
			# to teammates with bag space. Same helper used by harvest /
			# mine / loot drops so fabricator output respects the per-
			# character UI cap consistently.
			if main_node.has_method("add_item_with_overflow"):
				main_node.add_item_with_overflow(recipient, item_name, int(items[item_name]))
			else:
				recipient.data.inventory[item_name] = int(recipient.data.inventory.get(item_name, 0)) + int(items[item_name])
	var gui: Node = get_tree().root.get_node_or_null("Main/CanvasLayer/GUI")
	if gui != null and gui.has_method("notify_loot_batch"):
		gui.notify_loot_batch(fab_world, items)
	if main_node.has_method("notify_inventory_changed"):
		main_node.notify_inventory_changed()


# Cyan progress bar above the fabricator while a craft is running. Same
# Line2D pattern as harvest/mine bars; idempotent.
func _show_fabricator_bar(anchor: Vector2) -> void:
	if not fabricators.has(anchor):
		return
	var fab: Dictionary = fabricators[anchor]
	if fab.bar_bg != null and is_instance_valid(fab.bar_bg):
		return
	var bar_left: Vector2 = gridToWorld(anchor)
	var bar_w: float = float(2 * cell_size)
	var bar_y: float = bar_left.y - 14.0
	var bar_bg := Line2D.new()
	bar_bg.add_point(Vector2(bar_left.x, bar_y))
	bar_bg.add_point(Vector2(bar_left.x + bar_w, bar_y))
	bar_bg.width = 8.0
	bar_bg.default_color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index = 20
	add_child(bar_bg)
	var bar_fill := Line2D.new()
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.add_point(Vector2(bar_left.x, bar_y))
	bar_fill.width = 8.0
	bar_fill.default_color = Color(0.45, 0.85, 1.0, 1.0)
	bar_fill.z_index = 21
	add_child(bar_fill)
	fab.bar_bg = bar_bg
	fab.bar_fill = bar_fill
	fab["bar_x"] = bar_left.x
	fab["bar_y"] = bar_y
	fab["bar_w"] = bar_w


func _update_fabricator_bar(anchor: Vector2, t: float) -> void:
	if not fabricators.has(anchor):
		return
	var fab: Dictionary = fabricators[anchor]
	if fab.bar_fill == null or not is_instance_valid(fab.bar_fill):
		return
	(fab.bar_fill as Line2D).set_point_position(1, Vector2(float(fab.bar_x) + float(fab.bar_w) * t, float(fab.bar_y)))


func _hide_fabricator_bar(anchor: Vector2) -> void:
	if not fabricators.has(anchor):
		return
	var fab: Dictionary = fabricators[anchor]
	if fab.bar_bg != null and is_instance_valid(fab.bar_bg):
		(fab.bar_bg as Line2D).queue_free()
	if fab.bar_fill != null and is_instance_valid(fab.bar_fill):
		(fab.bar_fill as Line2D).queue_free()
	fab.bar_bg = null
	fab.bar_fill = null


func _draw() -> void:
	# HP bars above damaged buildings — fades when hp_bar_t expires.
	for anchor in buildings:
		var b: Dictionary = buildings[anchor]
		if b.hp_bar_t <= 0.0 or b.hp >= b.max_hp:
			continue
		var sprite := b.sprite as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		var pct: float = clamp(float(b.hp) / float(b.max_hp), 0.0, 1.0)
		var alpha: float = clamp(b.hp_bar_t / 0.5, 0.0, 1.0) if b.hp_bar_t < 0.5 else 1.0
		var size_v: Vector2i = (b.def as Dictionary).size
		var bar_w: float = float(size_v.x * cell_size) * 0.7
		var bar_h: float = 5.0
		var anchor_world: Vector2 = (anchor as Vector2) * float(cell_size)
		var bar_x: float = anchor_world.x + float(size_v.x * cell_size) * 0.5 - bar_w * 0.5
		var bar_y: float = anchor_world.y - 12.0
		# Background (track)
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.05, 0.8 * alpha), true)
		# Fill — green→yellow→red as HP drops.
		var fill_col: Color = Color(0.30, 0.85, 0.30) if pct > 0.6 else (Color(1.0, 0.80, 0.20) if pct > 0.3 else Color(1.0, 0.30, 0.25))
		fill_col.a = alpha
		draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), fill_col, true)
		# 1px border
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0, 0, 0, 0.85 * alpha), false, 1.0)
