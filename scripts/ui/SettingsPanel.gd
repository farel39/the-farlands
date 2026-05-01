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
	panel.custom_minimum_size = Vector2(420, 400)
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

	# SFX volume — controls the "SFX" bus that AudioManager routes every
	# gameplay sound through. Composes with master (sits above SFX in the
	# bus graph), so the player can mute SFX while keeping any future
	# music/voiceover audible.
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	col.add_child(sfx_row)

	var sfx_label := Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.custom_minimum_size = Vector2(160, 32)
	sfx_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sfx_row.add_child(sfx_label)

	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.01
	sfx_slider.value = SaveManager.get_sfx_volume()
	sfx_slider.custom_minimum_size = Vector2(200, 32)
	sfx_row.add_child(sfx_slider)

	var sfx_value := Label.new()
	sfx_value.custom_minimum_size = Vector2(40, 32)
	sfx_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sfx_value.text = "%d%%" % int(sfx_slider.value * 100)
	sfx_row.add_child(sfx_value)

	sfx_slider.value_changed.connect(func(v: float) -> void:
		SaveManager.set_sfx_volume(v)
		sfx_value.text = "%d%%" % int(v * 100)
		var sfx_idx: int = AudioServer.get_bus_index("SFX")
		if sfx_idx != -1:
			AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(max(v, 0.0001)))
	)

	# Brightness — multiplier applied to canvas_modulate in Main._process.
	# 1.0 is the existing day/night look; the slider runs 0.4 → 1.6 so the
	# player can dim or brighten the world to taste. Lives in display so it
	# survives across runs along with fullscreen.
	var br_row := HBoxContainer.new()
	br_row.add_theme_constant_override("separation", 12)
	col.add_child(br_row)

	var br_label := Label.new()
	br_label.text = "Brightness"
	br_label.custom_minimum_size = Vector2(160, 32)
	br_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br_row.add_child(br_label)

	var br_slider := HSlider.new()
	br_slider.min_value = 0.4
	br_slider.max_value = 1.6
	br_slider.step = 0.05
	br_slider.value = SaveManager.get_global_brightness()
	br_slider.custom_minimum_size = Vector2(200, 32)
	br_row.add_child(br_slider)

	var br_value := Label.new()
	br_value.custom_minimum_size = Vector2(50, 32)
	br_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br_value.text = "%d%%" % int(br_slider.value * 100)
	br_row.add_child(br_value)

	br_slider.value_changed.connect(func(v: float) -> void:
		SaveManager.set_global_brightness(v)
		br_value.text = "%d%%" % int(v * 100)
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
