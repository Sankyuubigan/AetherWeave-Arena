extends SceneTree
## Генератор куклы-трупа для рэгдолл-смерти манекенов (PhysicalBones3D).
## Структура по паттерну демо 3d/ragdoll_physics (Godot 4.8):
##   RagdollDummy (Node3D, RagdollCorpse.gd)
##   └ Skeleton3D — 13 костей (rest = поза стоя, Т-руки)
##     └ PhysicalBoneSimulator3D — 13 × PhysicalBone3D
##       joint_type = 2 (ConeTwist) на дочерних костях — отдельные Joint3D не нужны.
##   Конечности — капсулы детьми PB (без скиннинга: PB ведёт кость, меш едет с ней).
## Слои PB: layer 0 / mask 1 (мир); масса тела ~48.5 кг.
## Запуск: engine --headless -s res://Generators/build_ragdoll_dummy.gd

## [имя, родитель, pivot, r, h, смещение капсулы от pivot (в мировых осях), масса, euler-поворот °]
const BONES := [
	["Pelvis", "", Vector3(0, 1.02, 0), 0.14, 0.32, Vector3.ZERO, 9.0, Vector3.ZERO],
	["Chest", "Pelvis", Vector3(0, 1.22, 0), 0.13, 0.38, Vector3(0, 0.21, 0), 9.0, Vector3.ZERO],
	["Head", "Chest", Vector3(0, 1.62, 0), 0.11, 0.26, Vector3(0, 0.16, 0), 4.5, Vector3.ZERO],
	["ArmL", "Chest", Vector3(-0.16, 1.56, 0), 0.06, 0.26, Vector3(-0.10, 0, 0), 2.5, Vector3(0, 0, 90)],
	["ArmR", "Chest", Vector3(0.16, 1.56, 0), 0.06, 0.26, Vector3(0.10, 0, 0), 2.5, Vector3(0, 0, -90)],
	["ForeArmL", "ArmL", Vector3(-0.39, 1.56, 0), 0.05, 0.24, Vector3(-0.11, 0, 0), 2.0, Vector3(0, 0, 90)],
	["ForeArmR", "ArmR", Vector3(0.39, 1.56, 0), 0.05, 0.24, Vector3(0.11, 0, 0), 2.0, Vector3(0, 0, -90)],
	["ThighL", "Pelvis", Vector3(-0.11, 0.92, 0), 0.08, 0.40, Vector3(0, -0.21, 0), 4.0, Vector3.ZERO],
	["ThighR", "Pelvis", Vector3(0.11, 0.92, 0), 0.08, 0.40, Vector3(0, -0.21, 0), 4.0, Vector3.ZERO],
	["CalfL", "ThighL", Vector3(-0.11, 0.51, 0), 0.06, 0.38, Vector3(0, -0.20, 0), 3.0, Vector3.ZERO],
	["CalfR", "ThighR", Vector3(0.11, 0.51, 0), 0.06, 0.38, Vector3(0, -0.20, 0), 3.0, Vector3.ZERO],
	["FootL", "CalfL", Vector3(-0.11, 0.13, 0), 0.05, 0.20, Vector3(0, -0.06, 0.06), 1.5, Vector3(-90, 0, 0)],
	["FootR", "CalfR", Vector3(0.11, 0.13, 0), 0.05, 0.20, Vector3(0, -0.06, 0.06), 1.5, Vector3(-90, 0, 0)],
]
const JOINT_TYPE_CONE_TWIST := 2

func _init() -> void:
	var root := Node3D.new()
	root.name = "RagdollDummy"
	root.set_script(load("res://Graphics/RagdollCorpse.gd"))

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0)
	mat.roughness = 0.8

	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "PhysicalBoneSimulator3D"
	skel.add_child(sim)

	var idx := {}
	for b in BONES:
		var b_name: String = b[0]
		var parent_name: String = b[1]
		var pivot: Vector3 = b[2]
		var cap_r: float = b[3]
		var cap_h: float = b[4]
		var cap_off: Vector3 = b[5]
		var mass: float = b[6]
		var basis := Basis.from_euler((b[7] as Vector3) * TAU / 360.0)

		skel.add_bone(b_name)
		var bi := skel.find_bone(b_name)
		idx[b_name] = bi
		if parent_name != "":
			skel.set_bone_parent(bi, idx[parent_name])
		skel.set_bone_rest(bi, Transform3D(basis, pivot))

		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + b_name
		pb.bone_name = b_name
		pb.joint_type = JOINT_TYPE_CONE_TWIST if parent_name != "" else 0
		pb.mass = mass
		pb.collision_layer = 0
		pb.collision_mask = 1
		pb.friction = 0.7
		pb.transform = Transform3D(basis, pivot)
		sim.add_child(pb)

		var cs := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = cap_r
		shape.height = cap_h
		cs.shape = shape
		cs.position = basis.inverse() * cap_off
		pb.add_child(cs)

		var mi := MeshInstance3D.new()
		var cap_mesh := CapsuleMesh.new()
		cap_mesh.radius = cap_r
		cap_mesh.height = cap_h
		cap_mesh.material = mat
		mi.mesh = cap_mesh
		mi.position = cs.position
		pb.add_child(mi)

	# owner для сохранения в .tscn
	_set_owner(root, root)

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://Scenes/ragdoll_dummy.tscn")
	print("ragdoll_dummy.tscn saved, err=%d, bones=%d" % [err, BONES.size()])
	root.free() # без этого — RID-утечки тел/джойнтов при выходе генератора
	quit()

func _set_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for c in node.get_children():
		_set_owner(c, owner_node)
