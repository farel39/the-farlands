class_name EventManager
extends Node

# Random-event director. Sits idle until WaveManager enters PEACE or EVAC,
# then schedules events at irregular intervals. Each event is a small
# situational complication (or rare reward) — they layer on top of the
# wave loop to keep peace phases from feeling empty.

# Spacing between events. Random within this range so the player can't
# predict the next one. Tuned to fire 1-2 events per peace phase by default.
const MIN_EVENT_INTERVAL: float = 35.0
const MAX_EVENT_INTERVAL: float = 80.0

# Each entry: id, name, weight (relative probability), min_wave_completed
# (gate so harder events don't fire at the start of the run).
const EVENTS: Array = [
	{"id": "crab_raid",       "name": "Crab Raid!",         "weight": 3, "min_wave": 0},
	{"id": "lightning_storm", "name": "Lightning Storm",    "weight": 2, "min_wave": 0},
	{"id": "supply_drop",     "name": "Supply Drop",        "weight": 2, "min_wave": 0},
	{"id": "brood_mother",    "name": "Brood Mother Ambush!","weight": 1, "min_wave": 1},
	# Branching events — pause and prompt the player to pick. Both options
	# have real consequences, satisfying "every action affects the run."
	{"id": "mysterious_beacon","name": "Mysterious Beacon", "weight": 2, "min_wave": 0},
	{"id": "tempting_eggs",   "name": "Glowing Egg Cluster","weight": 2, "min_wave": 0},
]

signal event_announced(event_name: String, color: Color, duration: float)

var grid: Grid
var main_node: Node
var wave_manager: Node
var crab_scene: PackedScene
var _next_event_in: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const _CREATURE_DEFS := preload("res://scripts/data/CreatureDefs.gd")


func _ready() -> void:
	_rng.randomize()
	set_process(false)


# Called by Main once the world + wave manager are alive.
func start(g: Grid, m: Node, wm: Node, scene: PackedScene) -> void:
	grid = g
	main_node = m
	wave_manager = wm
	crab_scene = scene
	_schedule_next()
	set_process(true)


func _schedule_next() -> void:
	_next_event_in = _rng.randf_range(MIN_EVENT_INTERVAL, MAX_EVENT_INTERVAL)


func _process(delta: float) -> void:
	# Events only fire during peace + evac. Wave phases are already busy;
	# layering events on top of an active wave just creates frustration.
	if wave_manager == null:
		return
	# WaveManager.State enum: 0=PEACE 1=WAVE 2=EVAC 3=VICTORY 4=DEFEAT.
	var st: int = int(wave_manager.state)
	if st != 0 and st != 2:
		return
	_next_event_in -= delta
	if _next_event_in <= 0.0:
		_fire_random_event()
		_schedule_next()


func _fire_random_event() -> void:
	# Filter eligible events by wave-progression gate. Brood Mother won't
	# fire before wave 1 is done, etc.
	var wave_num: int = int(wave_manager.wave_num) if "wave_num" in wave_manager else 0
	var eligible: Array = []
	for e in EVENTS:
		if wave_num >= int(e.get("min_wave", 0)):
			eligible.append(e)
	if eligible.is_empty():
		return
	# Weighted random pick.
	var total_weight: int = 0
	for e in eligible:
		total_weight += int(e.get("weight", 1))
	var roll: int = _rng.randi() % total_weight
	var chosen: Dictionary = eligible[0]
	var acc: int = 0
	for e in eligible:
		acc += int(e.get("weight", 1))
		if roll < acc:
			chosen = e
			break
	_execute(chosen)


# Public: force-fire an event by id. Used by the debug panel so the player
# can test each branch without waiting for the random scheduler to pick it.
# Skips the wave-completion gate, so even Brood Mother fires before wave 1.
func fire_event_by_id(id: String) -> void:
	for e in EVENTS:
		if e.id == id:
			_execute(e)
			return


func _execute(event: Dictionary) -> void:
	var id: String = event.id
	event_announced.emit(event.name, _color_for(id), 4.5)
	match id:
		"crab_raid":        _fire_crab_raid()
		"lightning_storm":  _fire_lightning_storm()
		"supply_drop":      _fire_supply_drop()
		"brood_mother":     _fire_brood_mother()
		"mysterious_beacon":_fire_mysterious_beacon()
		"tempting_eggs":    _fire_tempting_eggs()


func _color_for(id: String) -> Color:
	match id:
		"crab_raid":       return Color(1.0, 0.55, 0.45)
		"lightning_storm": return Color(0.65, 0.85, 1.0)
		"supply_drop":     return Color(0.55, 1.0, 0.55)
		"brood_mother":    return Color(0.90, 0.45, 1.0)
	return Color(1, 1, 1)


# ── Event handlers ──────────────────────────────────────────────────────────

# 2-3 alien crabs spawn from one edge. Smaller than a full wave but still
# enough to wake up an idle base.
func _fire_crab_raid() -> void:
	var count: int = _rng.randi_range(2, 3)
	for _i in count:
		var cell: Vector2 = _pick_edge_cell()
		if cell == Vector2(-1, -1):
			continue
		_spawn_creature("alien_crab", cell)


# Brief storm: GUI flashes the screen, wood walls take chip damage, every
# unit's flashlight stutters. No persistent state — purely a moment of
# stress + a "watch your perimeter" cue.
func _fire_lightning_storm() -> void:
	var gui: Node = main_node.gui if main_node != null and "gui" in main_node else null
	if gui != null and gui.has_method("trigger_lightning_storm"):
		gui.trigger_lightning_storm(4.0)
	# Chip damage on wood walls only — stone shrugs off lightning.
	for anchor in grid.buildings.keys():
		var b: Dictionary = grid.buildings[anchor]
		var def: Dictionary = b.def
		if def.get("occupier", "") == "WoodWall" and _rng.randf() < 0.30:
			grid.damage_building(anchor, 12)
	# Every unit's flashlight + glow stutters for the storm's duration.
	for u in get_tree().get_nodes_in_group("units"):
		if u.has_method("flicker_flashlight"):
			u.flicker_flashlight(4.0)


# Drop pod lands at a random navigable cell with mid-late-game loot.
# Right-click works just like a supply crate (same occupier tag).
func _fire_supply_drop() -> void:
	for _try in 60:
		var x: int = _rng.randi_range(2, grid.width - 3)
		var y: int = _rng.randi_range(2, grid.height - 3)
		var cell: Vector2 = Vector2(x, y)
		if not grid.grid.has(cell):
			continue
		if not grid.grid[cell].navigable:
			continue
		if grid.water_tiles.has(cell):
			continue
		if grid.grid[cell].occupier != null:
			continue
		if grid.spawn_supply_pod(cell):
			return


# Single Brood Mother spawns from a far edge and hunts the team. Boss-tier
# HP + damage; the team needs to draft + focus-fire. The far-spawn rule
# gives the player time to spot it on the minimap and prep before contact.
func _fire_brood_mother() -> void:
	# 14 tiles ≈ across the map for typical play — far enough that the
	# player has reaction time, close enough that it'll reach the base
	# during the same peace phase.
	var cell: Vector2 = _pick_far_edge_cell(14)
	if cell == Vector2(-1, -1):
		# Fall back to any edge cell if no far one was found (e.g., units
		# happen to be hugging every edge). The boss should still spawn.
		cell = _pick_edge_cell()
	if cell == Vector2(-1, -1):
		return
	_spawn_creature("brood_mother", cell)


# ── Branching choice events ─────────────────────────────────────────────────
# These pause and ask the player to pick. Both options have real gameplay
# consequences — that's the "every action shapes the run" rubric. Choices
# are logged into run_stats.decisions for the end-of-run summary.

# Mysterious Beacon — investigate for a guaranteed reward at the cost of a
# small ambush, or skip and stay safe but miss the loot.
func _fire_mysterious_beacon() -> void:
	var gui: Node = main_node.gui if main_node != null and "gui" in main_node else null
	if gui == null or not gui.has_method("show_choice_event"):
		return
	var on_investigate: Callable = func():
		# Reward: drop pod with mid-tier loot at a random reachable cell.
		_fire_supply_drop()
		# Cost: 2 crabs immediately ambush from a nearby edge.
		for _i in 2:
			var cell: Vector2 = _pick_edge_cell()
			if cell != Vector2(-1, -1):
				_spawn_creature("alien_crab", cell)
	var on_avoid: Callable = func():
		# No reward, no cost. Pure safe choice — but the run summary will
		# show the player turned down free loot.
		pass
	gui.show_choice_event(
		"Mysterious Beacon",
		"A pulsing alien beacon glows in the distance. Worth investigating, but the noise will draw attention.",
		[
			{"label": "Investigate (drop pod, but ambush)", "callback": on_investigate},
			{"label": "Stay safe (no reward)",              "callback": on_avoid},
		]
	)


# Glowing Egg Cluster — smash for guaranteed eggs (crafting input) but risk
# attracting a Brood Mother shortly after. Or leave it and stay clean.
func _fire_tempting_eggs() -> void:
	var gui: Node = main_node.gui if main_node != null and "gui" in main_node else null
	if gui == null or not gui.has_method("show_choice_event"):
		return
	var on_smash: Callable = func():
		# Reward: 1-2 Strange Eggs deposited into a live unit.
		_deposit_anywhere({"Strange Egg": _rng.randi_range(1, 2)})
		# Cost: 60% chance of a Brood Mother ambush within ~20 seconds.
		if _rng.randf() < 0.6:
			_pending_brood_in = 20.0
	var on_leave: Callable = func():
		# No effect, but the missed eggs go on the run summary.
		pass
	gui.show_choice_event(
		"Glowing Egg Cluster",
		"You spot a cluster of bioluminescent eggs nestled in the sand. Smashing them yields rare crafting eggs — but the alien parents may notice.",
		[
			{"label": "Smash them (eggs, risk Brood Mother)", "callback": on_smash},
			{"label": "Leave them (no effect)",              "callback": on_leave},
		]
	)


# Drop a dict of items into the closest live unit + fire a loot toast,
# without needing a world position (used for "abstract" rewards from
# choice events that don't have an in-world spawn point).
var _pending_brood_in: float = -1.0

func _deposit_anywhere(items: Dictionary) -> void:
	if items.is_empty() or main_node == null:
		return
	var recipient: Unit = null
	# No specific anchor — use the first live unit we find. Visual toast
	# pops above them so the player sees the gain land somewhere.
	for u in main_node.all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if unit_node.is_dead() or unit_node.is_downed or unit_node.evacuated:
			continue
		recipient = unit_node
		break
	if recipient == null:
		return
	for item_name: String in items.keys():
		recipient.data.inventory[item_name] = int(recipient.data.inventory.get(item_name, 0)) + int(items[item_name])
	var gui: Node = main_node.gui if "gui" in main_node else null
	if gui != null and gui.has_method("notify_loot_batch"):
		gui.notify_loot_batch(recipient.global_position, items)
	if main_node.has_method("notify_inventory_changed"):
		main_node.notify_inventory_changed()


# ── Helpers ─────────────────────────────────────────────────────────────────

func _spawn_creature(creature_key: String, cell: Vector2) -> void:
	if crab_scene == null or grid == null:
		return
	var def: Dictionary = _CREATURE_DEFS.DEFS.get(creature_key, {})
	if def.is_empty():
		return
	var tex_down: Texture2D = load(def.tex_down) as Texture2D
	var tex_side: Texture2D = load(def.tex_side) as Texture2D
	if tex_down == null or tex_side == null:
		return
	var crab = crab_scene.instantiate()
	crab.position = grid.gridToWorld(cell)
	crab.aggressive = true
	crab.shore_y_min = 0
	crab.shore_y_max = grid.height
	grid.add_child(crab)
	grid.crabs.append(crab)
	crab.setup(tex_down, tex_side, grid, def)
	# Eye-glow matches ambient + wave crabs so event spawns aren't oddly
	# unlit at night.
	WorldSpawner.attach_crab_light(grid, crab)


func _pick_edge_cell() -> Vector2:
	for _try in 30:
		var side: int = _rng.randi_range(0, 3)
		var x: int = 0
		var y: int = 0
		match side:
			0: x = _rng.randi_range(0, grid.width - 1); y = 0
			1: x = grid.width - 1; y = _rng.randi_range(0, grid.height - 1)
			2: x = _rng.randi_range(0, grid.width - 1); y = grid.height - 1
			3: x = 0; y = _rng.randi_range(0, grid.height - 1)
		var cell: Vector2 = Vector2(x, y)
		if grid.grid.has(cell) and grid.grid[cell].navigable and not grid.water_tiles.has(cell):
			return cell
	return Vector2(-1, -1)


# Edge cell variant that rejects any candidate within `min_dist_tiles` of any
# live unit. Used by the Brood Mother spawn so the boss doesn't appear
# right on top of the team. Returns Vector2(-1, -1) if no far-enough
# navigable edge cell was found in 60 attempts.
func _pick_far_edge_cell(min_dist_tiles: int) -> Vector2:
	if main_node == null:
		return _pick_edge_cell()
	var min_d_sq: float = float(min_dist_tiles * min_dist_tiles)
	for _try in 60:
		var side: int = _rng.randi_range(0, 3)
		var x: int = 0
		var y: int = 0
		match side:
			0: x = _rng.randi_range(0, grid.width - 1); y = 0
			1: x = grid.width - 1; y = _rng.randi_range(0, grid.height - 1)
			2: x = _rng.randi_range(0, grid.width - 1); y = grid.height - 1
			3: x = 0; y = _rng.randi_range(0, grid.height - 1)
		var cell: Vector2 = Vector2(x, y)
		if not grid.grid.has(cell):
			continue
		if not grid.grid[cell].navigable or grid.water_tiles.has(cell):
			continue
		# Distance check against every live, non-evacuated unit.
		var ok: bool = true
		for u in main_node.all_units:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.is_dead() or unit_node.evacuated:
				continue
			var u_cell: Vector2 = grid.worldToGrid(unit_node.global_position)
			var dx: float = cell.x - u_cell.x
			var dy: float = cell.y - u_cell.y
			if dx * dx + dy * dy < min_d_sq:
				ok = false
				break
		if ok:
			return cell
	return Vector2(-1, -1)
