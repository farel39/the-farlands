extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 280)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_theme_constant_override("margin_left", 24)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Master volume
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	col.add_child(vol_row)

	var vol_label := Label.new()
	vol_label.text = "Master Volume"
	vol_label.custom_minimum_size = Vector2(160, 32)
	vol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vol_row.add_child(vol_label)

	var vol_slider := HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.01
	vol_slider.value = SaveManager.get_master_volume()
	vol_slider.custom_minimum_size = Vector2(200, 32)
	vol_row.add_child(vol_slider)

	var vol_value := Label.new()
	vol_value.custom_minimum_size = Vector2(40, 32)
	vol_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vol_value.text = "%d%%" % int(vol_slider.value * 100)
	vol_row.add_child(vol_value)

	vol_slider.value_changed.connect(func(v: float) -> void:
		SaveManager.set_master_volume(v)
		vol_value.text = "%d%%" % int(v * 100)
		AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))
	)

	# Fullscreen
	var fs_check := CheckBox.new()
	fs_check.text = "Fullscreen"
	fs_check.button_pressed = SaveManager.get_fullscreen()
	col.add_child(fs_check)
	fs_check.toggled.connect(func(on: bool) -> void:
		SaveManager.set_fullscreen(on)
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	col.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	col.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.pressed.connect(func() -> void:
		SaveManager.save_settings()
		queue_free()
	)
	btn_row.add_child(close_btn)
