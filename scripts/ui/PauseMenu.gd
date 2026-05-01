extends Control

const SETTINGS_SCENE := "res://scenes/SettingsPanel.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const LOADING_SCENE := "res://scenes/LoadingScreen.tscn"
const MAIN_SCENE := "res://scenes/Main.tscn"

var _root_view: Control = null
var _load_view: Control = null
var _controls_view: Control = null
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
	# Bumped from 320 → 460 to fit the now-6-button root view (was 5
	# before the Controls button) plus the title, slot label, spacer,
	# and save-toast. The Load and Controls views inherit the same
	# stack so they have headroom too — Controls especially, since
	# its outer column has a vertical scroll plus a Back button below.
	stack.custom_minimum_size = Vector2(360, 460)
	margin.add_child(stack)

	_root_view = _build_root_view()
	_root_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_root_view)

	_load_view = _build_load_view()
	_load_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_view.visible = false
	stack.add_child(_load_view)

	_controls_view = _build_controls_view()
	_controls_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_controls_view.visible = false
	stack.add_child(_controls_view)


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
	_add_btn(col, "Controls", _on_controls_show)
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


func _build_controls_view() -> Control:
	# Reference card listing every input the player can use. Hand-curated
	# from Main._unhandled_input + the GUI's mouse handling. If you bind
	# new keys, add them here too — there's no auto-discovery.
	# Wrapped in a ScrollContainer so the section list can grow beyond
	# the pause panel's fixed 320px height without overflowing.
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Pairs of (binding, description). Grouped by section via header rows.
	var sections: Array = [
		{"header": "Mouse", "rows": [
			["Left-click",            "Select unit or hovered object"],
			["Shift + Left-click",    "Add to / remove from selection"],
			["Click + drag",          "Rectangle-select multiple units"],
			["Right-click",           "Contextual action — move, attack, harvest, mine, cancel"],
		]},
		{"header": "Keyboard", "rows": [
			["A",      "Order selected drafted unit to attack"],
			["R",      "Toggle draft on every selected unit"],
			["ESC",    "Pause / resume — also closes blueprint mode"],
			["F",      "Toggle fog of war (debug)"],
		]},
		{"header": "UI tabs (bottom row)", "rows": [
			["Construct",  "Place buildings (Production / Structures / Lighting / Comms)"],
			["Inventory",  "Pooled team resources, with search"],
			["Units",      "Per-unit stats + character inventory + equipment slots"],
			["Work",       "Per-unit task priorities (HIGH / MED / LOW / OFF)"],
			["Orders",     "Bulk commands — Repair, Harvest, Mine, Demolish, Cancel"],
			["Guide",      "Item glossary — descriptions and where to get every item"],
		]},
		{"header": "Useful right-clicks", "rows": [
			["Right-click tree / rock",   "Order harvest / mine"],
			["Right-click crab corpse?",  "Inspect / loot leftovers from supply crates"],
			["Right-click Fabricator",    "Open craft panel"],
			["Right-click Comm Antenna",  "Start the channel sequence"],
			["Right-click blueprint",     "Cancel + refund materials"],
			["Right-click downed ally",   "Send the closest live unit to revive"],
		]},
	]

	for section: Dictionary in sections:
		var header := Label.new()
		header.text = String(section.header)
		header.add_theme_font_size_override("font_size", 13)
		header.modulate = Color(0.65, 0.78, 0.95, 0.95)
		col.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 2)
		for row in section.rows:
			var key_lbl := Label.new()
			key_lbl.text = String(row[0])
			key_lbl.custom_minimum_size = Vector2(170, 0)
			key_lbl.modulate = Color(0.95, 0.95, 0.65)
			key_lbl.add_theme_font_size_override("font_size", 11)
			grid.add_child(key_lbl)
			var desc_lbl := Label.new()
			desc_lbl.text = String(row[1])
			desc_lbl.add_theme_font_size_override("font_size", 11)
			desc_lbl.modulate = Color(0.88, 0.88, 0.92)
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(desc_lbl)
		col.add_child(grid)

	# Back button sits OUTSIDE the scroll so it's always visible at the
	# bottom of the panel, no matter how far the player has scrolled.
	_add_btn(outer, "Back", _on_controls_back)
	return outer


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
	# Pull the live snapshot from the running Main scene and persist it.
	# Falls back to a metadata-only stub if Main isn't reachable for any
	# reason (defensive — shouldn't happen since save is only available
	# while Main is the active scene).
	var main_node: Node = get_tree().root.get_node_or_null("Main")
	if main_node != null and main_node.has_method("serialize_run"):
		SaveManager.write_run_data(slot, main_node.serialize_run())
		_show_toast("Saved.")
	else:
		SaveManager.create_or_touch(slot)
		_show_toast("Saved (metadata only).")


func _on_load_show() -> void:
	_root_view.visible = false
	_load_view.visible = true


func _on_load_back() -> void:
	_load_view.visible = false
	_root_view.visible = true


func _on_controls_show() -> void:
	_root_view.visible = false
	_controls_view.visible = true


func _on_controls_back() -> void:
	_controls_view.visible = false
	_root_view.visible = true


func _on_load_slot(slot: int) -> void:
	# Queue the slot for Main._apply_pending_load to consume after the
	# scene reloads. current_slot is updated so future Saves overwrite
	# this slot rather than slot 0. We don't write anything here — read
	# happens on the new Main's _ready.
	SaveManager.queued_load_slot = slot
	SaveManager.current_slot = slot
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
	# Time.get_datetime_dict_from_unix_time returns UTC. Shift by the
	# system's timezone bias (in minutes) so the displayed timestamp
	# matches the player's wall clock instead of being N hours off.
	var tz: Dictionary = Time.get_time_zone_from_system()
	var local_unix: int = t + int(tz.get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local_unix)
	return "%04d-%02d-%02d  %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
