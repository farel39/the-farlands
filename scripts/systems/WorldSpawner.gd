class_name WorldSpawner


# Pull a CPU-side Image out of a Texture2D for pixel-walking
# (BitMap collision generation, sprite-alpha polygons, etc.). When the
# texture's import setting is VRAM Compressed (BC1/BC3 etc.), the
# Image we get back is also compressed — and BitMap.create_from_image_alpha
# can't read those, it errors with "Cannot convert to (or from)
# compressed formats." Decompressing in place gives us a normal RGBA8
# image that BitMap is happy with. No-op when the source is already
# uncompressed (Lossless / Lossy import).
static func _alpha_image(tex: Texture2D) -> Image:
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	return img


# A neighbour counts as "solid" for dirt fading if it's a dirt tile OR if it
# has an occupier (rock, tree, etc.) — so the fade never bleeds toward objects.
static func _dirt_solid(g: Grid, c: Vector2) -> bool:
	if g.dirt_tiles.has(c):
		return true
	if g.grid.has(c) and g.grid[c].occupier != null:
		return true
	return false


static func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.4, Color(1, 1, 1, 0.5))
	gradient.add_point(0.75, Color(1, 1, 1, 0.1))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


# Spawn a single tree at the given root cell. Used by spawn_trees during world
# init and by Grid's regrowth tick when a chopped tree finishes regrowing. Marks
# the 3x3 footprint as Tree-occupied + non-navigable, registers the tree's
# sprite + collision body + bioluminescent light in the Grid's tracking dicts.
# Returns the main sprite so the caller can keep a reference if needed.
static func spawn_one_tree(g: Grid, root: Vector2, texture: Texture2D) -> Sprite2D:
	var sp: Node2D = g.sprite_layer if g.sprite_layer != null else g
	var centre_pos: Vector2 = g.gridToWorld(root) + Vector2(g.cell_size * 1.5, g.cell_size * 1.5)
	var tree_s: float = float(g.cell_size * 3) / float(texture.get_width())

	var shadow := Sprite2D.new()
	shadow.texture = texture
	shadow.position = centre_pos + Vector2(g.cell_size * 0.15, g.cell_size * 0.7)
	shadow.scale = Vector2(tree_s * 1.1, tree_s * 0.22)
	shadow.modulate = Color(0, 0, 0, 0.35)
	shadow.z_index = -1
	sp.add_child(shadow)
	g.shadow_sprites.append(shadow)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = centre_pos
	sprite.scale = Vector2(tree_s, tree_s)
	sprite.z_index = int(root.y) + 2
	sp.add_child(sprite)
	g.tree_sprites[root] = sprite

	var tree_img: Image = _alpha_image(texture)
	var tree_bm := BitMap.new()
	tree_bm.create_from_image_alpha(tree_img)
	var tree_polys := tree_bm.opaque_to_polygons(Rect2(Vector2.ZERO, tree_img.get_size()), 2.0)
	if not tree_polys.is_empty():
		var tree_body := StaticBody2D.new()
		tree_body.position = centre_pos
		# Tag for the right-click physics query so clicking anywhere on the
		# tree (including canopy that overhangs neighboring grid cells)
		# resolves back to its root, not just clicks on the trunk's tile.
		tree_body.set_meta("occupier", "Tree")
		tree_body.set_meta("grid_pos", root)
		var tree_origin := Vector2(tree_img.get_width() * 0.5, tree_img.get_height() * 0.5)
		for poly: PackedVector2Array in tree_polys:
			var cp := CollisionPolygon2D.new()
			var scaled := PackedVector2Array()
			for pt: Vector2 in poly:
				scaled.append((pt - tree_origin) * tree_s)
			cp.polygon = Geometry2D.convex_hull(scaled)
			tree_body.add_child(cp)
		sp.add_child(tree_body)

	var light := PointLight2D.new()
	light.texture = _make_light_texture()
	light.color = Color(0.3, 1.0, 0.7)
	light.energy = 0.0
	light.texture_scale = 4.5 / tree_s
	light.position = centre_pos
	sp.add_child(light)
	g.tree_lights.append(light)
	g.tree_lights_by_root[root] = light

	for dx in 3:
		for dy in 3:
			var c: Vector2 = root + Vector2(dx, dy)
			g.grid[c].occupier = "Tree"
			g.grid[c].navigable = false
			g.tree_root[c] = root
	return sprite


static func spawn_trees(g: Grid, spawn_visuals: bool = true) -> void:
	var tree_textures: Array = [
		load("res://art/environment/alien lily pad tree var 1 rev.png"),
		load("res://art/environment/alien lily pad tree var 1 rev.png"),
	]
	var light_texture := _make_light_texture()
	var placed: Array = []
	const MIN_DISTANCE = 5
	const MAX_TREES = 8

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	const BIOME_RADIUS := 18.0
	var shore_y: int = g.height / 2
	var biome_centre := Vector2(
		rng.randi_range(int(BIOME_RADIUS) + 2, g.width  - int(BIOME_RADIUS) - 3),
		rng.randi_range(int(BIOME_RADIUS) + 2, shore_y - int(BIOME_RADIUS) - 3)
	)
	if biome_centre.distance_to(Vector2(0, 0)) < BIOME_RADIUS:
		biome_centre = Vector2(g.width * 0.6, shore_y * 0.4)

	var candidates: Array = []
	for x in range(0, g.width - 2):
		for y in range(0, g.height - 2):
			var p := Vector2(x, y)
			if p.distance_to(biome_centre) <= BIOME_RADIUS:
				candidates.append(p)
	candidates.shuffle()

	var tree_data: Array = []

	for pos in candidates:
		if tree_data.size() >= MAX_TREES:
			break
		if pos.distance_to(Vector2(0, 0)) < MIN_DISTANCE:
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_DISTANCE:
				too_close = true
				break
		if too_close:
			continue

		var can_place := true
		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c):
					can_place = false
			if not can_place:
				break
		if not can_place:
			continue

		placed.append(pos)

		var centre: Vector2 = pos + Vector2(1.0, 1.0)
		const DIRT_RADIUS := 6.5
		var local_dirt: Dictionary = {}

		for dx in range(-8, 9):
			for dy in range(-8, 9):
				var c := Vector2(centre.x + dx, centre.y + dy)
				if not g.grid.has(c) or g.water_tiles.has(c) or g.grid[c].occupier != null:
					continue
				var dist := Vector2(float(dx), float(dy)).length()
				var paint := false
				if dist <= 3.0:
					paint = true
				else:
					var prob := pow(max(0.0, 1.0 - (dist - 3.0) / (DIRT_RADIUS - 3.0)), 0.5)
					paint = rng.randf() < prob
				if paint:
					local_dirt[c] = true
					g.dirt_tiles[c] = true

		for dx in 3:
			for dy in 3:
				var c: Vector2 = pos + Vector2(dx, dy)
				g.grid[c].occupier = "Tree"
				g.grid[c].navigable = false
				g.tree_root[c] = pos

		tree_data.append({pos = pos, local_dirt = local_dirt, tex = tree_textures[rng.randi() % tree_textures.size()]})

	if not spawn_visuals:
		return

	var lily_tex := load("res://art/environment/alien lily pad plant.png")
	var sp: Node2D = g.sprite_layer if g.sprite_layer != null else g

	var dirt_tex := load("res://art/environment/alien dirt 3.png")
	var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial
	for c in g.dirt_tiles:
		var mask := 0
		if g.dirt_tiles.has(c + Vector2(0, -1)): mask |= 1
		if g.dirt_tiles.has(c + Vector2(1,  0)): mask |= 2
		if g.dirt_tiles.has(c + Vector2(0,  1)): mask |= 4
		if g.dirt_tiles.has(c + Vector2(-1, 0)): mask |= 8
		var diag := 0
		if g.dirt_tiles.has(c + Vector2( 1, -1)): diag |= 1
		if g.dirt_tiles.has(c + Vector2( 1,  1)): diag |= 2
		if g.dirt_tiles.has(c + Vector2(-1,  1)): diag |= 4
		if g.dirt_tiles.has(c + Vector2(-1, -1)): diag |= 8
		var dirt_sprite := Sprite2D.new()
		dirt_sprite.texture = dirt_tex
		dirt_sprite.position = g.gridToWorld(c) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		# dirt 3.png is 128x128, cell_size is 128 — scale 1:1
		dirt_sprite.scale = Vector2(1.0, 1.0)
		if mask < 15 or diag < 15:
			var mat: ShaderMaterial = dirt_base_mat.duplicate()
			mat.set_shader_parameter("cardinal_mask", mask)
			mat.set_shader_parameter("diag_mask", diag)
			mat.set_shader_parameter("fade_width", 0.55)
			dirt_sprite.material = mat
		sp.add_child(dirt_sprite)

	for td in tree_data:
		var pos: Vector2 = td.pos
		var local_dirt: Dictionary = td.local_dirt

		var tree_texture: Texture2D = td.tex
		var centre_pos := g.gridToWorld(pos) + Vector2(g.cell_size * 1.5, g.cell_size * 1.5)
		var tree_s := float(g.cell_size * 3) / float(tree_texture.get_width())

		var shadow := Sprite2D.new()
		shadow.texture = tree_texture
		shadow.position = centre_pos + Vector2(g.cell_size * 0.15, g.cell_size * 0.7)
		shadow.scale = Vector2(tree_s * 1.1, tree_s * 0.22)
		shadow.modulate = Color(0, 0, 0, 0.35)
		shadow.z_index = -1
		sp.add_child(shadow)
		g.shadow_sprites.append(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = tree_texture
		sprite.position = centre_pos
		sprite.scale = Vector2(tree_s, tree_s)
		sprite.z_index = int(pos.y) + 2
		sp.add_child(sprite)
		g.tree_sprites[pos] = sprite

		var tree_img: Image = _alpha_image(tree_texture as Texture2D)
		var tree_bm := BitMap.new()
		tree_bm.create_from_image_alpha(tree_img)
		var tree_polys := tree_bm.opaque_to_polygons(Rect2(Vector2.ZERO, tree_img.get_size()), 2.0)
		if not tree_polys.is_empty():
			var tree_body := StaticBody2D.new()
			tree_body.position = centre_pos
			var tree_origin := Vector2(tree_img.get_width() * 0.5, tree_img.get_height() * 0.5)
			for poly: PackedVector2Array in tree_polys:
				var cp := CollisionPolygon2D.new()
				var scaled := PackedVector2Array()
				for pt: Vector2 in poly:
					scaled.append((pt - tree_origin) * tree_s)
				cp.polygon = Geometry2D.convex_hull(scaled)
				tree_body.add_child(cp)
			sp.add_child(tree_body)

		var light := PointLight2D.new()
		light.texture = light_texture
		light.color = Color(0.3, 1.0, 0.7)
		light.energy = 0.0
		light.texture_scale = 4.5 / tree_s
		light.position = centre_pos
		sp.add_child(light)
		g.tree_lights.append(light)
		g.tree_lights_by_root[pos] = light
		# (Note: tree_sprites[pos] was set above to the actual Sprite2D — must
		# stay that way so harvest_tree can free it + capture the texture for
		# the regrowth sapling.)

		var lily_candidates: Array = local_dirt.keys()
		lily_candidates.shuffle()
		var lily_count := rng.randi_range(4, 7)
		var lily_placed := 0
		for lc in lily_candidates:
			if lily_placed >= lily_count:
				break
			if not g.grid.has(lc) or g.grid[lc].occupier != null:
				continue
			var lily := Sprite2D.new()
			lily.texture = lily_tex
			lily.position = g.gridToWorld(lc) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			lily.scale = Vector2(0.25, 0.25)
			# Ground-level decoration: z_index = cell.y - 1 so a unit
			# standing on the same cell (z_index = cell.y) renders ABOVE
			# the lily, while units further north (smaller cell.y, smaller
			# z_index) still get correctly occluded by lilies in front of
			# them. Previous +1 made the lily render on top of any unit
			# stepping on it.
			lily.z_index = int((lc as Vector2).y) - 1
			sp.add_child(lily)
			g.grid[lc].occupier = "LilyPad"
			lily_placed += 1


static func spawn_crash_site(g: Grid) -> void:
	var ship_tex  := load("res://art/crash_site/crashed ship.png") as Texture2D
	var hull_tex  := load("res://art/crash_site/crashed ship hull large.png") as Texture2D

	const SHIP_TILES := 4
	const HULL_TILES := 1

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var ship_pos := Vector2(-1, -1)
	var shore_y: int = g.height / 2
	for attempt in 40:
		var px: int = rng.randi_range(5, 14)
		var py: int = rng.randi_range(3, min(shore_y - SHIP_TILES - 1, 12))
		var ok := true
		for dx in SHIP_TILES:
			for dy in SHIP_TILES:
				var c := Vector2(px + dx, py + dy)
				if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c):
					ok = false
					break
			if not ok:
				break
		if ok:
			ship_pos = Vector2(px, py)
			break

	if ship_pos != Vector2(-1, -1):
		g.crash_site_pos = ship_pos
		g.ship_inventory = {
			"Metal Scrap": 8,
			"Electronics": 3,
			"Medical Supplies": 4,
			"Rations": 5,
		}
		var sp := g.gridToWorld(ship_pos) + Vector2(g.cell_size * SHIP_TILES * 0.5, g.cell_size * SHIP_TILES * 0.5)
		var half := float(SHIP_TILES * g.cell_size) * 0.5
		var a := half * 0.95
		var b := half * 0.50
		var tilt := -PI / 4.0

		# Corners of the 4x4 footprint are walkable; everything else is blocked.
		var ship_corners := [Vector2(0,0), Vector2(3,0), Vector2(0,3), Vector2(3,3)]
		for dx in SHIP_TILES:
			for dy in SHIP_TILES:
				var c := ship_pos + Vector2(dx, dy)
				if not g.grid.has(c):
					continue
				g.grid[c].occupier = "CrashedShip"
				if not ship_corners.has(Vector2(dx, dy)):
					g.grid[c].navigable = false

		var s_scale := float(SHIP_TILES * g.cell_size) / float(ship_tex.get_width())

		var ship_shadow := Sprite2D.new()
		ship_shadow.texture = ship_tex
		ship_shadow.position = sp + Vector2(24, 28)
		ship_shadow.scale = Vector2(s_scale * 1.1, s_scale * 0.5)
		ship_shadow.modulate = Color(0, 0, 0, 0.35)
		g.add_child(ship_shadow)
		g.shadow_sprites.append(ship_shadow)

		var ship_sprite := Sprite2D.new()
		ship_sprite.texture = ship_tex
		ship_sprite.scale = Vector2(s_scale, s_scale)
		ship_sprite.position = sp
		ship_sprite.z_index = int(ship_pos.y) + SHIP_TILES
		g.add_child(ship_sprite)

		var ship_body := StaticBody2D.new()
		ship_body.position = sp
		const STEPS := 20
		var ship_pts := PackedVector2Array()
		for i in STEPS:
			var t := (float(i) / STEPS) * TAU
			var ex := a * cos(t)
			var ey := b * sin(t)
			ship_pts.append(Vector2(
				ex * cos(tilt) - ey * sin(tilt),
				ex * sin(tilt) + ey * cos(tilt)
			))
		var ship_cp := CollisionPolygon2D.new()
		ship_cp.polygon = ship_pts
		ship_body.add_child(ship_cp)
		ship_body.set_meta("occupier", "CrashedShip")
		g.add_child(ship_body)

	var hull_count := rng.randi_range(1, 2)
	var hull_placed := 0
	if ship_pos != Vector2(-1, -1):
		for attempt in 60:
			if hull_placed >= hull_count:
				break
			var ox: int = rng.randi_range(-6, 6)
			var oy: int = rng.randi_range(-4, 4)
			var hp := ship_pos + Vector2(ox, oy)
			var ok := true
			for dx in HULL_TILES:
				for dy in HULL_TILES:
					var c := hp + Vector2(dx, dy)
					if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue

			for dx in HULL_TILES:
				for dy in HULL_TILES:
					var c := hp + Vector2(dx, dy)
					g.grid[c].occupier = "HullFragment"
					g.grid[c].navigable = false

			var hp_world := g.gridToWorld(hp) + Vector2(g.cell_size * HULL_TILES * 0.5, g.cell_size * HULL_TILES * 0.5)
			var h_scale := float(HULL_TILES * g.cell_size) / float(hull_tex.get_width())

			var hull_shadow := Sprite2D.new()
			hull_shadow.texture = hull_tex
			hull_shadow.position = hp_world + Vector2(18, 20)
			hull_shadow.scale = Vector2(h_scale * 1.1, h_scale * 0.5)
			hull_shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(hull_shadow)
			g.shadow_sprites.append(hull_shadow)

			var hull_sprite := Sprite2D.new()
			hull_sprite.texture = hull_tex
			hull_sprite.scale = Vector2(h_scale, h_scale)
			hull_sprite.position = hp_world
			hull_sprite.z_index = int(hp.y) + HULL_TILES
			g.add_child(hull_sprite)

			var hull_img: Image = _alpha_image(hull_tex)
			var hull_bm := BitMap.new()
			hull_bm.create_from_image_alpha(hull_img)
			var hull_polys := hull_bm.opaque_to_polygons(Rect2(Vector2.ZERO, hull_img.get_size()), 2.0)
			if not hull_polys.is_empty():
				var hull_body := StaticBody2D.new()
				hull_body.position = hp_world
				var hull_origin := Vector2(hull_img.get_width() * 0.5, hull_img.get_height() * 0.5)
				# Merge all polygon points and take convex hull — avoids convex decomposition failures
				var all_pts := PackedVector2Array()
				for poly: PackedVector2Array in hull_polys:
					for pt: Vector2 in poly:
						all_pts.append((pt - hull_origin) * h_scale)
				var hcp := CollisionPolygon2D.new()
				hcp.polygon = Geometry2D.convex_hull(all_pts)
				hull_body.add_child(hcp)
				hull_body.set_meta("occupier", "HullFragment")
				g.add_child(hull_body)

			hull_placed += 1

	if ship_pos != Vector2(-1, -1):
		var crate_tex := load("res://art/crash_site/supply crate.png") as Texture2D
		var crate_scale := float(g.cell_size) / float(crate_tex.get_width())
		var crate_count := rng.randi_range(2, 4)
		var crate_placed := 0
		for attempt in 80:
			if crate_placed >= crate_count:
				break
			var cx: int = rng.randi_range(-5, 5)
			var cy: int = rng.randi_range(-4, 4)
			var cp := ship_pos + Vector2(cx, cy)
			if not g.grid.has(cp) or g.grid[cp].occupier != null or g.water_tiles.has(cp):
				continue

			g.grid[cp].occupier = "SupplyCrate"
			g.grid[cp].navigable = false

			var all_loot: Array = [
				["Rations", rng.randi_range(2, 5)],
				["Bandages", rng.randi_range(1, 3)],
				["Tools", rng.randi_range(1, 2)],
				["Metal Scrap", rng.randi_range(1, 3)],
			]
			all_loot.shuffle()
			var crate_inv: Dictionary = {}
			for entry in all_loot.slice(0, rng.randi_range(2, 4)):
				crate_inv[entry[0]] = entry[1]
			g.crate_inventories[cp] = crate_inv

			var crate_world := g.gridToWorld(cp) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			var crate_shadow := Sprite2D.new()
			crate_shadow.texture = crate_tex
			crate_shadow.position = crate_world + Vector2(8, 10)
			crate_shadow.scale = Vector2(crate_scale * 1.1, crate_scale * 0.55)
			crate_shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(crate_shadow)
			g.shadow_sprites.append(crate_shadow)

			var crate_sprite := Sprite2D.new()
			crate_sprite.texture = crate_tex
			crate_sprite.scale = Vector2(crate_scale, crate_scale)
			crate_sprite.position = crate_world
			crate_sprite.z_index = int(cp.y) + 1
			g.add_child(crate_sprite)

			var crate_image: Image = _alpha_image(crate_tex)
			var crate_bm := BitMap.new()
			crate_bm.create_from_image_alpha(crate_image)
			var crate_polys := crate_bm.opaque_to_polygons(Rect2(Vector2.ZERO, crate_image.get_size()), 2.0)
			if not crate_polys.is_empty():
				var crate_body := StaticBody2D.new()
				crate_body.position = crate_world
				var crate_origin := Vector2(crate_image.get_width() * 0.5, crate_image.get_height() * 0.5)
				for poly: PackedVector2Array in crate_polys:
					var cp2 := CollisionPolygon2D.new()
					var scaled := PackedVector2Array()
					for pt: Vector2 in poly:
						scaled.append((pt - crate_origin) * crate_scale)
					cp2.polygon = Geometry2D.convex_hull(scaled)
					crate_body.add_child(cp2)
				crate_body.set_meta("occupier", "SupplyCrate")
				crate_body.set_meta("grid_pos", cp)
				g.add_child(crate_body)

			crate_placed += 1


static func spawn_driftwood(g: Grid) -> void:
	var textures: Array = [
		load("res://art/environment/driftwood 1.png"),
		load("res://art/environment/driftwood 2.png"),
		load("res://art/environment/driftwood 3.png"),
		load("res://art/environment/driftwood 4.png"),
		load("res://art/environment/driftwood 5.png"),
	]

	const SHORE_BAND  := 6
	const COUNT       := 8
	const MIN_DIST    := 10

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = g.height / 2

	var candidates: Array = []
	for x in range(0, g.width):
		for y in range(0, shore_y):
			var c := Vector2(x, y)
			if not g.water_tiles.has(c) and not g.dirt_tiles.has(c):
				candidates.append(c)
	candidates.shuffle()

	var placed_cells: Array = []
	var placed := 0
	for cell in candidates:
		if placed >= COUNT:
			break
		if not g.grid.has(cell) or g.grid[cell].occupier != null or g.water_tiles.has(cell):
			continue
		var too_close := false
		for pc in placed_cells:
			if cell.distance_to(pc) < MIN_DIST:
				too_close = true
				break
		if too_close:
			continue

		var tex: Texture2D = textures[rng.randi() % textures.size()]
		var longest := float(max(tex.get_width(), tex.get_height()))
		var s := float(g.cell_size) * 1.5 / longest

		var pos := g.gridToWorld(cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)

		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.scale = Vector2(s * 1.1, s * 0.55)
		shadow.position = pos + Vector2(14, 16)
		shadow.modulate = Color(0, 0, 0, 0.3)
		g.add_child(shadow)
		g.shadow_sprites.append(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2(s, s)
		sprite.position = pos
		sprite.z_index = int(cell.y) + 1
		g.add_child(sprite)

		var dw_body_ref: StaticBody2D = null
		var dw_img: Image = _alpha_image(tex)
		var dw_bm := BitMap.new()
		dw_bm.create_from_image_alpha(dw_img)
		var dw_polys := dw_bm.opaque_to_polygons(Rect2(Vector2.ZERO, dw_img.get_size()), 2.0)
		if not dw_polys.is_empty():
			var dw_body := StaticBody2D.new()
			dw_body.position = pos
			# Tag the body so the right-click physics query can identify the
			# driftwood and resolve back to its cell for collection.
			dw_body.set_meta("occupier", "Driftwood")
			dw_body.set_meta("grid_pos", cell)
			var dw_origin := Vector2(dw_img.get_width() * 0.5, dw_img.get_height() * 0.5)
			for poly: PackedVector2Array in dw_polys:
				var dcp := CollisionPolygon2D.new()
				var scaled := PackedVector2Array()
				for pt: Vector2 in poly:
					scaled.append((pt - dw_origin) * s)
				dcp.polygon = Geometry2D.convex_hull(scaled)
				dw_body.add_child(dcp)
			g.add_child(dw_body)
			dw_body_ref = dw_body

		g.grid[cell].occupier = "Driftwood"
		g.grid[cell].navigable = false
		# Track per-cell so collect_driftwood can free just this pile when a
		# unit picks it up.
		g.driftwood_nodes[cell] = {"sprite": sprite, "shadow": shadow, "body": dw_body_ref}
		placed_cells.append(cell)
		placed += 1


static func spawn_rocks(g: Grid) -> void:
	var tex_light1 = load("res://art/environment/rock light realistic 1.png")
	var tex_light2 = load("res://art/environment/rock light realistic 2.png")
	var tex_pebbles = load("res://art/environment/pebbles.png")
	const MAX_CLUSTERS = 25
	const MIN_CLUSTER_DISTANCE = 4
	const CLUSTER_RADIUS = 2

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var candidates: Array = []
	for x in g.width:
		for y in g.height:
			candidates.append(Vector2(x, y))
	candidates.shuffle()

	var centers: Array = []
	for pos in candidates:
		if centers.size() >= MAX_CLUSTERS:
			break
		if not g.grid.has(pos) or g.grid[pos].occupier != null or g.water_tiles.has(pos) or g.dirt_tiles.has(pos):
			continue
		if pos.distance_to(Vector2(0, 0)) < 4:
			continue
		var too_close := false
		for c in centers:
			if pos.distance_to(c) < MIN_CLUSTER_DISTANCE:
				too_close = true
				break
		if too_close:
			continue
		centers.append(pos)

	for center in centers:
		var nearby: Array = []
		for dx in range(-CLUSTER_RADIUS, CLUSTER_RADIUS + 1):
			for dy in range(-CLUSTER_RADIUS, CLUSTER_RADIUS + 1):
				var c: Vector2 = center + Vector2(dx, dy)
				if g.grid.has(c) and g.grid[c].occupier == null and not g.water_tiles.has(c) and not g.dirt_tiles.has(c):
					nearby.append(c)
		nearby.shuffle()
		var count := rng.randi_range(2, 3)
		for i in min(count, nearby.size()):
			var cell: Vector2 = nearby[i]
			g.grid[cell].occupier = "Rock"
			g.grid[cell].navigable = false

			var tex = tex_light1 if rng.randi() % 2 == 0 else tex_light2
			var center_pos := g.gridToWorld(cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			var rock_scale := float(g.cell_size) * 0.8 / float(tex.get_height())

			var shadow := Sprite2D.new()
			shadow.texture = tex
			shadow.position = center_pos + Vector2(8, 10)
			shadow.scale = Vector2(rock_scale * 1.15, rock_scale * 0.45)
			shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(shadow)
			g.shadow_sprites.append(shadow)

			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.position = center_pos
			sprite.scale = Vector2(rock_scale, rock_scale)
			sprite.z_index = int(center_pos.y / g.cell_size)
			g.add_child(sprite)

			var body_ref: StaticBody2D = null
			# Build a pixel-perfect StaticBody2D from the sprite's alpha channel.
			var image: Image = _alpha_image(tex as Texture2D)
			var bm := BitMap.new()
			bm.create_from_image_alpha(image)
			var polys := bm.opaque_to_polygons(Rect2(Vector2.ZERO, image.get_size()), 2.0)
			if not polys.is_empty():
				var body := StaticBody2D.new()
				body.position = center_pos
				body.set_meta("occupier", "Rock")
				body.set_meta("grid_pos", cell)
				# Sprite2D is centered, so offset polygon origin to match.
				var origin := Vector2(image.get_width() * 0.5, image.get_height() * 0.5)
				for poly: PackedVector2Array in polys:
					var cp := CollisionPolygon2D.new()
					var scaled := PackedVector2Array()
					for pt: Vector2 in poly:
						scaled.append((pt - origin) * rock_scale)
					cp.polygon = Geometry2D.convex_hull(scaled)
					body.add_child(cp)
				g.add_child(body)
				body_ref = body
			# Track per-cell so Grid.mine_rock can clean up just this rock.
			g.rock_nodes[cell] = {"sprite": sprite, "shadow": shadow, "body": body_ref}

		if rng.randf() > 0.3:
			continue
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(0.3, float(CLUSTER_RADIUS) + 0.8)
		var offset := Vector2(cos(angle), sin(angle)) * dist * g.cell_size
		var pebble_cell := g.worldToGrid(g.gridToWorld(center) + offset)
		if not g.grid.has(pebble_cell) or g.water_tiles.has(pebble_cell) or g.dirt_tiles.has(pebble_cell):
			continue
		var pebble := Sprite2D.new()
		pebble.texture = tex_pebbles
		pebble.position = g.gridToWorld(pebble_cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		var pebble_scale := float(g.cell_size) * 0.5 / float(tex_pebbles.get_height())
		pebble.scale = Vector2(pebble_scale, pebble_scale)
		pebble.z_index = 0
		g.add_child(pebble)


static func spawn_tide_pools(g: Grid) -> void:
	var pool_textures: Array = [
		load("res://art/environment/tide pool 1 tile var 1.png"),
		load("res://art/environment/tide pool 1 tile var 2.png"),
		load("res://art/environment/tide pool 1 tile var 3.png"),
	]
	var rock_tex   = load("res://art/environment/tide pool ground overlay.png")
	var iron_tex   = load("res://art/environment/iron ore vein.png")
	var copper_tex = load("res://art/environment/copper ore vein.png")

	const POOL_SIZE       = 2
	const SHORE_BAND      = 6
	const MIN_CLUSTER_DIST = 20

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = g.height / 2

	var all_candidates: Array = []
	for x in range(0, g.width - POOL_SIZE):
		for y in range(shore_y - SHORE_BAND, shore_y):
			all_candidates.append(Vector2(x, y))
	all_candidates.shuffle()

	var S: float             = g.cell_size * 2.0
	var light_tex            := _make_light_texture()
	var ring_offsets: Array  = [
		Vector2(0,-S), Vector2(S,0), Vector2(0,S), Vector2(-S,0),
		Vector2(-S,-S), Vector2(S,-S), Vector2(-S,S), Vector2(S,S),
	]
	var extra_side_offsets: Array = [
		[Vector2(-S,-S*2), Vector2(0,-S*2), Vector2(S,-S*2)],
		[Vector2(S*2,-S),  Vector2(S*2,0),  Vector2(S*2,S) ],
		[Vector2(-S,S*2),  Vector2(0,S*2),  Vector2(S,S*2) ],
		[Vector2(-S*2,-S), Vector2(-S*2,0), Vector2(-S*2,S)],
	]
	var adj_offsets: Array = [Vector2(2,0), Vector2(-2,0), Vector2(0,2), Vector2(0,-2)]

	var placed_anchors: Array    = []
	var global_footprints: Dictionary = {}

	var target_clusters: int = rng.randi_range(2, 3)

	for _cluster in range(target_clusters):
		var anchor := Vector2(-1, -1)
		for candidate in all_candidates:
			var ok: bool = true
			for dx in POOL_SIZE:
				for dy in POOL_SIZE:
					var c: Vector2 = candidate + Vector2(dx, dy)
					if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c) or global_footprints.has(c):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			for pa in placed_anchors:
				if candidate.distance_to(pa) < MIN_CLUSTER_DIST:
					ok = false
					break
			if ok:
				anchor = candidate
				break
		if anchor == Vector2(-1, -1):
			continue

		placed_anchors.append(anchor)

		var pool_count: int    = rng.randi_range(2, 3)
		var pool_positions: Array = [anchor]
		var pool_footprints: Dictionary = {}
		for dx in POOL_SIZE:
			for dy in POOL_SIZE:
				pool_footprints[anchor + Vector2(dx, dy)] = true

		for _i in range(20):
			if pool_positions.size() >= pool_count:
				break
			var base: Vector2 = pool_positions[rng.randi() % pool_positions.size()]
			adj_offsets.shuffle()
			for off in adj_offsets:
				var off_vec: Vector2 = off
				var np: Vector2 = base + off_vec
				var ok: bool = true
				for dx in POOL_SIZE:
					for dy in POOL_SIZE:
						var c: Vector2 = np + Vector2(dx, dy)
						if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c) or pool_footprints.has(c) or global_footprints.has(c):
							ok = false
							break
					if not ok:
						break
				if ok:
					pool_positions.append(np)
					for dx in POOL_SIZE:
						for dy in POOL_SIZE:
							pool_footprints[np + Vector2(dx, dy)] = true
					break

		for k in pool_footprints:
			global_footprints[k] = true

		var pool_centres: Dictionary = {}
		for pp in pool_positions:
			pool_centres[g.gridToWorld(pp) + Vector2(g.cell_size, g.cell_size)] = true

		var cluster_centre: Vector2 = Vector2.ZERO
		for pp in pool_positions:
			cluster_centre += g.gridToWorld(pp) + Vector2(g.cell_size, g.cell_size)
		cluster_centre /= pool_positions.size()

		var wet_gradient := Gradient.new()
		wet_gradient.set_color(0, Color(0.18, 0.14, 0.10, 0.55))
		wet_gradient.set_color(1, Color(0.18, 0.14, 0.10, 0.0))
		var wet_tex := GradientTexture2D.new()
		wet_tex.gradient = wet_gradient
		wet_tex.fill = GradientTexture2D.FILL_RADIAL
		wet_tex.fill_from = Vector2(0.5, 0.5)
		wet_tex.fill_to  = Vector2(1.0, 0.5)
		wet_tex.width  = 256
		wet_tex.height = 256
		var wet_sprite := Sprite2D.new()
		wet_sprite.texture = wet_tex
		wet_sprite.position = cluster_centre
		wet_sprite.scale = Vector2(8.0, 8.0)
		wet_sprite.z_index = 0
		g.add_child(wet_sprite)

		var shuffled_textures: Array = pool_textures.duplicate()
		shuffled_textures.shuffle()
		for pi in pool_positions.size():
			var pp: Vector2 = pool_positions[pi]
			for dx in POOL_SIZE:
				for dy in POOL_SIZE:
					var c: Vector2 = pp + Vector2(dx, dy)
					g.grid[c].occupier = "TidePool"
					g.grid[c].navigable = false
			var cp: Vector2 = g.gridToWorld(pp) + Vector2(g.cell_size, g.cell_size)
			var pool_sprite := Sprite2D.new()
			var pool_tex: Texture2D = shuffled_textures[pi % 3]
			pool_sprite.texture = pool_tex
			pool_sprite.position = cp
			var pool_scale := float(g.cell_size) * 2.0 / float(pool_tex.get_width())
			pool_sprite.scale = Vector2(pool_scale, pool_scale)
			pool_sprite.z_index = 0
			g.add_child(pool_sprite)
			var sp: Node2D = g.sprite_layer if g.sprite_layer != null else g
			var light := PointLight2D.new()
			light.texture = light_tex
			light.color = Color(0.1, 0.85, 1.0)
			light.energy = 0.0
			light.texture_scale = 5.5
			light.position = cp
			sp.add_child(light)
			g.tree_lights.append(light)

		var rock_positions: Dictionary = {}
		for pp in pool_positions:
			var cp: Vector2 = g.gridToWorld(pp) + Vector2(g.cell_size, g.cell_size)
			for ro in ring_offsets:
				var ro_vec: Vector2 = ro
				var rp: Vector2 = cp + ro_vec
				if not pool_centres.has(rp) and g.grid.has(g.worldToGrid(rp)):
					rock_positions[rp] = true
			for side_opts in extra_side_offsets:
				var opts: Array = side_opts
				var ext: Vector2 = opts[rng.randi() % 3]
				var ep: Vector2 = cp + ext
				if not pool_centres.has(ep) and g.grid.has(g.worldToGrid(ep)):
					rock_positions[ep] = true

		var fade_shader := load("res://art/shaders/tide_pool_rock.gdshader") as Shader
		for rp_key in rock_positions:
			var rp: Vector2 = rp_key
			var mask: int = 0
			if pool_centres.has(rp+Vector2(0,-S)) or rock_positions.has(rp+Vector2(0,-S)): mask |= 1
			if pool_centres.has(rp+Vector2(S, 0)) or rock_positions.has(rp+Vector2(S, 0)): mask |= 2
			if pool_centres.has(rp+Vector2(0, S)) or rock_positions.has(rp+Vector2(0, S)): mask |= 4
			if pool_centres.has(rp+Vector2(-S,0)) or rock_positions.has(rp+Vector2(-S,0)): mask |= 8
			var rock_sprite := Sprite2D.new()
			rock_sprite.texture = rock_tex
			rock_sprite.position = rp
			var tide_rock_scale := float(g.cell_size) * 2.0 / float(rock_tex.get_height())
			rock_sprite.scale = Vector2(tide_rock_scale, tide_rock_scale)
			rock_sprite.z_index = 0
			var rock_mat := ShaderMaterial.new()
			rock_mat.shader = fade_shader
			rock_mat.set_shader_parameter("cardinal_mask", mask)
			rock_mat.set_shader_parameter("fade_width", 0.3)
			rock_sprite.material = rock_mat
			g.add_child(rock_sprite)
			var rock_gc: Vector2 = g.worldToGrid(rp)
			if g.grid.has(rock_gc):
				g.grid[rock_gc].occupier = "TidePoolRock"

		var ore_candidates: Array = rock_positions.keys()
		ore_candidates.shuffle()
		var ore_count: int = rng.randi_range(2, 3)
		var used_ore_cells: Dictionary = {}
		for i in min(ore_count * 2, ore_candidates.size()):
			if used_ore_cells.size() >= ore_count * 2:
				break
			var ore_pos: Vector2 = ore_candidates[i]
			var gc: Vector2 = g.worldToGrid(ore_pos)
			if not g.grid.has(gc) or g.water_tiles.has(gc) or used_ore_cells.has(gc):
				continue
			used_ore_cells[gc] = true
			g.grid[gc].occupier = "Ore"
			g.grid[gc].navigable = false
			# Track whether this is iron-heavy or copper-heavy so mine_at can
			# roll drops appropriately. First half of the count = iron, rest
			# = copper, matching the texture choice below.
			var is_iron: bool = used_ore_cells.size() <= ore_count
			var ore_tex: Texture2D = iron_tex if is_iron else copper_tex
			var ore_pos2: Vector2 = g.gridToWorld(gc) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)

			var ore_scale := float(g.cell_size) * 0.9 / float(ore_tex.get_height())

			var ore_shadow := Sprite2D.new()
			ore_shadow.texture = ore_tex
			ore_shadow.position = ore_pos2 + Vector2(8, 10)
			ore_shadow.scale = Vector2(ore_scale * 1.1, ore_scale * 0.45)
			ore_shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(ore_shadow)
			g.shadow_sprites.append(ore_shadow)

			var ore_sprite := Sprite2D.new()
			ore_sprite.texture = ore_tex
			ore_sprite.position = ore_pos2
			ore_sprite.scale = Vector2(ore_scale, ore_scale)
			ore_sprite.z_index = int(gc.y) + 1
			g.add_child(ore_sprite)

			var ore_body_ref: StaticBody2D = null
			var ore_img: Image = _alpha_image(ore_tex)
			var ore_bm := BitMap.new()
			ore_bm.create_from_image_alpha(ore_img)
			var ore_polys := ore_bm.opaque_to_polygons(Rect2(Vector2.ZERO, ore_img.get_size()), 2.0)
			if not ore_polys.is_empty():
				var ore_body := StaticBody2D.new()
				ore_body.position = ore_pos2
				# Tag for right-click physics query — same convention as Rock.
				ore_body.set_meta("occupier", "Ore")
				ore_body.set_meta("grid_pos", gc)
				var ore_origin := Vector2(ore_img.get_width() * 0.5, ore_img.get_height() * 0.5)
				for poly: PackedVector2Array in ore_polys:
					var ocp := CollisionPolygon2D.new()
					var scaled := PackedVector2Array()
					for pt: Vector2 in poly:
						scaled.append((pt - ore_origin) * ore_scale)
					ocp.polygon = Geometry2D.convex_hull(scaled)
					ore_body.add_child(ocp)
				g.add_child(ore_body)
				ore_body_ref = ore_body
			# Track per-cell so mine_at can clean up when the ore is consumed,
			# plus remember which kind of ore so the drop roll picks the
			# matching primary metal.
			g.ore_nodes[gc] = {
				"sprite": ore_sprite,
				"shadow": ore_shadow,
				"body": ore_body_ref,
				"kind": "iron" if is_iron else "copper",
			}


static func spawn_monolith(g: Grid) -> void:
	var tex := load("res://art/environment/sand monolith realistic.png") as Texture2D
	const TILES := 2

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = g.height / 2
	var candidates: Array = []
	for x in range(TILES, g.width - TILES):
		for y in range(TILES, shore_y - TILES - 1):
			var pos := Vector2(x, y)
			var ok := true
			for dx in TILES:
				for dy in TILES:
					var c := pos + Vector2(dx, dy)
					if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c) or g.dirt_tiles.has(c):
						ok = false
						break
				if not ok:
					break
			if ok:
				candidates.append(pos)

	if candidates.is_empty():
		return

	var pos: Vector2 = candidates[rng.randi() % candidates.size()]
	for dx in TILES:
		for dy in TILES:
			var c := pos + Vector2(dx, dy)
			g.grid[c].occupier = "Monolith"
			g.grid[c].navigable = false

	g.monolith_pos = pos
	var centre_world := g.gridToWorld(pos) + Vector2(g.cell_size * TILES * 0.5, g.cell_size * TILES * 0.5)

	var s := float(TILES * g.cell_size) / float(tex.get_width())
	var shadow := Sprite2D.new()
	shadow.texture = tex
	shadow.scale = Vector2(s * 1.1, s * 0.5)
	shadow.position = centre_world + Vector2(20, 28)
	shadow.modulate = Color(0, 0, 0, 0.35)
	g.add_child(shadow)
	g.shadow_sprites.append(shadow)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(s, s)
	sprite.position = centre_world
	sprite.z_index = int(pos.y) + TILES
	g.add_child(sprite)

	var mono_img: Image = _alpha_image(tex)
	var mono_bm := BitMap.new()
	mono_bm.create_from_image_alpha(mono_img)
	var mono_polys := mono_bm.opaque_to_polygons(Rect2(Vector2.ZERO, mono_img.get_size()), 2.0)
	if not mono_polys.is_empty():
		var mono_body := StaticBody2D.new()
		mono_body.position = centre_world
		var mono_origin := Vector2(mono_img.get_width() * 0.5, mono_img.get_height() * 0.5)
		for poly: PackedVector2Array in mono_polys:
			var mcp := CollisionPolygon2D.new()
			var scaled := PackedVector2Array()
			for pt: Vector2 in poly:
				scaled.append((pt - mono_origin) * s)
			mcp.polygon = Geometry2D.convex_hull(scaled)
			mono_body.add_child(mcp)
		mono_body.set_meta("occupier", "Monolith")
		g.add_child(mono_body)

	var glow_tex := _make_light_texture()
	var glow := Sprite2D.new()
	glow.texture = glow_tex
	glow.modulate = Color(0.5, 0.1, 1.0, 0.25)
	var glow_size := float(g.cell_size * 3)
	glow.scale = Vector2(glow_size / 256.0, glow_size / 256.0)
	glow.position = centre_world
	glow.z_index = 0
	g.add_child(glow)

	var light_tex := _make_light_texture()
	var light := PointLight2D.new()
	light.texture = light_tex
	light.color = Color(0.55, 0.1, 1.0)
	light.energy = 0.0
	light.texture_scale = 5.0
	sprite.add_child(light)
	g.red_tree_lights.append(light)


# Attach the cyan eye-glow PointLight2D to a freshly-spawned crab. Registers
# the light in g.crab_lights so the day/night cycle controller fades it in
# at night alongside the ambient crabs. Used by WaveManager._spawn_wave_crab
# and EventManager._spawn_creature so wave / event creatures aren't visually
# distinct from peacetime ambient ones.
static func attach_crab_light(g: Grid, crab: Node2D) -> void:
	var light := PointLight2D.new()
	light.texture = _make_light_texture()
	light.color = Color(0.2, 0.9, 1.0)
	light.energy = 0.0
	light.texture_scale = 2.5
	light.position = Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
	crab.add_child(light)
	g.crab_lights.append(light)


static func spawn_crabs(g: Grid) -> void:
	# Ambient peacetime creatures, layered by distance from the coast so
	# the player meets a different threat as they push inland:
	#   • Alien Crabs       — coastline (0-8 tiles north of shore)
	#   • Tide Crawlers     — mid-band (8-16 tiles)
	#   • Shore Stalkers    — deep inland (16-26 tiles)
	# Sky Mawlings and the Brood Mother are excluded from peacetime —
	# they're wave/event-only since they ramp difficulty quickly. Each
	# species reuses Crab.tscn with a different CreatureDefs entry; the
	# Crab class reads stats from the def, so combat / AI just works.
	var crab_scene := load("res://scenes/Crab.tscn") as PackedScene
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var shore_y: int = g.height / 2
	var light_tex := _make_light_texture()

	# (def_key, count, y_min_offset_from_shore, y_max_offset_from_shore)
	# y offsets are NEGATIVE because land is above the shore (smaller y).
	var bands: Array = [
		["alien_crab",    6, -8,  -1],
		["tide_crawler",  3, -16, -8],
		["shore_stalker", 2, -26, -16],
	]

	for band in bands:
		var def_key: String = band[0]
		var target_count: int = band[1]
		var y_lo: int = shore_y + band[2]   # smaller y = further inland
		var y_hi: int = shore_y + band[3]
		_spawn_ambient_band(g, crab_scene, light_tex, def_key, target_count, y_lo, y_hi, shore_y)

	# Driftbacks — peaceful driftwood-haulers, one beside each driftwood pile.
	# spawnDriftwood() runs before spawnCrabs() in worldgen, so g.driftwood_nodes
	# is already populated. Tying them to piles guarantees they always appear and
	# reinforces the "this creature carries driftwood" read.
	_spawn_driftbacks_near_driftwood(g, crab_scene, light_tex, shore_y)


# Helper for spawn_crabs: pick `target_count` cells in the [y_lo, y_hi) band
# and instantiate a Crab from the named def. Skips water / dirt / occupied
# cells. Each creature gets the cyan eye-glow light parented so the night
# cycle still picks them up via g.crab_lights.
static func _spawn_ambient_band(g: Grid, crab_scene: PackedScene, light_tex: Texture2D, def_key: String, target_count: int, y_lo: int, y_hi: int, shore_y: int) -> void:
	var def: Dictionary = CreatureDefs.DEFS.get(def_key, {})
	if def.is_empty():
		return
	var tex_down := load(def.tex_down) as Texture2D
	var tex_side := load(def.tex_side) as Texture2D
	if tex_down == null or tex_side == null:
		return

	var candidates: Array = []
	for x in g.width:
		for y in range(y_lo, y_hi):
			var c := Vector2(x, y)
			if g.grid.has(c) and not g.water_tiles.has(c) and not g.dirt_tiles.has(c) and g.grid[c].occupier == null:
				candidates.append(c)
	candidates.shuffle()

	var spawned: int = 0
	for cell in candidates:
		if spawned >= target_count:
			break
		var crab: Crab = crab_scene.instantiate()
		crab.position = g.gridToWorld(cell)
		# Wander bounds: keep each species roughly inside its band so
		# alien crabs don't wander into stalker territory and vice versa.
		# A small overhang (±2 tiles) keeps movement looking natural at
		# band edges instead of pingponging off invisible walls.
		crab.shore_y_min = y_lo - 2
		crab.shore_y_max = y_hi + 2 if y_hi < shore_y else shore_y - 1
		g.add_child(crab)
		g.crabs.append(crab)
		crab.setup(tex_down, tex_side, g, def)

		var light := PointLight2D.new()
		light.texture = light_tex
		light.color = Color(0.2, 0.9, 1.0)
		light.energy = 0.0
		light.texture_scale = 2.5
		light.position = Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		crab.add_child(light)
		g.crab_lights.append(light)

		spawned += 1


# Spawn one Driftback on a free cell adjacent to each driftwood pile. The pile
# cell itself is occupied (non-navigable), so the creature stands beside it and
# its wander band is clamped tight around the pile so it lingers nearby instead
# of roaming inland. Ambient (non-aggressive) like the band-spawned creatures —
# it only retaliates when attacked. Saved/restored generically via the shared
# ambient-creature serialization (Grid.serialize_world reverse-looks-up def_key).
static func _spawn_driftbacks_near_driftwood(g: Grid, crab_scene: PackedScene, light_tex: Texture2D, shore_y: int) -> void:
	var def: Dictionary = CreatureDefs.DEFS.get("driftback", {})
	if def.is_empty():
		return
	var tex_down := load(def.tex_down) as Texture2D
	var tex_side := load(def.tex_side) as Texture2D
	if tex_down == null or tex_side == null:
		return

	# How far a Driftback is allowed to drift from its home pile, in tiles.
	const DRIFT_WANDER: int = 5
	# 8-neighbourhood, shuffled per pile so the creature isn't always NE of it.
	var offsets: Array = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
	]

	for cell in g.driftwood_nodes.keys():
		offsets.shuffle()
		var spot: Vector2 = Vector2(-1, -1)
		for off in offsets:
			var c: Vector2 = cell + off
			if g.grid.has(c) and not g.water_tiles.has(c) and not g.dirt_tiles.has(c) and g.grid[c].occupier == null:
				spot = c
				break
		if spot == Vector2(-1, -1):
			continue  # pile is boxed in — skip it rather than overlap something

		var crab: Crab = crab_scene.instantiate()
		crab.position = g.gridToWorld(spot)
		# Keep it loitering around its driftwood, clamped to the coastal land
		# band (never south of the shoreline into the water).
		crab.shore_y_min = int(spot.y) - DRIFT_WANDER
		crab.shore_y_max = min(int(spot.y) + DRIFT_WANDER, shore_y - 1)
		g.add_child(crab)
		g.crabs.append(crab)
		crab.setup(tex_down, tex_side, g, def)

		var light := PointLight2D.new()
		light.texture = light_tex
		light.color = Color(0.2, 0.9, 1.0)
		light.energy = 0.0
		light.texture_scale = 2.5
		light.position = Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		crab.add_child(light)
		g.crab_lights.append(light)


# ── World restoration (save/load) ─────────────────────────────────────────────
#
# Each restore_X function rebuilds visuals and grid bookkeeping from a
# saved data array, skipping the random selection logic in spawn_X. Used
# by Grid.apply_world during save loading. The saved arrays are produced
# by Grid.serialize_world.
#
# Texture variants are referenced by INDEX (0-based) into the TEXTURES_*
# arrays defined here so saves stay portable across asset re-orderings
# as long as we don't reshuffle these registries. If you add a new
# variant, append it to keep existing save indices valid.

const TREE_TEXTURE_PATHS: Array = [
	"res://art/environment/alien lily pad tree var 1 rev.png",
	"res://art/environment/alien lily pad tree var 1 rev.png",
]
const ROCK_TEXTURE_PATHS: Array = [
	"res://art/environment/rock light realistic 1.png",
	"res://art/environment/rock light realistic 2.png",
]
const DRIFTWOOD_TEXTURE_PATHS: Array = [
	"res://art/environment/driftwood 1.png",
	"res://art/environment/driftwood 2.png",
	"res://art/environment/driftwood 3.png",
	"res://art/environment/driftwood 4.png",
	"res://art/environment/driftwood 5.png",
]


# Trees — reuses the existing per-tree primitive `spawn_one_tree` and
# additionally writes the dirt biome from the saved tile dict so the
# trunk-base sand patches render under each tree exactly as they did
# before saving.
static func restore_trees(g: Grid, trees_data: Array) -> void:
	for entry_v: Variant in trees_data:
		var entry: Dictionary = entry_v as Dictionary
		var root: Vector2 = Vector2(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var tex_idx: int = clamp(int(entry.get("tex", 0)), 0, TREE_TEXTURE_PATHS.size() - 1)
		var tex: Texture2D = load(TREE_TEXTURE_PATHS[tex_idx]) as Texture2D
		if tex == null:
			continue
		spawn_one_tree(g, root, tex)


# Dirt biome cells — `dirt_tiles` dict is rebuilt by the caller before
# this runs; this just handles the visual sprite layer (with shader-
# masked fade based on neighbours). Mirrors the lower half of
# spawn_trees but skipping the tree placement loop.
static func restore_dirt(g: Grid) -> void:
	var sp: Node2D = g.sprite_layer if g.sprite_layer != null else g
	var dirt_tex := load("res://art/environment/alien dirt 3.png")
	var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial
	for c in g.dirt_tiles:
		var mask := 0
		if g.dirt_tiles.has(c + Vector2(0, -1)): mask |= 1
		if g.dirt_tiles.has(c + Vector2(1,  0)): mask |= 2
		if g.dirt_tiles.has(c + Vector2(0,  1)): mask |= 4
		if g.dirt_tiles.has(c + Vector2(-1, 0)): mask |= 8
		var diag := 0
		if g.dirt_tiles.has(c + Vector2( 1, -1)): diag |= 1
		if g.dirt_tiles.has(c + Vector2( 1,  1)): diag |= 2
		if g.dirt_tiles.has(c + Vector2(-1,  1)): diag |= 4
		if g.dirt_tiles.has(c + Vector2(-1, -1)): diag |= 8
		var dirt_sprite := Sprite2D.new()
		dirt_sprite.texture = dirt_tex
		dirt_sprite.position = g.gridToWorld(c) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		dirt_sprite.scale = Vector2(1.0, 1.0)
		if mask < 15 or diag < 15:
			var mat: ShaderMaterial = dirt_base_mat.duplicate()
			mat.set_shader_parameter("cardinal_mask", mask)
			mat.set_shader_parameter("diag_mask", diag)
			mat.set_shader_parameter("fade_width", 0.55)
			dirt_sprite.material = mat
		sp.add_child(dirt_sprite)


# Rocks — single-cell, light variant 1 or 2. Inlined from spawn_rocks
# without the cluster-pick / random-count logic.
static func restore_rocks(g: Grid, rocks_data: Array) -> void:
	for entry_v: Variant in rocks_data:
		var entry: Dictionary = entry_v as Dictionary
		var cell: Vector2 = Vector2(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var tex_idx: int = clamp(int(entry.get("tex", 0)), 0, ROCK_TEXTURE_PATHS.size() - 1)
		var tex: Texture2D = load(ROCK_TEXTURE_PATHS[tex_idx]) as Texture2D
		if tex == null:
			continue
		g.grid[cell].occupier = "Rock"
		g.grid[cell].navigable = false
		var center_pos := g.gridToWorld(cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		var rock_scale := float(g.cell_size) * 0.8 / float(tex.get_height())
		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.position = center_pos + Vector2(8, 10)
		shadow.scale = Vector2(rock_scale * 1.15, rock_scale * 0.45)
		shadow.modulate = Color(0, 0, 0, 0.35)
		g.add_child(shadow)
		g.shadow_sprites.append(shadow)
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.position = center_pos
		sprite.scale = Vector2(rock_scale, rock_scale)
		sprite.z_index = int(cell.y) + 1
		g.add_child(sprite)
		var img: Image = _alpha_image(tex)
		var bm := BitMap.new()
		bm.create_from_image_alpha(img)
		var polys := bm.opaque_to_polygons(Rect2(Vector2.ZERO, img.get_size()), 2.0)
		var body_ref: StaticBody2D = null
		if not polys.is_empty():
			var body := StaticBody2D.new()
			body.position = center_pos
			body.set_meta("occupier", "Rock")
			body.set_meta("grid_pos", cell)
			var origin := Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
			for poly: PackedVector2Array in polys:
				var cp := CollisionPolygon2D.new()
				var scaled := PackedVector2Array()
				for pt: Vector2 in poly:
					scaled.append((pt - origin) * rock_scale)
				cp.polygon = Geometry2D.convex_hull(scaled)
				body.add_child(cp)
			g.add_child(body)
			body_ref = body
		g.rock_nodes[cell] = {"sprite": sprite, "shadow": shadow, "body": body_ref}


# Ore veins — single-cell, kind = "iron" or "copper". Grid.spawn_ores
# (called from spawn_tide_pools) does similar visuals; this is the
# minimal restore variant.
static func restore_ores(g: Grid, ores_data: Array) -> void:
	const IRON_TEX_PATH := "res://art/environment/iron ore vein.png"
	const COPPER_TEX_PATH := "res://art/environment/copper ore vein.png"
	for entry_v: Variant in ores_data:
		var entry: Dictionary = entry_v as Dictionary
		var cell: Vector2 = Vector2(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var kind: String = String(entry.get("kind", "iron"))
		var path: String = COPPER_TEX_PATH if kind == "copper" else IRON_TEX_PATH
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		g.grid[cell].occupier = "Ore"
		g.grid[cell].navigable = false
		var center_pos := g.gridToWorld(cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		var ore_scale := float(g.cell_size) * 0.85 / float(tex.get_width())
		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.position = center_pos + Vector2(6, 8)
		shadow.scale = Vector2(ore_scale * 1.1, ore_scale * 0.4)
		shadow.modulate = Color(0, 0, 0, 0.35)
		g.add_child(shadow)
		g.shadow_sprites.append(shadow)
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.position = center_pos
		sprite.scale = Vector2(ore_scale, ore_scale)
		sprite.z_index = int(cell.y) + 1
		g.add_child(sprite)
		var img: Image = _alpha_image(tex)
		var bm := BitMap.new()
		bm.create_from_image_alpha(img)
		var polys := bm.opaque_to_polygons(Rect2(Vector2.ZERO, img.get_size()), 2.0)
		var body_ref: StaticBody2D = null
		if not polys.is_empty():
			var body := StaticBody2D.new()
			body.position = center_pos
			body.set_meta("occupier", "Ore")
			body.set_meta("grid_pos", cell)
			body.set_meta("kind", kind)
			var origin := Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
			for poly: PackedVector2Array in polys:
				var ocp := CollisionPolygon2D.new()
				var scaled := PackedVector2Array()
				for pt: Vector2 in poly:
					scaled.append((pt - origin) * ore_scale)
				ocp.polygon = Geometry2D.convex_hull(scaled)
				body.add_child(ocp)
			g.add_child(body)
			body_ref = body
		g.ore_nodes[cell] = {"sprite": sprite, "shadow": shadow, "body": body_ref, "kind": kind}


# Driftwood piles — 5 tex variants, no random rotation/orientation.
static func restore_driftwood(g: Grid, dw_data: Array) -> void:
	for entry_v: Variant in dw_data:
		var entry: Dictionary = entry_v as Dictionary
		var cell: Vector2 = Vector2(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var tex_idx: int = clamp(int(entry.get("tex", 0)), 0, DRIFTWOOD_TEXTURE_PATHS.size() - 1)
		var tex: Texture2D = load(DRIFTWOOD_TEXTURE_PATHS[tex_idx]) as Texture2D
		if tex == null:
			continue
		var longest := float(max(tex.get_width(), tex.get_height()))
		var s := float(g.cell_size) * 1.5 / longest
		var pos := g.gridToWorld(cell) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.scale = Vector2(s * 1.1, s * 0.55)
		shadow.position = pos + Vector2(14, 16)
		shadow.modulate = Color(0, 0, 0, 0.3)
		g.add_child(shadow)
		g.shadow_sprites.append(shadow)
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2(s, s)
		sprite.position = pos
		sprite.z_index = int(cell.y) + 1
		g.add_child(sprite)
		var dw_body_ref: StaticBody2D = null
		var dw_img: Image = _alpha_image(tex)
		var dw_bm := BitMap.new()
		dw_bm.create_from_image_alpha(dw_img)
		var dw_polys := dw_bm.opaque_to_polygons(Rect2(Vector2.ZERO, dw_img.get_size()), 2.0)
		if not dw_polys.is_empty():
			var dw_body := StaticBody2D.new()
			dw_body.position = pos
			dw_body.set_meta("occupier", "Driftwood")
			dw_body.set_meta("grid_pos", cell)
			var dw_origin := Vector2(dw_img.get_width() * 0.5, dw_img.get_height() * 0.5)
			for poly: PackedVector2Array in dw_polys:
				var dcp := CollisionPolygon2D.new()
				var scaled := PackedVector2Array()
				for pt: Vector2 in poly:
					scaled.append((pt - dw_origin) * s)
				dcp.polygon = Geometry2D.convex_hull(scaled)
				dw_body.add_child(dcp)
			g.add_child(dw_body)
			dw_body_ref = dw_body
		g.grid[cell].occupier = "Driftwood"
		g.grid[cell].navigable = false
		g.driftwood_nodes[cell] = {"sprite": sprite, "shadow": shadow, "body": dw_body_ref}


# Monolith — single 2x2 unique structure.
static func restore_monolith(g: Grid, pos: Vector2) -> void:
	var tex := load("res://art/environment/sand monolith realistic.png") as Texture2D
	if tex == null:
		return
	const TILES := 2
	for dx in TILES:
		for dy in TILES:
			var c := pos + Vector2(dx, dy)
			if g.grid.has(c):
				g.grid[c].occupier = "Monolith"
				g.grid[c].navigable = false
	g.monolith_pos = pos
	var centre_world := g.gridToWorld(pos) + Vector2(g.cell_size * TILES * 0.5, g.cell_size * TILES * 0.5)
	var s := float(TILES * g.cell_size) / float(tex.get_width())
	var shadow := Sprite2D.new()
	shadow.texture = tex
	shadow.scale = Vector2(s * 1.1, s * 0.5)
	shadow.position = centre_world + Vector2(20, 28)
	shadow.modulate = Color(0, 0, 0, 0.35)
	g.add_child(shadow)
	g.shadow_sprites.append(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(s, s)
	sprite.position = centre_world
	sprite.z_index = int(pos.y) + TILES
	g.add_child(sprite)
	var mono_img: Image = _alpha_image(tex)
	var mono_bm := BitMap.new()
	mono_bm.create_from_image_alpha(mono_img)
	var mono_polys := mono_bm.opaque_to_polygons(Rect2(Vector2.ZERO, mono_img.get_size()), 2.0)
	if not mono_polys.is_empty():
		var mono_body := StaticBody2D.new()
		mono_body.position = centre_world
		var mono_origin := Vector2(mono_img.get_width() * 0.5, mono_img.get_height() * 0.5)
		for poly: PackedVector2Array in mono_polys:
			var mcp := CollisionPolygon2D.new()
			var scaled := PackedVector2Array()
			for pt: Vector2 in poly:
				scaled.append((pt - mono_origin) * s)
			mcp.polygon = Geometry2D.convex_hull(scaled)
			mono_body.add_child(mcp)
		mono_body.set_meta("occupier", "Monolith")
		g.add_child(mono_body)
	var glow_tex := _make_light_texture()
	var glow := Sprite2D.new()
	glow.texture = glow_tex
	glow.modulate = Color(0.5, 0.1, 1.0, 0.25)
	var glow_size := float(g.cell_size * 3)
	glow.scale = Vector2(glow_size / 256.0, glow_size / 256.0)
	glow.position = centre_world
	glow.z_index = 0
	g.add_child(glow)
	var light := PointLight2D.new()
	light.texture = _make_light_texture()
	light.color = Color(0.55, 0.1, 1.0)
	light.energy = 0.0
	light.texture_scale = 5.0
	sprite.add_child(light)
	g.red_tree_lights.append(light)


# Crash site — ship hull (4x4), hull fragment debris, supply crates with
# inventories. Each list entry maps to a saved Vector2 cell + (for
# crates) the inventory dict at save time.
static func restore_crash_site(g: Grid, ship_pos: Vector2, hulls: Array, crates: Array, ship_inventory: Dictionary) -> void:
	if ship_pos == Vector2(-1, -1):
		return
	const SHIP_TILES := 4
	g.crash_site_pos = ship_pos
	g.ship_inventory = ship_inventory.duplicate(true)
	# Ship body (4x4 footprint, occupier + nav cleared).
	for dx in SHIP_TILES:
		for dy in SHIP_TILES:
			var c := ship_pos + Vector2(dx, dy)
			if g.grid.has(c):
				g.grid[c].occupier = "CrashedShip"
				g.grid[c].navigable = false
	var ship_tex := load("res://art/crash_site/crashed ship.png") as Texture2D
	if ship_tex != null:
		var ship_world := g.gridToWorld(ship_pos) + Vector2(g.cell_size * SHIP_TILES * 0.5, g.cell_size * SHIP_TILES * 0.5)
		var s_scale := float(SHIP_TILES * g.cell_size) / float(ship_tex.get_width())
		var ship_shadow := Sprite2D.new()
		ship_shadow.texture = ship_tex
		ship_shadow.scale = Vector2(s_scale * 1.05, s_scale * 0.4)
		ship_shadow.position = ship_world + Vector2(g.cell_size * 0.4, g.cell_size * 0.7)
		ship_shadow.modulate = Color(0, 0, 0, 0.4)
		g.add_child(ship_shadow)
		g.shadow_sprites.append(ship_shadow)
		var ship_sprite := Sprite2D.new()
		ship_sprite.texture = ship_tex
		ship_sprite.scale = Vector2(s_scale, s_scale)
		ship_sprite.position = ship_world
		ship_sprite.z_index = int(ship_pos.y) + SHIP_TILES
		g.add_child(ship_sprite)
		var ship_img: Image = _alpha_image(ship_tex)
		var ship_bm := BitMap.new()
		ship_bm.create_from_image_alpha(ship_img)
		var ship_polys := ship_bm.opaque_to_polygons(Rect2(Vector2.ZERO, ship_img.get_size()), 2.0)
		if not ship_polys.is_empty():
			var ship_body := StaticBody2D.new()
			ship_body.position = ship_world
			ship_body.set_meta("occupier", "CrashedShip")
			ship_body.set_meta("grid_pos", ship_pos)
			var ship_pts := PackedVector2Array()
			var origin := Vector2(ship_img.get_width() * 0.5, ship_img.get_height() * 0.5)
			for poly: PackedVector2Array in ship_polys:
				for pt: Vector2 in poly:
					ship_pts.append((pt - origin) * s_scale)
			var ship_cp := CollisionPolygon2D.new()
			ship_cp.polygon = Geometry2D.convex_hull(ship_pts)
			ship_body.add_child(ship_cp)
			g.add_child(ship_body)
	# Hull fragments — 1x1 cell debris around the ship.
	var hull_tex := load("res://art/crash_site/crashed ship hull large.png") as Texture2D
	if hull_tex != null:
		var hull_scale := float(g.cell_size) / float(max(hull_tex.get_width(), hull_tex.get_height()))
		for hp_v: Variant in hulls:
			var hp_dict: Dictionary = hp_v as Dictionary
			var hp: Vector2 = Vector2(int(hp_dict.get("x", 0)), int(hp_dict.get("y", 0)))
			if not g.grid.has(hp):
				continue
			g.grid[hp].occupier = "HullFragment"
			g.grid[hp].navigable = false
			var hp_world := g.gridToWorld(hp) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			var hull_shadow := Sprite2D.new()
			hull_shadow.texture = hull_tex
			hull_shadow.scale = Vector2(hull_scale * 1.05, hull_scale * 0.5)
			hull_shadow.position = hp_world + Vector2(8, 10)
			hull_shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(hull_shadow)
			g.shadow_sprites.append(hull_shadow)
			var hull_sprite := Sprite2D.new()
			hull_sprite.texture = hull_tex
			hull_sprite.scale = Vector2(hull_scale, hull_scale)
			hull_sprite.position = hp_world
			hull_sprite.z_index = int(hp.y) + 1
			g.add_child(hull_sprite)
			var hull_img: Image = _alpha_image(hull_tex)
			var hull_bm := BitMap.new()
			hull_bm.create_from_image_alpha(hull_img)
			var hull_polys := hull_bm.opaque_to_polygons(Rect2(Vector2.ZERO, hull_img.get_size()), 2.0)
			if not hull_polys.is_empty():
				var hull_body := StaticBody2D.new()
				hull_body.position = hp_world
				hull_body.set_meta("occupier", "HullFragment")
				hull_body.set_meta("grid_pos", hp)
				var hull_origin := Vector2(hull_img.get_width() * 0.5, hull_img.get_height() * 0.5)
				var all_pts := PackedVector2Array()
				for poly: PackedVector2Array in hull_polys:
					for pt: Vector2 in poly:
						all_pts.append((pt - hull_origin) * hull_scale)
				var hcp := CollisionPolygon2D.new()
				hcp.polygon = Geometry2D.convex_hull(all_pts)
				hull_body.add_child(hcp)
				g.add_child(hull_body)
	# Supply crates — 1x1 cell with stored inventory.
	var crate_tex := load("res://art/crash_site/supply crate.png") as Texture2D
	if crate_tex != null:
		var crate_scale := float(g.cell_size) * 0.7 / float(max(crate_tex.get_width(), crate_tex.get_height()))
		for cp_v: Variant in crates:
			var cp_dict: Dictionary = cp_v as Dictionary
			var cp: Vector2 = Vector2(int(cp_dict.get("x", 0)), int(cp_dict.get("y", 0)))
			if not g.grid.has(cp):
				continue
			g.grid[cp].occupier = "SupplyCrate"
			g.grid[cp].navigable = false
			var cp_world := g.gridToWorld(cp) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			var crate_shadow := Sprite2D.new()
			crate_shadow.texture = crate_tex
			crate_shadow.scale = Vector2(crate_scale * 1.15, crate_scale * 0.5)
			crate_shadow.position = cp_world + Vector2(6, 8)
			crate_shadow.modulate = Color(0, 0, 0, 0.35)
			g.add_child(crate_shadow)
			g.shadow_sprites.append(crate_shadow)
			var crate_sprite := Sprite2D.new()
			crate_sprite.texture = crate_tex
			crate_sprite.scale = Vector2(crate_scale, crate_scale)
			crate_sprite.position = cp_world
			crate_sprite.z_index = int(cp.y) + 1
			g.add_child(crate_sprite)
			var crate_img: Image = _alpha_image(crate_tex)
			var crate_bm := BitMap.new()
			crate_bm.create_from_image_alpha(crate_img)
			var crate_polys := crate_bm.opaque_to_polygons(Rect2(Vector2.ZERO, crate_img.get_size()), 2.0)
			if not crate_polys.is_empty():
				var crate_body := StaticBody2D.new()
				crate_body.position = cp_world
				crate_body.set_meta("occupier", "SupplyCrate")
				crate_body.set_meta("grid_pos", cp)
				var crate_origin := Vector2(crate_img.get_width() * 0.5, crate_img.get_height() * 0.5)
				for poly: PackedVector2Array in crate_polys:
					var cp2 := CollisionPolygon2D.new()
					var scaled := PackedVector2Array()
					for pt: Vector2 in poly:
						scaled.append((pt - crate_origin) * crate_scale)
					cp2.polygon = Geometry2D.convex_hull(scaled)
					crate_body.add_child(cp2)
				g.add_child(crate_body)
			g.crate_inventories[cp] = (cp_dict.get("inv", {}) as Dictionary).duplicate(true)


# Ambient creatures — peacetime crabs/crawlers/stalkers. Saved with
# their position + def_key + current HP. Different from wave creatures
# because they aren't aggressive by default.
static func restore_ambient_creatures(g: Grid, creatures_data: Array) -> void:
	var crab_scene := load("res://scenes/Crab.tscn") as PackedScene
	var light_tex := _make_light_texture()
	var shore_y: int = g.height / 2
	for c_v: Variant in creatures_data:
		var c: Dictionary = c_v as Dictionary
		var def_key: String = String(c.get("def_key", "alien_crab"))
		var def: Dictionary = CreatureDefs.DEFS.get(def_key, {})
		if def.is_empty():
			continue
		var tex_down: Texture2D = load(def.tex_down) as Texture2D
		var tex_side: Texture2D = load(def.tex_side) as Texture2D
		if tex_down == null or tex_side == null:
			continue
		var crab: Crab = crab_scene.instantiate()
		crab.position = Vector2(float(c.get("pos_x", 0.0)), float(c.get("pos_y", 0.0)))
		# Re-apply the wander band stored at save time (or fall back to
		# a sensible default if missing — keeps peacetime crabs from
		# wandering off into the deep land if the save predates the band
		# field).
		crab.shore_y_min = int(c.get("y_min", 0))
		crab.shore_y_max = int(c.get("y_max", shore_y - 1))
		g.add_child(crab)
		g.crabs.append(crab)
		crab.setup(tex_down, tex_side, g, def)
		# Restore HP after setup() (which would otherwise reset hp to
		# the def's max value).
		var saved_hp: int = int(c.get("hp", -1))
		if saved_hp > 0:
			crab.hp = min(saved_hp, crab.max_hp)
			# Trigger a redraw so the HP bar reflects the saved value.
			crab.queue_redraw()
		var light := PointLight2D.new()
		light.texture = light_tex
		light.color = Color(0.2, 0.9, 1.0)
		light.energy = 0.0
		light.texture_scale = 2.5
		light.position = Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		crab.add_child(light)
		g.crab_lights.append(light)
