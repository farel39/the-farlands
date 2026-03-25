class_name WorldSpawner


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


static func spawn_trees(g: Grid) -> void:
	var tree_texture = load("res://art/environment/alien lily pad tree.png")
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
					break
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

		tree_data.append({pos = pos, local_dirt = local_dirt})

	var dirt_tex := load("res://art/environment/alien dirt.png")
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
		var dirt_scale := float(g.cell_size) / float(dirt_tex.get_width())
		dirt_sprite.scale = Vector2(dirt_scale, dirt_scale)
		if mask < 15 or diag < 15:
			var mat: ShaderMaterial = dirt_base_mat.duplicate()
			mat.set_shader_parameter("cardinal_mask", mask)
			mat.set_shader_parameter("diag_mask", diag)
			mat.set_shader_parameter("fade_width", 0.55)
			dirt_sprite.material = mat
		g.add_child(dirt_sprite)

	var lily_tex := load("res://art/environment/alien lily pad plant.png")

	for td in tree_data:
		var pos: Vector2 = td.pos
		var local_dirt: Dictionary = td.local_dirt

		var centre_pos := g.gridToWorld(pos) + Vector2(g.cell_size * 1.5, g.cell_size * 1.5)
		var tree_s := float(g.cell_size * 3) / float(tree_texture.get_width())

		var shadow := Sprite2D.new()
		shadow.texture = tree_texture
		shadow.position = centre_pos + Vector2(g.cell_size * 0.15, g.cell_size * 0.7)
		shadow.scale = Vector2(tree_s * 1.1, tree_s * 0.22)
		shadow.modulate = Color(0, 0, 0, 0.35)
		shadow.z_index = -1
		g.add_child(shadow)
		g.shadow_sprites.append(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = tree_texture
		sprite.position = centre_pos
		sprite.scale = Vector2(tree_s, tree_s)
		g.add_child(sprite)

		var light := PointLight2D.new()
		light.texture = light_texture
		light.color = Color(0.3, 1.0, 0.7)
		light.energy = 0.0
		light.texture_scale = 4.5
		sprite.add_child(light)
		g.tree_lights.append(light)

		g.tree_sprites[pos] = sprite

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
			lily.z_index = 0
			g.add_child(lily)
			var lily_light := PointLight2D.new()
			lily_light.texture = light_texture
			lily_light.color = Color(0.3, 1.0, 0.7)
			lily_light.energy = 0.0
			lily_light.texture_scale = 4.5
			lily.add_child(lily_light)
			g.tree_lights.append(lily_light)
			g.grid[lc].occupier = "LilyPad"
			lily_placed += 1


static func spawn_red_trees(g: Grid) -> void:
	const TREE_W     := 3
	const TREE_H     := 3
	const MAX_TREES  := 3
	const MIN_DIST        := 12
	const MIN_DIST_BLUE   := 25
	const DIRT_RADIUS := 7.0
	const SAP_RADIUS := 5.0

	var tree_tex := load("res://art/environment/red alien tree.png")
	var sap_textures: Array = [
		load("res://art/environment/red alien tree sampling 1.png"),
		load("res://art/environment/red alien tree sampling 2.png"),
		load("res://art/environment/red alien tree sampling 3.png"),
	]
	var light_texture := _make_light_texture()
	var dirt_tex      := load("res://art/environment/alien dirt.png")
	var dirt_base_mat := load("res://data/materials/dirt_round.tres") as ShaderMaterial

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = g.height / 2

	var candidates: Array = []
	for x in range(0, g.width - TREE_W):
		for y in range(0, shore_y - TREE_W):
			candidates.append(Vector2(x, y))
	candidates.shuffle()

	var placed: Array = []
	var tree_data: Array = []

	var blue_roots: Dictionary = {}
	for root in g.tree_root.values():
		blue_roots[root] = true
	var blue_positions: Array = blue_roots.keys()

	for pos in candidates:
		if tree_data.size() >= MAX_TREES:
			break
		if pos.distance_to(Vector2(0, 0)) < 5:
			continue
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < MIN_DIST:
				too_close = true
				break
		if too_close:
			continue
		for bp in blue_positions:
			if pos.distance_to(bp) < MIN_DIST_BLUE:
				too_close = true
				break
		if too_close:
			continue

		var can_place := true
		for dx in TREE_W:
			for dy in TREE_H:
				var c: Vector2 = pos + Vector2(dx, dy)
				if not g.grid.has(c) or g.grid[c].occupier != null or g.water_tiles.has(c):
					can_place = false
					break
			if not can_place:
				break
		if not can_place:
			continue

		placed.append(pos)

		var centre: Vector2 = pos + Vector2(1, 1)
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

		for dx in TREE_W:
			for dy in TREE_H:
				var c: Vector2 = pos + Vector2(dx, dy)
				g.grid[c].occupier = "RedTree"
				g.grid[c].navigable = false
				g.tree_root[c] = pos

		tree_data.append({pos = pos, local_dirt = local_dirt})

	for td in tree_data:
		var local_dirt: Dictionary = td.local_dirt
		for c in local_dirt:
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
			var ds := float(g.cell_size) / float(dirt_tex.get_width())
			dirt_sprite.scale = Vector2(ds, ds)
			if mask < 15 or diag < 15:
				var mat: ShaderMaterial = dirt_base_mat.duplicate()
				mat.set_shader_parameter("cardinal_mask", mask)
				mat.set_shader_parameter("diag_mask", diag)
				mat.set_shader_parameter("fade_width", 0.55)
				dirt_sprite.material = mat
			g.add_child(dirt_sprite)

	for td in tree_data:
		var pos: Vector2 = td.pos
		var local_dirt: Dictionary = td.local_dirt
		var centre: Vector2 = pos + Vector2(1, 1)

		var s := float(TREE_W * g.cell_size) / float(tree_tex.get_width())
		var sprite := Sprite2D.new()
		sprite.texture = tree_tex
		sprite.scale = Vector2(s, s)
		sprite.position = g.gridToWorld(pos) + Vector2(g.cell_size * 1.5, g.cell_size * 1.5)
		g.add_child(sprite)

		var light := PointLight2D.new()
		light.texture = light_texture
		light.color = Color(1.0, 0.35, 0.2)
		light.energy = 0.0
		light.texture_scale = 12.0
		sprite.add_child(light)
		g.red_tree_lights.append(light)

		g.tree_sprites[pos] = sprite

		var sap_candidates: Array = []
		for c in local_dirt.keys():
			if c.distance_to(centre) <= SAP_RADIUS and g.grid.has(c) and g.grid[c].occupier == null:
				sap_candidates.append(c)
		sap_candidates.shuffle()
		var sap_count := rng.randi_range(3, 6)
		var sap_placed := 0
		for sc in sap_candidates:
			if sap_placed >= sap_count:
				break
			if not g.grid.has(sc) or g.grid[sc].occupier != null:
				continue
			var sap_tex: Texture2D = sap_textures[rng.randi() % 3]
			var sap_s := float(g.cell_size) / float(sap_tex.get_width())
			var sap := Sprite2D.new()
			sap.texture = sap_tex
			sap.position = g.gridToWorld(sc) + Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
			sap.scale = Vector2(sap_s, sap_s)
			g.add_child(sap)
			var sap_light := PointLight2D.new()
			sap_light.texture = light_texture
			sap_light.color = Color(1.0, 0.35, 0.2)
			sap_light.energy = 0.0
			sap_light.texture_scale = 5.0
			sap.add_child(sap_light)
			g.red_tree_lights.append(sap_light)
			g.grid[sc].occupier = "RedTreeSapling"
			sap_placed += 1


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
		for dx in SHIP_TILES:
			for dy in SHIP_TILES:
				if (dx == 0 and dy == 0) or (dx == SHIP_TILES - 1 and dy == SHIP_TILES - 1):
					continue
				var c := ship_pos + Vector2(dx, dy)
				g.grid[c].occupier = "CrashedShip"
				g.grid[c].navigable = false

		var sp := g.gridToWorld(ship_pos) + Vector2(g.cell_size * SHIP_TILES * 0.5, g.cell_size * SHIP_TILES * 0.5)
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
		g.add_child(ship_sprite)

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
			g.add_child(hull_sprite)

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
				["Ammo", rng.randi_range(3, 6)],
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
			g.add_child(crate_sprite)

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
		g.add_child(sprite)

		g.grid[cell].occupier = "Driftwood"
		g.grid[cell].navigable = false
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
			sprite.z_index = 1
			g.add_child(sprite)

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
	var rock_tex   = load("res://art/environment/tide pool rock.png")
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
			var light := PointLight2D.new()
			light.texture = light_tex
			light.color = Color(0.1, 0.85, 1.0)
			light.energy = 0.0
			light.texture_scale = 5.5
			pool_sprite.add_child(light)
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
			var ore_tex: Texture2D = iron_tex if used_ore_cells.size() <= ore_count else copper_tex
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
			g.add_child(ore_sprite)


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
	sprite.z_index = 1
	g.add_child(sprite)

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


static func spawn_crabs(g: Grid) -> void:
	var tex_down := load("res://art/characters/alien beach crab downward.png") as Texture2D
	var tex_side := load("res://art/characters/alien beach crab sideway left.png") as Texture2D
	var crab_scene := load("res://scenes/Crab.tscn") as PackedScene

	const COUNT := 10
	const SHORE_BAND := 8

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var shore_y: int = g.height / 2

	var candidates: Array = []
	for x in g.width:
		for y in range(shore_y - SHORE_BAND, shore_y):
			var c := Vector2(x, y)
			if g.grid.has(c) and not g.water_tiles.has(c) and not g.dirt_tiles.has(c) and g.grid[c].occupier == null:
				candidates.append(c)
	candidates.shuffle()

	var light_tex := _make_light_texture()

	var spawned := 0
	for cell in candidates:
		if spawned >= COUNT:
			break
		var crab: Crab = crab_scene.instantiate()
		crab.position = g.gridToWorld(cell)
		crab.shore_y_min = shore_y - SHORE_BAND - 2
		crab.shore_y_max = shore_y - 1
		g.add_child(crab)
		crab.setup(tex_down, tex_side, g)

		var light := PointLight2D.new()
		light.texture = light_tex
		light.color = Color(0.2, 0.9, 1.0)
		light.energy = 0.0
		light.texture_scale = 2.5
		light.position = Vector2(g.cell_size * 0.5, g.cell_size * 0.5)
		crab.add_child(light)
		g.crab_lights.append(light)

		spawned += 1
