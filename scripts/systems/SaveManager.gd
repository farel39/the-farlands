extends Node

# Stub save system: only stores slot metadata for now (the game itself doesn't
# yet persist world state). Loading or creating a slot just sets `current_slot`
# and switches to the main scene; the game starts fresh either way.

const SAVES_DIR := "user://saves/"
const SETTINGS_PATH := "user://settings.cfg"
const NUM_SLOTS := 3

var current_slot: int = -1
var settings: ConfigFile = ConfigFile.new()
# Set by the menu before transitioning to the LoadingScreen so it knows what
# to load. Plain string so callers can target any scene path.
var next_scene: String = "res://scenes/Main.tscn"

# Cross-scene handoff: when the player picks "Load Slot N" in the pause /
# main menu we set this to the slot index and change to the Main scene.
# Main._ready then checks this field after world generation and applies
# the saved state on top of the freshly-spawned world. Reset to -1 once
# consumed so a subsequent "New Game" from the menu doesn't re-trigger.
var queued_load_slot: int = -1

# Save-format version. Bump this any time the serialised dict shape
# changes incompatibly so apply_run_data can refuse stale saves with a
# clear log instead of crashing on a missing field.
const SAVE_FORMAT_VERSION: int = 1


func _ready() -> void:
	var d := DirAccess.open("user://")
	if d and not d.dir_exists("saves"):
		d.make_dir("saves")
	settings.load(SETTINGS_PATH)  # ok if file missing
	apply_settings()


func slot_path(slot: int) -> String:
	return "%sslot_%d.save" % [SAVES_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for i in NUM_SLOTS:
		if has_save(i):
			return true
	return false


# Slot index of the save with the most recent `last_played` timestamp, or
# -1 if no saves exist. Used by the main-menu Continue button so it loads
# the save the player was actually in last.
func get_most_recent_slot() -> int:
	var best_ts: int = -1
	var best_slot: int = -1
	for i in NUM_SLOTS:
		if not has_save(i):
			continue
		var d: Dictionary = get_slot_info(i)
		var ts: int = int(d.get("last_played", 0))
		if ts > best_ts:
			best_ts = ts
			best_slot = i
	return best_slot


func get_slot_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var v: Variant = JSON.parse_string(txt)
	if v is Dictionary:
		return v
	return {}


func create_or_touch(slot: int) -> void:
	var data := get_slot_info(slot)
	if data.is_empty():
		data = {
			"slot": slot,
			"created_at": Time.get_unix_time_from_system(),
		}
	data["last_played"] = Time.get_unix_time_from_system()
	_write(slot, data)
	current_slot = slot


func delete_save(slot: int) -> void:
	var p := slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


func _write(slot: int, data: Dictionary) -> void:
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


# Persist a full run snapshot to a save slot. `run_data` is the dict
# produced by Main.serialize_run(). We merge with the existing slot
# metadata (created_at / first save timestamp) so the slot's history is
# preserved when the player overwrites their save.
func write_run_data(slot: int, run_data: Dictionary) -> void:
	var existing: Dictionary = get_slot_info(slot)
	var merged: Dictionary = run_data.duplicate(true)
	merged["slot"] = slot
	merged["version"] = SAVE_FORMAT_VERSION
	merged["last_played"] = Time.get_unix_time_from_system()
	if existing.has("created_at"):
		merged["created_at"] = existing.created_at
	else:
		merged["created_at"] = Time.get_unix_time_from_system()
	_write(slot, merged)
	current_slot = slot


# Read a run snapshot back. Returns the full dict so the caller can
# inspect both metadata (last_played) and gameplay payload (units,
# buildings, etc.). Empty dict on miss / parse failure.
func read_run_data(slot: int) -> Dictionary:
	return get_slot_info(slot)


# Settings —————————————————————————————————————————————————————————————

func get_master_volume() -> float:
	return float(settings.get_value("audio", "master_volume", 1.0))


func set_master_volume(v: float) -> void:
	settings.set_value("audio", "master_volume", clamp(v, 0.0, 1.0))


# Per-category SFX bus volume — applied to the "SFX" bus that
# AudioManager creates and routes every gameplay sound through. Master
# volume sits above this in the bus graph (SFX → Master), so the two
# sliders compose: master at 50% + SFX at 50% = 25% effective for SFX.
func get_sfx_volume() -> float:
	return float(settings.get_value("audio", "sfx_volume", 1.0))


func set_sfx_volume(v: float) -> void:
	settings.set_value("audio", "sfx_volume", clamp(v, 0.0, 1.0))


func get_fullscreen() -> bool:
	return bool(settings.get_value("display", "fullscreen", false))


func set_fullscreen(on: bool) -> void:
	settings.set_value("display", "fullscreen", on)


# Global brightness multiplier applied to the world canvas in Main._process.
# 1.0 = default (matches the existing day/night cycle exactly), <1.0 dims
# the whole scene, >1.0 brightens. Range clamped to [0.4, 1.6] in the
# setter so a player can't slide to pitch black or fully blow out lighting.
func get_global_brightness() -> float:
	return float(settings.get_value("display", "global_brightness", 1.0))


func set_global_brightness(v: float) -> void:
	settings.set_value("display", "global_brightness", clamp(v, 0.4, 1.6))


func save_settings() -> void:
	settings.save(SETTINGS_PATH)
	apply_settings()


func apply_settings() -> void:
	var v: float = get_master_volume()
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))
	# SFX bus volume — only applies if the SFX bus has been created
	# (AudioManager creates it on autoload init). Defensive lookup so a
	# very-early settings save (e.g. before AudioManager runs) doesn't
	# crash trying to address a nonexistent bus.
	var sfx_idx: int = AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		var sv: float = get_sfx_volume()
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(max(sv, 0.0001)))
	var fs: bool = get_fullscreen()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	)
