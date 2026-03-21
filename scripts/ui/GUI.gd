extends Control

signal cut_requested(pos: Vector2)

@onready var grid: Grid = get_tree().root.get_node("Main/Grid")

# Building definitions: source_id maps to TileSet sources in Main.tscn
# 0=dirt, 1=grass, 2=missing, 3=stonewall, 4=woodwall
const BUILDINGS = {
	"WoodWall":  { "name": "Wood Wall",  "source_id": 4, "layer": 1, "navigable": false },
	"StoneWall": { "name": "Stone Wall", "source_id": 3, "layer": 1, "navigable": false },
	"DirtFloor": { "name": "Dirt Floor", "source_id": 0, "layer": 0, "navigable": true  },
}

var wood_label: Label
var _tree_panel: PanelContainer
var _selected_tree: Vector2
var _unit_panel: PanelContainer
var _draft_btn: Button
var _selected_unit: Unit

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

	_tree_panel = PanelContainer.new()
	_tree_panel.visible = false
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Tree"
	var cut_btn := Button.new()
	cut_btn.text = "Cut"
	cut_btn.pressed.connect(_on_cut_pressed)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_tree_cancel_pressed)
	vbox.add_child(title)
	vbox.add_child(cut_btn)
	vbox.add_child(cancel_btn)
	_tree_panel.add_child(vbox)
	add_child(_tree_panel)

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

	$BaseButtons/HBoxContainer/Construct.pressed.connect(_on_construct_pressed)
	$ConstructButtons/HBoxContainer/Back.pressed.connect(_on_back_pressed)
	$ConstructButtons/HBoxContainer/WoodWall.pressed.connect(_on_wood_wall_pressed)
	$ConstructButtons/HBoxContainer/StoneWall.pressed.connect(_on_stone_wall_pressed)
	$ConstructButtons/HBoxContainer/DirtFloor.pressed.connect(_on_dirt_floor_pressed)

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


func _on_tree_cancel_pressed() -> void:
	_tree_panel.visible = false


func show_unit_panel(unit: Unit, screen_pos: Vector2) -> void:
	_selected_unit = unit
	_draft_btn.text = "Undraft" if unit.drafted else "Draft"
	_unit_panel.position = screen_pos + Vector2(8, 8)
	_unit_panel.visible = true


func _on_draft_pressed() -> void:
	_selected_unit.set_drafted(not _selected_unit.drafted)
	_draft_btn.text = "Undraft" if _selected_unit.drafted else "Draft"
	_unit_panel.visible = false


func _process(_delta: float) -> void:
	wood_label.text = "Wood: " + str(grid.wood)
