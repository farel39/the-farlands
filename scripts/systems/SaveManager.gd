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


# Settings —————————————————————————————————————————————————————————————

func get_master_volume() -> float:
	return float(settings.get_value("audio", "master_volume", 1.0))


func set_master_volume(v: float) -> void:
	settings.set_value("audio", "master_volume", clamp(v, 0.0, 1.0))


func get_fullscreen() -> bool:
	return bool(settings.get_value("display", "fullscreen", false))


func set_fullscreen(on: bool) -> void:
	settings.set_value("display", "fullscreen", on)


func save_settings() -> void:
	settings.save(SETTINGS_PATH)
	apply_settings()


func apply_settings() -> void:
	var v: float = get_master_volume()
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))
	var fs: bool = get_fullscreen()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	)
