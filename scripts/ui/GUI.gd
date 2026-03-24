extends Control

signal cut_requested(pos: Vector2)
signal inspect_requested

@onready var grid: Grid = get_tree().root.get_node("Main/Grid")

const BUILDINGS = {
	"WoodWall":  { "name": "Wood Wall",  "source_id": 4, "layer": 1, "navigable": false },
	"StoneWall": { "name": "Stone Wall", "source_id": 3, "layer": 1, "navigable": false },
	"DirtFloor": { "name": "Dirt Floor", "source_id": 0, "layer": 0, "navigable": true  },
}

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
var _dialog_draft_btn: Button
var _dialog_unit: Unit
var _dialog_rng := RandomNumberGenerator.new()

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

var _sel_box_active: bool = false
var _sel_box: Rect2


func _ready() -> void:
	wood_label = Label.new()
	wood_label.position = Vector2(8, 8)
	add_child(wood_label)

	drafted_label = Label.new()
	drafted_label.position = Vector2(8, 28)
	add_child(drafted_label)

	# Tree panel
	_tree_panel = PanelContainer.new()
	_tree_panel.visible = false
	var tvbox := VBoxContainer.new()
	var ttitle := Label.new()
	ttitle.text = "Tree"
	var cut_btn := Button.new()
	cut_btn.text = "Cut"
	cut_btn.pressed.connect(_on_cut_pressed)
	var tcancel := Button.new()
	tcancel.text = "Cancel"
	tcancel.pressed.connect(func(): _tree_panel.visible = false)
	tvbox.add_child(ttitle)
	tvbox.add_child(cut_btn)
	tvbox.add_child(tcancel)
	_tree_panel.add_child(tvbox)
	add_child(_tree_panel)

	# Unit panel
	_unit_panel = PanelContainer.new()
	_unit_panel.visible = false
	var uvbox := VBoxContainer.new()
	var uname := Label.new()
	uname.text = "Colonist"
	_draft_btn = Button.new()
	_draft_btn.pressed.connect(_on_draft_pressed)
	var ucancel := Button.new()
	ucancel.text = "Cancel"
	ucancel.pressed.connect(func(): _unit_panel.visible = false)
	uvbox.add_child(uname)
	uvbox.add_child(_draft_btn)
	uvbox.add_child(ucancel)
	_unit_panel.add_child(uvbox)
	add_child(_unit_panel)

	# Group panel
	_group_panel = PanelContainer.new()
	_group_panel.visible = false
	var gvbox := VBoxContainer.new()
	var gtitle := Label.new()
	gtitle.text = "Group"
	_group_draft_btn = Button.new()
	_group_draft_btn.pressed.connect(_on_group_draft_pressed)
	var gcancel := Button.new()
	gcancel.text = "Cancel"
	gcancel.pressed.connect(func(): _group_panel.visible = false)
	gvbox.add_child(gtitle)
	gvbox.add_child(_group_draft_btn)
	gvbox.add_child(gcancel)
	_group_panel.add_child(gvbox)
	add_child(_group_panel)

	# Inventory panel
	_inv_panel = PanelContainer.new()
	_inv_panel.visible = false
	var inv_vbox := VBoxContainer.new()
	_inv_title = Label.new()
	_inv_title.text = "Inventory"
	inv_vbox.add_child(_inv_title)
	_inv_rows = GridContainer.new()
	_inv_rows.columns = 5
	inv_vbox.add_child(_inv_rows)
	var inv_sep := HSeparator.new()
	inv_vbox.add_child(inv_sep)
	var inv_close := Button.new()
	inv_close.text = "Close"
	inv_close.pressed.connect(func(): _inv_panel.visible = false)
	inv_vbox.add_child(inv_close)
	_inv_panel.add_child(inv_vbox)
	add_child(_inv_panel)

	# Dialog panel
	_dialog_rng.randomize()
	_dialog_panel = PanelContainer.new()
	_dialog_panel.visible = false
	_dialog_panel.custom_minimum_size = Vector2(320, 0)
	var d_vbox := VBoxContainer.new()
	# Top row: portrait + name/role
	var d_top := HBoxContainer.new()
	_dialog_portrait = TextureRect.new()
	_dialog_portrait.custom_minimum_size = Vector2(64, 64)
	_dialog_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialog_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialog_portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	d_top.add_child(_dialog_portrait)
	var d_name_col := VBoxContainer.new()
	_dialog_name = Label.new()
	_dialog_role = Label.new()
	_dialog_role.modulate = Color(0.7, 0.7, 0.7)
	d_name_col.add_child(_dialog_name)
	d_name_col.add_child(_dialog_role)
	d_top.add_child(d_name_col)
	d_vbox.add_child(d_top)
	d_vbox.add_child(HSeparator.new())
	# Dialog text
	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(300, 0)
	d_vbox.add_child(_dialog_text)
	d_vbox.add_child(HSeparator.new())
	# Buttons row
	var d_btns := HBoxContainer.new()
	_dialog_draft_btn = Button.new()
	_dialog_draft_btn.pressed.connect(_on_dialog_draft_pressed)
	d_btns.add_child(_dialog_draft_btn)
	var d_inspect := Button.new()
	d_inspect.text = "Inspect"
	d_inspect.pressed.connect(_on_inspect_pressed)
	d_btns.add_child(d_inspect)
	var d_close := Button.new()
	d_close.text = "Close"
	d_close.pressed.connect(func(): _dialog_panel.visible = false)
	d_btns.add_child(d_close)
	d_vbox.add_child(d_btns)
	_dialog_panel.add_child(d_vbox)
	add_child(_dialog_panel)



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



func show_tree_panel(pos: Vector2, screen_pos: Vector2) -> void:
	_selected_tree = pos
	_tree_panel.position = screen_pos + Vector2(8, 8)
	_tree_panel.visible = true

func _on_cut_pressed() -> void:
	_tree_panel.visible = false
	cut_requested.emit(_selected_tree)

func show_unit_panel(unit: Unit, screen_pos: Vector2) -> void:
	_selected_unit = unit
	_draft_btn.text = "Undraft" if unit.drafted else "Draft"
	_unit_panel.position = screen_pos + Vector2(8, 8)
	_unit_panel.visible = true

func _on_draft_pressed() -> void:
	_selected_unit.set_drafted(not _selected_unit.drafted)
	_draft_btn.text = "Undraft" if _selected_unit.drafted else "Draft"
	_unit_panel.visible = false


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


const MONOLITH_LINES: Array = [
	"The symbols etched into the stone predate any known civilisation.",
	"You feel a faint vibration beneath your fingertips.",
	"Something about this structure interferes with your instruments.",
	"The stone is warm — far warmer than the surrounding air.",
	"Whoever built this was not human.",
	"The glyphs shift slightly when you're not looking directly at them.",
	"A low hum emanates from within. There is no visible source.",
]

func show_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = ""
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func show_monolith_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = '"' + MONOLITH_LINES[_dialog_rng.randi() % MONOLITH_LINES.size()] + '"'
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func _on_dialog_draft_pressed() -> void:
	pass


func _on_inspect_pressed() -> void:
	_dialog_panel.visible = false
	inspect_requested.emit()


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
			# Slot: fixed-size container with tooltip on hover
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(56, 56)
			slot.tooltip_text = item

			# Overlay control to stack icon + qty label
			var overlay := Control.new()
			overlay.custom_minimum_size = Vector2(56, 56)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Icon fills the slot
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

			# Quantity label at bottom-right
			var qty := Label.new()
			qty.text = "×" + str(inventory[item])
			qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(qty)

			slot.add_child(overlay)
			_inv_rows.add_child(slot)
	_inv_panel.position = screen_pos + Vector2(8, 8)
	_inv_panel.visible = true


func _process(_delta: float) -> void:
	wood_label.text = "Wood: " + str(grid.wood)
	var drafted_count := 0
	for u in grid.get_node("Units").get_children():
		if u is Unit and u.drafted:
			drafted_count += 1
	drafted_label.text = "Drafted: " + str(drafted_count)
