extends Control

const TIPS := [
	"Drafted units (R) auto-engage nearby crabs.",
	"Right-click commands a drafted unit to a specific spot.",
	"Press F to toggle fog of war.",
	"Engineers swing in melee; medics and pilots fire from range.",
	"The atmosphere here corrodes metal faster than expected.",
]

var _scene_path: String = "res://scenes/Main.tscn"
var _progress: Array = []
var _started: bool = false
var _bar: ProgressBar = null
var _percent_label: Label = null


func _ready() -> void:
	if SaveManager and "next_scene" in SaveManager and SaveManager.next_scene != "":
		_scene_path = SaveManager.next_scene
	_build_ui()
	# Defer the load by one frame so the loading screen actually paints first.
	call_deferred("_start_load")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)

	var title := Label.new()
	title.text = "The Farlands"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var loading := Label.new()
	loading.text = "Loading…"
	loading.add_theme_font_size_override("font_size", 18)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(loading)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(420, 18)
	col.add_child(_bar)

	_percent_label = Label.new()
	_percent_label.text = "0%"
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_percent_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)

	var tip := Label.new()
	tip.text = "Tip: " + TIPS[randi() % TIPS.size()]
	tip.add_theme_font_size_override("font_size", 14)
	tip.modulate = Color(0.85, 0.85, 0.9, 0.85)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(420, 0)
	col.add_child(tip)


func _start_load() -> void:
	var err := ResourceLoader.load_threaded_request(_scene_path)
	if err != OK:
		push_error("Threaded load request failed (%s) for %s" % [err, _scene_path])
		# Fallback: direct (blocking) load.
		get_tree().change_scene_to_file(_scene_path)
		return
	_started = true


func _process(_delta: float) -> void:
	if not _started:
		return
	var status := ResourceLoader.load_threaded_get_status(_scene_path, _progress)
	var p: float = 0.0 if _progress.is_empty() else float(_progress[0])
	if _bar:
		_bar.value = p * 100.0
	if _percent_label:
		_percent_label.text = "%d%%" % int(p * 100.0)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(_scene_path) as PackedScene
			if packed:
				get_tree().change_scene_to_packed(packed)
			else:
				get_tree().change_scene_to_file(_scene_path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Threaded load failed for %s; falling back." % _scene_path)
			get_tree().change_scene_to_file(_scene_path)
