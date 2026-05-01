extends Control

# Multi-view main menu: root → Load Game / New Game → (Confirm overwrite).
# Continue button on root jumps straight into the most recent save.

const MAIN_SCENE := "res://scenes/Main.tscn"
const LOADING_SCENE := "res://scenes/LoadingScreen.tscn"
const SETTINGS_SCENE := "res://scenes/SettingsPanel.tscn"

var _settings_panel: Node = null

# View nodes — only one is visible at a time. Rebuilt on demand so save
# timestamps refresh after a load / delete / overwrite without manual
# bookkeeping.
var _stack: Control
var _root_view: Control
var _load_view: Control
var _new_view: Control
var _confirm_view: Control
var _confirm_detail: Label
var _confirm_target_slot: int = -1


func _ready() -> void:
	_build_ui()
	# Documentary track for the main menu — sets the contemplative tone
	# before the player commits to a run. Crossfades to the gameplay
	# track once Main._ready takes over.
	AudioManager.play_music(Sounds.MUSIC_MAIN_MENU, 1.5)


func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Fixed-size stack so views don't reflow as the player navigates between
	# screens with different content lengths.
	_stack = Control.new()
	_stack.custom_minimum_size = Vector2(440, 600)
	center.add_child(_stack)

	_root_view = _build_root_view()
	_stack.add_child(_root_view)

	_load_view = _build_load_view()
	_load_view.visible = false
	_stack.add_child(_load_view)

	_new_view = _build_new_view()
	_new_view.visible = false
	_stack.add_child(_new_view)

	_confirm_view = _build_confirm_view()
	_confirm_view.visible = false
	_stack.add_child(_confirm_view)


# ── View builders ──────────────────────────────────────────────────────────

func _build_root_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "The Farlands"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(_spacer(24))

	# Continue button — disabled when no saves exist; otherwise shows the
	# slot it'll load + the timestamp so the player knows what they're
	# resuming.
	var continue_btn := _make_btn("Continue", _on_continue)
	if SaveManager.has_any_save():
		var slot: int = SaveManager.get_most_recent_slot()
		if slot >= 0:
			var d: Dictionary = SaveManager.get_slot_info(slot)
			var ts: int = int(d.get("last_played", 0))
			continue_btn.text = "Continue  ·  Slot %d  ·  %s" % [slot + 1, _format_ts(ts)]
	else:
		continue_btn.disabled = true
		continue_btn.text = "Continue  ·  (no saves)"
	col.add_child(continue_btn)

	col.add_child(_make_btn("Load Game", _on_show_load))
	col.add_child(_make_btn("New Game", _on_show_new))

	col.add_child(_spacer(20))

	col.add_child(_make_btn("Settings", _on_settings))
	col.add_child(_make_btn("Exit", _on_exit))
	return col


func _build_load_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Load Game"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(_spacer(8))

	var any_save: bool = false
	for i in SaveManager.NUM_SLOTS:
		if SaveManager.has_save(i):
			col.add_child(_build_load_row(i))
			any_save = true

	if not any_save:
		var empty := Label.new()
		empty.text = "No saves yet."
		empty.modulate = Color(0.7, 0.7, 0.75)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(empty)

	col.add_child(_spacer(20))
	col.add_child(_make_btn("Back", _on_show_root))
	return col


func _build_load_row(slot: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER

	var info := Label.new()
	info.custom_minimum_size = Vector2(220, 36)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var d: Dictionary = SaveManager.get_slot_info(slot)
	var ts: int = int(d.get("last_played", 0))
	info.text = "Slot %d  ·  %s" % [slot + 1, _format_ts(ts)]
	hb.add_child(info)

	var load_btn := Button.new()
	load_btn.custom_minimum_size = Vector2(96, 36)
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load.bind(slot))
	hb.add_child(load_btn)

	var del_btn := Button.new()
	del_btn.custom_minimum_size = Vector2(72, 36)
	del_btn.text = "Delete"
	del_btn.modulate = Color(1.0, 0.7, 0.6)
	del_btn.pressed.connect(_on_delete.bind(slot))
	hb.add_child(del_btn)
	return hb


func _build_new_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "New Game"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var hint := Label.new()
	hint.text = "Choose a slot. Existing saves will ask before being overwritten."
	hint.modulate = Color(0.75, 0.75, 0.85)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(380, 0)
	col.add_child(hint)

	col.add_child(_spacer(8))

	for i in SaveManager.NUM_SLOTS:
		col.add_child(_build_new_row(i))

	col.add_child(_spacer(20))
	col.add_child(_make_btn("Back", _on_show_root))
	return col


func _build_new_row(slot: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER

	var info := Label.new()
	info.custom_minimum_size = Vector2(220, 36)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if SaveManager.has_save(slot):
		var d: Dictionary = SaveManager.get_slot_info(slot)
		var ts: int = int(d.get("last_played", 0))
		info.text = "Slot %d  ·  %s" % [slot + 1, _format_ts(ts)]
	else:
		info.text = "Slot %d  ·  Empty" % (slot + 1)
		info.modulate = Color(0.7, 0.7, 0.75)
	hb.add_child(info)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(168, 36)
	if SaveManager.has_save(slot):
		btn.text = "Overwrite"
		btn.modulate = Color(1.0, 0.7, 0.55)
		btn.pressed.connect(_on_request_overwrite.bind(slot))
	else:
		btn.text = "Start"
		btn.pressed.connect(_on_start_new.bind(slot))
	hb.add_child(btn)
	return hb


func _build_confirm_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_spacer(120))

	var title := Label.new()
	title.text = "Overwrite save?"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_confirm_detail = Label.new()
	_confirm_detail.text = ""
	_confirm_detail.modulate = Color(0.92, 0.88, 0.78)
	_confirm_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_detail.custom_minimum_size = Vector2(380, 0)
	col.add_child(_confirm_detail)

	var warn := Label.new()
	warn.text = "This cannot be undone."
	warn.modulate = Color(1.0, 0.55, 0.45)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(warn)

	col.add_child(_spacer(16))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(150, 42)
	cancel_btn.pressed.connect(_on_confirm_cancel)
	btn_row.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Overwrite"
	ok_btn.custom_minimum_size = Vector2(150, 42)
	ok_btn.modulate = Color(1.0, 0.55, 0.45)
	ok_btn.pressed.connect(_on_confirm_overwrite)
	btn_row.add_child(ok_btn)

	col.add_child(btn_row)
	return col


# ── View navigation ────────────────────────────────────────────────────────

func _show_view(view: Control) -> void:
	for v in [_root_view, _load_view, _new_view, _confirm_view]:
		if v != null:
			v.visible = (v == view)


# Rebuild a view fresh before showing — slot timestamps and disabled states
# may have changed since the menu was last constructed.
func _rebuild(view_holder: Control, builder: Callable) -> Control:
	if view_holder != null and view_holder.get_parent() == _stack:
		_stack.remove_child(view_holder)
		view_holder.queue_free()
	var fresh: Control = builder.call()
	fresh.visible = false
	_stack.add_child(fresh)
	return fresh


func _on_show_root() -> void:
	_root_view = _rebuild(_root_view, _build_root_view)
	_show_view(_root_view)


func _on_show_load() -> void:
	_load_view = _rebuild(_load_view, _build_load_view)
	_show_view(_load_view)


func _on_show_new() -> void:
	_new_view = _rebuild(_new_view, _build_new_view)
	_show_view(_new_view)


# ── Actions ────────────────────────────────────────────────────────────────

func _on_continue() -> void:
	var slot: int = SaveManager.get_most_recent_slot()
	if slot < 0:
		return
	_launch(slot, true)


func _on_load(slot: int) -> void:
	_launch(slot, true)


func _on_delete(slot: int) -> void:
	SaveManager.delete_save(slot)
	# Stay on the load view — just refresh it so the deleted slot drops off.
	_on_show_load()


func _on_start_new(slot: int) -> void:
	# Empty slot — straight into a fresh game (no queued load).
	_launch(slot, false)


func _on_request_overwrite(slot: int) -> void:
	_confirm_target_slot = slot
	var d: Dictionary = SaveManager.get_slot_info(slot)
	var ts: int = int(d.get("last_played", 0))
	_confirm_detail.text = "Slot %d will be replaced.\nLast played: %s" % [slot + 1, _format_ts(ts)]
	_show_view(_confirm_view)


func _on_confirm_overwrite() -> void:
	if _confirm_target_slot < 0:
		return
	SaveManager.delete_save(_confirm_target_slot)
	var slot := _confirm_target_slot
	_confirm_target_slot = -1
	_launch(slot)


func _on_confirm_cancel() -> void:
	_confirm_target_slot = -1
	_on_show_new()


func _launch(slot: int, load_existing: bool = false) -> void:
	# When `load_existing` is true (Continue / Load Slot), queue the
	# slot for Main._apply_pending_load to consume after the new scene
	# finishes initialising. For New Game flows we skip the queue so
	# the world stays at fresh-spawn defaults.
	if load_existing:
		SaveManager.queued_load_slot = slot
	else:
		SaveManager.queued_load_slot = -1
	SaveManager.create_or_touch(slot)
	SaveManager.next_scene = MAIN_SCENE
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_settings() -> void:
	if _settings_panel and is_instance_valid(_settings_panel):
		return
	_settings_panel = load(SETTINGS_SCENE).instantiate()
	add_child(_settings_panel)


func _on_exit() -> void:
	get_tree().quit()


# ── Helpers ────────────────────────────────────────────────────────────────

func _make_btn(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 40)
	b.pressed.connect(callback)
	return b


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _format_ts(t: int) -> String:
	if t <= 0:
		return "—"
	# Time.get_datetime_dict_from_unix_time returns UTC. Shift by the
	# system's timezone bias (in minutes) so the displayed timestamp
	# matches the player's wall clock instead of being N hours off.
	var tz: Dictionary = Time.get_time_zone_from_system()
	var local_unix: int = t + int(tz.get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local_unix)
	return "%04d-%02d-%02d  %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
