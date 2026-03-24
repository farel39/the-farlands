extends Camera2D

var zoomFactor: float = 1.1   # multiply/divide per scroll step
var zoomMin: float = 0.1
var zoomMax: float = 2.0
var dragSensitivity: float = 1.0

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		position -= event.relative * dragSensitivity / zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var node: Control = get_viewport().gui_get_hovered_control()
			while node != null:
				if node.mouse_filter == Control.MOUSE_FILTER_STOP:
					return
				node = node.get_parent() as Control
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom * zoomFactor, Vector2(zoomMin, zoomMin), Vector2(zoomMax, zoomMax))
			else:
				zoom = clamp(zoom / zoomFactor, Vector2(zoomMin, zoomMin), Vector2(zoomMax, zoomMax))
# Called when the node enters the scene tree for the first time.
func center_on(world_pos: Vector2) -> void:
	position = world_pos
