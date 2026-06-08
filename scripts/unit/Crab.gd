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
# Movement speed in pixels per second. Per-creature override via setup() def.
var speed: float = 60.0

# Shore band: y range to stay within
var shore_y_min: int = 0
var shore_y_max: int = 0

var _rng := RandomNumberGenerator.new()

# Combat
var hp: int = 30
var max_hp: int = 30
var _hit_flash_t: float = 0.0
const HIT_FLASH_DURATION := 0.18

# Set true for wave-spawned crabs: they actively hunt the nearest unit instead
# of merely retaliating. Default false → original wandering / reactive crab.
var aggressive: bool = false

# Retaliation AI: aggro is set when the crab is damaged, then it chases &
# attacks the attacker until they die or escape AGGRO_LOSE range.
var aggro_target: Node = null
const AGGRO_LOSE_TILES: float = 8.0
# Per-creature combat stats (var so setup() can override per def).
var attack_range_tiles: float = 0.9
var attack_cooldown_max: float = 1.4
var attack_damage: int = 5
# Lunge animation timing — visual only, kept const since all creatures share it.
const LUNGE_DURATION: float = 0.32
const LUNGE_DISTANCE_TILES: float = 0.45
# True when tex_down faces NORTH (default for "facing up" sprites). The sprite
# flips vertically when the creature moves south so it leads with its eyes.
# False for sprites that already face south (e.g., tide crawler).
var flip_v_south: bool = true
# Multiplier on the default 1-cell sprite width. Boss creatures (Brood Mother)
# render at 3.0 so they visually dominate. Default 1.0 keeps every other
# creature exactly as before.
var render_scale: float = 1.0

# ── Directional walk animation (optional, per-creature) ──────────────────────
# When a def supplies "walk_anim", the creature renders a rotating sprite-sheet
# walk cycle instead of the static down/side sprites: a single base-facing sheet
# is spun to the movement direction (works cleanly because creatures are drawn
# top-down). Used by the Driftback. Absent / empty → classic static behavior,
# so every other creature is untouched.
var _uses_rotation_anim: bool = false
var _walk_frames: Array = []          # Array[Texture2D], one per cycle frame
var _walk_frame_idx: int = 0
var _walk_anim_t: float = 0.0         # 0..1 progress into the current frame
var _walk_fps: float = 12.0
var _walk_base_angle: float = PI      # heading the base sheet faces (left = PI)
var _last_move_dir: Vector2 = Vector2.DOWN
# Per-frame Sprite2D.offset (texture pixels) that pins the creature's body
# centroid to a fixed point across the whole cycle. AI-generated frames drift
# the body around within the frame; without this the loop visibly snaps back
# every cycle. Computed once per sheet and shared via _walk_offset_cache.
var _walk_frame_offsets: Array = []   # Array[Vector2], parallel to _walk_frames
static var _walk_offset_cache: Dictionary = {}   # dir_path -> Array[Vector2]
# Local offset of the Sprite2D within the Crab node. ZERO for static creatures
# (texture top-left on the origin, centered=false). For rotation-anim creatures
# the sprite is centered and parked at the cell centre so it spins about its
# own body rather than swinging around a corner.
var _sprite_base_pos: Vector2 = Vector2.ZERO
# Per-creature loot table — copied from the def in setup(). On death each entry
# rolls independently against `chance`, then randi_range(min,max) for the count.
# Empty array = no drops (default for ambient peacetime spawns without a def).
var _drops: Array = []
# Per-creature engagement growl. Pulled from CreatureDefs.growl_sound
# during setup(). Played once via AudioManager when the creature first
# acquires an aggro target (either via take_damage retaliation or the
# aggressive hunting AI). _growled latches so we don't spam the sound
# every time the target list refreshes.
var _growl_sound: String = ""
var _growled: bool = false
var _attack_cooldown: float = 0.0
var _is_attacking: bool = false
var _attack_t: float = 0.0
var _attack_dir_vec: Vector2 = Vector2.RIGHT
var _hit_landed: bool = false
# Set when the current lunge is targeting a wall cell rather than the aggro
# target unit. Cleared when the lunge finishes. _apply_combat_hit reads this
# to route damage to grid.damage_wall_at instead of the unit.
var _wall_target_cell: Vector2 = Vector2(-1e9, -1e9)
const _NO_WALL_TARGET: Vector2 = Vector2(-1e9, -1e9)


func setup(down: Texture2D, side: Texture2D, g: Grid, def: Dictionary = {}) -> void:
	grid = g
	_tex_down = down
	_tex_side = side
	# Per-creature stat overrides from CreatureDefs. Empty def = keep defaults
	# (which match the alien crab — used by ambient peacetime spawns).
	if not def.is_empty():
		max_hp = int(def.get("hp", max_hp))
		hp = max_hp
		speed = float(def.get("speed", speed))
		attack_damage = int(def.get("attack_damage", attack_damage))
		attack_cooldown_max = float(def.get("attack_cooldown", attack_cooldown_max))
		attack_range_tiles = float(def.get("attack_range_tiles", attack_range_tiles))
		flip_v_south = bool(def.get("flip_v_south", flip_v_south))
		render_scale = float(def.get("render_scale", render_scale))
		_drops = def.get("drops", [])
		_growl_sound = String(def.get("growl_sound", ""))
	_rng.randomize()
	_idle_duration = _rng.randf_range(0.5, 2.5)
	if not def.is_empty() and def.has("walk_anim"):
		_load_walk_anim(def["walk_anim"])
	if _uses_rotation_anim:
		_init_walk_sprite()
	else:
		_apply_sprite(down, false)


func is_dead() -> bool:
	return hp <= 0


func take_damage(amount: int, attacker: Node = null) -> void:
	if hp <= 0:
		return
	hp -= amount
	_hit_flash_t = HIT_FLASH_DURATION
	if attacker != null and is_instance_valid(attacker):
		aggro_target = attacker
		_maybe_play_engagement_growl()
	# Refresh the overhead HP bar — _draw is event-driven, so the bar's
	# fill width only changes when we explicitly request a redraw.
	queue_redraw()
	if hp <= 0:
		_drop_loot()
		# Tick the run kill counter (drop-aware so peacetime ambient crabs
		# without a drops table still count toward the summary).
		var main_n: Node = get_tree().root.get_node_or_null("Main")
		if main_n != null and main_n.has_method("record_kill"):
			main_n.record_kill()
		queue_free()


func _draw() -> void:
	# Overhead HP bar — visible only after the creature has been hit.
	# Mirrors the building HP bar style in Grid.gd: black track, green→
	# yellow→red fill based on remaining %, 1px border.
	#
	# Position is derived from the actual rendered sprite rect rather
	# than a cell-size approximation, because the Crab's Sprite2D uses
	# `centered = false` (texture top-left sits on the Node2D origin).
	# For non-square textures or boss creatures (render_scale 3.0), the
	# old "centered on local origin" math placed the bar to the upper-
	# left of the visible body. Reading texture.get_size() * scale
	# gives the true visible footprint regardless of aspect ratio or
	# render_scale.
	if grid == null or hp >= max_hp or hp <= 0:
		return
	var sprite_node := get_node_or_null("Sprite2D") as Sprite2D
	if sprite_node == null or sprite_node.texture == null:
		return
	var pct: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	var tex_size: Vector2 = sprite_node.texture.get_size() * sprite_node.scale
	# Visible body bounds in local coords, anchored to the sprite's own local
	# position (ZERO for static creatures; the cell centre for rotation-anim
	# ones). centered=false puts the texture top-left on that point; centered=
	# true (rotation-anim) puts the texture centre there.
	var origin: Vector2 = sprite_node.position
	var body_left: float = origin.x
	var body_top: float = origin.y
	if sprite_node.centered:
		body_left -= tex_size.x * 0.5
		body_top -= tex_size.y * 0.5
	var body_center_x: float = body_left + tex_size.x * 0.5
	var bar_w: float = tex_size.x * 0.7
	var bar_h: float = 4.0
	var bar_x: float = body_center_x - bar_w * 0.5
	var bar_y: float = body_top - 8.0
	# Track
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.05, 0.85), true)
	# Fill — green when healthy, yellow when bloodied, red when critical.
	var fill_col: Color = Color(0.30, 0.85, 0.30) if pct > 0.6 else (Color(1.0, 0.80, 0.20) if pct > 0.3 else Color(1.0, 0.30, 0.25))
	draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), fill_col, true)
	# 1px border
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0, 0, 0, 0.85), false, 1.0)


# Roll the loot table, deposit items into the closest live (non-downed) unit,
# and tell the GUI to show floating "+N item" toasts above the corpse. Silent
# no-op when the def carries no drops (peacetime ambient crabs).
func _drop_loot() -> void:
	if _drops.is_empty():
		return
	var rolled: Dictionary = {}
	for entry in _drops:
		var chance: float = float(entry.get("chance", 1.0))
		if _rng.randf() > chance:
			continue
		var lo: int = int(entry.get("min", 1))
		var hi: int = int(entry.get("max", lo))
		var amt: int = _rng.randi_range(lo, hi)
		if amt <= 0:
			continue
		var item_name: String = entry.get("item", "")
		if item_name == "":
			continue
		rolled[item_name] = int(rolled.get(item_name, 0)) + amt
	if rolled.is_empty():
		return
	var recipient: Node = _find_nearest_live_unit()
	if recipient != null:
		# Route through Main.add_item_with_overflow so loot from a kill
		# next to a fully-stocked unit cascades to a teammate with bag
		# space rather than silently exceeding the 20-slot UI cap.
		var main_l: Node = get_tree().root.get_node_or_null("Main")
		for item_name: String in rolled.keys():
			if main_l != null and main_l.has_method("add_item_with_overflow"):
				main_l.add_item_with_overflow(recipient, item_name, int(rolled[item_name]))
			else:
				recipient.data.inventory[item_name] = int(recipient.data.inventory.get(item_name, 0)) + int(rolled[item_name])
	# Toast even if there's no recipient — drops are still acknowledged
	# visually so the player knows a kill paid out (in practice there's
	# always at least one live unit on screen during a wave).
	var gui: Node = get_tree().root.get_node_or_null("Main/CanvasLayer/GUI")
	if gui != null and gui.has_method("notify_loot_batch"):
		var crab_center: Vector2 = position + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		gui.notify_loot_batch(crab_center, rolled)
	# Wake up any deferred build tasks that were waiting on materials.
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("notify_inventory_changed"):
		main.notify_inventory_changed()


# Fire the per-creature engagement growl once. Called from both aggro
# entry points (take_damage retaliation, hunting AI), but the _growled
# latch ensures only the first transition into "I have a target" plays
# the sound. -4 dB so a pack of stalkers engaging at once layers as a
# chorus rather than blowing out the mix.
func _maybe_play_engagement_growl() -> void:
	if _growled or _growl_sound == "":
		return
	_growled = true
	AudioManager.play_2d(_growl_sound, global_position, -4.0)


func _find_nearest_live_unit() -> Node:
	var best: Node = null
	var best_d: float = INF
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if u.has_method("is_dead") and u.is_dead():
			continue
		if "is_downed" in u and u.is_downed:
			continue
		var d: float = position.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


func _apply_sprite(tex: Texture2D, flip_h: bool, flip_v: bool = false) -> void:
	_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		return
	_sprite.texture = tex
	_sprite.flip_h = flip_h
	_sprite.flip_v = flip_v
	# Default scaling fits the texture into a 1-cell-wide footprint. Boss
	# creatures bump render_scale (e.g., 3.0 for the Brood Mother) so they
	# visually dominate the area without changing collision math.
	var s := float(grid.cell_size) / float(tex.get_width()) * render_scale
	_sprite.scale = Vector2(s, s)


# Load the per-creature walk sheet described by the def's "walk_anim" dict and
# flip this crab into rotation-anim mode. Frames are named <prefix><N>.<ext>
# (1-based) inside `dir`. JPG frames (no alpha) get the white-key shader.
func _load_walk_anim(spec: Dictionary) -> void:
	var dir_path: String = String(spec.get("dir", ""))
	var prefix: String = String(spec.get("prefix", "frame_"))
	var ext: String = String(spec.get("ext", "png"))
	var count: int = int(spec.get("count", 0))
	if dir_path == "" or count <= 0:
		return
	var frames: Array = []
	for i in range(1, count + 1):
		var path: String = "%s/%s%d.%s" % [dir_path, prefix, i, ext]
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			frames.append(tex)
	if frames.is_empty():
		return
	_walk_frames = frames
	_walk_fps = float(spec.get("fps", 12.0))
	_walk_base_angle = _facing_to_angle(String(spec.get("facing", "left")))
	_uses_rotation_anim = true
	# Stabilize the cycle on the body centroid so the loop doesn't snap back.
	# Keyed by dir so all Driftbacks share one computation. key_white frames are
	# keyed on near-white; otherwise we treat low-alpha as background.
	_walk_frame_offsets = _frame_offsets(dir_path, frames, bool(spec.get("key_white", false)))
	if bool(spec.get("key_white", false)):
		_apply_white_key_material()


# Map the base sheet's facing string to the heading angle its head points along.
# (Godot 2D: +x = 0, +y = PI/2 since y is down.)
func _facing_to_angle(facing: String) -> float:
	match facing:
		"right": return 0.0
		"up": return -PI * 0.5
		"down": return PI * 0.5
	return PI   # "left" / default


# Per-frame Sprite2D.offset that re-centres each frame on the creature's body
# centroid, cancelling the positional drift baked into AI-generated frames so
# the cycle loops seamlessly. Cached by `key` (the sheet dir) so the pixel pass
# runs once no matter how many creatures share the sheet.
func _frame_offsets(key: String, frames: Array, key_white: bool) -> Array:
	if _walk_offset_cache.has(key):
		return _walk_offset_cache[key]
	var offsets: Array = []
	for tex in frames:
		offsets.append(_centroid_offset(tex as Texture2D, key_white))
	_walk_offset_cache[key] = offsets
	return offsets


# Offset (in texture pixels) that moves a frame's body centroid onto the
# texture centre — i.e. onto the centered sprite's origin. "Body" pixels are
# those that survive the background test: near-white rejected for key_white
# sheets, else low-alpha rejected. Subsamples for speed; returns ZERO on any
# failure so stabilization simply no-ops rather than breaking rendering.
func _centroid_offset(tex: Texture2D, key_white: bool) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var img: Image = tex.get_image()
	if img == null:
		return Vector2.ZERO
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return Vector2.ZERO
	var step: int = max(1, int(round(float(max(w, h)) / 256.0)))  # ~256 samples/axis
	var sx: float = 0.0
	var sy: float = 0.0
	var n: int = 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			var is_body: bool = (min(c.r, min(c.g, c.b)) < 0.90) if key_white else (c.a > 0.5)
			if is_body:
				sx += float(x)
				sy += float(y)
				n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(float(w) * 0.5 - sx / float(n), float(h) * 0.5 - sy / float(n))


func _apply_white_key_material() -> void:
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp == null:
		return
	var sh := load("res://art/shaders/white_key.gdshader") as Shader
	if sh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	sp.material = mat


# Configure the Sprite2D for rotation-anim rendering: centered so it spins about
# its body, parked at the cell centre, showing the first frame facing south.
func _init_walk_sprite() -> void:
	_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		return
	_sprite.centered = true
	_sprite_base_pos = Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	_sprite.position = _sprite_base_pos
	_last_move_dir = Vector2.DOWN
	_apply_walk_frame(Vector2.DOWN)


# Point the creature toward `dir`. Rotation-anim creatures (Driftback) spin
# their single walk sheet to the heading; everyone else swaps down/side sprites
# with the usual flips.
func _face_dir(dir: Vector2) -> void:
	if _uses_rotation_anim:
		_apply_walk_frame(dir)
	elif abs(dir.x) > abs(dir.y):
		_apply_sprite(_tex_side, dir.x > 0)
	else:
		_apply_sprite(_tex_down, false, (flip_v_south and dir.y > 0.0) or (not flip_v_south and dir.y < 0.0))


# Step the walk cycle forward by `delta`. Only advances while the creature is
# actually moving (callers gate this), so a stationary creature freezes on its
# current frame instead of marching in place.
func _advance_walk_anim(delta: float) -> void:
	if not _uses_rotation_anim or _walk_frames.is_empty():
		return
	_walk_anim_t += delta * _walk_fps
	while _walk_anim_t >= 1.0:
		_walk_anim_t -= 1.0
		_walk_frame_idx = (_walk_frame_idx + 1) % _walk_frames.size()


# Render the current walk frame, rotated so the sheet's base heading lines up
# with `dir`. Keeps the last heading when `dir` is ~zero so a creature that
# stops doesn't snap back to its default facing.
func _apply_walk_frame(dir: Vector2) -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D")
	if _sprite == null or _walk_frames.is_empty():
		return
	if dir.length() > 0.01:
		_last_move_dir = dir
	var idx: int = _walk_frame_idx % _walk_frames.size()
	var tex: Texture2D = _walk_frames[idx]
	_sprite.texture = tex
	_sprite.flip_h = false
	_sprite.flip_v = false
	# Centroid-stabilize: pin the body to the sprite origin so the cycle doesn't
	# drift-and-snap. offset is in texture pixels and rides the node's scale +
	# rotation, so the body stays put for every heading.
	if idx < _walk_frame_offsets.size():
		_sprite.offset = _walk_frame_offsets[idx]
	_sprite.rotation = _last_move_dir.angle() - _walk_base_angle
	var s := float(grid.cell_size) / float(tex.get_width()) * render_scale
	_sprite.scale = Vector2(s, s)


func _process(delta: float) -> void:
	z_index = int(position.y / float(grid.cell_size)) + 1
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		var s := get_node_or_null("Sprite2D") as Sprite2D
		if s:
			var k: float = clamp(_hit_flash_t / HIT_FLASH_DURATION, 0.0, 1.0)
			s.modulate = Color(1.0, lerp(1.0, 0.3, k), lerp(1.0, 0.3, k), 1.0)
			if _hit_flash_t <= 0.0:
				s.modulate = Color(1, 1, 1, 1)

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	# Mid-lunge: position the sprite along the lunge curve and pause AI.
	if _is_attacking:
		_tick_attack(delta)
		return

	# Drop dead/escaped aggro
	if aggro_target != null:
		if not is_instance_valid(aggro_target):
			aggro_target = null
		elif aggro_target.has_method("is_dead") and aggro_target.is_dead():
			aggro_target = null
		elif position.distance_to(aggro_target.global_position) > AGGRO_LOSE_TILES * float(grid.cell_size):
			aggro_target = null

	# Wave-spawned (aggressive) crabs proactively hunt the nearest live unit.
	# Plain wandering crabs only set aggro_target through retaliation in
	# take_damage(), so this branch is a no-op for them.
	if aggressive and aggro_target == null:
		aggro_target = _find_nearest_unit()
		if aggro_target != null:
			_maybe_play_engagement_growl()

	if aggro_target != null:
		_path.clear()
		_idle_timer = 0.0
		_tick_combat(delta)
		return

	if not _path.is_empty():
		_walk(delta)
	else:
		_idle_timer += delta
		if _idle_timer >= _idle_duration:
			_idle_timer = 0.0
			_idle_duration = _rng.randf_range(0.8, 3.5)
			_pick_new_target()


# Scan the "units" group for the closest living target. Group registration
# happens in Unit._ready(). Returns null when there are no candidates.
func _find_nearest_unit() -> Node:
	var nearest: Node = null
	var best_d: float = INF
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if u.has_method("is_dead") and u.is_dead():
			continue
		var d: float = position.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			nearest = u
	return nearest


func _tick_combat(delta: float) -> void:
	# Distance must compare visual-body centers, not anchor points. Crab anchor
	# is its sprite's top-left (centered=false) so its body center is a half-cell
	# down-right of `position`. Unit anchor is its feet so its body center is a
	# half-cell above `global_position`. Without this correction, a crab
	# approaching from the north thinks it's much farther than one from the
	# south for the same visible gap.
	var crab_center: Vector2 = position + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	var unit_center: Vector2 = aggro_target.global_position + Vector2(0, -grid.cell_size * 0.5)
	var to_unit: Vector2 = unit_center - crab_center
	var dist_unit: float = to_unit.length()
	var dir_unit: Vector2 = to_unit.normalized() if dist_unit > 0.001 else Vector2.DOWN

	# Wall-in-path detection. The cell orthogonally-adjacent in the dominant
	# direction of dir_unit; reliable at cell boundaries (free-space ray
	# sampling can overshoot to 2 cells when crab_center sits on a boundary).
	var crab_cell: Vector2 = grid.worldToGrid(crab_center)
	var ahead_cell: Vector2 = crab_cell + (
		Vector2(sign(dir_unit.x), 0) if abs(dir_unit.x) >= abs(dir_unit.y)
		else Vector2(0, sign(dir_unit.y))
	)
	var wall_in_way: bool = grid.is_wall_at(ahead_cell)

	var target_world: Vector2
	var dir: Vector2
	if wall_in_way:
		var wall_center: Vector2 = grid.gridToWorld(ahead_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		var to_wall: Vector2 = wall_center - crab_center
		var dist_wall: float = to_wall.length()
		dir = to_wall.normalized() if dist_wall > 0.001 else dir_unit
		target_world = wall_center
	else:
		dir = dir_unit
		target_world = unit_center

	# Face the target. Rotation-anim creatures spin their walk sheet toward it;
	# static ones swap down/side sprites (down-sprite faces up by default, so it
	# flips vertically when leading south).
	_face_dir(dir)

	var d: float = crab_center.distance_to(target_world)
	var range_world: float = attack_range_tiles * float(grid.cell_size)
	if d <= range_world:
		if _attack_cooldown <= 0.0:
			_wall_target_cell = ahead_cell if wall_in_way else _NO_WALL_TARGET
			_start_lunge(dir)
	else:
		# Only cycle the walk frames while actually closing the gap.
		_advance_walk_anim(delta)
		var step: float = speed * delta
		if step > d:
			step = d
		position += dir * step


func _start_lunge(dir: Vector2) -> void:
	_is_attacking = true
	_attack_t = 0.0
	_attack_dir_vec = dir
	_hit_landed = false


func _tick_attack(delta: float) -> void:
	_attack_t += delta
	var f: float = clamp(_attack_t / LUNGE_DURATION, 0.0, 1.0)
	# Triangle wave 0→1→0 for forward-then-back motion.
	var amp: float = 1.0 - abs(f * 2.0 - 1.0)
	var dist_world: float = LUNGE_DISTANCE_TILES * float(grid.cell_size)
	if _sprite:
		_sprite.position = _sprite_base_pos + _attack_dir_vec * (amp * dist_world)
	# Damage lands at the apex of the lunge.
	if not _hit_landed and f >= 0.5:
		_hit_landed = true
		_apply_combat_hit()
	if _attack_t >= LUNGE_DURATION:
		_is_attacking = false
		_attack_cooldown = attack_cooldown_max
		_wall_target_cell = _NO_WALL_TARGET
		if _sprite:
			_sprite.position = _sprite_base_pos


func _apply_combat_hit() -> void:
	# When _tick_combat targeted a wall instead of the unit, route damage to
	# the grid's destructible-building system. Returns early without checking
	# the unit so a wall hit doesn't also spend a unit attack tick.
	if _wall_target_cell != _NO_WALL_TARGET:
		grid.damage_wall_at(_wall_target_cell, attack_damage)
		# Wall hits use the same claw SFX (chitin on wood/stone reads close
		# enough) but pan from the wall cell so the player can localize the
		# attacker without seeing the crab specifically.
		var wc: Vector2 = grid.gridToWorld(_wall_target_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		AudioManager.play_2d(Sounds.CLAW_HIT, wc)
		return
	if aggro_target == null or not is_instance_valid(aggro_target):
		return
	if aggro_target.has_method("is_dead") and aggro_target.is_dead():
		return
	if aggro_target.has_method("take_damage"):
		aggro_target.take_damage(attack_damage, self)
	# Claw hit pans from the victim's position so the impact reads as
	# happening to the unit, not the crab — easier to track which of your
	# units is taking damage when you have several engaged at once.
	AudioManager.play_2d(Sounds.CLAW_HIT, aggro_target.global_position)


func _walk(delta: float) -> void:
	_advance_walk_anim(delta)
	var remaining := speed * delta
	while remaining > 0.0 and not _path.is_empty():
		var to_next: Vector2 = _path[0] - position
		var dist := to_next.length()
		# Face the way we're moving. Rotation-anim creatures spin their walk
		# sheet; static ones swap down/side sprites (down-sprite is "facing up",
		# so it flips vertically when walking south).
		var dir := to_next.normalized()
		_face_dir(dir)
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
