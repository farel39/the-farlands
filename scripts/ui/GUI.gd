extends Control

signal cut_requested(pos: Vector2)

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

var _sel_box_active: bool = false
var _sel_box: Rect2

var selectedObject = null :
	get:
		return selectedObject
	set(value):
		selectedObject = value
		if value != null:
			$InfoPanel.visible = true
			match value.get_class():
				"Unit":
					$InfoPanel/Name.text = value.data.name
					$BaseButtons/HBoxContainer/Bio.visible = true
		else:
			$InfoPanel.visible = false
			$BaseButtons/HBoxContainer/Bio.visible = false

func setSelectedObject(obj):
	selectedObject = obj

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

	$BaseButtons/HBoxContainer/Construct.pressed.connect(_on_construct_pressed)
	$ConstructButtons/HBoxContainer/Back.pressed.connect(_on_back_pressed)
	$ConstructButtons/HBoxContainer/WoodWall.pressed.connect(_on_wood_wall_pressed)
	$ConstructButtons/HBoxContainer/StoneWall.pressed.connect(_on_stone_wall_pressed)
	$ConstructButtons/HBoxContainer/DirtFloor.pressed.connect(_on_dirt_floor_pressed)


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


func _on_construct_pressed() -> void:
	$BaseButtons.visible = false
	$ConstructButtons.visible = true

func _on_back_pressed() -> void:
	$BaseButtons.visible = true
	$ConstructButtons.visible = false
	grid.exit_placement_mode()

func _on_wood_wall_pressed() -> void:
	grid.enter_placement_mode(BUILDINGS["WoodWall"])
	_show_base_buttons()

func _on_stone_wall_pressed() -> void:
	grid.enter_placement_mode(BUILDINGS["StoneWall"])
	_show_base_buttons()

func _on_dirt_floor_pressed() -> void:
	grid.enter_placement_mode(BUILDINGS["DirtFloor"])
	_show_base_buttons()

func _show_base_buttons() -> void:
	$BaseButtons.visible = true
	$ConstructButtons.visible = false


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


func _process(_delta: float) -> void:
	wood_label.text = "Wood: " + str(grid.wood)
	var drafted_count := 0
	for u in grid.get_node("Units").get_children():
		if u is Unit and u.drafted:
			drafted_count += 1
	drafted_label.text = "Drafted: " + str(drafted_count)
