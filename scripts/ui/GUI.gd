extends Control

signal cut_requested(pos: Vector2)
signal inspect_requested

@onready var grid: Grid = get_tree().root.get_node("Main/Grid")
@onready var camera: Camera2D = get_tree().root.get_node("Main/Camera2D")

const BUILDINGS = {
	"WoodWall":  { "name": "Wood Wall",  "source_id": 4, "layer": 1, "navigable": false },
	"StoneWall": { "name": "Stone Wall", "source_id": 3, "layer": 1, "navigable": false },
	"DirtFloor": { "name": "Dirt Floor", "source_id": 0, "layer": 0, "navigable": true  },
}

const ITEM_ICONS: Dictionary = {
	"Metal Scrap":          "res://art/items/metal scrap realistic.png",
	"Electronics":          "res://art/items/electronics realistic.png",
	"Medical Supplies":     "res://art/items/medical supplies realistic.png",
	"Rations":              "res://art/items/rations realistic.png",
	"Bandages":             "res://art/items/bandages realistic.png",
	"Tools":                "res://art/items/wrench realistic.png",
	"Ammo":                 "res://art/items/bullets realistic.png",
	"Fuel Canister":        "res://art/items/fuel canister realistic.png",
	"Emergency Flare":      "res://art/items/emergency flare realistic.png",
	"Alien Shell":          "res://art/items/alien shell realistic.png",
	"Bioluminescent Algae": "res://art/items/bioluminescent algae realisitc.png",
	"Copper Nugget":        "res://art/items/copper nugget realistic.png",
	"Crab Shell":           "res://art/items/crab shell realistic.png",
	"Driftwood Piece":      "res://art/items/driftwood piece realistic.png",
	"Fiber":                "res://art/items/fiber realistic.png",
	"Iron Chunk":           "res://art/items/iron chunk realistic.png",
	"Sand Glass Shard":     "res://art/items/sand glass shard realistic.png",
	"Strange Egg":          "res://art/items/strange egg realistic.png",
}

const MONOLITH_LINES: Array = [
	"The symbols etched into the stone predate any known civilisation.",
	"You feel a faint vibration beneath your fingertips.",
	"Something about this structure interferes with your instruments.",
	"The stone is warm — far warmer than the surrounding air.",
	"Whoever built this was not human.",
	"The glyphs shift slightly when you're not looking directly at them.",
	"A low hum emanates from within. There is no visible source.",
]

var wood_label: Label
var drafted_label: Label

var _tree_panel: PanelContainer
var _selected_tree: Vector2

var _unit_panel: PanelContainer
var _draft_btn: Button
var _selected_unit: Unit

var _group_panel: PanelContainer
var _group_draft_btn: Button
var _selected_group: Array = []

var _inv_panel: PanelContainer
var _inv_title: Label
var _inv_rows: GridContainer

var _dialog_panel: PanelContainer
var _dialog_portrait: TextureRect
var _dialog_name: Label
var _dialog_role: Label
var _dialog_text: Label
var _dialog_text_sep: HSeparator
var _dialog_draft_btn: Button
var _dialog_rng := RandomNumberGenerator.new()

var _sel_box_active: bool = false
var _sel_box: Rect2

var _construct_panel: PanelContainer
var _construct_vbox: VBoxContainer

var _global_inv_panel: PanelContainer
var _global_inv_vbox: VBoxContainer

var _units_panel: PanelContainer
var _units_vbox: VBoxContainer
var _all_units: Array = []

var _top_hud: HBoxContainer
var _hud_bars: Dictionary = {}          # Unit → ProgressBar
var _last_drafted_ids: Array = []


func _ready() -> void:
	wood_label = Label.new()
	wood_label.position = Vector2(8, 8)
	add_child(wood_label)

	drafted_label = Label.new()
	drafted_label.position = Vector2(8, 28)
	add_child(drafted_label)

	_tree_panel = _build_tree_panel()
	add_child(_tree_panel)

	_unit_panel = _build_unit_panel()
	add_child(_unit_panel)

	_group_panel = _build_group_panel()
	add_child(_group_panel)

	_inv_panel = _build_inventory_panel()
	add_child(_inv_panel)

	_dialog_rng.randomize()
	_dialog_panel = _build_dialog_panel()
	add_child(_dialog_panel)

	_build_construct_ui()
	_build_top_hud()


# ── Panel builders ────────────────────────────────────────────────────────────

func _build_tree_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Tree"
	var cut_btn := Button.new()
	cut_btn.text = "Cut"
	cut_btn.pressed.connect(_on_cut_pressed)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): panel.visible = false)
	vbox.add_child(title)
	vbox.add_child(cut_btn)
	vbox.add_child(cancel)
	panel.add_child(vbox)
	return panel


func _build_unit_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var uname := Label.new()
	uname.text = "Colonist"
	_draft_btn = Button.new()
	_draft_btn.pressed.connect(_on_draft_pressed)
	vbox.add_child(uname)
	vbox.add_child(_draft_btn)
	panel.add_child(vbox)
	return panel


func _build_group_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Group"
	_group_draft_btn = Button.new()
	_group_draft_btn.pressed.connect(_on_group_draft_pressed)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): panel.visible = false)
	vbox.add_child(title)
	vbox.add_child(_group_draft_btn)
	vbox.add_child(cancel)
	panel.add_child(vbox)
	return panel


func _build_inventory_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	_inv_title = Label.new()
	_inv_title.text = "Inventory"
	vbox.add_child(_inv_title)
	_inv_rows = GridContainer.new()
	_inv_rows.columns = 5
	vbox.add_child(_inv_rows)
	vbox.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): panel.visible = false)
	vbox.add_child(close)
	panel.add_child(vbox)
	return panel


func _build_dialog_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(320, 0)
	var vbox := VBoxContainer.new()

	var top := HBoxContainer.new()
	_dialog_portrait = TextureRect.new()
	_dialog_portrait.custom_minimum_size = Vector2(64, 64)
	_dialog_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialog_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialog_portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(_dialog_portrait)
	var name_col := VBoxContainer.new()
	_dialog_name = Label.new()
	_dialog_role = Label.new()
	_dialog_role.modulate = Color(0.7, 0.7, 0.7)
	name_col.add_child(_dialog_name)
	name_col.add_child(_dialog_role)
	top.add_child(name_col)
	vbox.add_child(top)
	vbox.add_child(HSeparator.new())

	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_dialog_text)
	_dialog_text_sep = HSeparator.new()
	vbox.add_child(_dialog_text_sep)

	var btns := HBoxContainer.new()
	_dialog_draft_btn = Button.new()
	_dialog_draft_btn.pressed.connect(_on_dialog_draft_pressed)
	btns.add_child(_dialog_draft_btn)
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	inspect_btn.pressed.connect(_on_inspect_pressed)
	btns.add_child(inspect_btn)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): panel.visible = false)
	btns.add_child(close)
	vbox.add_child(btns)

	panel.add_child(vbox)
	return panel


# ── Construction UI ───────────────────────────────────────────────────────────

func _build_construct_ui() -> void:
	# Panel: anchored to bottom-left, grows upward, fixed width
	_construct_panel = PanelContainer.new()
	_construct_panel.visible = false
	_construct_panel.anchor_left   = 0.0
	_construct_panel.anchor_top    = 1.0
	_construct_panel.anchor_right  = 0.0
	_construct_panel.anchor_bottom = 1.0
	_construct_panel.offset_left   = 0
	_construct_panel.offset_right  = 260
	_construct_panel.offset_bottom = -44
	_construct_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_construct_vbox = VBoxContainer.new()
	_construct_panel.add_child(_construct_vbox)
	add_child(_construct_panel)

	# "Construct" button — bottom-left, above nothing
	var btn := Button.new()
	btn.text = "Construct"
	btn.anchor_left   = 0.0
	btn.anchor_top    = 1.0
	btn.anchor_right  = 0.0
	btn.anchor_bottom = 1.0
	btn.offset_left   = 0
	btn.offset_right  = 120
	btn.offset_top    = -40
	btn.offset_bottom = 0
	btn.pressed.connect(_on_construct_btn_pressed)
	add_child(btn)

	# Global inventory panel — grows upward from above the inventory button
	_global_inv_panel = PanelContainer.new()
	_global_inv_panel.visible = false
	_global_inv_panel.anchor_left   = 0.0
	_global_inv_panel.anchor_top    = 1.0
	_global_inv_panel.anchor_right  = 0.0
	_global_inv_panel.anchor_bottom = 1.0
	_global_inv_panel.offset_left   = 124
	_global_inv_panel.offset_right  = 400
	_global_inv_panel.offset_bottom = -44
	_global_inv_panel.offset_top    = -500
	_global_inv_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_global_inv_vbox = VBoxContainer.new()
	_global_inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_global_inv_vbox)
	_global_inv_panel.add_child(scroll)
	add_child(_global_inv_panel)

	# "Inventory" button — sits right of Construct
	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	inv_btn.anchor_left   = 0.0
	inv_btn.anchor_top    = 1.0
	inv_btn.anchor_right  = 0.0
	inv_btn.anchor_bottom = 1.0
	inv_btn.offset_left   = 124
	inv_btn.offset_right  = 244
	inv_btn.offset_top    = -40
	inv_btn.offset_bottom = 0
	inv_btn.pressed.connect(_on_global_inv_btn_pressed)
	add_child(inv_btn)

	# Units panel — grows upward, scrollable
	_units_panel = PanelContainer.new()
	_units_panel.visible = false
	_units_panel.anchor_left   = 0.0
	_units_panel.anchor_top    = 1.0
	_units_panel.anchor_right  = 0.0
	_units_panel.anchor_bottom = 1.0
	_units_panel.offset_left   = 248
	_units_panel.offset_right  = 530
	_units_panel.offset_bottom = -44
	_units_panel.offset_top    = -500
	_units_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var units_scroll := ScrollContainer.new()
	units_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	units_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_units_vbox = VBoxContainer.new()
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units_scroll.add_child(_units_vbox)
	_units_panel.add_child(units_scroll)
	add_child(_units_panel)

	# "Units" button
	var units_btn := Button.new()
	units_btn.text = "Units"
	units_btn.anchor_left   = 0.0
	units_btn.anchor_top    = 1.0
	units_btn.anchor_right  = 0.0
	units_btn.anchor_bottom = 1.0
	units_btn.offset_left   = 248
	units_btn.offset_right  = 368
	units_btn.offset_top    = -40
	units_btn.offset_bottom = 0
	units_btn.pressed.connect(_on_units_btn_pressed)
	add_child(units_btn)


func _close_bottom_panels() -> void:
	_construct_panel.visible = false
	_global_inv_panel.visible = false
	_units_panel.visible = false


func _on_construct_btn_pressed() -> void:
	if _construct_panel.visible:
		_construct_panel.visible = false
	else:
		_close_bottom_panels()
		_show_categories()


func _show_categories() -> void:
	for c in _construct_vbox.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Build"
	title.name = "CategoryRow"
	_construct_vbox.add_child(title)
	for cat in BuildingDefs.get_categories():
		var btn := Button.new()
		btn.text = cat
		btn.pressed.connect(_show_items.bind(cat))
		_construct_vbox.add_child(btn)
	_construct_panel.visible = true


func _show_items(category: String) -> void:
	for c in _construct_vbox.get_children():
		c.queue_free()
	var back := Button.new()
	back.text = "← Back"
	back.pressed.connect(_show_categories)
	_construct_vbox.add_child(back)
	var title := Label.new()
	title.text = category
	_construct_vbox.add_child(title)
	for bname in BuildingDefs.get_by_category(category):
		var def: Dictionary = BuildingDefs.DEFS[bname]
		var row := HBoxContainer.new()
		# Icon
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var tex := load(def.sprite) as Texture2D
		if tex:
			icon.texture = tex
		row.add_child(icon)
		# Name + cost label
		var info_col := VBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = bname
		info_col.add_child(name_lbl)
		var cost_parts: Array = []
		for item in def.cost:
			cost_parts.append("%s ×%d" % [item, def.cost[item]])
		var cost_lbl := Label.new()
		cost_lbl.text = ", ".join(cost_parts)
		cost_lbl.modulate = Color(0.75, 0.75, 0.75)
		info_col.add_child(cost_lbl)
		row.add_child(info_col)
		# Place button
		var place_btn := Button.new()
		place_btn.text = "Place"
		place_btn.pressed.connect(_on_place_pressed.bind(def))
		row.add_child(place_btn)
		_construct_vbox.add_child(row)


func _on_place_pressed(def: Dictionary) -> void:
	_construct_panel.visible = false
	grid.enter_blueprint_mode(def)


# ── Global inventory ──────────────────────────────────────────────────────────

func _on_global_inv_btn_pressed() -> void:
	if _global_inv_panel.visible:
		_global_inv_panel.visible = false
		return
	_close_bottom_panels()
	_refresh_global_inventory()
	_global_inv_panel.visible = true


func _refresh_global_inventory() -> void:
	for c in _global_inv_vbox.get_children():
		c.queue_free()

	# Collect all sources: ship + crates
	var sources: Array = []
	if not grid.ship_inventory.is_empty():
		sources.append({"label": "Crashed Ship", "inv": grid.ship_inventory})
	for pos in grid.crate_inventories:
		var inv: Dictionary = grid.crate_inventories[pos]
		if not inv.is_empty():
			sources.append({"label": "Crate (%d,%d)" % [int(pos.x), int(pos.y)], "inv": inv})

	# Aggregate totals per item
	var totals: Dictionary = {}
	for src in sources:
		for item in src.inv:
			totals[item] = totals.get(item, 0) + src.inv[item]

	if totals.is_empty():
		var lbl := Label.new()
		lbl.text = "No resources found."
		_global_inv_vbox.add_child(lbl)
		return

	var title := Label.new()
	title.text = "All Resources"
	_global_inv_vbox.add_child(title)
	_global_inv_vbox.add_child(HSeparator.new())

	for item in totals:
		# Item row: icon + name + total
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		if ITEM_ICONS.has(item):
			var tex := load(ITEM_ICONS[item]) as Texture2D
			if tex:
				icon.texture = tex
		row.add_child(icon)
		var name_lbl := Label.new()
		name_lbl.text = item
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var qty_lbl := Label.new()
		qty_lbl.text = "×%d" % totals[item]
		row.add_child(qty_lbl)
		_global_inv_vbox.add_child(row)

		# Sub-rows: where each chunk is located
		for src in sources:
			if src.inv.has(item):
				var loc_lbl := Label.new()
				loc_lbl.text = "  %s: ×%d" % [src.label, src.inv[item]]
				loc_lbl.modulate = Color(0.7, 0.7, 0.7)
				_global_inv_vbox.add_child(loc_lbl)


# ── Units panel ──────────────────────────────────────────────────────────────

func register_units(units: Array) -> void:
	_all_units = units


func _on_units_btn_pressed() -> void:
	if _units_panel.visible:
		_units_panel.visible = false
		return
	_close_bottom_panels()
	_refresh_units_panel()
	_units_panel.visible = true


func _refresh_units_panel() -> void:
	for c in _units_vbox.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "Units"
	_units_vbox.add_child(title)
	_units_vbox.add_child(HSeparator.new())

	for u in _all_units:
		var u_node := u as Unit

		# Card: clickable panel for the whole unit row
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				camera.center_on(u_node.position)
		)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 56)
		row.mouse_filter = Control.MOUSE_FILTER_PASS

		# Portrait
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(48, 48)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_PASS
		if u_node.data.portrait:
			portrait.texture = u_node.data.portrait
		row.add_child(portrait)

		# Name, role, health bar column
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_PASS

		var name_lbl := Label.new()
		name_lbl.text = u_node.data.name
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = u_node.data.role
		role_lbl.modulate = Color(0.7, 0.7, 0.7)
		role_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(role_lbl)

		# Health bar
		var bar := _make_health_bar(0, 12)
		bar.max_value = u_node.data.max_health
		bar.value = u_node.data.health
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(bar)

		row.add_child(col)
		card.add_child(row)
		_units_vbox.add_child(card)
		_units_vbox.add_child(HSeparator.new())


# ── Selection box ─────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _sel_box_active:
		return
	draw_rect(_sel_box, Color(0.2, 0.8, 0.2, 0.15), true)
	draw_rect(_sel_box, Color(0.2, 0.8, 0.2, 1.0), false, 1.0)


func update_selection_box(start: Vector2, end: Vector2) -> void:
	_sel_box = Rect2(start, end - start).abs()
	_sel_box_active = true
	queue_redraw()


func hide_selection_box() -> void:
	_sel_box_active = false
	queue_redraw()


# ── Tree panel ────────────────────────────────────────────────────────────────

func show_tree_panel(pos: Vector2, screen_pos: Vector2) -> void:
	_selected_tree = pos
	_tree_panel.position = screen_pos + Vector2(8, 8)
	_tree_panel.visible = true

func _on_cut_pressed() -> void:
	_tree_panel.visible = false
	cut_requested.emit(_selected_tree)


# ── Unit panel ────────────────────────────────────────────────────────────────

func show_unit_panel(unit: Unit, screen_pos: Vector2) -> void:
	_selected_unit = unit
	_draft_btn.text = "Undraft" if unit.drafted else "Draft"
	# Rebuild inventory rows inside the unit panel
	var vbox := _unit_panel.get_child(0) as VBoxContainer
	# Remove any previously added inventory rows (after the 3 fixed children)
	while vbox.get_child_count() > 3:
		vbox.get_child(3).queue_free()
	if not unit.data.inventory.is_empty():
		vbox.add_child(HSeparator.new())
		var inv_lbl := Label.new()
		inv_lbl.text = "Carrying:"
		vbox.add_child(inv_lbl)
		for item in unit.data.inventory:
			var row := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(24, 24)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			if ITEM_ICONS.has(item):
				var tex := load(ITEM_ICONS[item]) as Texture2D
				if tex:
					icon.texture = tex
			row.add_child(icon)
			var lbl := Label.new()
			lbl.text = "%s ×%d" % [item, unit.data.inventory[item]]
			row.add_child(lbl)
			vbox.add_child(row)
	_unit_panel.position = screen_pos + Vector2(8, 8)
	_unit_panel.visible = true

func hide_unit_panel() -> void:
	_unit_panel.visible = false


func _on_draft_pressed() -> void:
	_selected_unit.set_drafted(not _selected_unit.drafted)
	_draft_btn.text = "Undraft" if _selected_unit.drafted else "Draft"
	_unit_panel.visible = false


# ── Group panel ───────────────────────────────────────────────────────────────

func show_group_panel(units: Array, screen_pos: Vector2) -> void:
	_selected_group = units
	var all_drafted: bool = units.all(func(u): return u.drafted)
	_group_draft_btn.text = "Undraft All" if all_drafted else "Draft All"
	_group_panel.position = screen_pos + Vector2(8, 8)
	_group_panel.visible = true

func _on_group_draft_pressed() -> void:
	var all_drafted: bool = _selected_group.all(func(u): return u.drafted)
	for u in _selected_group:
		u.set_drafted(not all_drafted)
	_group_draft_btn.text = "Draft All" if all_drafted else "Undraft All"
	_group_panel.visible = false


# ── Inventory panel ───────────────────────────────────────────────────────────

func show_inventory_panel(title: String, inventory: Dictionary, screen_pos: Vector2) -> void:
	_inv_title.text = title
	for child in _inv_rows.get_children():
		child.queue_free()
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		_inv_rows.add_child(empty)
	else:
		for item in inventory:
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(56, 56)
			slot.tooltip_text = item

			var overlay := Control.new()
			overlay.custom_minimum_size = Vector2(56, 56)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var icon := TextureRect.new()
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if ITEM_ICONS.has(item):
				var tex := load(ITEM_ICONS[item]) as Texture2D
				if tex:
					icon.texture = tex
			overlay.add_child(icon)

			var qty := Label.new()
			qty.text = "×" + str(inventory[item])
			qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(qty)

			slot.add_child(overlay)
			_inv_rows.add_child(slot)
	_inv_panel.position = screen_pos + Vector2(8, 8)
	_inv_panel.visible = true


# ── Dialog panel ──────────────────────────────────────────────────────────────

func show_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = ""
	_dialog_text.visible = false
	_dialog_text_sep.visible = false
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func show_monolith_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = '"' + MONOLITH_LINES[_dialog_rng.randi() % MONOLITH_LINES.size()] + '"'
	_dialog_text.visible = true
	_dialog_text_sep.visible = true
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func _on_dialog_draft_pressed() -> void:
	pass


func _on_inspect_pressed() -> void:
	_dialog_panel.visible = false
	inspect_requested.emit()


# ── Top HUD (drafted units) ───────────────────────────────────────────────────

func _make_health_bar(w: float, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(w, h)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.75, 0.25)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_top_hud() -> void:
	var wrapper := CenterContainer.new()
	wrapper.anchor_left   = 0.0
	wrapper.anchor_right  = 1.0
	wrapper.anchor_top    = 0.0
	wrapper.anchor_bottom = 0.0
	wrapper.offset_top    = 6
	wrapper.offset_bottom = 76
	wrapper.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_top_hud = HBoxContainer.new()
	_top_hud.add_theme_constant_override("separation", 8)
	_top_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(_top_hud)
	add_child(wrapper)


func _refresh_top_hud(drafted: Array) -> void:
	_hud_bars.clear()
	for c in _top_hud.get_children():
		c.queue_free()
	for u in drafted:
		var u_node := u as Unit

		# Fixed-size square card with white outline
		var card := Panel.new()
		card.custom_minimum_size = Vector2(56, 56)
		card.clip_contents = true
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.4)
		style.border_color = Color(1, 1, 1, 0.7)
		style.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", style)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				camera.center_on(u_node.position)
				get_viewport().set_input_as_handled()
		)

		# Portrait fills the whole card
		var portrait := TextureRect.new()
		portrait.anchor_right = 1.0
		portrait.anchor_bottom = 1.0
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if u_node.data.portrait:
			portrait.texture = u_node.data.portrait
		card.add_child(portrait)

		# Health bar pinned to bottom edge
		var bar := _make_health_bar(0, 5)
		bar.max_value = u_node.data.max_health
		bar.value = u_node.data.health
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = -5
		bar.offset_bottom = 0
		card.add_child(bar)
		_hud_bars[u] = bar

		# Name just above the bar
		var name_lbl := Label.new()
		name_lbl.text = u_node.data.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.anchor_left = 0.0
		name_lbl.anchor_right = 1.0
		name_lbl.anchor_top = 1.0
		name_lbl.anchor_bottom = 1.0
		name_lbl.offset_top = -19
		name_lbl.offset_bottom = -5
		card.add_child(name_lbl)

		_top_hud.add_child(card)


# ── HUD ───────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	wood_label.text = "Wood: " + str(grid.wood)
	var drafted: Array = []
	var drafted_count := 0
	for u in grid.get_node("Units").get_children():
		if u is Unit and u.drafted:
			drafted.append(u)
			drafted_count += 1
	drafted_label.text = "Drafted: " + str(drafted_count)

	# Refresh top HUD when drafted composition changes
	var ids: Array = drafted.map(func(u): return u.get_instance_id())
	if ids != _last_drafted_ids:
		_last_drafted_ids = ids
		_refresh_top_hud(drafted)

	# Update health bars live
	for u in _hud_bars:
		if is_instance_valid(u) and is_instance_valid(_hud_bars[u]):
			(_hud_bars[u] as ProgressBar).value = (u as Unit).data.health
