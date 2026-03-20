extends Control

@onready var grid: Grid = get_tree().root.get_node("Main/Grid")

# Building definitions: source_id maps to TileSet sources in Main.tscn
# 0=dirt, 1=grass, 2=missing, 3=stonewall, 4=woodwall
const BUILDINGS = {
	"WoodWall":  { "name": "Wood Wall",  "source_id": 4, "layer": 1, "navigable": false },
	"StoneWall": { "name": "Stone Wall", "source_id": 3, "layer": 1, "navigable": false },
	"DirtFloor": { "name": "Dirt Floor", "source_id": 0, "layer": 0, "navigable": true  },
}

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

func _process(_delta: float) -> void:
	pass
