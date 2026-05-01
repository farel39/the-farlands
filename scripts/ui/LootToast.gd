class_name LootToast
extends Node2D

# Floating loot pickup notification — spawns at the kill site, drifts upward,
# fades out. One toast per item type; multiple drops from the same kill stack
# vertically (handled by the spawner).

const LIFETIME: float = 1.6
const FADE_TIME: float = 0.6
const RISE_DISTANCE: float = 42.0  # total upward drift in screen pixels

var _t: float = 0.0
var _icon: Texture2D = null
var _text: String = "+1"
# Default gold for "+gained" loot. Shortage toasts override this with red so
# the same component reads as "Need X" without a separate scene/script.
var _color: Color = Color(1.0, 0.95, 0.55)


func setup(icon: Texture2D, text: String, color: Color = Color(1.0, 0.95, 0.55)) -> void:
	_icon = icon
	_text = text
	_color = color
	z_index = 1000
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k: float = clamp(_t / LIFETIME, 0.0, 1.0)
	# Ease-out curve so the rise slows as the toast fades.
	var rise_k: float = 1.0 - pow(1.0 - k, 2.0)
	var y_offset: float = -RISE_DISTANCE * rise_k
	var alpha: float = 1.0
	if _t > LIFETIME - FADE_TIME:
		alpha = clamp(1.0 - (_t - (LIFETIME - FADE_TIME)) / FADE_TIME, 0.0, 1.0)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_w: float = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon_size: float = 22.0
	var pad: float = 4.0
	var has_icon: bool = _icon != null
	var total_w: float = text_w + (icon_size + pad if has_icon else 0.0)
	var x_origin: float = -total_w * 0.5

	if has_icon:
		var icon_rect := Rect2(x_origin, y_offset - icon_size * 0.5, icon_size, icon_size)
		draw_texture_rect(_icon, icon_rect, false, Color(1, 1, 1, alpha))

	var text_x: float = x_origin + (icon_size + pad if has_icon else 0.0)
	var text_pos: Vector2 = Vector2(text_x, y_offset + 5)
	# 1px drop-shadow for legibility on bright sand / light tiles.
	draw_string(font, text_pos + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, alpha * 0.85))
	var fg: Color = Color(_color.r, _color.g, _color.b, alpha)
	draw_string(font, text_pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)
