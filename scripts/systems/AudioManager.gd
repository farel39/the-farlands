extends Node


# Project-wide SFX dispatcher. Registered as an autoload so any script can
# call `AudioManager.play_2d(...)` without instantiating a player or
# threading audio nodes through the scene. Routes through the Master bus so
# the Settings → Master Volume slider already controls everything.
#
# Two playback modes:
#   • play_2d(path, world_pos) — positional one-shot. Spawns a temporary
#     AudioStreamPlayer2D at the requested world position; it self-destructs
#     when finished. Use for in-world events (tree fall, hit, pickup) so the
#     listener (camera) gets natural stereo + distance attenuation.
#   • play_ui(path) — non-positional one-shot. For menu clicks, banners, etc.
#
# Streams are cached on first load so we don't re-decode the mp3 every time.
# AudioStreamMP3 instances default to non-looping — we override the loop flag
# inside `_load_stream` for paths whose filename hints at a loop, but the
# loops are also explicitly opted-in by callers via `play_2d_loop`, which
# returns the player so the caller can stop it.


var _stream_cache: Dictionary = {}

# Bus names for routing categorised audio. Created programmatically in
# _ready (both parented to Master) so the project doesn't need a custom
# default_bus_layout.tres. Master controls overall game volume; SFX and
# Music each get their own slider so the player can mute one without
# silencing the other.
const SFX_BUS_NAME: String = "SFX"
const MUSIC_BUS_NAME: String = "Music"

# Music director state. Two AudioStreamPlayer nodes alternate as the
# "active" track + "fading-out" track during crossfades, so we can move
# between thriller and climax tracks without a hard cut.
var _music_a: AudioStreamPlayer = null
var _music_b: AudioStreamPlayer = null
var _music_active: AudioStreamPlayer = null
var _current_music_path: String = ""
# Linear time-scaled crossfade — both players have their volume_db
# tweened in a synchronised pair when the track changes.
var _music_fade_t: float = 0.0
var _music_fade_total: float = 0.0
var _music_fading: bool = false
const _MUSIC_FULL_DB: float = 0.0
const _MUSIC_SILENT_DB: float = -60.0


func _ready() -> void:
	# Create the SFX bus if it doesn't already exist. The new bus is
	# parented to Master so master volume still scales SFX too.
	if AudioServer.get_bus_index(SFX_BUS_NAME) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, SFX_BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	# Music bus, same shape as SFX. Sits next to SFX in the bus graph
	# so master volume scales both, but each has an independent slider.
	if AudioServer.get_bus_index(MUSIC_BUS_NAME) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, MUSIC_BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	# Apply the persisted volumes on first load — same pattern as the
	# master volume in SaveManager.apply_settings.
	var v: float = SaveManager.get_sfx_volume()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS_NAME), linear_to_db(max(v, 0.0001)))
	var mv: float = SaveManager.get_music_volume()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS_NAME), linear_to_db(max(mv, 0.0001)))
	# Pre-instance the two music players so they're ready for the first
	# play_music call without a one-frame init delay.
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = MUSIC_BUS_NAME
	_music_a.volume_db = _MUSIC_SILENT_DB
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = MUSIC_BUS_NAME
	_music_b.volume_db = _MUSIC_SILENT_DB
	add_child(_music_b)
	_music_active = _music_a


# Switch the music track. If `path` matches the currently-playing track
# this is a no-op (so the music director can call it every frame without
# restarting the loop). Otherwise the active player fades out while a
# fresh one fades in over `fade_sec` seconds.
func play_music(path: String, fade_sec: float = 2.0) -> void:
	if path == _current_music_path:
		return
	_current_music_path = path
	if path == "":
		# Empty path means "stop music" — just fade the active out.
		_music_fading = true
		_music_fade_t = 0.0
		_music_fade_total = max(0.05, fade_sec)
		return
	# Mark the streams as looping so the per-track music keeps playing
	# even if the player lingers in a state.
	var stream: AudioStream = _load_stream(path, true)
	if stream == null:
		return
	# Swap active / inactive; the new player gets the new stream and
	# fades up while the old one fades out. _process drives the lerp.
	var fading_out: AudioStreamPlayer = _music_active
	var fading_in: AudioStreamPlayer = _music_b if _music_active == _music_a else _music_a
	fading_in.stream = stream
	fading_in.volume_db = _MUSIC_SILENT_DB
	fading_in.play()
	_music_active = fading_in
	_music_fading = true
	_music_fade_t = 0.0
	_music_fade_total = max(0.05, fade_sec)


# Hard-stop both music players. Used by Main when leaving the game scene
# — change_scene_to_file destroys the AudioManager autoload's children
# anyway, but stopping cleanly first avoids a moment of clipped tail.
func stop_music_immediate() -> void:
	if _music_a != null:
		_music_a.stop()
	if _music_b != null:
		_music_b.stop()
	_current_music_path = ""
	_music_fading = false


func _process(delta: float) -> void:
	if not _music_fading:
		return
	_music_fade_t += delta
	var k: float = clamp(_music_fade_t / _music_fade_total, 0.0, 1.0)
	# Linear fade in dB space — sounds close enough to "constant power"
	# for music transitions without the phasing artifacts a true cosine
	# crossfade can introduce on long ambient pads.
	var fade_in_db: float = lerp(_MUSIC_SILENT_DB, _MUSIC_FULL_DB, k)
	var fade_out_db: float = lerp(_MUSIC_FULL_DB, _MUSIC_SILENT_DB, k)
	for p in [_music_a, _music_b]:
		if p == null:
			continue
		if p == _music_active:
			p.volume_db = fade_in_db
		else:
			p.volume_db = fade_out_db
			# Stop the off-track once it's fully faded — saves a tiny
			# bit of decode work and prevents two streams running
			# silently in the background forever.
			if k >= 1.0 and p.playing:
				p.stop()
	if k >= 1.0:
		_music_fading = false


# Load (and cache) an AudioStream from disk. `loop` toggles the stream's
# loop flag — only meaningful for AudioStreamMP3 / AudioStreamOggVorbis.
# Returns null on failure so callers can early-out.
func _load_stream(path: String, loop: bool) -> AudioStream:
	# Cache key bakes in the loop flag because the same file can be needed
	# both as a one-shot (tree fall, ambience tail) and as a loop elsewhere.
	var key: String = "%s|%s" % [path, str(loop)]
	if _stream_cache.has(key):
		return _stream_cache[key]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: stream not found at %s" % path)
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	_stream_cache[key] = stream
	return stream


# Fire a positional one-shot at `world_pos`. Spawns a temporary
# AudioStreamPlayer2D parented to the autoload node; it auto-frees on
# `finished`. Returns the player so the caller can tweak (e.g. pitch_scale)
# before it starts on the next frame, but most callers can ignore it.
#
# `from_pos` skips the first N seconds of the audio file — useful when a
# source mp3 has silent lead-in (encoder padding / artist breathing room
# before the actual transient) that makes the sound feel desynced from
# the animation. Default 0.0 plays from the start.
func play_2d(path: String, world_pos: Vector2, volume_db: float = 0.0, from_pos: float = 0.0) -> AudioStreamPlayer2D:
	var stream: AudioStream = _load_stream(path, false)
	if stream == null:
		return null
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.global_position = world_pos
	player.volume_db = volume_db
	player.bus = SFX_BUS_NAME
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play(from_pos)
	return player


# Fire a non-positional UI/global one-shot. Same lifecycle as play_2d but
# uses an AudioStreamPlayer (no spatialization).
func play_ui(path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var stream: AudioStream = _load_stream(path, false)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = SFX_BUS_NAME
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


# Build (don't auto-play) a looping AudioStreamPlayer2D parented to `parent`
# so it follows that node in the world. Returns the player; the caller is
# responsible for calling `.play()` and `.queue_free()` (or stopping +
# leaving it for reuse). Used by Unit for chop/mine loops that need to
# start when work begins and stop when it ends.
func make_looping_2d(path: String, parent: Node, volume_db: float = 0.0) -> AudioStreamPlayer2D:
	var stream: AudioStream = _load_stream(path, true)
	if stream == null:
		return null
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = SFX_BUS_NAME
	parent.add_child(player)
	return player
