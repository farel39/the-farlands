extends Control

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

func _on_construct_pressed():
	$BaseButtons.visible = false
	$ConstructButtons.visible = true

func _on_back_pressed():
	$BaseButtons.visible = true
	$ConstructButtons.visible = false

func _ready() -> void:
	$BaseButtons/HBoxContainer/Construct.pressed.connect(_on_construct_pressed)
	$ConstructButtons/HBoxContainer/Back.pressed.connect(_on_back_pressed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
