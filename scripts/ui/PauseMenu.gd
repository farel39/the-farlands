extends Control

const SETTINGS_SCENE := "res://scenes/SettingsPanel.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const LOADING_SCENE := "res://scenes/LoadingScreen.tscn"
const MAIN_SCENE := "res://scenes/Main.tscn"

var _root_view: Control = null
var _load_view: Control = null
var _save_toast: Label = null
var _toast_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(360, 320)
	margin.add_child(stack)

	_root_view = _build_root_view()
	_root_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_root_view)

	_load_view = _build_load_view()
	_load_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_view.visible = false
	stack.add_child(_load_view)


func _build_root_view() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var slot_label := Label.new()
	slot_label.text = "Current slot: %d" % (SaveManager.current_slot + 1) if SaveManager.current_slot >= 0 else "Current slot: —"
	slot_label.modulate = Color(0.85, 0.85, 0.9, 0.8)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(slot_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)

	_add_btn(col, "Resume", _on_resume)
	_add_btn(col, "Save", _on_save)
	_add_btn(col, "Load", _on_load_show)
	_add_btn(col, "Settings", _on_settings)
	_add_btn(col, "Quit to Main Menu", _on_quit)

	_save_toast = Label.new()
	_save_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_toast.modulate = Color(0.6, 1, 0.6, 0.0)
	col.add_child(_save_toast)
	return col


func _build_load_view() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "Load"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	for i in SaveManager.NUM_SLOTS:
		col.add_child(_build_slot_row(i))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)

	_add_btn(col, "Back", _on_load_back)
	return col


func _build_slot_row(slot: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.custom_minimum_size = Vector2(200, 36)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if SaveManager.has_save(slot):
		var d := SaveManager.get_slot_info(slot)
		var ts := int(d.get("last_played", 0))
		info.text = "Slot %d  ·  %s" % [slot + 1, _format_ts(ts)]
	else:
		info.text = "Slot %d  ·  Empty" % (slot + 1)
	hb.add_child(info)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 36)
	if SaveManager.has_save(slot):
		btn.text = "Load"
		btn.pressed.connect(_on_load_slot.bind(slot))
	else:
		btn.text = "Empty"
		btn.disabled = true
	hb.add_child(btn)

	return hb


func _add_btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 36)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_resume() -> void:
	get_tree().paused = false
	queue_free()


func _on_save() -> void:
	var slot: int = SaveManager.current_slot
	if slot < 0:
		slot = 0
	SaveManager.create_or_touch(slot)
	_show_toast("Saved.")


func _on_load_show() -> void:
	_root_view.visible = false
	_load_view.visible = true


func _on_load_back() -> void:
	_load_view.visible = false
	_root_view.visible = true


func _on_load_slot(slot: int) -> void:
	SaveManager.create_or_touch(slot)
	SaveManager.next_scene = MAIN_SCENE
	get_tree().paused = false
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_settings() -> void:
	var p: Node = load(SETTINGS_SCENE).instantiate()
	add_child(p)


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# If a settings panel is open, let it handle its own Esc; otherwise resume.
		_on_resume()
		get_viewport().set_input_as_handled()


func _show_toast(msg: String) -> void:
	if _save_toast == null:
		return
	_save_toast.text = msg
	_save_toast.modulate = Color(0.6, 1, 0.6, 1)
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(_save_toast, "modulate:a", 0.0, 0.6)


func _format_ts(t: int) -> String:
	if t <= 0:
		return "—"
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%04d-%02d-%02d  %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
