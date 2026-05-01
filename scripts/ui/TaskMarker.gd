class_name TaskMarker
extends Node2D

# World-space pulsing icon shown above any object the player has queued for
# action — trees marked for harvest, rocks marked for mining, walls marked
# for repair / demolish, blueprints awaiting build. Each task type gets a
# distinct color + single-letter glyph so the player can tell at a glance
# what's in the queue. Spawned + freed by Grid.set_task_marker /
# clear_task_marker; this script just owns the visual.

const COLORS: Dictionary = {
	"harvest":  Color(0.55, 0.85, 0.40),  # green — chopping
	"mine":     Color(0.95, 0.70, 0.30),  # orange — mining
	"repair":   Color(1.00, 0.85, 0.30),  # yellow — repair
	"demolish": Color(1.00, 0.40, 0.40),  # red — tear down
	"build":    Color(0.50, 0.75, 1.00),  # blue — construct
}

const SYMBOLS: Dictionary = {
	"harvest":  "H",
	"mine":     "M",
	"repair":   "R",
	"demolish": "X",
	"build":    "B",
}

const RADIUS: float = 14.0
const FONT_SIZE: int = 16

var _type: String = ""


func setup(task_type: String) -> void:
	_type = task_type
	queue_redraw()


func _process(_delta: float) -> void:
	# Pulse animation needs a redraw every frame.
	queue_redraw()


func _draw() -> void:
	var col: Color = COLORS.get(_type, Color(0.8, 0.8, 0.8))
	var symbol: String = SYMBOLS.get(_type, "?")
	# Pulse 0.85 → 1.0 → 0.85 so the marker reads as "active / waiting"
	# rather than a dead UI overlay.
	var pulse: float = 0.85 + sin(Time.get_ticks_msec() * 0.005) * 0.15
	var center: Vector2 = Vector2.ZERO
	# Black halo for legibility on bright tiles.
	draw_circle(center, RADIUS + 2.0, Color(0, 0, 0, 0.55))
	draw_circle(center, RADIUS, Color(col.r, col.g, col.b, 0.92 * pulse))
	# Single-letter glyph.
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var text_pos: Vector2 = center + Vector2(-text_size.x * 0.5, font.get_ascent(FONT_SIZE) * 0.5 - 1.0)
	draw_string(font, text_pos + Vector2(1, 1), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 1))
