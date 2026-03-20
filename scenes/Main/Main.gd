extends Node2D

@onready var grid = $Grid
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	grid.generateGrid()
	$Grid/Pathfinding.initialize()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
