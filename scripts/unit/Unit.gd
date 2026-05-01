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
# Anchor of a damaged building this unit is sent to repair. Set by
# queue_repair() (right-click flow); cleared on completion or interruption.
var repair_target: Vector2 = Vector2(-1, -1)
var _repair_timer: float = -1.0
const REPAIR_TICK_DURATION := 1.0  # seconds between resource→HP exchanges

# Demolish target — anchor of a building marked for tear-down via the Orders
# command tab. The unit walks to the building, then drains its HP over time
# (visualized by the building's HP bar) until it falls. Total demolish time
# scales with the building's HP — wood walls fall fast, stone walls take a
# while. Drafted units don't auto-pick this; queued via pending_tasks.
var demolish_target: Vector2 = Vector2(-1, -1)
var _demolish_timer: float = -1.0
const DEMOLISH_TICK_DURATION := 0.5  # seconds between damage chunks
const DEMOLISH_HP_PER_TICK := 10     # HP drained per chunk (wood: 6 ticks, stone: 20)

# Chopping a tree: arrival starts the timer; once it expires, grid.harvest_tree
# fires and the rolled drops auto-deposit into this unit's inventory plus a
# loot toast at the tree's location.
var _harvest_timer: float = -1.0
const HARVEST_DURATION := 3.0

# Mining a rock cluster cell: same shape as harvest, but tied to mine_target
# (rock cell coords). Drops Stone always plus chance of Iron / Copper / Glass.
var mine_target: Vector2 = Vector2(-1, -1)
var _mine_timer: float = -1.0
const MINE_DURATION := 4.0
var gather_target: Vector2 = Vector2(-1, -1)
var gather_items: Dictionary = {}
var _dest: Vector2 = Vector2(-1, -1)        # grid coords, used for path visualiser
var _dest_world: Vector2 = Vector2(-1, -1)  # exact world destination

const GATHER_DURATION := 1.5  # seconds to stand at source before picking up
var _gather_timer: float = -1.0

# Looping AudioStreamPlayer2D for the active work action (chop / mine).
# Lazily created on first use and parented to the unit so it tracks the
# unit's position. Reused across actions by swapping the stream — only
# one work loop ever plays at a time per unit, since the unit can only
# do one thing at a time.
var _work_audio: AudioStreamPlayer2D = null
var _work_audio_path: String = ""

# Looping pistol audio for combat. Behaves like _work_audio: parented to
# the unit so it pans with their position, started when an attack tick
# lands (so the loop only fires when actually shooting, not while walking
# to engage), and stopped automatically the frame after _combat_target
# clears. Keeping it as a single sustained loop reads better than
# overlapping per-hit one-shots when the source sample is a 1s+ burst.
var _combat_audio: AudioStreamPlayer2D = null
# Tracks whether the unit had a live combat target last frame so we can
# detect the transition to "no target" and revert the post-attack
# aim-hold sprite back to an idle stance. Without this, ranged units
# freeze in their final attack frame when the target dies / escapes,
# because _tick_attack_anim only runs while _is_attacking is true.
var _was_in_combat: bool = false

var _build_timer: float = -1.0
var _build_duration: float = 1.0

var _tex_down: Texture2D = null
var _tex_side: Texture2D = null
var _tex_up: Texture2D = null
var _tex_downed: Texture2D = null  # body lying on ground when HP=0
var _shadow: Sprite2D

# Down state — HP hit 0 but the unit is still revivable. Combat / movement /
# tasks all freeze; the body shows the per-character "downed" sprite. A
# teammate using a Revival Injector flips this back off and restores HP.
var is_downed: bool = false
# Set when this unit is en route to revive a downed teammate (from right-click
# on the downed body). Cleared on arrival or interruption.
var revive_target: Unit = null
# Anchor of a Comm Relay Antenna this unit was sent to channel. Set by
# queue_relay_channel; cleared on arrival (replaced by the relay's internal
# channeler reference) or by any interrupt path. While set, the move()
# arrival cleanup tells the grid to start the channel.
var relay_target: Vector2 = Vector2(-1, -1)

# Evacuated: unit boarded the rescue shuttle during the EVAC phase. They're
# safe — hidden from the world, removed from the "units" group so crabs stop
# targeting them, and their _process is skipped so no AI runs. They count as
# saved for the WaveManager's victory check.
var evacuated: bool = false

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
# If set, side-idle uses this texture with the attack-side layout instead of
# `_walk_frames_side[_walk_idle_frame_side]`. Useful when the "ready stance"
# frame lives in the attack animation rather than the walk loop.
var idle_side_tex: Texture2D = null

var _attack_frames_side: Array = []
var _attack_frames_down: Array = []
var _attack_frames_up: Array = []
var _is_attacking: bool = false
var _attack_dir: String = "side"  # "side", "down", or "up"
var _attack_down_hold: bool = false  # stay on last down-attack frame until next move
var _attack_frame_idx: int = 0
var _attack_frame_timer: float = 0.0
# When an attack is triggered shortly after the previous one ended, start from
# these frames instead of frame 0 — lets pistol/melee skip a "draw weapon" or
# windup intro on chained attacks. 0 disables the skip for that direction.
var attack_chain_start_side: int = 0
var attack_chain_start_down: int = 0
var attack_chain_start_up: int = 0
var _time_since_attack_end: float = 1.0e6  # large => "no recent attack"

# Combat state (used when drafted)
var _combat_target: Node = null
var _combat_cooldown: float = 0.0
var _hit_landed_this_attack: bool = false
var _last_path_target_pos: Vector2 = Vector2(-INF, -INF)
# Set true when the current path was issued by the combat tick (approaching
# a target). Used to draw the path in red instead of the default white.
var _path_is_combat: bool = false

# Combat stance (only meaningful when drafted):
#   HOLD    — never auto-engages, won't even retaliate. Walks past enemies.
#   DEFEND  — auto-acquires any visible enemy in aggro range. Default.
#   PASSIVE — won't seek out enemies, but retaliates against attackers.
# An explicit attack command (right-click on enemy) bypasses stance for one shot.
enum Stance { HOLD, DEFEND, PASSIVE }
var stance: int = Stance.DEFEND
# Set by attack_target() — temporarily bypasses stance gating so a HOLD or
# PASSIVE unit will still pursue an explicitly-commanded target. Cleared when
# the target naturally becomes invalid (death/escape) or a fresh user move is
# issued via draft_move_to.
var _force_attack: bool = false

func stance_name() -> String:
	match stance:
		Stance.HOLD:    return "Hold"
		Stance.PASSIVE: return "Passive"
		_:              return "Defend"

func cycle_stance() -> void:
	stance = (stance + 1) % 3
	# HOLD/PASSIVE shouldn't keep an auto-acquired target after the toggle.
	if stance == Stance.HOLD:
		_combat_target = null
		_path_is_combat = false
	queue_redraw()
var attack_fps_side: float = 48.0
var attack_fps_down: float = 48.0
var attack_fps_up: float = 48.0
# Per-unit attack-sprite tuning (defaults match the engineer melee setup).
# Down-attack: top-offset model (sprite-bottom = feet, top overflows above tile).
var attack_down_top_offset: int = 180
# Vertical nudge in source-px (scaled by `s`). Positive = shift sprite DOWN
# from the feet anchor; negative = shift up. Use to fine-tune feet-on-tile
# for attack-down poses where the gun extends low and the body sits higher
# on the canvas than expected.
var attack_down_y_nudge: int = 0
# Up-attack: body-height + feet-y model. PX_PER_CELL = source-px mapped to one
# cell (use the matching walk-up tex height for body-scale parity). FEET_Y bigger
# = sprite shifts up; smaller = shifts down.
var attack_up_px_per_cell: int = 1060
var attack_up_feet_y: int = 1171
# Side-attack alignment: anchor feet & body x-center to match walk-side.
# X_NUDGE shifts TOWARD the facing direction (positive = forward, negative = backward).
var attack_side_px_per_cell: int = 480
var attack_side_feet_y: int = 500
var attack_side_x_nudge: int = 15
# Walk-down: same top-offset model as attack-down. 0 = body fills the cell
# vertically (sprite_h == cell_size). Positive = sprite renders taller than the
# cell, with WALK_DOWN_TOP_OFFSET source-px overflowing above the tile.
var walk_down_top_offset: int = 0
# Vertical nudge in source-px (scaled by `s`). Positive = shift sprite DOWN
# from the feet anchor; negative = shift up. Use to fine-tune feet-on-tile.
var walk_down_y_nudge: int = 0
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
# Lightning storm event briefly stutters the flashlight to sell the storm
# visually. Counts down each frame; while > 0 the flashlight energy gets
# multiplied by a noisy 0.2..1.0 factor.
var _flashlight_flicker_t: float = 0.0
# Sub-timer for flicker target picks. Refreshing every-frame felt like a
# strobe; refreshing every ~0.3s with smooth interpolation between targets
# reads as wind-buffeted light or atmospheric interference.
var _flicker_target_t: float = 0.0
var _flicker_current_k: float = 1.0
var _flicker_next_k: float = 1.0
const _FLASHLIGHT_BASE_ENERGY: float = 1.45
const _GLOW_BASE_ENERGY: float = 1.35
const _FLICKER_TARGET_INTERVAL: float = 0.30
const _FLICKER_LERP_SPEED: float = 6.0
var _move_dir: Vector2 = Vector2.DOWN
var sight_dir: Vector2 = Vector2.DOWN  # public: current cone direction (smoothed)
const STUCK_CHECK_INTERVAL := 0.5
const STUCK_MIN_MOVE := 4.0
# Vision: units only auto-engage enemies they can actually see — anything inside
# the flashlight cone (sight_dir ± half-angle, up to cone range) OR within a
# tight radius around the unit (matches the close ambient glow). Out of sight
# = out of mind: existing combat targets are dropped if they slip out.
const SIGHT_CONE_HALF_ANGLE: float = 0.6632251       # deg_to_rad(38.0)
const SIGHT_CONE_RANGE: float = 896.0                # 128 tex-px * 7 scale (matches flashlight)
# Matches the radial ambient glow's full extent (128px texture * 7 texture_scale
# = 448px radius). Anything inside the visible halo around the unit gets
# auto-engaged in Defend stance regardless of which way the cone is pointing,
# matching the design rule "if the player can see it, the unit reacts."
const SIGHT_NEAR_RADIUS: float = 448.0
var drafted: bool = false:
	set(value):
		drafted = value
		queue_redraw()

# Medic auto-heal: when true, medic scans nearby allies (and self) for the
# best heal-target each tick and burns the smallest-qualifying medicine. Held
# off by efficiency rule (see GUI auto-heal constants) so a 15-HP bandage is
# never spent on a 1-HP scratch unless the patient is in emergency range.
var auto_heal_enabled: bool = false
var _auto_heal_cooldown: float = 0.0
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
	# Register so wave-spawned crabs can locate the nearest live unit via
	# get_tree().get_nodes_in_group("units") — see Crab._find_nearest_unit.
	add_to_group("units")
	# Trigger an initial _draw() so the stance label appears on spawn for
	# undrafted units (drafted units already redraw every frame via _process).
	queue_redraw()


func set_character_textures(down: Texture2D, side: Texture2D, up: Texture2D = null) -> void:
	_tex_down = down
	_tex_side = side
	_tex_up = up
	_apply_sprite(down, false)


# Per-character lying-on-ground sprite, shown when HP drops to 0. The body
# stays in the world (not freed) so a teammate with a Revival Injector can
# bring the unit back.
func set_downed_texture(tex: Texture2D) -> void:
	_tex_downed = tex


# Tear down any visible harvest / mine progress bar tied to this unit's
# current target. The saved elapsed time in grid.tree_harvest_progress /
# grid.rock_mine_progress is preserved on purpose — the next worker resumes
# from where this one left off. Safe to call when no bar is shown (no-op).
func _hide_active_progress_bars() -> void:
	if grid == null:
		return
	if harvest_target != Vector2(-1, -1):
		grid.hide_harvest_bar(grid.get_tree_root(harvest_target))
	if mine_target != Vector2(-1, -1):
		grid.hide_mine_bar(mine_target)


# Trigger a lightning-storm flicker on this unit's flashlight. Energy drops
# to a noisy fraction of normal for `duration` seconds, then snaps back. No
# effect on downed / evacuated units (they have no active flashlight).
func flicker_flashlight(duration: float) -> void:
	_flashlight_flicker_t = max(_flashlight_flicker_t, duration)
	# Reset target picker so the storm starts moving toward a fresh value
	# instead of holding whatever k was set before the call.
	_flicker_target_t = 0.0


func _tick_flashlight_flicker(delta: float) -> void:
	if _flashlight_flicker_t <= 0.0:
		return
	_flashlight_flicker_t -= delta
	if _flashlight_flicker_t <= 0.0:
		# Restore base intensities — the storm passed.
		_flicker_current_k = 1.0
		_flicker_next_k = 1.0
		if _flashlight:
			_flashlight.energy = _FLASHLIGHT_BASE_ENERGY
		if _glow:
			_glow.energy = _GLOW_BASE_ENERGY
		_flashlight_flicker_t = 0.0
		return
	# Pick a new target intensity every FLICKER_TARGET_INTERVAL seconds.
	# Bias toward the brighter half of the range (0.55..1.0) so the light
	# reads as wind-buffeted, with occasional dips rather than constant
	# stuttering. Real-feeling rather than strobe-like.
	_flicker_target_t -= delta
	if _flicker_target_t <= 0.0:
		_flicker_target_t = _FLICKER_TARGET_INTERVAL * randf_range(0.7, 1.3)
		# 80% of the time pick a gentle dim (0.55..1.0); 20% a deeper dip.
		if randf() < 0.20:
			_flicker_next_k = randf_range(0.25, 0.55)
		else:
			_flicker_next_k = randf_range(0.55, 1.0)
	# Smoothly approach the target so transitions don't snap.
	_flicker_current_k = lerp(_flicker_current_k, _flicker_next_k, clamp(delta * _FLICKER_LERP_SPEED, 0.0, 1.0))
	if _flashlight:
		_flashlight.energy = _FLASHLIGHT_BASE_ENERGY * _flicker_current_k
	if _glow:
		_glow.energy = _GLOW_BASE_ENERGY * _flicker_current_k


# Mark this unit as boarded on the evac shuttle. Hides the sprite and pulls
# the unit out of the "units" group so crabs stop hunting them. The Unit node
# stays in the tree (so the WaveManager's victory check can still find it via
# Main.all_units), it just no longer participates in the world.
func evacuate() -> void:
	if evacuated:
		return
	evacuated = true
	visible = false
	if is_in_group("units"):
		remove_from_group("units")
	if _flashlight:
		_flashlight.enabled = false
	if _glow:
		_glow.enabled = false
	# Cancel anything in flight so a half-finished task doesn't keep ticking.
	_hide_active_progress_bars()
	path.clear()
	task_queue.clear()
	harvest_target = Vector2(-1, -1)
	build_target = Vector2(-1, -1)
	gather_target = Vector2(-1, -1)
	repair_target = Vector2(-1, -1)
	demolish_target = Vector2(-1, -1)
	mine_target = Vector2(-1, -1)
	revive_target = null
	if relay_target != Vector2(-1, -1):
		clear_relay_target()
	_combat_target = null


# Render the unconscious body. Sprite anchored at the unit's feet; height
# fits roughly one cell so the body lies flat on the tile rather than
# occupying multiple rows like a standing pose.
func _apply_downed_sprite(tex: Texture2D) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = false
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(tex.get_height())
	sprite.scale = Vector2(s, s)
	var scaled_w := s * float(tex.get_width())
	var scaled_h := s * float(tex.get_height())
	sprite.position = Vector2(-scaled_w * 0.5, -scaled_h)
	sprite.modulate = Color(1, 1, 1, 1)
	if _shadow:
		_shadow.texture = tex
		_shadow.flip_h = false
		_shadow.scale = Vector2(s * 1.05, s * 0.5)
		_shadow.position = Vector2(-scaled_w * 0.55 + 2, -scaled_h * 0.35)


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


# Walk-down rendering: scale so (tex_h - WALK_DOWN_TOP_OFFSET) source-px == cell.
# Sprite bottom anchored at feet; the top-offset region overflows above the tile.
# When WALK_DOWN_TOP_OFFSET == 0 this reduces to plain `_apply_sprite(tex, false)`.
func _apply_sprite_walk_down(tex: Texture2D) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = false
	sprite.flip_v = false
	var denom: int = tex.get_height() - walk_down_top_offset
	if denom <= 0:
		denom = tex.get_height()
	var s := float(grid.cell_size) / float(denom)
	sprite.scale = Vector2(s, s)
	var scaled_w := s * tex.get_width()
	var scaled_h := s * float(tex.get_height())
	var y_nudge := s * float(walk_down_y_nudge)
	sprite.position = Vector2(-scaled_w * 0.5, -scaled_h + y_nudge)
	if _shadow:
		_shadow.texture = tex
		_shadow.flip_h = false
		_shadow.scale = Vector2(s * 1.1, s * 0.18)
		_shadow.position = Vector2(-scaled_w * 0.55 + 2, -grid.cell_size * 0.18 + y_nudge)

func _draw() -> void:
	if drafted:
		_draw_ground_ring(Color(1.0, 0.55, 0.0, 1.0))
		if not path.is_empty():
			_draw_path()
	# Stance now drives autonomous combat for everyone, drafted or not, so the
	# label is always visible — players need to know what an idle colonist will
	# do if a crab wanders past.
	_draw_stance_label()
	if selected:
		_draw_corner_brackets(Color(1.0, 1.0, 1.0, 0.9))
	if _bubble_timer > 0.0 and not _bubble_text.is_empty():
		_draw_speech_bubble()


# Stance label above the head, drafted-only. Bright stance-coded text with a
# dark drop-shadow for legibility on light tiles. Colors picked to be vivid
# rather than pastel, so each stance is unambiguous at a glance:
#   Hold    — amber (restrained, "hold fire")
#   Defend  — green (active, default engagement)
#   Passive — blue (reactive, defensive)
func _draw_stance_label() -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = max(11, grid.cell_size / 10)
	var label: String
	var col: Color
	if is_downed:
		# Pulse the DOWNED label so the body reads as "needs help" at a glance.
		var pulse: float = 0.65 + sin(Time.get_ticks_msec() * 0.005) * 0.35
		label = "DOWNED"
		col = Color(1.0, 0.2, 0.2, pulse)
	else:
		label = stance_name().to_upper()
		match stance:
			Stance.HOLD:    col = Color(1.0, 0.65, 0.15, 1.0)   # amber
			Stance.PASSIVE: col = Color(0.40, 0.70, 1.0, 1.0)   # blue
			_:              col = Color(0.35, 0.95, 0.45, 1.0)  # green
	var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Float the label above the sprite top edge for both standing and downed
	# states. The downed sprite still spans the full cell vertically (it's
	# scaled to cell_size tall), so the lying body would otherwise eat any
	# label drawn into the body's box.
	var label_y: float = -float(grid.cell_size) - 6.0
	var pos: Vector2 = Vector2(-text_w * 0.5, label_y)
	# 1px dark drop-shadow so colored text stays readable on bright sand/water.
	draw_string(font, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


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
	var col := Color(1.0, 0.25, 0.2, 0.85) if _path_is_combat else Color(1, 1, 1, 0.8)
	var fill_col := Color(col.r, col.g, col.b, 0.2)
	var dest_center := _dest_world - global_position
	var prev := Vector2.ZERO  # origin is feet
	for i in range(path.size() - 1):
		var lp := path[i] - global_position
		draw_line(prev, lp, col, 1.5, true)
		prev = lp
	draw_line(prev, dest_center, col, 1.5, true)
	draw_circle(dest_center, 7.0, fill_col)
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


func set_attack_frames_side(frames: Array) -> void:
	_attack_frames_side = frames


func set_attack_frames_down(frames: Array) -> void:
	_attack_frames_down = frames


func set_attack_frames_up(frames: Array) -> void:
	_attack_frames_up = frames


func trigger_attack() -> void:
	if _is_attacking:
		return
	_hit_landed_this_attack = false
	# If the previous attack ended recently, start from the per-direction
	# chain frame to skip the windup/gun-draw intro.
	var chain: bool = _time_since_attack_end < data.attack_cooldown * 2.0
	# Pick direction based on current facing
	var vertical: bool = abs(_move_dir.y) >= abs(_move_dir.x)
	var facing_up: bool = vertical and _move_dir.y < 0.0
	var facing_down: bool = vertical and _move_dir.y >= 0.0
	if facing_up and not _attack_frames_up.is_empty():
		_attack_dir = "up"
		_is_attacking = true
		_attack_frame_idx = clamp(attack_chain_start_up if chain else 0, 0, _attack_frames_up.size() - 1)
		_attack_frame_timer = 0.0
		_apply_sprite_attack_up(_attack_frames_up[_attack_frame_idx])
	elif facing_down and not _attack_frames_down.is_empty():
		_attack_dir = "down"
		_is_attacking = true
		_attack_frame_idx = clamp(attack_chain_start_down if chain else 0, 0, _attack_frames_down.size() - 1)
		_attack_frame_timer = 0.0
		_apply_sprite_attack_down(_attack_frames_down[_attack_frame_idx])
	elif not _attack_frames_side.is_empty():
		_attack_dir = "side"
		_is_attacking = true
		_attack_frame_idx = clamp(attack_chain_start_side if chain else 0, 0, _attack_frames_side.size() - 1)
		_attack_frame_timer = 0.0
		_apply_sprite_attack_side(_attack_frames_side[_attack_frame_idx], _walk_flip_h)
	# Engineer melee fires at the START of the swing animation so the axe
	# "thunk" lines up with the visible swing. Ranged units (Medic, Pilot)
	# fire their pistol on hit-register instead — see _apply_combat_hit —
	# because the muzzle flash / shot beat falls on the hit frame, not
	# the holster-raise windup.
	if _is_attacking and String(data.role) == "Engineer":
		AudioManager.play_2d(Sounds.ENGINEER_MELEE, global_position)


func _apply_combat_hit() -> void:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return
	if _combat_target.has_method("take_damage"):
		_combat_target.take_damage(data.attack_damage, self)
	# Pistol report — per-hit one-shot at the shooter's position so each
	# fired shot pops with the muzzle-flash frame. -6 dB to keep it from
	# burying the rest of the mix. Engineer's melee SFX is fired at swing
	# start instead (see trigger_attack) and is excluded here.
	if String(data.role) != "Engineer":
		AudioManager.play_2d(Sounds.PISTOL_SHOT, global_position, -6.0)


func is_dead() -> bool:
	return data.health <= 0.0


# Damage incoming from a crab (or other attacker). Triggers a brief red flash
# and queue_frees the unit on death.
const _UNIT_HIT_FLASH_DURATION := 0.18
var _unit_hit_flash_t: float = 0.0

func take_damage(amount: int, attacker: Node = null) -> void:
	if data.health <= 0.0 or is_downed:
		return
	# Debug invincibility (toggle in top-left button). Still flash + retaliate
	# so the unit reads as "engaged in combat" — just no HP loss.
	var dmg: float = 0.0 if (gui != null and gui.invincible_units) else float(amount)
	data.health = max(0.0, data.health - dmg)
	_unit_hit_flash_t = _UNIT_HIT_FLASH_DURATION
	# Retaliation: stash the attacker as combat target unless we're holding fire.
	# Drafting still gates whether the combat tick acts on it (see _tick_combat).
	if stance != Stance.HOLD and _combat_target == null and attacker != null and is_instance_valid(attacker):
		if not (attacker.has_method("is_dead") and attacker.is_dead()):
			_combat_target = attacker
	if data.health <= 0.0:
		_enter_downed()


# Knock the unit unconscious. Stops every in-flight task / animation, kills
# the flashlight + glow (so you can tell at a glance the unit is out), swaps
# to the per-character lying sprite. The body persists as a Unit node — never
# queue_freed — so a teammate can right-click it with a Revival Injector.
func _enter_downed() -> void:
	if is_downed:
		return
	is_downed = true
	# Stat hook — counts each going-down as a separate event. Run summary
	# uses this alongside revived_count to show a "downed but saved" tally.
	var main_d: Node = get_tree().root.get_node_or_null("Main")
	if main_d != null and main_d.has_method("record_downed"):
		main_d.record_downed()
	_hide_active_progress_bars()
	path.clear()
	_dest = Vector2(-1, -1)
	_dest_world = Vector2(-1, -1)
	task_queue.clear()
	harvest_target = Vector2(-1, -1)
	build_target = Vector2(-1, -1)
	gather_target = Vector2(-1, -1)
	gather_items = {}
	repair_target = Vector2(-1, -1)
	demolish_target = Vector2(-1, -1)
	revive_target = null
	if relay_target != Vector2(-1, -1):
		clear_relay_target()
	_build_timer = -1.0
	_gather_timer = -1.0
	_repair_timer = -1.0
	_demolish_timer = -1.0
	_harvest_timer = -1.0
	_mine_timer = -1.0
	_stop_work_loop()
	_combat_target = null
	_stop_combat_loop()
	_force_attack = false
	_path_is_combat = false
	_is_walking_side = false
	_is_walking_up = false
	_is_walking_down = false
	_is_attacking = false
	_attack_down_hold = false
	drafted = false
	auto_heal_enabled = false
	if _flashlight:
		_flashlight.enabled = false
	# Keep the body glow active so the player can spot the downed
	# teammate on a dim battlefield — but dimmed so they read as
	# "wounded life sign" rather than "fully alert." A teammate's
	# revive call swaps the energy back via _exit_downed_state.
	if _glow:
		_glow.enabled = true
		_glow.energy = _GLOW_BASE_ENERGY * 0.45
	if _tex_downed:
		_apply_downed_sprite(_tex_downed)
	queue_redraw()


# Restore from the downed state. Re-enables vision lights, sets HP to the
# given amount (clamped to 1..max_health), and resets the sprite back to the
# standing walk-down idle. Caller (the rescuer) is responsible for consuming
# the Revival Injector before this is called.
func _exit_downed_state(hp_amount: float) -> void:
	if not is_downed:
		return
	is_downed = false
	data.health = clamp(hp_amount, 1.0, data.max_health)
	# Stat hook for the run summary.
	var main_r: Node = get_tree().root.get_node_or_null("Main")
	if main_r != null and main_r.has_method("record_revived"):
		main_r.record_revived()
	if _flashlight:
		_flashlight.enabled = true
	if _glow:
		_glow.enabled = true
		# Restore full glow on revive — _enter_downed dimmed it to 45%
		# as the "wounded life sign" cue.
		_glow.energy = _GLOW_BASE_ENERGY
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.modulate = Color(1, 1, 1, 1)
	# Reset to standing walk-down idle pose.
	if _walk_frames_down.size() > _walk_idle_frame_down:
		_apply_sprite_walk_down(_walk_frames_down[_walk_idle_frame_down])
	elif _tex_down:
		_apply_sprite(_tex_down, false)
	queue_redraw()


# Send this unit to channel the Comm Relay Antenna at `anchor`. Walks
# adjacent; on arrival the Grid registers them as the channeler and the
# relay's tick advances the bar. Drafted state is cleared so the player
# can't accidentally walk a channeling unit out of position with a stray
# right-click — they'd need to explicitly reassign.
func queue_relay_channel(anchor: Vector2) -> void:
	if grid == null or not grid.comm_relays.has(anchor):
		return
	# Clear conflicting work — channeling is a focused job.
	harvest_target = Vector2(-1, -1)
	build_target = Vector2(-1, -1)
	gather_target = Vector2(-1, -1)
	gather_items = {}
	repair_target = Vector2(-1, -1)
	_repair_timer = -1.0
	demolish_target = Vector2(-1, -1)
	_demolish_timer = -1.0
	_stop_work_loop()
	mine_target = Vector2(-1, -1)
	_mine_timer = -1.0
	revive_target = null
	_combat_target = null
	_force_attack = false
	# Path to a free tile next to the antenna's 2x2 footprint.
	var dest_cell: Vector2 = _find_relay_destination(anchor)
	if dest_cell == Vector2(-1, -1):
		return
	relay_target = anchor
	_dest_world = grid.gridToWorld(dest_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85)
	path = _set_dest(dest_cell)


# Closest navigable cell touching any cell of the antenna's 2x2 footprint.
func _find_relay_destination(anchor: Vector2) -> Vector2:
	var unit_cell: Vector2 = get_grid_pos()
	var best: Vector2 = Vector2(-1, -1)
	var best_d: float = INF
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			# Skip footprint interior — the unit can't stand on the antenna.
			if dx >= 0 and dx < 2 and dy >= 0 and dy < 2:
				continue
			var c: Vector2 = anchor + Vector2(dx, dy)
			if not grid.grid.has(c) or not grid.grid[c].navigable:
				continue
			var d: float = unit_cell.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	return best


# Called by Grid's relay tick on completion. Drops the relay assignment so
# the unit returns to normal idle behavior.
func clear_relay_target() -> void:
	if relay_target != Vector2(-1, -1) and grid != null:
		grid.release_relay_channeler(relay_target, self)
	relay_target = Vector2(-1, -1)


# Send this unit to revive a downed teammate. Walks to a tile adjacent to the
# body, then _apply_revival fires from move()'s arrival cleanup. Aborts on
# arrival if the target is already gone or the team is out of injectors.
func queue_revive(target: Unit) -> void:
	if target == null or not is_instance_valid(target) or not target.is_downed:
		return
	if target == self or is_downed:
		return
	# Clear conflicting work — revive overrides everything.
	_hide_active_progress_bars()
	harvest_target = Vector2(-1, -1)
	build_target = Vector2(-1, -1)
	repair_target = Vector2(-1, -1)
	_repair_timer = -1.0
	demolish_target = Vector2(-1, -1)
	_demolish_timer = -1.0
	gather_target = Vector2(-1, -1)
	gather_items = {}
	_combat_target = null
	_force_attack = false
	_path_is_combat = false
	var dest_cell: Vector2 = _find_revive_destination(target)
	if dest_cell == Vector2(-1, -1):
		return
	revive_target = target
	_dest_world = grid.gridToWorld(dest_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85)
	path = _set_dest(dest_cell)


# Closest navigable cell touching the downed body. Falls back to the body's
# own cell if every neighbor is blocked (downed bodies don't mark cells
# unnavigable so the unit can stand on top of them in the worst case).
func _find_revive_destination(target: Unit) -> Vector2:
	var target_cell: Vector2 = target.get_grid_pos()
	var unit_cell: Vector2 = get_grid_pos()
	var best: Vector2 = Vector2(-1, -1)
	var best_d: float = INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2 = target_cell + Vector2(dx, dy)
			if not grid.grid.has(c) or not grid.grid[c].navigable:
				continue
			var d: float = unit_cell.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	if best == Vector2(-1, -1) and grid.grid.has(target_cell) and grid.grid[target_cell].navigable:
		return target_cell
	return best


# Consume one Revival Injector from the shared team pool and bring `target`
# back to ~40% HP. No-op if injectors are unavailable or the body was already
# revived between dispatch and arrival.
func _apply_revival(target: Unit) -> void:
	if target == null or not is_instance_valid(target) or not target.is_downed:
		return
	if not _pull_shared_resource("Revival Injector", 1):
		show_speech("Out of Revival Injectors!", true)
		return
	target._exit_downed_state(target.data.max_health * 0.4)
	show_speech("On your feet!")


# Restore HP up to max_health. Returns the actual amount healed (0 if already
# at full HP or already dead).
func apply_heal(amount: float) -> float:
	if data.health <= 0.0 or amount <= 0.0:
		return 0.0
	var before: float = data.health
	data.health = min(data.max_health, data.health + amount)
	return data.health - before


func _find_nearest_enemy() -> Node:
	if grid == null:
		return null
	var aggro_world: float = data.aggro_range_tiles * float(grid.cell_size)
	var best_d: float = aggro_world
	var best: Node = null
	for c in grid.crabs:
		if not is_instance_valid(c) or (c.has_method("is_dead") and c.is_dead()):
			continue
		# Visibility gate: only see crabs in the cone or within the close glow.
		var anchor: Vector2 = c.global_position
		if c is Crab:
			anchor += Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
		if not _can_see(anchor):
			continue
		var d: float = global_position.distance_to(anchor)
		if d < best_d:
			best_d = d
			best = c
	return best


# Cancel any current path/walking visuals so the unit settles into idle before
# attacking. Mirrors the path-empty cleanup inside move().
func _stop_for_combat() -> void:
	path.clear()
	_dest = Vector2(-1, -1)
	_dest_world = Vector2(-1, -1)
	if _is_walking_side:
		if idle_side_tex:
			_apply_sprite_attack_side(idle_side_tex, _walk_flip_h)
		elif _walk_frames_side.size() > _walk_idle_frame_side:
			_apply_sprite(_walk_frames_side[_walk_idle_frame_side], _walk_flip_h)
	elif _is_walking_up:
		if not _walk_frames_up.is_empty():
			_apply_sprite(_walk_frames_up[0], false)
	elif _is_walking_down:
		if _walk_frames_down.size() > _walk_idle_frame_down:
			_apply_sprite_walk_down(_walk_frames_down[_walk_idle_frame_down])
	_is_walking_side = false
	_is_walking_up = false
	_is_walking_down = false
	_walk_frame_idx = 0


func _tick_combat(delta: float) -> void:
	if _combat_cooldown > 0.0:
		_combat_cooldown -= delta
	# Combat-state bookkeeping: any path that nulls _combat_target (HOLD
	# stance, target killed, target out of aggro range, sight broken,
	# manual move override) gets caught here on the next combat tick and
	# (a) stops the pistol loop, (b) resets the post-attack aim-hold
	# sprite back to a normal idle stance. Without (b), ranged units
	# would freeze in their final attack frame after the target dies.
	if _combat_target == null or not is_instance_valid(_combat_target):
		_stop_combat_loop()
		if _was_in_combat:
			_was_in_combat = false
			if not _is_attacking:
				_revert_to_idle_sprite()
	else:
		_was_in_combat = true
	# Combat is gated by stance, not drafted state. Drafted only affects whether
	# the unit accepts player commands (move / attack-target). Undrafted units
	# can still defend themselves or auto-engage based on stance.
	if _is_attacking:
		return
	# Don't override active tasks (gather/build/harvest)
	if _gather_timer >= 0.0 or _build_timer >= 0.0:
		return
	if gather_target != Vector2(-1, -1) or build_target != Vector2(-1, -1) or harvest_target != Vector2(-1, -1):
		return
	# HOLD without an explicit attack-target: full combat off.
	if stance == Stance.HOLD and not _force_attack:
		_combat_target = null
		_path_is_combat = false
		return
	# Refresh target — drop if out of aggro range, dead, or out of sight.
	if _combat_target != null:
		if not is_instance_valid(_combat_target):
			_combat_target = null
		elif _combat_target.has_method("is_dead") and _combat_target.is_dead():
			_combat_target = null
		else:
			var aggro_world: float = data.aggro_range_tiles * float(grid.cell_size)
			var anchor_check: Vector2 = _combat_target_anchor()
			if global_position.distance_to(anchor_check) > aggro_world * 1.5:
				_combat_target = null
			elif not _can_see(anchor_check):
				_combat_target = null
	if _combat_target == null:
		# Forced engagement is over — back to whatever the stance dictates.
		_force_attack = false
		_path_is_combat = false
		# HOLD/PASSIVE skip proactive scans; PASSIVE relies on take_damage to
		# re-arm _combat_target if struck.
		if stance == Stance.HOLD or stance == Stance.PASSIVE:
			return
		_combat_target = _find_nearest_enemy()
	if _combat_target == null:
		return
	var anchor: Vector2 = _combat_target_anchor()
	var to_t: Vector2 = anchor - global_position
	var dist_world: float = to_t.length()
	var attack_range_world: float = data.attack_range_tiles * float(grid.cell_size)
	if dist_world <= attack_range_world:
		# In range — face target and attack on cooldown
		if not path.is_empty():
			_stop_for_combat()
		_path_is_combat = false
		_move_dir = to_t.normalized() if dist_world > 0.001 else _move_dir
		if abs(_move_dir.x) > abs(_move_dir.y):
			_walk_flip_h = _move_dir.x < 0
		if _combat_cooldown <= 0.0:
			trigger_attack()
			_combat_cooldown = data.attack_cooldown
	else:
		# Approach — repath if we don't have one or target moved noticeably
		if path.is_empty() or _last_path_target_pos.distance_to(anchor) > float(grid.cell_size) * 0.7:
			draft_move_to(anchor, true)
			_last_path_target_pos = anchor
			_path_is_combat = true


# Explicit user command: "attack THIS thing", regardless of stance. Clears any
# task and forces engagement. Stance still applies to *future* auto-acquisition
# after this target dies/escapes — Hold and Passive will not pick a new enemy.
func attack_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.is_dead():
		return
	_combat_target = target
	_force_attack = true


# Visual-center of the current combat target. Crabs are Node2Ds with the sprite
# anchored top-left (centered=false), so their `global_position` is the cell's
# top-left corner, not its centre — pathing straight there always biased the
# approach toward the upper-left of the crab. This corrects for that.
func _combat_target_anchor() -> Vector2:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return global_position
	var p: Vector2 = _combat_target.global_position
	if _combat_target is Crab:
		p += Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	return p


# True iff `world_pos` is inside the unit's flashlight cone (forward arc within
# SIGHT_CONE_HALF_ANGLE of sight_dir, up to SIGHT_CONE_RANGE) OR inside the
# close-range glow around the unit (SIGHT_NEAR_RADIUS). Both checks share the
# same origin: roughly hip-height, matching where the flashlight is anchored.
func _can_see(world_pos: Vector2) -> bool:
	var origin: Vector2 = global_position + Vector2(0.0, -float(grid.cell_size) * 0.5)
	var to_t: Vector2 = world_pos - origin
	var d: float = to_t.length()
	if d <= SIGHT_NEAR_RADIUS:
		return true
	# Player-built light sources (campfires, floodlights) act as additional
	# sight: anything inside any building light's radius is visible to the
	# team, even if outside the unit's own cone. The team-wide check fires
	# once per _can_see call but the building list is small.
	if grid != null and grid.has_method("get_building_lights"):
		for entry in grid.get_building_lights():
			if (entry.world_pos as Vector2).distance_to(world_pos) <= float(entry.radius):
				return true
	if d > SIGHT_CONE_RANGE or d <= 0.001:
		return d <= 0.001
	var dot_v: float = sight_dir.dot(to_t / d)
	if dot_v <= 0.0:
		return false
	return acos(clamp(dot_v, -1.0, 1.0)) <= SIGHT_CONE_HALF_ANGLE


# Sideways attack: anchor feet at ATTACK_SIDE_FEET_Y (matches walk-side feet
# elevation) and shift the bounding box toward the facing direction by
# ATTACK_SIDE_X_NUDGE source-px so the body x-center aligns with walk-side.
func _apply_sprite_attack_side(tex: Texture2D, flip_h: bool) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = flip_h
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(attack_side_px_per_cell)
	sprite.scale = Vector2(s, s)
	var scaled_w := s * tex.get_width()
	var x_nudge := s * float(attack_side_x_nudge) * (-1.0 if flip_h else 1.0)
	sprite.position = Vector2(-scaled_w * 0.5 + x_nudge, -s * float(attack_side_feet_y))


# Downward attack: scale so the sprite bottom touches the tile bottom (feet)
# AND ATTACK_DOWN_TOP_OFFSET source-pixels overflow above the tile top.
# Total world height needed = cell_size + overflow_world
# where overflow_world = ATTACK_DOWN_TOP_OFFSET * s, and s = total_world_h / tex_h
# Solving: s = cell_size / (tex_h - ATTACK_DOWN_TOP_OFFSET)
func _apply_sprite_attack_down(tex: Texture2D) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = false
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(tex.get_height() - attack_down_top_offset)
	sprite.scale = Vector2(s, s)
	var scaled_w := s * tex.get_width()
	var scaled_h := s * float(tex.get_height())
	var y_nudge: float = s * float(attack_down_y_nudge)
	# bottom of sprite at feet (y=0), top overflows upward; nudge shifts down.
	sprite.position = Vector2(-scaled_w * 0.5, -scaled_h + y_nudge)


# Upward attack: scale so the body (head->feet, ATTACK_UP_BODY_PX source-px)
# fills one cell, then position the sprite so the feet (at ATTACK_UP_FEET_Y in
# source) land at the tile bottom. Anything above the head naturally overflows
# upward (the raised weapon); transparent padding below the feet is ignored.
func _apply_sprite_attack_up(tex: Texture2D) -> void:
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.texture = tex
	sprite.flip_h = false
	sprite.flip_v = false
	var s := float(grid.cell_size) / float(attack_up_px_per_cell)
	sprite.scale = Vector2(s, s)
	var scaled_w := s * tex.get_width()
	sprite.position = Vector2(-scaled_w * 0.5, -s * float(attack_up_feet_y))


func _tick_attack_anim(delta: float) -> void:
	if not _is_attacking:
		return
	var frames: Array
	var fps: float
	match _attack_dir:
		"down":
			frames = _attack_frames_down
			fps = attack_fps_down
		"up":
			frames = _attack_frames_up
			fps = attack_fps_up
		_:
			frames = _attack_frames_side
			fps = attack_fps_side
	if frames.is_empty():
		_is_attacking = false
		return
	_attack_frame_timer += delta
	while _attack_frame_timer >= 1.0 / fps:
		_attack_frame_timer -= 1.0 / fps
		_attack_frame_idx += 1
		if not _hit_landed_this_attack and _attack_frame_idx >= int(float(frames.size()) * data.attack_hit_ratio):
			_hit_landed_this_attack = true
			_apply_combat_hit()
		if _attack_frame_idx >= frames.size():
			_is_attacking = false
			_time_since_attack_end = 0.0
			# Between chained shots, hold the last attack frame (weapon drawn,
			# aiming) instead of flickering back to the holstered idle pose.
			# Only revert to idle when there's no active target (truly disengaged).
			var still_in_combat: bool = _combat_target != null and is_instance_valid(_combat_target) and not (_combat_target.has_method("is_dead") and _combat_target.is_dead())
			match _attack_dir:
				"down":
					_attack_down_hold = true
					_apply_sprite_attack_down(frames[frames.size() - 1])
				"up":
					if still_in_combat:
						_apply_sprite_attack_up(frames[frames.size() - 1])
					elif not _walk_frames_up.is_empty():
						_apply_sprite(_walk_frames_up[0], false)
					elif _tex_up:
						_apply_sprite(_tex_up, false)
				_:
					if still_in_combat:
						_apply_sprite_attack_side(frames[frames.size() - 1], _walk_flip_h)
					elif idle_side_tex:
						_apply_sprite_attack_side(idle_side_tex, _walk_flip_h)
					else:
						_apply_sprite(_walk_frames_side[_walk_idle_frame_side] if _walk_frames_side.size() > _walk_idle_frame_side else _tex_side, _walk_flip_h)
			return
	match _attack_dir:
		"down":
			_apply_sprite_attack_down(frames[_attack_frame_idx])
		"up":
			_apply_sprite_attack_up(frames[_attack_frame_idx])
		_:
			_apply_sprite_attack_side(frames[_attack_frame_idx], _walk_flip_h)


func set_walk_frames_side(frames: Array) -> void:
	_walk_frames_side = frames
	_walk_frame_idx = 0
	_walk_frame_timer = 0.0


func set_walk_frames_up(frames: Array) -> void:
	_walk_frames_up = frames


func set_walk_frames_down(frames: Array) -> void:
	_walk_frames_down = frames
	if frames.size() > _walk_idle_frame_down:
		_apply_sprite_walk_down(frames[_walk_idle_frame_down])


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
	_flashlight.energy = 1.45
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
	glow.energy = 1.35
	glow.texture_scale = 7.0
	glow.blend_mode = PointLight2D.BLEND_MODE_MIX
	glow.position = Vector2(0.0, -grid.cell_size * 0.5)
	add_child(glow)
	_glow = glow

const OBSTACLE_BOTTOM_CLEARANCE := 12.0

func _process(delta: float) -> void:
	if evacuated:
		return
	if _flashlight == null and grid != null:
		_setup_flashlight()
	# Downed: body persists in the world, but no AI / movement / combat ticks
	# fire. The unit thaws when a teammate calls _exit_downed_state via revival.
	if is_downed:
		_tick_bubble(delta)
		z_index = int((position.y - grid.cell_size * 0.5) / grid.cell_size)
		# Keep redrawing so the pulsing "DOWNED" label animates.
		queue_redraw()
		return
	# Chain-window timer: only ticks when fully disengaged. While pursuing a
	# target (chase or in-range pause), the gun is still considered drawn, so
	# the timer freezes — chained shots keep working across long approaches
	# even when the crab is moving around. Resumes ticking once the target is
	# dropped (dead/escaped/out of sight).
	if not _is_attacking and _time_since_attack_end < 1000.0:
		if _combat_target == null or not is_instance_valid(_combat_target):
			_time_since_attack_end += delta
	_tick_combat(delta)
	move(delta)
	_tick_separation(delta)
	_tick_obstacle_clearance()
	_tick_stuck_check(delta)
	_tick_attack_anim(delta)
	_tick_walk_anim(delta)
	_tick_gather(delta)
	_tick_build(delta)
	_tick_repair(delta)
	_tick_demolish(delta)
	_tick_harvest(delta)
	_tick_mine(delta)
	_tick_flashlight_flicker(delta)
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
	_tick_hit_flash(delta)
	_tick_auto_heal(delta)


func _tick_hit_flash(delta: float) -> void:
	if _unit_hit_flash_t <= 0.0:
		return
	_unit_hit_flash_t -= delta
	var s := get_node_or_null("Sprite2D") as Sprite2D
	if s == null:
		return
	if _unit_hit_flash_t <= 0.0:
		s.modulate = Color(1, 1, 1, 1)
		return
	var k: float = clamp(_unit_hit_flash_t / _UNIT_HIT_FLASH_DURATION, 0.0, 1.0)
	s.modulate = Color(1.0, lerp(1.0, 0.3, k), lerp(1.0, 0.3, k), 1.0)


# Medic auto-heal tick. Runs only on medics with the toggle on. Picks the
# lowest-HP ally within range (incl. self), then the smallest medicine whose
# heal value is "efficient" enough — never wasting a 40-HP medical supply on
# a 1-HP scratch. Emergency rule: HP < AUTO_HEAL_EMERGENCY_PCT bypasses the
# efficiency check, since "any heal is better than dying."
func _tick_auto_heal(delta: float) -> void:
	if not auto_heal_enabled or data.role != "Medic":
		return
	# Heal priority OFF in the Work tab disables auto-heal too — gives the
	# player one place to control all auto-work, not two scattered toggles.
	if int(data.work_priorities.get("heal", 0)) <= 0:
		return
	if is_dead():
		return
	if _auto_heal_cooldown > 0.0:
		_auto_heal_cooldown -= delta
		return

	var range_world: float = gui.AUTO_HEAL_RANGE_TILES * float(grid.cell_size)
	var best_target: Unit = null
	var best_missing: float = 0.0
	# Self is a valid target; include in the same scan.
	for sibling in get_parent().get_children():
		if not (sibling is Unit):
			continue
		var u: Unit = sibling as Unit
		if not is_instance_valid(u) or u.is_dead():
			continue
		if u != self and global_position.distance_to(u.global_position) > range_world:
			continue
		var missing: float = u.data.max_health - u.data.health
		if missing > best_missing:
			best_missing = missing
			best_target = u
	if best_target == null or best_missing <= 0.0:
		return

	# Sort heal items ascending by base heal value; the smallest qualifying
	# item wins. Iterating sorted means the first qualifier is also the most
	# efficient one for this wound size.
	var items: Array = []
	for item: String in gui.HEAL_AMOUNTS.keys():
		var count: int = int(data.inventory.get(item, 0))
		if count <= 0:
			continue
		items.append({"name": item, "base": float(gui.HEAL_AMOUNTS[item])})
	if items.is_empty():
		return
	items.sort_custom(func(a, b): return a["base"] < b["base"])

	var emergency: bool = (best_target.data.health / best_target.data.max_health) < gui.AUTO_HEAL_EMERGENCY_PCT
	for entry in items:
		var actual: float = entry["base"] * gui.MEDIC_HEAL_MULT
		var effective: float = min(actual, best_missing)
		if emergency or (effective / actual) >= gui.AUTO_HEAL_EFFICIENCY:
			# Apply this item.
			data.inventory[entry["name"]] = int(data.inventory[entry["name"]]) - 1
			if int(data.inventory[entry["name"]]) <= 0:
				data.inventory.erase(entry["name"])
			best_target.apply_heal(actual)
			_auto_heal_cooldown = gui.AUTO_HEAL_COOLDOWN
			return


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
	if _is_attacking:
		return
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
	if _is_walking_down:
		_apply_sprite_walk_down(frames[_walk_frame_idx])
	else:
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
		# Fire the unified pickup feedback (toast + SFX) so collecting
		# driftwood / crate items feels the same as harvest / mine drops.
		# Position above the source cell, not the worker, so the player's
		# eye stays on what they just emptied.
		if gui != null and gui.has_method("notify_loot_batch"):
			var src_world: Vector2 = grid.gridToWorld(gather_target) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.3)
			gui.notify_loot_batch(src_world, actual)
		_notify_team_inventory_changed()
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
	# Construction loop ends when the build tick wraps up — same pattern
	# as harvest / mine. Cancellation paths (move-override, downed,
	# blueprint pulled out from under the worker) already call
	# _stop_work_loop, so we don't need to scatter more stop calls here.
	_stop_work_loop()
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
					_attack_down_hold = false
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
			if idle_side_tex:
				_apply_sprite_attack_side(idle_side_tex, _walk_flip_h)
			elif _walk_frames_side.size() > _walk_idle_frame_side:
				_apply_sprite(_walk_frames_side[_walk_idle_frame_side], _walk_flip_h)
			_walk_frame_idx = 0
		elif _is_walking_up:
			if not _walk_frames_up.is_empty():
				_apply_sprite(_walk_frames_up[0], false)
			_walk_frame_idx = 0
		elif _is_walking_down:
			if not _attack_down_hold:
				if _walk_frames_down.size() > _walk_idle_frame_down:
					_apply_sprite_walk_down(_walk_frames_down[_walk_idle_frame_down])
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
			# Arrived adjacent to the tree — pick up where the previous chopper
			# left off (if any) by reading the saved elapsed time, and show the
			# progress bar above the trunk so the player can see the timer.
			var hroot: Vector2 = grid.get_tree_root(harvest_target)
			if not grid.tree_lights_by_root.has(hroot):
				# Tree fell between dispatch and arrival.
				harvest_target = Vector2(-1, -1)
				_start_next_task()
				return
			var hsaved: float = float(grid.tree_harvest_progress.get(hroot, 0.0))
			_harvest_timer = max(0.01, HARVEST_DURATION - hsaved)
			grid.show_harvest_bar(hroot)
			grid.update_harvest_bar(hroot, hsaved / HARVEST_DURATION)
			_start_work_loop(Sounds.TREE_CHOP_LOOP)
			return
		if mine_target != Vector2(-1, -1):
			# Arrived adjacent to the rock — same shape as harvest, with saved
			# mining progress restored from the rock's cell.
			if not _is_mineable(mine_target):
				mine_target = Vector2(-1, -1)
				_start_next_task()
				return
			var msaved: float = float(grid.rock_mine_progress.get(mine_target, 0.0))
			_mine_timer = max(0.01, MINE_DURATION - msaved)
			grid.show_mine_bar(mine_target)
			grid.update_mine_bar(mine_target, msaved / MINE_DURATION)
			# Source sample is louder than the chop loop; -8 dB brings it
			# into balance with tree harvesting and other ambient SFX.
			_start_work_loop(Sounds.ROCK_MINE_LOOP, -8.0)
			return
		if build_target != Vector2(-1, -1):
			# Bail if the blueprint was canceled / completed by someone else
			# while we were walking.
			if not grid.blueprints.has(build_target):
				build_target = Vector2(-1, -1)
				_start_next_task()
				return
			var bp: Dictionary = grid.blueprints[build_target]
			var cost: Dictionary = bp.def.cost
			# Deduct materials once per blueprint. If a previous worker already
			# paid (got drafted / killed mid-build), spent_cost is set and we
			# skip the deduct — the materials are committed to this build.
			if not bp.has("spent_cost"):
				var spent: Dictionary = {}
				var ok: bool = true
				for item_name: String in cost.keys():
					var amt: int = int(cost[item_name])
					if not _pull_shared_resource(item_name, amt):
						ok = false
						break
					spent[item_name] = amt
				if not ok:
					# Refund any partial pull so we don't stealthily eat
					# materials when the build can't actually start.
					for item_name: String in spent.keys():
						data.inventory[item_name] = int(data.inventory.get(item_name, 0)) + int(spent[item_name])
					show_speech("Need more materials!", true)
					build_target = Vector2(-1, -1)
					_start_next_task()
					return
				bp["spent_cost"] = spent
			var cost_total := 0
			for v in cost.values():
				cost_total += v
			_build_duration = max(2.0, float(cost_total) * 0.8)
			_build_timer = _build_duration
			grid.start_blueprint_build(build_target)
			_start_work_loop(Sounds.CONSTRUCTION_LOOP)
			return
		if repair_target != Vector2(-1, -1):
			# Arrived next to the damaged wall — start the per-second repair
			# tick. _tick_repair handles resource consumption and HP refill,
			# and bails out if the building is destroyed or fully repaired.
			_repair_timer = REPAIR_TICK_DURATION
			return
		if demolish_target != Vector2(-1, -1):
			# Arrived adjacent to the wall — start the demolish tick. HP
			# drains in chunks (visualized by the building's HP bar) until
			# the wall falls. _tick_demolish handles the drain + cleanup.
			if grid.buildings.has(demolish_target):
				_demolish_timer = DEMOLISH_TICK_DURATION
			else:
				demolish_target = Vector2(-1, -1)
				_start_next_task()
			return
		if revive_target != null:
			# Arrived next to the downed teammate — burn the injector and
			# bring them back. _apply_revival is a no-op if the body's gone
			# or the team's out of Revival Injectors.
			var rt: Unit = revive_target
			revive_target = null
			_apply_revival(rt)
			_start_next_task()
			return
		if relay_target != Vector2(-1, -1):
			# Arrived adjacent to the Comm Relay Antenna — register as
			# the channeler. The Grid's _tick_comm_relays drives progress
			# from here while we stay adjacent. We don't clear relay_target
			# yet — it tells the rest of the unit's logic that we're
			# committed to this relay.
			if grid.start_relay_channel(relay_target, self):
				show_speech("Calling for evac…")
			else:
				# Relay gone or already completed — drop the target.
				relay_target = Vector2(-1, -1)
				_start_next_task()
			return
		_start_next_task()

# Drafted: move to an exact world position, routing via grid for obstacle avoidance.
# world_pos is the intended visual landing point (character feet).
func draft_move_to(world_pos: Vector2, from_combat: bool = false) -> void:
	_hide_active_progress_bars()
	harvest_target = Vector2(-1, -1)
	# Reset combat-path flag; the combat tick re-sets it immediately after this
	# call when the move is for an attack approach. External calls (user move
	# commands) also drop any forced attack so the unit doesn't snap back to
	# chasing the same target after the new move resolves.
	_path_is_combat = false
	if not from_combat:
		_combat_target = null
		_force_attack = false
		# A new move command also abandons any in-progress repair / demolish
		# / harvest / mine / revive / relay channel. Revive + relay paths
		# are always explicit, never auto-recovered — if the player
		# overrides the channeler/rescuer, the relay/body waits for someone
		# else.
		repair_target = Vector2(-1, -1)
		_repair_timer = -1.0
		demolish_target = Vector2(-1, -1)
		_demolish_timer = -1.0
		harvest_target = Vector2(-1, -1)
		_harvest_timer = -1.0
		mine_target = Vector2(-1, -1)
		_mine_timer = -1.0
		_stop_work_loop()
		revive_target = null
		if relay_target != Vector2(-1, -1):
			clear_relay_target()
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


# Queue a harvest task by tree grid position. Drafted units route directly
# (matches the queue_mine / queue_repair drafted branches) so the right-click
# Harvest popup actually starts a chop instead of silently appending to a
# task queue that drafted units never drain.
func queue_harvest(tree_pos: Vector2) -> void:
	if drafted:
		var root: Vector2 = grid.get_tree_root(tree_pos)
		var dest_cell: Vector2 = _closest_adjacent(root)
		if dest_cell == Vector2(-1, -1):
			return
		harvest_target = root
		_dest_world = grid.gridToWorld(dest_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85)
		path = _set_dest(dest_cell)
		return
	task_queue.append({"type": "harvest", "pos": tree_pos})
	if path.is_empty():
		_start_next_task()


# Queue a build task by blueprint top-left grid position.
func queue_build(blueprint_pos: Vector2) -> void:
	task_queue.append({"type": "build", "pos": blueprint_pos})
	if path.is_empty() and not drafted:
		_start_next_task()


# Send this unit to repair the damaged building anchored at `anchor`. Drafted
# units take the job immediately (right-click flow). Undrafted units queue it
# and let _start_next_task dispatch via the priority scheduler.
func queue_repair(anchor: Vector2) -> void:
	if not grid.buildings.has(anchor):
		return
	if drafted:
		var dest_cell: Vector2 = _find_repair_destination(anchor)
		if dest_cell == Vector2(-1, -1):
			return
		repair_target = anchor
		_dest_world = grid.gridToWorld(dest_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85)
		path = _set_dest(dest_cell)
	else:
		task_queue.append({"type": "repair", "pos": anchor})
		if path.is_empty():
			_start_next_task()


# Closest navigable cell that touches any wall cell of the building footprint.
func _find_repair_destination(anchor: Vector2) -> Vector2:
	var b: Dictionary = grid.buildings.get(anchor, {})
	if b.is_empty():
		return Vector2(-1, -1)
	var def: Dictionary = b.def
	var size: Vector2i = def.size
	var unit_cell: Vector2 = get_grid_pos()
	var best: Vector2 = Vector2(-1, -1)
	var best_d: float = INF
	for dx in size.x:
		for dy in size.y:
			if not grid._cell_in_footprint(def, dx, dy):
				continue
			var wall_cell: Vector2 = anchor + Vector2(dx, dy)
			for ddx in range(-1, 2):
				for ddy in range(-1, 2):
					if ddx == 0 and ddy == 0:
						continue
					var adj: Vector2 = wall_cell + Vector2(ddx, ddy)
					if not grid.grid.has(adj):
						continue
					if not grid.grid[adj].navigable:
						continue
					var d: float = unit_cell.distance_to(adj)
					if d < best_d:
						best_d = d
						best = adj
	return best


func _tick_repair(delta: float) -> void:
	if _repair_timer < 0.0 or repair_target == Vector2(-1, -1):
		return
	if not grid.buildings.has(repair_target):
		# Wall destroyed mid-repair (e.g., crab finished it off).
		_stop_repair()
		return
	# Only repair while adjacent — guards against pathfinding failures and
	# accidentally repairing from a distance.
	if not _is_adjacent_to_building(repair_target):
		_stop_repair()
		return
	_repair_timer -= delta
	if _repair_timer > 0.0:
		return
	var b: Dictionary = grid.buildings[repair_target]
	var def: Dictionary = b.def
	var cost: Dictionary = def.cost
	# Pick the primary build resource (first key in cost dict) — wood walls
	# need driftwood, stone walls need iron, etc.
	var resource_name: String = ""
	for k in cost.keys():
		resource_name = k
		break
	if resource_name == "":
		_stop_repair()
		return
	# Treat all live units as a shared inventory pool — pull from anyone who
	# has the resource (instant transfer, no fetch trip). Returns false when
	# the whole team is out of the material.
	if not _pull_shared_resource(resource_name, 1):
		show_speech("Out of " + resource_name + "!", true)
		_stop_repair()
		return
	# HP per tick scales with the building's HP-per-cost ratio so the repair
	# resource budget matches the original build cost (60-HP wood wall costs 6
	# driftwood to build → repairs at 10 HP per driftwood; 200-HP stone wall
	# costs 6 iron → 33 HP per iron).
	var total_cost: float = 0.0
	for v in cost.values():
		total_cost += float(v)
	var hp_per_tick: int = max(1, int(round(float(b.max_hp) / max(total_cost, 1.0))))
	grid.repair_wall_at(repair_target, hp_per_tick)
	# Stop conditions: building destroyed during this tick, or fully repaired.
	if not grid.buildings.has(repair_target):
		_stop_repair()
		return
	var b2: Dictionary = grid.buildings[repair_target]
	if int(b2.hp) >= int(b2.max_hp):
		# Wall fully repaired — drop the indicator so the player sees the
		# task is done. Interruption / draft-out leaves the marker alone so
		# the next worker still knows the wall needs attention.
		grid.clear_task_marker(repair_target)
		_stop_repair()
		return
	_repair_timer = REPAIR_TICK_DURATION


func _stop_repair() -> void:
	repair_target = Vector2(-1, -1)
	_repair_timer = -1.0
	# Chain into the next queued task so undrafted units don't sit idle after
	# a repair finishes / aborts. No-op for drafted units (early-returns).
	_start_next_task()


# Queue a demolish order on the building anchored at `anchor`. On arrival the
# unit drains the building's HP over time until it falls. The Orders command
# tab is the main producer; right-click is not currently wired for demolish
# to avoid mis-clicks on existing walls.
func queue_demolish(anchor: Vector2) -> void:
	if not grid.buildings.has(anchor):
		return
	if drafted:
		return  # Drafted units only do explicit combat / move commands.
	task_queue.append({"type": "demolish", "pos": anchor})
	if path.is_empty():
		_start_next_task()


func _tick_demolish(delta: float) -> void:
	if _demolish_timer < 0.0 or demolish_target == Vector2(-1, -1):
		return
	if not grid.buildings.has(demolish_target):
		# Building went down some other way (crab kill, another demolisher).
		_stop_demolish()
		return
	# Must stay adjacent — guards against pathing failures and prevents
	# remote-demolish if the unit slid off the cell.
	if not _is_adjacent_to_building(demolish_target):
		_stop_demolish()
		return
	_demolish_timer -= delta
	if _demolish_timer > 0.0:
		return
	# Apply one chunk of demolish damage. damage_building drives the HP bar
	# fade + hit flash + auto-cleanup-at-0-HP, so we don't need to check
	# completion here — if the chunk drops HP to 0, _destroy_building runs
	# inside damage_building and the next tick sees buildings.has = false.
	grid.damage_building(demolish_target, DEMOLISH_HP_PER_TICK)
	if not grid.buildings.has(demolish_target):
		_stop_demolish()
		return
	_demolish_timer = DEMOLISH_TICK_DURATION


func _stop_demolish() -> void:
	demolish_target = Vector2(-1, -1)
	_demolish_timer = -1.0
	# Chain into the next task so undrafted units don't sit idle after a
	# demolish finishes / aborts. No-op for drafted (early-returns).
	_start_next_task()


# Chop tick. Counts down HARVEST_DURATION; when it expires the tree falls,
# rolled drops land in this unit's inventory, and a loot toast pops above
# the tree. Each tick also persists the elapsed time to grid.tree_harvest_progress
# so an interrupted worker doesn't reset the chop — the next worker resumes.
func _tick_harvest(delta: float) -> void:
	if _harvest_timer < 0.0 or harvest_target == Vector2(-1, -1):
		return
	var hroot: Vector2 = grid.get_tree_root(harvest_target)
	# Bail if the tree was felled by someone else mid-chop.
	if not grid.tree_lights_by_root.has(hroot):
		grid.hide_harvest_bar(hroot)
		harvest_target = Vector2(-1, -1)
		_harvest_timer = -1.0
		_stop_work_loop()
		_start_next_task()
		return
	_harvest_timer -= delta
	var elapsed: float = clamp(HARVEST_DURATION - _harvest_timer, 0.0, HARVEST_DURATION)
	grid.tree_harvest_progress[hroot] = elapsed
	grid.update_harvest_bar(hroot, elapsed / HARVEST_DURATION)
	if _harvest_timer > 0.0:
		return
	var root: Vector2 = grid.get_tree_root(harvest_target)
	var drops: Dictionary = grid.harvest_tree(harvest_target)
	harvest_target = Vector2(-1, -1)
	_harvest_timer = -1.0
	_stop_work_loop()
	# Tree fall one-shot at the trunk's world position so the sound pans
	# from the tree, not the chopper. Centre of the 3x3 footprint.
	var fall_world: Vector2 = grid.gridToWorld(root) + Vector2(grid.cell_size * 1.5, grid.cell_size * 1.5)
	AudioManager.play_2d(Sounds.TREE_FALL, fall_world)
	if not drops.is_empty():
		for item_name: String in drops.keys():
			data.inventory[item_name] = int(data.inventory.get(item_name, 0)) + int(drops[item_name])
		if gui != null and gui.has_method("notify_loot_batch"):
			# Toast above the tree's centre (3x3 footprint).
			var world: Vector2 = grid.gridToWorld(root) + Vector2(grid.cell_size * 1.5, grid.cell_size * 0.5)
			gui.notify_loot_batch(world, drops)
		_notify_team_inventory_changed()
	_start_next_task()


# Mine tick. Same shape as harvest — counts down MINE_DURATION, then asks
# the grid to remove the rock and roll drops, deposits them, fires a toast.
# Also persists progress per cell so an interrupted miner can be resumed by
# another worker without losing time.
func _tick_mine(delta: float) -> void:
	if _mine_timer < 0.0 or mine_target == Vector2(-1, -1):
		return
	if not _is_mineable(mine_target):
		grid.hide_mine_bar(mine_target)
		mine_target = Vector2(-1, -1)
		_mine_timer = -1.0
		_stop_work_loop()
		_start_next_task()
		return
	_mine_timer -= delta
	var elapsed: float = clamp(MINE_DURATION - _mine_timer, 0.0, MINE_DURATION)
	grid.rock_mine_progress[mine_target] = elapsed
	grid.update_mine_bar(mine_target, elapsed / MINE_DURATION)
	if _mine_timer > 0.0:
		return
	var rock_cell: Vector2 = mine_target
	var drops: Dictionary = grid.mine_at(rock_cell)
	mine_target = Vector2(-1, -1)
	_mine_timer = -1.0
	_stop_work_loop()
	if not drops.is_empty():
		for item_name: String in drops.keys():
			data.inventory[item_name] = int(data.inventory.get(item_name, 0)) + int(drops[item_name])
		if gui != null and gui.has_method("notify_loot_batch"):
			var world: Vector2 = grid.gridToWorld(rock_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
			gui.notify_loot_batch(world, drops)
		_notify_team_inventory_changed()
	_start_next_task()


# Send a unit to mine a rock at `cell`. Drafted units take it immediately;
# undrafted units queue it under the work-priority scheduler.
func queue_mine(cell: Vector2) -> void:
	if not _is_mineable(cell):
		return
	if drafted:
		var dest_cell: Vector2 = _find_mine_destination(cell)
		if dest_cell == Vector2(-1, -1):
			return
		mine_target = cell
		_dest_world = grid.gridToWorld(dest_cell) + Vector2(grid.cell_size * 0.5, grid.cell_size * 0.85)
		path = _set_dest(dest_cell)
	else:
		task_queue.append({"type": "mine", "pos": cell})
		if path.is_empty():
			_start_next_task()


# Closest navigable cell adjacent to the rock cell (8-neighborhood).
# True iff the cell holds something a unit can mine — covers both regular
# rocks and ore deposits. Used by the mine task lifecycle (queue/tick/
# arrival) so a single check stays in sync across all sites.
func _is_mineable(cell: Vector2) -> bool:
	if not grid.grid.has(cell):
		return false
	var occ = grid.grid[cell].occupier
	return occ == "Rock" or occ == "Ore"


func _find_mine_destination(rock_cell: Vector2) -> Vector2:
	var unit_cell: Vector2 = get_grid_pos()
	var best: Vector2 = Vector2(-1, -1)
	var best_d: float = INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2 = rock_cell + Vector2(dx, dy)
			if not grid.grid.has(c) or not grid.grid[c].navigable:
				continue
			var d: float = unit_cell.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	return best


# Tell Main that the team's combined inventory grew so any deferred build
# tasks (waiting on materials) get a fresh dispatch attempt. Silent no-op
# if Main isn't around (shouldn't happen at runtime, but stays safe).
func _notify_team_inventory_changed() -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("notify_inventory_changed"):
		main.notify_inventory_changed()


# Equip an item from this unit's inventory into its matching slot. Returns
# true on success. Fails (silently) when:
#   • the item isn't a registered gear def
#   • the unit's role isn't in the def's `roles` whitelist
#   • the item isn't in the unit's inventory
# If a different item already occupies the slot, it gets unequipped back
# into the inventory first so the player never loses gear.
#
# Stat bonuses from the def's `stats` dict are added directly to the live
# fields on UnitData (attack_damage, max_health, speed, …). max_health
# bonuses also bump current health by the same amount so the player
# perceives an instant heal — feels right for armour swaps and avoids
# the "equipped armor but my HP is still 80/120" surprise.
func equip_gear(item_name: String) -> bool:
	if not GearDefs.is_gear(item_name):
		return false
	var def: Dictionary = GearDefs.get_def(item_name)
	if not GearDefs.role_can_equip(item_name, String(data.role)):
		return false
	if int(data.inventory.get(item_name, 0)) <= 0:
		return false
	var slot: String = String(def.get("slot", ""))
	if slot == "":
		return false
	# Vacate slot first if occupied — push the existing piece back into
	# inventory rather than destroying it.
	var current: String = String(data.equipped.get(slot, ""))
	if current != "":
		unequip_gear(slot)
	# Decrement inventory count; remove the entry entirely when it hits
	# zero so iterating the inventory doesn't show stale "0" rows.
	data.inventory[item_name] = int(data.inventory[item_name]) - 1
	if int(data.inventory[item_name]) <= 0:
		data.inventory.erase(item_name)
	data.equipped[slot] = item_name
	_apply_gear_stats(def.get("stats", {}), 1)
	_notify_team_inventory_changed()
	return true


# Remove whatever is in `slot` and return it to the inventory. No-op if
# the slot is already empty. Reverts every stat bonus the gear applied.
# Current health is clamped if a max_health drop pulled it past max.
func unequip_gear(slot: String) -> bool:
	var item_name: String = String(data.equipped.get(slot, ""))
	if item_name == "":
		return false
	var def: Dictionary = GearDefs.get_def(item_name)
	data.equipped[slot] = ""
	data.inventory[item_name] = int(data.inventory.get(item_name, 0)) + 1
	_apply_gear_stats(def.get("stats", {}), -1)
	if data.health > data.max_health:
		data.health = data.max_health
	_notify_team_inventory_changed()
	return true


# Walk the gear def's stats dict and add `sign * value` to the matching
# UnitData fields. Sign = +1 on equip, -1 on unequip. max_health bonuses
# also adjust current health so equipping armour heals proportionally and
# unequipping doesn't leave the unit "over-healed".
func _apply_gear_stats(stats: Dictionary, sign_i: int) -> void:
	for key in stats.keys():
		var v: float = float(stats[key]) * float(sign_i)
		match key:
			"attack_damage":
				data.attack_damage = int(data.attack_damage + v)
			"attack_range_tiles":
				data.attack_range_tiles = data.attack_range_tiles + v
			"attack_cooldown":
				data.attack_cooldown = max(0.1, data.attack_cooldown + v)
			"max_health":
				data.max_health = data.max_health + v
				# Equip → heal by bonus; unequip → just shrink the cap.
				if sign_i > 0:
					data.health = min(data.max_health, data.health + v)
			"speed":
				data.speed = max(20.0, data.speed + v)


# Start (or switch to) a looping work-action SFX parented to this unit.
# Idempotent — calling with the same path while already playing is a no-op,
# so it's safe to call from per-frame tick code if needed (currently only
# called on tick start / cancel paths). Audio attenuates by world distance
# from the listener via AudioStreamPlayer2D's built-in falloff.
func _start_work_loop(stream_path: String, volume_db: float = 0.0) -> void:
	if _work_audio_path == stream_path and _work_audio != null and _work_audio.playing:
		return
	if _work_audio != null:
		_work_audio.stop()
		_work_audio.queue_free()
		_work_audio = null
	_work_audio = AudioManager.make_looping_2d(stream_path, self, volume_db)
	_work_audio_path = stream_path
	if _work_audio != null:
		_work_audio.play()


func _stop_work_loop() -> void:
	if _work_audio != null:
		_work_audio.stop()
		_work_audio.queue_free()
		_work_audio = null
	_work_audio_path = ""


# Combat pistol loop. Idempotent — re-calling while already playing is a
# no-op so it's safe to invoke from _apply_combat_hit on every shot
# register. The loop sustains until _stop_combat_loop fires (driven by
# _tick_combat noticing _combat_target went null).
func _start_combat_loop() -> void:
	if _combat_audio != null and _combat_audio.playing:
		return
	if _combat_audio == null:
		_combat_audio = AudioManager.make_looping_2d(Sounds.PISTOL_SHOT, self)
	if _combat_audio != null:
		_combat_audio.play()


func _stop_combat_loop() -> void:
	if _combat_audio == null:
		return
	if _combat_audio.playing:
		_combat_audio.stop()


# Reset the displayed sprite back to an idle pose for the current attack
# direction. _tick_attack_anim's end-of-anim handler holds the last attack
# frame as an "aim hold" pose between chained shots; once combat ends
# nothing runs to clear it, so we apply this from the combat-state
# transition in _tick_combat. Order of preference per direction matches
# the existing post-attack idle code paths so the reset feels consistent.
func _revert_to_idle_sprite() -> void:
	# Engineer holds the last attack-down frame deliberately (axe held in
	# a ready stance reads better than blinking back to a holstered tex).
	# Stay out of the way for that role and direction.
	if String(data.role) == "Engineer" and _attack_dir == "down":
		return
	_attack_down_hold = false
	match _attack_dir:
		"down":
			if not _walk_frames_down.is_empty():
				_apply_sprite_walk_down(_walk_frames_down[_walk_idle_frame_down])
			elif _tex_down:
				_apply_sprite(_tex_down, false)
		"up":
			if not _walk_frames_up.is_empty():
				_apply_sprite(_walk_frames_up[0], false)
			elif _tex_up:
				_apply_sprite(_tex_up, false)
		_:
			if idle_side_tex:
				_apply_sprite_attack_side(idle_side_tex, _walk_flip_h)
			elif not _walk_frames_side.is_empty() and _walk_frames_side.size() > _walk_idle_frame_side:
				_apply_sprite(_walk_frames_side[_walk_idle_frame_side], _walk_flip_h)
			elif _tex_side:
				_apply_sprite(_tex_side, _walk_flip_h)


# Sum of `item_name` across every live unit's inventory. Used by build
# planning to decide whether the team already has enough for a blueprint
# before queueing crate-fetch tasks. Treats downed units as out of the pool
# (they can't hand off until revived).
func _team_count(item_name: String) -> int:
	var total: int = 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		var unit: Unit = u as Unit
		if unit.is_dead() or unit.is_downed:
			continue
		total += int(unit.data.inventory.get(item_name, 0))
	return total


# Pull `amount` of `resource_name` from the shared team pool — own inventory
# first, then any other live unit. Treats all units as one bag so a repairer
# can spend resources their teammates are carrying without walking over to
# fetch (per design: instant transfer between units). Returns true on success;
# on failure (team has fewer than `amount` total), no inventories are modified.
func _pull_shared_resource(resource_name: String, amount: int) -> bool:
	# Build the donor list, self first so the repairer empties their own
	# pockets before raiding teammates.
	var donors: Array = []
	var own: int = int(data.inventory.get(resource_name, 0))
	if own > 0:
		donors.append([self, own])
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u):
			continue
		if (u as Unit).is_dead():
			continue
		var their: int = int((u as Unit).data.inventory.get(resource_name, 0))
		if their > 0:
			donors.append([u, their])
	var total: int = 0
	for d in donors:
		total += int(d[1])
	if total < amount:
		return false
	var remaining: int = amount
	for d in donors:
		var u: Unit = d[0]
		var their: int = int(d[1])
		var take: int = min(their, remaining)
		var inv: Dictionary = u.data.inventory
		var new_count: int = int(inv[resource_name]) - take
		if new_count <= 0:
			inv.erase(resource_name)
		else:
			inv[resource_name] = new_count
		remaining -= take
		if remaining <= 0:
			break
	return true


# True if the unit's grid cell is one of the cells immediately surrounding
# any wall cell of the building anchored at `anchor` (8-neighborhood).
func _is_adjacent_to_building(anchor: Vector2) -> bool:
	var b: Dictionary = grid.buildings.get(anchor, {})
	if b.is_empty():
		return false
	var def: Dictionary = b.def
	var size: Vector2i = def.size
	var unit_cell: Vector2 = get_grid_pos()
	for dx in size.x:
		for dy in size.y:
			if not grid._cell_in_footprint(def, dx, dy):
				continue
			var wall_cell: Vector2 = anchor + Vector2(dx, dy)
			if abs(unit_cell.x - wall_cell.x) <= 1 and abs(unit_cell.y - wall_cell.y) <= 1:
				return true
	return false


func set_drafted(value: bool) -> void:
	# Downed units can't accept the draft — they're unconscious. _enter_downed
	# already clears the drafted flag, but this guard catches the explicit
	# R-key path too so the player can't redraft them mid-revive.
	if is_downed and value:
		return
	drafted = value
	if not path.is_empty():
		_dest = Vector2(-1, -1)
		path = PackedVector2Array([path[0]])
	# Cancel in-progress timers
	_gather_timer = -1.0
	if _build_timer >= 0.0:
		_build_timer = -1.0
		grid.cancel_blueprint_build(build_target)
		_stop_work_loop()
	if not drafted:
		_hide_active_progress_bars()
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

		"repair":
			# Skip if the building is already gone (wall destroyed before this
			# task got dispatched).
			if not grid.buildings.has(task.pos):
				_start_next_task()
				return
			var rdest := _find_repair_destination(task.pos)
			if rdest == Vector2(-1, -1):
				_start_next_task()
				return
			repair_target = task.pos
			path = _set_dest(rdest)

		"demolish":
			if not grid.buildings.has(task.pos):
				_start_next_task()
				return
			var ddest := _find_repair_destination(task.pos)
			if ddest == Vector2(-1, -1):
				_start_next_task()
				return
			demolish_target = task.pos
			path = _set_dest(ddest)

		"mine":
			# Skip if the rock was mined by someone else before we got here.
			if not _is_mineable(task.pos):
				_start_next_task()
				return
			var mdest := _find_mine_destination(task.pos)
			if mdest == Vector2(-1, -1):
				_start_next_task()
				return
			mine_target = task.pos
			path = _set_dest(mdest)

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
	# If the blueprint was already paid for (mid-build interruption), no gather
	# needed — the materials are committed and the next worker just builds.
	var bp: Dictionary = grid.blueprints[blueprint_pos]
	if bp.has("spent_cost"):
		return {}
	var cost: Dictionary = bp.def.cost
	var needed: Dictionary = {}
	for item in cost:
		# Team-pool aware: harvested materials in any unit's pocket count
		# toward what's already on hand. Auto-fetch from crates only kicks
		# in for the genuine deficit.
		var have: int = _team_count(item)
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
		or repair_target != Vector2(-1, -1) \
		or demolish_target != Vector2(-1, -1) \
		or mine_target != Vector2(-1, -1) \
		or revive_target != null \
		or relay_target != Vector2(-1, -1) \
		or _build_timer >= 0.0 \
		or _gather_timer >= 0.0 \
		or _repair_timer >= 0.0 \
		or _demolish_timer >= 0.0 \
		or _harvest_timer >= 0.0 \
		or _mine_timer >= 0.0


func get_grid_pos() -> Vector2:
	return grid.worldToGrid(position + Vector2(-grid.cell_size * 0.5, -grid.cell_size))
