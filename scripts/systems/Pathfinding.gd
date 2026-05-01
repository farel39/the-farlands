class_name Pathfinder
extends Node2D

var aStar = AStar2D.new()
@onready var grid: Grid = get_parent() as Grid

const DIRECTIONS = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
]

# Height of the nav grid in cells — set during initialize(), used for O(1) ID lookup.
var _nav_h: int = 0

# O(1): compute A* point ID directly from nav coordinates.
# Matches addPoints() insertion order: outer loop x, inner loop y.
func _pid(navPoint: Vector2) -> int:
	return int(navPoint.x) * _nav_h + int(navPoint.y)

func getPointID(navPoint: Vector2) -> int:
	return aStar.get_closest_point(grid.navToWorld(navPoint))

func getWorldID(worldPoint: Vector2) -> int:
	return aStar.get_closest_point(worldPoint)

func getIDWorldPos(_id: int) -> Vector2:
	return aStar.get_point_position(_id)

func getIDNavPos(_id: int) -> Vector2:
	return grid.worldToNav(getIDWorldPos(_id))

func addPoints():
	var curID = 0
	for point in grid.nav_grid:
		aStar.add_point(curID, grid.navToWorld(point))
		curID += 1

func connectPoint(_point: Vector2):
	if not grid.nav_grid[_point]:
		return
	var _pointID = _pid(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		if not grid.nav_grid.has(neighbor) or not grid.nav_grid[neighbor]:
			continue
		if direction.x != 0 and direction.y != 0:
			var c1 = _point + Vector2(direction.x, 0)
			var c2 = _point + Vector2(0, direction.y)
			# Block diagonal if EITHER corner is blocked. Stricter than the
			# old "both blocked" rule — prevents units from cutting diagonally
			# past the corner of a wall (which was visually clipping them).
			if (grid.nav_grid.has(c1) and not grid.nav_grid[c1]) or \
			   (grid.nav_grid.has(c2) and not grid.nav_grid[c2]):
				continue
		aStar.connect_points(_pointID, _pid(neighbor))

func disconnectPoint(_point: Vector2):
	var _pointID = _pid(_point)
	for direction in DIRECTIONS:
		var neighbor = _point + direction
		if grid.nav_grid.has(neighbor):
			aStar.disconnect_points(_pointID, _pid(neighbor))

func connectAllPoints():
	for point in grid.nav_grid:
		connectPoint(point)

func initialize():
	_nav_h = grid.height * grid.cell_size / Grid.NAV_CELL_SIZE
	addPoints()
	connectAllPoints()
	for point in grid.nav_grid:
		if not grid.nav_grid[point]:
			aStar.set_point_disabled(_pid(point), true)
	grid.nav_cell_changed.connect(_on_nav_changed)

func _on_nav_changed(pos: Vector2) -> void:
	var pid := _pid(pos)
	if grid.nav_grid[pos]:
		aStar.set_point_disabled(pid, false)
		connectPoint(pos)
	else:
		disconnectPoint(pos)
		aStar.set_point_disabled(pid, true)
	_refresh_corner_diagonals(pos)

func _refresh_corner_diagonals(pos: Vector2) -> void:
	var pairs := [
		[pos + Vector2(-1, 0), pos + Vector2(0, -1)],
		[pos + Vector2(-1, 0), pos + Vector2(0,  1)],
		[pos + Vector2( 1, 0), pos + Vector2(0, -1)],
		[pos + Vector2( 1, 0), pos + Vector2(0,  1)],
	]
	for pair in pairs:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		if not (grid.nav_grid.has(a) and grid.nav_grid.has(b)):
			continue
		if not (grid.nav_grid[a] and grid.nav_grid[b]):
			continue
		var aID := _pid(a)
		var bID := _pid(b)
		# The other intermediate corner (the one that isn't pos)
		var c1 := a + Vector2(sign(b.x - a.x), 0)
		var c2 := a + Vector2(0, sign(b.y - a.y))
		var other: Vector2 = c2 if c1 == pos else c1
		var pos_blocked: bool = grid.nav_grid.has(pos) and not grid.nav_grid[pos]
		var other_blocked: bool = grid.nav_grid.has(other) and not grid.nav_grid[other]
		# OR rule: a single blocked corner is enough to break the diagonal,
		# matching connectPoint() above.
		if pos_blocked or other_blocked:
			aStar.disconnect_points(aID, bID)
		else:
			aStar.connect_points(aID, bID)

func getPath(_pointA: Vector2, _pointB: Vector2) -> PackedVector2Array:
	var aID = getPointID(_pointA)
	var bID = getPointID(_pointB)
	var worldPath = aStar.get_point_path(aID, bID)
	var navPath: PackedVector2Array = []
	for point in worldPath:
		navPath.append(grid.worldToNav(point))
	return navPath

func smoothPath(world_path: PackedVector2Array) -> PackedVector2Array:
	if world_path.size() <= 2:
		return world_path

	var result := PackedVector2Array()
	result.append(world_path[0])

	var anchor := 0
	while anchor < world_path.size() - 1:
		var farthest := anchor + 1
		for look in range(anchor + 2, world_path.size()):
			if _hasLOS(world_path[anchor], world_path[look]):
				farthest = look
		result.append(world_path[farthest])
		anchor = farthest

	return result

func tightenPath(world_path: PackedVector2Array) -> PackedVector2Array:
	if world_path.size() <= 2:
		return world_path
	# Distance the tightened path keeps from a hugged wall corner. Set above
	# half a unit's body width so the rendered sprite doesn't visually clip
	# into the wall when the path wraps around a corner. Unit bodies are
	# ~50-90 px depending on character; 40 px gives ~5-15 px of breathing room.
	const CLEARANCE := 40.0
	var ns := float(Grid.NAV_CELL_SIZE)
	var result := PackedVector2Array()
	result.append(world_path[0])
	for i in range(1, world_path.size() - 1):
		# Use last confirmed result point as prev so chained double-corners work correctly.
		var prev     := result[result.size() - 1]
		var curr     := world_path[i]
		var nxt      := world_path[i + 1]
		var curr_nav := grid.worldToNav(curr)
		var orig_len := prev.distance_to(curr) + curr.distance_to(nxt)
		var best_len := orig_len
		var best_pts: Array = [curr]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nb := curr_nav + Vector2(dx, dy)
				if not grid.nav_grid.has(nb) or grid.nav_grid[nb]:
					continue
				var tile_tl     := grid.navToWorld(nb)
				var tile_center := tile_tl + Vector2(ns * 0.5, ns * 0.5)
				var corners := [
					tile_tl,
					tile_tl + Vector2(ns, 0),
					tile_tl + Vector2(0, ns),
					tile_tl + Vector2(ns, ns),
				]
				# Single corner — hug one corner of the obstacle.
				for corner: Vector2 in corners:
					var push := (corner - tile_center).normalized()
					var cand := corner + push * CLEARANCE
					if not (_hasLOS(prev, cand) and _hasLOS(cand, nxt)):
						continue
					var len := prev.distance_to(cand) + cand.distance_to(nxt)
					if len < best_len:
						best_len = len
						best_pts = [cand]
				# Double corner — hug the entry corner (closest to prev) then the
				# exit corner (closest to nxt) of the same obstacle tile.
				# This handles going all the way around a single tile.
				var c1: Vector2 = corners[0]
				var c1_dist := prev.distance_to(corners[0])
				var c2: Vector2 = corners[0]
				var c2_dist := nxt.distance_to(corners[0])
				for corner: Vector2 in corners:
					if prev.distance_to(corner) < c1_dist:
						c1_dist = prev.distance_to(corner)
						c1 = corner
					if nxt.distance_to(corner) < c2_dist:
						c2_dist = nxt.distance_to(corner)
						c2 = corner
				if c1 == c2:
					continue  # same corner, already handled by single above
				var push1 := (c1 - tile_center).normalized()
				var push2 := (c2 - tile_center).normalized()
				var cand1 := c1 + push1 * CLEARANCE
				var cand2 := c2 + push2 * CLEARANCE
				if not (_hasLOS(prev, cand1) and _hasLOS(cand1, cand2) and _hasLOS(cand2, nxt)):
					continue
				var len := prev.distance_to(cand1) + cand1.distance_to(cand2) + cand2.distance_to(nxt)
				if len < best_len:
					best_len = len
					best_pts = [cand1, cand2]
		for pt in best_pts:
			result.append(pt)
	result.append(world_path[world_path.size() - 1])
	return result


func _hasLOS(a: Vector2, b: Vector2) -> bool:
	var a_nav := grid.worldToNav(a)
	var b_nav := grid.worldToNav(b)
	# Check the starting cell — if it's blocked there is no LOS from here
	if grid.nav_grid.has(a_nav) and not grid.nav_grid[a_nav]:
		return false
	var x: int = int(a_nav.x);  var y: int = int(a_nav.y)
	var x1: int = int(b_nav.x); var y1: int = int(b_nav.y)
	var dx: int = x1 - x;       var dy: int = y1 - y
	var nx: int = abs(dx);       var ny: int = abs(dy)
	var sx: int = 1 if dx > 0 else -1
	var sy: int = 1 if dy > 0 else -1
	var ix: int = 0;             var iy: int = 0
	while ix < nx or iy < ny:
		var t1: int = (1 + 2 * ix) * ny
		var t2: int = (1 + 2 * iy) * nx
		if t1 == t2:
			# Line grazes the corner between two cells. Impassable when EITHER
			# adjacent cell is blocked — matches the OR rule used by
			# connectPoint() so smoothing can't shortcut past wall corners.
			var c1 := Vector2(x + sx, y)
			var c2 := Vector2(x, y + sy)
			if (grid.nav_grid.has(c1) and not grid.nav_grid[c1]) or \
			   (grid.nav_grid.has(c2) and not grid.nav_grid[c2]):
				return false
			x += sx;  y += sy;  ix += 1;  iy += 1
		elif t1 < t2:
			x += sx;  ix += 1
		else:
			y += sy;  iy += 1
		if grid.nav_grid.has(Vector2(x, y)) and not grid.nav_grid[Vector2(x, y)]:
			return false
	return true

func _supercover(from: Vector2, to: Vector2) -> Array:
	var cells: Array = []
	var x: int = int(from.x)
	var y: int = int(from.y)
	var x1: int = int(to.x)
	var y1: int = int(to.y)
	var dx: int = x1 - x
	var dy: int = y1 - y
	var nx: int = abs(dx)
	var ny: int = abs(dy)
	var sign_x: int = 1 if dx > 0 else -1
	var sign_y: int = 1 if dy > 0 else -1

	cells.append(Vector2(x, y))
	var ix: int = 0
	var iy: int = 0
	while ix < nx or iy < ny:
		var t1: int = (1 + 2 * ix) * ny
		var t2: int = (1 + 2 * iy) * nx
		if t1 == t2:
			cells.append(Vector2(x + sign_x, y))
			cells.append(Vector2(x, y + sign_y))
			x += sign_x
			y += sign_y
			ix += 1
			iy += 1
		elif t1 < t2:
			x += sign_x
			ix += 1
		else:
			y += sign_y
			iy += 1
		cells.append(Vector2(x, y))
	return cells

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
