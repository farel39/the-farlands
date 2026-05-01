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

# Bus name every AudioManager-spawned player routes through. Created
# programmatically in _ready (parented to Master) so the project doesn't
# need a custom default_bus_layout.tres. Master controls overall game
# volume; SFX gives the player a separate slider for sound effects vs.
# everything else.
const SFX_BUS_NAME: String = "SFX"


func _ready() -> void:
	# Create the SFX bus if it doesn't already exist. The new bus is
	# parented to Master so master volume still scales SFX too.
	if AudioServer.get_bus_index(SFX_BUS_NAME) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, SFX_BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	# Apply the persisted SFX volume on first load — same pattern as the
	# master volume in SaveManager.apply_settings.
	var v: float = SaveManager.get_sfx_volume()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS_NAME), linear_to_db(max(v, 0.0001)))


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
