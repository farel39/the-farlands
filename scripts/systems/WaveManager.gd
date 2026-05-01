class_name WaveManager
extends Node

# Endless wave-defense loop:
#   PEACE → WAVE → PEACE → WAVE → ... until the player builds + activates
#   the Comm Relay Antenna, which triggers EVAC → VICTORY/DEFEAT.
# Forced timer pacing — peace ends automatically after PEACE_DURATION; the wave
# ends when every aggressive crab spawned for that wave is dead. Defeat fires
# at any point if all units are dead. Victory fires when any live unit reaches
# the evac marker (after the relay calls it).
#
# Wave intensity scales from Main.threat_level — every harvest, mine, and build
# bumps that counter, which feeds spawn count + creature variety. Players who
# minimize ecosystem disturbance face lighter waves; players who stockpile
# aggressively face the consequences.

enum State { PEACE, WAVE, EVAC, VICTORY, DEFEAT }

# Long peace gives the player real time to explore, repair, build, and gather
# resources between waves. The banner intentionally hides the exact countdown
# so the player has to read the tension cue rather than watch a clock.
const PEACE_DURATION: float = 180.0
const WAVE_SPAWN_INTERVAL: float = 1.5

# Wave generator parameters. Spawn count scales with threat + wave number;
# creature variety unlocks at threat thresholds.
const WAVE_BASE_COUNT: int = 4
const WAVE_THREAT_DIVISOR: float = 8.0  # +1 spawn per 8 threat
const WAVE_MAX_COUNT: int = 30          # safety cap so late game stays playable
const THREAT_UNLOCK_TIDE_CRAWLER: float = 20.0
const THREAT_UNLOCK_SHORE_STALKER: float = 40.0
const THREAT_UNLOCK_SKY_MAWLING: float = 60.0
# EVAC pacing: spawn rate scales linearly from EVAC_SPAWN_INTERVAL_START down
# to EVAC_SPAWN_INTERVAL_END across EVAC_TIME_LIMIT, so dawdling is punished
# with denser harassment toward the end of the run.
const EVAC_SPAWN_INTERVAL_START: float = 4.5
const EVAC_SPAWN_INTERVAL_END: float = 1.5
const EVAC_REACH_TILES: float = 1.5
# Hard deadline for the rescue shuttle. Timer expires → DEFEAT regardless of
# how many units are still inbound. Tuned so a careful, formation-based walk
# across the map is feasible but stragglers and detours bite.
const EVAC_TIME_LIMIT: float = 180.0

# Evac harassment: pulls from this rotating pool, one per spawn.
const EVAC_SPAWN_POOL: Array = ["alien_crab", "tide_crawler", "shore_stalker"]

signal state_changed(new_state: int, wave_index: int, duration: float)
signal banner_message(text: String, duration: float)

var state: int = State.PEACE
# How many waves the player has completed so far. wave_num=0 → next wave is W1.
var wave_num: int = 0
var phase_timer: float = 0.0
var _spawn_remaining: int = 0
var _spawn_timer: float = 0.0
var evac_pos: Vector2 = Vector2(-1, -1)
var _evac_marker: Node2D = null

var grid: Grid
var main: Node
var crab_scene: PackedScene
# Spawn queue for the current wave — populated from WAVE_ROSTERS[wave_num] at
# wave entry, then shuffled. Each entry is a creature key into CreatureDefs.
var _spawn_queue: Array = []
# Cached loaded textures keyed by creature name to avoid re-loading every spawn.
var _tex_cache: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Preload to avoid relying on `class_name CreatureDefs` registration timing.
const _CREATURE_DEFS := preload("res://scripts/data/CreatureDefs.gd")


func _ready() -> void:
	_rng.randomize()
	set_process(false)


# Called by Main once the world and units are ready. Kicks off the loop.
# Creature textures are pulled per-spawn from CreatureDefs, so only the scene
# needs to be passed here.
func start(g: Grid, m: Node, scene: PackedScene) -> void:
	grid = g
	main = m
	crab_scene = scene
	set_process(true)
	_enter_peace()


# Returns a cached [tex_down, tex_side] pair for a creature key. First call for
# a key loads from disk, subsequent calls reuse the loaded textures.
func _textures_for(creature_key: String) -> Array:
	if _tex_cache.has(creature_key):
		return _tex_cache[creature_key]
	var def: Dictionary = _CREATURE_DEFS.DEFS.get(creature_key, {})
	if def.is_empty():
		return [null, null]
	var tex_down: Texture2D = load(def.tex_down) as Texture2D
	var tex_side: Texture2D = load(def.tex_side) as Texture2D
	_tex_cache[creature_key] = [tex_down, tex_side]
	return _tex_cache[creature_key]


func _process(delta: float) -> void:
	phase_timer += delta
	match state:
		State.PEACE: _tick_peace(delta)
		State.WAVE: _tick_wave(delta)
		State.EVAC: _tick_evac(delta)
		_: pass


# ── State entry helpers ──────────────────────────────────────────────────────

func _enter_peace() -> void:
	state = State.PEACE
	phase_timer = 0.0
	state_changed.emit(state, wave_num + 1, PEACE_DURATION)
	banner_message.emit("Peace — Wave %d incoming" % (wave_num + 1), 3.0)


func _enter_wave() -> void:
	state = State.WAVE
	phase_timer = 0.0
	# Generate the wave roster from threat level + wave number rather than
	# a fixed table. Spawn order is randomized so the player sees a mix
	# instead of a sorted block of one creature type per archetype.
	_spawn_queue.clear()
	for creature_key in _build_wave_roster():
		_spawn_queue.append(creature_key)
	_spawn_queue.shuffle()
	_spawn_remaining = _spawn_queue.size()
	_spawn_timer = 0.0
	state_changed.emit(state, wave_num + 1, 0.0)
	banner_message.emit("Wave %d — incoming!" % (wave_num + 1), 3.0)


# Threat-driven roster builder. Reads Main.threat_level and the current
# wave number to scale total spawn count + creature variety. The bigger
# the disturbance the player has caused, the harder the wave they face.
func _build_wave_roster() -> Array:
	var threat: float = 0.0
	if main != null and "threat_level" in main:
		threat = float(main.threat_level)
	# Total enemies: base + threat-driven + slow per-wave ramp.
	var total_count: int = WAVE_BASE_COUNT + int(threat / WAVE_THREAT_DIVISOR) + wave_num
	total_count = clamp(total_count, 3, WAVE_MAX_COUNT)
	# Creature pool grows as threat passes thresholds.
	var pool: Array = ["alien_crab"]
	if threat >= THREAT_UNLOCK_TIDE_CRAWLER:
		pool.append("tide_crawler")
	if threat >= THREAT_UNLOCK_SHORE_STALKER:
		pool.append("shore_stalker")
	if threat >= THREAT_UNLOCK_SKY_MAWLING:
		pool.append("sky_mawling")
	var roster: Array = []
	for _i in total_count:
		roster.append(pool[_rng.randi() % pool.size()])
	return roster


func _enter_evac() -> void:
	state = State.EVAC
	phase_timer = 0.0
	_spawn_timer = EVAC_SPAWN_INTERVAL_START
	evac_pos = _pick_evac_point()
	_spawn_evac_marker()
	state_changed.emit(state, 0, EVAC_TIME_LIMIT)
	banner_message.emit("EVAC — get every survivor to the shuttle!", 5.0)


func _enter_victory() -> void:
	state = State.VICTORY
	state_changed.emit(state, 0, 0.0)
	banner_message.emit("VICTORY — Survivors evacuated", 999.0)
	set_process(false)


func _enter_defeat() -> void:
	state = State.DEFEAT
	state_changed.emit(state, 0, 0.0)
	banner_message.emit("DEFEAT — All survivors lost", 999.0)
	set_process(false)


# ── Per-state ticks ──────────────────────────────────────────────────────────

func _tick_peace(_delta: float) -> void:
	if _all_units_dead():
		_enter_defeat()
		return
	if phase_timer >= PEACE_DURATION:
		_enter_wave()


func _tick_wave(delta: float) -> void:
	if _all_units_dead():
		_enter_defeat()
		return
	# Spawn enemies over time so the wave feels staggered, not instantaneous.
	if _spawn_remaining > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_wave_crab()
			_spawn_remaining -= 1
			_spawn_timer = WAVE_SPAWN_INTERVAL
	elif _count_aggressive_crabs_alive() == 0:
		_end_wave()


func _tick_evac(delta: float) -> void:
	# Defeat triggers if every survivor is gone before any reach the shuttle,
	# OR if the rescue deadline expires with anyone still inbound.
	if _all_remaining_units_dead():
		_enter_defeat()
		return
	if phase_timer >= EVAC_TIME_LIMIT:
		_enter_defeat()
		return
	# Spawn rate scales from START → END across the time limit, so stragglers
	# face increasingly dense harassment.
	var t: float = clamp(phase_timer / EVAC_TIME_LIMIT, 0.0, 1.0)
	var current_interval: float = lerp(EVAC_SPAWN_INTERVAL_START, EVAC_SPAWN_INTERVAL_END, t)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_wave_crab()
		_spawn_timer = current_interval
	# Each tick, mark any live unit standing on the shuttle as evacuated.
	_check_evac_arrivals()
	# Victory the moment every still-living survivor has boarded. Dead units
	# don't block the check — they're casualties, not stragglers.
	if _all_live_units_evacuated():
		_enter_victory()


# Mark each live unit within EVAC_REACH_TILES of the shuttle as evacuated.
# evacuate() handles the visual hide + de-targeting, so the unit drops out
# of the world cleanly.
func _check_evac_arrivals() -> void:
	if main == null or evac_pos == Vector2(-1, -1):
		return
	var threshold: float = EVAC_REACH_TILES * float(grid.cell_size)
	var evac_world: Vector2 = grid.gridToWorld(evac_pos) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	for u in main.all_units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		if unit.is_dead() or unit.evacuated:
			continue
		# Downed units can't walk themselves to the shuttle — they have to be
		# revived first. Skip them in the proximity check.
		if unit.is_downed:
			continue
		if unit.global_position.distance_to(evac_world) <= threshold:
			unit.evacuate()


func _end_wave() -> void:
	wave_num += 1
	# Stat hook — each completed wave bumps the run summary counter.
	if main != null and main.has_method("record_wave_completed"):
		main.record_wave_completed()
	# Endless mode — always go back to peace. EVAC is triggered by the
	# Comm Relay Antenna's channel completion, not by a fixed wave count.
	_enter_peace()


# Public hook: the Comm Relay Antenna's channel-complete callback fires this
# to kick off the EVAC phase. Safe to call from any state — re-entering
# EVAC if it's already active is a no-op since _enter_evac respawns the
# marker idempotently.
func trigger_evac_from_relay() -> void:
	if state == State.VICTORY or state == State.DEFEAT:
		return
	# Cancel any in-flight wave's spawn queue so the EVAC's own escalating
	# spawn rate takes over without leftover wave creatures piling on.
	_spawn_queue.clear()
	_spawn_remaining = 0
	_enter_evac()


# ── Spawning ─────────────────────────────────────────────────────────────────

func _spawn_wave_crab() -> void:
	_spawn_wave_crab_keyed("")


# Public harassment spawner used by Grid._tick_comm_relays during the relay
# channel. Forces a random pick from EVAC_SPAWN_POOL (no boss / sky-mawling
# tier) regardless of state, so we don't accidentally drain a live wave's
# spawn queue when channeling overlaps with a wave. Spawns at a random
# map edge, same lifecycle as a wave creature.
func spawn_harassment_creature() -> void:
	_spawn_wave_crab_keyed(EVAC_SPAWN_POOL[_rng.randi() % EVAC_SPAWN_POOL.size()])


# Shared spawn helper. Pass an empty string to keep the original wave/evac
# behavior (queue pop or evac pool); pass a specific creature key to force
# that creature.
func _spawn_wave_crab_keyed(forced_key: String) -> void:
	var cell: Vector2 = _pick_edge_cell()
	if cell == Vector2(-1, -1):
		return
	var creature_key: String = forced_key
	if creature_key == "":
		# Pick the creature key:
		#   - Wave: pop the next entry from the pre-built shuffled queue.
		#   - Evac: random pick from EVAC_SPAWN_POOL (rotating harassment).
		if state == State.WAVE and not _spawn_queue.is_empty():
			creature_key = _spawn_queue.pop_back()
		else:
			creature_key = EVAC_SPAWN_POOL[_rng.randi() % EVAC_SPAWN_POOL.size()]
	var def: Dictionary = _CREATURE_DEFS.DEFS.get(creature_key, {})
	if def.is_empty():
		return
	var textures: Array = _textures_for(creature_key)
	if textures[0] == null or textures[1] == null:
		return
	var crab = crab_scene.instantiate()
	crab.position = grid.gridToWorld(cell)
	crab.aggressive = true
	# Wave creatures roam the whole map, not just the shore band.
	crab.shore_y_min = 0
	crab.shore_y_max = grid.height
	grid.add_child(crab)
	grid.crabs.append(crab)
	crab.setup(textures[0], textures[1], grid, def)
	# Eye-glow PointLight2D — same one ambient crabs get from WorldSpawner.
	# Day/night cycle fades it in at night.
	WorldSpawner.attach_crab_light(grid, crab)


func _pick_edge_cell() -> Vector2:
	# Random navigable, non-water cell on one of the four edges. 30 attempts is
	# plenty — failure is rare and harmless (the next tick tries again).
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


func _pick_evac_point() -> Vector2:
	# Random navigable tile, ≥8 tiles from every live unit (so reaching it
	# requires real travel). Falls back to map center on repeated failures.
	for _try in 200:
		var cell: Vector2 = Vector2(
			_rng.randi_range(2, grid.width - 3),
			_rng.randi_range(2, grid.height - 3)
		)
		if not grid.grid.has(cell):
			continue
		if not grid.grid[cell].navigable:
			continue
		if grid.water_tiles.has(cell):
			continue
		var ok: bool = true
		for u in main.all_units:
			if not is_instance_valid(u):
				continue
			if (u as Unit).is_dead():
				continue
			var u_cell: Vector2 = grid.worldToGrid(u.global_position)
			if cell.distance_to(u_cell) < 8.0:
				ok = false
				break
		if ok:
			return cell
	return Vector2(int(grid.width * 0.5), int(grid.height * 0.5))


# How many cells wide the shuttle renders. Source PNG (1856x2304) at 3 cells
# wide gives ~3.7 cells of vertical extent — landing gear plants on the evac
# cell, hull and antennas overflow upward into cells above.
const EVAC_SHUTTLE_CELL_WIDTH: int = 3


func _spawn_evac_marker() -> void:
	if _evac_marker != null and is_instance_valid(_evac_marker):
		_evac_marker.queue_free()
	var tex: Texture2D = load("res://art/structures/evac shuttle.png") as Texture2D
	if tex == null:
		# Fallback to a tiny procedural dot if the sprite is missing — keeps
		# the run from soft-locking even if the asset got deleted.
		var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.25, 1.0, 0.45, 0.9))
		var fb: Sprite2D = Sprite2D.new()
		fb.texture = ImageTexture.create_from_image(img)
		fb.position = grid.gridToWorld(evac_pos) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		fb.z_index = 12
		main.add_child(fb)
		_evac_marker = fb
		return
	var marker: Sprite2D = Sprite2D.new()
	marker.texture = tex
	# Scale to fit EVAC_SHUTTLE_CELL_WIDTH cells horizontally; height comes
	# along uniformly. Centered=true (default), so position is the sprite's
	# centre — anchor bottom-of-sprite to bottom-of-cell.
	var s: float = float(grid.cell_size * EVAC_SHUTTLE_CELL_WIDTH) / float(tex.get_width())
	marker.scale = Vector2(s, s)
	var scaled_h: float = s * float(tex.get_height())
	var cell: float = float(grid.cell_size)
	var cell_world: Vector2 = grid.gridToWorld(evac_pos)
	marker.position = Vector2(
		cell_world.x + cell * 0.5,
		cell_world.y + cell - scaled_h * 0.5
	)
	marker.z_index = 12
	main.add_child(marker)
	_evac_marker = marker


# ── Queries ──────────────────────────────────────────────────────────────────

func _all_units_dead() -> bool:
	if main == null:
		return false
	for u in main.all_units:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			return false
	return true


# Defeat condition during EVAC: nobody left to evacuate. Permanently-dead
# units (HP=0 AND not revivable) are skipped; downed teammates still count
# as "in play" because a live teammate could still revive them.
func _all_remaining_units_dead() -> bool:
	if main == null:
		return false
	for u in main.all_units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		# Permanently dead — true casualty, doesn't keep the run going.
		if unit.is_dead() and not unit.is_downed:
			continue
		return false
	return true


# Victory condition: at least one survivor evacuated, and no live OR downed
# teammate is left on the field. Casualties (permanent dead) don't block
# the check — only live stragglers and downed bodies do, since the latter
# can still be rescued.
func _all_live_units_evacuated() -> bool:
	if main == null:
		return false
	var any_evacuated: bool = false
	for u in main.all_units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		if unit.is_dead() and not unit.is_downed:
			continue
		if unit.evacuated:
			any_evacuated = true
			continue
		# A live or downed straggler still on the map blocks victory.
		return false
	return any_evacuated


func _count_aggressive_crabs_alive() -> int:
	var n: int = 0
	for c in grid.crabs:
		if not is_instance_valid(c):
			continue
		if c.has_method("is_dead") and c.is_dead():
			continue
		if "aggressive" in c and c.aggressive:
			n += 1
	return n


# Read by the GUI banner each frame to render the countdown.
func get_phase_remaining() -> float:
	if state == State.PEACE:
		return max(0.0, PEACE_DURATION - phase_timer)
	if state == State.EVAC:
		return max(0.0, EVAC_TIME_LIMIT - phase_timer)
	return 0.0


# 0..1 fraction of how close the next wave is during PEACE (0 = just started
# peace, 1 = wave about to fire). Used by the GUI banner's progress bar so
# the player has a vague "the wave is approaching" indicator without seeing
# the exact countdown number.
func get_phase_progress() -> float:
	if state == State.PEACE:
		return clamp(phase_timer / PEACE_DURATION, 0.0, 1.0)
	if state == State.EVAC:
		return clamp(phase_timer / EVAC_TIME_LIMIT, 0.0, 1.0)
	return 0.0


# How many units have boarded the shuttle so far. Read by the EVAC banner.
func get_evac_boarded() -> int:
	if main == null:
		return 0
	var n: int = 0
	for u in main.all_units:
		if is_instance_valid(u) and (u as Unit).evacuated:
			n += 1
	return n


# Live + downed survivors still in play (not permanently dead, not evacuated).
# Downed teammates count as stragglers — they're still rescuable and they
# DO need to make it to the shuttle for victory. Combined with
# get_evac_boarded for the "N / T boarded" banner readout.
func get_evac_remaining() -> int:
	if main == null:
		return 0
	var n: int = 0
	for u in main.all_units:
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		if unit.is_dead() and not unit.is_downed:
			continue
		if unit.evacuated:
			continue
		n += 1
	return n
