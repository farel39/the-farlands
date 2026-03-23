extends Camera2D

var zoomFactor: float = 1.1   # multiply/divide per scroll step
var zoomMin: float = 0.1
var zoomMax: float = 2.0
var dragSensitivity: float = 1.0

func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		position -= event.relative * dragSensitivity / zoom
	if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom * zoomFactor, Vector2(zoomMin, zoomMin), Vector2(zoomMax, zoomMax))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clamp(zoom / zoomFactor, Vector2(zoomMin, zoomMin), Vector2(zoomMax, zoomMax))
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
