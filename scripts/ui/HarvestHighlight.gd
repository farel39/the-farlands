class_name HarvestHighlight
extends Node2D

# Pulsing glow outlines on harvestable objects while the player is in the
# Harvest or Mine command mode. Visibility-gated via Main._visible_cells so
# objects behind fog of war stay hidden — the highlight is meant to help
# the player spot what's nearby, not reveal the whole map.

var grid: Grid
var main_node: Node = null
var gui_ref: Node = null


func setup(g: Grid, m: Node, ui: Node) -> void:
	grid = g
	main_node = m
	gui_ref = ui
	z_index = 25


func _process(_delta: float) -> void:
	# Pulse animation needs a redraw every frame, but the _draw early-returns
	# when no highlight mode is active so the cost is essentially zero outside
	# of harvest/mine targeting.
	queue_redraw()


func _draw() -> void:
	if grid == null or main_node == null or gui_ref == null:
		return
	var mode: String = gui_ref.command_mode
	if mode != "harvest" and mode != "mine":
		return
	# Local ref so attribute access inside the loop body is cheap.
	var visible: Dictionary = main_node._visible_cells
	var cs: float = float(grid.cell_size)
	var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.005) * 0.25

	if mode == "harvest":
		# Harvest-color matches the green "H" task marker.
		var col := Color(0.55, 0.85, 0.40)
		# Trees — 3x3 footprint, treat the whole tree as highlighted if any
		# of its cells is currently in sight.
		for root in grid.tree_lights_by_root.keys():
			if not _footprint_visible(visible, root, 3, 3):
				continue
			_draw_glow_rect(grid.gridToWorld(root), 3.0 * cs, 3.0 * cs, col, pulse)
		# Loose driftwood piles — single cell.
		for cell in grid.driftwood_nodes.keys():
			if not visible.has(Vector2i(int(cell.x), int(cell.y))):
				continue
			_draw_glow_rect(grid.gridToWorld(cell), cs, cs, col, pulse)
	else:
		# Mine-color matches the orange "M" task marker.
		var col := Color(0.95, 0.70, 0.30)
		for cell in grid.rock_nodes.keys():
			if not visible.has(Vector2i(int(cell.x), int(cell.y))):
				continue
			_draw_glow_rect(grid.gridToWorld(cell), cs, cs, col, pulse)
		for cell in grid.ore_nodes.keys():
			if not visible.has(Vector2i(int(cell.x), int(cell.y))):
				continue
			_draw_glow_rect(grid.gridToWorld(cell), cs, cs, col, pulse)


# True if any cell in the (w x h) footprint anchored at `root` is currently
# in the unit visibility set. One sighted corner reveals the whole object —
# matches how a player would expect "I can see the edge of that tree."
func _footprint_visible(visible: Dictionary, root: Vector2, w: int, h: int) -> bool:
	for dx in w:
		for dy in h:
			var c: Vector2 = root + Vector2(dx, dy)
			if visible.has(Vector2i(int(c.x), int(c.y))):
				return true
	return false


func _draw_glow_rect(top_left: Vector2, w: float, h: float, col: Color, pulse: float) -> void:
	var rect := Rect2(top_left, Vector2(w, h))
	# Soft semi-transparent fill so the object reads as "marked" without
	# obscuring its sprite.
	draw_rect(rect, Color(col.r, col.g, col.b, 0.18 * pulse), true)
	# Bold outline so the highlight is unmissable at a glance.
	draw_rect(rect, Color(col.r, col.g, col.b, 0.92 * pulse), false, 3.0)
