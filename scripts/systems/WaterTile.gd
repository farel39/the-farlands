class_name WaterTile
extends Node2D

## A 128x128 water overlay tile placed on top of floor tiles.
## Matches the tree-spawning pattern in Grid.gd — instances are children
## of the Water node under Grid, positioned with gridToWorld().

enum Variant {
	WET_SAND,        ## alpha ~0.2 — just barely wet, sand clearly shows
	SHALLOW,         ## alpha ~0.38 — ankle deep, sand visible
	DEEP_SHALLOW,    ## alpha ~0.55 — knee deep, sand faint
	SHORELINE,       ## bottom half of tile only, wavy animated edge
}

const _MATERIAL_PATHS: Array[String] = [
	"res://data/materials/wet_sand.tres",
	"res://data/materials/shallow_water.tres",
	"res://data/materials/deep_shallow_water.tres",
	"res://data/materials/shoreline.tres",
]

@export var variant: Variant = Variant.SHALLOW:
	set(v):
		variant = v
		if is_inside_tree():
			_apply_material()

@onready var _rect: ColorRect = $ColorRect


func _ready() -> void:
	_apply_material()


func _apply_material() -> void:
	_rect.material = load(_MATERIAL_PATHS[variant]) as ShaderMaterial
