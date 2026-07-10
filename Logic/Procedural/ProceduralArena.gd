extends Node3D

# Это скрипт, который запускается в реальном времени при телепорте.
# Задел на будущее: смена стилей карты.
@export var theme_style: String = "fantasy" 

const WFCModuleDB = preload("res://Logic/Procedural/WFCModuleDB.gd")
const WFCSolver = preload("res://Logic/Procedural/WFCSolver.gd")

const TILE_SIZE = 2.0
const GRID_W = 15
const GRID_D = 15
const TERRAIN_SIZE = 200.0
const TERRAIN_RES = 128

var _noise: FastNoiseLite

func _ready():
	print("Runtime: Generating Procedural Arena [Theme: " + theme_style + "]...")
	
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.015
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.5

	_add_terrain()
	_add_nature()
	_add_wfc_camp()
	_add_entities()
	
	print("Runtime: Procedural Arena generation complete!")

func _height(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 4.0

func _add_terrain():
	var half = TERRAIN_SIZE / 2.0
	var step = TERRAIN_SIZE / float(TERRAIN_RES)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height_data = []
	for iz in TERRAIN_RES:
		var row = []
		for ix in TERRAIN_RES:
			var x = ix * step - half
			var z = iz * step - half
			var y = _height(x, z)
			row.append(y)
			var uv = Vector2(float(ix) / TERRAIN_RES * 8.0, float(iz) / TERRAIN_RES * 8.0)
			st.set_uv(uv)
			st.add_vertex(Vector3(x, y, z))
		height_data.append(row)

	for iz in TERRAIN_RES - 1:
		for ix in TERRAIN_RES - 1:
			var tl = iz * TERRAIN_RES + ix
			var tr = tl + 1
			var bl = (iz + 1) * TERRAIN_RES + ix
			var br = bl + 1
			st.add_index(tl); st.add_index(tr); st.add_index(bl)
			st.add_index(tr); st.add_index(br); st.add_index(bl)

	st.generate_normals()

	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.35, 0.55, 0.25)
	if theme_style == "cyberpunk":
		mat.albedo_color = Color(0.1, 0.1, 0.2)
	elif theme_style == "desert":
		mat.albedo_color = Color(0.8, 0.7, 0.4)

	var terrain_mesh = st.commit()

	var body = StaticBody3D.new()
	body.name = "Terrain"
	add_child(body)

	var mi = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = terrain_mesh
	mi.material_override = mat
	body.add_child(mi)

	# ИСПРАВЛЕНИЕ КОЛЛИЗИИ: Создаем точную форму на основе сгенерированного меша
	# Теперь игрок будет бегать строго по холмам, и объекты не провалятся под землю!
	var floor_cs = CollisionShape3D.new()
	floor_cs.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(floor_cs)

func _add_nature():
	var half = TERRAIN_SIZE / 2.0 - 10.0

	var tree_mesh = CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 0.6
	tree_mesh.height = 4.0
	var tree_mat = StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.08, 0.50, 0.08) if theme_style != "desert" else Color(0.4, 0.4, 0.1)
	tree_mesh.material = tree_mat

	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.08
	trunk_mesh.bottom_radius = 0.12
	trunk_mesh.height = 1.5
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.20, 0.08)
	trunk_mesh.material = trunk_mat

	var rock_mesh = SphereMesh.new()
	rock_mesh.radius = 0.4
	rock_mesh.height = 0.3
	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.40, 0.35)
	rock_mesh.material = rock_mat

	var rng = RandomNumberGenerator.new()

	_add_scatter_group("Trees", tree_mesh, 200, rng, half, 0.3, 25.0)
	_add_scatter_group("Trunks", trunk_mesh, 200, rng, half, 0.3, 25.0)
	_add_scatter_group("Rocks", rock_mesh, 150, rng, half, 0.6, 20.0)

func _add_scatter_group(group_name: String, mesh: Mesh, count: int, rng: RandomNumberGenerator, half: float, spacing: float, camp_radius: float):
	rng.seed = randi()

	var positions = []
	for i in count * 3:
		var x = rng.randf_range(-half, half)
		var z = rng.randf_range(-half, half)
		if abs(x) < camp_radius and abs(z) < camp_radius:
			continue
		var too_close = false
		for p in positions:
			if (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) < spacing * spacing:
				too_close = true
				break
		if too_close:
			continue
		var y = _height(x, z)
		positions.append(Vector3(x, y, z))
		if positions.size() >= count:
			break

	if positions.is_empty():
		return

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = positions.size()
	mm.mesh = mesh

	for i in positions.size():
		var t = Transform3D.IDENTITY
		t.origin = positions[i]
		t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(0, PI * 2))
		if rng.randf() > 0.5:
			t.basis = t.basis.scaled(Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3)))
		mm.set_instance_transform(i, t)

	var mmi = MultiMeshInstance3D.new()
	mmi.name = group_name
	mmi.multimesh = mm
	add_child(mmi)

func _add_wfc_camp():
	var modules = WFCModuleDB.get_modules()
	var solver = WFCSolver.new(GRID_W, GRID_D, modules)

	var result = solver.collapse()
	if not result.success:
		print("WFC failed, using fallback layout")
		return

	var grid = result.grid
	var camp_root = Node3D.new()
	camp_root.name = "WFC_Camp"
	add_child(camp_root)

	var offset_x = -(GRID_W * TILE_SIZE) / 2.0
	var offset_z = -(GRID_D * TILE_SIZE) / 2.0
	var wall_h = 2.0
	var wall_d = 0.2

	for z in GRID_D:
		for x in GRID_W:
			var mod_idx = grid[z][x]
			var mod = modules[mod_idx]
			var pos_x = x * TILE_SIZE + offset_x
			var pos_z = z * TILE_SIZE + offset_z

			var tile = Node3D.new()
			tile.position = Vector3(pos_x, _height(pos_x + TILE_SIZE/2, pos_z + TILE_SIZE/2), pos_z)
			tile.name = "Tile_%d_%d_%s" % [x, z, mod.id]
			camp_root.add_child(tile)

			var floor_mi = MeshInstance3D.new()
			floor_mi.mesh = BoxMesh.new()
			floor_mi.mesh.size = Vector3(TILE_SIZE, 0.15, TILE_SIZE)
			var floor_mat = StandardMaterial3D.new()
			floor_mat.albedo_color = Color(0.30, 0.28, 0.25)
			floor_mi.mesh.material = floor_mat
			floor_mi.position.y = -0.075
			tile.add_child(floor_mi)

			var s = mod.sockets
			var half = TILE_SIZE / 2.0
			var wall_offsets = [
				{sock=s.N, pos=Vector3(0, wall_h/2, -half), sz=Vector3(TILE_SIZE - wall_d, wall_h, wall_d)},
				{sock=s.S, pos=Vector3(0, wall_h/2, half), sz=Vector3(TILE_SIZE - wall_d, wall_h, wall_d)},
				{sock=s.E, pos=Vector3(half, wall_h/2, 0), sz=Vector3(wall_d, wall_h, TILE_SIZE - wall_d)},
				{sock=s.W, pos=Vector3(-half, wall_h/2, 0), sz=Vector3(wall_d, wall_h, TILE_SIZE - wall_d)},
			]

			for wo in wall_offsets:
				if wo.sock == 1:
					var wmi = MeshInstance3D.new()
					wmi.mesh = BoxMesh.new()
					wmi.mesh.size = wo.sz
					var wmat = StandardMaterial3D.new()
					wmat.albedo_color = mod.color
					wmi.mesh.material = wmat
					wmi.position = wo.pos
					tile.add_child(wmi)

func _add_entities():
	var player_scene = load("res://Scenes/player.tscn")
	if player_scene:
		var player = player_scene.instantiate()
		player.position = Vector3(2, _height(2, 2) + 1.5, 2)
		add_child(player)

	var dummy_scene = load("res://Scenes/dummy.tscn")
	if not dummy_scene: return

	var dummy_positions = [
		Vector3(-4, _height(-4, -4) + 1.5, -4),
		Vector3(6, _height(6, -3) + 1.5, -3),
		Vector3(-3, _height(-3, 5) + 1.5, 5),
		Vector3(-6, _height(-6, -6) + 1.5, -6),
	]

	for i in dummy_positions.size():
		var d = dummy_scene.instantiate()
		d.position = dummy_positions[i]
		if i == 1:
			d.set_script(load("res://Logic/MovingDummy.gd"))
			d.set("move_type", "line")
			d.set("move_speed", 3.0)
		elif i == 2:
			d.set_script(load("res://Logic/MovingDummy.gd"))
			d.set("move_type", "complex_polygon")
			d.set("move_speed", 12.0)
		elif i == 3:
			d.set_script(load("res://Logic/FriendlyDummy.gd"))
			d.set("move_type", "triangle")
			d.set("move_speed", 8.0)
		add_child(d)